#!/usr/bin/env bash
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:$PATH"
cd "${CLAUDE_HOST_REPO_ROOT:-$(pwd)}"

graphify_python="$(head -1 "$(command -v graphify)" | tr -d '#!')"
echo "graphify python: $graphify_python"
"$graphify_python" -c "import graphify; print('graphify pkg version:', getattr(graphify,'__version__','?'))" 2>&1

echo "=== applying patch ==="
"$graphify_python" graphify-arch/patches/apply_dart_extractor_patch.py
echo "patch exit: $?"
