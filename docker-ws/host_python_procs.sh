#!/bin/bash
# Read-only: Python processes with pid, ppid, age, cpu and short args.
ps -axo pid=,ppid=,etime=,pcpu=,args= | grep -i -E "[p]ython" | cut -c1-260
for p in $(pgrep -i python); do echo "$p cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n s/^n//p)"; done
