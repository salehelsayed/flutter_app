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

fake_bin="$tmp_dir/bin"
activity_log="$tmp_dir/activity.log"
real_flutter="$(command -v flutter)"
mkdir -p "$fake_bin"
touch "$activity_log"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'target="integration_test/group_lifecycle_simulator_harness.dart"' \
  'for arg in "$@"; do' \
  '  if [ "$arg" = "$target" ]; then' \
  '    printf "START\tdevice-build\t%s\n" "$$" >>"${SIMS_ACTIVITY_LOG:?}"' \
  '    sleep 0.1' \
  '    printf "END\tdevice-build\t%s\n" "$$" >>"${SIMS_ACTIVITY_LOG:?}"' \
  '    exit 0' \
  '  fi' \
  'done' \
  'exec "${REAL_FLUTTER:?}" "$@"' \
  >"$fake_bin/flutter"

chmod +x "$fake_bin/flutter"
export PATH="$fake_bin:$PATH"
export REAL_FLUTTER="$real_flutter"
export SIMS_ACTIVITY_LOG="$activity_log"

# Host-safe work uses the existing exact-path Flutter batch. The caller can
# bound it without having to know the lower-level host gate flags.
host_plan="$({
  SIMS_HOST_CONCURRENCY=3 \
    ./.claude/skills/sims/scripts/run_with_devices.sh \
      host-all --repo "$ROOT_DIR" --simultaneous --list
})"
grep -Fq 'Simultaneous policy: host Flutter tests use bounded concurrency=3; Go tails remain serial.' \
  <<<"$host_plan" ||
  fail 'host-all did not explain its simultaneous resource policy'
grep -Fq 'concurrency=3, reporter=failures-only' <<<"$host_plan" ||
  fail 'host-all did not map --simultaneous to the bounded Flutter batch'

# Performance measurements are deliberately exclusive even when the flag is
# supplied; concurrent neighbors would make their budgets meaningless.
performance_plan="$({
  ./.claude/skills/sims/scripts/run_with_devices.sh \
    performance-host --repo "$ROOT_DIR" --simultaneous --list
})"
grep -Fq 'Simultaneous policy: performance-host is exclusive; running serially.' \
  <<<"$performance_plan" ||
  fail 'performance-host did not remain exclusive under --simultaneous'
if grep -Fq 'Batch execution shape:' <<<"$performance_plan"; then
  fail 'performance-host was incorrectly converted to a concurrent batch'
fi

# Legacy reliability scheduling is fail-closed. Artifact-only validators are
# support owned by their captures and no longer appear as executable rows. All
# legacy rows serialize; typed overlap belongs to the sims manifest scheduler.
reliability_plan="$({
  SIMS_MAX_PARALLEL=2 ./scripts/run_reliability_simulations.sh \
    group --simultaneous --list
})"
grep -Fq \
  'Simultaneous policy: legacy reliability rows serialize; typed resource-aware overlap is owned by the sims manifest scheduler (compatibility max 2).' \
  <<<"$reliability_plan" ||
  fail 'reliability plan omitted the fail-closed simultaneous policy'
grep -Fq '[resource: exclusive-shared-device-build]' <<<"$reliability_plan" ||
  fail 'reliability plan did not mark shared device/build work exclusive'
if grep -Fq '[resource: post-capture-validator]' <<<"$reliability_plan"; then
  fail 'legacy plan retained a path-based post-capture validator allowlist'
fi

set +e
support_output="$({
  ./scripts/run_reliability_simulations.sh group --simultaneous --list \
    --only integration_test/scripts/validate_group_reaction_notification_artifacts.dart
} 2>&1)"
support_status=$?
set -e
[ "$support_status" -ne 0 ] ||
  fail 'capture-owned support validator remained executable in the legacy plan'
grep -Fq 'No runnable reliability simulation commands matched' <<<"$support_output" ||
  fail 'removed support validator did not fail with the expected selection error'

# Four rows sharing one Flutter device/build resource stay strictly serial.
: >"$activity_log"
SIMS_MAX_PARALLEL=4 ./scripts/run_reliability_simulations.sh \
  group --simultaneous \
  --only integration_test/group_lifecycle_simulator_harness.dart \
  >/dev/null
awk '
  $1 == "START" { active++; if (active > 1) bad = 1 }
  $1 == "END" { active-- }
  END { exit bad || active != 0 ? 1 : 0 }
' "$activity_log" ||
  fail 'shared device/build scenarios overlapped under --simultaneous'

set +e
invalid_output="$({
  SIMS_MAX_PARALLEL=0 ./scripts/run_reliability_simulations.sh \
    group --simultaneous --list
} 2>&1)"
invalid_status=$?
set -e
[ "$invalid_status" -eq 2 ] ||
  fail "invalid SIMS_MAX_PARALLEL exited with $invalid_status instead of 2"
grep -Fq 'Invalid SIMS_MAX_PARALLEL: 0' <<<"$invalid_output" ||
  fail 'invalid SIMS_MAX_PARALLEL did not explain the accepted range'

printf 'PASS: sims simultaneous scheduling contract\n'
