#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

multi_party_scenarios_from_plan() {
  sed -n 's/.*dart run integration_test\/scripts\/run_group_multi_party_device_real\.dart --scenario \([^ ]*\).*/\1/p' |
    tr -d "'"
}

scenario_count() {
  awk 'NF { count++ } END { print count + 0 }'
}

expected_smoke="$(
  dart integration_test/scripts/run_group_multi_party_device_real.dart \
    --scenario smoke \
    --list-scenarios
)"
expected_full="$(
  dart integration_test/scripts/run_group_multi_party_device_real.dart \
    --scenario all \
    --list-scenarios
)"
expected_smoke_count="$(printf '%s\n' "$expected_smoke" | scenario_count)"
expected_full_count="$(printf '%s\n' "$expected_full" | scenario_count)"

smoke_output="$(
  RELIABILITY_GROUP_TIER=smoke ./scripts/run_reliability_simulations.sh group --list
)"
actual_smoke="$(
  printf '%s\n' "$smoke_output" | multi_party_scenarios_from_plan
)"
actual_smoke_count="$(printf '%s\n' "$actual_smoke" | scenario_count)"

[ "$actual_smoke" = "smoke" ] ||
  fail "smoke tier plan did not collapse to --scenario smoke"
[ "$actual_smoke_count" = "1" ] ||
  fail "smoke tier planned $actual_smoke_count rows, expected 1"
[ "$actual_smoke_count" != "$expected_full_count" ] ||
  fail "smoke tier unexpectedly planned the full scenario count"
printf '%s\n' "$smoke_output" | grep -q 'Group multi-party tier: smoke' ||
  fail "smoke tier plan header did not name the selected tier"

default_output="$(./scripts/run_reliability_simulations.sh group --list)"
default_scenarios="$(
  printf '%s\n' "$default_output" | multi_party_scenarios_from_plan
)"
[ "$default_scenarios" = "all" ] ||
  fail "default tier did not collapse to --scenario all"
[ "$(printf '%s\n' "$default_scenarios" | scenario_count)" = "1" ] ||
  fail "default tier planned more than one multi-party row"

full_output="$(
  RELIABILITY_GROUP_TIER=full ./scripts/run_reliability_simulations.sh group --list
)"
full_scenarios="$(
  printf '%s\n' "$full_output" | multi_party_scenarios_from_plan
)"
[ "$full_scenarios" = "all" ] ||
  fail "full tier did not collapse to --scenario all"
[ "$(printf '%s\n' "$full_scenarios" | scenario_count)" = "1" ] ||
  fail "full tier planned more than one multi-party row"
printf '%s\n' "$full_output" | grep -q 'Group multi-party tier: full' ||
  fail "full tier plan header did not name the selected tier"

only_output="$(
  ./scripts/run_reliability_simulations.sh group --list --only private_abc_create
)"
only_scenarios="$(
  printf '%s\n' "$only_output" | multi_party_scenarios_from_plan
)"
[ "$only_scenarios" = "private_abc_create" ] ||
  fail "--only <scenario-id> did not preserve a single-scenario multi-party row"

path_only_output="$(
  ./scripts/run_reliability_simulations.sh group --list \
    --only integration_test/scripts/run_group_multi_party_device_real.dart:private_reaction_roundtrip
)"
path_only_scenarios="$(
  printf '%s\n' "$path_only_output" | multi_party_scenarios_from_plan
)"
[ "$path_only_scenarios" = "private_reaction_roundtrip" ] ||
  fail "--only path:scenario did not preserve a single-scenario multi-party row"

set +e
bad_output="$(
  RELIABILITY_GROUP_TIER=bogus ./scripts/run_reliability_simulations.sh group --list 2>&1
)"
bad_status=$?
set -e

[ "$bad_status" -ne 0 ] || fail "invalid RELIABILITY_GROUP_TIER unexpectedly succeeded"
printf '%s\n' "$bad_output" | grep -q 'Invalid RELIABILITY_GROUP_TIER' ||
  fail "invalid RELIABILITY_GROUP_TIER did not fail loudly"

printf 'PASS: reliability group tier contract\n'
