#!/bin/bash
# Read-only: process tree under the Wave 5 full runner.
r=$(pgrep -f "mknoon_checks.py full" | head -1); [ -z "$r" ] && { echo "no runner"; exit 0; }
tree(){ for c in $(pgrep -P "$1"); do ps -o pid=,pcpu=,etime=,command= -p "$c" | cut -c1-200 | sed "s/^/$2/"; tree "$c" "$2  "; done; }
ps -o pid=,etime=,command= -p "$r" | cut -c1-120; tree "$r" "  " | head -40
