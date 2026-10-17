#!/bin/bash
# Copy one file from a Codex worktree into this repo's build/ (git-ignored), so
# the container can read it. Only sources under /Volumes/CrucialX9/flutter_app_codex_* are allowed.
#   host-run bash docker-ws/fetch_codex_artifact.sh <absolute source file> <name under build/codex_artifacts/>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/docker-ws/_host_paths.sh"
SRC="$(mknoon_real_path "${1:?source}")"; NAME="${2:?name}"
case "$SRC" in /Volumes/CrucialX9/flutter_app_codex_*) ;; *) echo "refused source"; exit 2 ;; esac
case "$NAME" in .|*/*|..*) echo "refused name"; exit 2 ;; esac
[ -f "$SRC" ] || { echo "source is not a file"; exit 2; }
DST="$REPO/build/codex_artifacts"
mknoon_require_output "$REPO" "$DST/$NAME" || exit 2
mkdir -p "$DST"; cp "$SRC" "$DST/$NAME"; shasum -a 256 "$DST/$NAME"
