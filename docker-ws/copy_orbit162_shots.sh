#!/bin/bash
# Copy the iPhone 11 build-162 Orbit screenshots into Claude-UI's audit folder.
S=/Volumes/CrucialX9/flutter_app/.codex-test-logs/iphone11-162-20261028
D=/Volumes/CrucialX9/flutter_app-ui-update/.audit/orbit-seats/device
mkdir -p "$D" || exit 2
for f in orbit162_rest.png orbit162_spread.png; do
  cp "$S/$f" "$D/$f" && echo "copied $f"
done
ls -la "$D"
