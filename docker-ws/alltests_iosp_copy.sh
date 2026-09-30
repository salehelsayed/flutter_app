#!/bin/bash
# Read-only on the worktree: list capture folder and copy non-private files into docker-ws/.run_handover_copy/iosp/
src="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/build/sims/proofs/notifications.ios_payload_fast_path/capture-1790424625561574-62035"
dst="/Volumes/CrucialX9/flutter_app/docker-ws/.run_handover_copy/iosp"
mkdir -p "$dst"
cd "$src" || exit 1
find . -type f | while read -r f; do
  case "$f" in (*run-env*|*private*|*secret*|*.p8|*credential*) echo "SKIP $f"; continue;; esac
  sz=$(stat -f %z "$f"); echo "$sz $f"
  if [ "$sz" -lt 60000000 ]; then mkdir -p "$dst/$(dirname "$f")"; cp "$f" "$dst/$f"; fi
done
