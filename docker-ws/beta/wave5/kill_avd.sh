#!/bin/bash
# Stop the qemu process(es) of the named AVD (used when an emulator dropped off adb but is still running).
for p in $(pgrep -f "qemu-system.*-avd $1( |$)"); do echo "stopping $p"; kill "$p"; done
sleep 6
for p in $(pgrep -f "qemu-system.*-avd $1( |$)"); do echo "force $p"; kill -9 "$p"; done
pgrep -fl "qemu-system.*-avd $1" || echo "no $1 emulator left"
