#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CANONICAL="$ROOT_DIR/scripts/check_flutter_analyze_strict.sh"
LEGACY="$ROOT_DIR/scripts/check_flutter_analyze_baseline.sh"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/flutter-analyze-strict-contract.XXXXXX")"
tmp_dir="$(cd "$tmp_dir" && pwd -P)"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_status() {
  expected="$1"
  actual="$2"
  label="$3"
  if [[ "$actual" -ne "$expected" ]]; then
    fail "$label returned $actual instead of $expected"
  fi
}

assert_empty_log() {
  log_path="$1"
  label="$2"
  if [[ -s "$log_path" ]]; then
    printf '%s\n' "Unexpected child calls for $label:" >&2
    cat "$log_path" >&2
    fail "$label invoked a child process"
  fi
}

assert_exact_log() {
  actual="$1"
  expected="$2"
  label="$3"
  if ! cmp -s "$actual" "$expected"; then
    printf '%s\n' "Unexpected command log for $label:" >&2
    diff -u "$expected" "$actual" >&2 || true
    fail "$label did not preserve exact child order/argv"
  fi
}

capture_git_status() {
  status_repo="$1"
  status_output="$2"
  status_code=0
  git -C "$status_repo" status \
    --porcelain=v1 -z --untracked-files=all >"$status_output" ||
    status_code=$?
  if [[ "$status_code" -ne 0 ]]; then
    fail "git status failed for $status_repo with exit $status_code"
  fi
}

assert_retired_analyzer_state_absent() {
  retired_prefix="$ROOT_DIR/tool/analyzer_baseline"
  retired_parser="$ROOT_DIR/test/unit/analyzer_baseline_parser_test.dart"
  if [[ -e "$retired_prefix" || -L "$retired_prefix" ]]; then
    fail 'retired tool/analyzer_baseline prefix still exists'
  fi
  if [[ -e "$retired_parser" || -L "$retired_parser" ]]; then
    fail 'retired analyzer baseline parser path still exists'
  fi
}

