#!/bin/bash
# Read-only liveness probe for an in-flight iOS build, run ON THE MAC.
# The container's view of the shared checkout lags by minutes, so a "nothing
# changed" answer from inside the container is not evidence of a stall.
cd /Volumes/CrucialX9/flutter_app
echo "now: $(date '+%H:%M:%S')"
echo "=== build processes ==="
# Only real compile/link work counts as busy. A bare `dart`/`flutter`
# match caught long-lived analyzer and test processes under the SDK and
# hung every wait loop built on this probe (2026-09-05 21:07-21:18Z).
ps -eo pid,etime,comm | grep -Ei "xcodebuild|swift-frontend|clang|ld$|Xcode.app" | grep -v grep | head -12
echo "=== files touched under build/ios in the last 3 minutes ==="
find build/ios -type f -newermt '-3 minutes' 2>/dev/null | wc -l
find build/ios -type f -newermt '-3 minutes' 2>/dev/null | tail -5
echo "=== newest build artifacts ==="
ls -lat build/ios/iphoneos 2>/dev/null | head -4
ls -lat build/ios/Release-iphoneos 2>/dev/null | head -4
