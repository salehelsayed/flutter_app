#!/bin/bash
# Inspect (default) or delete (arg "remove") the three leftover worktree parent folders.
DIRS="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp /Volumes/CrucialX9/mknoon-test-runner-z2tuurrn /Volumes/CrucialX9/mknoon-worktrees"
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "=== registered worktrees under them"; git worktree list | grep -E 'y227gs8x-tmp|z2tuurrn|mknoon-worktrees' || echo none
for d in $DIRS; do
  [ -d "$d" ] || { echo "absent $d"; continue; }
  echo "=== $d $(du -sh "$d" | cut -f1) newest=$(find "$d" -type f -print0 2>/dev/null | xargs -0 stat -f '%m' 2>/dev/null | sort -n | tail -1 | xargs -I{} date -r {} '+%Y-%m-%d %H:%M')"
  ls -A "$d" | head -8
  echo "git dirs: $(find "$d" -maxdepth 3 -name .git 2>/dev/null | wc -l | tr -d ' ')"
  echo "procs: $(ps -axo command= | grep -F "$d" | grep -v -e grep -e r39_rm | wc -l | tr -d ' ')"
done
if [ "$1" = remove ]; then
  A=/Volumes/CrucialX9/flutter_app/artifacts/worktree-archive-20261001/leftover-folders
  mkdir -p "$A"
  tar czf "$A/mknoon-worktrees.tgz" -C /Volumes/CrucialX9 mknoon-worktrees || { echo "FAIL tar 1"; exit 1; }
  tar czf "$A/all-tests-tmp-git-repos.tgz" -C /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp mknoon-checks-test-r3qhfmsp mknoon-checks-test-4sbxjpws || { echo "FAIL tar 2"; exit 1; }
  tar czf "$A/mknoon-test-runner-z2tuurrn-notes.tgz" -C /Volumes/CrucialX9 --exclude '*.xcresult' --exclude 'build' mknoon-test-runner-z2tuurrn || { echo "FAIL tar 3"; exit 1; }
  ls -la "$A"
  for d in $DIRS; do rm -rf "$d"; [ -d "$d" ] && echo "FAIL $d" || echo "DELETED $d"; done
  df -h /Volumes/CrucialX9 | tail -1
fi
echo "R39 DONE"
if [ "$1" = gits ]; then
  for g in $(find /Volumes/CrucialX9/mknoon-worktrees /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp -maxdepth 3 -name .git 2>/dev/null); do
    w=$(dirname "$g")
    if [ -f "$g" ]; then t=$(sed 's/gitdir: //' "$g"); [ -d "$t" ] && s=live || s=dangling; echo "FILE $s $w -> $t files=$(ls -A "$w" | wc -l | tr -d ' ')"
    else echo "REPO $w head=$(git -C "$w" log -1 --format='%h %cd %s' --date=short 2>&1 | cut -c1-80) remotes=$(git -C "$w" remote | tr '\n' ,) dirty=$(git -C "$w" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
      h=$(git -C "$w" rev-parse HEAD 2>/dev/null); git -C /Volumes/CrucialX9/flutter_app cat-file -e "$h^{commit}" 2>/dev/null && echo "   head in main repo: yes" || echo "   head in main repo: NO"
    fi
  done
fi
