#!/bin/bash
# O1 conditions: restart = restart the iPhone 13 app, background it, wait IDLE s, call (the earlier slow case);
# killed = terminate the iPhone 13 app, wait IDLE s, call (PushKit must launch it). Prints banner time and outcome.
cd "$(dirname "$0")"
MODE=$1; IDLE=${2:-20}
if [ "$MODE" = restart ]; then
  python3 ap.py 13 app terminate >/dev/null; python3 ap.py 13 app activate >/dev/null; sleep 8
  python3 ap.py 13 app background -1 >/dev/null
else
  python3 ap.py 13 app terminate >/dev/null
fi
sleep "$IDLE"
T0=$(date +%s.%N); echo "$MODE call at $(TZ=Europe/Berlin date +%H:%M:%S) (app state $(python3 ap.py 13 app state))"
python3 ap.py 11 tap "name == 'chat_call_button'" >/dev/null
banner=none
for i in $(seq 1 90); do
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
python3 ap.py 13 app activate >/dev/null; sleep 2
