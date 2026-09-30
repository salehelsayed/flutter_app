#!/bin/bash
# Read-only: Android native/system lines about the app between two HH:MM:SS times.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
awk -v a="$1" -v b="$2" '$2>=a && $2<=b' "$RUN/android_logcat_live.txt" \
  | grep -E "MainActivity|onDestroy|onBackPressed|OnBackPressed|BackInvoked|Back|SystemNavigator|cleanUpFlutterEngine|CALL_ANDROID|Telecom.*mknoon|ActivityTaskManager.*mknoon|wm_.*mknoon|task.*mknoon|appShutdown|detached|AppLifecycle|\"event\":\"CALL_|\"event\":\"APP_LIFECYCLE|canonical_runtime_shutdown|RUNTIME_SHUTDOWN|flutter .*Back" \
  | grep -vE "remoteIce|iceCandidateHandled|peer:ping" \
  | sed -E 's/\{"ts":"[^"]*","milestone":"[A-Z0-9_]*","layer":"(FL|GO|DB)",//' | cut -c1-210 | head -n ${3:-60}
