#!/bin/bash
# Read-only: top 8 processes by CPU and by memory (pid, %cpu, rss MB, elapsed, command name, cwd for the top CPU ones).
echo "== by CPU"; ps -axo pid=,pcpu=,rss=,etime=,comm= | sort -k2 -nr | head -8 | awk "{printf \"%s %s%% %dMB %s %s\\n\", \$1, \$2, \$3/1024, \$4, \$5}"
echo "== by memory"; ps -axo pid=,pcpu=,rss=,etime=,comm= | sort -k3 -nr | head -8 | awk "{printf \"%s %s%% %dMB %s %s\\n\", \$1, \$2, \$3/1024, \$4, \$5}"
echo "== cwd of top CPU"; for p in $(ps -axo pid=,pcpu= | sort -k2 -nr | head -5 | awk "{print \$1}"); do echo "$p $(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n "s/^n//p" | head -1)"; done
sysctl -n vm.loadavg
