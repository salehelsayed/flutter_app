#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr view 5 --json mergeable,mergeStateStatus,baseRefName,headRefOid,statusCheckRollup --jq '.mergeable, .mergeStateStatus, .baseRefName, .headRefOid, (.statusCheckRollup|length)'
git fetch -q origin main fix/relay-outage-self-healed-recovered
git merge-tree --write-tree origin/main origin/fix/relay-outage-self-healed-recovered >/dev/null && echo "merge-tree: clean" || echo "merge-tree: CONFLICT"
