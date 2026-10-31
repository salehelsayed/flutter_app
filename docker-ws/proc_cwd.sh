#!/bin/bash
# Read-only: cwd, parent and full args of one PID.  host-run bash docker-ws/proc_cwd.sh <pid>
P="${1:?pid}"; [[ "$P" =~ ^[0-9]+$ ]] || exit 2
echo "cwd $(lsof -a -p "$P" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
ps -o pid=,ppid=,etime=,args= -p "$P" | cut -c1-400
PP=$(ps -o ppid= -p "$P" | tr -d ' '); [ -n "$PP" ] && ps -o pid=,ppid=,etime=,args= -p "$PP" | cut -c1-300
