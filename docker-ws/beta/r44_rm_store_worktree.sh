#!/bin/bash
# Remove the 1.0.1 (121) store snapshot worktree after checking the build outputs and source record are saved.
MAIN=/Volumes/CrucialX9/flutter_app
WT=/Volumes/CrucialX9/flutter_app-store-20261001
REC=$MAIN/artifacts/store-build-20261001
cd "$MAIN" || exit 1
for f in mknoon-1.0.1-121.aab mknoon-1.0.1-121.ipa artifacts.sha256 snapshot-tracked.patch snapshot-untracked.tgz provenance.txt; do
  [ -s "$REC/$f" ] || { echo "MISSING $REC/$f, not removing"; exit 2; }
done
(cd "$REC" && shasum -a 256 -c artifacts.sha256) || { echo "checksum mismatch, not removing"; exit 2; }
echo "files changed since the snapshot record:"
git -C "$WT" diff --binary HEAD > /tmp/r44.patch
git -C "$WT" diff --stat HEAD | tail -1
cmp -s /tmp/r44.patch "$REC/snapshot-tracked.patch" && echo "patch identical" || { echo "patch differs in:"; diff <(grep '^diff --git' "$REC/snapshot-tracked.patch") <(grep '^diff --git' /tmp/r44.patch); }
du -sh "$WT" | cut -f1
git worktree remove --force --force "$WT" && echo "REMOVED $WT"
git worktree prune; git worktree list
df -h /Volumes/CrucialX9 | tail -1