run_active_caller_census() {
  census_repo="$1"
  census_output="$2"
  census_paths="$census_output.paths"
  census_errors="$census_output.errors"
  census_git_status=0
  git -C "$census_repo" ls-files \
    --cached --others --exclude-standard -z >"$census_paths" ||
    census_git_status=$?
  if [[ "$census_git_status" -ne 0 ]]; then
    printf 'Git caller inventory failed with exit %s.\n' \
      "$census_git_status" >"$census_errors"
    return 2
  fi

  census_scan_status=0
  python3 - \
    "$census_repo" "$census_paths" >"$census_output" 2>"$census_errors" <<'PY' ||
    census_scan_status=$?
import os
import pathlib
import stat
import sys

repo = os.fsencode(os.path.realpath(sys.argv[1]))
paths_file = pathlib.Path(sys.argv[2])

try:
    raw_inventory = paths_file.read_bytes()
except OSError as error:
    print(f"Unable to read Git caller inventory: {error}", file=sys.stderr)
    raise SystemExit(2)

if raw_inventory and not raw_inventory.endswith(b"\0"):
    print("Git caller inventory is not NUL-terminated.", file=sys.stderr)
    raise SystemExit(2)

paths = [path for path in raw_inventory.split(b"\0") if path]
if len(paths) != len(set(paths)):
    print("Git caller inventory contains duplicate paths.", file=sys.stderr)
    raise SystemExit(2)

permitted_policy_paths = {
    b"scripts/check_flutter_analyze_baseline.sh",
    b"scripts/test/flutter_analyze_strict_contract_test.sh",
}
historical_prefixes = (
    b"Test-Flight-Improv/",
    b"Network-Arch/",
    b"docs/",
)
generated_prefixes = (
    b".dart_tool/",
    b"build/",
    b"graphify-out/",
    b"graphify-arch/graphify-out/",
)
result_paths = {
    b"docker-ws/flutter_analyze_log.txt",
    b"docker-ws/analyzer_baseline_result.txt",
}
active_prefixes = (
    b"scripts/",
    b"docker-ws/",
    b"tool/",
    b"test/",
    b"integration_test/",
    b"test_driver/",
    b".github/",
    b".circleci/",
    b".buildkite/",
    b"ci/",
    b"bin/",
    b"packages/",
    b"third_party/",
    b"android/",
    b"ios/",
    b"macos/",
    b"linux/",
    b"windows/",
    b"web/",
    b".claude/",
    b".codex/",
)
active_suffixes = (
    b".sh",
    b".bash",
    b".zsh",
    b".dart",
    b".yaml",
    b".yml",
    b".json",
    b".toml",
    b".gradle",
    b".kts",
    b".rb",
    b".py",
    b".pl",
    b".ps1",
    b".cmd",
    b".bat",
    b".mk",
)
active_basenames = {
    b"Makefile",
    b"GNUmakefile",
    b"Dockerfile",
    b"Jenkinsfile",
    b"Rakefile",
    b"Gemfile",
    b"Podfile",
    b"Brewfile",
    b"Justfile",
    b"justfile",
    b"gradlew",
}
forbidden = (
    b"check_flutter_analyze_baseline.sh",
    b"ANALYZER_BASELINE_FILE",
    b"ANALYZER_BASELINE_LOG_PATH",
    b"ANALYZER_BASELINE_KEEP_LOG",
    b"tool/analyzer_baseline/",
)


def is_explicit_result(path):
    if path in result_paths:
        return True
    return (
        path.startswith(b"docker-ws/")
        and path.endswith(b"_result.txt")
    )


def is_active(path, mode):
    if path.startswith(active_prefixes):
        return True
    basename = path.rsplit(b"/", 1)[-1]
    return (
        path.endswith(active_suffixes)
        or basename in active_basenames
        or basename.startswith(b"Dockerfile.")
        or stat.S_IMODE(mode) & 0o111 != 0
    )


matches = []
for path in paths:
    if (
        path.startswith(b"/")
        or b"\0" in path
        or b".." in path.split(b"/")
    ):
        print(f"Unsafe Git-visible path: {path!r}", file=sys.stderr)
        raise SystemExit(2)
    if path in permitted_policy_paths:
        continue
    if path.startswith(historical_prefixes):
        continue
    if path.startswith(generated_prefixes):
        continue
    if is_explicit_result(path):
        continue

    absolute = os.path.join(repo, path)
    if not os.path.lexists(absolute):
        # A cached deletion is not an active worktree caller.
        continue
    try:
        mode = os.lstat(absolute).st_mode
    except OSError as error:
        print(f"Unable to stat {path!r}: {error}", file=sys.stderr)
        raise SystemExit(2)
    if not is_active(path, mode):
        continue

    try:
        if stat.S_ISLNK(mode):
            contents = os.readlink(absolute)
            if isinstance(contents, str):
                contents = os.fsencode(contents)
        elif stat.S_ISREG(mode):
            with open(absolute, "rb") as source:
                contents = source.read()
        else:
            print(
                f"Git-visible active path is not a file or symlink: {path!r}",
                file=sys.stderr,
            )
            raise SystemExit(2)
    except OSError as error:
        print(f"Unable to read {path!r}: {error}", file=sys.stderr)
        raise SystemExit(2)

    for needle in forbidden:
        if needle in contents:
            matches.append((path, needle))

if matches:
    for path, needle in matches:
        print(f"{path!r}: forbidden active analyzer caller token {needle!r}")
    raise SystemExit(1)
raise SystemExit(0)
PY

  case "$census_scan_status" in
    0|1)
      return "$census_scan_status"
      ;;
    *)
      return 2
      ;;
  esac
}

