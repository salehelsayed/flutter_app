#!/bin/bash
# Read-only: list Android AVD names and running emulator serials.
"$HOME/Library/Android/sdk/emulator/emulator" -list-avds 2>/dev/null
echo "--- running"
"$HOME/Library/Android/sdk/platform-tools/adb" devices 2>/dev/null | awk '/^emulator-/{print $1, $2}'
