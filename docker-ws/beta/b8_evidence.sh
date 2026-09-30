#!/bin/bash
# Read-only B8 evidence from the current run: timeline, Maestro results, the call
# events around the kill/relaunch, main-thread stalls of the app after the relaunch,
# and crashes/ANRs.
. "$(dirname "$0")/beta_env.sh"
RUN="${1:-$(current_run)}"; L="$RUN/android_logcat_live.txt"
echo "RUN $RUN"
echo "--- timeline"; grep -vE "start |end   ready_" "$RUN/timeline.txt" | cut -c1-150
echo "--- maestro"
for d in "$RUN"/maestro/*/; do
  f=$(grep -oE '<failure[^>]*>[^<]{0,160}' "$d/junit.xml" 2>/dev/null | head -1)
  printf '%s: %s\n' "$(basename "$d")" "${f:-PASS}"
done
echo "--- native call lines around R1 (presentation, process start/death, re-registration, answer)"
grep -E "MKNOON_CALL_PRESENTATION_DIAG|CallsManager: addCall|Start proc [0-9]+:com.mknoon.app|Process com.mknoon.app .*has died|am_kill|CALL_ANDROID_ANSWER|CALL_ANDROID_DISCONNECT|\"trigger\":\"(remoteInvite|nativeAction|mediaConnected|remoteTerminate)\"" "$L" \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +([0-9]+) +([0-9]+) [A-Z] /\1 p\2 t\3 /' | cut -c1-170 | head -40
echo "--- main-thread stalls reported by the app (Choreographer)"
grep -E "Choreographer.*Skipped [0-9]+ frames" "$L" | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +([0-9]+) +([0-9]+) [A-Z] /\1 p\2 /' | cut -c1-140 | tail -8
echo "--- crashes / ANRs"
echo "FATAL: $(grep -c 'FATAL EXCEPTION' "$L")  ANR: $(grep -c 'ANR in com.mknoon' "$L")"
