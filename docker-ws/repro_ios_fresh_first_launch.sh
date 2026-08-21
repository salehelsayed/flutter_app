#!/bin/bash
# Repro: capture the FIRST launch after uninstall+install on ONE iPhone, with
# syslog running the whole time, to see whether the app finds a Keychain-resident
# identity that the freshly-created app DB knows nothing about — and what the
# connection badge does on that first run.
# Reuses the already-built FDC_FLOW_LOG=1 Runner.app. Run on the Mac via host-run.
#   ./docker-ws/repro_ios_fresh_first_launch.sh <udid>
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR/.."
UDID="${1:?usage: repro_ios_fresh_first_launch.sh <udid>}"
BUNDLE_ID=com.mknoon.app
APP=build/ios/iphoneos/Runner.app
OUT="$DIR/repro_first_launch_${UDID:0:8}.txt"
SYSLOG_BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"

[ -d "$APP" ] || { echo "MISSING $APP"; exit 1; }

echo "== starting syslog capture -> $OUT"
"$SYSLOG_BIN" -u "$UDID" > "$OUT" 2>&1 &
SYSPID=$!
sleep 5

echo "== uninstall (app container + DB destroyed; iOS Keychain is NOT reached by this)"
xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE_ID" || echo "   (not installed)"
sleep 3
echo "== install"
xcrun devicectl device install app --device "$UDID" "$APP" || { kill $SYSPID; exit 1; }
echo "== FIRST launch after wipe"
xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" || true

echo "== observing 75s"
sleep 75
kill $SYSPID 2>/dev/null
sleep 1
echo "== capture done"
wc -l "$OUT"
