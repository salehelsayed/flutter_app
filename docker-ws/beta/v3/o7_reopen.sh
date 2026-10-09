#!/bin/bash
# O7 reopen: Orbit showing, Home, wait $1 s in the background, reopen, poll the Orbit status line until ready.
. "$(dirname "$0")/lib.sh"
WAIT=${1:-180}
T0=$(p_devtime)
note "O7R start: home, ${WAIT} s in background (devtime $T0)"
padb shell input keyevent KEYCODE_HOME
sleep "$WAIT"
S=$(date +%s.%N)
p_open_app
for i in $(seq 1 40); do
  st=$(p_dump o7r | grep -oE '"(online|offline|connecting|Connecting)[^"]*"' | head -1)
  el=$(python3 -c "import time; print(round(time.time()-$S, 1))")
  [ -n "$st" ] && echo "$el s $st" >> "$OUT/logs/o7r_status.txt"
  case "$st" in *"reservation ready"*|*"directly reachable"*) break ;; esac
done
note "O7R reopen: '$st' after $el s"
p_log_since "$T0" "$OUT/logs/o7r_logcat.txt"
F="$OUT/logs/o7r_logcat.txt"
note "O7R window: relay_selector_failed=$(grep -c 'RELAY_SELECTOR.*failed' "$F") no_good_addresses=$(grep -c 'no good addresses' "$F")"
note "O7R DONE"
