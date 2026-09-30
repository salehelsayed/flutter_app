#!/bin/bash
# Read-only: find recent files mentioning ios_payload_fast_path / capture id in run root and worktree build/sims (names only).
for root in /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims; do
  echo "== $root"
  find "$root" -type f -newermt "2026-09-26 14:05" ! -newermt "2026-09-26 14:40" 2>/dev/null | grep -v -E 'run-env|private|secret|\.p8|credential' | head -60
done
echo "== capture dir tree"
ls -la /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/ | tail -8
ls -laR /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/capture-1790424625561574-62035 | head -40
