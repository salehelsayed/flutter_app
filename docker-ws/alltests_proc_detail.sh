#!/bin/bash
# Read-only: full command line + cwd for given PIDs (or default suspicious set).
for p in "$@"; do
  echo "== $p =="
  ps -o pid=,ppid=,etime=,command= -p "$p" 2>/dev/null | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-900
  lsof -a -p "$p" -d cwd -Fn 2>/dev/null | grep '^n' | head -1
done
