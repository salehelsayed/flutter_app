#!/bin/bash
# Read-only: open regular files (logs/reports) of given PIDs.
for p in "$@"; do echo "== $p =="; lsof -p "$p" 2>/dev/null | awk '$4 ~ /[0-9]+[wu]/ && $5=="REG"{print $9}' | grep -v -E '\.(dylib|so)$' | head -20; done
echo "== parent chain 59606 =="; ps -o pid=,ppid=,command= -p 59606 | cut -c1-120
echo "== children of 59606 =="; pgrep -P 59606 | while read c; do ps -o pid=,etime=,command= -p $c | cut -c1-200; done
