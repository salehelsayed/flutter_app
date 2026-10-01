#!/bin/bash
# Shows each Android emulator's AVD, CPU and scheduling priority (4 = throttled).
for p in $(pgrep -f qemu-system-aarch64); do
  avd=$(ps -o command= -p $p | grep -oE -- "-avd [^ ]+" | head -1)
  printf '%s %s ' "$p" "$avd"; ps -o pcpu=,pri= -p $p | tr '\n' ' '
  ps -M -p $p | awk 'NR>1{print $4}' | sort | uniq -c | tr '\n' ' '; echo
done
