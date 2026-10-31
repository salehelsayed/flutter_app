#!/bin/bash
# Read-only: list WebDriverAgent and RunnerUITests runner .app builds on the Mac with modification times and signing authority.
#   host-run bash docker-ws/ios13_runner_stamps.sh
for d in "$HOME/Library/Developer/Xcode/DerivedData" /Volumes/CrucialX9/flutter_app/build /Volumes/CrucialX9/mac-development "$HOME/.appium"; do
  [ -d "$d" ] || continue
  find "$d" -maxdepth 9 -type d \( -name 'WebDriverAgentRunner-Runner.app' -o -name 'RunnerUITests-Runner.app' \) -path '*iphoneos*' 2>/dev/null
done | while read -r a; do
  m=$(stat -f '%Sm' -t '%Y-%m-%dT%H:%M:%S' "$a")
  auth=$(codesign -dvv "$a" 2>&1 | grep -m1 '^Authority=' | cut -c1-60)
  team=$(codesign -dvv "$a" 2>&1 | grep -m1 '^TeamIdentifier=')
  echo "$m | $auth | $team | ${a#/Volumes/CrucialX9/}"
done | sort | tail -25
date '+now local %Y-%m-%dT%H:%M:%S %Z'
exit 0
