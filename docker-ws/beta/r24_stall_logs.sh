#!/bin/bash
# Stall analysis (read-only on the devices): excerpts of the stalled run's Pixel logcat around the transcode.
# Usage: r24_stall_logs.sh <run dir name> <from HH:MM:SS> <to HH:MM:SS>
. "$(dirname "$0")/beta_env.sh"
RUN="$BETA/$1"; A="${2:-15:45:00}"; B="${3:-15:49:00}"
L="$RUN/android_logcat_live.txt"; OUT="$RUN/extra/stall"; mkdir -p "$OUT"
echo "logcat: $(wc -l < "$L") lines, $(stat -f %z "$L") bytes"
awk -v a="$A" -v b="$B" '($2 >= a && $2 <= b)' "$L" > "$OUT/window_all.txt"
APP=$(grep -m1 -oE "Start proc [0-9]+:com\.mknoon\.app" "$L" | tail -1 | grep -oE "[0-9]+")
PIDS=$(awk '($2 >= "'"$A"'") && / flutter : \[FLOW\]/ {print $3}' "$L" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
echo "app pid (from FLOW lines in the window): $PIDS"
awk -v p="$PIDS" '$3 == p' "$OUT/window_all.txt" | grep -v " flutter : " > "$OUT/window_app_native.txt"
echo "app native lines: $(wc -l < "$OUT/window_app_native.txt")"
echo "=== app native tags"; awk '{print $5, $6}' "$OUT/window_app_native.txt" | sort | uniq -c | sort -rn | head -25
echo "=== codec/media service lines (other pids) with error-ish words"
grep -iE "c2|codec|omx|goldfish|avc|h264|hevc|aac" "$OUT/window_all.txt" | grep -iE "err|fail|timeout|stuck|watchdog|abort|fatal|warn| W | E " | grep -v Maestro | head -30 | cut -c1-220
