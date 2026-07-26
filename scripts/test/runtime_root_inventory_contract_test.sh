#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WRAPPER="$ROOT_DIR/scripts/check_runtime_root_inventory.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/runtime-roots-contract.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

fixture="$tmp_dir/repository with spaces"
outside="$tmp_dir/outside cwd"
manifest="$fixture/policy with spaces/runtime roots.json"
mkdir -p "$fixture" "$outside" "$(dirname "$manifest")"

python3 - "$fixture" "$manifest" <<'PY'
import json
import os
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
manifest = pathlib.Path(sys.argv[2])

files = {
    "pubspec.yaml": "name: process_fixture\n",
    ".gitignore": "build/\n",
    "lib/main.dart": "import 'main_reachable.dart';\nvoid main() {}\n",
    "lib/main_reachable.dart": "class MainReachable {}\n",
    "lib/candidate.dart": "class Candidate {}\n",
    "lib/tracked.dart": "class Tracked {}\n",
    "lib/quote'file.dart": "class QuoteFile {}\n",
    "lib/line\nbreak.dart": "class LineBreak {}\n",
    "tool/retired_analyzer.dart": "class RetiredAnalyzerTool {}\n",
    "test/retired_parser_test.dart": "void main() {}\n",
    "build/ignored.dart": "this is deliberately ignored and not valid Dart\n",
}
for relative, contents in files.items():
    path = repo / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(contents, encoding="utf-8")

def declaration(path):
    return {
        "path": path,
        "rootKinds": [],
        "disposition": "candidate",
        "owner": "Fixture owner",
        "reason": "Exact advisory fixture row.",
        "condition": "Revisit with replacement proof.",
        "evidence": [],
    }

