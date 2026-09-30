#!/bin/bash
# Read-only: every 3 s for N seconds (default 900), the emulator-5556 qemu process's CPU use and scheduling priority
# (process and per-thread min/max), plus Mac load. Output: <run>/extra/qemu_prio.txt. The Pixel screen state comes
# from the run's timeline (no adb calls here, so the probe adds no load to the emulator).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); OUT="$RUN/extra/qemu_prio.txt"; N=${1:-900}
P=$(ps -axo pid,command | grep qemu-system | grep -- '-avd Pixel_7a' | grep -v grep | awk '{print $1}' | head -1)
O=$(ps -axo pid,command | grep qemu-system | grep -v -- '-avd Pixel_7a' | grep -v grep | awk '{print $1}' | head -1)
echo "qemu 5556 pid=$P other qemu pid=$O" >> "$OUT"
end=$(( $(date +%s) + N ))
while [ $(date +%s) -lt $end ]; do
  a=$(ps -o pri=,nice=,%cpu= -p "$P" | tr -s ' ')
  th=$(ps -M -p "$P" | awk 'NR==2 {print $6} NR>2 {print $4}' | sort | uniq -c | sort -rn | awk '{printf "%s:%s ", $2, $1}')
  busy=$(ps -M -p "$P" | awk 'NR==2 && $4+0 >= 5 {print $6 "@" $4} NR>2 && $2+0 >= 5 {print $4 "@" $2}' | tr '\n' ' ')
  b=$(ps -o pri=,%cpu= -p "$O" 2>/dev/null | tr -s ' ')
  echo "$(date '+%H:%M:%S') load=$(sysctl -n vm.loadavg | awk '{print $2}') 5556[pri,nice,cpu]=$a threads_by_pri=[$th] busy_threads(pri@cpu)=[$busy] other[pri,cpu]=$b" >> "$OUT"
  sleep 3
done
