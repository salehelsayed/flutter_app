#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr merge 5 --merge --subject "Merge PR #5: close a relay outage that the node heals by itself" 2>&1 | tail -3
gh pr view 5 --json state,mergedAt,mergeCommit --jq '.state+" "+.mergedAt+" "+.mergeCommit.oid[0:9]'
git fetch -q origin main
git branch -f main origin/main && echo "local main -> $(git rev-parse --short main)"
git log --oneline -3 origin/main
