#!/bin/bash
# O1: N calls from the iPhone 11 to the iPhone 13 while the iPhone 13 app is in the background. For each call: seconds
# from the caller's tap to the CallKit banner, Answer, and whether both sides reach Connected. Needs both ap.py sessions,
# the iPhone 11 inside the iphone-13 chat.
cd "$(dirname "$0")"
N=${1:-5}; IDLE=${2:-25}
for n in $(seq 1 "$N"); do
  python3 ap.py 13 app background -1 >/dev/null
  sleep "$IDLE"
  T0=$(date +%s.%N); echo "call $n at $(TZ=Europe/Berlin date +%H:%M:%S)"
  python3 ap.py 11 tap "name == 'chat_call_button'" >/dev/null
  banner=none
  for i in $(seq 1 60); do
    if python3 ap.py 13 find "label == 'Answer call'" >/dev/null 2>&1; then
      banner=$(python3 -c "import time; print(round(time.time()-$T0,1))")
      python3 ap.py 13 tap "label == 'Answer call'" >/dev/null 2>&1
      break
    fi
    sleep 0.3
  done
  conn=no
  python3 ap.py 11 wait "name == 'call_status' AND label == 'Connected'" 25 >/dev/null 2>&1 && conn=yes
  echo "  banner +${banner} s, caller connected: $conn"
  sleep 3
  python3 ap.py 11 tap "name == 'call_end'" >/dev/null 2>&1 || python3 ap.py 11 tap "name == 'call_cancel'" >/dev/null 2>&1
  sleep 4
  python3 ap.py 11 src 'call_row' | tail -1 | cut -d'|' -f3 | sed 's/^/  last call row:/'
  python3 ap.py 13 app activate >/dev/null; sleep 2
done
