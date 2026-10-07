#!/bin/bash
# Read-only: total CPU seconds and process count under the Wave 5 runner, sampled twice 20 s apart.
r=$(pgrep -f "mknoon_checks.py full" | head -1); [ -z "$r" ] && { echo "no runner"; exit; }
desc(){ for c in $(pgrep -P "$1"); do echo "$c"; desc "$c"; done; }
snap(){ pids=$(desc "$r" | tr '\n' ','); pids=${pids%,}; ps -o time=,comm= -p "$pids" 2>/dev/null | awk '{split($1,a,":"); s=(length(a)==3)?a[1]*3600+a[2]*60+a[3]:a[1]*60+a[2]; t+=s; n++} END {printf "cpu=%.1fs procs=%d\n", t, n}'; }
snap; sleep 20; snap
ps -axo pcpu,comm -r | head -6 | cut -c1-90
