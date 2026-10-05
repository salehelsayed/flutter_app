#!/bin/bash
# Delete mknoon-worktrees: some evidence folders are read-only, so make them writable first.
d=/Volumes/CrucialX9/mknoon-worktrees
tar tzf /Volumes/CrucialX9/flutter_app/artifacts/worktree-archive-20261001/leftover-folders/mknoon-worktrees.tgz | grep -c 'diagnostics-deploy-deadlines-20260920/.linux-compatibility/evidence/'
chmod -R u+w "$d" && rm -rf "$d"
[ -d "$d" ] && echo "STILL THERE" || echo "DELETED $d"
df -h /Volumes/CrucialX9 | tail -1
