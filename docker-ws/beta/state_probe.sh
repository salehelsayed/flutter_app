#!/bin/bash
# Read-only snapshot: emulator + app process, logcat capture liveness, sim app.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
echo "now: $(date '+%H:%M:%S')"
echo "--- emulator"; $ADB get-state 2>&1; $ADB shell pidof $PKG 2>&1 | sed 's/^/app pid: /'
echo "--- logcat capture pid $(cat "$RUN/logcat.pid") alive: $(ps -p "$(cat "$RUN/logcat.pid")" >/dev/null && echo yes || echo no)"
ls -la "$RUN"/android_logcat_live_*.txt | awk '{print $5, $6, $7, $8, $9}'
tail -1 "$RUN"/android_logcat_live_*.txt | cut -c1-120
echo "--- android call events since 00:13 (live buffer)"
$ADB logcat -d -v time | grep -E '"event":"CALL_STATE_TRANSITION' | awk '$2>="00:13:50"' | sed -E 's/.*"details"://' | tail -8
echo "--- ios app"; xcrun simctl spawn "$UDID" launchctl list 2>/dev/null | grep -i mknoon
xcrun simctl spawn "$UDID" log show --last 12m --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E '"event":"CALL_STATE_TRANSITION' | sed -E 's/.*"ts":"[0-9-]+T([0-9:.]{12}).*"details":/\1 /' | tail -8
