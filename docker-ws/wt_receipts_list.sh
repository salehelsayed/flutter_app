#!/bin/bash
# Read-only: list .codex-test-logs dirs (name + size) inside build/wt-<name> worktrees.
#   host-run bash docker-ws/wt_receipts_list.sh <name>...
R=/Volumes/CrucialX9/flutter_app/build
for n in "$@"; do
  L="$R/$n/.codex-test-logs"
  [ -d "$L" ] || { echo "$n none"; continue; }
  for d in "$L"/*; do echo "$n $(du -sk "$d" | cut -f1)KB $(basename "$d")"; done
done
