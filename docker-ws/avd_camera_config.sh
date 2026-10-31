#!/bin/bash
# Read-only: print hw.camera.* lines of one AVD config.ini.
#   host-run bash docker-ws/avd_camera_config.sh <avd>
d=$(sed -n "s/^path=//p" "$HOME/.android/avd/${1:?avd}.ini"); grep -E "^hw\.camera" "$d/config.ini"
