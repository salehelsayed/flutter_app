#!/bin/bash
# Fresh-identity build + install + launch of the real (non-E2E) mknoon app on
# EXACTLY three phones: iPhone 11, iPhone 13 (explicit UDID allowlist — never
# touches other paired iPhones) and the Pixel. Fresh identity = uninstall first.
# Derived from run_fresh_all_phones.sh (provenance stamp, freshness gate,
# binary gate, post-install verify). Run on the Mac (or via host-run).
# Per-device results land in docker-ws/run_fresh_three_phones_result.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
RESULT_FILE="docker-ws/run_fresh_three_phones_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0

# Explicit targets (chip-prefix map: 00008030=iPhone 11, 00008110=iPhone 13)
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"
PIXEL_SERIAL=21071FDF600CSC

# Optional: --flowlog adds --dart-define=FDC_FLOW_LOG=1 to the iOS release
# build so Dart [FLOW] events reach the iPhone syslog (release builds gate
# flowEventLoggingEnabled on kDebugMode; the Android debug APK logs anyway).
IOS_FLOW_LOG=""
for arg in ${1+"$@"}; do
  case "$arg" in
    --flowlog) IOS_FLOW_LOG="--dart-define=FDC_FLOW_LOG=1" ;;
    *) echo "unknown argument: $arg (supported: --flowlog)" >&2; exit 2 ;;
  esac
done

# Wrap devicectl in timeout when available (zombie-tunnel hangs must not
# block later phases); macOS may lack GNU timeout.
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi

# --- 0. Build provenance (current working tree; run timestamp is the verify key)
GIT_SHA=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
RUN_STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}"
[ "$GIT_DIRTY" != "0" ] && BUILD_NAME="${BUILD_NAME}.d${GIT_DIRTY}"
BUILD_NAME="${BUILD_NAME}.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
note "PROVENANCE tree=current-working-tree sha=$GIT_SHA branch=$GIT_BRANCH dirty_files=$GIT_DIRTY build_name=$BUILD_NAME ios_bundle_version=$RUN_STAMP ios_flow_log=${IOS_FLOW_LOG:-off} date=$(date '+%Y-%m-%d %H:%M:%S')"

# --- 1. Android: debug APK (real app UX — no E2E gate; voice-call gates from tool/build/voice_call_release_defines.json), arm64 ---
echo "== Building Android debug APK (voice-call gates on, arm64)"
APK=build/app/outputs/flutter-apk/app-debug.apk
if ! flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
    --dart-define-from-file=tool/build/voice_call_release_defines.json --android-project-arg=enableAndroidNativeCalls=true \
    --build-name="$BUILD_NAME" \
    || [ ! -f "$APK" ]; then
  note "ANDROID FAILED(build)"; APK=""; FAILED=1
elif [ ! "$APK" -nt "$FRESH_MARK" ]; then
  note "ANDROID FAILED(stale-artifact: $APK predates this build run)"; APK=""; FAILED=1
fi

# --- 2. iOS: release app, dev-signed, same define as ios.device.production ---
echo "== Building iOS release app"
APP=build/ios/iphoneos/Runner.app
# Go binding freshness: the GoMknoon Pod copies the xcframework slice while the
# Pods project builds, BEFORE the Runner target's ensure phase can rebuild it,
# so a changed go-mknoon source links one build late. Refresh first.
scripts/ensure_go_ios_bindings.sh || { echo "IOS FAILED(go bindings)"; exit 1; }
if ! flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
    $IOS_FLOW_LOG \
    --build-name="$BUILD_NAME" --build-number="$RUN_STAMP" \
    || [ ! -d "$APP" ]; then
  note "IOS FAILED(build)"; APP=""; FAILED=1
elif [ ! "$APP/Runner" -nt "$FRESH_MARK" ]; then
  note "IOS FAILED(stale-artifact: $APP/Runner predates this build run)"; APP=""; FAILED=1
