#!/bin/bash
# O4: full-screen access denied, Pixel app killed, screen off >= 40 s, swipe lock screen; iPhone 13 calls.
# Like a user: after 8 s of ringing, press power, look at the lock screen, answer from it if possible.
# Usage: o4.sh <label>
. "$(dirname "$0")/lib.sh"
L=$1
filt() { grep -oE '"[^"]*(iphone-13|[Cc]all|Answer|Decline|Connected|Opening|Feed|Mknoon|MKnoon)[^"]*"' | head -10 | tr '\n' ' '; }
padb shell cmd statusbar collapse
p_kill_app
padb shell input keyevent KEYCODE_SLEEP
sleep ${IDLE:-40}
note "$L: killed + screen off ${IDLE:-40} s (pid at call: $(p_pid)) (wake=$(p_wake) keyguard=$(p_keyguard) fsi=$(padb shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r' | cut -c1-30)); iphone13 calls"
T0=$(p_devtime); S=$(date +%s.%N)
el() { python3 -c "import time; print(round(time.time()-$S, 1))"; }
ios tap "name == 'chat_call_button'" >/dev/null 2>&1
notif=""
for i in $(seq 1 30); do
  [ "$(p_notifs | grep -c 'Incoming call')" -gt 0 ] && { notif=$(el); break; }
  sleep 0.3
done
note "$L ringing notification at +${notif:-none}s; wake=$(p_wake) (screen not woken by the app if Dozing/Asleep)"
while [ "$(python3 -c "print(int($(el) < 8))")" = 1 ]; do sleep 0.3; done
padb shell input keyevent KEYCODE_WAKEUP
sleep 1.5
p_shot "${L}_wake" >/dev/null
note "$L power pressed at +8 s; top=$(p_top) keyguard=$(p_keyguard); lock screen shows: $(p_dump "${L}_wake" | filt)"
if p_tap_node "${L}_wake" 'Answer' >/dev/null; then
  note "$L tapped Answer on the lock screen at +$(el)s"
elif p_tap_node "${L}_wake" 'Expand' >/dev/null && sleep 1.5 && p_dump "${L}_expanded" >/dev/null && p_shot "${L}_expanded" >/dev/null \
     && p_tap_node "${L}_expanded" 'Answer' >/dev/null; then
  note "$L expanded the lock-screen call notification, tapped Answer at +$(el)s"
else
  padb shell cmd statusbar expand-notifications; sleep 1.5
  p_dump "${L}_shade" >/dev/null
  p_tap_node "${L}_shade" 'Answer' >/dev/null && note "$L tapped Answer in the shade at +$(el)s" || note "$L NO Answer button found"
  rm -f "$OUT/ui/${L}_shade.xml"
fi
for i in $(seq 1 12); do  # up to ~25 s: wait for the caller to see Connected (or the call to end)
  ist=$(ios src 'call_status' 2>&1 | cut -d'|' -f3 | head -1)
  case "$ist" in *Connected*|*ended*|*Ended*|*answer*) break ;; esac
  [ -z "$ist" ] && break
  sleep 1
done
note "$L caller state '$ist' at +$(el)s"
pst=$(p_dump "${L}_after" | grep -oE '"(Connected|Connecting|Call duration [0-9:]+)"' | tr '\n' ' ')
note "$L after answer: pixel=[$pst] iphone=[$ist]"
sleep 4
ios tap "name == 'call_end'" >/dev/null 2>&1 || ios tap "name == 'call_cancel'" >/dev/null 2>&1
padb shell cmd statusbar collapse
p_log_since "$T0" "$OUT/logs/${L}_logcat.txt"
note "$L DONE"
