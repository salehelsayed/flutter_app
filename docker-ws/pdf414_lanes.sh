#!/bin/bash
# Plan 414: run the 1:1, groups and feed lanes one after another.
D="$(cd "$(dirname "$0")" && pwd)"
for lane in 1to1 groups feed completeness-check runtime-roots; do
  echo "=== $lane"
  bash "$D/pdf414_lane.sh" "$lane" | tail -4
done
