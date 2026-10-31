#!/bin/bash
# Copy a Codex kayan-safe packet directory (read-only source) into build/kayan-safe/codex/<name>/ and print sha256 of each file.
#   host-run bash docker-ws/fetch_codex_packet.sh /Volumes/CrucialX9/flutter_app_codex_*/build/kayan-safe/<name>
SRC="${1:?src}"
case "$SRC" in /Volumes/CrucialX9/flutter_app_codex_*/build/kayan-safe/*) ;; *) echo refused; exit 2;; esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"; DEST="$REPO/build/kayan-safe/codex"; mkdir -p "$DEST"
rm -rf "$DEST/$(basename "$SRC")"; cp -Rp "$SRC" "$DEST/" || exit 1
cd "$DEST/$(basename "$SRC")" && for f in $(ls -A); do [ -f "$f" ] && shasum -a 256 "$f"; done
