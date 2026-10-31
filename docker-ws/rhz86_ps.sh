#!/bin/bash
# relay-hz-86b786747 read-only: show my capture/appium processes and the iPhone 13 devicectl state.
for p in "$@"; do ps -ww -o pid=,etime=,args= -p "$p" | cut -c1-200 || echo "$p gone"; done
echo "--- appium/idevicesyslog/logcat ---"
ps -axo pid=,etime=,args= | grep -E "appium --port|idevicesyslog|adb .*logcat|qemu-system" | grep -v grep | cut -c1-160
echo "--- devicectl ---"
timeout 60 xcrun devicectl list devices 2>/dev/null | grep -iE 'iphone' | sed -E 's/[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}/<id>/g' | cut -c1-140
