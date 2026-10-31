#!/bin/bash
# bytes.sh <serial>: one line of app data KiB + eth0/wlan0 rx bytes
S=$1; export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
a=$(timeout 30 adb -s $S shell du -sk /data/data/com.mknoon.app 2>/dev/null | awk '{print $1}')
[ -z "$a" ] && a=$(timeout 30 adb -s $S shell run-as com.mknoon.app du -sk . 2>/dev/null | awk '{print $1}')
n=$(timeout 20 adb -s $S shell cat /proc/net/dev | awk '/eth0|wlan0/{gsub(":","",$1); printf "%s_rx=%s ", $1, $2}')
echo "$(date -u +%FT%TZ) app_kib=$a $n"
