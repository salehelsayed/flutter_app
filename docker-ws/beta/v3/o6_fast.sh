#!/bin/bash
# O6 answer path, like a user: app killed, screen off, call; tap Answer on the call screen as soon as it shows.
# Usage: o6_fast.sh <label>
. "$(dirname "$0")/lib.sh"
L=$1
padb shell cmd statusbar collapse
p_kill_app
padb shell input keyevent KEYCODE_SLEEP
sleep "${IDLE:-15}"
note "$L: killed + screen off ${IDLE:-15} s (pid at call: $(p_pid)); iphone13 calls"
[ -z "$(p_pid)" ] || note "$L WARNING: app process still alive at call time"
ios app activate >/dev/null 2>&1; sleep 1
ios tap "label CONTAINS 'Dismiss'" >/dev/null 2>&1   # the previous call's "Call ended" notice covers the call button
ios tap "label BEGINSWITH 'Open chat with puxel'" >/dev/null 2>&1; sleep 2
T0=$(p_devtime); S=$(date +%s.%N)
el() { python3 -c "import time; print(round(time.time()-$S, 1))"; }
ios tap "name == 'chat_call_button'" >/dev/null 2>&1
ios src 'call_status' 2>&1 | grep -q call_status || { note "$L iPhone did not start the call; retrying"; ios app activate >/dev/null 2>&1; sleep 2; ios tap "name == 'chat_call_button'" >/dev/null 2>&1; }
tapped=""
for i in $(seq 1 40); do
  p_dump "${L}_poll" >/dev/null
  if p_tap_node "${L}_poll" 'Answer' >/dev/null; then tapped=$(el); break; fi
done
note "$L tapped Answer on the call screen at +${tapped:-never}s"
for i in $(seq 1 15); do
  ist=$(ios src 'call_status' 2>&1 | cut -d'|' -f3 | head -1)
  case "$ist" in *Connected*|*ended*|*Ended*) break ;; esac
  sleep 1
done
note "$L caller '$ist' at +$(el)s"
sleep 3
ios tap "name == 'call_end'" >/dev/null 2>&1 || ios tap "name == 'call_cancel'" >/dev/null 2>&1
p_log_since "$T0" "$OUT/logs/${L}_logcat.txt"
note "$L DONE"
