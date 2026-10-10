#!/bin/bash
ps -axo pid,ppid,etime,pcpu,command | awk '$2!=1' | grep -E "build ipa|build_ios_appstore|build_store_release|release122" | grep -v grep | cut -c1-160
echo ---; ps -axo ppid,command | awk '$1==1' | grep -c "build ipa"
ls -la -T /Volumes/CrucialX9/flutter_app/build/ios/archive/Runner.xcarchive 2>&1 | head -3; ls -la -T /Volumes/CrucialX9/flutter_app/build/ios/ipa 2>&1 | tail -3
