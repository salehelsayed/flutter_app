#!/bin/bash
# Read-only: emulator network + app connection state.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run)
echo "now: $(date '+%H:%M:%S')  emulator clock: $($ADB shell date '+%H:%M:%S')"
$ADB shell settings get global airplane_mode_on | sed 's/^/airplane: /'
$ADB shell dumpsys connectivity 2>/dev/null | grep -E "Active default network|NetworkAgentInfo.*(WIFI|CELLULAR).*CONNECTED" | head -3 | cut -c1-160
$ADB shell ping -c 2 -W 2 mknoun.xyz 2>&1 | tail -2
echo "--- app status badge"
timeout 90 maestro --device "$SERIAL" hierarchy 2>/dev/null | grep -oE '"accessibilityText" : "(online|offline|Connecting|connecting)[^"]*"' | head -3
echo "--- recent node/relay lines"
grep -E '"event":"(NODE_STATUS|RELAY_[A-Z_]*|P2P_(NODE|RELAY)[A-Z_]*|CONNECTIVITY[A-Z_]*)"' "$RUN/android_logcat_live.txt" | tail -6 | sed -E 's/.*"ts":"[0-9-]+T([0-9:.]{12})[^"]*".*"event":"/\1 /' | cut -c1-160
