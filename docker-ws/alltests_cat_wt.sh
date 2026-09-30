#!/bin/bash
# Read-only: cat (bounded) a file under the worktree build/sims/proofs.
head -c "${2:-3000}" "/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/$1"
