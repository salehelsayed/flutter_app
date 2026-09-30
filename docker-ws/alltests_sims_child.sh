#!/bin/bash
# Read-only: full command of the sims major children and their descendants (short).
for p in $(pgrep -f "tool/sims/sims.dart major"); do
  for c in $(pgrep -P "$p"); do
    ps -o pid=,etime=,command= -p "$c" | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-220
    for g in $(pgrep -P "$c"); do ps -o pid=,etime=,command= -p "$g" | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-200 | sed 's/^/   /'; done
  done
done
