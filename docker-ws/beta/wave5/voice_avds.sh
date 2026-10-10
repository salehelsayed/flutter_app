#!/bin/bash
# Read-only: AVDs, running emulators, Mac load.
$HOME/Library/Android/sdk/emulator/emulator -list-avds
$HOME/Library/Android/sdk/platform-tools/adb devices -l | tail -n +2
sysctl -n vm.loadavg
