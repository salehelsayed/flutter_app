#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

readonly REPEAT_COUNT="${GO012_REPEAT_COUNT:-5}"

run_iteration() {
  local iteration="$1"
  printf 'GO-012 fake flake-budget pass %s/%s\n' "$iteration" "$REPEAT_COUNT"

  flutter test --no-pub test/shared/fakes/fake_group_pubsub_network_test.dart

  flutter test --no-pub \
    test/features/groups/integration/group_messaging_smoke_test.dart \
    --name 'GE-017|GE-019|GE-020|message is received after app restart with rejoin'

  flutter test --no-pub \
    test/features/groups/integration/group_resume_recovery_test.dart \
    --name 'watchdog restart rejoins topics and receives subsequent live messages|GP-026 same message is not duplicated if both pubsub and group inbox deliver it|offline remaining member drains remove-vs-send backlog'
}

for iteration in $(seq 1 "$REPEAT_COUNT"); do
  run_iteration "$iteration"
done

printf 'GO-012 fake flake budget passed: %s iterations, 0 failures\n' "$REPEAT_COUNT"
