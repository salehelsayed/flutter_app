#!/bin/bash
# Read-only: top CPU and memory users on the Mac right now.
echo "load: $(sysctl -n vm.loadavg)  swap: $(sysctl -n vm.swapusage | awk '{print $6}') used"
echo "--- top CPU"
ps -Aceo pcpu,pid,etime,comm -r | head -12
echo "--- parent commands of busy dart/java/xcode processes"
for p in $(ps -Aceo pid,pcpu,comm -r | awk 'NR>1 && $2>20 {print $1}' | head -8); do
  pp=$(ps -o ppid= -p "$p" | tr -d ' '); printf '%s <- %s\n' "$(ps -o command= -p "$p" | cut -c1-90)" "$(ps -o command= -p "$pp" | cut -c1-90)"
done
