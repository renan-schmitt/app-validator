---
name: checklist-publicacao-play-store
description: Valida todas as etapas necessárias para publicar um app Android na Google Play Store — configuração de build, assinatura, target SDK, permissões, políticas, Data safety, ficha da loja, testes obrigatórios e envio no Play Console. Use para "publicar na play store", "checklist de publicação", "app está pronto para a loja?", "por que o app foi rejeitado".
---

# Checklist de publicação na Google Play Store

Valide cada etapa abaixo e marque como ✅ (verificado OK), ❌ (falha — com evidência), ⚠️ (risco) ou ❓ (não verificável pelo código — o usuário precisa confirmar no Play Console).

> **Requisitos da Google mudam com frequência** (principalmente target SDK e políticas). Se houver acesso à web, confirme os valores atuais em https://developer.android.com/google/play/requirements/target-sdk e https://support.google.com/googleplay/android-developer antes de reprovar algo por versão.

Comece rodando a verificação automática:
```bash
bash .claude/skills/checklist-publicacao-play-store/scripts/check_build.sh <caminho-do-projeto>
```
Depois revise manualmente cada etapa.

---

## Etapa 1 — Conta de desenvolvedor (❓ confirmar com o usuário)
- [ ] Conta no Play Console criada (taxa única de US$ 25) e **identidade verificada**.
- [ ] Tipo de conta: **pessoal** ou **organização** (organização exige D-U-N-S).
- [ ] **Contas pessoais criadas após nov/2023**: obrigatório **teste fechado com pelo menos 12 testadores ativos por 14 dias contínuos** antes de solicitar acesso à produção.
- [ ] Perfil de pagamentos configurado (se o app for pago ou tiver compras no app).

## Etapa 2 — Identidade do app
- [ ] `applicationId` definitivo (não pode ser alterado após publicar; não usar `com.example`).
- [ ] `versionCode` inteiro e maior que qualquer versão já enviada; `versionName` legível.
- [ ] Nome do app (≤ 30 caracteres) e ícone adaptativo (`mipmap-anydpi-v26/ic_launcher.xml`).

## Etapa 3 — Configuração de build
- [ ] **targetSdk** atende ao mínimo exigido (apps novos e atualizações: API 35 desde 31/08/2025; a Google costuma elevar para a versão seguinte — API 36 — em agosto do ano corrente. Confirme o valor vigente).
- [ ] `compileSdk` ≥ `targetSdk`.
- [ ] `minSdk` coerente com o público.
- [ ] Formato **Android App Bundle (.aab)** — APK não é aceito para apps novos.
- [ ] Build `release` com `isMinifyEnabled = true` / `isShrinkResources = true` (recomendado) e regras ProGuard/R8 testadas.
- [ ] `android:debuggable` **não** definido como `true` no release.
- [ ] Sem `android:usesCleartextTraffic="true"` sem justificativa; `network_security_config` revisado.
- [ ] **Suporte a páginas de memória de 16 KB** para apps com código nativo (`.so`) que miram Android 15+: NDK r28+ ou bibliotecas alinhadas a 16 KB, AGP ≥ 8.5.1. Verificar com `zipalign -c -P 16 -v 4 app.apk` ou o APK Analyzer.
- [ ] Sem bibliotecas de terceiros com versões bloqueadas pelo Play SDK Index.
- [ ] Mapping file (R8) e símbolos nativos prontos para upload (para desofuscar crashes).

## Etapa 4 — Assinatura
- [ ] **Play App Signing** ativado (padrão para apps novos).
- [ ] Chave de upload (`upload-keystore.jks`) gerada, com backup seguro, **fora do repositório**.
- [ ] `signingConfigs` lê senhas de variáveis de ambiente/`keystore.properties` não versionado (verifique `.gitignore`).

## Etapa 5 — Permissões e APIs sensíveis
- [ ] Cada `<uses-permission>` no `AndroidManifest.xml` (incluindo as de bibliotecas — ver manifest mesclado em `build/intermediates/merged_manifests/`) é realmente usada.
- [ ] Permissões que exigem **declaração no Play Console** têm justificativa e vídeo de demonstração se necessário:
  - `ACCESS_BACKGROUND_LOCATION`
  - `READ_SMS`, `RECEIVE_SMS`, `READ_CALL_LOG` e afins (só para apps com função principal de SMS/telefone)
  - `MANAGE_EXTERNAL_STORAGE` (All files access)
  - `QUERY_ALL_PACKAGES`
  - `REQUEST_INSTALL_PACKAGES`
  - `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` (preferir Photo Picker se o uso não for central)
  - `USE_EXACT_ALARM` / `SCHEDULE_EXACT_ALARM`
  - `FOREGROUND_SERVICE_*` (Android 14+ exige tipo do serviço declarado e justificativa no Console)
  - `BIND_ACCESSIBILITY_SERVICE`
