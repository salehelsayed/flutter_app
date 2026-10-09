#!/bin/bash
# O1: iPhone 13 with the CallKit-off build, app in the background; the Pixel calls it.
# Pass: the Pixel never ends with signalingFailed; the iPhone rings/notifies or the call ends normally.
# Usage: o1.sh <label>   (the iPhone app must already be running; the Pixel shows the chat with iphone-13)
. "$(dirname "$0")/lib.sh"
L=$1
ios app activate >/dev/null 2>&1; sleep 4
ios app background >/dev/null 2>&1; sleep 6
note "$L: iphone13 app state=$(ios app state 2>&1 | tail -1) (4 = foreground); Pixel calls"
T0=$(p_devtime); S=$(date +%s.%N)
el() { python3 -c "import time; print(round(time.time()-$S, 1))"; }
p_dump "${L}_chat" >/dev/null
p_tap_node "${L}_chat" 'Start voice call' >/dev/null || note "$L no call button"
last=""
for i in $(seq 1 45); do
  t=$(p_dump "${L}_c" | grep -oE '"(Calling|Ringing|Connecting|Call ended[^"]*|No answer[^"]*|[^"]*unavailable[^"]*|[^"]*failed[^"]*)"' | tr '\n' ' ')
  [ -n "$t" ] && [ "$t" != "$last" ] && { note "$L +$(el)s pixel: $t"; last="$t"; }
  case "$t" in *"Call ended"*) break ;; esac
  sleep 1
done
p_log_since "$T0" "$OUT/logs/${L}_logcat.txt"
note "$L pixel end: $(grep -oE '"trigger":"[a-zA-Z]+","state":"ended","endReason":"[a-zA-Z]+"' "$OUT/logs/${L}_logcat.txt" | tail -1)"
padb shell input keyevent KEYCODE_BACK
note "$L DONE"
