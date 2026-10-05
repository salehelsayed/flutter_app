#!/bin/bash
# Read-only: full process tree (pid, cpu, elapsed, short command) under processes matching a pattern.
show() { echo "$2$1 cpu=$(ps -o %cpu= -p $1) $(ps -o etime= -p $1) $(ps -o command= -p $1 | sed 's/.*--resolved_executable_name=[^ ]* //' | sed 's#/Users/I560101/development/flutter-3.47.2/bin/cache/dart-sdk/bin/##' | cut -c1-120)"; for c in $(pgrep -P "$1"); do show "$c" "$2  "; done; }
for p in $(pgrep -f "$1"); do show "$p" ""; done
