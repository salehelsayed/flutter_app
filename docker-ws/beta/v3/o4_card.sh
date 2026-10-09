#!/bin/bash
# O4 in-app prompt: full-screen access denied, a call rings unanswered, then the app is opened.
# Checks the card, "Open settings" (the system page), the card hiding after access is granted, and "Not now".
. "$(dirname "$0")/lib.sh"
FSI0=$(padb shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r')
card() { p_dump "$1" | grep -oE '"(Show calls on your lock screen|Open settings|Not now)"' | tr '\n' ' '; }
missed_call() {
  padb shell cmd statusbar collapse
  p_kill_app
  padb shell input keyevent KEYCODE_SLEEP
  sleep 10
  ios tap "name == 'chat_call_button'" >/dev/null 2>&1
  sleep 12
  ios tap "name == 'call_cancel'" >/dev/null 2>&1
  sleep 4
  padb shell input keyevent KEYCODE_WAKEUP
  sleep 1
}
padb shell run-as $PKG rm -f shared_prefs/mknoon_full_screen_call_access.xml
padb shell cmd appops set $PKG USE_FULL_SCREEN_INTENT deny
note "O4C start: fsi before='$FSI0', now deny; prompt state cleared"

note "O4C card before any denied call (app opened): [$(p_open_app; sleep 8; card c0)]"
missed_call
p_open_app; sleep 8
note "O4C after a missed call with access denied, app opened: [$(card c1)]"
p_tap_node c1 'Open settings' >/dev/null && sleep 3
note "O4C Open settings -> top=$(p_top)"
p_shot o4c_settings >/dev/null
padb shell cmd appops set $PKG USE_FULL_SCREEN_INTENT allow
padb shell input keyevent KEYCODE_BACK; sleep 4
note "O4C access granted, back in app (top=$(p_top)): card=[$(card c2)]"

padb shell cmd appops set $PKG USE_FULL_SCREEN_INTENT deny
missed_call
p_open_app; sleep 8
note "O4C second missed call: card=[$(card c3)]"
p_tap_node c3 'Not now' >/dev/null && sleep 2
note "O4C after Not now: card=[$(card c4)]"
padb shell input keyevent KEYCODE_HOME; sleep 2; p_open_app; sleep 6
note "O4C reopened after Not now: card=[$(card c5)] (expected hidden for 7 days)"

padb shell run-as $PKG rm -f shared_prefs/mknoon_full_screen_call_access.xml
padb shell cmd appops set $PKG USE_FULL_SCREEN_INTENT default
note "O4C restored fsi=$(padb shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r' | cut -c1-35); prompt state cleared"
note "O4C DONE"
