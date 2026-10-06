#!/bin/bash
# Read-only device inventory on the Mac: adb, booted/available simulators, USB iPhones.
export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:$PATH"
echo "== adb"; adb devices -l | tail -n +2
echo "== emulator avds"; for s in $(adb devices | awk '/^emulator/{print $1}'); do echo "$s $(adb -s $s emu avd name 2>/dev/null | head -1)"; done
echo "== simulators (booted)"; xcrun simctl list devices booted | grep -E "\(" 
echo "== simulators available iPhone (first 12)"; xcrun simctl list devices available | grep -E "iPhone" | head -12
echo "== USB iPhones"; timeout 30 xcrun devicectl list devices 2>/dev/null | grep -iE "iphone" | head
