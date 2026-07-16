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
artifact_dir="$tmp_dir/artifacts"
discovery_log="$tmp_dir/discovery.log"
runner="$tmp_dir/checkpoint_fixture.sh"
execution_log="$tmp_dir/execution.log"
checkpoint="$tmp_dir/checkpoint.json"
manifest="$tmp_dir/manifest.json"
proof="$tmp_dir/first-proof.json"
unrelated_proof="$tmp_dir/unrelated-proof.json"
source_v1=1111111111111111111111111111111111111111111111111111111111111111
source_v2=2222222222222222222222222222222222222222222222222222222222222222
mkdir -p "$fake_bin" "$artifact_dir"
touch "$execution_log"
touch "$discovery_log"
printf '{"fixture":"first"}\n' >"$proof"
printf '{"fixture":"unrelated"}\n' >"$unrelated_proof"
proof_digest="$(shasum -a 256 "$proof" | awk '{print $1}')"
unrelated_proof_digest="$(shasum -a 256 "$unrelated_proof" | awk '{print $1}')"

# Read-only discovery and central-build shims keep the mixed host/device
# checkpoint regression causal without touching a live target.
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "flutter %s\n" "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"' \
  'case "${1-}" in' \
  '  --version)' \
  '    printf "Flutter fixture 1.0.0\n"' \
  '    ;;' \
  '  devices)' \
  '    id="${SIMS_FIXTURE_ANDROID_ID:-fixture-android}"' \
  '    row="{\"name\":\"Fixture Android\",\"id\":\"$id\",\"targetPlatform\":\"android-arm64\",\"emulator\":false,\"isSupported\":true,\"connectionInterface\":\"usb\"}"' \
  '    if [ "${SIMS_FIXTURE_DUPLICATE_FLUTTER_ROW-}" = 1 ]; then' \
  '      printf '\''[%s,%s]\n'\'' "$row" "$row"' \
  '    else' \
  '      printf '\''[%s]\n'\'' "$row"' \
  '    fi' \
  '    ;;' \
  '  emulators)' \
  '    printf "No emulators available.\n"' \
  '    ;;' \
  '  build)' \
  '    test -n "${SIMS_BUILD_PROFILE-}"' \
  '    artifact="${SIMS_FIXTURE_ARTIFACT_DIR:?}/${SIMS_BUILD_PROFILE}.apk"' \
  '    printf "fixture build for %s\n" "$SIMS_BUILD_PROFILE" >"$artifact"' \
  '    printf "SIMS_BUILD_ARTIFACT=%s\n" "$artifact"' \
  '    ;;' \
  '  *)' \
  '    printf "unexpected flutter command: %s\n" "$*" >&2' \
  '    exit 64' \
  '    ;;' \
  'esac' \
  >"$fake_bin/flutter"
chmod +x "$fake_bin/flutter"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "adb %s\n" "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"' \
  'if [ "$*" = "devices -l" ]; then' \
  '  id="${SIMS_FIXTURE_ANDROID_ID:-fixture-android}"' \
  '  printf "List of devices attached\n%s device usb:1-1 product:fixture model:Fixture_Android transport_id:1\n" "$id"' \
  '  exit 0' \
  'fi' \
  'printf "unexpected adb command: %s\n" "$*" >&2' \
  'exit 64' \
  >"$fake_bin/adb"
chmod +x "$fake_bin/adb"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "xcrun %s\n" "$*" >>"${SIMS_FIXTURE_DISCOVERY_LOG:?}"' \
  'if [ "$*" = "simctl list devices available -j" ]; then' \
  '  printf '\''%s\n'\'' '\''{"devices":{}}'\''' \
  '  exit 0' \
  'fi' \
  'printf "unexpected xcrun command: %s\n" "$*" >&2' \
  'exit 64' \
  >"$fake_bin/xcrun"
