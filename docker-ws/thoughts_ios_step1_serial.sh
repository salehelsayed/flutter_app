#!/bin/bash
# Thoughts branch step 1 with low parallelism (call under with_native_lease.py): Flutter config only, then xcodebuild
# with 1 job and the arm64 simulator slice only (full parallel builds lose SwiftCompile steps silently after the
# 10-26 Mac restart), then RunnerTests with the same limits.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/thoughts_ios_step1_serial.sh <tree under build/> <evidence dir under repo>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/${1:?tree}"; E="$REPO/${2:?evidence}"; mkdir -p "$E"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
H="--dart-define=MKNOON_UPDATE_CHECK=off --dart-define=MKNOON_RELAY_ADDRESSES=/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM"
{
  echo "start $(date -u +%T) head=$(git rev-parse HEAD)"
  bash scripts/ensure_go_ios_bindings.sh; echo "bindings exit=$?"
  flutter build ios --simulator --debug --config-only --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=FDC_FLOW_LOG=1 $H; echo "config exit=$?"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Debug -sdk iphonesimulator \
    -destination 'generic/platform=iOS Simulator' -jobs 1 ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
    -derivedDataPath build/ios-dd-lowjobs build; echo "build exit=$? $(date -u +%T)"
} > "$E/ios_build_serial.log" 2>&1
B=$(grep -oE 'build exit=[0-9]+' "$E/ios_build_serial.log" | tail -1); echo "$B"
[ "$B" = "build exit=0" ] || { grep -c 'exit code 0 but produced' "$E/ios_build_serial.log" | sed 's/^/silent_compile_failures=/'; echo "STEP1 BUILD FAILED"; exit 3; }
A=$(find build/ios-dd-lowjobs/Build/Products -maxdepth 2 -name Runner.app -path '*iphonesimulator*' | head -1); echo "app=$A"
echo "go_runtime=$(LC_ALL=C grep -a -c 'runtime.main' "$A/Runner.debug.dylib" 2>/dev/null) nse=$(ls -d "$A/PlugIns/"*.appex 2>/dev/null | wc -l | tr -d ' ')"
SIM_ID=$(xcrun simctl list devices available | grep -E 'iPhone' | head -1 | grep -oE '[0-9A-F-]{36}')
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination "platform=iOS Simulator,id=$SIM_ID" \
  CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -jobs 1 ONLY_ACTIVE_ARCH=YES ARCHS=arm64 \
  -derivedDataPath build/ios-dd-lowjobs -only-testing:RunnerTests > "$E/runner_tests.log" 2>&1; rc=$?
echo "runner_tests exit=$rc"; grep -E 'Executed [0-9]+ test|TEST (SUCCEEDED|FAILED)|testThoughtTextStaysHidden' "$E/runner_tests.log" | tail -4
exit $rc
