---
name: validar-fluxos-funcionalidades
description: Valida funcionalidades de um app Android quando o usuário navega entre várias funcionalidades abandonando outras no meio. Detecta threads, coroutines, streams, timers e requisições inacabadas/órfãs, callbacks em telas destruídas, vazamentos de memória e crashes de ciclo de vida. Use para "validar funcionalidades", "threads inacabadas", "vazamento ao trocar de tela", "testar abandono de fluxo".
---

# Validação de fluxos com abandono de funcionalidades

Objetivo: provar (ou refutar) que, quando o usuário entra em uma funcionalidade, dispara trabalho assíncrono e sai antes de terminar — indo para outra, e outra — **nenhum trabalho fica rodando sem dono**, nada é entregue a uma tela destruída e o consumo de recursos volta ao normal.

Execute as três fases em ordem. A fase 2 depende de dispositivo/emulador; se não houver, registre isso no relatório.

---

## Fase 1 — Mapear funcionalidades e trabalho assíncrono

1. Liste as funcionalidades (telas/rotas): `Activity`, `Fragment`, destinos do Navigation, `@Composable` de tela, rotas Flutter (`GoRoute`, `Navigator.push`), telas React Navigation.
2. Para cada funcionalidade, liste o trabalho assíncrono que ela inicia e **quem é o dono** (escopo que cancela o trabalho).
3. Monte uma tabela: `Funcionalidade | Trabalho iniciado | Dono/escopo | Cancelado em | OK?`

## Fase 1b — Análise estática (padrões de risco)

Use `Grep` para procurar os padrões abaixo. Para cada ocorrência, abra o arquivo e confirme se o trabalho é cancelado quando a tela sai.

### Kotlin / Coroutines
| Padrão | Risco | Correto |
|---|---|---|
| `GlobalScope.launch` / `GlobalScope.async` | Nunca é cancelado | `viewModelScope` / `lifecycleScope` |
| `CoroutineScope(Dispatchers.*)` criado manualmente | Órfão se não houver `cancel()` | Cancelar em `onCleared`/`onDestroy` ou usar escopo de lifecycle |
| `lifecycleScope.launch` coletando Flow na UI | Continua coletando em background | `repeatOnLifecycle(Lifecycle.State.STARTED)` / `collectAsStateWithLifecycle()` |
| `runBlocking` na main thread | ANR | `suspend` + dispatcher |
| `withContext(NonCancellable)` | Ignora cancelamento | Só para cleanup curto |
| Loop `while(true)` sem `isActive`/`ensureActive()` | Não responde a cancelamento | Checar `isActive` |
| `catch (e: Exception)` engolindo `CancellationException` | Quebra cancelamento | Relançar `CancellationException` |
| `LaunchedEffect(Unit)` disparando trabalho fora do escopo do composable | Órfão | Usar escopo do efeito / `DisposableEffect` |

### Java / Android clássico
| Padrão | Risco |
|---|---|
| `new Thread(` / `Thread {` | Sem cancelamento; segura referência à Activity |
| `Executors.new*` / `ExecutorService` sem `shutdown()` | Threads do pool vivem para sempre |
| `AsyncTask` | Deprecated; vaza Activity; resultado entregue em tela destruída |
| `Handler.postDelayed` sem `removeCallbacksAndMessages(null)` | Runnable roda após sair da tela |
| `Timer` / `TimerTask` / `CountDownTimer` sem `cancel()` | Continua disparando |
| `registerReceiver` / `addListener` / `LocationManager.requestLocationUpdates` sem par de remoção | Vazamento + bateria |
| Callbacks Retrofit `enqueue` sem `call.cancel()` | Callback em tela destruída |
| Classe interna não-estática/lambda capturando `Activity`/`Context`/`View` em trabalho longo | Memory leak |

### RxJava
- `subscribe(` sem guardar `Disposable` / sem `CompositeDisposable.clear()` em `onDestroy`/`onCleared`.

### Flutter / Dart
- `StreamSubscription` sem `cancel()` em `dispose()`.
- `Timer` / `Timer.periodic` sem `cancel()`.
- `AnimationController`, `TextEditingController`, `ScrollController` sem `dispose()`.
- `setState` após `await` sem checar `if (!mounted) return;` (erro "setState() called after dispose()").
- `Isolate.spawn` sem `kill`.

### React Native / JS
- `useEffect` que cria `setInterval`/`setTimeout`/listener/subscription **sem função de cleanup**.
- `fetch` sem `AbortController` abortado no cleanup.
- `setState` após unmount.

Comandos úteis (ajuste ao projeto):

