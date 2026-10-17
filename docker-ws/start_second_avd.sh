#!/bin/bash
# Start ONE disposable AVD on a fixed console port beside the running emulator, then wait for boot.
#   host-run bash docker-ws/start_second_avd.sh <avd-name> <even-port 5556..5584>
set -uo pipefail
AVD="${1:?avd}"; PORT="${2:?port}"
[[ "$PORT" =~ ^55(5[6-9]|[6-8][0-9])$ ]] || { echo "refused port" >&2; exit 2; }
SDK="$HOME/Library/Android/sdk"; SERIAL="emulator-$PORT"
if adb devices | grep -q "^$SERIAL"; then echo "$SERIAL already attached"; exit 0; fi
nohup "$SDK/emulator/emulator" -avd "$AVD" -port "$PORT" -no-snapshot-load -no-boot-anim \
  -netdelay none -netspeed full > "/tmp/emulator_${AVD}_$PORT.log" 2>&1 < /dev/null &
echo "launched $AVD pid=$!"
for i in $(seq 1 72); do
  sleep 5
  [ "$(adb -s "$SERIAL" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && { echo "BOOT COMPLETE after $((i*5))s"; exit 0; }
done
echo "BOOT TIMEOUT"; exit 1
