#!/bin/bash
# Read-only: flutter_webrtc SPM binary target definition, global SwiftPM artifact cache, tree Package.resolved diff.
P="$HOME/.pub-cache/hosted/pub.dev/flutter_webrtc-1.6.0/ios/flutter_webrtc"
ls -la "$P"; echo "--- Package.swift"; cat "$P/Package.swift"
echo "--- global artifacts cache"; ls -la "$HOME/Library/Caches/org.swift.swiftpm/artifacts" 2>&1 | head -20
echo "--- tree diff"; cd /Volumes/CrucialX9/flutter_app/build/wt-final128i && git diff --stat && git diff ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved | head -40
