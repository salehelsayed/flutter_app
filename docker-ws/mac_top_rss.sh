#!/bin/bash
# Read-only: top N Mac processes by resident memory (MB) with user, age and a short command name (no arguments), plus swap.
#   host-run bash docker-ws/mac_top_rss.sh [N]
N=${1:-10}
sysctl -n vm.swapusage
ps -axmo pid=,user=,rss=,etime=,comm= | head -n "$N" | awk '{c=$5; for(i=6;i<=NF;i++) c=c" "$i; n=split(c,a,"/"); printf "%s %s %dMB %s %s\n", $1, $2, $3/1024, $4, a[n]}'
