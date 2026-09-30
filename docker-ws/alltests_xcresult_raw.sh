#!/bin/bash
# Read-only: raw xcresulttool summary (bounded) for one worktree proofs xcresult, plus sibling log tails.
d="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/$1"
xcrun xcresulttool get test-results summary --path "$d" 2>&1 | head -c 1500; echo
ls -la "$(dirname "$d")" | awk '{print $5,$9}' | head -15
