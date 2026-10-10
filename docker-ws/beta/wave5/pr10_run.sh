#!/bin/bash
# PR 10 device proof: run one Maestro flow on one emulator with its logcat captured.
# Usage: pr10_run.sh <serial> <flow.yaml> <tag>
set -u
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
EV=$W/pr10_ev/$3; mkdir -p "$EV"
ADBB=$ANDROID_HOME/platform-tools/adb
$ADBB -s $1 logcat -c
$ADBB -s $1 logcat -v time >"$EV/logcat.txt" 2>&1 &
LP=$!
maestro --device $1 test --test-output-dir "$EV/maestro" "$W/$2" >"$EV/maestro.log" 2>&1
echo "$3 flow exit=$?"
sleep 2; kill $LP 2>/dev/null
grep -E 'COMPLETED|FAILED' "$EV/maestro.log" | tail -25
grep -oE '"event":"(GROUP_EXIT|GROUP_INFO|LEAVE|GROUP_LEAVE)[A-Z_]*"' "$EV/logcat.txt" | sort | uniq -c | head -12
