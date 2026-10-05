#!/bin/bash
# Read-only: the process tree under the given pids (pid, elapsed, command).
show() { ps -o pid=,etime=,command= -p "$1" | cut -c1-160 | sed "s/^/$2/"; for c in $(pgrep -P "$1"); do show "$c" "$2  "; done; }
for p in "$@"; do show "$p" ""; echo; done
