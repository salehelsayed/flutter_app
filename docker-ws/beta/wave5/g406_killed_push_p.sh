#!/bin/bash
# Plan 406: killed-app delivery through the CURRENT relay build. Kills the app on $KILL_ON, sends from $SEND_ON to PEER_B.
# app, Alice (old build) sends a text, then check Bob's notification shade.
set -u
KILL_ON=${KILL_ON:-emulator-5556}; SEND_ON=${SEND_ON:-emulator-5554}
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
ADBB=$ANDROID_HOME/platform-tools/adb
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
B=${PEER_B:?}
TEXT="killed-push-$(date +%H%M%S)"
$ADBB -s $KILL_ON shell input keyevent 3; sleep 2
$ADBB -s $KILL_ON shell am kill com.mknoon.app; sleep 2
echo "Bob pid after kill: '$($ADBB -s $KILL_ON shell pidof com.mknoon.app | tr -d '\r')'"
$ADBB -s $KILL_ON logcat -c
$ADBB -s $KILL_ON logcat -v time > $W/g406/killed_push_bob.txt 2>&1 & LP=$!
maestro --device $SEND_ON test -e PEER_ID=$B -e TEXT="$TEXT" "$W/g406_text.yaml" >/dev/null 2>&1; echo "Alice send flow exit=$? text=$TEXT"
for i in $(seq 1 30); do
  $ADBB -s $KILL_ON shell dumpsys notification --noredact | grep -q "$TEXT" && { echo "Bob notification with the text after ~$((i*2))s"; break; }
  sleep 2
done
kill $LP
echo "Bob pid now: '$($ADBB -s $KILL_ON shell pidof com.mknoon.app | tr -d '\r')'"
$ADBB -s $KILL_ON shell dumpsys notification --noredact | grep -E "android.title=|android.text=" | grep -A0 -B0 -iE "Alice|$TEXT" | head -4
grep -oE '"event":"(PUSH|FCM|BACKGROUND|INBOX)[A-Z_]*"' $W/g406/killed_push_bob.txt | sort | uniq -c | sort -rn | head -8
