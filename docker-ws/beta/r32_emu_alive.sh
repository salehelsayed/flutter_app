#!/bin/bash
# Read-only: is the Pixel_7a emulator responsive? adb round trips, guest clock and uptime advancing, a fresh screenshot,
# recent logcat activity, the qemu process CPU/priority, and my runner's current step.
. "$(dirname "$0")/beta_env.sh"
echo "serial=$SERIAL mac=$(date +%H:%M:%S) load=$(sysctl -n vm.loadavg)"
for i in 1 2 3; do a=$(date +%s.%N 2>/dev/null || python3 -c 'import time;print(time.time())'); o=$(timeout 20 $ADB shell 'date +%H:%M:%S; cat /proc/uptime' 2>&1 | tr '\r\n' '  '); echo "adb#$i: $o (took $(python3 -c "import time;print(round(time.time()-$(python3 -c 'import time;print(time.time())'),1))" 2>/dev/null))"; sleep 2; done
echo "wakefulness: $(timeout 20 $ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r')  focus: $(timeout 20 $ADB shell dumpsys window | grep -m1 -E 'mCurrentFocus' | tr -d '\r' | cut -c1-120)"
echo "last logcat line: $(timeout 20 $ADB logcat -d -t 1 2>/dev/null | tail -1 | cut -c1-120)"
timeout 30 $ADB exec-out screencap -p > /tmp/r32_alive.png 2>/dev/null; echo "screencap bytes: $(stat -f %z /tmp/r32_alive.png 2>/dev/null)"
cp /tmp/r32_alive.png "$(current_run)/extra/alive_check.png" 2>/dev/null
P=$(ps -axo pid,command | grep qemu-system | grep -- '-avd Pixel_7a' | grep -v grep | awk '{print $1}' | head -1)
echo "qemu pid=$P $(ps -o pri=,%cpu=,etime= -p $P) threads_at_4: $(ps -M -p $P | awk 'NR>1' | grep -c ' 4T ')"
echo "runner: $(ps -axo pid,etime,command | grep -E 'run_r32_validate|maestro .*test' | grep -v grep | cut -c1-160)"
tail -3 "$(current_run)/timeline.txt"
