#!/bin/bash
set -uo pipefail
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "HEAD $(git rev-parse --short HEAD) branch $(git rev-parse --abbrev-ref HEAD)"
for attempt in 1 2 3; do
  echo "=== attempt $attempt ==="
  out=$(git push -u origin feat/audio-prd-implementation 2>&1)
  status=$?
  echo "$out"
  echo "EXIT=$status"
  if [ $status -eq 0 ]; then
    break
  fi
  sleep 5
done
echo "=== final ==="
git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>&1
git log --oneline -1 origin/feat/audio-prd-implementation 2>&1
