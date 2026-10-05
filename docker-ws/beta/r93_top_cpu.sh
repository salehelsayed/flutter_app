#!/bin/bash
# Read-only: the Mac's top CPU processes with their parent and start time, plus load.
uptime
ps -Ao pid,ppid,pcpu,pmem,lstart,comm -r | head -25 | cut -c1-200
echo "--- full commands of the top 12"
for p in $(ps -Ao pid,pcpu -r | awk 'NR>1 && NR<=13 {print $1}'); do
  echo "$p: $(ps -o command= -p "$p" 2>/dev/null | cut -c1-230)"
done