capture_policy_state() {
  policy_repo="$1"
  policy_output="$2"
  policy_paths="$policy_output.paths"
  policy_status="$policy_output.status"
  policy_errors="$policy_output.errors"
  policy_git_status=0
  policy_inventory_status=0
  policy_hash_status=0
  policy_pathspecs=(
    analysis_options.yaml
    pubspec.yaml
    pubspec.lock
    scripts/check_flutter_analyze_strict.sh
    scripts/check_flutter_analyze_baseline.sh
    scripts/test/flutter_analyze_strict_contract_test.sh
    tool/analyzer_guard
    tool/analyzer_baseline
    tool/sims
    test/unit/analyzer_suppression_ratchet_test.dart
    test/unit/analyzer_baseline_parser_test.dart
  )

  git -C "$policy_repo" status \
    --porcelain=v1 -z --untracked-files=all \
    -- "${policy_pathspecs[@]}" >"$policy_status" ||
    policy_git_status=$?
  if [[ "$policy_git_status" -ne 0 ]]; then
    fail "policy/evidence git status failed with exit $policy_git_status"
  fi

  git -C "$policy_repo" ls-files \
    --cached --others --exclude-standard -z \
    -- "${policy_pathspecs[@]}" >"$policy_paths" ||
    policy_inventory_status=$?
  if [[ "$policy_inventory_status" -ne 0 ]]; then
    fail "policy/evidence Git inventory failed with exit $policy_inventory_status"
  fi

  python3 - \
    "$policy_repo" "$policy_paths" "$policy_status" \
    >"$policy_output" 2>"$policy_errors" <<'PY' ||
    policy_hash_status=$?
import hashlib
import os
import pathlib
import stat
import sys

repo = os.fsencode(os.path.realpath(sys.argv[1]))
paths_file = pathlib.Path(sys.argv[2])
status_file = pathlib.Path(sys.argv[3])

try:
    raw_paths = paths_file.read_bytes()
    raw_status = status_file.read_bytes()
except OSError as error:
    print(f"Unable to read Git-visible policy state: {error}", file=sys.stderr)
    raise SystemExit(2)

if raw_paths and not raw_paths.endswith(b"\0"):
    print("Policy path inventory is not NUL-terminated.", file=sys.stderr)
    raise SystemExit(2)
if raw_status and not raw_status.endswith(b"\0"):
    print("Policy git status is not NUL-terminated.", file=sys.stderr)
    raise SystemExit(2)

paths = [path for path in raw_paths.split(b"\0") if path]
if len(paths) != len(set(paths)):
    print("Policy path inventory contains duplicates.", file=sys.stderr)
    raise SystemExit(2)

output = sys.stdout.buffer
output.write(b"git-status\0")
output.write(len(raw_status).to_bytes(8, "big"))
output.write(raw_status)

for path in paths:
    if (
        path.startswith(b"/")
        or b"\0" in path
        or b".." in path.split(b"/")
    ):
        print(f"Unsafe policy path: {path!r}", file=sys.stderr)
        raise SystemExit(2)
    absolute = os.path.join(repo, path)
    output.write(len(path).to_bytes(8, "big"))
    output.write(path)
    if not os.path.lexists(absolute):
        output.write(b"missing\0")
        continue
    try:
        mode = os.lstat(absolute).st_mode
        output.write(stat.S_IMODE(mode).to_bytes(4, "big"))
        if stat.S_ISLNK(mode):
            target = os.readlink(absolute)
            if isinstance(target, str):
                target = os.fsencode(target)
            output.write(b"symlink\0")
            output.write(len(target).to_bytes(8, "big"))
            output.write(target)
        elif stat.S_ISREG(mode):
            digest = hashlib.sha256()
            with open(absolute, "rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
            output.write(b"file\0")
            output.write(digest.digest())
        else:
            print(
                f"Policy path is not a regular file or symlink: {path!r}",
                file=sys.stderr,
            )
            raise SystemExit(2)
    except OSError as error:
        print(f"Unable to hash policy path {path!r}: {error}", file=sys.stderr)
        raise SystemExit(2)
PY

  if [[ "$policy_hash_status" -ne 0 ]]; then
    cat "$policy_errors" >&2 || true
    fail "policy/evidence state hashing failed with exit $policy_hash_status"
  fi
}

[[ -x "$CANONICAL" ]] || fail 'canonical strict analyzer gate is not executable'
[[ -x "$LEGACY" ]] || fail 'legacy compatibility gate is not executable'

fixture="$tmp_dir/repository with spaces"
outside="$tmp_dir/outside cwd"
fake_bin="$tmp_dir/fake bin"
command_log="$tmp_dir/commands.log"
expected_log="$tmp_dir/expected.log"
mkdir -p \
  "$fixture/scripts" \
  "$fixture/.dart_tool" \
  "$fixture/tool/analyzer_guard" \
  "$outside" \
  "$fake_bin"

cp "$CANONICAL" "$fixture/scripts/check_flutter_analyze_strict.sh"
cp "$LEGACY" "$fixture/scripts/check_flutter_analyze_baseline.sh"
chmod +x \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  "$fixture/scripts/check_flutter_analyze_baseline.sh"

printf '%s\n' '{"configVersion":2,"packages":[]}' \
  >"$fixture/.dart_tool/package_config.json"
printf '%s\n' '{"schemaVersion":1,"suppressions":[]}' \
  >"$fixture/tool/analyzer_guard/production_unused_suppressions.json"
printf '%s\n' 'analyzer:' '  errors:' '    unused_import: warning' \
  >"$fixture/analysis_options.yaml"
newline_caller_probe="$fixture/scripts/caller"$'\n'"probe"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$newline_caller_probe"
chmod +x "$newline_caller_probe"

git -C "$fixture" init -q
git -C "$fixture" config user.email analyzer-contract@example.invalid
git -C "$fixture" config user.name analyzer-contract
git -C "$fixture" add -- .
git -C "$fixture" commit -qm fixture

fixture_census_status=0
run_active_caller_census \
  "$fixture" "$tmp_dir/fixture-caller-census.txt" ||
  fixture_census_status=$?
if [[ "$fixture_census_status" -ne 0 ]]; then
  cat "$tmp_dir/fixture-caller-census.txt.errors" >&2 || true
  cat "$tmp_dir/fixture-caller-census.txt" >&2 || true
  fail "NUL-safe fixture caller census failed with exit $fixture_census_status"
fi

cat >"$fake_bin/dart" <<'SH'
#!/usr/bin/env bash
{
  printf 'dart\tcwd=%s' "$PWD"
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >>"$FAKE_COMMAND_LOG"
if [[ -n "${FAKE_DART_OUTPUT:-}" ]]; then
  printf '%s\n' "$FAKE_DART_OUTPUT"
fi
exit "${FAKE_DART_STATUS:-0}"
SH

cat >"$fake_bin/flutter" <<'SH'
#!/usr/bin/env bash
{
  printf 'flutter\tcwd=%s' "$PWD"
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >>"$FAKE_COMMAND_LOG"
if [[ -n "${FAKE_FLUTTER_OUTPUT:-}" ]]; then
  printf '%s\n' "$FAKE_FLUTTER_OUTPUT"
fi
exit "${FAKE_FLUTTER_STATUS:-0}"
SH
chmod +x "$fake_bin/dart" "$fake_bin/flutter"

{
  printf 'dart\tcwd=%s\ttool/analyzer_guard/analyzer_suppression_ratchet.dart\tcheck\n' \
    "$fixture"
  printf 'flutter\tcwd=%s\tanalyze\t--no-pub\t--fatal-infos\t--fatal-warnings\n' \
    "$fixture"
} >"$expected_log"

: >"$command_log"
set +e
(
  cd "$outside"
  PATH="$fake_bin:$PATH" \
    FAKE_COMMAND_LOG="$command_log" \
    FAKE_DART_STATUS=0 \
    FAKE_FLUTTER_STATUS=0 \
    "$fixture/scripts/check_flutter_analyze_strict.sh"
) >"$tmp_dir/canonical-success.out" 2>&1
canonical_success_status=$?
set -e
assert_status 0 "$canonical_success_status" 'canonical strict success'
assert_exact_log "$command_log" "$expected_log" 'canonical strict success'

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=1 \
  FAKE_FLUTTER_STATUS=0 \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  >"$tmp_dir/checker-drift.out" 2>&1
checker_drift_status=$?
set -e
assert_status 1 "$checker_drift_status" 'suppression drift'
head -n 1 "$expected_log" >"$tmp_dir/checker-only.log"
assert_exact_log "$command_log" "$tmp_dir/checker-only.log" 'suppression drift'

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=2 \
  FAKE_FLUTTER_STATUS=0 \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  >"$tmp_dir/checker-untrusted.out" 2>&1
checker_untrusted_status=$?
set -e
assert_status 2 "$checker_untrusted_status" 'untrustworthy suppression check'
assert_exact_log \
  "$command_log" "$tmp_dir/checker-only.log" \
  'untrustworthy suppression check'

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=0 \
  FAKE_FLUTTER_STATUS=7 \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  >"$tmp_dir/analyzer-failure.out" 2>&1
analyzer_failure_status=$?
set -e
assert_status 7 "$analyzer_failure_status" 'strict Flutter analyzer failure'
assert_exact_log "$command_log" "$expected_log" 'strict Flutter analyzer failure'

for wrapper in \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  "$fixture/scripts/check_flutter_analyze_baseline.sh"; do
  : >"$command_log"
  set +e
  PATH="$fake_bin:$PATH" \
    FAKE_COMMAND_LOG="$command_log" \
    FAKE_DART_STATUS=0 \
    FAKE_FLUTTER_STATUS=0 \
    "$wrapper" --no-fatal-warnings >"$tmp_dir/argument-rejection.out" 2>&1
  argument_status=$?
  set -e
  assert_status 2 "$argument_status" "$(basename "$wrapper") argument rejection"
  assert_empty_log "$command_log" "$(basename "$wrapper") argument rejection"
done

: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=0 \
  FAKE_FLUTTER_STATUS=0 \
  "$fixture/scripts/check_flutter_analyze_baseline.sh" \
  >"$tmp_dir/legacy-success.out" 2>&1
legacy_success_status=$?
set -e
assert_status 0 "$legacy_success_status" 'legacy strict delegate'
assert_exact_log "$command_log" "$expected_log" 'legacy strict delegate'

mv \
  "$fixture/.dart_tool/package_config.json" \
  "$tmp_dir/package_config.json"
: >"$command_log"
set +e
PATH="$fake_bin:$PATH" \
  FAKE_COMMAND_LOG="$command_log" \
  FAKE_DART_STATUS=0 \
  FAKE_FLUTTER_STATUS=0 \
  "$fixture/scripts/check_flutter_analyze_strict.sh" \
  >"$tmp_dir/missing-package-config.out" 2>&1
missing_config_status=$?
set -e
assert_status 2 "$missing_config_status" 'missing package config'
assert_empty_log "$command_log" 'missing package config'
mv \
  "$tmp_dir/package_config.json" \
  "$fixture/.dart_tool/package_config.json"

fixture_git_status="$tmp_dir/fixture-git-status.z"
capture_git_status "$fixture" "$fixture_git_status"
if [[ -s "$fixture_git_status" ]]; then
  tr '\0' '\n' <"$fixture_git_status" >&2 ||
    fail 'unable to print unexpected fixture Git status'
  fail 'strict gate changed tracked policy/evidence or created repository state'
fi

if rg -n \
  'flutter analyze|dart (run )?tool/analyzer|ANALYZER_BASELINE_|mktemp|compare' \
  "$LEGACY" >/dev/null; then
  fail 'legacy compatibility gate contains analyzer or baseline policy'
fi
rg -qF 'exec "$ROOT_DIR/scripts/check_flutter_analyze_strict.sh"' "$LEGACY" ||
  fail 'legacy compatibility gate is not a direct strict delegate'

printf '%s\n' \
  'PASS: strict analyzer invocation argument rejection and exit propagation'
printf '%s\n' \
  'PASS: ratchet precedes analysis both statuses are fatal and tracked policy is read only'

assert_retired_analyzer_state_absent

caller_census_status=0
run_active_caller_census \
  "$ROOT_DIR" "$tmp_dir/repository-caller-census.txt" ||
  caller_census_status=$?
case "$caller_census_status" in
  0)
    ;;
  1)
    cat "$tmp_dir/repository-caller-census.txt" >&2 ||
      fail 'unable to print stale analyzer caller census'
    fail 'an active repository caller still depends on analyzer baseline state'
    ;;
  *)
    cat "$tmp_dir/repository-caller-census.txt.errors" >&2 || true
    fail "active analyzer caller census failed with exit $caller_census_status"
    ;;
