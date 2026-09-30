#!/bin/bash
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
echo "--- screenshot"; xcrun simctl io "$UDID" screenshot "$RUN/screens/probe_ios.png" 2>&1 | tail -2
echo "--- log stream pid alive?"; ps -p "$(cat "$RUN/ioslog.pid")" -o pid,command | tail -1
echo "--- log show last 3m (Runner)"; xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "Runner"' 2>&1 | wc -l
xcrun simctl spawn "$UDID" log show --last 3m --style compact --predicate 'process == "Runner"' 2>&1 | grep -iE "flutter|FLOW" | head -5
echo "--- app running?"; xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i mknoon | head -3
