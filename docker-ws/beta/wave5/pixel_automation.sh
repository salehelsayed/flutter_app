#!/bin/bash
# Read-only: automation processes on the Pixel 6 (Maestro driver, uiautomator, Appium).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s 21071FDF600CSC shell ps -A 2>/dev/null | grep -iE "maestro|uiautomator|appium|instrument" | head
adb -s 21071FDF600CSC shell dumpsys activity instrumentation 2>/dev/null | grep -iE "ActiveInstrumentation|ComponentInfo" | head -5
