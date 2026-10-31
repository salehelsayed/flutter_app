#!/bin/bash
# Copy one macOS temp evidence directory (/var/folders/...group_multi_party_*) into a run folder under build/kayan-safe/.
#   host-run bash docker-ws/copy_tmp_evidence.sh <tmp dir> <dest under build/kayan-safe/>
SRC="${1:?src}"; REPO="$(cd "$(dirname "$0")/.." && pwd)"; DEST="$REPO/${2:?dest}"
case "$SRC" in /var/folders/*/T/group_multi_party_*) ;; *) echo refused; exit 2;; esac
case "$2" in build/kayan-safe/*) ;; *) echo refused; exit 2;; esac
mkdir -p "$DEST" && cp -Rp "$SRC" "$DEST/" && du -sh "$DEST/$(basename "$SRC")"
