#!/bin/bash
# Voice-playback repro on Alice (emulator-5554): run a Maestro flow with logcat captured.
# Usage: voice_run.sh <flow.yaml> <tag>
set -u
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
EV=$W/voice/ev_$2; mkdir -p "$EV"
ADBB=$ANDROID_HOME/platform-tools/adb
BOB=$($ADBB -s emulator-5556 shell "run-as com.mknoon.app cat app_flutter/intro_e2e_identity.json" | python3 -c "import json,sys;print(json.loads(json.load(sys.stdin)['qrPayload'])['ns'])")
echo "bob=$BOB"
$ADBB -s emulator-5554 logcat -c
$ADBB -s emulator-5554 logcat -v time >"$EV/alice_logcat.txt" 2>&1 &
LP=$!
maestro --device emulator-5554 test --test-output-dir "$EV/maestro" -e PEER_ID="$BOB" "$W/$1" >"$EV/maestro.log" 2>&1
echo "flow exit=$?"
sleep 3; kill $LP
grep -E 'COMPLETED|FAILED|SKIPPED' "$EV/maestro.log" | tail -14
grep -oE '"event":"(VOICE|CONV_FL_VOICE|MEDIA_DURABILITY|AUDIO|PLAY)[A-Z_]*"' "$EV/alice_logcat.txt" | sort | uniq -c
