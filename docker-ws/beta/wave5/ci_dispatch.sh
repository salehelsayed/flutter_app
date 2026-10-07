#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"; cd /Volumes/CrucialX9/flutter_app || exit 1
gh workflow run mknoon-checks.yml --ref main -f mode=change -f baseline=2e5a9d72049bbb91db466259d148e047792ac865 2>&1 | tail -2
sleep 8
gh run list --workflow mknoon-checks.yml --limit 1 --json databaseId,status,headSha,event --jq '.[0] | (.databaseId|tostring)+" "+.status+" "+.event+" "+.headSha[0:9]'
