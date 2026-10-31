#!/bin/bash
# Rerun one go-mknoon test alone inside a worktree under build/ (flake check), output to a log file.
#   host-run bash docker-ws/go_one_test_in_tree.sh <tree under build/> <package dir under go-mknoon> <test name> <count> <log in repo>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO/${1:?tree}/go-mknoon" || exit 2
export PATH="/opt/homebrew/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin" GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4
L="$REPO/${5:?log}"
go test "./${2:?pkg}" -run "^${3:?test}\$" -count="${4:?count}" -v > "$L" 2>&1; rc=$?
echo "exit=$rc" >> "$L"; grep -E '^(--- (PASS|FAIL)|ok|FAIL)' "$L" | sort | uniq -c; echo "exit=$rc"; exit $rc
