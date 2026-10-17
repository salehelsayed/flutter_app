#!/bin/bash
# Run scripts/mknoon_checks.py on the Mac with the toolchain env Codex uses.
# Output goes to a log file (bridge stdout is buffered); the exit code is the runner's.
#   host-run bash docker-ws/mknoon_checks_host.sh <log file in repo> <mknoon_checks args...>
set -uo pipefail
cd "$(dirname "$0")/.."
LOG="${1:?log file}"; shift
REPO="$PWD"
. "$REPO/docker-ws/_host_paths.sh"
mknoon_require_output "$REPO" "$LOG" || exit 2
EXPECT_OUTPUT=0
for ARG in "$@"; do
  if [ "$EXPECT_OUTPUT" = 1 ]; then
    mknoon_require_output "$REPO" "$ARG/.output-check" || exit 2
    EXPECT_OUTPUT=0
  else
    case "$ARG" in
      --output|--report-directory) EXPECT_OUTPUT=1 ;;
      --output=*|--report-directory=*) mknoon_require_output "$REPO" "${ARG#*=}/.output-check" || exit 2 ;;
    esac
  fi
done
[ "$EXPECT_OUTPUT" = 0 ] || { echo "missing output directory"; exit 2; }
mkdir -p "$(dirname "$LOG")" || exit 2
export PATH="/Users/I560101/development/flutter-3.47.2/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 GOFLAGS=-p=4 GRADLE_OPTS='-Dorg.gradle.workers.max=2 -Dorg.gradle.parallel=false'
python3 scripts/mknoon_checks.py "$@" > "$LOG" 2>&1
rc=$?; echo "exit=$rc" >> "$LOG"; exit $rc
