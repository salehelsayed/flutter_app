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

# --- 0. Build provenance: git SHA stamped into versionName (verifiable via
# dumpsys / devicectl) + freshness gate refusing silently-reused artifacts.
# Dev-environment rule: we always build the CURRENT WORKING TREE. The sha/dirty
# suffix is a descriptive label only — no build or verify step depends on commit
# identity. Verification checks the per-run timestamp, so every deploy run
# (including dirty rebuilds at the same commit) is distinct and verifiable.
GIT_SHA=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
RUN_STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}"
[ "$GIT_DIRTY" != "0" ] && BUILD_NAME="${BUILD_NAME}.d${GIT_DIRTY}"
BUILD_NAME="${BUILD_NAME}.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
# iOS sanitizes CFBundleShortVersionString to digits/dots — CFBundleVersion
# (numeric run timestamp) carries iOS provenance; Android versionName keeps the
# readable label; Android versionCode deliberately untouched (E2E install safety).
note "PROVENANCE tree=current-working-tree sha=$GIT_SHA branch=$GIT_BRANCH dirty_files=$GIT_DIRTY build_name=$BUILD_NAME ios_bundle_version=$RUN_STAMP date=$(date '+%Y-%m-%d %H:%M:%S')"

# --- 1. Android: defines-free debug APK (real app UX — no E2E gate), arm64 ---
echo "== Building Android debug APK (no dart-defines, arm64)"
APK=build/app/outputs/flutter-apk/app-debug.apk
if ! flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
    --build-name="$BUILD_NAME" \
    || [ ! -f "$APK" ]; then
  note "ANDROID FAILED(build)"; APK=""; FAILED=1
elif [ ! "$APK" -nt "$FRESH_MARK" ]; then
  note "ANDROID FAILED(stale-artifact: $APK predates this build run)"; APK=""; FAILED=1
fi

# --- 2. iOS: release app, dev-signed, same define as the ios.device.production profile ---
echo "== Building iOS release app"
APP=build/ios/iphoneos/Runner.app
if ! flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --build-name="$BUILD_NAME" --build-number="$RUN_STAMP" \
    || [ ! -d "$APP" ]; then
  note "IOS FAILED(build)"; APP=""; FAILED=1
elif [ ! "$APP/Runner" -nt "$FRESH_MARK" ]; then
  note "IOS FAILED(stale-artifact: $APP/Runner predates this build run)"; APP=""; FAILED=1
fi

# Binary-content gate: if ios/Runner/GoMknoon.xcframework was missing at
# pod-install time, the Podfile silently drops the GoMknoon pod and
# `#if canImport(GoMknoon)` compiles the whole bridge out — the build SUCCEEDS
# but every bridge call fails on device ("Failed to generate identity",
# 2026-07-19). The linked Go library is ~tens of MB; a bridge-less Runner is
# under 1 MB and has no Bridge symbols.
if [ -n "$APP" ]; then
  # Raw grep, not `strings`: macOS llvm-strings misses this literal in the
  # linked Runner (0 hits on a healthy 33MB binary, 2026-07-21 false-negative).
  GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
  if [ "${GO_SYMS:-0}" -lt 1 ]; then
    note "IOS FAILED(binary-gate: Go bridge not linked into Runner — run 'cd ios && pod install' [restores GoMknoon pod] and rebuild)"; APP=""; FAILED=1
  fi
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
  # ${DEVICES[@]+...}: macOS bash 3.2 + set -u aborts on expanding an empty
  # array, which killed the script here and silently skipped the Pixel phase.
  for UDID in ${DEVICES[@]+"${DEVICES[@]}"}; do
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
    if [ "$GOT" = "$RUN_STAMP" ]; then
      note "$UDID OK $BUILD_NAME bundleVersion=$RUN_STAMP (verified)"
    else
      note "$UDID FAILED(verify: installed bundleVersion '$GOT' != built '$RUN_STAMP')"; FAILED=1
    fi
  done
fi

# --- 4. Pixel: uninstall -> install -> launch ---
if [ -n "$APK" ]; then
  SERIAL=$(adb devices | awk 'NR>1 && $2=="device" && $1 !~ /^emulator-/ {print $1; exit}')
  if [ -z "$SERIAL" ]; then
    note "PIXEL FAILED(no authorized physical adb device)"; FAILED=1
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
      GOT=$(adb -s "$SERIAL" shell dumpsys package "$BUNDLE_ID" | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
      if [ "$GOT" = "$BUILD_NAME" ]; then
        note "$SERIAL OK $BUILD_NAME (verified)"
      else
        note "$SERIAL FAILED(verify: installed '$GOT' != built '$BUILD_NAME')"; FAILED=1
      fi
    fi
  fi
fi

echo "---"
cat "$RESULT_FILE"
if [ "$FAILED" -ne 0 ]; then
  echo "!!! STALE-BUILD RISK: every FAILED device above may still be running an OLD commit."
fi
exit $FAILED
