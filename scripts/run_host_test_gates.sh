#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

scope="host-all"
dry_run=0
continue_on_failure=0
start_at=1
only_selector=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/run_host_test_gates.sh [host-all|feature-host-all|core-host-all|performance-host] [options]

Options:
  --list, --dry-run          Discover host tests and print the command plan only.
  --continue-on-failure      Run the remaining commands after a failure.
  --start-at <N>             Run the planned command list starting at item N.
  --only <N|path>            Run only planned item N or the exact planned path.
  -h, --help                 Show this help.

Scopes:
  host-all                   All test/**/*_test.dart except test/performance/**.
  feature-host-all           All test/features/**/*_test.dart.
  core-host-all              All test/core/**/*_test.dart.
  performance-host           All test/performance/**/*_test.dart.
EOF
}

while (($# > 0)); do
  case "$1" in
    host-all|all)
      scope="host-all"
      shift
      ;;
    feature-host-all|features)
      scope="feature-host-all"
      shift
      ;;
    core-host-all|core)
      scope="core-host-all"
      shift
      ;;
    performance-host|performance)
      scope="performance-host"
      shift
      ;;
    --list|--dry-run)
      dry_run=1
      shift
      ;;
    --continue-on-failure)
      continue_on_failure=1
      shift
      ;;
    --start-at)
      start_at="${2:?missing --start-at value}"
      if ! [[ "$start_at" =~ ^[0-9]+$ ]] || [ "$start_at" -lt 1 ]; then
        printf 'Invalid --start-at value: %s\n' "$start_at" >&2
        exit 2
      fi
      shift 2
      ;;
    --only)
      only_selector="${2:?missing --only value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v rg >/dev/null 2>&1; then
  printf 'ripgrep (rg) is required for host test discovery.\n' >&2
  exit 1
fi

plan_file="$(mktemp)"
indexed_plan_file="$(mktemp)"
active_plan_file="$(mktemp)"
failures_file="$(mktemp)"
trap 'rm -f "$plan_file" "$indexed_plan_file" "$active_plan_file" "$failures_file"' EXIT

case "$scope" in
  host-all)
    rg --files test -g '*_test.dart' | awk '$0 !~ /^test\/performance\//' | sort >"$plan_file"
    ;;
  feature-host-all)
    rg --files test/features -g '*_test.dart' | sort >"$plan_file"
    ;;
  core-host-all)
    rg --files test/core -g '*_test.dart' | sort >"$plan_file"
    ;;
  performance-host)
    rg --files test/performance -g '*_test.dart' | sort >"$plan_file"
    ;;
esac

if [ ! -s "$plan_file" ]; then
  printf 'No host test files matched scope: %s\n' "$scope" >&2
  exit 1
fi

awk '{ print NR "\t" $0 }' "$plan_file" >"$indexed_plan_file"

awk -F '\t' -v start_at="$start_at" -v only_selector="$only_selector" '
  function is_number(value) {
    return value ~ /^[0-9]+$/
  }
  {
    plan_index = $1
    path = $2

    if (only_selector != "") {
      if (is_number(only_selector)) {
        if (plan_index == only_selector) {
          print
        }
      } else if (path == only_selector) {
        print
      }
      next
    }

    if (plan_index >= start_at) {
      print
    }
  }
' "$indexed_plan_file" >"$active_plan_file"

if [ ! -s "$active_plan_file" ]; then
  printf 'No host test commands matched the requested resume filter.\n' >&2
  exit 1
fi

quote_for_display() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

print_command_for_path() {
  local path="$1"
  printf 'flutter test %s' "$(quote_for_display "$path")"
}

run_path() {
  local path="$1"
  flutter test "$path"
}

printf '\nHost test command plan: %s\n' "$scope"
if [ "$start_at" -ne 1 ]; then
  printf 'Resume filter: starting at planned item #%s\n' "$start_at"
fi
if [ -n "$only_selector" ]; then
  printf 'Resume filter: only %s\n' "$only_selector"
fi

command_count=0
while IFS=$'\t' read -r index path; do
  [ -n "$path" ] || continue
  command_count=$((command_count + 1))
  printf '  %3d. ' "$index"
  print_command_for_path "$path"
  printf '\n'
done <"$active_plan_file"

if [ "$dry_run" -eq 1 ]; then
  printf '\nDry run only. Host test discovery passed and no commands were executed.\n'
  exit 0
fi

printf '\nRunning %s host test command(s)...\n' "$command_count"
while IFS=$'\t' read -r index path; do
  [ -n "$path" ] || continue
  printf '\n==> #%s ' "$index"
  print_command_for_path "$path"
  printf '\n'

  if run_path "$path"; then
    printf 'PASS: #%s %s\n' "$index" "$path"
  else
    status=$?
    printf 'FAIL: #%s %s exited with %s\n' "$index" "$path" "$status" >&2
    printf '%s\t%s\t%s\n' "$index" "$path" "$status" >>"$failures_file"
    if [ "$continue_on_failure" -ne 1 ]; then
      exit "$status"
    fi
  fi
done <"$active_plan_file"

failure_count="$(awk 'END { print NR + 0 }' "$failures_file")"
if [ "$failure_count" -gt 0 ]; then
  printf '\nHost tests failed (%s):\n' "$failure_count" >&2
  awk -F '\t' '{ printf "  - #%s %s exited with %s\n", $1, $2, $3 }' "$failures_file" >&2
  exit 1
fi

printf '\nPASS: host tests completed for scope: %s\n' "$scope"
