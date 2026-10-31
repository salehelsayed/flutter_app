#!/bin/bash
# Read-only: for each name pattern, show Astra's P0 run dirs, their exit code and the last test-count line.
#   host-run bash docker-ws/astra_p0_file_runs.sh <pattern>...
D=/Volumes/CrucialX9/flutter_app-astra-p0-tests-post129-20261030/.codex-test-logs/p0-inventory-20261030
cd "$D" || exit 2
echo "astra base: $(git -C .. rev-parse --short HEAD 2>/dev/null) merge-base-with-main: $(git -C .. merge-base HEAD f217047f4 2>/dev/null | cut -c1-9)"
for p in "$@"; do for d in $(ls -d p0-test-*"$p"* 2>/dev/null); do
  rc=$(python3 -I -c "import json;print(json.load(open('$d/result.json')).get('exit_code'))" 2>/dev/null)
  last=$(cat "$d"/*.log "$d"/stdout* 2>/dev/null | grep -aoE "[0-9]+:[0-9]+ \+[0-9]+( ~[0-9]+)?( -[0-9]+)?" | tail -1)
  echo "$d rc=$rc $last $(ls "$d" | tr '\n' ' ' | cut -c1-120)"
done; done
