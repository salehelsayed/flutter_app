#!/bin/bash
# O3: on the iPhone 13, start playing the 0:30 voice note and leave the chat at once, N times.
N=${1:-10}; ok=0
for i in $(seq 1 $N); do
  r=$(python3 ap.py 13 find "label CONTAINS 'Voice message' AND label CONTAINS '0:30'" 2>/dev/null | tail -1)
  y=$(echo "$r" | sed -n "s/.*'y': \([0-9]*\).*/\1/p"); x=$(echo "$r" | sed -n "s/.*'x': \([0-9]*\).*/\1/p")
  [ -n "$y" ] || { echo "cycle $i: bubble not found"; break; }
  python3 ap.py 13 tapxy $((x + 33)) $((y + 24)) >/dev/null
  python3 ap.py 13 tap "name == 'Back'" >/dev/null || { echo "cycle $i: no Back"; break; }
  python3 ap.py 13 wait "name CONTAINS 'orbit.contact.12D3KooWL9' OR label BEGINSWITH 'Open chat with iphone-11'" 10 >/dev/null 2>&1
  python3 ap.py 13 tap "name CONTAINS 'orbit.contact.12D3KooWL9'" >/dev/null 2>&1 \
    || python3 ap.py 13 tap "label BEGINSWITH 'Open chat with iphone-11'" >/dev/null 2>&1 \
    || { echo "cycle $i: cannot reopen"; break; }
  python3 ap.py 13 wait "label CONTAINS 'Voice message' AND label CONTAINS '0:30'" 15 >/dev/null || { echo "cycle $i: chat not ready"; break; }
  ok=$i
done
echo "completed $ok of $N cycles"
