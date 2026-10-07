#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh pr view "$1" --json title,body,headRefName,headRefOid,baseRefName,commits,files --jq '.title, .body, .headRefName, .headRefOid, (.files[]|.path+" +"+(.additions|tostring)+" -"+(.deletions|tostring)), (.commits[]|.oid[0:9]+" "+.messageHeadline)'
echo "=== DIFF"; gh pr diff "$1"
