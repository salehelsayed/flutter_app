#!/bin/bash
# Run one Python unittest file on the Mac inside a repo worktree under build/.  host-run bash docker-ws/run_py_unittest_in_tree.sh <tree dir> <test file>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO/${1:?tree}" || exit 2
python3 -m unittest -v "${2:?test}" 2>&1 | tail -25
