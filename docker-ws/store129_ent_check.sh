#!/bin/bash
# Read-only: print the increased-memory-limit entitlement of the 129 IPA's app (PlistBuddy handles dotted keys).
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-translate-129; T=$(mktemp -d)
unzip -q -o "$W/build/ios/ipa/mknoon.ipa" -d "$T"; APP=$(find "$T/Payload" -maxdepth 1 -name '*.app' | head -1)
codesign -d --entitlements :- "$APP" 2>/dev/null > "$T/ent.plist"
echo "increased-memory-limit=$(/usr/libexec/PlistBuddy -c 'Print :com.apple.developer.kernel.increased-memory-limit' "$T/ent.plist" 2>&1)"
echo "keys=$(/usr/libexec/PlistBuddy -c 'Print' "$T/ent.plist" | grep -c ' = ')"
rm -rf "$T"
