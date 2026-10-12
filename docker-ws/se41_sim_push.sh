#!/bin/bash
# SE-41: send a simulated content-available update_check push to the Debug simulator
# build from se41_xctest.sh and show the [SE41_UPDATE_CHECK] lines. Usage: host-run bash docker-ws/se41_sim_push.sh [bg|fg]
set -u
MODE="${1:-bg}"
REPO="$(cd "$(dirname "$0")/.." && pwd)"
APP="$REPO/build/se41-xctest/derived/Build/Products/Debug-iphonesimulator/Runner.app"
OUT="$REPO/build/se41-sim-push"
mkdir -p "$OUT"
sim="$(xcrun simctl list devices booted -j | python3 -c '
import json, sys
d = json.load(sys.stdin)["devices"]
c = [v["udid"] for k, vs in d.items() if "iOS" in k for v in vs if v["name"].startswith("iPhone")]
print(c[0] if c else "")')"
[ -n "$sim" ] || { echo "no booted iPhone simulator"; exit 2; }
echo "simulator=$sim"
xcrun simctl install "$sim" "$APP" || { echo "install failed"; exit 1; }
xcrun simctl launch "$sim" com.mknoon.app || { echo "launch failed"; exit 1; }
sleep 20
pid=$(xcrun simctl spawn "$sim" launchctl list | grep -i "mknoon" | awk '{print $1}' | head -1)
echo "app pid after launch: ${pid:-none}"
[ "$MODE" = bg ] && xcrun simctl launch "$sim" com.apple.Preferences >/dev/null
sleep 3
cat > "$OUT/payload.json" <<'JSON'
{"Simulator Target Bundle":"com.mknoon.app","aps":{"content-available":1},"type":"update_check","gcm.message_id":"0:se41-sim","google.c.sender.id":"1","from":"/topics/update_check"}
JSON
xcrun simctl push "$sim" com.mknoon.app "$OUT/payload.json"
sleep 15
xcrun simctl spawn "$sim" log show --last 2m --style compact \
  --predicate 'eventMessage CONTAINS "SE41_UPDATE_CHECK" OR eventMessage CONTAINS "PUSH_DIAG" OR (process == "Runner" AND eventMessage CONTAINS[c] "notification")' \
  > "$OUT/log.txt" 2>&1
tail -20 "$OUT/log.txt"
pid=$(xcrun simctl spawn "$sim" launchctl list | grep -i "mknoon" | awk '{print $1}' | head -1)
echo "app pid at end: ${pid:-none}"
