#!/bin/bash
# Read-only: newest keepalive warm-readiness evidence in the worktree proofs.
d=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/android.keepalive_drop_skip_direct
f=$(find "$d" -name 'keepalive-warm-readiness*.json' 2>/dev/null | xargs ls -t 2>/dev/null | head -1); echo "file=$f"; head -c 1500 "$f"; echo
ls -t "$d" | head -5
