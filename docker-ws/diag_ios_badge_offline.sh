#!/bin/bash
# Diagnostic (non-destructive): rebuild the SAME iOS release app under test but
# with --dart-define=FDC_FLOW_LOG=1, which production_application_bootstrap.dart
# uses to force flowEventLoggingEnabled=true + synchronous debugPrint in a
# release build. Installs IN PLACE (no uninstall — identity/app data survive) on
# both iPhones so the Dart-side [FLOW] events behind the "Offline" badge become
# visible. Run on the Mac via host-run.
set -uo pipefail
cd "$(dirname "$0")/.."

BUNDLE_ID=com.mknoon.app
IPHONE_UDIDS="00008030-001A6D2801BB802E 00008110-00184D622289801E"
RESULT="docker-ws/diag_ios_badge_offline_result.txt"
: > "$RESULT"
note() { echo "$*" | tee -a "$RESULT"; }
FAILED=0

if command -v timeout >/dev/null 2>&1; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi

RUN_STAMP=$(date +%y%m%d%H%M%S)
GIT_SHA=$(git rev-parse --short HEAD)
BUILD_NAME="1.0.0-${GIT_SHA}.flowlog.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
note "DIAG PROVENANCE sha=$GIT_SHA build_name=$BUILD_NAME bundle_version=$RUN_STAMP define=FDC_FLOW_LOG=1 date=$(date '+%Y-%m-%d %H:%M:%S')"

APP=build/ios/iphoneos/Runner.app
if ! flutter build ios --release --target=lib/main.dart \
    --dart-define=PRODUCTION_APNS=true \
    --dart-define=FDC_FLOW_LOG=1 \
    --build-name="1.0.0" --build-number="$RUN_STAMP" \
    || [ ! -d "$APP" ]; then
  note "IOS FAILED(build)"; exit 1
fi
if [ ! "$APP/Runner" -nt "$FRESH_MARK" ]; then
  note "IOS FAILED(stale-artifact)"; exit 1
fi
GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
if [ "${GO_SYMS:-0}" -lt 1 ]; then
  note "IOS FAILED(binary-gate: Go bridge not linked)"; exit 1
fi

for UDID in $IPHONE_UDIDS; do
  echo "== iPhone $UDID: install (in place, data kept)"
  if ! TO 300 xcrun devicectl device install app --device "$UDID" "$APP"; then
    note "$UDID FAILED(install)"; FAILED=1; continue
  fi
  note "$UDID OK installed bundleVersion=$RUN_STAMP (data kept)"
done

echo "---"; cat "$RESULT"
exit $FAILED