document = {
    "schemaVersion": 1,
    "manualRoots": [],
    "externalEntrypoints": [],
    "declarations": [
        declaration("lib/candidate.dart"),
        declaration("lib/tracked.dart"),
        declaration("lib/quote'file.dart"),
        declaration("lib/line\nbreak.dart"),
    ],
    "requiredRestrictedRoots": [],
    "restrictedRoots": [],
}
manifest.write_text(
    json.dumps(document, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

git -C "$fixture" init -q
git -C "$fixture" config user.email runtime-roots@example.invalid
git -C "$fixture" config user.name runtime-roots-contract
git -C "$fixture" add -- \
  .gitignore \
  pubspec.yaml \
  lib/main.dart \
  lib/main_reachable.dart \
  lib/candidate.dart \
  lib/tracked.dart \
  tool/retired_analyzer.dart \
  test/retired_parser_test.dart
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
for path in sorted(
    (path for path in root.rglob("*") if ".git" not in path.parts),
    key=lambda item: os.fsencode(str(item.relative_to(root))),
):
    relative = os.fsencode(str(path.relative_to(root)))
    mode = path.lstat().st_mode
    digest.update(len(relative).to_bytes(8, "big"))
    digest.update(relative)
    digest.update((mode & 0o7777).to_bytes(4, "big"))
    if stat.S_ISLNK(mode):
        digest.update(b"link")
        digest.update(os.fsencode(os.readlink(path)))
    elif stat.S_ISREG(mode):
        digest.update(b"file")
        digest.update(path.read_bytes())
    elif stat.S_ISDIR(mode):
        digest.update(b"dir")
print(digest.hexdigest())
PY
}

before_digest="$(tree_digest)"
(
  cd "$outside"
  "$WRAPPER" report \
    --repo-root "$fixture" \
    --manifest "$manifest" \
    --format json >"$tmp_dir/report-a.json"
  "$WRAPPER" report \
    --repo-root="$fixture" \
    --manifest="$manifest" \
    --format=json >"$tmp_dir/report-b.json"
)
cmp "$tmp_dir/report-a.json" "$tmp_dir/report-b.json" ||
  fail 'report JSON is not byte-deterministic'

python3 - "$tmp_dir/report-a.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert document["drift"] is False
paths = [row["path"] for row in document["files"]]
assert "lib/quote'file.dart" in paths
assert "lib/line\nbreak.dart" in paths
assert "build/ignored.dart" not in paths
assert all("dead" not in row.get("disposition", "") for row in document["files"])
PY

"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format text >"$tmp_dir/check.txt"
after_digest="$(tree_digest)"
[ "$before_digest" = "$after_digest" ] ||
  fail 'report/check changed a tracked, new, or ignored fixture path'

# An ordinary non-ignored new source is advisory in report and admission drift
# in check. It is not an I/O/configuration failure.
printf '%s\n' 'class NewSource {}' >"$fixture/lib/new source.dart"
"$WRAPPER" report \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/new-report.json"
python3 - "$tmp_dir/new-report.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True and document["drift"] is True
assert any(
    issue["code"] == "unreviewed-non-main-source"
    and issue.get("path") == "lib/new source.dart"
    for issue in document["issues"]
)
PY
set +e
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format text >"$tmp_dir/new-check.txt"
new_status=$?
set -e
[ "$new_status" -eq 1 ] ||
  fail "unreviewed source returned $new_status instead of drift exit 1"
rm "$fixture/lib/new source.dart"

# A tracked deletion is stale declaration drift, not a failed file read.
rm "$fixture/lib/tracked.dart"
set +e
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/deletion.json"
deletion_status=$?
set -e
[ "$deletion_status" -eq 1 ] ||
  fail "tracked deletion returned $deletion_status instead of drift exit 1"
python3 - "$tmp_dir/deletion.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert any(issue["code"] == "stale-declaration" for issue in document["issues"])
assert any(
    issue["code"] == "tracked-path-deleted"
    and issue.get("path") == "lib/tracked.dart"
    for issue in document["issues"]
)
PY
git -C "$fixture" checkout -q -- lib/tracked.dart

# The independent Git deletion channel also catches an undeclared file that was
# main-reachable before the same worktree change removed its import.
printf '%s\n' 'void main() {}' >"$fixture/lib/main.dart"
rm "$fixture/lib/main_reachable.dart"
set +e
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/main-reachable-deletion.json"
main_reachable_deletion_status=$?
set -e
[ "$main_reachable_deletion_status" -eq 1 ] ||
  fail "main-reachable deletion returned $main_reachable_deletion_status instead of drift exit 1"
python3 - "$tmp_dir/main-reachable-deletion.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert any(
    issue["code"] == "tracked-path-deleted"
    and issue.get("path") == "lib/main_reachable.dart"
    for issue in document["issues"]
)
PY
git -C "$fixture" checkout -q -- lib/main.dart lib/main_reachable.dart

# A tracked rename preserves the deleted old-side path in the same independent
# ratchet even when the new-side file remains readable.
mv "$fixture/lib/tracked.dart" "$fixture/lib/tracked_renamed.dart"
set +e
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/rename.json"
rename_status=$?
set -e
[ "$rename_status" -eq 1 ] ||
  fail "tracked rename returned $rename_status instead of drift exit 1"
python3 - "$tmp_dir/rename.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True
assert any(
    issue["code"] == "tracked-path-deleted"
    and issue.get("path") == "lib/tracked.dart"
    for issue in document["issues"]
)
PY
mv "$fixture/lib/tracked_renamed.dart" "$fixture/lib/tracked.dart"

# Intentional non-app analyzer-tool/parser retirement is not production-source
# deletion drift. An exact manifest/evidence reference would still fail through
# its own stale-record validation.
rm "$fixture/tool/retired_analyzer.dart" "$fixture/test/retired_parser_test.dart"
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/retired-tooling.json"
python3 - "$tmp_dir/retired-tooling.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True and document["drift"] is False
assert not any(
    issue["code"] == "tracked-path-deleted"
    and issue.get("path") in {
        "tool/retired_analyzer.dart",
        "test/retired_parser_test.dart",
    }
    for issue in document["issues"]
)
PY
git -C "$fixture" checkout -q -- \
  tool/retired_analyzer.dart \
  test/retired_parser_test.dart

# Missing required anchors and malformed source prevent a trustworthy result.
mv "$fixture/lib/main.dart" "$fixture/lib/main.missing"
set +e
"$WRAPPER" report \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/missing-main.json"
missing_status=$?
set -e
[ "$missing_status" -eq 2 ] ||
  fail "missing main returned $missing_status instead of fatal exit 2"
