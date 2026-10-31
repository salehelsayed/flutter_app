#!/bin/bash
# Read-only: how many TRACKED files and how many untracked docker-ws files contain the relay hosts/IPs/peer IDs.
# Prints counts only.   host-run bash docker-ws/main_ident_census.sh
M=/Volumes/CrucialX9/flutter_app; cd "$M" || exit 2
L=.codex-test-logs/p0-merge-20261031/untracked_scan.txt.list
for p in '51.21.194.144' '2-29-62-121.sslip.io' 'mknoun.xyz' '12D3KooWB2HGqKUNt9sX' '12D3KooWGMYMmN1RGUYj' '21071FDF600CSC' '00008110-00184D622289801E'; do
  t=$(git grep -l -F -- "$p" 2>/dev/null | wc -l | tr -d ' ')
  u=$(xargs grep -l -F -- "$p" < "$L" 2>/dev/null | wc -l | tr -d ' ')
  echo "$p tracked_files=$t untracked_docker_ws_files=$u"
done
