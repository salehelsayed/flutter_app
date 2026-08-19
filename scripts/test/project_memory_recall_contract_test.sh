#!/usr/bin/env bash
#
# Registered gate for the project-memory deterministic recall layer (plan 381).
#
# Legs: build the graph from the live plan corpus -> run the contract suite ->
# run the gated-question eval (run_eval.py --gate prints its own N/N count;
# 18 as of plan 382). Pure python3 + stdlib sqlite3, so this is
# container-runnable: the scripts/test host-run rule binds gates that invoke
# dart/flutter, and this one invokes neither.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || fail 'python3 not on PATH'

# Leg 1 -- deterministic build over the real corpus, census floor enforced.
python3 project-memory/src/build_graph.py ||
  fail 'build_graph.py failed (census floor violated, or the parser regressed)'

# Leg 2 -- the contract suite (TC-381-01..10).
python3 project-memory/tests/test_project_memory.py ||
  fail 'project-memory contract suite red'

# Leg 3 -- the eval gate: 12 v1-scope questions, every required fact present
# within the token cap.
python3 project-memory/src/run_eval.py --gate ||
  fail 'eval gate red (a v1-scope question lost a required fact)'

printf 'PASS: project-memory build + contract suite + recall eval gate\n'
