#!/bin/bash
# Read-only: load, overall CPU use, and the processes using the most CPU right now
# (top's second 2-second sample; the first sample of top -l is not meaningful).
echo "load: $(sysctl -n vm.loadavg)   cores: $(sysctl -n hw.ncpu)"
top -l 2 -n 18 -o cpu -s 2 -stats pid,command,cpu,th,state > /tmp/cpu_breakdown.$$ 2>/dev/null
awk '/^Processes:/{n++} n==2' /tmp/cpu_breakdown.$$ | grep -E "^(Processes|CPU usage|Load Avg)"
echo "--- top processes by CPU"
awk '/^Processes:/{n++} n==2' /tmp/cpu_breakdown.$$ | awk '/^PID/{p=1} p' | head -19
rm -f /tmp/cpu_breakdown.$$
