#!/bin/bash
# Repair + install for the recurring iOS code-seal break: the SDK's original
# Flutter.framework/Info.plist gets copied back over the framework AFTER
# codesign sealed it, so devicectl install dies with
# ApplicationVerificationFailed 0xe8008001 ("Failed to verify code signature of
# .../Frameworks/Flutter.framework"). It is NOT a credential problem.
# Re-signs the framework, then the app (that order — re-signing the framework
# invalidates the outer bundle), verifies, then installs + launches on the
# active iOS fleet. NO rebuild: uses the already-built Runner.app as is.
# Results land in docker-ws/resign_and_install_iphones_result.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
APP=build/ios/iphoneos/Runner.app
SIGN_ID="Apple Development: Saleh Elsayed (QGRWQ86DP5)"
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"
RESULT_FILE="docker-ws/resign_and_install_iphones_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0

if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi

[ -d "$APP" ] || { note "FAILED(no built app at $APP — run a build first)"; exit 1; }

# The run timestamp built into this artifact is the verify key.
RUN_STAMP=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null)
BUILD_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null)
note "ARTIFACT $APP bundleVersion=$RUN_STAMP shortVersion=$BUILD_NAME runner_mtime=$(stat -f %Sm "$APP/Runner" 2>/dev/null || stat -c %y "$APP/Runner")"

# Binary-content gate: a bridge-less Runner installs fine but every Go bridge
# call fails on device, so keep it here too.
GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
if [ "${GO_SYMS:-0}" -lt 1 ]; then
  note "FAILED(binary-gate: Go bridge not linked into Runner)"; exit 1
fi

echo "== pre-check: codesign --verify"
xcrun codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5

echo "== re-sign Flutter.framework"
if ! xcrun codesign --force --preserve-metadata=identifier,entitlements,flags \
    --sign "$SIGN_ID" "$APP/Frameworks/Flutter.framework"; then
  note "FAILED(resign framework)"; exit 1
fi
echo "== re-sign $APP (must follow the framework)"
if ! xcrun codesign --force --preserve-metadata=identifier,entitlements,flags \
    --sign "$SIGN_ID" "$APP"; then
  note "FAILED(resign app)"; exit 1
fi
echo "== post-check: codesign --verify"
if ! xcrun codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -5; then
  note "FAILED(codesign verify still invalid after re-sign)"; exit 1
fi

for UDID in $IPHONE_UDIDS; do
  echo "== iPhone $UDID: reachability check"
  if ! TO 45 xcrun devicectl device info details --device "$UDID" >/dev/null 2>&1; then
    note "$UDID FAILED(unreachable — plug in + unlock + trust)"; FAILED=1; continue
  fi
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
    note "$UDID OK bundleVersion=$RUN_STAMP (verified)"
  else
    note "$UDID FAILED(verify: installed bundleVersion '$GOT' != built '$RUN_STAMP')"; FAILED=1
  fi
done

echo "---"
cat "$RESULT_FILE"
exit $FAILED
