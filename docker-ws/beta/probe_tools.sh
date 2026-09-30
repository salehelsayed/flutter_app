#!/bin/bash
export PATH="$HOME/.maestro/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
for t in appium idb idb_companion maestro node npm java; do printf "%s: " $t; command -v $t || echo missing; done
appium driver list --installed 2>&1 | tail -5
ls ~/.appium 2>/dev/null | head
ls ~/Library/Developer/Xcode/DerivedData 2>/dev/null | grep -i WebDriverAgent | head
ls "$HOME/development" 2>/dev/null
xcrun simctl list devices booted
