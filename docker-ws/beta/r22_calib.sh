#!/bin/bash
# R2-2 calibration (~70 s): do Mac-only fake services (R22_IF, default lo0) reach the simulator app? Registers 3 quiet services
# for 50 s, checks them with dns-sd, then counts the app's LOCAL_MDNS events for their ports.
. "$(dirname "$0")/beta_env.sh"
H="$(cd "$(dirname "$0")" && pwd)"
OUT="$BETA/r2-2/calib-$(date +%H%M%S)"; mkdir -p "$OUT"
START=$(date '+%Y-%m-%d %H:%M:%S')
R22_IF=${R22_IF:-lo0} /usr/bin/python3 "$H/r22_gen.py" "$OUT" 50 3 0 0 47100 > "$OUT/gen.out" 2>&1 & g=$!
sleep 6
echo "=== browse (4 s)"; dns-sd -B _mknoon._tcp local. > "$OUT/browse.txt" 2>&1 & p=$!; sleep 4; kill $p; grep stress "$OUT/browse.txt"
echo "=== resolve q0 (3 s)"; dns-sd -L mknoon-stress-q0 _mknoon._tcp local. > "$OUT/lookup.txt" 2>&1 & p=$!; sleep 3; kill $p; tail -3 "$OUT/lookup.txt"
wait $g; cat "$OUT/gen.out"; tail -1 "$OUT/gen_counts.txt"
sleep 3
END=$(date '+%Y-%m-%d %H:%M:%S')
xcrun simctl spawn "$UDID" log show --start "$START" --end "$END" --predicate 'process == "Runner"' --style compact > "$OUT/ios_log.txt" 2>&1
echo "=== app LOCAL_MDNS events in the window ($START .. $END)"
grep -o '"event":"LOCAL_MDNS_[A-Z_]*".*' "$OUT/ios_log.txt" | sed -E 's/"peerId":"[^"]*",?//; s/"ts":"[^"]*",?//' | cut -c1-110 | sort | uniq -c | sort -rn | head -12
echo "calib dir: $OUT"
