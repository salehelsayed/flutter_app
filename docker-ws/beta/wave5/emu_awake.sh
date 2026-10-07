#!/bin/bash
# Keep the emulators' Android screens on (macOS throttles an idle emulator's qemu to priority 4).
export PATH="$HOME/Library/Android/sdk/platform-tools:$PATH"
for s in emulator-5554 emulator-5556 emulator-5558; do
  adb -s $s shell svc power stayon true; adb -s $s shell input keyevent KEYCODE_WAKEUP; adb -s $s shell settings put system screen_off_timeout 2147483647
done
sleep 20
bash /Volumes/CrucialX9/flutter_app/docker-ws/wave3_host_qemu_prio.sh
