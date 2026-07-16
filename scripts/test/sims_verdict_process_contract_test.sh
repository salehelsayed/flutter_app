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

fixture_runner="$tmp_dir/result_fixture.sh"
fixture_proof="$tmp_dir/result-proof.json"
printf '%s\n' '{"status":"passed","fixture":true}' >"$fixture_proof"
fixture_proof_sha="$(shasum -a 256 "$fixture_proof" | awk '{print $1}')"
inherited_checkpoint="$tmp_dir/inherited-campaign.checkpoint.json"
printf '%s\n' \
  '{' \
  '  "failedId": "outer.failure",' \
  '  "manifestDigest": "manifest",' \
  '  "sourceDigest": "source",' \
  '  "deviceDigest": "devices",' \
  '  "buildArtifactDigests": {},' \
  '  "redactedCommand": ["outer-runner"],' \
  '  "targetAssignments": {},' \
  '  "targetStateDigests": {},' \
  '  "logPaths": [],' \
  '  "failureClass": "test",' \
  '  "passedIds": [],' \
  '  "passedVerdicts": [],' \
  '  "createdAt": "2026-07-15T00:00:00.000Z",' \
  '  "finalCleanRunRequired": true' \
  '}' \
  >"$inherited_checkpoint"
inherited_checkpoint_sha="$({ shasum -a 256 "$inherited_checkpoint"; } | awk '{print $1}')"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'case "${1:?missing fixture case}" in' \
  '  pass)' \
  '    printf '\''SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":2,"artifactPresent":true,"printOnly":false,"artifactEvidence":{"path":"%s","sha256":"%s","validatorIds":["fixture.sentinel"]}}\n'\'' "${SIMS_FIXTURE_PROOF_PATH:?}" "${SIMS_FIXTURE_PROOF_SHA256:?}"' \
  '    ;;' \
  '  mandatory-skip)' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"SKIP","assertionsAttempted":0,"artifactPresent":false,"printOnly":false}'\''' \
  '    ;;' \
  '  zero-attempt)' \
  '    printf '\''SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":0,"artifactPresent":true,"printOnly":false,"artifactEvidence":{"path":"%s","sha256":"%s","validatorIds":["fixture.sentinel"]}}\n'\'' "${SIMS_FIXTURE_PROOF_PATH:?}" "${SIMS_FIXTURE_PROOF_SHA256:?}"' \
  '    ;;' \
  '  print-only)' \
  '    printf '\''Deferred campaign catalog: nothing was executed.\n'\''' \
  '    printf '\''SIMS_RESULT_JSON={"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":true,"artifactEvidence":{"path":"%s","sha256":"%s","validatorIds":["fixture.sentinel"]}}\n'\'' "${SIMS_FIXTURE_PROOF_PATH:?}" "${SIMS_FIXTURE_PROOF_SHA256:?}"' \
  '    ;;' \
  '  missing-artifact)' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":false,"printOnly":false}'\''' \
  '    ;;' \
  '  exit-78)' \
  '    printf '\''blocked: fixture driver unavailable\n'\'' >&2' \
  '    exit 78' \
  '    ;;' \
  '  device-loss)' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"FAIL","assertionsAttempted":1,"artifactPresent":false,"printOnly":false,"blocker":"deviceLost"}'\''' \
  '    exit 1' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  >"$fixture_runner"
chmod +x "$fixture_runner"

write_manifest() {
  local fixture_case="$1"
  local manifest_path="$2"

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
    '    }' \
    '  ],' \
    '  "capabilities": [' \
    '    {' \
    '      "id": "fixture.verdict",' \
    '      "owner": "fixture",' \
    '      "proofBoundary": "fixture.verdict.boundary",' \
    '      "assertions": ["fixture.assertion"],' \
    '      "lane": "reliability",' \
    '      "modes": ["major"],' \
    '      "families": ["fixture"],' \
    '      "required": true,' \
    "      \"command\": [\"bash\", \"$fixture_runner\", \"$fixture_case\"]," \
    '      "buildProfile": "host.fixture",' \
    '      "dependencies": [],' \
    '      "resources": [{"name": "host.cpu", "access": "read"}],' \
    '      "targetCapabilities": [],' \
    '      "artifactRequired": true,' \
    '      "artifactValidator": "fixture.sentinel",' \
    '      "active": true,' \
    '      "declaredBuildException": false' \
    '    }' \
    '  ],' \
    '  "ownership": []' \
    '}' \
    >"$manifest_path"
}

assert_report() {
  local report_path="$1"
  local expected_status="$2"
  local expected_exit_kind="$3"

  python3 - "$report_path" "$expected_status" "$expected_exit_kind" <<'PY'
import json
import sys

path, expected_status, expected_exit_kind = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    report = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(report.get("plan", {}).get("mode") == "major", "typed report lost major mode")
require(report.get("selectedIds") == ["fixture.verdict"], "typed report selectedIds drifted")
require(report.get("attemptedIds") == ["fixture.verdict"], "typed report omitted attempted fixture row")
require(report.get("terminalIds") == ["fixture.verdict"], "typed report omitted terminal fixture row")
verdicts = report.get("verdicts")
require(isinstance(verdicts, list) and len(verdicts) == 1, "typed report needs exactly one verdict")
verdict = verdicts[0]
require(verdict.get("capabilityId") == "fixture.verdict", "verdict has the wrong capability ID")
require(verdict.get("status") == expected_status,
        f"expected typed status {expected_status}, got {verdict.get('status')}")
require(report.get("validationErrors") == [], "typed report is internally inconsistent")

if expected_exit_kind == "pass":
    require(report.get("assessment", {}).get("releaseEligible") is True,
            "complete mandatory PASS did not produce release-green assessment")
    require(report.get("cleanFullRun") is True, "unfiltered major fixture is not marked clean/full")
    evidence = verdict.get("artifactEvidence")
    require(isinstance(evidence, dict), "PASS omitted durable artifact evidence")
    require(evidence.get("validatorIds") == ["fixture.sentinel"],
            "PASS validator binding drifted")
else:
    require(report.get("assessment", {}).get("releaseEligible") is False,
            "failing mandatory evidence incorrectly produced release green")

if expected_exit_kind in ("zero-attempt", "print-only"):
    require(verdict.get("blocker") == "harness",
            "contradictory PASS metadata was not classified as a harness failure")
    require("Invalid structured result" in verdict.get("detail", ""),
            "contradictory PASS did not retain its parser diagnosis")
if expected_exit_kind == "missing-artifact":
    require(verdict.get("artifactPresent") is False, "missing artifact was invented")
if expected_exit_kind == "exit-78":
    require(verdict.get("exitCode") == 78, "exit 78 was not recorded")
    require(verdict.get("blocker") == "missingDriver", "exit 78 was not typed as a missing driver")
if expected_exit_kind == "device-loss":
    require(verdict.get("blocker") == "deviceLost", "device loss blocker was not preserved")
PY
}

run_case() {
  local fixture_case="$1"
  local expected_status="$2"
  local expect_process_success="$3"
  local report_path="$tmp_dir/$fixture_case.report.json"
  local manifest_path="$tmp_dir/$fixture_case.manifest.json"
  local checkpoint_path="$tmp_dir/$fixture_case.checkpoint.json"
  local process_status

  write_manifest "$fixture_case" "$manifest_path"
  rm -f "$report_path" "$checkpoint_path"
  set +e
  SIMS_MANIFEST="$manifest_path" \
    SIMS_REPORT_PATH="$report_path" \
    SIMS_CHECKPOINT_PATH="$checkpoint_path" \
    SIMS_FIXTURE_PROOF_PATH="$fixture_proof" \
    SIMS_FIXTURE_PROOF_SHA256="$fixture_proof_sha" \
    ./scripts/run_test_gates.sh sims major --format json \
      >"$tmp_dir/$fixture_case.stdout" \
      2>"$tmp_dir/$fixture_case.stderr"
  process_status=$?
  set -e

  if [ ! -f "$report_path" ]; then
    fail "sims executor/report seam missing: SIMS_REPORT_PATH was not written for '$fixture_case' (required protocol: execute the manifest command, parse SIMS_RESULT_JSON, and persist a typed report even on failure)"
  fi
  if [ "$expect_process_success" = "yes" ] && [ "$process_status" -ne 0 ]; then
    fail "passing typed fixture exited with $process_status instead of 0"
  fi
  if [ "$expect_process_success" = "no" ] && [ "$process_status" -eq 0 ]; then
    fail "mandatory '$fixture_case' mutation incorrectly exited 0"
  fi
  assert_report "$report_path" "$expected_status" "$fixture_case"
}

SIMS_CHECKPOINT_PATH="$inherited_checkpoint" run_case pass PASS yes
[ -f "$inherited_checkpoint" ] ||
  fail 'nested verdict fixture deleted its inherited campaign checkpoint'
[ "$(shasum -a 256 "$inherited_checkpoint" | awk '{print $1}')" = \
  "$inherited_checkpoint_sha" ] ||
  fail 'nested verdict fixture rewrote its inherited campaign checkpoint'
run_case mandatory-skip SKIP no
run_case zero-attempt FAIL no
run_case print-only FAIL no
run_case missing-artifact FAIL no
run_case exit-78 BLOCKED no
run_case device-loss FAIL no

printf 'PASS: sims typed verdict process contract\n'
