#!/bin/bash
# O7: Pixel app in the background for 5 min (screen on, process alive): count relay dials and "no good addresses";
# then reopen and time the relay connection's return (status pill text on Orbit).
. "$(dirname "$0")/lib.sh"
T0=$(p_devtime)
note "O7 start: home (app pid $(p_pid)), devtime $T0"
padb shell input keyevent KEYCODE_HOME
sleep 300
note "O7 5 min over: pid $(p_pid) wake=$(p_wake)"
p_log_since "$T0" "$OUT/logs/o7_bg_logcat.txt"
F="$OUT/logs/o7_bg_logcat.txt"
note "O7 background window: lines=$(wc -l < "$F") relay_selector_failed=$(grep -c 'RELAY_SELECTOR.*failed' "$F") no_good_addresses=$(grep -c 'no good addresses' "$F") reservation_lines=$(grep -ciE 'reservation (opened|ok|refreshed)|Reservation opened' "$F") dial_attempt_lines=$(grep -cE 'RELAY_SELECTOR\] Relay' "$F")"
T1=$(p_devtime); S=$(date +%s.%N)
p_open_app
for i in $(seq 1 40); do
  st=$(p_dump o7_open | grep -oE '"(online|offline|connecting)[^"]*"' | head -1)
  case "$st" in *"relay reservation ready"*|*"directly reachable"*) break ;; esac
  sleep 0.5
done
E=$(date +%s.%N)
note "O7 reopen: status '$st' after $(python3 -c "print(round($E-$S,1))") s (polls $i)"
p_log_since "$T1" "$OUT/logs/o7_reopen_logcat.txt"
note "O7 DONE"
