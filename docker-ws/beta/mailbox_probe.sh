#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk '$2>="22:19:25" && $2<="22:20:10"' "$RUN/android_logcat_live.txt" \
 | grep -E '"event":"(CALL_[A-Z_]*|INBOX_[A-Z_]*|P2P_PUSH_EVENT_RECEIVED|MSG_RECEIVED_TRANSPORT|FCM_[A-Z_]*|PUSH_[A-Z_]*|WAKE_[A-Z_]*)"|FirebaseMessaging|FCM' \
 | sed -E 's/.*"ts":"[0-9-]+T([0-9:.]{12})[^"]*".*"event":"/\1 /; s/","details":/ /' | cut -c1-170 | sort | uniq -c | sort -rn | head -20
