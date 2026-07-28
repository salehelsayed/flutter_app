#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLI="$ROOT_DIR/tool/architecture_guard/architecture_boundary_checker_cli.dart"
WRAPPER="$ROOT_DIR/scripts/check_architecture_boundaries.sh"
GATE="$ROOT_DIR/scripts/run_test_gates.sh"
MANIFEST="$ROOT_DIR/tool/architecture_guard/architecture_boundary_exceptions.json"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for path in "$CLI" "$WRAPPER" "$GATE" "$MANIFEST"; do
  [ -f "$path" ] || fail "missing architecture-boundary surface: $path"
done
[ -x "$WRAPPER" ] || fail 'architecture-boundary wrapper is not executable'

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/architecture-boundaries-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repository with spaces"
outside="$tmp_dir/outside cwd"
fixture_manifest="$fixture/tool/architecture_guard/architecture_boundary_exceptions.json"
mkdir -p \
  "$fixture/lib/core" \
  "$fixture/lib/features/example/domain" \
  "$(dirname "$fixture_manifest")" \
  "$outside"

printf '%s\n' 'name: process_fixture' >"$fixture/pubspec.yaml"
printf '%s\n' 'class StableCore {}' >"$fixture/lib/core/stable_core.dart"
printf '%s\n' \
  'abstract class ExampleRepository {}' \
  >"$fixture/lib/features/example/domain/example_repository.dart"
python3 - "$fixture_manifest" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
path.write_text(
    json.dumps(
        {
            "schemaVersion": 1,
            "policy": {
                "layers": [
                    "core",
                    "domain",
                    "application",
                    "presentation",
                ],
                "rules": [
                    "core-must-not-depend-on-feature",
                    "lower-layer-must-not-depend-upward",
                    "feature-domain-concrete-repository",
                ],
            },
            "dependencyExceptions": [],
            "placementExceptions": [],
        },
        indent=2,
    )
    + "\n",
    encoding="utf-8",
)
PY

git -C "$fixture" init -q
git -C "$fixture" config user.email architecture-boundaries@example.invalid
git -C "$fixture" config user.name architecture-boundaries-contract
git -C "$fixture" add -- .
git -C "$fixture" commit -qm fixture

tree_digest() {
  python3 - "$fixture" <<'PY'
import hashlib
import os
import pathlib
import stat
import sys

root = pathlib.Path(sys.argv[1])
digest = hashlib.sha256()
paths = sorted(
    (path for path in root.rglob("*") if ".git" not in path.parts),
    key=lambda path: os.fsencode(str(path.relative_to(root))),
)
for path in paths:
    relative = os.fsencode(str(path.relative_to(root)))
    info = path.lstat()
    digest.update(relative)
    digest.update(str(stat.S_IMODE(info.st_mode)).encode())
    if stat.S_ISREG(info.st_mode):
        digest.update(b"file")
        digest.update(path.read_bytes())
    elif stat.S_ISDIR(info.st_mode):
        digest.update(b"dir")
    elif stat.S_ISLNK(info.st_mode):
        digest.update(b"link")
        digest.update(os.fsencode(os.readlink(path)))
print(digest.hexdigest())
PY
}

run_cli() {
  (
    cd "$ROOT_DIR"
    dart "$CLI" "$@"
  )
}

# Real CLI fixture: trustworthy report/check are deterministic, read-only, and
# use the validated fixture-only overrides that the release wrapper never
# exposes.
before_digest="$(tree_digest)"
run_cli report \
  --repo-root "$fixture" \
  --manifest "$fixture_manifest" \
  --format json >"$tmp_dir/report-a.json"
run_cli report \
  --repo-root="$fixture" \
  --manifest="$fixture_manifest" \
  --format=json >"$tmp_dir/report-b.json"
cmp "$tmp_dir/report-a.json" "$tmp_dir/report-b.json" ||
  fail 'architecture-boundary JSON report is not byte deterministic'
run_cli check \
  --repo-root "$fixture" \
  --manifest "$fixture_manifest" \
  --format text >"$tmp_dir/check.txt"
after_digest="$(tree_digest)"
[ "$before_digest" = "$after_digest" ] ||
  fail 'architecture-boundary report/check mutated the fixture'

python3 - "$tmp_dir/report-a.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert document["drift"] is False
PY

# A new semantic edge is trusted policy drift: report remains diagnostic zero,
# while check returns one against the unchanged reviewed manifest.
printf '%s\n' \
  "import 'package:process_fixture/features/example/domain/example_repository.dart';" \
  'ExampleRepository? repository;' \
  >"$fixture/lib/core/new_forbidden_edge.dart"
set +e
run_cli report \
  --repo-root "$fixture" \
  --manifest "$fixture_manifest" \
  --format json >"$tmp_dir/drift-report.json"
report_status=$?
run_cli check \
  --repo-root "$fixture" \
  --manifest "$fixture_manifest" \
  --format text >"$tmp_dir/drift-check.txt"
check_status=$?
set -e
[ "$report_status" -eq 0 ] ||
  fail "trusted drift report returned $report_status instead of 0"
[ "$check_status" -eq 1 ] ||
  fail "trusted drift check returned $check_status instead of 1"
python3 - "$tmp_dir/drift-report.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert document["drift"] is True
PY

