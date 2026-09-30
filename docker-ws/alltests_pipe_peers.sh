#!/bin/bash
# Read-only: other processes sharing pipe objects with a pid.
p=$1
lsof -p $p 2>/dev/null | awk '$5=="PIPE"{print $6}' | sort -u > /tmp/.pp_$$
echo "pipes: $(wc -l < /tmp/.pp_$$)"
lsof 2>/dev/null | awk -v p=$p '$5=="PIPE" && $2!=p {print $6, $2, $1}' | grep -Ff /tmp/.pp_$$ | sort -u | head -20 | while read dev pid cmd; do echo "$dev $pid $(ps -o etime=,command= -p $pid | cut -c1-170)"; done
lsof -p $p 2>/dev/null | awk '$5=="PIPE"{print $4, $6, $9}' | head -12
rm -f /tmp/.pp_$$