fi

# Binary-content gate: missing GoMknoon.xcframework at pod-install time means
# the bridge is silently compiled out — build succeeds, every bridge call fails.
if [ -n "$APP" ]; then
  # Raw grep, not `strings`: macOS llvm-strings misses this literal in the
  # linked Runner (0 hits on a healthy 33MB binary, 2026-07-21 false-negative).
  GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
  if [ "${GO_SYMS:-0}" -lt 1 ]; then
    note "IOS FAILED(binary-gate: Go bridge not linked into Runner — run 'cd ios && pod install' and rebuild)"; APP=""; FAILED=1
  fi
fi

# --- 3. iPhones (allowlist only): reachability -> uninstall -> install -> launch -> verify ---
if [ -n "$APP" ]; then
  for UDID in $IPHONE_UDIDS; do
    echo "== iPhone $UDID: reachability check"
    if ! TO 45 xcrun devicectl device info details --device "$UDID" >/dev/null 2>&1; then
      note "$UDID FAILED(unreachable — not enumerating on USB or tunnel dead; plug in + unlock + trust)"; FAILED=1; continue
    fi
    echo "== iPhone $UDID: uninstall $BUNDLE_ID (fresh identity)"
    TO 120 xcrun devicectl device uninstall app --device "$UDID" "$BUNDLE_ID" \
      || echo "   (uninstall failed or app not installed — continuing)"
    echo "== iPhone $UDID: install"
    if ! TO 300 xcrun devicectl device install app --device "$UDID" "$APP"; then
      note "$UDID FAILED(install)"; FAILED=1; continue
    fi
    echo "== iPhone $UDID: launch"
    if ! TO 90 xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"; then
      note "$UDID FAILED(launch — is the phone unlocked?)"; FAILED=1; continue
    fi
    JSONAPPS=$(mktemp)
    GOT="?"
    if TO 90 xcrun devicectl device info apps --device "$UDID" --json-output "$JSONAPPS" >/dev/null 2>&1; then
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

# --- 4. Pixel (pinned serial): uninstall -> install -> launch -> verify ---
if [ -n "$APK" ]; then
  if ! adb devices | awk -v s="$PIXEL_SERIAL" '$1==s && $2=="device" {found=1} END {exit !found}'; then
    note "PIXEL $PIXEL_SERIAL FAILED(not attached/authorized via adb)"; FAILED=1
  else
    echo "== Pixel $PIXEL_SERIAL: uninstall $BUNDLE_ID (fresh identity)"
    adb -s "$PIXEL_SERIAL" uninstall "$BUNDLE_ID" \
      || echo "   (uninstall failed or app not installed — continuing)"
    echo "== Pixel $PIXEL_SERIAL: install + launch"
    if ! adb -s "$PIXEL_SERIAL" install "$APK"; then
      note "$PIXEL_SERIAL FAILED(install)"; FAILED=1
    elif ! adb -s "$PIXEL_SERIAL" shell monkey -p "$BUNDLE_ID" -c android.intent.category.LAUNCHER 1 >/dev/null; then
      note "$PIXEL_SERIAL FAILED(launch)"; FAILED=1
    else
      GOT=$(adb -s "$PIXEL_SERIAL" shell dumpsys package "$BUNDLE_ID" | grep -m1 versionName | sed 's/.*versionName=//' | tr -d '\r ')
      if [ "$GOT" = "$BUILD_NAME" ]; then
        note "$PIXEL_SERIAL OK $BUILD_NAME (verified)"
      else
        note "$PIXEL_SERIAL FAILED(verify: installed '$GOT' != built '$BUILD_NAME')"; FAILED=1
      fi
    fi
  fi
fi

echo "---"
cat "$RESULT_FILE"
if [ "$FAILED" -ne 0 ]; then
  echo "!!! STALE-BUILD RISK: every FAILED device above may still be running an OLD build."
fi
exit $FAILED
