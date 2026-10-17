#!/bin/bash
# Read-only: list dartvm processes whose parent is launchd, with start time, cwd and only the .dart file argument.
#   host-run bash docker-ws/probe_orphan_dartvm.sh
set -u
ps -axo pid=,ppid=,comm= | while read -r pid ppid comm; do
  case "$comm" in */dartvm|dartvm) ;; *) continue ;; esac
  [[ "$ppid" == 1 ]] || continue
  start="$(ps -o lstart= -p "$pid" 2>/dev/null)"
  cwd="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  dartfile="$(ps -o args= -p "$pid" 2>/dev/null | tr ' ' '\n' | grep -E '\.dart$|_test' | head -2 | tr '\n' ' ')"
  echo "$pid|$start|$cwd|$dartfile"
done
echo end
