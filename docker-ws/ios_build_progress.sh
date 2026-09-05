#!/bin/bash
# Read-only liveness probe for an in-flight iOS build, run ON THE MAC.
# The container's view of the shared checkout lags by minutes, so a "nothing
# changed" answer from inside the container is not evidence of a stall.
cd /Volumes/CrucialX9/flutter_app
echo "now: $(date '+%H:%M:%S')"
echo "=== build processes ==="
ps -eo pid,etime,comm | grep -Ei "xcodebuild|flutter|dart|swift-frontend|clang|ld$" | grep -v grep | head -12
echo "=== files touched under build/ios in the last 3 minutes ==="
find build/ios -type f -newermt '-3 minutes' 2>/dev/null | wc -l
find build/ios -type f -newermt '-3 minutes' 2>/dev/null | tail -5
echo "=== newest build artifacts ==="
ls -lat build/ios/iphoneos 2>/dev/null | head -4
ls -lat build/ios/Release-iphoneos 2>/dev/null | head -4