esac

docker_helpers=(
  "docker-ws/run_group_notification_fix_tests.sh"
  "docker-ws/run_pending_replay_tests.sh"
  "docker-ws/rerun_analyzer_baseline.sh"
)
for helper in "${docker_helpers[@]}"; do
  rg -qF './scripts/check_flutter_analyze_strict.sh' "$ROOT_DIR/$helper" ||
    fail "$helper does not call the canonical strict analyzer gate"
  if rg -n \
    'ANALYZER_BASELINE_|check_flutter_analyze_baseline\.sh|analyzer baseline' \
    "$ROOT_DIR/$helper" >/dev/null; then
    fail "$helper retains baseline labels, state, or caller behavior"
  fi
done

helper_repo="$tmp_dir/helper repository"
helper_fake_bin="$tmp_dir/helper fake bin"
helper_mktemp_fail_bin="$tmp_dir/helper mktemp failure bin"
helper_persist_fail_bin="$tmp_dir/helper persist failure bin"
mkdir -p \
  "$helper_repo/docker-ws" \
  "$helper_repo/scripts" \
  "$helper_fake_bin" \
  "$helper_mktemp_fail_bin" \
  "$helper_persist_fail_bin"
for helper in "${docker_helpers[@]}"; do
  cp "$ROOT_DIR/$helper" "$helper_repo/$helper"
  chmod +x "$helper_repo/$helper"
