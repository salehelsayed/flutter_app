#!/bin/bash
# Run the two approved AWS pre-publish lanes in sequence on the given tree: <evid-rel> <tree>
E="${1:?evid}"; T="${2:?tree}"; M=/Volumes/CrucialX9/flutter_app; L="$M/$E/lanes.txt"
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for c in device-group-mute device-notifications-android; do
  echo "== $c battery=$(adb -s 21071FDF600CSC shell dumpsys battery | awk '/level/{print $2}') $(date -u +%TZ)" >> "$L"
  bash "$M/docker-ws/aws_campaigns.sh" "$c" "$E" "$T" >> "$L" 2>&1
  echo "== $c done rc=$? $(date -u +%TZ)" >> "$L"
done
echo "ALL DONE $(date -u +%TZ)" >> "$L"
