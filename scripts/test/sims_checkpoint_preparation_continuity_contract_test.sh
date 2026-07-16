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
booted_dir="$tmp_dir/booted"
manifest="$tmp_dir/manifest.json"
checkpoint="$tmp_dir/checkpoint.json"
execution_log="$tmp_dir/execution.log"
discovery_log="$tmp_dir/discovery.log"
runner="$tmp_dir/runner.sh"
source_digest=1111111111111111111111111111111111111111111111111111111111111111
sim_a=11111111-1111-1111-1111-111111111111
sim_b=22222222-2222-2222-2222-222222222222
sim_c=33333333-3333-3333-3333-333333333333
sim_d=44444444-4444-4444-4444-444444444444
sim_ids="$sim_a,$sim_b,$sim_c,$sim_d"

mkdir -p "$fake_bin" "$booted_dir"
: >"$execution_log"
: >"$discovery_log"

cat >"$fake_bin/flutter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'flutter %s\n' "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"
case "${1-}" in
  --version)
    printf 'Flutter fixture 1.0.0\n'
    ;;
  devices)
    printf '[]\n'
    ;;
  emulators)
    printf 'No emulators available.\n'
    ;;
  *)
    printf 'unexpected flutter command: %s\n' "$*" >&2
    exit 64
    ;;
esac
SH
chmod +x "$fake_bin/flutter"

cat >"$fake_bin/adb" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'adb %s\n' "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"
if [ "$*" = 'devices -l' ]; then
  printf 'List of devices attached\n'
  exit 0
fi
printf 'unexpected adb command: %s\n' "$*" >&2
exit 64
SH
chmod +x "$fake_bin/adb"

cat >"$fake_bin/xcrun" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'xcrun %s\n' "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"

if [ "$*" = 'simctl list devices available -j' ]; then
  python3 - "${SIMS_FIXTURE_BOOTED_DIR:?}" "${SIMS_FIXTURE_IOS_IDS:?}" <<'PY'
import json
import os
import sys

booted_dir, raw_ids = sys.argv[1:]
devices = []
for index, device_id in enumerate(raw_ids.split(','), start=1):
    devices.append({
        'name': f'Fixture iPhone {index}',
        'udid': device_id,
        'state': 'Booted' if os.path.exists(os.path.join(booted_dir, device_id)) else 'Shutdown',
        'isAvailable': True,
    })
print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-18-0': devices}}))
PY
  exit 0
fi

if [ "${1-}" = simctl ] && [ "${2-}" = boot ]; then
  device_id="${3:?missing simulator ID}"
  case ",${SIMS_FIXTURE_IOS_IDS:?}," in
    *",$device_id,"*) : >"${SIMS_FIXTURE_BOOTED_DIR:?}/$device_id" ;;
    *) exit 64 ;;
  esac
  exit 0
fi

if [ "${1-}" = simctl ] && [ "${2-}" = bootstatus ]; then
  test -f "${SIMS_FIXTURE_BOOTED_DIR:?}/${3:?missing simulator ID}"
  exit 0
fi

printf 'unexpected xcrun command: %s\n' "$*" >&2
exit 64
SH
chmod +x "$fake_bin/xcrun"

cat >"$runner" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

capability_id="${1:?missing capability ID}"
printf '%s\n' "$capability_id" >>"${SIMS_FIXTURE_EXECUTION_LOG:?}"
if [ "${SIMS_FIXTURE_FAIL_ID-}" = "$capability_id" ]; then
  printf '%s\n' 'SIMS_RESULT_JSON={"status":"FAIL","assertionsAttempted":1,"artifactPresent":false,"printOnly":false,"blocker":"product"}'
  exit 17
fi

if [ "$capability_id" = fixture.four_simulators ]; then
  IFS=, read -r expected_a expected_b expected_c expected_d <<<"${SIMS_FIXTURE_IOS_IDS:?}"
  test "${SIMS_IOS_SIMULATOR_A_DEVICE_ID-}" = "$expected_a"
  test "${SIMS_IOS_SIMULATOR_B_DEVICE_ID-}" = "$expected_b"
  test "${SIMS_IOS_SIMULATOR_C_DEVICE_ID-}" = "$expected_c"
  test "${SIMS_IOS_SIMULATOR_D_DEVICE_ID-}" = "$expected_d"
