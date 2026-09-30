#!/bin/bash
# Read-only: raw Defender real-time statistics output (first lines) and its CPU now.
/usr/local/bin/mdatp diagnostic real-time-protection-statistics --output json 2>&1 | head -c 1500; echo
/usr/local/bin/mdatp diagnostic real-time-protection-statistics 2>&1 | head -40
echo "cpu now: $(ps -o pcpu= -p $(pgrep -f wdavdaemon_unprivileged | head -1))  load: $(sysctl -n vm.loadavg)"
