#!/bin/bash
# Read-only probe for the credential history purge. Changes nothing.
# Run: /claude-host-bin/host-run bash docker-ws/purge_probe.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
echo "== tooling =="
for t in git-filter-repo bfg python3 git; do
  printf '  %-16s ' "$t"; command -v "$t" >/dev/null && "$t" --version 2>&1 | head -1 || echo "MISSING"
done
printf '  %-16s ' "filter-repo(py)"; python3 -c "import git_filter_repo; print('importable')" 2>/dev/null || echo "MISSING"
echo "== repo size / refs =="
echo "  .git: $(du -sh .git | cut -f1)"
echo "  local branches:  $(git branch | wc -l | tr -d ' ')"
echo "  remote branches: $(git branch -r | grep -vc HEAD)"
echo "  tags:            $(git tag | wc -l | tr -d ' ')"
echo "== commits touching the three credential paths (all refs) =="
git rev-list --all --objects -- APPLE/AuthKey_M7T46H43B2.p8 APPLE/AuthKey_GF735BCHFM.p8 APPLE/upload-keystore.jks 2>/dev/null | wc -l | sed 's/^/  objects+commits: /'
for f in APPLE/AuthKey_M7T46H43B2.p8 APPLE/AuthKey_GF735BCHFM.p8 APPLE/upload-keystore.jks; do
  printf '  %-34s commits=%s\n' "$(basename "$f")" "$(git log --all --oneline --follow -- "$f" 2>/dev/null | wc -l | tr -d ' ')"
done
echo "== distinct blob SHAs to eliminate =="
for f in APPLE/AuthKey_M7T46H43B2.p8 APPLE/AuthKey_GF735BCHFM.p8 APPLE/upload-keystore.jks; do
  git rev-list --all -- "$f" 2>/dev/null | while read -r c; do git rev-parse "$c:$f" 2>/dev/null; done | sort -u | sed "s|^|  $(basename "$f") |"
done
echo "== host free space =="
df -h "$HOME" | tail -1
