#!/bin/bash
# N1 call trace: Pixel (all pids) call/Telecom/notification lines + app CALL_ flow events + crashes, and the iPhone's
# CALL_ events, for a window. Usage: r25_call_trace.sh <from HH:MM:SS> <to HH:MM:SS> <ios-from "YYYY-MM-DD HH:MM:SS">
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
awk -v a="$1" -v b="$2" '($2 >= a && $2 <= b)' "$L" > /tmp/r25_n1.txt
echo "== Pixel app CALL_ flow events"
grep -oE '"event":"CALL_[A-Z_]*"[^}]*' /tmp/r25_n1.txt | uniq -c | head -20 | cut -c1-200
echo "== Pixel native call / Telecom / notification / crash lines"
grep -E "Mknoon|Telecom|CallsManager|NotificationService.*mknoon|FATAL|AndroidRuntime|ANR in|Exception" /tmp/r25_n1.txt | grep -v "Maestro\|persistent_data_block\|GoLog" | head -25 | cut -c1-230
echo "== Pixel FCM / wake lines"
grep -iE "FirebaseMessaging|fcm|CallWake|wake" /tmp/r25_n1.txt | head -8 | cut -c1-200
echo "== iPhone CALL_ events"
xcrun simctl spawn "$UDID" log show --start "$3" --style compact --predicate 'process == "Runner"' 2>/dev/null | grep -oE '"event":"CALL_[A-Z_]*"[^}]*' | uniq -c | head -20 | cut -c1-200
