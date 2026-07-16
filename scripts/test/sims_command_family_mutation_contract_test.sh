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

runner="$tmp_dir/command_failure.sh"
manifest="$tmp_dir/manifest.json"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'family="${1:?missing command family}"' \
  'code="${2:?missing exit code}"' \
  'printf "%s mutation failed\n" "$family" >&2' \
  'exit "$code"' \
  >"$runner"
chmod +x "$runner"

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
  '      "id": "fixture.analyzer",' \
  '      "owner": "fixture",' \
  '      "proofBoundary": "fixture.analyzer.boundary",' \
  '      "assertions": ["fixture.analyzer.exit"],' \
  '      "lane": "analyzer",' \
  '      "modes": ["major"],' \
  '      "families": ["fixture"],' \
  '      "required": true,' \
  "      \"command\": [\"bash\", \"$runner\", \"analyzer\", \"41\"]," \
  '      "buildProfile": "host.fixture",' \
  '      "dependencies": [],' \
  '      "resources": [{"name": "host.cpu", "access": "read"}],' \
  '      "targetCapabilities": [],' \
  '      "artifactRequired": false,' \
  '      "active": true,' \
  '      "declaredBuildException": false' \
  '    },' \
  '    {' \
  '      "id": "fixture.dart",' \
  '      "owner": "fixture",' \
  '      "proofBoundary": "fixture.dart.boundary",' \
  '      "assertions": ["fixture.dart.exit"],' \
  '      "lane": "host-dart",' \
  '      "modes": ["major"],' \
  '      "families": ["fixture"],' \
  '      "required": true,' \
  "      \"command\": [\"bash\", \"$runner\", \"Dart\", \"42\"]," \
  '      "buildProfile": "host.fixture",' \
  '      "dependencies": [],' \
  '      "resources": [{"name": "host.cpu", "access": "read"}],' \
  '      "targetCapabilities": [],' \
  '      "artifactRequired": false,' \
  '      "active": true,' \
  '      "declaredBuildException": false' \
  '    },' \
  '    {' \
  '      "id": "fixture.go",' \
  '      "owner": "fixture",' \
  '      "proofBoundary": "fixture.go.boundary",' \
  '      "assertions": ["fixture.go.exit"],' \
  '      "lane": "go-node",' \
  '      "modes": ["major"],' \
  '      "families": ["fixture"],' \
  '      "required": true,' \
  "      \"command\": [\"bash\", \"$runner\", \"Go\", \"43\"]," \
  '      "buildProfile": "host.fixture",' \
  '      "dependencies": [],' \
  '      "resources": [{"name": "host.cpu", "access": "read"}],' \
  '      "targetCapabilities": [],' \
  '      "artifactRequired": false,' \
  '      "active": true,' \
  '      "declaredBuildException": false' \
  '    }' \
  '  ],' \
  '  "ownership": []' \
  '}' \
  >"$manifest"

run_mutation() {
  local id="$1"
  local expected_exit="$2"
  local report="$tmp_dir/$id.report.json"
  local status

  set +e
  SIMS_MANIFEST="$manifest" \
    SIMS_REPORT_PATH="$report" \
    SIMS_CACHE_DIR="$tmp_dir/cache" \
    SIMS_SOURCE_DIGEST=fixture-source-v1 \
    SIMS_TEST_ALLOW_SOURCE_DIGEST_OVERRIDE=1 \
    ./scripts/run_test_gates.sh sims major --only "fixture.$id" --format json \
      >"$tmp_dir/$id.stdout" 2>"$tmp_dir/$id.stderr"
  status=$?
  set -e

  [ "$status" -ne 0 ] || fail "$id command failure incorrectly exited 0"
  [ -f "$report" ] || fail "$id command failure omitted its typed report"

  python3 - "$report" "fixture.$id" "$expected_exit" <<'PY'
import json
import sys

path, expected_id, expected_exit = sys.argv[1:]
with open(path, encoding="utf-8") as stream:
    report = json.load(stream)

verdicts = report.get("verdicts", [])
if len(verdicts) != 1:
    raise SystemExit(f"FAIL: {expected_id} needs exactly one verdict")
verdict = verdicts[0]
if verdict.get("capabilityId") != expected_id:
    raise SystemExit(f"FAIL: {expected_id} verdict identity drifted")
if verdict.get("status") == "PASS":
    raise SystemExit(f"FAIL: {expected_id} command failure was typed PASS")
if verdict.get("exitCode") != int(expected_exit):
    raise SystemExit(f"FAIL: {expected_id} lost exit {expected_exit}")
if report.get("assessment", {}).get("releaseEligible") is not False:
    raise SystemExit(f"FAIL: {expected_id} command failure produced release green")
PY
}

run_mutation analyzer 41
run_mutation dart 42
run_mutation go 43

printf 'PASS: analyzer, Dart, and Go command-family mutations remain release-red\n'