- [ ] Permissões em runtime solicitadas no contexto de uso, com tratamento de recusa.

## Etapa 6 — Privacidade e políticas
- [ ] **Política de privacidade** publicada em URL pública (não PDF, não geo-bloqueada) e acessível também dentro do app.
- [ ] **Formulário Data safety** preenchido de forma consistente com o que o app **e seus SDKs** (Firebase, Analytics, Ads, Crashlytics, Facebook SDK…) coletam e compartilham. Liste os SDKs do `build.gradle` para o usuário conferir.
- [ ] **Exclusão de conta**: se o app permite criar conta, deve oferecer exclusão dentro do app **e** via link web informado no Console.
- [ ] **Classificação de conteúdo** (questionário IARC) respondida.
- [ ] **Público-alvo e conteúdo**: faixa etária declarada; se inclui crianças, cumprir Families Policy (SDKs certificados para famílias).
- [ ] Declaração de **anúncios** (contém anúncios? sim/não) coerente com SDKs de ads no código.
- [ ] Declarações específicas quando aplicável: app de notícias, saúde, governo, financeiro/empréstimo, VPN, ID de publicidade (`AD_ID` — Android 13+ exige a permissão `com.google.android.gms.permission.AD_ID` se usar o ID).
- [ ] Compras digitais usam **Google Play Billing** (salvo exceções permitidas).
- [ ] Sem conteúdo/funcionalidade que viole políticas (marca de terceiros, conteúdo enganoso, coleta oculta de dados).

## Etapa 7 — Qualidade técnica (pré-lançamento)
- [ ] Sem crashes nem ANRs nos fluxos principais (rodar também a skill `validar-fluxos-funcionalidades`).
- [ ] Funciona sem internet / com rede lenta sem travar.
- [ ] Testado nas versões mínima e alvo do Android e em telas pequenas/grandes; suporte a edge-to-edge (obrigatório ao mirar API 35+).
- [ ] Botão voltar / predictive back funcionando.
- [ ] Credenciais de teste disponíveis para o revisor da Google se o app tiver login (informar em "Acesso ao app" no Console).
- [ ] Relatório de pré-lançamento do Play Console sem problemas críticos.

## Etapa 8 — Ficha da loja (Store listing) (❓ confirmar)
- [ ] Título (≤ 30), descrição curta (≤ 80), descrição completa (≤ 4000) — sem keyword stuffing nem menção a outros apps/rankings.
- [ ] Ícone 512×512 PNG 32-bit (≤ 1 MB).
- [ ] Feature graphic 1024×500 JPG/PNG.
- [ ] Mínimo de 2 screenshots de telefone (proporção entre 16:9 e 9:16, lado entre 320 e 3840 px); screenshots de tablet se suportar tablets.
- [ ] Categoria, e-mail de contato e (opcional) site.
- [ ] Traduções das fichas para os mercados-alvo.

## Etapa 9 — Lançamento
1. Criar app no Play Console → preencher **Configurar app** (todas as tarefas do painel).
2. Enviar `.aab` para **Teste interno** → validar instalação pela Play Store.
3. **Teste fechado** (obrigatório para contas pessoais novas: 12 testadores × 14 dias) → corrigir feedback.
4. Solicitar acesso à **Produção** (contas pessoais novas) e responder o questionário.
5. Selecionar países/regiões e preço.
6. Lançamento em produção — preferir **lançamento gradual** (ex. 10% → 50% → 100%) acompanhando o Android Vitals.
7. Revisão da Google: normalmente de algumas horas a ~7 dias (mais para contas novas).

---

## Relatório
Entregue uma tabela por etapa (`Item | Status | Evidência | Ação necessária`), seguida de:
- **Bloqueadores** (❌) — impedem envio ou causam rejeição.
- **Riscos** (⚠️) — podem gerar rejeição ou suspensão.
- **Pendências do usuário** (❓) — o que precisa ser feito/confirmado no Play Console, em ordem.