mv "$fixture/lib/main.missing" "$fixture/lib/main.dart"

printf '%s\n' 'void main( {' >"$fixture/lib/main.dart"
set +e
"$WRAPPER" check \
  --repo-root "$fixture" \
  --manifest "$manifest" \
  --format json >"$tmp_dir/malformed.json"
malformed_status=$?
set -e
[ "$malformed_status" -eq 2 ] ||
  fail "malformed Dart returned $malformed_status instead of fatal exit 2"
git -C "$fixture" checkout -q -- lib/main.dart

for bad_args in \
  "check --unknown value" \
  "check --format" \
  "check --format text --format json" \
  "check --repo-root"; do
  # shellcheck disable=SC2086
  set +e
  "$WRAPPER" $bad_args >"$tmp_dir/bad.stdout" 2>"$tmp_dir/bad.stderr"
  bad_status=$?
  set -e
  [ "$bad_status" -eq 2 ] ||
    fail "bad argument vector '$bad_args' returned $bad_status"
  [ ! -s "$tmp_dir/bad.stdout" ] ||
    fail "bad argument vector polluted stdout: $bad_args"
done

# The named gate owns exactly the unit and real-check legs. Shims prove the
# argument vectors without recursively invoking this shell contract.
fake_bin="$tmp_dir/fake-bin"
command_log="$tmp_dir/named-gate.log"
mkdir -p "$fake_bin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "flutter" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'printf "\t%s" "$@" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'printf "\n" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'exit "${FAKE_FLUTTER_STATUS:-0}"' \
  >"$fake_bin/flutter"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf "dart" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'printf "\t%s" "$@" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'printf "\n" >>"${RUNTIME_ROOTS_COMMAND_LOG:?}"' \
  'exit "${FAKE_DART_STATUS:-0}"' \
  >"$fake_bin/dart"
chmod +x "$fake_bin/flutter" "$fake_bin/dart"

: >"$command_log"
PATH="$fake_bin:$PATH" \
  RUNTIME_ROOTS_COMMAND_LOG="$command_log" \
  "$ROOT_DIR/scripts/run_test_gates.sh" runtime-roots
python3 - "$command_log" <<'PY'
import pathlib
import sys

lines = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()
assert lines == [
    "flutter\ttest\ttest/unit/runtime_root_inventory_test.dart",
    "dart\ttool/runtime_roots/runtime_root_inventory_cli.dart\tcheck\t--format\ttext",
], lines
PY

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  RUNTIME_ROOTS_COMMAND_LOG="$command_log" \
  FAKE_FLUTTER_STATUS=23 \
  "$ROOT_DIR/scripts/run_test_gates.sh" runtime-roots >/dev/null 2>&1
flutter_failure=$?
set -e
[ "$flutter_failure" -eq 23 ] ||
  fail "named gate swallowed unit failure: $flutter_failure"
[ "$(wc -l <"$command_log" | tr -d ' ')" -eq 1 ] ||
  fail 'named gate ran check after the unit leg failed'

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  RUNTIME_ROOTS_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=24 \
  "$ROOT_DIR/scripts/run_test_gates.sh" runtime-roots >/dev/null 2>&1
dart_failure=$?
set -e
[ "$dart_failure" -eq 24 ] ||
  fail "named gate swallowed check failure: $dart_failure"
[ "$(wc -l <"$command_log" | tr -d ' ')" -eq 2 ] ||
  fail 'named gate did not run each leg exactly once'

# Canonical defaults resolve from the wrapper rather than the caller's CWD.
(
  cd "$outside"
  "$WRAPPER" check --format json >"$tmp_dir/repository-check.json"
)
python3 - "$tmp_dir/repository-check.json" <<'PY'
import json
import sys

document = json.load(open(sys.argv[1], encoding="utf-8"))
assert document["trustworthy"] is True and document["drift"] is False
PY

printf 'PASS: runtime-root report/check 0-1-2, NUL-safe, deterministic, non-mutating, and named-gate contracts\n'
