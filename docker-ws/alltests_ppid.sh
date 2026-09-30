#!/bin/bash
# Read-only: ancestor chain of a pid.
p=$1; while [ -n "$p" ] && [ "$p" != 1 ] && [ "$p" != 0 ]; do ps -o pid=,ppid=,etime=,command= -p $p | sed -E 's/--resolved_executable_name=[^ ]+ --executable_name=[^ ]+ //' | cut -c1-250; p=$(ps -o ppid= -p $p | tr -d ' '); done
