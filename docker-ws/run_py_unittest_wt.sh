#!/bin/bash
# Run one python unittest target in a worktree on the Mac with python3.15, with a time limit.
#   bash docker-ws/run_py_unittest_wt.sh <worktree> <seconds> <unittest target>
cd "$1" || exit 2
start=$(date +%s)
/opt/homebrew/opt/python@3.15/bin/python3.15 -m unittest "$3" 2>&1 | tail -4 || true
echo "elapsed $(( $(date +%s) - start )) s"
