#!/bin/bash
ps -axo pid,ppid,etime,pcpu,command | grep -E "build ipa|build_ios_appstore|build_store_release|xcodebuild|flutter_tools" | grep -v grep | cut -c1-230
echo ---; ls -la --time-style=+%T /Volumes/CrucialX9/flutter_app/build/ios/archive/Runner.xcarchive /Volumes/CrucialX9/flutter_app/build/ios/ipa 2>&1 | tail -8
