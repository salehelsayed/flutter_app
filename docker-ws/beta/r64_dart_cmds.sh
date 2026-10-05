#!/bin/bash
# Read-only: full commands of orphaned dartvm processes (first 3 of each start time) and their cwd.
for p in $(ps -axo pid=,ppid=,command= | awk '$2==1 && /dartvm/ {print $1}' | head -40); do
  echo "$p $(ps -o etime= -p $p) cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p') :: $(ps -o command= -p $p | sed 's/.*--resolved_executable_name=[^ ]* //' | cut -c1-200)"
done | sort -k2 | awk '{k=$2; c[k]++; if (c[k]<=3) print}'
echo "total orphan dartvm: $(ps -axo ppid=,command= | awk '$1==1 && /dartvm/' | wc -l)"