chmod +x "$fake_bin/xcrun"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'id="${1:?missing stable ID}"' \
  'printf "%s\n" "$id" >>"${SIMS_FIXTURE_EXECUTION_LOG:?}"' \
  'if [ "${SIMS_FIXTURE_FAIL_ID-}" = "$id" ]; then' \
  '  printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"FAIL","assertionsAttempted":1,"artifactPresent":false,"printOnly":false,"blocker":"product"}'\''' \
  '  exit 17' \
  'fi' \
  'if [ "$id" = fixture.first ]; then' \
  '  printf '\''SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false,"artifactEvidence":{"path":"%s","sha256":"%s","validatorIds":["fixture.first.validator"]}}\n'\'' "${SIMS_FIXTURE_PROOF_PATH:?}" "${SIMS_FIXTURE_PROOF_DIGEST:?}"' \
  '  exit 0' \
  'fi' \
  'if [ "$id" = fixture.unrelated ]; then' \
  '  printf '\''SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false,"artifactEvidence":{"path":"%s","sha256":"%s","validatorIds":["fixture.unrelated.validator"]}}\n'\'' "${SIMS_FIXTURE_UNRELATED_PROOF_PATH:?}" "${SIMS_FIXTURE_UNRELATED_PROOF_DIGEST:?}"' \
  '  exit 0' \
  'fi' \
  'printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false}'\''' \
  >"$runner"
chmod +x "$runner"

write_manifest() {
  local path="$1"
  local revision="$2"

  printf '%s\n' \
    '{' \
    '  "schemaVersion": 1,' \
    '  "buildProfiles": [' \
    '    {' \
    '      "id": "host.fixture",' \
    '      "platform": "host",' \
    '      "artifactKind": "none",' \
    '      "buildRequired": false,' \
    '      "compileDefines": {},' \
    '      "declaredException": false' \
    '    },' \
    '    {' \
    '      "id": "android.fixture.device",' \
    '      "platform": "android",' \
    '      "artifactKind": "apk",' \
    '      "buildRequired": true,' \
    '      "compileDefines": {},' \
    '      "declaredException": false' \
    '    }' \
    '  ],' \
    '  "capabilities": [' \
    '    {' \
    '      "id": "fixture.first",' \
    '      "owner": "fixture",' \
    "      \"proofBoundary\": \"fixture.first.$revision\"," \
    '      "assertions": ["fixture.first.assertion"],' \
    '      "lane": "host-dart",' \
    '      "modes": ["major", "full"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"fixture.first\"]," \
    '      "buildProfile": "host.fixture",' \
    '      "dependencies": [],' \
    '      "resources": [{"name": "host.cpu", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.first.validator",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.unrelated",' \
    '      "owner": "fixture",' \
    "      \"proofBoundary\": \"fixture.unrelated.$revision\"," \
    '      "assertions": ["fixture.unrelated.assertion"],' \
    '      "lane": "host-dart",' \
    '      "modes": ["major", "full"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"fixture.unrelated\"]," \
    '      "buildProfile": "host.fixture",' \
    '      "dependencies": [],' \
    '      "resources": [{"name": "host.cpu", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.unrelated.validator",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.middle",' \
    '      "owner": "fixture",' \
    "      \"proofBoundary\": \"fixture.middle.$revision\"," \
    '      "assertions": ["fixture.middle.assertion"],' \
    '      "lane": "host-dart",' \
    '      "modes": ["major", "full"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"fixture.middle\"]," \
    '      "buildProfile": "host.fixture",' \
    '      "dependencies": ["fixture.first"],' \
    '      "resources": [{"name": "host.cpu", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": false,' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.device",' \
    '      "owner": "fixture",' \
    "      \"proofBoundary\": \"fixture.device.$revision\"," \
    '      "assertions": ["fixture.device.assertion"],' \
    '      "lane": "device",' \
    '      "modes": ["major", "full"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"fixture.device\"]," \
    '      "buildProfile": "android.fixture.device",' \
    '      "dependencies": ["fixture.middle"],' \
    '      "resources": [' \
    '        {"name": "build:android.fixture.device", "access": "read"},' \
    '        {"name": "device:android-physical", "access": "exclusive"}' \
    '      ],' \
    '      "targetCapabilities": ["android.physical"],' \
    '      "artifactRequired": false,' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    },' \
    '    {' \
    '      "id": "fixture.last",' \
    '      "owner": "fixture",' \
    "      \"proofBoundary\": \"fixture.last.$revision\"," \
    '      "assertions": ["fixture.last.assertion"],' \
    '      "lane": "host-dart",' \
    '      "modes": ["major", "full"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$runner\", \"fixture.last\"]," \
    '      "buildProfile": "host.fixture",' \
    '      "dependencies": ["fixture.device"],' \
    '      "resources": [{"name": "host.cpu", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": false,' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    }' \
    '  ],' \
    '  "ownership": []' \
    '}' \
    >"$path"
}

run_sims() {
  local report_path="$1"
  shift
  local mode=major
  case "${1-}" in
    major|full|smoke)
      mode="$1"
      shift
      ;;
  esac
  env -u SIMS_ANDROID_PHYSICAL_DEVICE_ID \
    PATH="$fake_bin:$PATH" \
    SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report_path" \
    SIMS_CHECKPOINT_PATH="${SIMS_FIXTURE_CHECKPOINT_PATH:-$checkpoint}" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_SOURCE_DIGEST="${SIMS_FIXTURE_SOURCE_DIGEST:-$source_v1}" \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    SIMS_SUITE_SOURCE_DIGEST="${SIMS_FIXTURE_SOURCE_DIGEST:-$source_v1}" \
    SIMS_TEST_ALLOW_SUITE_SOURCE_DIGEST_OVERRIDE=1 \
    SIMS_FIXTURE_EXECUTION_LOG="$execution_log" \
    SIMS_FIXTURE_PROOF_PATH="$proof" \
    SIMS_FIXTURE_PROOF_DIGEST="$proof_digest" \
    SIMS_FIXTURE_UNRELATED_PROOF_PATH="$unrelated_proof" \
    SIMS_FIXTURE_UNRELATED_PROOF_DIGEST="$unrelated_proof_digest" \
    SIMS_FIXTURE_DISCOVERY_LOG="$discovery_log" \
    SIMS_FIXTURE_ARTIFACT_DIR="$artifact_dir" \
    ./scripts/run_test_gates.sh sims "$mode" "$@" --format json
}

assert_report_ids() {
  local report_path="$1"
  local expected_ids_csv="$2"
  local expect_release_green="$3"

  python3 - "$report_path" "$expected_ids_csv" "$expect_release_green" <<'PY'
import json
import sys

path, ids_csv, expect_green = sys.argv[1:]
expected = ids_csv.split(",") if ids_csv else []
with open(path, encoding="utf-8") as stream:
    report = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(report.get("selectedIds") == expected,
        f"selected IDs {report.get('selectedIds')} != {expected}")
require(report.get("attemptedIds") == sorted(expected),
        f"attempted IDs {report.get('attemptedIds')} != {sorted(expected)}")
require(report.get("terminalIds") == sorted(expected),
        f"terminal IDs {report.get('terminalIds')} != {sorted(expected)}")
green = report.get("assessment", {}).get("releaseEligible")
require(green is (expect_green == "yes"),
        f"releaseEligible={green}, expected {expect_green}")
if expect_green == "yes":
    require(report.get("cleanFullRun") is True, "final release-green report is not a clean full run")
else:
    require(report.get("cleanFullRun") is False, "partial retry/resume was mislabeled clean/full")
PY
}

write_manifest "$manifest" v1

# Checkpoint creation is deliberately restricted to an unfiltered major. A
# family-filtered fix run would freeze an ambiguous selection and must reject
# before discovery/build/dispatch.
: >"$execution_log"
set +e
run_sims "$tmp_dir/filtered-fix.report.json" --fix-as-you-go --family fixture \
  >"$tmp_dir/filtered-fix.stdout" 2>"$tmp_dir/filtered-fix.stderr"
filtered_fix_status=$?
set -e
[ "$filtered_fix_status" -ne 0 ] ||
  fail 'family-filtered --fix-as-you-go was accepted'
[ ! -s "$execution_log" ] ||
  fail 'family-filtered --fix-as-you-go dispatched before rejection'
[ ! -f "$checkpoint" ] ||
  fail 'family-filtered --fix-as-you-go persisted a checkpoint'
grep -qi 'unfiltered major' "$tmp_dir/filtered-fix.stderr" ||
  fail 'filtered fix rejection did not explain the unfiltered-major contract'

# Fail in the middle. Fail-fast must not attempt the dependent final row, and a
# durable checkpoint must retain stable IDs and frozen-input classifications.
initial_report="$tmp_dir/initial.report.json"
set +e
SIMS_FIXTURE_FAIL_ID=fixture.middle \
  run_sims "$initial_report" --fix-as-you-go \
    >"$tmp_dir/initial.stdout" 2>"$tmp_dir/initial.stderr"
initial_status=$?
set -e
[ "$initial_status" -ne 0 ] || fail 'middle failure incorrectly exited 0'
if [ ! -f "$checkpoint" ] || [ ! -f "$initial_report" ]; then
  sed -n '1,120p' "$tmp_dir/initial.stderr" >&2
  fail 'sims checkpoint/executor seam missing: a mid-plan failure must honor SIMS_CHECKPOINT_PATH and SIMS_REPORT_PATH with durable stable-ID state'
fi
[ "$(cat "$execution_log")" = "$(printf '%s\n' fixture.first fixture.unrelated fixture.middle)" ] ||
  fail 'initial fail-fast run did not stop after the middle failure'

python3 - "$checkpoint" "$initial_report" "$unrelated_proof_digest" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    report = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(checkpoint.get("failedId") == "fixture.middle", "checkpoint lost the failed stable ID")
require(checkpoint.get("passedIds") == ["fixture.first", "fixture.unrelated"],
        "checkpoint lost prior passes from the independent branch")
prior = checkpoint.get("passedVerdicts", [])
require(len(prior) == 2, "checkpoint lost exact prior verdicts")
evidence = prior[0].get("artifactEvidence", {})
require(evidence.get("validatorIds") == ["fixture.first.validator"],
        "checkpoint lost prior artifact evidence")
unrelated_evidence = prior[1].get("artifactEvidence", {})
require(unrelated_evidence.get("sha256") == sys.argv[3],
        "checkpoint lost the unrelated branch artifact digest")
require(unrelated_evidence.get("validatorIds") == ["fixture.unrelated.validator"],
        "checkpoint lost the unrelated branch validator binding")
require(checkpoint.get("nextId") == "fixture.device", "checkpoint lost the next stable ID")
require(checkpoint.get("failureClass") == "product", "failure classification was not persisted")
require(checkpoint.get("finalCleanRunRequired") is True, "checkpoint does not require a final clean run")
for key in ("manifestDigest", "sourceDigest", "deviceDigest"):
    require(isinstance(checkpoint.get(key), str) and checkpoint[key], f"checkpoint omitted {key}")
require(isinstance(checkpoint.get("redactedCommand"), list), "checkpoint omitted redacted command")
require(report.get("assessment", {}).get("releaseEligible") is False,
        "failed partial report produced release green")
PY

initial_build_digest="$(python3 - "$checkpoint" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)
print(checkpoint.get("buildArtifactDigests", {}).get("android.fixture.device", ""))
PY
)"
[ -n "$initial_build_digest" ] ||
  fail 'mixed-plan checkpoint omitted the unrelated device build digest'

# Resume cannot skip over the still-failing stable ID. It must reject before
# dispatch and must leave the exact checkpoint bytes untouched.
pre_repair_checkpoint="$tmp_dir/pre-repair.checkpoint.json"
cp "$checkpoint" "$pre_repair_checkpoint"
: >"$execution_log"
set +e
run_sims "$tmp_dir/pre-repair-resume.report.json" --resume \
  >"$tmp_dir/pre-repair-resume.stdout" \
  2>"$tmp_dir/pre-repair-resume.stderr"
pre_repair_resume_status=$?
set -e
[ "$pre_repair_resume_status" -ne 0 ] ||
  fail 'resume skipped over a failed ID without exact repair PASS evidence'
[ ! -s "$execution_log" ] ||
  fail 'pre-repair resume dispatched a later row'
cmp -s "$checkpoint" "$pre_repair_checkpoint" ||
  fail 'pre-repair resume rewrote the checkpoint'
grep -qi 'failed.*PASS\|repair.*--only\|resume.*repair' \
  "$tmp_dir/pre-repair-resume.stderr" ||
  fail 'pre-repair resume did not explain the required focused repair'

# A checkpoint created by major cannot be repaired under another mode even
# when the stable ID also participates there.
cross_mode_checkpoint="$tmp_dir/cross-mode.checkpoint.json"
cp "$checkpoint" "$cross_mode_checkpoint"
: >"$execution_log"
set +e
SIMS_FIXTURE_CHECKPOINT_PATH="$cross_mode_checkpoint" \
  run_sims "$tmp_dir/cross-mode.report.json" full --only fixture.middle \
    >"$tmp_dir/cross-mode.stdout" 2>"$tmp_dir/cross-mode.stderr"
cross_mode_status=$?
set -e
[ "$cross_mode_status" -ne 0 ] ||
  fail 'cross-mode checkpoint repair was accepted'
[ ! -s "$execution_log" ] ||
  fail 'cross-mode checkpoint repair dispatched before rejection'
cmp -s "$cross_mode_checkpoint" "$checkpoint" ||
  fail 'cross-mode checkpoint repair rewrote checkpoint evidence'
grep -qi 'unfiltered major\|checkpoint.*mode' "$tmp_dir/cross-mode.stderr" ||
  fail 'cross-mode rejection did not explain the checkpoint mode contract'

# Focused repair is the one permitted selection change. Combining it with an
# additional family/lane filter would make the checkpoint selection ambiguous.
cross_filter_checkpoint="$tmp_dir/cross-filter.checkpoint.json"
cp "$checkpoint" "$cross_filter_checkpoint"
: >"$execution_log"
set +e
SIMS_FIXTURE_CHECKPOINT_PATH="$cross_filter_checkpoint" \
  run_sims "$tmp_dir/cross-filter.report.json" --only fixture.middle \
    --family fixture \
    >"$tmp_dir/cross-filter.stdout" 2>"$tmp_dir/cross-filter.stderr"
cross_filter_status=$?
set -e
[ "$cross_filter_status" -ne 0 ] ||
  fail 'family-filtered checkpoint repair was accepted'
[ ! -s "$execution_log" ] ||
  fail 'family-filtered checkpoint repair dispatched before rejection'
cmp -s "$cross_filter_checkpoint" "$checkpoint" ||
  fail 'family-filtered checkpoint repair rewrote checkpoint evidence'
grep -qi 'unfiltered major\|checkpoint.*filter' "$tmp_dir/cross-filter.stderr" ||
  fail 'cross-filter rejection did not explain the checkpoint selection contract'

# Numeric position is not a stable resume identity and must be rejected before
# dispatch. This preserves the old --start-at hazard as an explicit red case.
: >"$execution_log"
set +e
run_sims "$tmp_dir/numeric.report.json" --only 2 \
  >"$tmp_dir/numeric.stdout" 2>"$tmp_dir/numeric.stderr"
numeric_status=$?
set -e
[ "$numeric_status" -ne 0 ] || fail 'numeric --only was accepted as a stable capability ID'
[ ! -s "$execution_log" ] || fail 'numeric --only dispatched a row before rejection'

# A changed manifest invalidates resume before any row is attempted. Use a copy
# so the original valid checkpoint remains available for the real repair flow.
mismatch_checkpoint="$tmp_dir/mismatch.checkpoint.json"
cp "$checkpoint" "$mismatch_checkpoint"
write_manifest "$manifest" v2
: >"$execution_log"
set +e
SIMS_FIXTURE_CHECKPOINT_PATH="$mismatch_checkpoint" \
  SIMS_FIXTURE_SOURCE_DIGEST="$source_v1" \
  run_sims "$tmp_dir/mismatch.report.json" --resume \
    >"$tmp_dir/mismatch.stdout" 2>"$tmp_dir/mismatch.stderr"
mismatch_status=$?
set -e
[ "$mismatch_status" -ne 0 ] || fail 'resume accepted a changed manifest digest'
[ ! -s "$execution_log" ] || fail 'digest-invalid resume dispatched a row'
grep -qi 'manifest.*digest\|manifest.*changed' "$tmp_dir/mismatch.stderr" ||
  fail 'digest-invalid resume did not explain the manifest mismatch'

write_manifest "$manifest" v1

# Simulate a checkpoint written by the legacy whole-inventory digest. A focused
# repair may migrate it only when a fresh full-plan binding proves that every
# selected resource and target state is still exact.
legacy_device_digest=dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd
python3 - "$checkpoint" "$legacy_device_digest" <<'PY'
import json
import sys

path, digest = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    checkpoint = json.load(stream)
checkpoint["deviceDigest"] = digest
with open(path, "w", encoding="utf-8") as stream:
    json.dump(checkpoint, stream, separators=(",", ":"))
    stream.write("\n")
PY

# A selected-target rebind cannot use the migration fallback. It must reject
# before dispatch and leave the copied checkpoint byte-for-byte unchanged.
device_mismatch_checkpoint="$tmp_dir/device-mismatch.checkpoint.json"
cp "$checkpoint" "$device_mismatch_checkpoint"
: >"$execution_log"
set +e
SIMS_FIXTURE_ANDROID_ID=fixture-android-replacement \
  SIMS_FIXTURE_CHECKPOINT_PATH="$device_mismatch_checkpoint" \
  run_sims "$tmp_dir/device-mismatch.report.json" --only fixture.middle \
    >"$tmp_dir/device-mismatch.stdout" 2>"$tmp_dir/device-mismatch.stderr"
device_mismatch_status=$?
set -e
[ "$device_mismatch_status" -ne 0 ] ||
  fail 'focused repair accepted a selected-target rebind'
[ ! -s "$execution_log" ] ||
  fail 'selected-target mismatch dispatched before checkpoint rejection'
cmp -s "$device_mismatch_checkpoint" "$checkpoint" ||
  fail 'selected-target mismatch rewrote checkpoint evidence'
grep -qi 'device matrix changed' "$tmp_dir/device-mismatch.stderr" ||
  fail 'selected-target mismatch did not explain device continuity failure'

# Retry only the stable failed ID. Its green process result is useful repair
# evidence, but the report must remain explicitly non-release-green. A real
# repair changes the source digest; focused retry accepts that deliberate
# change and rebases the checkpoint for the following resume. The duplicate
# discovery row changes only diagnostic row-count detail after target dedupe.
: >"$execution_log"
retry_report="$tmp_dir/retry.report.json"
export SIMS_FIXTURE_SOURCE_DIGEST="$source_v2"
export SIMS_FIXTURE_DUPLICATE_FLUTTER_ROW=1
if ! run_sims "$retry_report" --only fixture.middle \
  >"$tmp_dir/retry.stdout" 2>"$tmp_dir/retry.stderr"; then
  sed -n '1,160p' "$tmp_dir/retry.stderr" >&2
  sed -n '1,80p' "$tmp_dir/retry.stdout" >&2
  if [ -f "$retry_report" ]; then
    python3 -m json.tool "$retry_report" >&2
  fi
  fail 'passing stable-ID retry returned nonzero'
fi
unset SIMS_FIXTURE_DUPLICATE_FLUTTER_ROW
[ "$(cat "$execution_log")" = 'fixture.middle' ] ||
  fail '--only retry reran prior passes or later rows'
assert_report_ids "$retry_report" fixture.first,fixture.middle no

python3 - "$checkpoint" "$source_v2" "$unrelated_proof_digest" \
  "$initial_build_digest" "$retry_report" "$legacy_device_digest" \
  "$pre_repair_checkpoint" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)
with open(sys.argv[5], encoding="utf-8") as stream:
    report = json.load(stream)
with open(sys.argv[7], encoding="utf-8") as stream:
    original = json.load(stream)

if checkpoint.get("sourceDigest") != sys.argv[2]:
    raise SystemExit("FAIL: passing repair retry retained the stale source digest")
if checkpoint.get("passedIds") != ["fixture.first", "fixture.unrelated", "fixture.middle"]:
    raise SystemExit("FAIL: focused repair dropped or reordered an unrelated prior PASS")
unrelated = next(
    (item for item in checkpoint.get("passedVerdicts", [])
     if item.get("capabilityId") == "fixture.unrelated"),
    None,
)
if unrelated is None:
    raise SystemExit("FAIL: focused repair dropped unrelated prior verdict evidence")
evidence = unrelated.get("artifactEvidence", {})
if evidence.get("sha256") != sys.argv[3] or evidence.get("validatorIds") != ["fixture.unrelated.validator"]:
    raise SystemExit("FAIL: focused repair changed unrelated prior artifact evidence")
if checkpoint.get("buildArtifactDigests", {}).get("android.fixture.device") != sys.argv[4]:
    raise SystemExit("FAIL: focused host repair dropped the unrelated device build digest")
report_digest = report.get("devices", {}).get("inventoryDigest")
if not report_digest or checkpoint.get("deviceDigest") != report_digest:
    raise SystemExit("FAIL: focused repair did not rebase the legacy device digest")
if checkpoint.get("deviceDigest") == sys.argv[6]:
    raise SystemExit("FAIL: focused repair retained the legacy device digest")
if checkpoint.get("targetAssignments") != original.get("targetAssignments"):
    raise SystemExit("FAIL: focused repair changed selected target assignments")
if checkpoint.get("targetStateDigests") != original.get("targetStateDigests"):
    raise SystemExit("FAIL: focused repair changed selected target state evidence")
PY

# A later row can fail while resuming without repeating --fix-as-you-go. That
# failure must replace the copied checkpoint so the next repair targets the
# actual failing stable ID rather than the already-repaired middle row.
later_failure_checkpoint="$tmp_dir/later-failure.checkpoint.json"
later_failure_report="$tmp_dir/later-failure.report.json"
cp "$checkpoint" "$later_failure_checkpoint"
: >"$execution_log"
set +e
SIMS_FIXTURE_FAIL_ID=fixture.last \
  SIMS_FIXTURE_CHECKPOINT_PATH="$later_failure_checkpoint" \
  run_sims "$later_failure_report" --resume \
    >"$tmp_dir/later-failure.stdout" \
    2>"$tmp_dir/later-failure.stderr"
later_failure_status=$?
set -e
[ "$later_failure_status" -ne 0 ] ||
  fail 'a later resume failure incorrectly exited 0'
[ "$(cat "$execution_log")" = "$(printf '%s\n' fixture.device fixture.last)" ] ||
  fail 'later resume failure reran an already-proven row'
[ -f "$later_failure_report" ] ||
  fail 'later resume failure omitted its typed report'

python3 - "$later_failure_checkpoint" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(checkpoint.get("failedId") == "fixture.last",
        "resume failure did not replace the checkpoint stable ID")
require(checkpoint.get("passedIds") == ["fixture.first", "fixture.unrelated", "fixture.middle", "fixture.device"],
        "resume failure lost the previously proven rows")
require("nextId" not in checkpoint,
        "terminal resume failure retained a stale next ID")
require(checkpoint.get("failureClass") == "product",
        "resume failure classification was not refreshed")
require(checkpoint.get("finalCleanRunRequired") is True,
        "resume failure dropped the final-clean requirement")
PY

# Resume begins strictly after the failed stable ID. Dependencies already proven
# by the frozen checkpoint are not rerun, and this remains partial evidence.
: >"$execution_log"
resume_report="$tmp_dir/resume.report.json"
run_sims "$resume_report" --resume \
  >"$tmp_dir/resume.stdout" 2>"$tmp_dir/resume.stderr" ||
  fail 'valid stable-ID resume returned nonzero'
[ "$(cat "$execution_log")" = "$(printf '%s\n' fixture.device fixture.last)" ] ||
  fail '--resume did not continue strictly after the repaired stable ID'
assert_report_ids "$resume_report" fixture.first,fixture.unrelated,fixture.middle,fixture.device,fixture.last no
[ -f "$checkpoint" ] ||
  fail 'resume discarded the final-clean requirement before a clean major run'

# Re-running an already-passed failed ID can fail again. That new causal result
# invalidates the ID and every transitive dependent; none may remain in
# passedIds/passedVerdicts.
refail_checkpoint="$tmp_dir/refail.checkpoint.json"
cp "$checkpoint" "$refail_checkpoint"
: >"$execution_log"
set +e
SIMS_FIXTURE_FAIL_ID=fixture.middle \
  SIMS_FIXTURE_CHECKPOINT_PATH="$refail_checkpoint" \
  run_sims "$tmp_dir/refail.report.json" --only fixture.middle \
    >"$tmp_dir/refail.stdout" 2>"$tmp_dir/refail.stderr"
refail_status=$?
set -e
[ "$refail_status" -ne 0 ] ||
  fail 'already-passed failed ID re-failure incorrectly exited zero'
[ "$(cat "$execution_log")" = 'fixture.middle' ] ||
  fail 'already-passed ID re-failure dispatched another row'
python3 - "$refail_checkpoint" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)
if checkpoint.get("failedId") != "fixture.middle":
    raise SystemExit("FAIL: re-failure did not target the executed failed ID")
if checkpoint.get("passedIds") != ["fixture.first", "fixture.unrelated"]:
    raise SystemExit("FAIL: re-failure retained the failed ID or invalidated dependents")
verdict_ids = [item.get("capabilityId") for item in checkpoint.get("passedVerdicts", [])]
if verdict_ids != ["fixture.first", "fixture.unrelated"]:
    raise SystemExit("FAIL: re-failure retained stale passed verdict evidence")
if checkpoint.get("nextId") != "fixture.device":
    raise SystemExit("FAIL: re-failure did not resume at the first invalidated dependent")
PY

# Only a separate unfiltered run on the current frozen inputs may close green.
: >"$execution_log"
final_report="$tmp_dir/final.report.json"
if ! run_sims "$final_report" \
  >"$tmp_dir/final.stdout" 2>"$tmp_dir/final.stderr"; then
  sed -n '1,120p' "$tmp_dir/final.stderr" >&2
  fail 'final clean major fixture returned nonzero'
fi
[ "$(cat "$execution_log")" = "$(printf '%s\n' fixture.first fixture.unrelated fixture.middle fixture.device fixture.last)" ] ||
  fail 'final clean run did not execute the complete current plan'
assert_report_ids "$final_report" fixture.first,fixture.unrelated,fixture.middle,fixture.device,fixture.last yes
[ ! -f "$checkpoint" ] ||
  fail 'successful clean full major left a stale failure checkpoint'

if rg -n '(^| )(install|uninstall|launch|boot|emu start|shell|push|pull)( |$)' \
  "$discovery_log" >/dev/null; then
  sed -n '1,160p' "$discovery_log" >&2
  fail 'checkpoint device-digest fixture issued a mutating device command'
fi

printf 'PASS: sims checkpoint/only/resume/final-clean process contract\n'
