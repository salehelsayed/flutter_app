#!/bin/bash
# Read-only: the SIMS_RESULT_JSON status/detail (or last test-summary line) of worktree sims capability logs.
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/logs
for c in "$@"; do
  f="$d/$c.log"
  r=$(grep -o 'SIMS_RESULT_JSON={"status":"[A-Z/ ]*"' "$f" 2>/dev/null | tail -1)
  det=$(grep -o '"detail":"[^"]*' "$f" 2>/dev/null | tail -1 | cut -c1-160)
  sum=$(grep -E "All tests passed|Some tests failed|[0-9]+ passed|FAIL:|PASS:" "$f" 2>/dev/null | tail -1 | cut -c1-160)
  echo "$c | ${r:-no-result-json} | ${det} | ${sum}"
done
