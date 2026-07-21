#!/usr/bin/env bash
# Push the current branch from the Mac host, where GitHub credentials live.
# The container checkout has no credential helper, so `git push` there fails;
# run this via `/claude-host-bin/host-run bash scripts/host_git_push.sh [args...]`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [ "$#" -gt 0 ]; then
  exec git push "$@"
fi
exec git push origin HEAD
