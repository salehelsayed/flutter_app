#!/bin/bash
# Copy one file from a Codex worktree's .codex-test-logs into build/kayan-safe/codex/ (read-only source).
#   host-run bash docker-ws/fetch_codex_file.sh <absolute path under /Volumes/CrucialX9/flutter_app_codex_*/.codex-test-logs/>
SRC="${1:?src}"
case "$SRC" in /Volumes/CrucialX9/flutter_app_codex_*/.codex-test-logs/*) ;; *) echo "refused"; exit 2;; esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"; mkdir -p "$REPO/build/kayan-safe/codex"
cp "$SRC" "$REPO/build/kayan-safe/codex/" && wc -c "$REPO/build/kayan-safe/codex/$(basename "$SRC")"
