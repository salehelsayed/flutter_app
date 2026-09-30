#!/bin/bash
# Stops the log capture of the current run.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
for f in logcat.pid ioslog.pid; do
  [ -f "$RUN/$f" ] && kill "$(cat "$RUN/$f")" 2>/dev/null && echo "stopped $f"
done
xcrun simctl spawn "$UDID" log show --style compact --info --debug \
  --start "$(cat "$RUN/ios_log_start.txt")" --predicate 'process == "Runner"' \
  > "$RUN/ios_simulator_log.txt" 2>&1
echo "ios log lines: $(wc -l < "$RUN/ios_simulator_log.txt")"
ls -la "$RUN"
