#!/bin/bash
# One Pixel icon cold start with group texts pending: force-stop Pixel Mknoon, emulator (group chat open) sends N texts,
# clear Pixel logcat, launch from launcher, wait, dump logcat. Host-side.
#   host-run bash docker-ws/cs_retry_run.sh <run-tag> <evidence dir under repo> [texts=3] [wait=50]
set -u
TAG="$1"; EV="/Volumes/CrucialX9/flutter_app/$2"; N="${3:-3}"; W="${4:-50}"
P=21071FDF600CSC; S=emulator-5554; R=/Volumes/CrucialX9/flutter_app
adb -s $P shell am force-stop com.mknoon.app; sleep 2
adb -s $P shell pidof com.mknoon.app && { echo "STILL RUNNING"; exit 3; }
for i in $(seq 1 "$N"); do bash $R/docker-ws/emu_chat_send.sh $S "${TAG}msg$i"; done
sleep 8
adb -s $P shell pidof com.mknoon.app && echo "WARN: Pixel app relaunched before open"
adb -s $P logcat -c
OPEN=$(date -u +%FT%T.%3NZ); echo "OPEN $OPEN"; echo "$OPEN" > "$EV/${TAG}_open_utc.txt"
adb -s $P shell monkey -p com.mknoon.app -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
sleep "$W"
adb -s $P logcat -d > "$EV/${TAG}_logcat.txt"
echo "lines $(wc -l < "$EV/${TAG}_logcat.txt")"
