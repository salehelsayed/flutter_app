#!/bin/bash
# Read-only: WebDriverAgent / Appium / Maestro processes on the Mac with start time and parent chain, plus the iPhone
# 15 simulator's installed Mknoon build.
. "$(dirname "$0")/beta_env.sh"
for p in $(ps -axo pid=,command= | grep -E 'WebDriverAgent|appium|maestro' | grep -v grep | awk '{print $1}' | head -12); do
  echo "== $p"; q=$p
  while [ -n "$q" ] && [ "$q" != 1 ] && [ "$q" != 0 ]; do
    ps -o pid=,ppid=,lstart=,command= -p "$q" | cut -c1-230; q=$(ps -o ppid= -p "$q" | tr -d ' ')
  done
done
echo "installed ios: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null)"
