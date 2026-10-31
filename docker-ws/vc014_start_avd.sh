#!/bin/bash
# VC-014: start ONE disposable AVD headless with audio fully OFF (-no-audio), no camera; wait for boot; print the emulator PID.
#   host-run bash docker-ws/vc014_start_avd.sh <avd-name> <even-port 5554..5584>
set -uo pipefail
AVD="${1:?avd}"; PORT="${2:?port}"
[[ "$PORT" =~ ^55(5[4-9]|[6-8][0-9])$ ]] || { echo "refused port" >&2; exit 2; }
SDK="$HOME/Library/Android/sdk"; SERIAL="emulator-$PORT"
if adb devices | grep -q "^$SERIAL"; then echo "$SERIAL already attached"; exit 0; fi
nohup "$SDK/emulator/emulator" -avd "$AVD" -port "$PORT" -no-window -no-snapshot-load -no-snapshot-save -no-boot-anim \
  -no-audio -camera-back none -camera-front none -cores 2 -memory 3072 -netdelay none -netspeed full \
  > "/tmp/emulator_${AVD}_$PORT.log" 2>&1 < /dev/null &
echo "launched $AVD pid=$!"
for i in $(seq 1 72); do
  sleep 5
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && { echo "BOOT COMPLETE after $((i*5))s"; exit 0; }
done
echo "BOOT TIMEOUT"; tail -5 "/tmp/emulator_${AVD}_$PORT.log"; exit 1
