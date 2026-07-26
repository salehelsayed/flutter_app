#!/bin/bash
# Rerun ONLY the strict analyzer gate, persisting its output into docker-ws so
# Claude can read it from the sandbox.
# Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/rerun_analyzer_baseline.sh

set -u
set -o pipefail

cd "$(dirname "$0")/.." || exit 2
OUT=docker-ws/analyzer_strict_result.txt
TMP="$(mktemp "${TMPDIR:-/tmp}/analyzer-strict-result.XXXXXX")" || exit 2
trap 'if [[ -n "$TMP" ]]; then rm -f "$TMP"; fi' EXIT

./scripts/check_flutter_analyze_strict.sh >"$TMP" 2>&1
strict_status=$?
printf 'exit=%s\n' "$strict_status" >>"$TMP"

if ! mv -f "$TMP" "$OUT"; then
  echo "Unable to persist strict analyzer output: $OUT" >&2
  exit 2
fi
TMP=

tail -20 "$OUT" || true
exit "$strict_status"
