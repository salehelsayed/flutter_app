#!/bin/bash
# Audio OFF (-no-audio). Like mlkit_start_avd_image.sh but keeps the AVD's own hw.ramSize (no -memory override). Back camera = image file.
#   host-run bash docker-ws/start_avd_poster_fullram.sh <avd-name> <even-port 5554..5584> <poster-png-in-repo>
set -uo pipefail
AVD="${1:?avd}"; PORT="${2:?port}"; POSTER="$(cd "$(dirname "$0")/.." && pwd)/${3:?poster}"
[[ "$PORT" =~ ^55(5[4-9]|[6-8][0-9])$ ]] || { echo "refused port" >&2; exit 2; }
[ -f "$POSTER" ] || { echo "no poster"; exit 2; }
SDK="$HOME/Library/Android/sdk"; SERIAL="emulator-$PORT"
if adb devices | grep -q "^$SERIAL"; then echo "$SERIAL already attached"; exit 0; fi
nohup "$SDK/emulator/emulator" -avd "$AVD" -port "$PORT" -no-window -no-snapshot-load -no-snapshot-save -no-boot-anim \
  -no-audio -netdelay none -netspeed full \
  -camera-back "imagefile:$POSTER" > "/tmp/emulator_${AVD}_$PORT.log" 2>&1 < /dev/null &
echo "launched $AVD pid=$!"
for i in $(seq 1 72); do
  sleep 5
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && { echo "BOOT COMPLETE after $((i*5))s"; exit 0; }
done
echo "BOOT TIMEOUT"; tail -5 "/tmp/emulator_${AVD}_$PORT.log"; exit 1
