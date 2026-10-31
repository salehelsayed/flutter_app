#!/bin/bash
# Read-only: list processes holding mknoon device lease files.
D="/tmp/mknoon-device-leases-$(id -u)"
ls -la "$D" 2>&1 | tail -5
lsof +D "$D" 2>/dev/null | awk 'NR>1{print $2}' | sort -u | while read p; do echo "pid $p etime $(ps -o etime= -p $p) $(ps -o args= -p $p | cut -c1-160)"; done
