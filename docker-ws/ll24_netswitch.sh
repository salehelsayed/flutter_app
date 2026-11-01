#!/bin/bash
# LL-24 bonus: during an active Pixel <-> iPhone 11 call, Pixel Wi-Fi off (falls to mobile data) then on; sample both call states.
#   ll24_netswitch.sh <out-file> [off-secs=30]
cd "$(dirname "$0")/.." || exit 2
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
O="$1"; OFF=${2:-30}; P=21071FDF600CSC; A() { timeout 20 adb -s $P "$@"; }
st() { echo "$(date -u +%T) pixel=[$(bash docker-ws/calls31.sh pui 2>/dev/null | grep -oE 'content-desc="(Connected|Reconnecting|Connecting|Call ended|Ringing|Calling)[^"]{0,20}"|Call duration [0-9:]+' | paste -sd,)] ip11=[$(IP=11 bash docker-ws/calls31.sh iui 2>/dev/null | grep -E 'call_status|Call ended' | awk -F'|' '{print $3}' | head -1)] net=$(A shell dumpsys connectivity 2>/dev/null | grep -m1 -oE 'Active default network: [0-9a-z]+')"; }
{ bash docker-ws/setA_ui.sh tap $P 'Start voice call'; echo "pixel dial $(date -u +%T.%3N)"
  timeout 70 python3 docker-ws/beta/ap.py 11 wait "name == 'call_answer' OR label == 'Answer call'" 40 >/dev/null; timeout 60 python3 docker-ws/beta/ap.py 11 tap "name == 'call_answer' OR label == 'Answer call'"; echo "ip11 answered $(date -u +%T.%3N)"
  sleep 8; st
  A shell cmd wifi set-wifi-enabled disabled; echo "WIFI OFF $(date -u +%T.%3N)"
  e=$(( $(date +%s) + OFF )); while [ "$(date +%s)" -lt "$e" ]; do st; done
  A shell cmd wifi set-wifi-enabled enabled; echo "WIFI ON $(date -u +%T.%3N)"
  e=$(( $(date +%s) + 40 )); while [ "$(date +%s)" -lt "$e" ]; do st; done
} 2>&1 | tee "$O"
