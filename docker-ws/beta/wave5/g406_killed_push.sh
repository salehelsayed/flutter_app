#!/bin/bash
# Plan 406: killed-app delivery on BobNew (new build). Background + kill Bob's
# app, AliceOld (old build) sends a text, then check Bob's notification shade.
set -u
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
ADBB=$ANDROID_HOME/platform-tools/adb
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
B=12D3KooWGyzpyMehMF3NnLF295SXuReF6Sqx1bYj3doQvtDfChjZ
TEXT="killed-push-$(date +%H%M%S)"
$ADBB -s emulator-5556 shell input keyevent 3; sleep 2
$ADBB -s emulator-5556 shell am kill com.mknoon.app; sleep 2
echo "Bob pid after kill: '$($ADBB -s emulator-5556 shell pidof com.mknoon.app | tr -d '\r')'"
$ADBB -s emulator-5556 logcat -c
$ADBB -s emulator-5556 logcat -v time > $W/g406/killed_push_bob.txt 2>&1 & LP=$!
maestro --device emulator-5554 test -e PEER_ID=$B -e TEXT="$TEXT" "$W/g406_text.yaml" >/dev/null 2>&1; echo "Alice send flow exit=$? text=$TEXT"
for i in $(seq 1 30); do
  $ADBB -s emulator-5556 shell dumpsys notification --noredact | grep -q "$TEXT" && { echo "Bob notification with the text after ~$((i*2))s"; break; }
  sleep 2
done
kill $LP
echo "Bob pid now: '$($ADBB -s emulator-5556 shell pidof com.mknoon.app | tr -d '\r')'"
$ADBB -s emulator-5556 shell dumpsys notification --noredact | grep -E "android.title=|android.text=" | grep -A0 -B0 -iE "AliceOld|$TEXT" | head -4
grep -oE '"event":"(PUSH|FCM|BACKGROUND|INBOX)[A-Z_]*"' $W/g406/killed_push_bob.txt | sort | uniq -c | sort -rn | head -8
