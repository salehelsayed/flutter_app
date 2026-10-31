#!/bin/bash
# Screenshot a simulator into the media-bug shots folder.  host-run bash docker-ws/sim_shot.sh <udid> <name>
cd "$(dirname "$0")/.."
xcrun simctl io "$1" screenshot "build/kayan-safe/media-bug/shots/$2.png" 2>&1 | tail -1
