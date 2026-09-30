#!/bin/bash
# Export the iOS simulator app log for a time window into the current run dir.
# Usage: ios_log_window.sh "<start YYYY-mm-dd HH:MM:SS>" "<end>" <label>
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); mkdir -p "$RUN/windows"
xcrun simctl spawn "$UDID" log show --style compact --info --debug \
  --start "$1" --end "$2" --predicate 'process == "Runner"' \
  > "$RUN/windows/${3}_ios.txt" 2>&1
wc -l "$RUN/windows/${3}_ios.txt"
