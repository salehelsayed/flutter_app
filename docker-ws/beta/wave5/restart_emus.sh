#!/bin/bash
# Cold-restart the named emulators: "<avd>:<port>" pairs. Waits for boot, then checks relay reachability.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
for pair in "$@"; do avd=${pair%%:*}; port=${pair##*:}
  $ADB -s emulator-$port emu kill >/dev/null 2>&1
done
sleep 8
for pair in "$@"; do avd=${pair%%:*}; port=${pair##*:}
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$avd" -port "$port" -no-snapshot-load -no-boot-anim -netdelay none -netspeed full \
    > /tmp/emulator_$avd.log 2>&1 &
  echo "launched $avd on $port"
done
for i in $(seq 1 30); do sleep 5; ok=0
  for pair in "$@"; do port=${pair##*:}; [ "$($ADB -s emulator-$port shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && ok=$((ok+1)); done
  [ $ok = $# ] && { echo "booted after $((i*5))s"; break; }
done
sleep 10
for pair in "$@"; do port=${pair##*:}
  echo "emulator-$port | $($ADB -s emulator-$port shell 'ping -c1 -W3 mknoun.xyz 2>&1 | head -1' | tr -d '\r' | cut -c1-50) | $($ADB -s emulator-$port shell 'toybox nc -z -w 4 mknoun.xyz 4001 && echo open4001 || echo closed4001' | tr -d '\r' | tail -1)"
done
