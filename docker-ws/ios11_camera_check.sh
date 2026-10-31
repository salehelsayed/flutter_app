#!/bin/bash
# Read-only: is the Camera app process running on the iPhone 11?
#   host-run bash docker-ws/ios11_camera_check.sh
timeout 90 /usr/bin/xcrun devicectl device info processes --device 00008030-001A6D2801BB802E 2>&1 | grep -iE 'Camera.app|camera' | head -5
echo "checked $(date -u +%TZ)"
