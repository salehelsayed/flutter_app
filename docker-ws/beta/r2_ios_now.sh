#!/bin/bash
# Read-only: is the iPhone app running, and what did it log in the last N minutes
# (errors, exceptions, crashes, termination)?
. "$(dirname "$0")/beta_env.sh"
MIN=${1:-6}
echo "now $(date '+%H:%M:%S')"
xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i mknoon || echo "app process: none"
echo "--- crash reports (last 2 h)"
ls -lt ~/Library/Logs/DiagnosticReports 2>/dev/null | grep -i runner | head -5
echo "--- runner log: errors / lifecycle"
xcrun simctl spawn "$UDID" log show --last ${MIN}m --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -iE "exception|error|fatal|crash|terminat|assert|flutter: \[|EXCEPTION|signal|abort|did(Enter|Become)|willTerminate|jetsam" \
  | grep -vE "peer:ping|remoteIce" | cut -c1-230 | tail -${2:-40}
echo "--- springboard/runningboard about the app"
xcrun simctl spawn "$UDID" log show --last ${MIN}m --style compact --predicate 'process == "SpringBoard" OR process == "runningboardd"' 2>/dev/null \
  | grep -i "mknoon" | grep -iE "terminat|exit|crash|kill|launch|foreground|background" | cut -c1-230 | tail -15
