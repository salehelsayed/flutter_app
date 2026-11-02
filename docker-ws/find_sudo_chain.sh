#!/bin/bash
# Read-only: list sudo processes on the Mac and walk each one's parent chain (pid, ppid, etime, command cut).
ps -axo pid,ppid,etime,command | grep -i '[s]udo' | while read -r pid ppid et cmd; do
  echo "HIT $pid $et ${cmd:0:120}"; p=$ppid
  for i in 1 2 3 4 5 6; do [ "$p" -le 1 ] && break; l=$(ps -o pid=,ppid=,etime=,command= -p "$p"); echo "  up $(echo "$l" | cut -c1-200)"; p=$(echo "$l" | awk '{print $2}'); done
done
echo "end"
