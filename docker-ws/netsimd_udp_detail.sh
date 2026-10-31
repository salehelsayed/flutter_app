#!/bin/bash
# Read-only: UDP socket detail for one pid (count, address families, port range buckets, sample).  host-run bash docker-ws/netsimd_udp_detail.sh <pid>
P="${1:?pid}"; [[ "$P" =~ ^[0-9]+$ ]] || exit 2
date -u +%T
lsof -nP -a -p "$P" -iUDP 2>/dev/null | awk 'NR>1{print $5,$9}' > /tmp/nsd_udp.$$
echo "total $(wc -l < /tmp/nsd_udp.$$)"
echo "by family:"; awk '{print $1}' /tmp/nsd_udp.$$ | sort | uniq -c
echo "by bind addr:"; awk '{a=$2; sub(/:[0-9]+$/,"",a); print a}' /tmp/nsd_udp.$$ | sort | uniq -c | sort -rn | head -5
echo "by port bucket:"; awk '{n=split($2,x,":"); p=x[n]+0; b=(p>=49152)?"ephemeral 49152-65535":(p>=1024?"1024-49151":"<1024"); print b}' /tmp/nsd_udp.$$ | sort | uniq -c
echo "connected (has ->): $(grep -c -- '->' /tmp/nsd_udp.$$)"
echo "sample:"; sed -n '1,4p;2000,2003p' /tmp/nsd_udp.$$
echo "fd count $(lsof -nP -p "$P" 2>/dev/null | wc -l)  open-file limit $(launchctl limit maxfiles | awk '{print $2, $3}')"
echo "system UDP sockets total $(netstat -an -p udp 2>/dev/null | grep -c '^udp')"
echo "kern.ipc.maxsockets $(sysctl -n kern.ipc.maxsockets) numsockets $(sysctl -n kern.ipc.numsockets 2>/dev/null)"
rm -f /tmp/nsd_udp.$$
echo "== emulators/qemu"; ps -axo pid=,ppid=,etime=,command= | grep -E 'qemu-system|netsimd|emulator ' | grep -v grep | cut -c1-200
