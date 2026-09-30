#!/bin/bash
# Detached: wait for emulator-5556 boot_completed (max 15 min), settle, then run run_fixed2.sh.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
LOG="$H/wait_boot.log"; : > "$LOG"
for i in $(seq 1 180); do
  [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 5
done
echo "boot_completed=$($ADB shell getprop sys.boot_completed | tr -d '\r') at $(date '+%H:%M:%S')" >> "$LOG"
[ "$($ADB shell getprop sys.boot_completed | tr -d '\r')" = "1" ] || { echo "BOOT TIMEOUT" >> "$LOG"; exit 1; }
sleep 45
$ADB shell input keyevent KEYCODE_WAKEUP; $ADB shell wm dismiss-keyguard 2>/dev/null
$ADB shell svc wifi enable; $ADB shell svc data enable
echo "clock host $(date '+%H:%M:%S') emu $($ADB shell date '+%H:%M:%S'); keyguard $($ADB shell dumpsys window | grep -m1 -oE 'isKeyguardShowing=[a-z]+')" >> "$LOG"
echo "starting run_fixed2 at $(date '+%H:%M:%S')" >> "$LOG"
exec /bin/bash "$H/run_fixed2.sh" > "$H/run_fixed2.out" 2>&1
