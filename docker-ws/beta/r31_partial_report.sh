#!/bin/bash
# Read-only: r31_report.py on the current run while it is still going (iPhone log exported up to now into a temp dir).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); T=$(mktemp -d)/$(basename "$RUN"); mkdir -p "$T"
cp "$RUN/timeline.txt" "$T/"; ln -s "$RUN/android_logcat_live.txt" "$T/android_logcat_live.txt"
xcrun simctl spawn "$UDID" log show --style compact --info --debug --start "$(sed -n 's/^\[\([0-9:]*\)\] R3[0-9] VALIDATE start.*/\1/p' "$RUN/timeline.txt" | head -1 | sed "s/^/$(date +%Y-%m-%d) /")" \
  --predicate 'process == "Runner"' > "$T/ios_log_validate.txt" 2>&1
cp "$T/ios_log_validate.txt" "$RUN/extra/ios_log_partial.txt"
/usr/bin/python3 "$(dirname "$0")/r31_report.py" "$T"
/usr/bin/python3 "$(dirname "$0")/r29_receipts.py" "$T/ios_log_validate.txt"
