#!/bin/bash
# VC-014c: iPhone 13 Mknoon in background for BG seconds, then the Pixel dials it; report whether iOS showed the call.
#   calls32_missring.sh <out-file> [tries=3] [bg-secs=150]
cd "$(dirname "$0")/.." || exit 2
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
O="$1"; N=${2:-3}; BG=${3:-150}; AP() { timeout 90 python3 docker-ws/beta/ap.py 13 "$@"; }
SEL="label == 'Answer call' OR label == 'Accept' OR label == 'Decline' OR name == 'call_answer'"
for k in $(seq 1 "$N"); do
  { AP app activate com.mknoon.app >/dev/null; sleep 2; AP tap "label CONTAINS 'Dismiss'" >/dev/null 2>&1
    AP app background >/dev/null; echo "try $k ip13 background $(date -u +%T.%3N) state=$(AP app state)"
    sleep "$BG"
    bash docker-ws/setA_ui.sh tap 21071FDF600CSC 'content-desc="Dismiss' >/dev/null 2>&1
    bash docker-ws/setA_ui.sh tap 21071FDF600CSC 'Start voice call'; echo "try $k pixel dial $(date -u +%T.%3N)"
    if AP wait "$SEL" 35 >/dev/null 2>&1; then echo "try $k RANG $(date -u +%T.%3N)"; else echo "try $k NO_RING $(date -u +%T.%3N)"; fi
    bash docker-ws/setA_ui.sh tap 21071FDF600CSC 'content-desc="Cancel call"' || bash docker-ws/setA_ui.sh tap 21071FDF600CSC 'content-desc="End"'; echo "try $k pixel end $(date -u +%T.%3N)"
    sleep 12
  } 2>&1 | tee -a "$O"
done
