#!/bin/bash
# Plan 414: stop this worktree's lane chain and any flutter test it started.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
pkill -f "$ROOT/docker-ws/pdf414_lanes.sh"
pkill -f "$ROOT/docker-ws/pdf414_lane.sh"
pkill -f "$ROOT/scripts/run_test_gates.sh"
sleep 3
pkill -f "flutter_tools.snapshot test.*pdf-407" 
sleep 2
pgrep -fl "$ROOT/scripts/run_test_gates.sh|pdf414_lane" || echo "no lanes left"
