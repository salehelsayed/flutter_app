#!/bin/bash
# Read-only: where the 406 device-proof emulators live, and what the OLD (AliceOld) app build is.
for a in Pixel_7 Pixel_8 Pixel_6a; do echo "== $a: $(cat $HOME/.android/avd/$a.ini 2>/dev/null | tr '\n' ' ')"; done
ls -la /Volumes/CrucialX9/AndroidAVDs/ 2>/dev/null | head
ls /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406/ | head -40
echo "mac: $(sysctl -n vm.loadavg) $(sysctl -n vm.swapusage | cut -c1-60)"
