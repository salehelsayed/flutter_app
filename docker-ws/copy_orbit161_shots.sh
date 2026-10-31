#!/bin/bash
# Copy the iPhone 11 build-161 Orbit screenshots into Claude-UI's audit folder.
S=/Volumes/CrucialX9/flutter_app/.codex-test-logs/iphone11-161-photos-20261028
D=/Volumes/CrucialX9/flutter_app-ui-update/.audit/orbit-seats/device
mkdir -p "$D" || exit 2
for f in orbit161photos_11.png orbit161_rest.png orbit161_spread.png orbit161photos_all_11.png; do
  cp "$S/$f" "$D/$f" && echo "copied $f"
done
ls -la "$D"
