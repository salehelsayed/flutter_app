#!/bin/bash
A=$HOME/Library/Android/sdk/platform-tools/adb
for s in emulator-5554 emulator-5556; do $A -s $s emu kill >/dev/null 2>&1; done
sleep 6; $A devices | tail -n +2