fi

printf '%s\n' 'SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}'
SH
chmod +x "$runner"

cat >"$manifest" <<JSON
{
  "schemaVersion": 1,
  "buildProfiles": [
    {
      "id": "host.fixture",
      "platform": "host",
      "artifactKind": "none",
      "buildRequired": false,
      "compileDefines": {},
      "declaredException": false
    }
  ],
  "capabilities": [
    {
      "id": "fixture.failure",
      "owner": "fixture",
      "proofBoundary": "fixture.checkpoint.preparation.failure",
      "assertions": ["fixture.failure.result"],
      "lane": "host-dart",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["bash", "$runner", "fixture.failure"],
      "buildProfile": "host.fixture",
      "dependencies": [],
      "resources": [{"name": "host.cpu", "access": "read"}],
      "targetCapabilities": [],
      "artifactRequired": false,
      "active": true,
      "declaredBuildException": false
    },
    {
      "id": "fixture.four_simulators",
      "owner": "fixture",
      "proofBoundary": "fixture.checkpoint.preparation.four-simulators",
      "assertions": ["fixture.four_simulators.result"],
      "lane": "device",
      "modes": ["major"],
      "families": ["fixture"],
      "required": true,
      "command": ["bash", "$runner", "fixture.four_simulators"],
      "buildProfile": "host.fixture",
      "dependencies": ["fixture.failure"],
      "resources": [
        {"name": "device:ios-simulator-a", "access": "exclusive"},
        {"name": "device:ios-simulator-b", "access": "exclusive"},
        {"name": "device:ios-simulator-c", "access": "exclusive"},
        {"name": "device:ios-simulator-d", "access": "exclusive"}
      ],
      "targetCapabilities": ["ios.simulator.count4", "ios.simulators.disposable"],
      "artifactRequired": false,
      "active": true,
      "declaredBuildException": false
    }
  ],
  "ownership": []
}
JSON

run_sims() {
  local report_path="$1"
  shift
  local -a authorization=(-u SIMS_IOS_DISPOSABLE_SIMULATOR_IDS)
  if [ "${SIMS_FIXTURE_AUTHORIZE-}" = 1 ]; then
    authorization=("SIMS_IOS_DISPOSABLE_SIMULATOR_IDS=$sim_ids")
  fi

  env "${authorization[@]}" \
    PATH="$fake_bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report_path" \
    SIMS_CHECKPOINT_PATH="$checkpoint" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_SOURCE_DIGEST="$source_digest" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    SIMS_SUITE_SOURCE_DIGEST="$source_digest" \
    SIMS_TEST_ALLOW_SUITE_SOURCE_DIGEST_OVERRIDE=1 \
    SIMS_FIXTURE_EXECUTION_LOG="$execution_log" \
    SIMS_FIXTURE_DISCOVERY_LOG="$discovery_log" \
    SIMS_FIXTURE_BOOTED_DIR="$booted_dir" \
    SIMS_FIXTURE_IOS_IDS="$sim_ids" \
    ./scripts/run_test_gates.sh sims major "$@" --format json
}

# The first run deliberately lacks disposable-simulator authorization. The
# future device row therefore cannot trigger preparation, and the failure
# checkpoint freezes the four launchable (stopped) simulators.
set +e
SIMS_FIXTURE_FAIL_ID=fixture.failure \
  run_sims "$tmp_dir/initial.report.json" --fix-as-you-go \
    >"$tmp_dir/initial.stdout" 2>"$tmp_dir/initial.stderr"
initial_status=$?
set -e
[ "$initial_status" -ne 0 ] || fail 'initial causal failure exited zero'
[ -f "$checkpoint" ] || fail 'initial failure did not persist a checkpoint'
[ -z "$(find "$booted_dir" -type f -print -quit)" ] ||
  fail 'unauthorized initial run prepared a simulator'

