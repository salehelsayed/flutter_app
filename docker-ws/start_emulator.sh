#!/bin/bash
# Launch an AVD headless-ish for automated call testing. Idempotent: if one is
# already attached, do nothing.
set -uo pipefail
AVD="${1:-Codex_API35}"
SDK="$HOME/Library/Android/sdk"
if adb devices | grep -q "^emulator-"; then
  echo "EMULATOR ALREADY RUNNING"; adb devices; exit 0
fi
nohup "$SDK/emulator/emulator" -avd "$AVD" -no-snapshot-load -no-boot-anim \
  -netdelay none -netspeed full > /tmp/emulator_$AVD.log 2>&1 &
echo "launched $AVD pid=$!"
for i in $(seq 1 60); do
  sleep 5
  BOOT=$(adb -s emulator-5554 shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  if [ "$BOOT" = "1" ]; then echo "BOOT COMPLETE after $((i*5))s"; break; fi
done
adb devices
