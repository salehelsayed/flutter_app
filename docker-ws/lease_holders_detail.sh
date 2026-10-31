#!/bin/bash
# Read-only: which process holds which mknoon device-lease lock file.
D="/tmp/mknoon-device-leases-$(id -u)"
lsof +D "$D" 2>/dev/null | awk 'NR>1{print $2, $NF}' | sort -u | while read p f; do echo "pid $p etime $(ps -o etime= -p $p | tr -d ' ') file $(basename "$f") cmd $(ps -o args= -p $p | cut -c1-140)"; done
