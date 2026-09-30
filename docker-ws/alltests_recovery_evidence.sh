#!/bin/bash
# Read-only: newest notifications.android_recovery_completion capture: failure + timeout evidence summary.
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.android_recovery_completion/capture-* | head -1)
echo "dir=$d"; ls -la "$d" | awk "{print \$5, \$9}" | tail -40
for f in "$d"/*failure*.json; do echo "== $f"; head -c 1500 "$f"; echo; done
for f in "$d"/*jobscheduler-resume.log; do echo "== $f"; sort "$f" | uniq -c | head -20; done
f=$(ls "$d"/*timeout-jobscheduler.txt 2>/dev/null | head -1); [ -n "$f" ] && { echo "== $f"; grep -nE "JOB #|androidx.work|Satisf|Unsatisf|Ready|Pending|Running|active|Required" "$f" | head -60; }
f=$(ls "$d"/*timeout-runtime.jsonl 2>/dev/null | head -1); [ -n "$f" ] && { echo "== $f lines=$(wc -l < "$f")"; tail -c 3000 "$f"; }
