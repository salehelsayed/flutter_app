#!/bin/bash
# Read-only: sample a pid's children once a second for N seconds; print each distinct child command.
for i in $(seq 1 ${2:-20}); do
  for c in $(pgrep -P "$1"); do ps -o command= -p "$c" | cut -c1-160; for g in $(pgrep -P "$c"); do ps -o command= -p "$g" | cut -c1-160 | sed 's/^/  /'; done; done
  sleep 1
done | sort | uniq -c | sort -rn | head -12
echo "alive: $(ps -o etime= -p $1)"
