#!/usr/bin/env bash

set -euo pipefail

scope="host-all"
repo_dir=""
list_only=0
continue_on_failure=0
start_at=""
only_selector=""

usage() {
  cat <<'EOF'
Usage:
  run_host_gates.sh [host-all|feature-host-all|core-host-all|performance-host] [options]

Options:
  --repo <path>              Flutter repo root. Defaults to current dir or parent.
  --list, --dry-run          Discover host tests and print the command plan.
  --continue-on-failure      Forward to run_host_test_gates.sh.
  --start-at <N>             Forward to run_host_test_gates.sh.
  --only <N|path>            Forward to run_host_test_gates.sh.
  -h, --help                 Show this help.
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
    --repo)
      repo_dir="${2:?missing --repo value}"
      shift 2
      ;;
    --list|--dry-run)
      list_only=1
      shift
      ;;
    --continue-on-failure)
      continue_on_failure=1
      shift
      ;;
    --start-at)
      start_at="${2:?missing --start-at value}"
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

find_repo_root() {
  local dir="${1:-$PWD}"
  while [ "$dir" != "/" ]; do
    if [ -x "$dir/scripts/run_test_gates.sh" ] &&
       [ -x "$dir/scripts/run_host_test_gates.sh" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  return 1
}

if [ -n "$repo_dir" ]; then
  repo_dir="$(cd "$repo_dir" && pwd)"
else
  if ! repo_dir="$(find_repo_root "$PWD")"; then
    printf 'Could not find repo root with scripts/run_host_test_gates.sh.\n' >&2
    exit 1
  fi
fi

cd "$repo_dir"

cmd=(./scripts/run_test_gates.sh "$scope")
if [ "$list_only" -eq 1 ]; then
  cmd+=(--list)
fi
if [ "$continue_on_failure" -eq 1 ]; then
  cmd+=(--continue-on-failure)
fi
if [ -n "$start_at" ]; then
  cmd+=(--start-at "$start_at")
fi
if [ -n "$only_selector" ]; then
  cmd+=(--only "$only_selector")
fi

printf 'Running from repo: %s\n' "$repo_dir"
printf 'Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

"${cmd[@]}"
