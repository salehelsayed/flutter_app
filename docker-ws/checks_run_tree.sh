#!/bin/bash
# Read-only: process tree (pid, %cpu, elapsed, command head) under the mknoon_checks run for a tree under build/.
T="/Volumes/CrucialX9/flutter_app/build/${1:?tree}"
for p in $(pgrep -f "scripts/mknoon_checks.py run"); do c=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n "s/^n//p"); case "$c" in "$T"*) echo "root $p"; ps -o pid=,pcpu=,etime=,command= -g $(ps -o pgid= -p $p | tr -d " ") | cut -c1-170;; esac; done
