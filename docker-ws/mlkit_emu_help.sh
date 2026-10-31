#!/bin/bash
# Read-only: emulator help topics for camera modes.
E="$HOME/Library/Android/sdk/emulator/emulator"
"$E" -help-camera-back 2>&1 | head -40
"$E" -help-all 2>&1 | grep -i -E "imagefile|environment|camera" | head -20
