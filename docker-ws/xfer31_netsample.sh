#!/bin/bash
# xfer31_netsample.sh <serial> <seconds> <out>: every ~1 s, count ONLY com.mknoon.app sockets (uid filter on /proc/net), no addresses written:
#   tcp_lan = established TCP to the shared emulator Wi-Fi 10.0.2.0/24, tcp_relay = established TCP to remote port 4005,
#   tcp_other = other established TCP, udp_conn = UDP sockets with a remote peer set, udp_all = all app UDP sockets
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
S=$1; END=$(( $(date +%s) + $2 )); OUT=$3
U=$(timeout 10 adb -s "$S" shell dumpsys package com.mknoon.app | grep -m1 -oE '(userId|appId)=[0-9]+' | cut -d= -f2)
while [ "$(date +%s)" -lt "$END" ]; do
  timeout 8 adb -s "$S" shell 'for f in tcp tcp6 udp udp6; do sed "s/^/$f /" /proc/net/$f; done' 2>/dev/null | awk -v u="$U" -v t="$(date -u +%T)" '
    $9==u { split($4,r,":"); ip=r[1]; port=r[2];
      if ($1 ~ /^tcp/) { if ($5!="01") next; if (ip ~ /02000A$/) lan++; else if (port=="0FA5") relay++; else other++ }
      else { ua++; if (ip !~ /^0+$/) uc++ } }
    END { printf "%s tcp_lan=%d tcp_relay=%d tcp_other=%d udp_conn=%d udp_all=%d\n", t, lan+0, relay+0, other+0, uc+0, ua+0 }' >> "$OUT"
  sleep 1
done
