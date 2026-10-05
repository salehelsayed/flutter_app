#!/bin/bash
# Read-only: full command (after the dart executable) and children of one pid.
ps -o command= -p "$1" | sed 's/.*--resolved_executable_name=[^ ]* //' | tr ' ' '\n' | grep -v -- '--packages' | tail -8 | tr '\n' ' '; echo
pgrep -P "$1" | while read c; do echo "child $c: $(ps -o etime=,command= -p $c | cut -c1-140)"; done
