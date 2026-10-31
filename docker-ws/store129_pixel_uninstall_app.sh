#!/bin/bash
# Pixel 6 only (Pixel wipe approved for the 129 AWS lanes): remove com.mknoon.app so the lanes' app-state guard
# sees "not installed" instead of a non-debuggable release it cannot snapshot.
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
adb -s 21071FDF600CSC uninstall com.mknoon.app; adb -s 21071FDF600CSC shell pm list packages com.mknoon.app | tr -d '\r'
