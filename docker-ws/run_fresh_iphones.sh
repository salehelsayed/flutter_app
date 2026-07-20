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

# --- Staleness gate: this script never builds — it REUSES the newest cached
# sims bundle, which can be arbitrarily old. The check is purely against the
# CURRENT WORKING TREE (never commit identity): if any source file is newer
# than the bundle binary, the bundle does not contain the code on disk.
# Deliberate reuse of an old bundle: rerun with ALLOW_STALE=1.
APP_BIN="$APP/Runner"
APP_TS=$(stat -f %m "$APP_BIN")
APP_VER=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP/Info.plist" 2>/dev/null || echo "?")
APP_MARKETING=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null || echo "?")
echo "ARTIFACT version=$APP_MARKETING bundleVersion=$APP_VER built=$(date -r "$APP_TS" '+%Y-%m-%d %H:%M:%S')" | tee -a "$RESULT_FILE"
STALE=""
NEWER_SRC=$(find lib ios/Runner pubspec.yaml pubspec.lock integration_test -type f -newer "$APP_BIN" 2>/dev/null | head -1)
[ -n "$NEWER_SRC" ] && STALE="source newer than bundle (e.g. $NEWER_SRC)"
if [ -n "$STALE" ]; then
  if [ "${ALLOW_STALE:-0}" = "1" ]; then
    echo "WARNING deploying STALE bundle anyway (ALLOW_STALE=1): $STALE" | tee -a "$RESULT_FILE"
  else
    echo "FAILED(stale-artifact: $STALE — rebuild via sims @prepare-build ios.device.production, or ALLOW_STALE=1 to force)" | tee -a "$RESULT_FILE"
    exit 1
  fi
fi

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
  # Verify the install actually took: installed bundleVersion must match the
  # artifact we just pushed (see deploy_all_phones.sh for the same pattern).
  JSONAPPS=$(mktemp)
  GOT="?"
  if xcrun devicectl device info apps --device "$UDID" --json-output "$JSONAPPS" >/dev/null 2>&1; then
    GOT=$(python3 - "$JSONAPPS" "$BUNDLE_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for a in data.get("result", {}).get("apps", []):
    if a.get("bundleIdentifier") == sys.argv[2]:
        print(a.get("bundleVersion", "?")); break
else:
    print("not-installed")
PY
)
  fi
  if [ "$APP_VER" != "?" ] && [ "$GOT" != "$APP_VER" ]; then
    echo "$UDID FAILED(verify: installed bundleVersion '$GOT' != artifact '$APP_VER')" >> "$RESULT_FILE"; FAILED=1; continue
  fi
  echo "$UDID OK bundleVersion=$GOT (verified)" >> "$RESULT_FILE"
done

echo "---"
cat "$RESULT_FILE"
exit $FAILED
