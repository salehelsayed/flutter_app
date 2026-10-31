#!/bin/bash
# Terminate the Camera app on the iPhone 11 by exact PID after a path check (left open by a harness swipe).
#   host-run bash docker-ws/ios11_terminate_camera.sh <pid>
U=00008030-001A6D2801BB802E; P="$1"
[[ "$P" =~ ^[0-9]+$ ]] || { echo "bad pid"; exit 2; }
timeout 90 /usr/bin/xcrun devicectl device info processes --device "$U" 2>&1 | grep -E "^$P +.*/Camera\.app/Camera *$" >/dev/null || { echo "pid $P is not Camera.app"; exit 3; }
timeout 90 /usr/bin/xcrun devicectl device process terminate --device "$U" --pid "$P" 2>&1 | tail -2
