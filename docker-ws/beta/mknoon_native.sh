#!/bin/bash
# Read-only: native (non-Dart) app lines and app process starts in this run.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
grep -E "Mknoon|MainActivity|call_task|CallBridge|BridgeTeardown" "$RUN/android_logcat_live.txt" | grep -v '\[FLOW\]' | cut -c1-220 | head -40
echo "--- process start"; grep -E "Start proc [0-9]+:com.mknoon.app" "$RUN/android_logcat_live.txt" | cut -c1-160
