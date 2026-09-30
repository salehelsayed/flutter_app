#!/bin/bash
# Read-only: show the live process tree under run_fresh_three_phones.sh on the Mac.
echo "now: $(date '+%H:%M:%S')"
ROOTS=$(pgrep -f run_fresh_three_phones.sh)
[ -z "$ROOTS" ] && { echo "run_fresh_three_phones.sh NOT running"; exit 0; }
show() { local p=$1 d=$2; ps -o pid=,etime=,command= -p "$p" 2>/dev/null | cut -c1-220 | sed "s/^/$d/"; for c in $(pgrep -P "$p"); do show "$c" "$d  "; done; }
for r in $ROOTS; do show "$r" ""; done
