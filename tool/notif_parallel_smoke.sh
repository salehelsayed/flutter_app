#!/usr/bin/env bash
# Phase G2b (plan 120) — the true G2 acceptance gate.
#
# Runs the notification/group/integration/push suites under PARALLEL
# `flutter test -j 4` in a loop, asserting ZERO flake. Before Phase G2's
# per-test gate isolation (test/flutter_test_config.dart), these suites raced
# on the shared module-global notification gates and only passed at `-j 1`;
# with isolation they must be deterministically green at -j 4 across N runs.
#
# Usage:
#   bash tool/notif_parallel_smoke.sh [N]
# N defaults to 20. Exits non-zero on the FIRST iteration that fails.

set -u

N="${1:-20}"
SHARDS=(
  test/features/groups/
  test/integration/
  test/features/push/
)

echo "notif_parallel_smoke: ${N} iterations of 'flutter test ${SHARDS[*]} -j 4'"

for ((i = 1; i <= N; i++)); do
  echo "===== iteration ${i}/${N} ====="
  if ! flutter test "${SHARDS[@]}" -j 4; then
    echo "FLAKE: iteration ${i}/${N} failed under -j 4 parallelism." >&2
    exit 1
  fi
done

echo "notif_parallel_smoke: PASS — ${N}/${N} iterations green under -j 4, zero flake."
