#!/bin/bash
# Read-only: top processes by CPU (pcpu, rss MB, pid, ppid, etime, name).
ps -axo pcpu=,rss=,pid=,ppid=,etime=,comm= | sort -rn | head -n "${1:-15}" | awk '{printf "%6s %6.0f %6s %6s %12s ", $1, $2/1024, $3, $4, $5; $1=$2=$3=$4=$5=""; sub(/^ +/,""); n=split($0,a,"/"); print a[n]}'
