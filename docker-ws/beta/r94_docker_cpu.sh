#!/bin/bash
# Read-only: CPU per Docker container, and the busiest processes inside each running one.
export PATH="/usr/local/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"
docker stats --no-stream --format '{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' 2>&1 | head -20
for c in $(docker ps --format '{{.Names}}' 2>/dev/null); do
  echo "--- $c"
  docker exec "$c" sh -c 'ps -eo pid,pcpu,etime,args --sort=-pcpu 2>/dev/null | head -6' 2>/dev/null | cut -c1-200
done
