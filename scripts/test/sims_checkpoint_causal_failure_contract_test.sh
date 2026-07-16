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

runner="$tmp_dir/runner.sh"
manifest="$tmp_dir/manifest.json"
checkpoint="$tmp_dir/checkpoint.json"
report="$tmp_dir/report.json"
execution_log="$tmp_dir/execution.log"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'id="${1:?missing capability ID}"' \
  'printf "%s\n" "$id" >>"${SIMS_FIXTURE_EXECUTION_LOG:?}"' \
  'case "$id" in' \
  '  fixture.slow)' \
  '    sleep 0.30' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false}'\''' \
  '    ;;' \
  '  fixture.synthetic-earlier)' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"PASS","assertionsAttempted":1,"artifactPresent":true,"printOnly":false}'\''' \
  '    ;;' \
  '  fixture.causal-later)' \
  '    sleep 0.05' \
  '    printf '\''SIMS_RESULT_JSON=%s\n'\'' '\''{"status":"FAIL","assertionsAttempted":1,"artifactPresent":false,"printOnly":false,"blocker":"product"}'\''' \
  '    exit 17' \
  '    ;;' \
  '  *) exit 64 ;;' \
  'esac' \
  >"$runner"
chmod +x "$runner"

python3 - "$manifest" "$runner" <<'PY'
import json
import sys

manifest_path, runner = sys.argv[1:]

def row(capability_id, resources):
    return {
        "id": capability_id,
        "owner": "fixture",
        "proofBoundary": f"boundary.{capability_id}",
        "assertions": [f"assertion.{capability_id}"],
        "lane": "host-dart",
        "modes": ["major"],
        "families": ["fixture"],
        "required": True,
        "command": ["bash", runner, capability_id],
        "buildProfile": "host.fixture",
        "dependencies": [],
        "resources": resources,
        "targetCapabilities": [],
        "artifactRequired": False,
        "active": True,
        "declaredBuildException": False,
    }

payload = {
    "schemaVersion": 1,
    "buildProfiles": [{
        "id": "host.fixture",
        "platform": "host",
        "artifactKind": "none",
        "buildRequired": False,
        "compileDefines": {},
        "declaredException": False,
    }],
    "capabilities": [
        row("fixture.slow", [{"name": "artifact:shared", "access": "write"}]),
        row("fixture.synthetic-earlier", [{"name": "artifact:shared", "access": "write"}]),
        row("fixture.causal-later", [{"name": "host.cpu", "access": "read"}]),
    ],
    "ownership": [],
}
with open(manifest_path, "w", encoding="utf-8") as stream:
    json.dump(payload, stream)
PY

set +e
SIMS_MANIFEST="$manifest" \
SIMS_REPORT_PATH="$report" \
SIMS_CHECKPOINT_PATH="$checkpoint" \
SIMS_CACHE_DIR="$tmp_dir/cache" \
SIMS_SOURCE_DIGEST=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
SIMS_SUITE_SOURCE_DIGEST=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
SIMS_TEST_ALLOW_SUITE_SOURCE_DIGEST_OVERRIDE=1 \
SIMS_FIXTURE_EXECUTION_LOG="$execution_log" \
SIMS_MAX_PARALLEL=2 \
SIMS_HOST_CONCURRENCY=2 \
./scripts/run_test_gates.sh sims major --simultaneous --fix-as-you-go --format json \
  >"$tmp_dir/stdout" 2>"$tmp_dir/stderr"
status=$?
set -e

[ "$status" -ne 0 ] || fail 'causal fixture unexpectedly exited zero'
[ -f "$checkpoint" ] || fail 'causal fixture did not persist a checkpoint'
[ "$(cat "$execution_log")" = "$(printf '%s\n' fixture.slow fixture.causal-later)" ] ||
  fail 'fixture did not execute the intended simultaneous branch'

python3 - "$checkpoint" "$report" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    checkpoint = json.load(stream)
with open(sys.argv[2], encoding="utf-8") as stream:
    report = json.load(stream)

def require(condition, message):
    if not condition:
        raise SystemExit(f"FAIL: {message}")

require(checkpoint.get("failedId") == "fixture.causal-later",
        "checkpoint targeted an earlier synthetic blocker instead of the executed causal failure")
require(checkpoint.get("passedIds") == ["fixture.slow"],
        "checkpoint did not retain the completed independent PASS")
verdicts = {item["capabilityId"]: item for item in report.get("verdicts", [])}
require(verdicts.get("fixture.synthetic-earlier", {}).get("status") == "BLOCKED",
        "fixture did not produce the earlier synthetic blocker")
require(verdicts.get("fixture.causal-later", {}).get("status") == "FAIL",
        "fixture did not retain the actual executed failure")
PY

printf 'PASS: sims checkpoint causal-failure selection contract\n'
