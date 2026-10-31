#!/bin/bash
# Read-only: sha256 of google-services.json files in sibling worktrees (no contents printed).
for f in /Volumes/CrucialX9/flutter_app*/android/app/google-services.json /Volumes/CrucialX9/flutter_app*/android/app/src/*/google-services.json; do
  [ -f "$f" ] && echo "$(shasum -a 256 "$f" | cut -c1-16) $f"
done
