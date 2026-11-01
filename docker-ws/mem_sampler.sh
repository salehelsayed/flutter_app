#!/bin/bash
# Sample Mknoon TOTAL PSS / TOTAL RSS (kB) on one Android device until <out>.stop exists or <max-secs> pass. One line per sample.
#   mem_sampler.sh <serial> <out-file> [max-secs]
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S="${1:?serial}"; OUT="${2:?out}"; MAX="${3:-300}"; end=$(( $(date +%s) + MAX ))
rm -f "$OUT.stop"; : > "$OUT"
while [ ! -f "$OUT.stop" ] && [ "$(date +%s)" -lt "$end" ]; do
  L=$(timeout 10 adb -s "$S" shell dumpsys meminfo com.mknoon.app | grep -E "TOTAL PSS|TOTAL RSS" | tr -s ' ' | paste -sd' ')
  echo "$(date -u +%T.%2N) $L" >> "$OUT"; sleep 1
done
rm -f "$OUT.stop"
