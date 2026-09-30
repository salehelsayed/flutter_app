#!/bin/bash
# Read-only on sources: list or copy non-private files from run root (R:) or worktree (W:) into docker-ws/.and_copy/
# Usage: alltests_and_copy.sh ls|cp <R:relpath|W:relpath>...
R=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run; W=/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree
dst=/Volumes/CrucialX9/flutter_app/docker-ws/.and_copy; mkdir -p "$dst"
mode=$1; shift
for a in "$@"; do
  case "$a" in (*run-env*|*private*|*secret*|*.p8|*credential*) echo "REFUSED $a"; continue;; esac
  case "$a" in (R:*) p="$R/${a#R:}"; tag=R;; (W:*) p="$W/${a#W:}"; tag=W;; (*) echo bad; continue;; esac
  if [ "$mode" = ls ]; then find "$p" -maxdepth 2 2>/dev/null | head -80 | while read f; do ls -ld "$f" | awk '{print $5, $6, $7, $8, $9}'; done
  else rel="${a#?:}"; mkdir -p "$dst/$tag/$(dirname "$rel")"; cp -R "$p" "$dst/$tag/$rel" && echo "COPIED $a"; find "$dst/$tag/$rel" \( -name '*run-env*' -o -name '*private*' \) -exec rm -rf {} +; fi
done
