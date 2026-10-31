#!/bin/bash
# Read-only screenshot of one iPhone via libimobiledevice.  host-run bash docker-ws/ios_screenshot.sh <udid> <out-path-in-repo>
command -v idevicescreenshot >/dev/null || { echo "no idevicescreenshot"; ls /opt/homebrew/bin | grep -i idevice; exit 3; }
timeout 30 idevicescreenshot -u "$1" "$2" 2>&1
