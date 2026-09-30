#!/bin/bash
# Read-only: working directory of running gomobile/gobind processes.
for p in $(pgrep -f "gomobile bind -target=ios"); do
  echo "gomobile $p cwd: $(lsof -a -p "$p" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
done
echo "now: $(date '+%H:%M:%S')"
