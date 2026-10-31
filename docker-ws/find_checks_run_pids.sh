#!/bin/bash
# Read-only: PIDs of mknoon_checks.py runs whose cwd is the given tree under build/.
T="/Volumes/CrucialX9/flutter_app/build/${1:?tree}"
for p in $(pgrep -f "scripts/mknoon_checks.py run"); do c=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n "s/^n//p"); case "$c" in "$T"*) echo "$p";; esac; done
