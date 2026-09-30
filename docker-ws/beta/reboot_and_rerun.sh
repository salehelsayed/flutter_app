#!/bin/bash
# Stop the previous beta runner, reboot the Pixel 7a emulator (Android reboot),
# wait until it is fully booted, check the clock, then start run_fixed2.sh
# detached. Touches only our runner/maestro processes and emulator-5556.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
kill_tree() { local p=$1 c; for c in $(pgrep -P "$p"); do kill_tree "$c"; done; kill "$p" 2>/dev/null; }
for r in $(pgrep -f "run_fixed2.sh"); do kill_tree "$r"; done
sleep 2
echo "runner stopped: $(pgrep -f run_fixed2.sh >/dev/null && echo no || echo yes)"
echo "rebooting $SERIAL at $(date '+%H:%M:%S')"
$ADB reboot
$ADB wait-for-device
for i in $(seq 1 120); do
  [ "$($ADB shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && break; sleep 2
done
echo "boot_completed=$($ADB shell getprop sys.boot_completed | tr -d '\r') at $(date '+%H:%M:%S')"
sleep 20
$ADB shell input keyevent KEYCODE_WAKEUP; $ADB shell wm dismiss-keyguard 2>/dev/null
echo "host clock: $(date '+%H:%M:%S')  emulator clock: $($ADB shell date '+%H:%M:%S')"
echo "keyguard: $($ADB shell dumpsys window | grep -m1 -oE 'isKeyguardShowing=[a-z]+')"
$ADB shell svc wifi enable; $ADB shell svc data enable
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' /bin/bash "$H/run_fixed2.sh" \
  > "$H/run_fixed2.out" 2>&1 < /dev/null &
echo "rerun launched pid $!"
