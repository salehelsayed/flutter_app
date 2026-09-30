#!/bin/bash
# Read-only: whole-run counts for fixes A, B, C and bug B7, from both phones' logs.
. "$(dirname "$0")/beta_env.sh"
RUN="${1:-$(current_run)}"
L="$RUN/android_logcat_live.txt"; I="$RUN/ios_simulator_log.txt"
echo "--- A: headless admission worker runs / second engine starts during calls"
echo "worker runs: $(grep -c 'Starting work for com.mknoon.app.call.HeadlessCallAdmissionWorker' "$L")"
echo "worker outcomes: $(grep -oE 'CALL_ANDROID_ADMISSION event=[a-z_]+' "$L" | sort | uniq -c | tr '\n' ';')"
echo "headless finish lines: $(grep -oE 'HeadlessCallAdmission[A-Za-z]*: [^ ]+ [^ ]+ [^ ]+' "$L" | sort | uniq -c | head -5 | tr '\n' ';')"
echo "engine starts (Impeller opt-out line) at: $(grep 'Impeller opt-out' "$L" | awk '{print $2}' | cut -c1-8 | tr '\n' ' ')"
echo "--- B: refused incoming call signals (route/outcome/reason)"
for f in "$L" "$I"; do
  echo "$(basename "$f"):"
  grep -oE 'CALL_INCOMING_SIGNAL_NOT_ACCEPTED.{0,12}"details":\{[^}]*' "$f" \
    | grep -oE '"route":"[a-z]+".*"reason":"[a-z_A-Z]+"' | sed -E 's/"signal":"[a-z]+",//' | sort | uniq -c
done
echo "--- C: call wake parse lines"
grep -E 'CALL_ANDROID_WAKE_PARSE' "$L" | sed -E 's/^[0-9-]+ ([0-9:.]{12}).*CALL_ANDROID_WAKE_PARSE/\1/' | cut -c1-120 | head -10
echo "--- B7: handler_exception"
grep -c 'handler_exception' "$L" "$I"
echo "--- app crashes / ANRs on the Pixel during the run"
grep -cE 'FATAL EXCEPTION|ANR in com.mknoon' "$L"
