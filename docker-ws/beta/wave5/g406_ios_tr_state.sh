#!/bin/bash
# Is the test-relay iOS build still running, and what did it produce?
date
ps -axo pid,etime,%cpu,command | grep -E "g406_build_testrelay|flutter_tools.snapshot build ios|xcodebuild -workspace|ensure_go_ios|gomobile bind" | grep -v grep | cut -c1-150 | head -8
A=/Volumes/CrucialX9/flutter_app/build/ios/iphoneos/Runner.app
echo "Runner mtime: $(stat -f %Sm "$A/Runner" 2>&1)  bundleVersion=$(defaults read "$A/Info.plist" CFBundleVersion 2>&1)  bridge=$(grep -c BridgeGenerateIdentity "$A/Runner" 2>&1)"
