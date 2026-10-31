#!/bin/bash
# Read-only: is the Pixel / iPhone visible on USB, and to adb / devicectl?
system_profiler SPUSBDataType 2>/dev/null | grep -iE 'Pixel|iPhone|Google' | sed 's/^ *//' | sort -u
echo "== adb"; "$HOME/Library/Android/sdk/platform-tools/adb" devices | tail -n +2
echo "== devicectl"; timeout 30 xcrun devicectl list devices 2>/dev/null | grep -iE 'iPhone' | sed -E 's/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/<id>/g' | cut -c1-120
