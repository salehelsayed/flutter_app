#!/bin/bash
# Read-only: what Android emulators exist on the Mac and which are running?
echo "=== adb devices ==="
adb devices
echo "=== avdmanager / emulator binaries ==="
for c in "$HOME/Library/Android/sdk/emulator/emulator" "$HOME/Library/Android/sdk/cmdline-tools/latest/bin/avdmanager"; do
  [ -x "$c" ] && echo "found: $c"
done
echo "=== AVDs ==="
"$HOME/Library/Android/sdk/emulator/emulator" -list-avds 2>/dev/null || echo "(emulator binary not found)"
