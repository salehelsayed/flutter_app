#!/bin/bash
# Read-only: process tree under a pid, plus run folder listing.
desc() { local p=$1 d=$2; ps -o pid=,etime=,stat=,command= -p $p | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-220 | sed "s/^/$d/"; for c in $(pgrep -P $p); do desc $c "$d  "; done; }
desc "$1" ""
echo "== folder =="; ls -la "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/$2" 2>&1 | tail -8
