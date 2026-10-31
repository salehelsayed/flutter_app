#!/bin/bash
# Read-only: signing authority and profile type of the release-126 IPA (no secrets).
W="$(cd "$(dirname "$0")/.." && pwd)/build/wt-release-126"
T=$(mktemp -d); unzip -q "$W/build/ios/ipa/mknoon.ipa" -d "$T"
A="$T/Payload/Runner.app"
codesign -dvv "$A" 2>&1 | grep -E '^Authority|^TeamIdentifier'
security cms -D -i "$A/embedded.mobileprovision" > "$T/p.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :Name' "$T/p.plist" 2>/dev/null | sed 's/^/profile_name=/'
/usr/libexec/PlistBuddy -c 'Print :ProvisionedDevices' "$T/p.plist" >/dev/null 2>&1 && echo "provisioned_devices=yes (not App Store)" || echo "provisioned_devices=none (App Store profile)"
rm -rf "$T"
