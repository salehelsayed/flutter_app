#!/bin/bash
# Copy the iPhone 11 build-163 Orbit screenshots into Claude-UI's audit folder.
S=/Volumes/CrucialX9/flutter_app/.codex-test-logs/iphone11-163-20261028
D=/Volumes/CrucialX9/flutter_app-ui-update/.audit/orbit-seats/device
mkdir -p "$D" || exit 2
for f in orbit163_rest.png; do
  cp "$S/$f" "$D/$f" && echo "copied $f"
done
ls -la "$D"
