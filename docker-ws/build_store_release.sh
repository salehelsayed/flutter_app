#!/bin/bash
# Build BOTH store artifacts from the current tree:
#   iOS  -> build/ios/ipa/*.ipa            (App Store Connect / TestFlight)
#   Play -> build/app/outputs/bundle/release/app-release.aab
# Version comes from pubspec.yaml (version: x.y.z+BUILD). Both stores reject a
# build number that does not increase, so bump pubspec BEFORE running this.
# Results land in docker-ws/build_store_release_result.txt.
#
# Unlike the device deploy scripts, this does NOT stamp a git sha into the
# version: store builds must carry the exact pubspec version the stores expect.
# Provenance is recorded in the result file instead.
set -uo pipefail
cd "$(dirname "$0")/.."

RESULT_FILE="docker-ws/build_store_release_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }
FAILED=0

VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION%%+*}"
BUILD_NUMBER="${VERSION##*+}"
GIT_SHA=$(git rev-parse --short HEAD)
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
FRESH_MARK=$(mktemp)

note "PROVENANCE version=$VERSION name=$VERSION_NAME build=$BUILD_NUMBER sha=$GIT_SHA branch=$GIT_BRANCH dirty_files=$GIT_DIRTY date=$(date '+%Y-%m-%d %H:%M:%S')"
if [ "$GIT_DIRTY" != "0" ]; then
  note "WARNING dirty tree ($GIT_DIRTY files) — store artifacts will not match any commit exactly"
fi

# --- Android App Bundle (Play) ---
# Release signing comes from android/key.properties; the gradle config throws a
# clear error if it is missing, so a debug-signed bundle can never reach Play.
echo "== Building Android App Bundle (release)"
AAB=build/app/outputs/bundle/release/app-release.aab
if ! flutter build appbundle --release --target=lib/main.dart || [ ! -f "$AAB" ]; then
  note "PLAY FAILED(build)"; AAB=""; FAILED=1
elif [ ! "$AAB" -nt "$FRESH_MARK" ]; then
  note "PLAY FAILED(stale-artifact: $AAB predates this build run)"; AAB=""; FAILED=1
else
  note "PLAY OK $AAB ($(du -m "$AAB" | cut -f1) MB) versionName=$VERSION_NAME versionCode=$BUILD_NUMBER"
fi

# --- iOS IPA (App Store Connect / TestFlight) ---
# PRODUCTION_APNS mirrors the ios.device.production sims profile so the store
# build is the same compile as the device builds. Nothing in lib/ reads it
# today; aps-environment=production in Runner.entitlements is what actually
# selects the production APNs environment.
echo "== Building iOS App Store IPA (release)"
if ! scripts/build_ios_appstore_ipa.sh --dart-define=PRODUCTION_APNS=true; then
  note "IOS FAILED(build)"; FAILED=1
else
  IPA=$(find build/ios/ipa -maxdepth 1 -type f -name '*.ipa' 2>/dev/null | head -1)
  if [ -z "$IPA" ]; then
    note "IOS FAILED(no .ipa produced)"; FAILED=1
  elif [ ! "$IPA" -nt "$FRESH_MARK" ]; then
    note "IOS FAILED(stale-artifact: $IPA predates this build run)"; FAILED=1
  else
    # Binary-content gate: a missing GoMknoon.xcframework at pod-install time
    # makes the Podfile drop the pod and `#if canImport(GoMknoon)` compile the
    # whole bridge out. The build SUCCEEDS and the upload succeeds; every
    # bridge call then fails on testers' phones.
    #
    # Do NOT gate on exported symbol NAMES here. The device scripts grep for
    # "BridgeGenerateIdentity", which works on a dev-signed Runner, but the
    # App Store archive is symbol-stripped: on 2026-08-29 a healthy 28.8MB
    # archive had 0 hits for BridgeGenerateIdentity/GoMknoon while carrying the
    # full Go runtime. Gate on the Go RUNTIME markers instead — they live in
    # read-only data and survive stripping. A bridge-less Runner has no Go
    # runtime at all (and is under 1MB), so this still catches the real defect.
    ARCH_RUNNER=build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/Runner
    if [ -f "$ARCH_RUNNER" ]; then
      GO_RT=$(grep -c "go1\." "$ARCH_RUNNER" 2>/dev/null || true)
      GO_MAIN=$(grep -c "runtime\.main" "$ARCH_RUNNER" 2>/dev/null || true)
      GO_SYMS=$(grep -c "BridgeGenerateIdentity" "$ARCH_RUNNER" 2>/dev/null || true)
      if [ "${GO_RT:-0}" -lt 1 ] || [ "${GO_MAIN:-0}" -lt 1 ]; then
        note "IOS FAILED(binary-gate: no Go runtime in archive — bridge compiled out; run 'cd ios && pod install' and rebuild)"; FAILED=1
      else
        note "IOS OK $IPA ($(du -m "$IPA" | cut -f1) MB) version=$VERSION_NAME build=$BUILD_NUMBER bridge-linked (go-runtime=yes, stripped-symbol-names=$GO_SYMS)"
      fi
    else
      note "IOS OK $IPA ($(du -m "$IPA" | cut -f1) MB) version=$VERSION_NAME build=$BUILD_NUMBER (bridge gate SKIPPED — no xcarchive)"
    fi
  fi
fi

echo "---"
cat "$RESULT_FILE"
exit $FAILED
