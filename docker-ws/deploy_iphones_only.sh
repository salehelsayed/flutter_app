#!/bin/bash
# iPhone-only phase of the 2026-07-21 fresh deploy: the already-built
# build/ios/iphoneos/Runner.app (verified bridge-linked from the container) is
# installed fresh on iPhone 11 + iPhone 12. No builds. Also diagnoses why the
# Mac-side `strings` binary gate false-negatived.
# Results append to docker-ws/run_fresh_three_phones_result.txt.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
RESULT_FILE="docker-ws/run_fresh_three_phones_result.txt"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0

BUILD_NAME="1.0.0-8204bae9b.d3.t260721200327"
RUN_STAMP="260721200327"
# iPhone 11 already deployed+verified 2026-07-21; iPhone 12 unreachable on USB
# (ecid-1011) — user redirected the third slot to the iPhone 13.
IPHONE_UDIDS="00008110-00184D622289801E"
APP=build/ios/iphoneos/Runner.app

if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi

# --- 0. Diagnose the false-negative binary gate (read-only) ---
echo "== gate diagnosis"
echo "   command -v strings: $(command -v strings || echo MISSING)"
echo "   strings|grep -ci: $(strings "$APP/Runner" 2>&1 | grep -ci 'BridgeGenerateIdentity')"
echo "   xcrun strings|grep -ci: $(xcrun strings "$APP/Runner" 2>&1 | grep -ci 'BridgeGenerateIdentity')"
echo "   grep -c (raw): $(grep -c 'BridgeGenerateIdentity' "$APP/Runner" 2>&1 || true)"
echo "   Runner size: $(du -m "$APP/Runner" | cut -f1) MB, mtime: $(stat -f %Sm "$APP/Runner" 2>/dev/null || stat -c %y "$APP/Runner")"

# --- 1. iPhones: reachability -> uninstall -> install -> launch -> verify ---
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
    note "$UDID OK $BUILD_NAME bundleVersion=$RUN_STAMP (verified, bridge-linked)"
  else
    note "$UDID FAILED(verify: installed bundleVersion '$GOT' != built '$RUN_STAMP')"; FAILED=1
  fi
done

echo "---"
cat "$RESULT_FILE"
exit $FAILED
