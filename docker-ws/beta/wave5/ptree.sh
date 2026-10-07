#!/bin/bash
# Read-only: process tree under a pid with cpu, state and elapsed time.
tree(){ for c in $(pgrep -P "$1"); do ps -o pid=,stat=,pcpu=,etime=,command= -p "$c" | cut -c1-200 | sed "s/^/$2/"; tree "$c" "$2  "; done; }
ps -o pid=,stat=,pcpu=,etime=,command= -p "$1" | cut -c1-200; tree "$1" "  "
