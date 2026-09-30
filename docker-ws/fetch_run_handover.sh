#!/bin/bash
# Copy named non-private files from the all-tests run root into an ignored scratch folder in docker-ws.
# Usage: fetch_run_handover.sh <relpath>...   (private env/credential files are refused)
src="/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run"
dst="/Volumes/CrucialX9/flutter_app/docker-ws/.run_handover_copy"
mkdir -p "$dst"
for rel in "$@"; do
  case "$rel" in (*run-env*|*private*|*secret*|*.p8|*credential*) echo "REFUSED $rel"; continue;; esac
  if [ -d "$src/$rel" ]; then ls -la "$src/$rel" > "$dst/$(echo "$rel" | tr / _).listing.txt"; echo "LISTED $rel";
  elif [ -f "$src/$rel" ]; then mkdir -p "$dst/$(dirname "$rel")"; cp "$src/$rel" "$dst/$rel"; echo "COPIED $rel";
  else echo "MISSING $rel"; fi
done
