#!/bin/bash
# VC-014 read-only: list candidate iOS device Runner.app builds and their CFBundleVersion.
for d in "$HOME"/tmp-dd-device* "$HOME"/tmp-dd-* /Volumes/CrucialX9/flutter_app/build/ios/iphoneos /Volumes/CrucialX9/flutter_app/build/wt-*/build/ios/iphoneos /Volumes/CrucialX9/flutter_app/.codex-test-logs/*158*; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 6 -type d -name 'Runner.app' -path '*iphoneos*' 2>/dev/null | while read -r a; do
    v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$a/Info.plist" 2>/dev/null)
    e=$(/usr/libexec/PlistBuddy -c 'Print :MknoonVoipEnvironment' "$a/Info.plist" 2>/dev/null)
    echo "$v | $(stat -f '%Sm' "$a") | voipenv=$e | $a"
  done
done
