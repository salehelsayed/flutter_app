#!/bin/bash
# Read-only: list the files that block fast-forwarding the main checkout to <target> (local edits or untracked
# files that the target changes or adds).   host-run bash docker-ws/main_ff_blockers.sh <target>
T=${1:?target}; M=/Volumes/CrucialX9/flutter_app; cd "$M" || exit 2
CH=$(mktemp); git diff --name-only HEAD "$T" > "$CH"
echo "files changed HEAD..target: $(wc -l < "$CH" | tr -d ' ')"
echo "== locally modified AND changed upstream"; git diff --name-only | grep -F -x -f "$CH"
echo "== untracked locally AND added upstream"; git ls-files -o --exclude-standard | grep -F -x -f "$CH"
rm -f "$CH"
