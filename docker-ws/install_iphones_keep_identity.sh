#!/bin/bash
# Install the already-built build/ios/iphoneos/Runner.app on iPhone 11 + 13
# WITHOUT uninstalling first (identity, contacts and call state are kept), then
# launch and verify bundleVersion. Falls back to resign_and_install_iphones.sh
# on the recurring Flutter.framework code-seal break (that script also keeps
# identity: it never uninstalls). Results: docker-ws/install_iphones_keep_identity_result.txt
set -uo pipefail
cd "$(dirname "$0")/.."
BUNDLE_ID=com.mknoon.app
APP=build/ios/iphoneos/Runner.app
IPHONE_UDIDS="${IPHONE_UDIDS:-00008030-001A6D2801BB802E 00008110-00184D622289801E}"
RESULT_FILE="docker-ws/install_iphones_keep_identity_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0
if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi
[ -d "$APP" ] || { note "FAILED(no built app at $APP)"; exit 1; }
RUN_STAMP=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
BUILD_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")
note "ARTIFACT $BUILD_NAME bundleVersion=$RUN_STAMP"
NEED_RESIGN=0
for UDID in $IPHONE_UDIDS; do
  if ! TO 45 xcrun devicectl device info details --device "$UDID" >/dev/null 2>&1; then
    note "$UDID FAILED(unreachable)"; FAILED=1; continue
  fi
  echo "== iPhone $UDID: install (keep identity)"
  if ! TO 300 xcrun devicectl device install app --device "$UDID" "$APP"; then
    note "$UDID FAILED(install)"; NEED_RESIGN=1; continue
  fi
  echo "== iPhone $UDID: launch"
  TO 90 xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID" \
    || { note "$UDID FAILED(launch — unlocked?)"; FAILED=1; continue; }
  JSONAPPS=$(mktemp); GOT="?"
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
  if [ "$GOT" = "$RUN_STAMP" ]; then note "$UDID OK $BUILD_NAME bundleVersion=$RUN_STAMP (verified)"; else note "$UDID FAILED(verify: '$GOT' != '$RUN_STAMP')"; FAILED=1; fi
done
if [ "$NEED_RESIGN" = 1 ]; then
  echo "== install failed on an iPhone: re-signing and retrying via resign_and_install_iphones.sh"
  docker-ws/resign_and_install_iphones.sh; RC=$?
  cat docker-ws/resign_and_install_iphones_result.txt >> "$RESULT_FILE"
  [ "$RC" -eq 0 ] || FAILED=1
fi
echo "---"; cat "$RESULT_FILE"; exit $FAILED
