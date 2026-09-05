#!/bin/bash
# iOS release build identical to run_fresh_three_phones.sh's iOS leg, plus
# --dart-define=FDC_FLOW_LOG=1 so Dart [FLOW] events reach the iPhone syslog
# (release builds otherwise gate flowEventLoggingEnabled on kDebugMode).
# Diagnostic build for call debugging; install with install_iphones_keep_identity.sh.
set -uo pipefail
cd "$(dirname "$0")/.."
GIT_SHA=$(git rev-parse --short HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}.d${GIT_DIRTY}.flowlog.t${STAMP}"
echo "PROVENANCE sha=$GIT_SHA dirty=$GIT_DIRTY build_name=$BUILD_NAME bundle_version=$STAMP"
APP=build/ios/iphoneos/Runner.app
# Go binding freshness: the GoMknoon Pod copies the xcframework slice while the
# Pods project builds, BEFORE the Runner target's ensure phase can rebuild it,
# so a changed go-mknoon source links one build late. Refresh first.
scripts/ensure_go_ios_bindings.sh || { echo "IOS FAILED(go bindings)"; exit 1; }
flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --dart-define=FDC_FLOW_LOG=1 \
    --build-name="$BUILD_NAME" --build-number="$STAMP" || { echo "IOS FAILED(build)"; exit 1; }
GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || true)
[ "${GO_SYMS:-0}" -ge 1 ] || { echo "IOS FAILED(binary-gate: Go bridge not linked)"; exit 1; }
echo "IOS BUILT $BUILD_NAME bundleVersion=$STAMP"
