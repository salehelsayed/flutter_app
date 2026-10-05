#!/bin/bash
# Read-only: attached Android devices/emulators (with model and AVD) and iOS physical devices / booted simulators.
export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
echo "== adb"
for d in $(adb devices | awk 'NR>1 && $2=="device" {print $1}'); do
  m=$(adb -s "$d" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
  a=$(adb -s "$d" emu avd name 2>/dev/null | head -1 | tr -d '\r')
  echo "$d | $m | ${a:-physical}"
done
echo "== iOS physical (devicectl)"
timeout 40 xcrun devicectl list devices 2>/dev/null | grep -v -E "^-|^Name" | cut -c1-140 | head -10
echo "== booted simulators"
xcrun simctl list devices booted 2>/dev/null | grep -E "Booted" | head
