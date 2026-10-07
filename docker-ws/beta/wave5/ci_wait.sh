#!/bin/bash
export PATH="/opt/homebrew/bin:$PATH"; cd /Volumes/CrucialX9/flutter_app || exit 1
for i in $(seq 1 50); do
  s=$(gh run view "$1" --json status --jq .status); [ "$s" = completed ] && break; sleep 10
done
gh run view "$1" --json conclusion,jobs --jq '"run: "+.conclusion, (.jobs[] | "  "+.name+": "+.status+" / "+(.conclusion//"")), (.jobs[] | select(.name=="metadata") | .steps[] | "    "+.name+": "+(.conclusion//""))'
