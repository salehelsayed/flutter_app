#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Exercise the aggregate in a minimal staged repository so its only discovered
# row is VC2-04 and the device boundary is a harmless argv-recording fake.
staged_repo="$tmp_dir/repo"
mkdir -p "$staged_repo/scripts"
cp scripts/run_reliability_simulations.sh "$staged_repo/scripts/"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "${1:-}" == "--records-tsv" ]] || exit 64' \
  'printf "1to1\\trunner\\tscripts/run_vc204_android_call_lifecycle_e2e.sh\\tVC2-04 fixture\\n"' \
  >"$staged_repo/scripts/check_reliability_simulation_discovery.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "%s\\n" "$@" >"${VC204_TEST_INVOCATION_LOG:?}"' \
  >"$staged_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh"

chmod +x \
  "$staged_repo/scripts/check_reliability_simulation_discovery.sh" \
  "$staged_repo/scripts/run_reliability_simulations.sh" \
  "$staged_repo/scripts/run_vc204_android_call_lifecycle_e2e.sh"

# Keep the aggregate's unrelated transport-process preflight deterministic.
fake_bin="$tmp_dir/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$fake_bin/ps"
chmod +x "$fake_bin/ps"
export PATH="$fake_bin:$PATH"

aggregate="$staged_repo/scripts/run_reliability_simulations.sh"
runner_path="scripts/run_vc204_android_call_lifecycle_e2e.sh"
device_id="emulator-5554"
artifact_dir="$tmp_dir/reusable artifacts"
result_dir="$tmp_dir/reusable results"
invocation_log="$tmp_dir/invocation.log"

dry_output="$(
  VC204_TEST_INVOCATION_LOG="$invocation_log" \
  RELIABILITY_SINGLE_DEVICE_ID="$device_id" \
  RELIABILITY_VC204_ARTIFACT_DIR="$artifact_dir" \
  RELIABILITY_VC204_RESULT_DIR="$result_dir" \
    "$aggregate" 1to1 --dry-run \
      --only "$runner_path:vc204_android_call_lifecycle"
)"

expected_display="./$runner_path --device-id '$device_id' --artifact-dir '$artifact_dir' --result-dir '$result_dir' --scenario 'vc204_android_call_lifecycle'"
grep -Fq -- "$expected_display" <<<"$dry_output" ||
  fail 'VC2-04 dry-run did not display every explicit runner input'
runner_plan_lines="$(grep -F -- "./$runner_path" <<<"$dry_output" || true)"
if grep -Fv -- ' --device-id ' <<<"$runner_plan_lines" | grep -q .; then
  fail 'VC2-04 dry-run retained a bare runner command'
fi
grep -Fq 'Dry run only. Discovery passed and no commands were executed.' \
  <<<"$dry_output" ||
  fail 'VC2-04 dry-run did not truthfully report that it skipped execution'
[ ! -e "$invocation_log" ] || fail 'VC2-04 dry-run invoked the device runner'

assert_missing_input_fails_closed() {
  local missing_name="$1"
  local expected_message="$2"
  local output
  local status

  : >"$invocation_log"
  set +e
  output="$(
    VC204_TEST_INVOCATION_LOG="$invocation_log" \
    RELIABILITY_SINGLE_DEVICE_ID="${VC204_TEST_DEVICE_ID:-}" \
    FLUTTER_DEVICE_ID= \
    RELIABILITY_VC204_ARTIFACT_DIR="${VC204_TEST_ARTIFACT_DIR:-}" \
    RELIABILITY_VC204_RESULT_DIR="${VC204_TEST_RESULT_DIR:-}" \
      "$aggregate" 1to1 --only "$runner_path" 2>&1
  )"
  status=$?
  set -e

  [ "$status" -eq 64 ] ||
    fail "missing $missing_name exited $status instead of 64"
  grep -Fq -- "$expected_message" <<<"$output" ||
    fail "missing $missing_name did not explain its required input"
  [ ! -s "$invocation_log" ] ||
    fail "missing $missing_name reached the VC2-04 runner"
}

VC204_TEST_DEVICE_ID= \
VC204_TEST_ARTIFACT_DIR="$artifact_dir" \
VC204_TEST_RESULT_DIR="$result_dir" \
  assert_missing_input_fails_closed \
    'device ID' 'Missing explicit Android device ID for scripts/run_vc204_android_call_lifecycle_e2e.sh.'

VC204_TEST_DEVICE_ID="$device_id" \
VC204_TEST_ARTIFACT_DIR= \
VC204_TEST_RESULT_DIR="$result_dir" \
  assert_missing_input_fails_closed \
    'artifact directory' 'Missing explicit artifact directory for scripts/run_vc204_android_call_lifecycle_e2e.sh.'

VC204_TEST_DEVICE_ID="$device_id" \
VC204_TEST_ARTIFACT_DIR="$artifact_dir" \
VC204_TEST_RESULT_DIR= \
  assert_missing_input_fails_closed \
    'result directory' 'Missing explicit result directory for scripts/run_vc204_android_call_lifecycle_e2e.sh.'

: >"$invocation_log"
VC204_TEST_INVOCATION_LOG="$invocation_log" \
RELIABILITY_SINGLE_DEVICE_ID="$device_id" \
RELIABILITY_VC204_ARTIFACT_DIR="$artifact_dir" \
RELIABILITY_VC204_RESULT_DIR="$result_dir" \
  "$aggregate" 1to1 --only "$runner_path" >/dev/null

expected_argv="$tmp_dir/expected-argv.txt"
printf '%s\n' \
  --device-id "$device_id" \
  --artifact-dir "$artifact_dir" \
  --result-dir "$result_dir" \
  --scenario vc204_android_call_lifecycle \
  >"$expected_argv"
cmp -s "$expected_argv" "$invocation_log" ||
  fail 'aggregate did not execute VC2-04 with the exact explicit argv contract'

printf 'PASS: VC2-04 reliability aggregate contract\n'
