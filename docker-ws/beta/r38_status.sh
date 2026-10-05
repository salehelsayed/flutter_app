#!/bin/bash
# Progress of r38_archive_and_remove.sh.
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "=== out tail"; tail -5 docker-ws/beta/r38_archive_and_remove.out
echo "=== procs"; ps -axo pid,etime,command | grep -E "r38_archive|tar czf|git (worktree|diff|status|ls-files)|rm -rf" | grep -v grep | cut -c1-200
echo "=== archive"; ls artifacts/worktree-archive-20261001 2>/dev/null | wc -l
echo "=== summary"; f=docker-ws/beta/r38_archive_and_remove.out
grep -vE '^(ARCHIVED|REMOVED) ' $f
echo "archived=$(grep -c '^ARCHIVED' $f) removed=$(grep -c '^REMOVED' $f)"
grep '^ARCHIVED' $f | awk '{print $3, $5}' | grep -v 'skipped=0' | head
du -sh artifacts/worktree-archive-20261001/* | sort -h | tail -4
for d in /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp /Volumes/CrucialX9/mknoon-worktrees /Volumes/CrucialX9/mknoon-test-runner-z2tuurrn; do [ -d "$d" ] && echo "leftover parent $d $(du -sh "$d" | cut -f1) entries=$(ls -A "$d" | wc -l)"; done
df -h /Volumes/CrucialX9 / | tail -2