done

cat >"$helper_repo/scripts/check_flutter_analyze_strict.sh" <<'SH'
#!/usr/bin/env bash
: "${FAKE_STRICT_LOG:?FAKE_STRICT_LOG is required}"
{
  printf 'strict\thelper=%s\tcwd=%s\targc=%s' \
    "${FAKE_HELPER_IDENTITY:-missing}" "$PWD" "$#"
  for argument in "$@"; do
    printf '\t%s' "$argument"
  done
  printf '\n'
} >>"$FAKE_STRICT_LOG"
printf '%s\n' 'strict fixture output'
exit "${FAKE_STRICT_STATUS:-0}"
SH
cat >"$helper_fake_bin/flutter" <<'SH'
#!/usr/bin/env bash
printf '%s\n' 'Flutter fixture output'
exit "${FAKE_FLUTTER_STATUS:-0}"
SH
cat >"$helper_mktemp_fail_bin/mktemp" <<'SH'
#!/usr/bin/env bash
exit 73
SH
cat >"$helper_persist_fail_bin/mv" <<'SH'
#!/usr/bin/env bash
exit 74
SH
chmod +x \
  "$helper_repo/scripts/check_flutter_analyze_strict.sh" \
  "$helper_fake_bin/flutter" \
  "$helper_mktemp_fail_bin/mktemp" \
  "$helper_persist_fail_bin/mv"

