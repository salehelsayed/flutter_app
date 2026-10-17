#!/bin/bash
# Read-only: the Mac's load and the 15 busiest processes by CPU (pid, %cpu, elapsed, command name only).
#   host-run bash docker-ws/top_cpu.sh
set -u
echo "load: $(sysctl -n vm.loadavg)"
ps -axo pid=,pcpu=,etime=,comm= | sort -k2 -nr | head -15 | awk '{n=split($4,p,"/"); printf "%7s %6s %12s %s\n", $1, $2, $3, p[n]}'
