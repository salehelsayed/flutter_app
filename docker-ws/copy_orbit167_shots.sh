#!/bin/bash
# Copy the iPhone 11 build-167 Orbit screenshots into Claude-UI's audit folder.
S=/Volumes/CrucialX9/flutter_app/.codex-test-logs/iphone11-167-20261029
D=/Volumes/CrucialX9/flutter_app-ui-update/.audit/orbit-seats/device
mkdir -p "$D" || exit 2
for f in orbit167_rest.png; do
  cp "$S/$f" "$D/$f" && echo "copied $f"
done
ls -la "$D"
