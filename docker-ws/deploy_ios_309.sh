#!/bin/bash
# Plan 309 re-land STAGE 2b: iOS client (NSE archived guards) to exactly the
# two app-carrying iPhones — 13 (93B4C4D0…) and 11 (5763A494…). Deliberately
# NOT deploy_all_phones.sh: that targets every paired iPhone, including the
# 17 Pro Max which carries no app. In-place update, data kept, binary-gated.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
RESULT_FILE="docker-ws/deploy_ios_309_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0
DEVICES=("93B4C4D0-F4B7-50F6-B130-0A7578BA4E9E" "5763A494-757C-5B37-AC70-3AA2775FBEFF")

GIT_SHA=$(git rev-parse --short HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
RUN_STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}"
[ "$GIT_DIRTY" != "0" ] && BUILD_NAME="${BUILD_NAME}.d${GIT_DIRTY}"
BUILD_NAME="${BUILD_NAME}.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
note "PROVENANCE sha=$GIT_SHA dirty_files=$GIT_DIRTY build_name=$BUILD_NAME ios_bundle_version=$RUN_STAMP date=$(date '+%Y-%m-%d %H:%M:%S')"

APP=build/ios/iphoneos/Runner.app
if ! flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --build-name="$BUILD_NAME" --build-number="$RUN_STAMP" \
    || [ ! -d "$APP" ]; then
  note "IOS FAILED(build)"; exit 1
elif [ ! "$APP/Runner" -nt "$FRESH_MARK" ]; then
  note "IOS FAILED(stale-artifact)"; exit 1
fi

# Binary-content gate (GoMknoon silent-drop landmine): raw grep, never strings.
GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
if [ "${GO_SYMS:-0}" -lt 1 ]; then
  note "IOS FAILED(binary-gate: Go bridge not linked into Runner)"; exit 1
fi
note "binary-gate OK (BridgeGenerateIdentity hits=$GO_SYMS)"

ios_installed_bundle_version() {
  local json; json=$(mktemp)
  xcrun devicectl device info apps --device "$1" --json-output "$json" >/dev/null 2>&1 || { echo "?"; return; }
  python3 - "$json" "$BUNDLE_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
for app in data.get("result", {}).get("apps", []):
    if app.get("bundleIdentifier") == sys.argv[2]:
        print(app.get("bundleVersion", "?"))
        break
else:
    print("?")
PY
}

for UDID in "${DEVICES[@]}"; do
  echo "== iPhone $UDID: install (update in place, data kept)"
  if ! xcrun devicectl device install app --device "$UDID" "$APP"; then
    note "$UDID FAILED(install — unlocked and reachable?)"; FAILED=1; continue
  fi
  if ! xcrun devicectl device process launch --device "$UDID" --terminate-existing "$BUNDLE_ID"; then
    note "$UDID FAILED(launch — is the phone unlocked?)"; FAILED=1; continue
  fi
  GOT=$(ios_installed_bundle_version "$UDID")
  if [ "$GOT" = "$RUN_STAMP" ]; then
    note "$UDID OK $BUILD_NAME bundleVersion=$RUN_STAMP (verified)"
  else
    note "$UDID FAILED(verify: installed bundleVersion '$GOT' != built '$RUN_STAMP')"; FAILED=1
  fi
done
[ "$FAILED" -eq 0 ] && note "STAGE2B PASS" || { note "STAGE2B FAILED"; exit 1; }
