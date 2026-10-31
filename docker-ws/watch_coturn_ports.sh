#!/bin/bash
# Read-only: poll docker for coturn containers and print their published ports (max ~3-5 min).
PATH=/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin
for i in $(seq 1 1500); do
  L=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | grep -i coturn)
  [ -n "$L" ] && { date -u +%T; echo "$L" | sed -E 's/[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/<ip>/g' | cut -c1-400; exit 0; }
  sleep 0.1
done; echo "no coturn container seen"
