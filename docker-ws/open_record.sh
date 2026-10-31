#!/bin/bash
# Record an Android screen around one tap and make a frame contact sheet (first 2.4 s at 10 fps).
#   host-run bash docker-ws/open_record.sh <serial> <x> <y> <evid dir under repo> <name> [tap delay s, default 1]
set -uo pipefail
S=${1:?serial}; X=${2:?x}; Y=${3:?y}; E="/Volumes/CrucialX9/flutter_app/${4:?evid}"; N=${5:?name}; D=${6:-1}
mkdir -p "$E"; F=/sdcard/rec_$N.mp4
adb -s "$S" shell rm -f "$F"
adb -s "$S" shell screenrecord --time-limit 5 --bit-rate 8000000 "$F" & RP=$!
sleep "$D"; T0=$(date -u +%H:%M:%S.%N | cut -c1-12); adb -s "$S" shell input tap "$X" "$Y"
wait $RP; sleep 1
adb -s "$S" pull "$F" "$E/$N.mp4" >/dev/null 2>&1; adb -s "$S" shell rm -f "$F"
/opt/homebrew/bin/ffmpeg -loglevel error -y -ss 0.6 -t 2.4 -i "$E/$N.mp4" -vf "fps=10,scale=270:-1,tile=8x3" -frames:v 1 "$E/${N}_sheet.png"
echo "tap_utc=$T0 mp4=$E/$N.mp4 sheet=$E/${N}_sheet.png bytes=$(stat -f %z "$E/$N.mp4" 2>/dev/null)"
