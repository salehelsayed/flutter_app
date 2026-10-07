#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
gh run view 37611674565 --log-failed 2>&1 | grep -vE "^\s*$" | tail -30 | cut -c1-220
echo "=== recent runs on main"
gh run list --branch main --limit 5 --json headSha,conclusion,createdAt,name --jq '.[] | .createdAt[0:16]+" "+.headSha[0:9]+" "+.name+" "+(.conclusion//"")'
