#!/bin/bash
# Read-only summary of a run_fixed3.sh run: gates, Maestro results, call transitions
# on both devices, back-guard / task channel lines, app process changes.
# Usage: analyze_fixed3.sh [run dir]
. "$(dirname "$0")/beta_env.sh"
RUN="${1:-$(current_run)}"
echo "RUN $RUN"
echo "=== timeline"; cat "$RUN/timeline.txt"
echo "=== maestro results"
for d in "$RUN"/maestro/*/; do
  f=$(grep -oE '<failure[^>]*>[^<]{0,200}' "$d/junit.xml" 2>/dev/null | head -1)
  echo "$(basename "$d"): ${f:-PASS}"
done
EV='"event":"CALL_(STATE_TRANSITION|CONTROL_SIGNAL_SEND_RESULT|TERMINAL_CLEANUP_RESULT|INCOMING_PRESENTATION_RESULT|INCOMING_SIGNAL_NOT_ACCEPTED|SIGNALING_WAKE_RESULT|FOREGROUND_ADMISSION_SETTLEMENT)"'
echo "=== pixel call events"
grep -E "$EV" "$RUN/android_logcat_live.txt" | grep -vE 'remoteIce|iceCandidateHandled' \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}).*"event":"/\1 /; s/","details":/ /' | cut -c1-170
echo "=== pixel back guard / task channel / native call lines"
grep -E "ForegroundCallBackGuard|call_task|moveTaskToBack|CallOwnsBack|MknoonCallAdmission|WM-WorkerWrapper: Starting work for com.mknoon|Impeller opt-out|CALL_ANDROID_[A-Z_]+|BridgeTeardown" "$RUN/android_logcat_live.txt" \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +([0-9]+) +([0-9]+) ([A-Z]) /\1 p\2 t\3 \4 /' | cut -c1-200 | head -60
echo "=== pixel app process starts / deaths"
grep -E "Start proc [0-9]+:com.mknoon.app|Process com.mknoon.app .*has died|Killing [0-9]+:com.mknoon.app|am_proc_died.*com.mknoon" "$RUN/android_logcat_live.txt" | cut -c1-170
if [ -f "$RUN/ios_simulator_log.txt" ]; then
  echo "=== iphone call events"
  grep -oE '"ts":"[^"]+"[^{]*'"$EV"',"details":\{[^}]{0,160}' "$RUN/ios_simulator_log.txt" \
    | grep -vE 'remoteIce|iceCandidateHandled' \
    | sed -E 's/"ts":"2026-09-2[56]T([0-9:.]{12})[^"]*"[^{]*"event":"/\1 /' | cut -c1-200
fi
echo "=== diag files"; for f in "$RUN"/diag_*.txt; do echo "--- $f"; tail -n +3 "$f" | cut -c1-200 | head -40; done
