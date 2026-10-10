#!/bin/bash
# Plan 414: run the Go binding staleness contract in this worktree and in the main checkout.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "=== worktree"; (cd "$ROOT" && bash scripts/test/go_binding_staleness_contract_test.sh; echo "exit=$?") 2>&1 | tail -15
echo "=== main"; (cd /Volumes/CrucialX9/flutter_app && bash scripts/test/go_binding_staleness_contract_test.sh; echo "exit=$?") 2>&1 | tail -6