# Unsupported modes/options and an unsafe manifest override are untrustworthy
# usage/configuration failures.
cp "$fixture_manifest" "$tmp_dir/outside-manifest.json"
for bad_case in unknown-mode unknown-option outside-manifest; do
  set +e
  case "$bad_case" in
    unknown-mode)
      run_cli update \
        --repo-root "$fixture" \
        --manifest "$fixture_manifest" \
        >"$tmp_dir/bad.stdout" 2>"$tmp_dir/bad.stderr"
      ;;
    unknown-option)
      run_cli check \
        --repo-root "$fixture" \
        --manifest "$fixture_manifest" \
        --unknown \
        >"$tmp_dir/bad.stdout" 2>"$tmp_dir/bad.stderr"
      ;;
    outside-manifest)
      run_cli check \
        --repo-root "$fixture" \
        --manifest "$tmp_dir/outside-manifest.json" \
        >"$tmp_dir/bad.stdout" 2>"$tmp_dir/bad.stderr"
      ;;
  esac
  bad_status=$?
  set -e
  [ "$bad_status" -eq 2 ] ||
    fail "$bad_case returned $bad_status instead of 2"
done

# Wrapper and named-gate contract: the public surfaces reject arguments, bind
# the real root, run the exact unit leg first, and preserve fail-fast statuses.
fake_bin="$tmp_dir/fake-bin"
command_log="$tmp_dir/named-gate.log"
mkdir -p "$fake_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "flutter" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'printf "\t%s" "$@" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'printf "\n" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'exit "${FAKE_FLUTTER_STATUS:-0}"' \
  >"$fake_bin/flutter"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "dart" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'printf "\t%s" "$@" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'printf "\n" >>"${ARCHITECTURE_BOUNDARY_COMMAND_LOG:?}"' \
  'exit "${FAKE_DART_STATUS:-0}"' \
  >"$fake_bin/dart"
chmod +x "$fake_bin/flutter" "$fake_bin/dart"

: >"$command_log"
(
  cd "$outside"
  PATH="$fake_bin:$PATH" \
    ARCHITECTURE_BOUNDARY_COMMAND_LOG="$command_log" \
    "$GATE" architecture-boundaries
)
python3 - "$command_log" "$ROOT_DIR" <<'PY'
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
root = sys.argv[2]
assert lines == [
    "flutter\ttest\t--no-pub\ttest/unit/architecture_boundary_checker_test.dart",
    (
        "dart\trun\ttool/architecture_guard/architecture_boundary_checker_cli.dart"
        f"\tcheck\t--repo-root\t{root}\t--manifest"
        f"\t{root}/tool/architecture_guard/architecture_boundary_exceptions.json"
    ),
], lines
PY

for surface in wrapper gate; do
  : >"$command_log"
  set +e
  if [ "$surface" = wrapper ]; then
    PATH="$fake_bin:$PATH" \
      ARCHITECTURE_BOUNDARY_COMMAND_LOG="$command_log" \
      "$WRAPPER" unexpected >"$tmp_dir/args.stdout" 2>"$tmp_dir/args.stderr"
  else
    PATH="$fake_bin:$PATH" \
      ARCHITECTURE_BOUNDARY_COMMAND_LOG="$command_log" \
      "$GATE" architecture-boundaries unexpected \
      >"$tmp_dir/args.stdout" 2>"$tmp_dir/args.stderr"
  fi
  argument_status=$?
  set -e
  [ "$argument_status" -eq 2 ] ||
    fail "$surface accepted arguments or returned $argument_status"
  [ ! -s "$command_log" ] ||
    fail "$surface invoked a child after rejecting arguments"
done

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  ARCHITECTURE_BOUNDARY_COMMAND_LOG="$command_log" \
  FAKE_FLUTTER_STATUS=23 \
  "$GATE" architecture-boundaries >"$tmp_dir/flutter.stdout" 2>&1
flutter_status=$?
set -e
[ "$flutter_status" -eq 23 ] ||
  fail "named gate swallowed unit failure: $flutter_status"
[ "$(wc -l <"$command_log" | tr -d ' ')" -eq 1 ] ||
  fail 'named gate ran the real check after unit failure'

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  ARCHITECTURE_BOUNDARY_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=24 \
  "$GATE" architecture-boundaries >"$tmp_dir/dart.stdout" 2>&1
dart_status=$?
set -e
[ "$dart_status" -eq 24 ] ||
  fail "named gate swallowed real-check failure: $dart_status"
[ "$(wc -l <"$command_log" | tr -d ' ')" -eq 2 ] ||
  fail 'named gate did not invoke each child exactly once'

# Registration proof: usage/docs name the lane, core-host-all classifies its
# unit suite, sims-contracts auto-discovers this process proof, and release
# major owns the named lane through its typed capability.
rg -F './scripts/run_test_gates.sh architecture-boundaries' \
  "$ROOT_DIR/Test-Flight-Improv/test-gate-definitions.md" >/dev/null ||
  fail 'canonical gate documentation omits architecture-boundaries'
"$ROOT_DIR/scripts/run_host_test_gates.sh" \
  core-host-all --list --dart-only |
  rg -F "test/unit/architecture_boundary_checker_test.dart" >/dev/null ||
  fail 'core-host-all does not classify the boundary unit suite'
"$GATE" sims-contracts --list |
  rg -F 'scripts/test/architecture_boundary_checker_contract_test.sh' \
    >/dev/null ||
  fail 'sims-contracts does not discover the boundary process contract'
"$GATE" sims major --list --format json >"$tmp_dir/major.json"
python3 - "$tmp_dir/major.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
rows = [row for row in document["rows"] if row["id"] == "architecture.boundaries"]
assert len(rows) == 1
row = rows[0]
assert row["required"] is True
assert row["active"] is True
assert row["modes"] == ["major"]
assert row["families"] == ["infra"]
assert row["command"] == [
    "./scripts/run_test_gates.sh",
    "architecture-boundaries",
]
PY

printf '%s\n' \
  'PASS: architecture boundary CLI and named gate process contract'
