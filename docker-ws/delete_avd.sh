#!/bin/bash
# Delete one disposable AVD by exact name (refuses the four standing AVDs).  host-run bash docker-ws/delete_avd.sh <name>
N="${1:?name}"; [[ "$N" =~ ^[A-Za-z0-9_]+$ ]] || exit 2
case "$N" in Pixel_7|Pixel_8|Pixel_6a|Pixel_8b) echo "refused: standing AVD"; exit 2;; esac
SDK="$HOME/Library/Android/sdk"; AVD="$SDK/cmdline-tools/latest/bin/avdmanager"
"$SDK/emulator/emulator" -list-avds | grep -qx "$N" || { echo "no such AVD"; exit 0; }
"$AVD" delete avd -n "$N" 2>&1 | tail -1
"$SDK/emulator/emulator" -list-avds
