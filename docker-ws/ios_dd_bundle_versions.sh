#!/bin/bash
# Read-only: for each ~/tmp-dd-* DerivedData folder, print the Release-iphoneos Runner.app bundle version, relay mode and date.
#   host-run bash docker-ws/ios_dd_bundle_versions.sh
for d in "$HOME"/tmp-dd-*; do
  A="$d/Build/Products/Release-iphoneos/Runner.app"
  [ -d "$A" ] || continue
  v=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist" 2>/dev/null)
  h=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c 'sslip.io')
  echo "$(basename "$d") bundle=$v hetzner_strings=$h modified=$(stat -f %Sm -t %m-%dT%H:%M "$A")"
done