assert_strict_helper_call() {
  helper_log="$1"
  helper_identity="$2"
  helper_expected="$tmp_dir/strict-helper-expected.log"
  printf 'strict\thelper=%s\tcwd=%s\targc=0\n' \
    "$helper_identity" "$helper_repo" >"$helper_expected"
  assert_exact_log \
    "$helper_log" "$helper_expected" \
    "$helper_identity strict helper invocation"
}

aggregators=(
  "run_group_notification_fix_tests.sh"
  "run_pending_replay_tests.sh"
)
for aggregator in "${aggregators[@]}"; do
  strict_log="$tmp_dir/$aggregator.strict.log"
  : >"$strict_log"
  set +e
  PATH="$helper_fake_bin:$PATH" \
    FAKE_FLUTTER_STATUS=0 \
    FAKE_STRICT_STATUS=9 \
    FAKE_STRICT_LOG="$strict_log" \
    FAKE_HELPER_IDENTITY="$aggregator" \
    "$helper_repo/docker-ws/$aggregator" \
    >"$tmp_dir/$aggregator.out" 2>&1
  aggregator_status=$?
  set -e
  assert_status 1 "$aggregator_status" "$aggregator analyzer failure"
  assert_strict_helper_call "$strict_log" "$aggregator"
  rg -qF 'strict analyzer: FAILED' "$tmp_dir/$aggregator.out" ||
    fail "$aggregator did not print its strict analyzer failure"
  rg -q '^FAILED$' "$tmp_dir/$aggregator.out" ||
    fail "$aggregator did not print its final failed result"

  : >"$strict_log"
  set +e
  PATH="$helper_mktemp_fail_bin:$helper_fake_bin:$PATH" \
    FAKE_FLUTTER_STATUS=0 \
    FAKE_STRICT_STATUS=0 \
    FAKE_STRICT_LOG="$strict_log" \
    FAKE_HELPER_IDENTITY="$aggregator:mktemp-failure" \
    "$helper_repo/docker-ws/$aggregator" \
    >"$tmp_dir/$aggregator.mktemp-failure.out" 2>&1
  mktemp_failure_status=$?
  set -e
  assert_status 2 "$mktemp_failure_status" "$aggregator mktemp failure"
  assert_empty_log "$strict_log" "$aggregator mktemp failure"
  rg -qF 'Unable to create result staging file' \
    "$tmp_dir/$aggregator.mktemp-failure.out" ||
    fail "$aggregator did not diagnose result staging failure"

  persist_identity="$aggregator:persist-failure"
  : >"$strict_log"
  set +e
  PATH="$helper_persist_fail_bin:$helper_fake_bin:$PATH" \
    FAKE_FLUTTER_STATUS=0 \
    FAKE_STRICT_STATUS=0 \
    FAKE_STRICT_LOG="$strict_log" \
    FAKE_HELPER_IDENTITY="$persist_identity" \
    "$helper_repo/docker-ws/$aggregator" \
    >"$tmp_dir/$aggregator.persist-failure.out" 2>&1
  persist_failure_status=$?
  set -e
  assert_status 2 "$persist_failure_status" "$aggregator persist failure"
  assert_strict_helper_call "$strict_log" "$persist_identity"
  rg -qF 'Unable to persist result atomically' \
    "$tmp_dir/$aggregator.persist-failure.out" ||
    fail "$aggregator did not diagnose atomic result persistence failure"
