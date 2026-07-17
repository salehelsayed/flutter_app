#!/bin/bash
# Fresh-identity install + launch of the mknoon app on USB-connected iPhones.
# Run this ON THE MAC (phones plugged in, unlocked, and trusted):
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_fresh_iphones.sh [UDID ...]
# With no arguments it targets every paired iPhone devicectl can see.
# Writes per-device results to docker-ws/run_fresh_iphones_result.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
RESULT_FILE="docker-ws/run_fresh_iphones_result.txt"
: > "$RESULT_FILE"

APP=$(ls -td build/sims/cache/ios.device.production/*/ios.device.production.bundle/TestProducts/Release-iphoneos/Runner.app 2>/dev/null | head -1)
if [ ! -d "$APP" ]; then
  echo "ERROR: no ios.device.production Runner.app found under build/sims/cache" | tee -a "$RESULT_FILE"
  exit 1
fi
echo "Using app: $APP"

JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null

if [ $# -gt 0 ]; then
  DEVICES=("$@")
else
  DEVICES=($(python3 - "$JSON" <<'PY'
import json, sys
seen = set()
data = json.load(open(sys.argv[1]))
for d in data.get("result", {}).get("devices", []):
    hw = d.get("hardwareProperties") or {}
    conn = d.get("connectionProperties") or {}
    name = (d.get("deviceProperties") or {}).get("name", "?")
    udid = hw.get("udid") or d.get("identifier")
    if hw.get("deviceType") == "iPhone" and conn.get("pairingState") == "paired" and udid not in seen:
        seen.add(udid)
        print(udid)
        print(f"  {name}  {udid}", file=sys.stderr)
PY
))
fi

if [ ${#DEVICES[@]} -eq 0 ]; then
  echo "ERROR: no paired iPhones found — unlock the phones, tap Trust, retry" | tee -a "$RESULT_FILE"
  exit 1
fi
echo "Target iPhones: ${DEVICES[*]}"

FAILED=0
for UDID in "${DEVICES[@]}"; do
  echo "== $UDID: uninstall $BUNDLE_ID (fresh identity)"
  xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE_ID" \
    || echo "   (uninstall failed or app not installed — continuing)"
  echo "== $UDID: install"
  if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
    echo "$UDID FAILED(install)" >> "$RESULT_FILE"; FAILED=1; continue
  fi
  echo "== $UDID: launch"
  if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"; then
    echo "$UDID FAILED(launch — is the phone unlocked?)" >> "$RESULT_FILE"; FAILED=1; continue
  fi
  echo "$UDID OK" >> "$RESULT_FILE"
done

echo "---"
cat "$RESULT_FILE"
exit $FAILED
