#!/bin/bash
# Read-only: confirm the translate-preview pieces landed in build 165 (frameworks, entitlements, defines).
A="$HOME/tmp-dd-161/Build/Products/Release-iphoneos/Runner.app"
echo "bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist") minOS=$(/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "$A/Info.plist")"
ls "$A/Frameworks" | grep -iE "edge|litert|gemma|ai" | head
echo "--- entitlements"; codesign -d --entitlements :- "$A" 2>/dev/null | grep -iE "memory|virtual|aps-environment" -A1 | head -10
echo "--- translate define in snapshot"; LC_ALL=C grep -a -c "GEMMA_PREVIEW" "$A/Frameworks/App.framework/App"
