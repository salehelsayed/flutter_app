#!/bin/bash
# Test-only: dump Mknoon app + Go node logcat lines from one device, redacted (peer IDs, IPs, long hex/base64 tokens).
#   mk_logcat_redacted.sh <serial> <out-file>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="${1:?serial}"; OUT="${2:?out}"
PID=$(timeout 15 adb -s "$S" shell pidof com.mknoon.app | tr -d '\r')
{
  echo "# serial-redacted capture $(date -u +%FT%TZ) app_pid=${PID:-none}"
  if [ -n "$PID" ]; then timeout 60 adb -s "$S" logcat -d -v threadtime --pid="$PID"
  else timeout 60 adb -s "$S" logcat -d -v threadtime | grep -i -E 'mknoon|flutter|GoLog|libp2p|gomknoon'; fi
} | sed -E \
    -e 's/12D3KooW[1-9A-HJ-NP-Za-km-z]+/<peer>/g' \
    -e 's/Qm[1-9A-HJ-NP-Za-km-z]{44}/<peer>/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g' \
    -e 's/[0-9a-fA-F]{32,}/<hex>/g' \
    -e 's/[A-Za-z0-9_+\/=-]{60,}/<token>/g' > "$OUT"
echo "wrote $OUT lines=$(wc -l < "$OUT") bytes=$(wc -c < "$OUT")"
