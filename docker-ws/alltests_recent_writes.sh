#!/bin/bash
# Read-only: files written in the last N minutes under the worktree build dir and the run tmp dir.
m="${1:-10}"
for d in /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-tmp; do
  echo "== $d"
  find "$d" -type f -mmin -"$m" 2>/dev/null | grep -v -E '/(DerivedData|intermediates|\.dart_tool)/' | head -8
done
