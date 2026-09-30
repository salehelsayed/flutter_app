#!/bin/bash
# Read-only: what makes up the Mac load: top CPU users, total CPU in use, and processes/threads waiting (state U = disk wait, R = runnable).
echo "load: $(sysctl -n vm.loadavg)  cpus: $(sysctl -n hw.ncpu)"
echo "total %CPU of all processes: $(ps -axo pcpu= | awk '{s+=$1} END {printf "%.0f", s}') (1200 = all 12 cores busy)"
echo "threads by state: $(ps -M -ax -o state= 2>/dev/null | cut -c1 | sort | uniq -c | tr -s ' ' | tr '\n' ' ')"
echo "--- processes with threads in disk wait (U):"
ps -M -ax -o pid=,state=,comm= 2>/dev/null | awk '$2 ~ /^U/ {print $1}' | sort | uniq -c | sort -rn | head -8 | while read n p; do echo "$n threads  pid $p $(ps -o comm= -p $p | cut -c1-110)"; done
echo "--- top 15 by CPU:"
ps -axo pcpu,pid,comm -r | head -16 | cut -c1-140
