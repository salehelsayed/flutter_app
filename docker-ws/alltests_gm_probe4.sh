#!/bin/bash
# Read-only: earlier captures' XCTest stdout + session log tails; newest session log tail; sims run logs.
W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
P=$W/build/sims/proofs/groups.media_send_reliability_ios
for d in $(ls -td "$P"/ios-p269-*); do echo "##### ${d##*/}"
  find "$d/p269-ios.xcresult" -name 'StandardOutputAndStandardError*.txt' -print0 2>/dev/null | while IFS= read -r -d '' f; do LC_ALL=C grep -a -E 'MKNOON_269|t = |error:|failed \(|Executed' "$f" | head -14 | LC_ALL=C cut -c1-260; done
done
echo "##### newest session log: last 12 lines"
d=$(ls -td "$P"/ios-p269-* | head -1)
find "$d/p269-ios.xcresult" -name 'Session-*.log' -print0 | while IFS= read -r -d '' f; do tail -n 12 "$f" | LC_ALL=C cut -c1-200; done
echo "##### sims logs mentioning the row (newest 6)"
ls -t $(LC_ALL=C grep -rl --include='*.log' --include='*.jsonl' --include='*.json' 'groups.media_send_reliability_ios' "$W/build/sims" 2>/dev/null | grep -v '/proofs/' | head -40) 2>/dev/null | head -6