done

rerun_strict_log="$tmp_dir/rerun.strict.log"
: >"$rerun_strict_log"
set +e
FAKE_STRICT_STATUS=7 \
  FAKE_STRICT_LOG="$rerun_strict_log" \
  FAKE_HELPER_IDENTITY=rerun_analyzer_baseline.sh \
  "$helper_repo/docker-ws/rerun_analyzer_baseline.sh" \
  >"$tmp_dir/rerun.out" 2>&1
rerun_status=$?
set -e
assert_status 7 "$rerun_status" 'strict analyzer rerun helper'
assert_strict_helper_call \
  "$rerun_strict_log" "rerun_analyzer_baseline.sh"
rerun_result="$helper_repo/docker-ws/analyzer_strict_result.txt"
[[ -f "$rerun_result" ]] ||
  fail 'strict analyzer rerun helper did not persist its output'
rg -qF 'strict fixture output' "$rerun_result" ||
  fail 'strict analyzer rerun helper omitted child output from persisted result'
rg -qF 'exit=7' "$rerun_result" ||
  fail 'strict analyzer rerun helper omitted the exact child status'
rg -qF 'strict fixture output' "$tmp_dir/rerun.out" ||
  fail 'strict analyzer rerun helper did not print persisted child output'
rg -qF 'exit=7' "$tmp_dir/rerun.out" ||
  fail 'strict analyzer rerun helper did not print the exact child status'

printf '%s\n' \
  'PASS: legacy baseline artifacts retire atomically and compatibility is strict'

before_one="$tmp_dir/analyzer-before-one.txt"
before_two="$tmp_dir/analyzer-before-two.txt"
after_one="$tmp_dir/analyzer-after-one.txt"
printf '%s\n' \
  'WARNING|STATIC_WARNING|UNUSED_IMPORT|lib/a.dart|1|1|1|unused a' \
  >"$before_one"
printf '%s\n' \
  'WARNING|STATIC_WARNING|UNUSED_IMPORT|lib/a.dart|1|1|1|unused a' \
  'INFO|HINT|DEAD_CODE|lib/b.dart|2|1|1|dead b' \
  >"$before_two"
cp "$before_one" "$after_one"

policy_state_before="$tmp_dir/policy-state-before.bin"
policy_state_after="$tmp_dir/policy-state-after.bin"
capture_policy_state "$ROOT_DIR" "$policy_state_before"
assert_retired_analyzer_state_absent

set +e
(
  cd "$ROOT_DIR"
  ANALYZER_BASELINE_FILE="$tmp_dir/does-not-exist.tsv" \
    dart tool/sims/sims.dart verify-analyzer-delta \
      "$before_one" "$before_two"
) >"$tmp_dir/delta-add.out" 2>&1
delta_add_status=$?
set -e
assert_status 1 "$delta_add_status" 'transient analyzer delta issue addition'

(
  cd "$ROOT_DIR"
  ANALYZER_BASELINE_FILE="$tmp_dir/does-not-exist.tsv" \
    dart tool/sims/sims.dart verify-analyzer-delta \
      "$before_two" "$after_one"
) >"$tmp_dir/delta-shrink.out" 2>&1 ||
  fail 'transient analyzer delta rejected a strict shrink'
rg -qF 'introduced 0 new machine-reported issues' "$tmp_dir/delta-shrink.out" ||
  fail 'transient analyzer delta did not report a clean shrink'

capture_policy_state "$ROOT_DIR" "$policy_state_after"
if ! cmp -s "$policy_state_before" "$policy_state_after"; then
  fail 'Sims analyzer delta changed Git-visible policy/evidence state'
fi
assert_retired_analyzer_state_absent

printf '%s\n' \
  'PASS: transient Sims analyzer delta remains independent'
printf '%s\n' 'PASS: strict analyzer shell/process contract'
