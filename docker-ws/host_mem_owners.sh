#!/bin/bash
# Read-only: list dev-tool processes (dartvm, dart, flutter_tester, java, node, qemu, xcodebuild, Simulator, gradle) with pid, ppid, etime, rss MB, cwd and args cut.
#   host-run bash docker-ws/host_mem_owners.sh
ps -axo pid=,ppid=,etime=,rss=,args= | grep -E 'dartvm|dartaotruntime|/dart |flutter_tester|java|qemu|xcodebuild|Simulator|gradle|kotlin|/node ' | grep -v grep | while read -r pid ppid et rss rest; do
  cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' | head -1)
  printf '%6s %6s %12s %6.0fMB cwd=%s | %s\n' "$pid" "$ppid" "$et" "$((rss/1024))" "$cwd" "$(echo "$rest" | cut -c1-150)"
done
exit 0
