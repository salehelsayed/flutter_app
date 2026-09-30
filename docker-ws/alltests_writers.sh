#!/bin/bash
# Read-only: processes holding files open under the run root / worktree build (log writers), plus log streams.
run=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run
lsof +D "$run" 2>/dev/null | awk 'NR>1{print $2, $1, $9}' | sort -u | head -20
echo "== log/syslog streams =="; ps ax -o pid=,ppid=,etime=,command= | grep -E "simctl .*log stream|xcrun simctl spawn|log stream|idevicesyslog|logcat" | grep -v grep | cut -c1-220
