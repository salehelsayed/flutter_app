#!/bin/bash
# Read-only B5 evidence from the current run: Maestro results, every native presentation /
# outgoing registration result, how long Telecom took to register each call (core-telecom
# addCall start -> the presentation result), and crashes/ANRs.
. "$(dirname "$0")/beta_env.sh"
RUN="${1:-$(current_run)}"; L="$RUN/android_logcat_live.txt"
echo "RUN $RUN"
echo "--- maestro"
for d in "$RUN"/maestro/*/; do
  f=$(grep -oE '<failure[^>]*>[^<]{0,160}' "$d/junit.xml" 2>/dev/null | head -1)
  printf '%s: %s\n' "$(basename "$d")" "${f:-PASS}"
done
echo "--- Telecom registrations (addCall start -> result)"
grep -E "CallsManager: addCall: pausing|MKNOON_CALL_PRESENTATION_DIAG result=|CALL_CONTROL_SIGNAL_SEND_RESULT.*\"type\":\"invite\"|CALL_ANDROID_DISCONNECT source=|native_lifecycle_failed" "$L" \
  | sed -E 's/^[0-9-]+ ([0-9:.]{12}) +[0-9]+ +[0-9]+ [A-Z] /\1 /' | cut -c1-150
echo "--- crashes / ANRs / B7"
echo "FATAL: $(grep -c 'FATAL EXCEPTION' "$L")  ANR: $(grep -c 'ANR in com.mknoon' "$L")  handler_exception: $(grep -c handler_exception "$L")"
