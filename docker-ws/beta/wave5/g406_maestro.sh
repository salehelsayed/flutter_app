#!/bin/bash
# Plan 406: run a Maestro flow on one emulator with logcat captured on BOTH emulators.
# Usage: g406_maestro.sh <serial> <flow.yaml> <tag> [KEY=VALUE ...]
set -u
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
S=$1; FLOW=$2; TAG=$3; shift 3
EV=$W/g406/ev_$TAG; mkdir -p "$EV"
ADBB=$ANDROID_HOME/platform-tools/adb
ENVS=(); for kv in "$@"; do ENVS+=(-e "$kv"); done
for D in emulator-5554 emulator-5556; do $ADBB -s $D logcat -c; done
$ADBB -s emulator-5554 logcat -v time >"$EV/alice_old.txt" 2>&1 & L1=$!
$ADBB -s emulator-5556 logcat -v time >"$EV/bob_new.txt" 2>&1 & L2=$!
maestro --device "$S" test --test-output-dir "$EV/maestro" ${ENVS[@]+"${ENVS[@]}"} "$W/$FLOW" >"$EV/maestro.log" 2>&1
echo "flow exit=$?"
sleep ${SETTLE:-8}; kill $L1 $L2
grep -E 'COMPLETED|FAILED' "$EV/maestro.log" | tail -4
