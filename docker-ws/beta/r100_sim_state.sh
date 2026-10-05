#!/bin/bash
# Read-only: one simulator's state, installed user apps and running app processes.
#   r100_sim_state.sh <udid>
U=$1
xcrun simctl list devices | grep "$U"
echo "-- user apps:"; xcrun simctl listapps "$U" 2>/dev/null | grep -E '"CFBundleIdentifier"' | grep -v "com.apple" | head -10
echo "-- running (launchctl):"; xcrun simctl spawn "$U" launchctl list 2>/dev/null | grep -i "UIKitApplication" | grep -v "com.apple" | head -10
