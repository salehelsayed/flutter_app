#!/bin/bash
# Read-only: working folders of orphaned `flutter build ios` helpers (ppid 1).
for p in $(ps -axo pid=,ppid=,command= | awk '$2==1 && /dartvm/ && /build ios/ {print $1}'); do
  lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p'
done | sort | uniq -c
echo "rss MB total: $(ps -axo ppid=,rss=,command= | awk '$1==1 && /dartvm/ && /build ios/ {s+=$2} END {print int(s/1024)}')"