initial_digest="$(python3 - "$checkpoint" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    print(json.load(stream)['deviceDigest'])
PY
)"

# Repairing the host failure may authorize later device work, but the focused
# plan itself must remain read-only and retain the stopped inventory digest.
SIMS_FIXTURE_AUTHORIZE=1 \
  run_sims "$tmp_dir/repair.report.json" --only fixture.failure \
    >"$tmp_dir/repair.stdout" 2>"$tmp_dir/repair.stderr" ||
  fail 'focused checkpoint repair failed'
[ -z "$(find "$booted_dir" -type f -print -quit)" ] ||
  fail 'focused host repair prepared a simulator outside its selected plan'

repair_digest="$(python3 - "$checkpoint" <<'PY'
import json
import sys
with open(sys.argv[1], encoding='utf-8') as stream:
    print(json.load(stream)['deviceDigest'])
PY
)"
[ "$repair_digest" = "$initial_digest" ] ||
  fail 'focused repair changed the read-only device checkpoint digest'

# Resume is allowed to boot the explicitly authorized targets. Validation must
# compare the checkpoint with the entry inventory, while persisted evidence
# records the connected inventory produced by Sims-owned preparation.
SIMS_FIXTURE_AUTHORIZE=1 \
  run_sims "$tmp_dir/resume.report.json" --resume \
    >"$tmp_dir/resume.stdout" 2>"$tmp_dir/resume.stderr" || {
      sed -n '1,160p' "$tmp_dir/resume.stderr" >&2
      fail 'resume rejected its own simulator preparation'
    }

[ "$(find "$booted_dir" -type f | wc -l | tr -d ' ')" = 4 ] ||
  fail 'resume did not prepare all four authorized simulators'
[ "$(tail -n 1 "$execution_log")" = fixture.four_simulators ] ||
  fail 'resume did not dispatch the newly prepared device row'

python3 - "$checkpoint" "$tmp_dir/resume.report.json" "$initial_digest" \
  "$sim_ids" <<'PY'
import json
import sys

checkpoint_path, report_path, initial_digest, raw_ids = sys.argv[1:]
with open(checkpoint_path, encoding='utf-8') as stream:
    checkpoint = json.load(stream)
with open(report_path, encoding='utf-8') as stream:
    report = json.load(stream)

post_digest = report.get('devices', {}).get('inventoryDigest')
if not post_digest or post_digest == initial_digest:
    raise SystemExit('FAIL: report did not retain the post-preparation inventory digest')
if checkpoint.get('deviceDigest') != post_digest:
    raise SystemExit('FAIL: progress checkpoint did not retain the post-preparation inventory digest')
if checkpoint.get('passedIds') != ['fixture.failure', 'fixture.four_simulators']:
    raise SystemExit('FAIL: resume did not preserve both exact PASS verdicts')

assignments = report.get('devices', {}).get('assignments', {})
expected = dict(zip(
    [
        'device:ios-simulator-a',
        'device:ios-simulator-b',
        'device:ios-simulator-c',
        'device:ios-simulator-d',
    ],
    raw_ids.split(','),
))
if assignments != expected:
    raise SystemExit(f'FAIL: prepared assignments {assignments} != {expected}')
PY

# The next resume observes the persisted connected matrix on entry and must
# validate without issuing another boot command.
boot_count_before="$(rg -c '^xcrun simctl boot ' "$discovery_log" || true)"
SIMS_FIXTURE_AUTHORIZE=1 \
  run_sims "$tmp_dir/second-resume.report.json" --resume \
    >"$tmp_dir/second-resume.stdout" 2>"$tmp_dir/second-resume.stderr" ||
  fail 'second resume rejected the persisted connected inventory'
boot_count_after="$(rg -c '^xcrun simctl boot ' "$discovery_log" || true)"
[ "$boot_count_after" = "$boot_count_before" ] ||
  fail 'second resume rebooted already connected simulators'

printf 'PASS: sims checkpoint continuity across live target preparation\n'
