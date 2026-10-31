#!/bin/bash
# Copy one read-only file from the Astra worktree into build/kayan-safe/astra/ so the container can read it.
#   host-run bash docker-ws/fetch_astra_doc.sh <absolute path under /Volumes/CrucialX9/flutter_app-astra-cd/>
SRC="${1:?src}"
case "$SRC" in /Volumes/CrucialX9/flutter_app-astra-cd/*) ;; *) echo "refused"; exit 2;; esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"; mkdir -p "$REPO/build/kayan-safe/astra"
cp "$SRC" "$REPO/build/kayan-safe/astra/" && shasum -a 256 "$REPO/build/kayan-safe/astra/$(basename "$SRC")"
