#!/bin/bash
# Read-only: which child of the fixed-build runner is busy right now?
echo "now: $(date '+%H:%M:%S')"
tree() { local p=$1 d=$2; ps -o pid=,etime=,%cpu=,command= -p "$p" | awk -v d="$d" '{printf "%s%s %s cpu=%s %s\n", d, $1, $2, $3, substr($4" "$5" "$6,1,90)}'; for c in $(pgrep -P "$p"); do tree "$c" "$d  "; done; }
for r in $(pgrep -f build_beta_fixed.sh); do tree "$r" ""; done | head -40
echo "--- go/gomobile anywhere:"
ps -axo pid,etime,%cpu,command | grep -E "gomobile|/go/bin/go |go build|compile -o" | grep -v grep | cut -c1-120 | head -5
