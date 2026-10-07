#!/bin/bash
# Read-only GitHub PR lookup on the Mac (gh is authenticated there).
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd /Volumes/CrucialX9/flutter_app || exit 1
which gh || { echo "no gh"; exit 1; }
gh pr list --head "$1" --state all --json number,title,state,author,createdAt,baseRefName,additions,deletions,changedFiles,url
