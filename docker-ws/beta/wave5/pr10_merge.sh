#!/bin/bash
# User-approved 2026-10-07: rebase-merge PR 10 on GitHub, then bring local main and
# wave3-baseline-20260930 (checked out here) to the new origin/main and push the baseline.
export PATH="/opt/homebrew/bin:$PATH"
set -u
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr merge 10 --rebase 2>&1 | tail -3
gh pr view 10 --json state,mergedAt --jq '.state+" "+.mergedAt'
git fetch -q origin main
git log --oneline -3 origin/main
git merge --ff-only origin/main | tail -1
git branch -f main origin/main && echo "local main -> $(git rev-parse --short main)"
git push origin wave3-baseline-20260930 2>&1 | tail -1
git ls-remote origin refs/heads/main refs/heads/wave3-baseline-20260930
