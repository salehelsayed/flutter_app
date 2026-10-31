#!/bin/bash
# Read-only: list all descendants of <pid> (pid, ppid, etime, cpu, rss MB, args cut).
#   host-run bash docker-ws/host_proc_descendants.sh <pid>
R="${1:?pid}"; [[ "$R" =~ ^[0-9]+$ ]] || exit 2
walk() { for c in $(pgrep -P "$1"); do ps -o pid=,ppid=,etime=,%cpu=,rss=,args= -p "$c" | awk '{printf "%s %s %s %s %dMB ", $1,$2,$3,$4,$5/1024; $1=$2=$3=$4=$5=""; print substr($0,6,200)}'; walk "$c"; done; }
walk "$R"
