#!/bin/bash
# Read-only: UTC time, app data total KiB (debug run-as), radio0/eth0/wlan0 rx bytes on an emulator.
#   emu_app_bytes.sh <serial>
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}; E="$1"
kb=$(timeout 60 adb -s "$E" shell run-as com.mknoon.app du -sk . 2>/dev/null | awk '{print $1}')
rx=$(timeout 20 adb -s "$E" shell cat /proc/net/dev | awk -F'[: ]+' '/radio0|eth0|wlan0|rmnet/ {printf "%s_rx=%s ", $2, $3}')
echo "$(date -u +%FT%TZ) app_kib=$kb $rx"
