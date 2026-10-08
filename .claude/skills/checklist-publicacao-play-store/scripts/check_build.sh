#!/usr/bin/env bash
# Verificação automática de itens de publicação na Play Store a partir do código-fonte.
# Uso: check_build.sh [caminho_do_projeto=.]
set -uo pipefail

ROOT="${1:-.}"
cd "$ROOT" || { echo "Diretório inválido: $ROOT" >&2; exit 1; }

ok()   { echo "✅ $*"; }
fail() { echo "❌ $*"; }
warn() { echo "⚠️  $*"; }

# Localiza o módulo app (nativo Android, Flutter ou React Native)
GRADLE=$(find . -path ./node_modules -prune -o \( -name 'build.gradle.kts' -o -name 'build.gradle' \) -print 2>/dev/null \
  | xargs grep -l "com.android.application" 2>/dev/null | head -1)
if [ -z "$GRADLE" ]; then
  fail "Módulo Android (plugin com.android.application) não encontrado"
  exit 1
fi
APPDIR=$(dirname "$GRADLE")
MANIFEST="$APPDIR/src/main/AndroidManifest.xml"
echo "Módulo app: $APPDIR"
echo

val() { grep -Eo "$1[[:space:]]*(=|[[:space:]])[[:space:]]*[\"']?[A-Za-z0-9_.]+" "$GRADLE" | head -1 | sed -E "s/.*[= ][\"']?//"; }

APPID=$(val applicationId)
TARGET=$(val 'targetSdk(Version)?')
COMPILE=$(val 'compileSdk(Version)?')
MIN=$(val 'minSdk(Version)?')
VCODE=$(val versionCode)

echo "applicationId=$APPID targetSdk=$TARGET compileSdk=$COMPILE minSdk=$MIN versionCode=$VCODE"
echo

case "$APPID" in
  ""|*flutter*) warn "applicationId não encontrado de forma literal (pode vir de variável) — confirmar";;
  com.example*) fail "applicationId usa com.example ($APPID) — a Play Store rejeita";;
  *) ok "applicationId: $APPID";;
esac

REQUIRED_TARGET="${REQUIRED_TARGET:-35}"
if [[ "$TARGET" =~ ^[0-9]+$ ]]; then
  if [ "$TARGET" -ge "$REQUIRED_TARGET" ]; then ok "targetSdk $TARGET ≥ $REQUIRED_TARGET"
  else fail "targetSdk $TARGET < $REQUIRED_TARGET (mínimo exigido; ajuste REQUIRED_TARGET se o requisito mudou)"; fi
else
  warn "targetSdk não literal ($TARGET) — confirmar valor efetivo (ex. flutter.targetSdkVersion)"
fi

if grep -Eq "isMinifyEnabled[[:space:]]*=[[:space:]]*true|minifyEnabled[[:space:]]+true" "$GRADLE"; then ok "R8/minify habilitado"
else warn "minify não habilitado no release"; fi

if grep -q "signingConfig" "$GRADLE"; then
  if grep -Eq "storePassword[[:space:]]*=?[[:space:]]*\"[^\"$]+\"" "$GRADLE"; then fail "Senha do keystore em texto no $GRADLE"
  else ok "signingConfig presente sem senha literal"; fi
  if grep -Eq "signingConfig[[:space:]]*=?[[:space:]]*signingConfigs\.(getByName\(\"debug\"\)|debug)" "$GRADLE"; then
    warn "Algum buildType usa a chave de debug — garantir que o release use a chave de upload"
  fi
else
  warn "Nenhum signingConfig no gradle — release precisa ser assinado com a chave de upload"
fi

if git ls-files --error-unmatch '*.jks' '*.keystore' >/dev/null 2>&1 || git ls-files 2>/dev/null | grep -Eq '\.(jks|keystore)$|key\.properties$|keystore\.properties$'; then
  fail "Keystore ou arquivo de senhas versionado no git"
else ok "Nenhum keystore versionado"; fi

if [ -f "$MANIFEST" ]; then
  grep -q 'android:debuggable="true"' "$MANIFEST" && fail "android:debuggable=\"true\" no manifest"
  grep -q 'android:usesCleartextTraffic="true"' "$MANIFEST" && warn "usesCleartextTraffic=true — justificar ou usar network_security_config"
  grep -q 'android:allowBackup="true"' "$MANIFEST" && warn "allowBackup=true — revisar se dados sensíveis vão para backup"
  echo
  echo "Permissões declaradas (manifest principal; confira também o manifest mesclado):"
  grep -Eo 'uses-permission[^>]*android:name="[^"]+"' "$MANIFEST" | sed -E 's/.*name="([^"]+)"/  - \1/'
  SENSITIVE='ACCESS_BACKGROUND_LOCATION|READ_SMS|RECEIVE_SMS|SEND_SMS|READ_CALL_LOG|WRITE_CALL_LOG|PROCESS_OUTGOING_CALLS|MANAGE_EXTERNAL_STORAGE|QUERY_ALL_PACKAGES|REQUEST_INSTALL_PACKAGES|READ_MEDIA_IMAGES|READ_MEDIA_VIDEO|USE_EXACT_ALARM|SCHEDULE_EXACT_ALARM|FOREGROUND_SERVICE|BIND_ACCESSIBILITY_SERVICE|AD_ID'
  if grep -Eq "$SENSITIVE" "$MANIFEST"; then
    warn "Permissões que exigem declaração/justificativa no Play Console:"
    grep -Eo "($SENSITIVE)[A-Z_]*" "$MANIFEST" | sort -u | sed 's/^/     • /'
  fi
else
  warn "Manifest não encontrado em $MANIFEST"
fi

echo
if find . -path ./node_modules -prune -o \( -name '*.cpp' -o -name 'CMakeLists.txt' -o -name 'Android.mk' -o -name '*.so' \) -print 2>/dev/null | grep -q . ; then
  warn "Código nativo detectado — validar alinhamento de 16 KB (NDK r28+, AGP ≥ 8.5.1, zipalign -c -P 16)"
fi

echo
echo "SDKs de terceiros (conferir com o formulário Data safety e declaração de anúncios):"
grep -Eho "(implementation|api)[[:space:]]*\(?[\"'][^\"']+[\"']" "$GRADLE" | sed -E "s/.*[\"']([^\"']+)[\"'].*/  - \1/" | sort -u
grep -Eiq "ads|admob|applovin|unity3d.ads|facebook.*audience" "$GRADLE" && warn "SDK de anúncios detectado — declarar 'Contém anúncios' e AD_ID"
