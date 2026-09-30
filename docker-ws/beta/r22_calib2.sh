#!/bin/bash
# R2-2 calibration 2 (~70 s): fake services on lo0 AND LocalOnly. How many replies does one lookup get,
# and does the app still resolve them? Uses its own names (mknoon-cal-*) so it never clashes with a running test.
. "$(dirname "$0")/beta_env.sh"
H="$(cd "$(dirname "$0")" && pwd)"
OUT="$BETA/r2-2/calib2-$(date +%H%M%S)"; mkdir -p "$OUT"
START=$(date '+%Y-%m-%d %H:%M:%S')
R22_IF=lo0,local R22_PREFIX=mknoon-cal /usr/bin/python3 "$H/r22_gen.py" "$OUT" 50 2 1 0 47200 > "$OUT/gen.out" 2>&1 & g=$!
sleep 6
echo "=== browse (4 s)"; dns-sd -B _mknoon._tcp local. > "$OUT/browse.txt" 2>&1 & p=$!; sleep 4; kill $p; grep cal "$OUT/browse.txt"
echo "=== lookup q0 (3 s)"; dns-sd -L mknoon-cal-q0 _mknoon._tcp local. > "$OUT/lookup.txt" 2>&1 & p=$!; sleep 3; kill $p; grep -c "can be reached" "$OUT/lookup.txt"; grep "can be reached" "$OUT/lookup.txt"
echo "=== lookup u2 (3 s, TXT changing)"; dns-sd -L mknoon-cal-u2 _mknoon._tcp local. > "$OUT/lookup_u.txt" 2>&1 & p=$!; sleep 3; kill $p; grep -c "can be reached" "$OUT/lookup_u.txt"
wait $g; cat "$OUT/gen.out"; tail -1 "$OUT/gen_counts.txt"
sleep 3
END=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --start "$START" --end "$END" --predicate 'process == "Runner"' --style compact > "$OUT/ios_log.txt" 2>&1
echo "=== app PEER_FOUND for the calibration ports"
grep -o '"event":"LOCAL_MDNS_PEER_FOUND".*' "$OUT/ios_log.txt" | grep -o '"port":472[0-9][0-9]' | sort | uniq -c
echo "calib dir: $OUT"
