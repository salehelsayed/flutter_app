#!/bin/bash
# O5/O6 (and O4 with FSI=deny): Pixel app killed, screen off >= 40 s, no lock screen; iPhone 13 calls.
# Records: time to screen on, the first screen after wake (UI tree + screenshot), then answers on the Pixel if an
# Answer button is reachable (call screen, or the heads-up), and checks Connected on both phones.
# Usage: o5.sh <label>
. "$(dirname "$0")/lib.sh"
L=$1
padb shell cmd statusbar collapse
p_kill_app
padb shell input keyevent KEYCODE_SLEEP
sleep ${IDLE:-40}
note "$L: killed + screen off ${IDLE:-40} s (pid at call: $(p_pid)) (wake=$(p_wake) keyguard=$(p_keyguard) fsi=$(padb shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r' | cut -c1-40)); iphone13 calls"
T0=$(p_devtime); S=$(date +%s.%N)
ios tap "name == 'chat_call_button'" >/dev/null 2>&1
el() { python3 -c "import time; print(round(time.time()-$S, 1))"; }
awake=""; notif=""
for i in $(seq 1 60); do
  [ -z "$notif" ] && [ "$(p_notifs | grep -c 'Incoming call')" -gt 0 ] && { notif=$(el); note "$L ringing notification at +${notif}s"; }
  if [ "$(p_wake)" = Awake ]; then awake=$(el); break; fi
  sleep 0.3
done
if [ -n "$awake" ]; then
  p_shot "${L}_first" >/dev/null
  first=$(p_dump "${L}_first" | grep -oE '"[^"]*(iphone-13|[Cc]all|Answer|Decline|Connected|Opening|Feed|online|Open chat)[^"]*"' | head -8 | tr '\n' ' ')
  note "$L screen ON at +${awake}s; top=$(p_top); first screen: $first"
else
  note "$L screen stayed OFF for $(el)s (wake=$(p_wake)); notification at +${notif:-none}s"
fi
sleep 2
p_dump "${L}_ring" >/dev/null
if p_tap_node "${L}_ring" 'Answer' >/dev/null; then
  note "$L tapped Answer on the screen at +$(el)s"
else
  padb shell cmd statusbar expand-notifications; sleep 1.5
  p_dump "${L}_shade" >/dev/null
  p_tap_node "${L}_shade" 'Answer' >/dev/null && note "$L tapped Answer in the shade at +$(el)s" || note "$L NO Answer button found"
  rm -f "$OUT/ui/${L}_shade.xml"
fi
sleep 6
pst=$(p_dump "${L}_after" | grep -oE '"(Connected|Connecting|Call duration [0-9:]+)"' | tr '\n' ' ')
ist=$(ios src 'call_status' 2>&1 | cut -d'|' -f3 | head -1)
note "$L after answer: pixel=[$pst] iphone=[$ist]"
sleep 4
ios tap "name == 'call_end'" >/dev/null 2>&1 || ios tap "name == 'call_cancel'" >/dev/null 2>&1
p_log_since "$T0" "$OUT/logs/${L}_logcat.txt"
note "$L DONE"
