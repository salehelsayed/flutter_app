#!/bin/bash
# Boot the Pixel_7 AVD ("AliceOld", OLD build from the plan-406 device proof), data kept, window visible.
. "$(dirname "$0")/../beta_env.sh"
if "$ANDROID_HOME/platform-tools/adb" devices | grep -q emulator-5560; then echo "already running"; exit 0; fi
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/emulator/emulator" -avd Pixel_7 -port 5560 \
  -no-snapshot-load -no-boot-anim > /Volumes/CrucialX9/flutter_app/artifacts/beta-20261008/logs/emu_pixel7.log 2>&1 < /dev/null &
A="$ANDROID_HOME/platform-tools/adb -s emulator-5560"
for i in $(seq 1 120); do [ "$($A shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 5; done
echo "boot_completed after ~$((i*5))s"
sleep 15
echo "app: $($A shell dumpsys package com.mknoon.app | grep -m1 versionName | tr -d ' \r')"
echo "mac: $(sysctl -n vm.loadavg) $(sysctl -n vm.swapusage | cut -c1-60)"
