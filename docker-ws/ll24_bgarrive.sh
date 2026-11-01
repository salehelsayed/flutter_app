#!/bin/bash
# LL-24 bonus part 2: Pixel Mknoon in background, Wi-Fi switched to <off|on>, then iPhone 11 sends a message and calls; time the card and the ring.
#   ll24_bgarrive.sh <off|on> <label> <out-file>
cd "$(dirname "$0")/.." || exit 2
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
W=$1; L=$2; O="$3"; P=21071FDF600CSC; A() { timeout 20 adb -s $P "$@"; }
ms() { date +%s%3N; }
cnt() { A shell dumpsys notification --noredact | grep -cE "pkg=com.mknoon.app.*channel=$1"; }
{ bash docker-ws/calls32_pixel.sh home
  [ "$W" = off ] && A shell cmd wifi set-wifi-enabled disabled || A shell cmd wifi set-wifi-enabled enabled; echo "WIFI $W $(date -u +%T.%3N)"
  m0=$(cnt mknoon_messages)
  bash docker-ws/media31.sh isend 11 "p0 $L msg"; t=$(ms)
  r=NO_CARD; for i in $(seq 1 60); do [ "$(cnt mknoon_messages)" -gt "$m0" ] && { r="CARD +$(( $(ms)-t ))ms $(date -u +%T.%3N)"; break; }; done; echo "msg $r"
  echo "net $(A shell dumpsys connectivity 2>/dev/null | grep -m1 -oE 'Active default network: [0-9]+')"
  timeout 60 python3 docker-ws/beta/ap.py 11 tap "name == 'chat_call_button'" >/dev/null; t=$(ms); echo "ip11 dial $(date -u +%T.%3N)"
  r=NO_RING; for i in $(seq 1 60); do A shell dumpsys activity services com.mknoon.app | grep -q 'MknoonCallForegroundService' && { r="RING(call FGS up) +$(( $(ms)-t ))ms $(date -u +%T.%3N)"; break; }; done; echo "call $r"
  bash docker-ws/calls32_pixel.sh shadetap Decline; sleep 3; bash docker-ws/calls32_pixel.sh collapse
} 2>&1 | tee -a "$O"
