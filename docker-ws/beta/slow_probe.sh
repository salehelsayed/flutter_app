#!/bin/bash
# Read-only: why is emulator-5556 slow? adb latency, guest memory/CPU pressure,
# Mac memory pressure and the emulator process footprint.
. "$(dirname "$0")/beta_env.sh"
kill "$(cat "$(current_run)/logcat.pid" 2>/dev/null)" 2>/dev/null   # stray logcat of the stopped run
t0=$(date +%s); $ADB shell true; echo "adb round trip: $(( $(date +%s) - t0 )) s"
echo "--- guest PSI + memory"
$ADB shell 'for f in cpu memory io; do echo "$f: $(head -1 /proc/pressure/$f 2>/dev/null)"; done; grep -E "MemTotal|MemAvailable|SwapTotal|SwapFree" /proc/meminfo; uptime'
echo "--- guest top"
$ADB shell top -b -n 1 -m 8 -o PID,%CPU,RES,S,ARGS 2>/dev/null | tail -9 | cut -c1-110
echo "--- mac memory"
sysctl -n vm.swapusage; memory_pressure 2>/dev/null | tail -1
echo "load: $(sysctl -n vm.loadavg)"
echo "--- emulator + simulator processes (cpu, rss MB)"
ps -axo pid,pcpu,rss,etime,command | awk '/qemu-system|SimMetalHost|launchd_sim|com.apple.Virtualization/ && !/awk/ {printf "%s %s%% %d MB %s %s\n",$1,$2,$3/1024,$4,substr($0,index($0,$5),90)}'
echo "--- adb server and clients"
ps -axo pid,pcpu,etime,command | grep -E "adb .*(server|logcat|forward|shell)" | grep -v grep | cut -c1-120 | head -10
