#!/bin/bash
# Resolve SPM packages for build/wt-final128i into the internal-disk device DerivedData and show the WebRTC artifact.
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd /Volumes/CrucialX9/flutter_app/build/wt-final128i || exit 2
xcodebuild -resolvePackageDependencies -workspace ios/Runner.xcworkspace -scheme Runner -derivedDataPath "$HOME/tmp-dd-device" 2>&1 | grep -v '^$' | grep -i -E "webrtc|artifact|error|fail|resolved" | head -30
echo "resolve exit=${PIPESTATUS[0]}"
ls -la "$HOME/tmp-dd-device/SourcePackages/artifacts/" "$HOME/tmp-dd-device/SourcePackages/artifacts/flutter_webrtc-1.6.0/WebRTC" 2>&1 | head
