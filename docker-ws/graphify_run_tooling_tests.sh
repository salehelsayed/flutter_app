#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"
python3 graphify-arch/tests/test_graphify_arch_tooling.py 2>&1 | tail -8
