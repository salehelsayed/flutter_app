#!/bin/bash
# Read-only: find processes whose pipe NAME/device references the given pid's pipe addresses.
p=$1
addrs=$(lsof -p $p 2>/dev/null | awk '$5=="PIPE"{print $6}' | sort -u)
all=$(lsof -nP 2>/dev/null | awk '$5=="PIPE"')
for a in $addrs; do echo "$all" | grep -F -- "$a" | awk -v p=$p '$2!=p{print $1, $2, $4, $6, $9}'; done | sort -u | head -20
