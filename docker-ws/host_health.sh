#!/bin/bash
# Read-only Mac health snapshot: disk, swap, memory pressure, load, top memory users.
#   host-run bash docker-ws/host_health.sh [top N]
N="${1:-25}"
echo "time $(date -u +%FT%TZ)"
df -h / /Volumes/CrucialX9 2>/dev/null | awk 'NR==1 || /\//{print "df " $0}'
echo "swap $(sysctl -n vm.swapusage)"
echo "load $(sysctl -n vm.loadavg)"
echo "ram_gb $(( $(sysctl -n hw.memsize) / 1073741824 ))"
vm_stat | awk '/Swapins|Swapouts|Pageouts/ {gsub(/\./,"",$NF); printf "vm %s %s\n", $1, $NF}'
memory_pressure -Q 2>/dev/null | tail -1 | sed 's/^/mem /'
echo "--- top $N by RSS (MB pid ppid etime command)"
ps -axo rss=,pid=,ppid=,etime=,comm= | sort -rn | head -n "$N" | awk '{printf "%7.0f %6s %6s %12s ", $1/1024, $2, $3, $4; $1=$2=$3=$4=""; sub(/^ +/,""); n=split($0,a,"/"); print a[n]}'
echo "--- counts"
for p in dartvm flutter_tester java qemu-system-aarch64 xcodebuild simctl idevicesyslog node python3 Python gradle kotlin; do c=$(pgrep -x "$p" 2>/dev/null | wc -l | tr -d ' '); [ "$c" != 0 ] && echo "$p $c"; done
echo "--- booted simulators"
xcrun simctl list devices booted 2>/dev/null | grep -E '\(Booted\)' | sed -E 's/\(([0-9A-F-]{36})\)/(<sim>)/'