```bash
rg -n "GlobalScope|CoroutineScope\(|runBlocking|NonCancellable" --type kotlin
rg -n "new Thread\(|Thread \{|Executors\.new|AsyncTask|postDelayed|Timer\(|CountDownTimer" -g '*.{kt,java}'
rg -n "registerReceiver|requestLocationUpdates|addListener" -g '*.{kt,java}'
rg -n "\.subscribe\(" -g '*.{kt,java}'
rg -n "StreamSubscription|Timer\.periodic|Timer\(|setState\(" -g '*.dart'
rg -n "setInterval|setTimeout|addEventListener|subscribe\(" -g '*.{js,jsx,ts,tsx}'
```

Para cada achado, confirme se existe o par de cancelamento correspondente no mesmo componente (`onDestroy`, `onCleared`, `onStop`, `dispose`, cleanup do `useEffect`). **Ocorrência sem par = achado.**

---

## Fase 2 — Teste dinâmico (dispositivo/emulador)

Pré-requisitos: `adb devices` mostra um dispositivo, app instalado em build **debug** (de preferência com LeakCanary e StrictMode habilitados).

### 2.1 Linha de base
```bash
bash .claude/skills/validar-fluxos-funcionalidades/scripts/monitor_threads.sh <package.name> 60 2
```
O script grava em CSV: número de threads, memória (PSS) e nomes das threads a cada intervalo. Rode com o app parado na tela inicial para obter a linha de base.

### 2.2 Cenários de abandono
Enquanto o monitor roda, execute cada cenário (manualmente, via `adb shell input`, Espresso/UI Automator, Maestro ou Appium — use o que o projeto já tiver):

1. **Abandono simples**: entrar na funcionalidade A, disparar a ação que carrega dados (lista, upload, busca), voltar imediatamente (`adb shell input keyevent KEYCODE_BACK`).
2. **Salto em cadeia**: A → (antes de carregar) B → (antes de carregar) C → D… sem esperar nenhuma terminar. Repetir 10x.
3. **Toques rápidos/duplos**: tocar duas vezes no mesmo botão que inicia trabalho (detecta trabalho duplicado).
4. **Background no meio**: iniciar ação e ir para home (`KEYCODE_HOME`), voltar após 30s.
5. **Rotação/recriação**: iniciar ação e rotacionar (`adb shell settings put system user_rotation 1`) — verifica se o trabalho é duplicado a cada recriação.
6. **Morte de processo**: `adb shell am kill <package>` com app em background e reabrir — verifica restauração de estado.
7. **Monkey** (estresse aleatório):
   ```bash
   adb shell monkey -p <package> --throttle 100 --pct-touch 60 --pct-nav 20 --pct-majornav 15 -v 2000
   ```

Após cada cenário, volte para a tela inicial, aguarde ~10s, force GC (`adb shell am send-trim-memory <package> RUNNING_LOW` ou via Android Studio) e anote o estado.

### 2.3 Critérios de reprovação
- **Contagem de threads não volta à linha de base** (tolerância: ±2) após os cenários → threads órfãs. Use os nomes das threads no CSV para achar a origem (`DefaultDispatcher-worker-*`, `pool-N-thread-M`, `OkHttp …`, `Thread-N`).
- **Crescimento contínuo** de threads ou PSS a cada repetição do cenário 2 → vazamento.
- **Logcat** com qualquer um destes:
  ```bash
  adb logcat -d | grep -E "FATAL EXCEPTION|ANR in|StrictMode|LeakCanary|IllegalStateException|setState\(\) called after dispose|Can't perform a React state update|Fragment .* not attached"
  ```
- Requisições de rede continuando após sair da tela (ver logcat do OkHttp/interceptor ou Network Inspector).
- Trabalho executado em duplicidade (cenários 3 e 5).

### 2.4 Inspeção detalhada (quando houver suspeita)
```bash
adb shell ps -T -p $(adb shell pidof <package>)           # threads com nome
adb shell dumpsys meminfo <package>                        # Activities/Views vivas
adb shell am dumpheap <package> /data/local/tmp/heap.hprof # heap dump para análise
```
Em `dumpsys meminfo`, a seção **Objects → Activities** deve voltar a 1 (ou ao número de telas realmente abertas). Mais que isso = Activity vazada.

---

## Fase 3 — Relatório

Para cada achado, registre:

- **Severidade**: Crítico (crash/ANR) · Alto (thread/coroutine órfã, vazamento de Activity) · Médio (trabalho duplicado, bateria/rede) · Baixo.
- **Funcionalidade e cenário** que reproduz.
- **Evidência**: `arquivo:linha` e/ou trecho do CSV/logcat.
- **Causa**: qual trabalho não tem dono/cancelamento.
- **Correção sugerida** com código (ex. trocar `GlobalScope` por `viewModelScope`, adicionar `repeatOnLifecycle`, cancelar `Disposable` em `onCleared`, `if (!mounted) return;`).

Inclua a tabela da Fase 1 com a coluna `OK?` preenchida e um gráfico/tabela da contagem de threads ao longo dos cenários.
