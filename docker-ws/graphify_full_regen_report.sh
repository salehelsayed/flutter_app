#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"
export PYTHONHASHSEED=0

graphify cluster-only . --no-label
echo "full cluster-only exit: $?"
