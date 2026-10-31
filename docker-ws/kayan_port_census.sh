#!/bin/bash
# Read-only census of local TCP/UDP sockets per process (Kayan, 2026-10-20).
echo "== time"; date -u
echo "== ephemeral range"; sysctl net.inet.ip.portrange.first net.inet.ip.portrange.last 2>/dev/null
echo "== sockets per process (top 12)"
lsof -nP -iTCP -iUDP 2>/dev/null | awk 'NR>1{print $1" "$2}' | sort | uniq -c | sort -rn | head -12
echo "== top process detail"
TOP=$(lsof -nP -iTCP -iUDP 2>/dev/null | awk 'NR>1{print $2}' | sort | uniq -c | sort -rn | head -3 | awk '{print $2}')
for P in $TOP; do
  echo "-- pid $P"; ps -o pid=,ppid=,etime=,command= -p "$P" | cut -c1-300
  echo "   by state:"; lsof -nP -a -p "$P" -iTCP -iUDP 2>/dev/null | awk 'NR>1{s=$NF; if($8=="UDP")s="UDP"; print s}' | sort | uniq -c | sort -rn | head -6
  echo "   sample:"; lsof -nP -a -p "$P" -iTCP -iUDP 2>/dev/null | sed -n '2,6p' | awk '{print $1,$5,$8,$9,$10}'
done
echo "== total TCP/UDP sockets"; lsof -nP -iTCP -iUDP 2>/dev/null | wc -l
