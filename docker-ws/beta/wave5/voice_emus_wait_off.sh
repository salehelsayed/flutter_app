#!/bin/bash
A=$HOME/Library/Android/sdk/platform-tools/adb
for i in $(seq 1 12); do n=$($A devices | grep -c "^emulator-"); [ "$n" = 0 ] && break; sleep 5; done
$A devices | tail -n +2
pgrep -fl "qemu-system|emulator -avd" | cut -c1-80
