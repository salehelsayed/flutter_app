#!/bin/bash
# Read-only: call events of both phones inside one scenario window, plus native lines.
# Usage: windows_full4.sh <local HH:MM:SS> <local HH:MM:SS> [run dir]
# The Pixel logs local time; the iPhone "ts" is UTC (Mac local = UTC+2 on 2026-09-26).
. "$(dirname "$0")/beta_env.sh"
A=$1; B=$2; RUN="${3:-$(current_run)}"
ua=$(date -j -v-2H -f %H:%M:%S "$A" +%H:%M:%S); ub=$(date -j -v-2H -f %H:%M:%S "$B" +%H:%M:%S)
EV='"event":"CALL_(STATE_TRANSITION|CONTROL_SIGNAL_SEND_RESULT|TERMINAL_CLEANUP_RESULT|INCOMING_PRESENTATION_RESULT|INCOMING_SIGNAL_NOT_ACCEPTED|SIGNALING_WAKE_RESULT|FOREGROUND_ADMISSION_SETTLEMENT)"'
echo "=== pixel $A-$B"
awk -v a="$A" -v b="$B" 'substr($2,1,8)>=a && substr($2,1,8)<=b' "$RUN/android_logcat_live.txt" \
  | grep -E "$EV|HeadlessCallAdmission|release_deferred|Starting work for com.mknoon|Impeller opt-out|CALL_ANDROID_[A-Z_]+|MknoonCallWake|ForegroundCallBackGuard|moveTaskToBack|onTaskRemoved|BridgeTeardown|handler_exception|appShutdown" \
  | grep -vE 'remoteIce|iceCandidateHandled' \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +[0-9]+ +[0-9]+ [A-Z] /\1 /; s/[^ ]*"event":"/ /; s/","details":/ /' | cut -c1-200
echo "=== iphone $ua-$ub UTC"
grep -oE '"ts":"[^"]+"[^{]*'"$EV"',"details":\{[^}]{0,170}' "$RUN/ios_simulator_log.txt" \
  | grep -vE 'remoteIce|iceCandidateHandled' \
  | sed -E 's/"ts":"2026-09-2[5-7]T([0-9:.]{12})[^"]*"[^{]*"event":"/\1 /' \
  | awk -v a="$ua" -v b="$ub" 'substr($1,1,8)>=a && substr($1,1,8)<=b' | cut -c1-200
