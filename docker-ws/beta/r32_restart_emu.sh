#!/bin/bash
# Stop my R2-9 run (runner, its Maestro flows, logcat, priority sampler), then restart the Pixel_7a emulator on the same
# port with its data kept (cold boot, no wipe) and wait until it has booted. Prints the app state afterwards.
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); PORT=${SERIAL#emulator-}
echo "stopping run $RUN"
pkill -f run_r32_validate.sh; pkill -f "maestro --device $SERIAL"; pkill -f "maestro --device $UDID"; pkill -f r31_qemu_prio.sh
kill "$(cat "$RUN/logcat.pid" 2>/dev/null)" 2>/dev/null
echo "[$(date '+%H:%M:%S')] RUN STOPPED by the operator: emulator restart (window frozen, qemu throttled)" >> "$RUN/timeline.txt"
P=$(ps -axo pid,command | grep qemu-system | grep -- '-avd Pixel_7a' | grep -v grep | awk '{print $1}' | head -1)
echo "old qemu pid=$P: $(ps -o command= -p $P | cut -c1-200)"
$ADB emu kill >/dev/null 2>&1
for i in $(seq 1 60); do kill -0 "$P" 2>/dev/null || break; sleep 1; done
kill -0 "$P" 2>/dev/null && { echo "emu kill did not stop it; SIGTERM"; kill "$P"; sleep 10; }
kill -0 "$P" 2>/dev/null && { echo "still alive, not continuing"; exit 1; }
echo "old emulator stopped after ${i}s"
nohup perl -e 'use POSIX qw(setsid); setsid(); exec @ARGV' "$ANDROID_HOME/emulator/emulator" -avd Pixel_7a -port "$PORT" \
  -no-snapshot-load -no-boot-anim > "$BETA/emulator_restart_$(date +%H%M%S).log" 2>&1 < /dev/null &
echo "launched emulator -avd Pixel_7a -port $PORT (pid $!)"
A="$ANDROID_HOME/platform-tools/adb -s emulator-$PORT"
for i in $(seq 1 90); do [ "$($A shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && break; sleep 5; done
echo "boot_completed after ~$((i*5))s"
sleep 20
echo "installed: $($A shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') $($A shell dumpsys package $PKG | grep -m1 -oE 'ceDataInode=[0-9]+|stopped=(true|false)' | tr -d '\r' | tr '\n' ' ')"
echo "full-screen: $($A shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r')  emu time $($A shell date +%H:%M:%S | tr -d '\r') mac $(date +%H:%M:%S)"
P=$(ps -axo pid,command | grep qemu-system | grep -- '-avd Pixel_7a' | grep -v grep | awk '{print $1}' | head -1)
echo "new qemu pid=$P pri=$(ps -o pri= -p $P) cmd: $(ps -o command= -p $P | cut -c1-160)"
