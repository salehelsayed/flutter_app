#!/bin/bash
# Tail one SE-41 log; the name cannot escape the test log directory.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO/docker-ws/_host_paths.sh"
NAME="${1:?log name}"; LINES="${2:-40}"
case "$NAME" in .|*/*|..*) echo 'refused log name'; exit 2 ;; esac
[[ "$LINES" =~ ^[0-9]+$ ]] || { echo 'invalid line count'; exit 2; }
ROOT="$(mknoon_real_path /Volumes/CrucialX9/se41_test)"
FILE="$(mknoon_real_path "$ROOT/$NAME")"
case "$FILE" in "$ROOT/"*) ;; *) echo 'refused log path'; exit 2 ;; esac
tail -n "$LINES" "$FILE"
