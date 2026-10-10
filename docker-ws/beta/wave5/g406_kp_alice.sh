#!/bin/bash
# Killed-app push to AliceH (emulator-5554) from BobH, Hetzner test relay build.
/Users/I560101/Library/Android/sdk/platform-tools/adb -s emulator-5556 shell cmd statusbar collapse; sleep 8
PEER_B=12D3KooWMgBCGvZV2Tm1MVgqtTDcYHb6uc73uQsNCqoX9LY8EYte KILL_ON=emulator-5554 SEND_ON=emulator-5556 bash /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406_killed_push_p.sh
