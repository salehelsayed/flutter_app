#!/bin/bash
# Read-only: sample descendants of a pid every 2 s for N seconds; print unique commands.
root=$1; n=${2:-40}; end=$((SECONDS+n)); out=$(mktemp)
desc() { for c in $(pgrep -P $1); do ps -o command= -p $c | cut -c1-200; desc $c; done; }
while ((SECONDS<end)); do desc $root >> "$out"; sleep 2; done
sort "$out" | uniq -c | sort -rn | head -15; rm -f "$out"
