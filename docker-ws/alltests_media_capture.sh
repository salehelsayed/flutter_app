#!/bin/bash
# Read-only: list the newest iOS group media capture and tail its log files.
d=$(ls -td /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/groups.media_send_reliability_ios/ios-p269-* | head -1)
ls -la "$d" | awk '{print $5,$9}' | sed -n 15,60p
for f in $(ls -t "$d"/*.log 2>/dev/null | head -4); do echo "== ${f##*/}"; tail -n 12 "$f" | cut -c1-220; done
