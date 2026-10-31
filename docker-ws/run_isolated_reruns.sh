#!/bin/bash
# Isolated reruns in a clean environment (no MKNOON_*/SIMS_* exports), one at a time, logs to <out>.
#   host-run bash docker-ws/run_isolated_reruns.sh <out dir under .codex-test-logs/> <step>...
#   steps: go-holepunch | batch-contract | sims-verification
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$REPO/${1:?out}"; shift; mkdir -p "$OUT"
CLEAN=(env -i HOME="$HOME" USER="$USER" TMPDIR="${TMPDIR:-/tmp}" LANG=en_US.UTF-8
  PATH="$HOME/development/flutter-3.47.2/bin:/usr/local/go/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 GOFLAGS=-p=4)
for S in "$@"; do
  case "$S" in
    go-holepunch) (cd "$REPO/go-mknoon" && "${CLEAN[@]}" go test ./node -count=1 -v -run '^(TestHolePunchFeasibility_LoopbackUpgradeObservable|TestHolePunchNegativeControl_RelayOnly_NoUpgradeNoThrash)$') > "$OUT/$S.log" 2>&1 ;;
    batch-contract) (cd "$REPO" && "${CLEAN[@]}" bash scripts/test/host_test_gate_batch_contract_test.sh) > "$OUT/$S.log" 2>&1 ;;
    batch-contract-trace) (cd "$REPO" && "${CLEAN[@]}" bash -x scripts/test/host_test_gate_batch_contract_test.sh) > "$OUT/$S.log" 2>&1 ;;
    file:*) F="${S#file:}"; N="$(basename "$F" .dart)-$(date +%H%M%S)"
      case "$F" in test/*.dart) ;; *) echo "refused $F"; continue;; esac
      (cd "$REPO" && "${CLEAN[@]}" flutter test --no-pub --concurrency 1 "$F") > "$OUT/$N.log" 2>&1; echo "$F exit=$? log=$N.log"; continue ;;
    sims-verification) (cd "$REPO" && "${CLEAN[@]}" flutter test --no-pub test/tool/sims/sims_verification_test.dart) > "$OUT/$S.log" 2>&1 ;;
    *) echo "unknown step $S"; continue ;;
  esac
  echo "$S exit=$?"
done
