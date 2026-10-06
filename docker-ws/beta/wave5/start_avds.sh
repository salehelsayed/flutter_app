#!/bin/bash
# Start Pixel_6a on port 5556 and Pixel_8 on port 5558 (if not already attached), detached; wait for boot.
. /Volumes/CrucialX9/flutter_app/docker-ws/beta/beta_env.sh
start(){ avd=$1; port=$2
  if $ADB devices | grep -q "^emulator-$port"; then echo "emulator-$port already attached"; return; fi
  nohup "$ANDROID_HOME/emulator/emulator" -avd "$avd" -port "$port" -no-snapshot-load -no-boot-anim -netdelay none -netspeed full \
    > /tmp/emulator_$avd.log 2>&1 &
  echo "launched $avd on $port (pid $!)"; }
start Pixel_6a 5556; start Pixel_8 5558
for i in $(seq 1 36); do
  sleep 5; ok=0
  for p in 5556 5558; do [ "$($ADB -s emulator-$p shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ] && ok=$((ok+1)); done
  [ $ok = 2 ] && { echo "both booted after $((i*5))s"; break; }
done
$ADB devices
