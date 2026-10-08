#!/usr/bin/env bash
# Monitora threads e memória de um app Android via adb e grava em CSV.
# Uso: monitor_threads.sh <package> [duracao_segundos=60] [intervalo_segundos=2] [saida=threads_<package>.csv]
set -euo pipefail

PKG="${1:?Uso: $0 <package> [duracao] [intervalo] [saida]}"
DURATION="${2:-60}"
INTERVAL="${3:-2}"
OUT="${4:-threads_${PKG}.csv}"

command -v adb >/dev/null || { echo "adb não encontrado no PATH" >&2; exit 1; }
[ "$(adb devices | sed '1d' | grep -c 'device$')" -ge 1 ] || { echo "Nenhum dispositivo conectado" >&2; exit 1; }

echo "timestamp,pid,thread_count,pss_kb,threads" > "$OUT"
END=$(( $(date +%s) + DURATION ))

while [ "$(date +%s)" -lt "$END" ]; do
  TS=$(date +%H:%M:%S)
  PID=$(adb shell pidof "$PKG" 2>/dev/null | tr -d '\r' || true)
  if [ -z "$PID" ]; then
    echo "$TS,,0,0," >> "$OUT"
    echo "$TS  processo não está rodando"
  else
    # Nomes das threads (coluna CMD de ps -T), agrupados com contagem
    NAMES=$(adb shell ps -T -p "$PID" -o CMD= 2>/dev/null | tr -d '\r' \
      | sed -E 's/-[0-9]+$/-N/; s/[0-9]+$/N/' | sort | uniq -c \
      | awk '{c=$1; $1=""; sub(/^ /,""); printf "%s(%s) ", $0, c}')
    COUNT=$(adb shell ls "/proc/$PID/task" 2>/dev/null | tr -d '\r' | wc -l | tr -d ' ')
    PSS=$(adb shell dumpsys meminfo "$PKG" 2>/dev/null | tr -d '\r' | awk '/TOTAL PSS:/ {print $3; exit} /^ *TOTAL / {print $2; exit}')
    echo "$TS,$PID,$COUNT,${PSS:-0},\"$NAMES\"" >> "$OUT"
    echo "$TS  pid=$PID threads=$COUNT pss_kb=${PSS:-?}"
  fi
  sleep "$INTERVAL"
done

echo "Resultado salvo em $OUT"
