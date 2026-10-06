#!/bin/bash
# Read-only: CPU count, memory, load and the host-all worker processes.
sysctl -n hw.ncpu hw.perflevel0.physicalcpu hw.memsize 2>/dev/null; uptime
ps -axo pid,pcpu,etime,command | grep -E "flutter_tester|flutter_tools.*test" | grep -v grep | wc -l
