#!/bin/bash
# Read-only: host load, emulator build type/clock, and ANR files on emulator-5556.
. "$(dirname "$0")/beta_env.sh"
echo "host now: $(date '+%H:%M:%S')  load: $(sysctl -n vm.loadavg)  cpus: $(sysctl -n hw.ncpu)"
echo "--- top CPU processes on the Mac"
ps -Aceo pcpu,pid,etime,comm -r | head -12
echo "--- flutter/dart/xcodebuild/gradle/emulator processes"
ps -axo pid,etime,pcpu,command | grep -E "flutter_tester|dart .*test|xcodebuild|gradle|qemu-system|Simulator.app|run_test_gates|run_sims" | grep -v grep | cut -c1-150 | head -20
echo "--- emulator"
$ADB shell 'echo "emu clock: $(date +%H:%M:%S)"; getprop ro.build.type; getprop ro.debuggable; getprop ro.product.name; getprop ro.build.version.sdk; uptime; pidof com.mknoon.app; ls -la /data/anr 2>&1 | head'
echo "host clock after: $(date '+%H:%M:%S')"
echo "--- adb root check"
$ADB root 2>&1 | head -2
