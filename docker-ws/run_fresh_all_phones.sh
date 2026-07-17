#!/bin/bash
# Fresh-identity build + install + launch of the real (non-E2E) mknoon app on
# all 3 phones: every paired USB iPhone (devicectl) and the Pixel (adb).
# Fresh identity = uninstall first; app data/identity DB die with the app.
# Run ON THE MAC (phones plugged in, unlocked, and trusted):
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/run_fresh_all_phones.sh
# Per-device results land in docker-ws/run_fresh_all_phones_result.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
RESULT_FILE="docker-ws/run_fresh_all_phones_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0

# --- 1. Android: defines-free debug APK (real app UX — no E2E gate), arm64 ---
echo "== Building Android debug APK (no dart-defines, arm64)"
APK=build/app/outputs/flutter-apk/app-debug.apk
if ! flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
    || [ ! -f "$APK" ]; then
  note "ANDROID FAILED(build)"; APK=""; FAILED=1
fi

# --- 2. iOS: release app, dev-signed, same define as the ios.device.production profile ---
echo "== Building iOS release app"
APP=build/ios/iphoneos/Runner.app
if ! flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    || [ ! -d "$APP" ]; then
  note "IOS FAILED(build)"; APP=""; FAILED=1
fi

# --- 3. iPhones: uninstall -> install -> launch ---
if [ -n "$APP" ]; then
  JSON=$(mktemp)
  xcrun devicectl list devices --json-output "$JSON" >/dev/null
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
  if [ ${#DEVICES[@]} -eq 0 ]; then
    note "IPHONES FAILED(none-paired — unlock the phones, tap Trust, rerun)"
    FAILED=1
  fi
  for UDID in "${DEVICES[@]}"; do
    echo "== iPhone $UDID: uninstall $BUNDLE_ID (fresh identity)"
    xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE_ID" \
      || echo "   (uninstall failed or app not installed — continuing)"
    echo "== iPhone $UDID: install"
    if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
      note "$UDID FAILED(install)"; FAILED=1; continue
    fi
    echo "== iPhone $UDID: launch"
    if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"; then
      note "$UDID FAILED(launch — is the phone unlocked?)"; FAILED=1; continue
    fi
    note "$UDID OK"
  done
fi

# --- 4. Pixel: uninstall -> install -> launch ---
if [ -n "$APK" ]; then
  SERIAL=$(adb devices | awk 'NR>1 && $2=="device" {print $1; exit}')
  if [ -z "$SERIAL" ]; then
    note "PIXEL FAILED(no authorized adb device)"; FAILED=1
  else
    echo "== Pixel $SERIAL: uninstall $BUNDLE_ID (fresh identity)"
    adb -s "$SERIAL" uninstall "$BUNDLE_ID" \
      || echo "   (uninstall failed or app not installed — continuing)"
    echo "== Pixel $SERIAL: install + launch"
    if ! adb -s "$SERIAL" install "$APK"; then
      note "$SERIAL FAILED(install)"; FAILED=1
    elif ! adb -s "$SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null; then
      note "$SERIAL FAILED(launch)"; FAILED=1
    else
      note "$SERIAL OK"
    fi
  fi
fi

echo "---"
cat "$RESULT_FILE"
exit $FAILED
