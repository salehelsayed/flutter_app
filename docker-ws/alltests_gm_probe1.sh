#!/bin/bash
# Read-only probe of the newest groups.media_send_reliability_ios capture. Bounded output.
W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
P=$W/build/sims/proofs/groups.media_send_reliability_ios
echo "=== proofs dir (newest 8)"; ls -lt "$P" | head -9
d=$(ls -td "$P"/ios-p269-* | head -1); echo "=== newest: $d"
ls -laT "$d" 2>/dev/null | awk '{print $1,$5,$6,$7,$8,$10}' | head -40
echo "=== xcresult tree"; find "$d/p269-ios.xcresult" -maxdepth 3 -exec ls -ldT {} \; 2>/dev/null | awk '{print $5,$6,$7,$8,$10}' | head -20
echo "=== small logs (not run-env/private)"
for f in "$d"/*.log "$d"/*.json; do b=${f##*/}; case "$b" in run-env*|*private*|auto_setup.json) continue;; esac; [ -f "$f" ] || continue; echo "--- $b ($(wc -c <"$f") bytes)"; tail -n 8 "$f" | cut -c1-200; done
echo "=== parent of proofs: other files"; ls -lt "$P" | awk '$1 !~ /^d/' | head
echo "=== tmp root"; ls -lt /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp 2>/dev/null | head -15
