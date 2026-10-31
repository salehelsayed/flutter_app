#!/bin/bash
# Copy an Astra kayan-safe packet directory (read-only source) into build/kayan-safe/astra/<name>/.
#   host-run bash docker-ws/fetch_astra_packet.sh /Volumes/CrucialX9/flutter_app-astra-*/build/kayan-safe/<name>
SRC="${1:?src}"
case "$SRC" in /Volumes/CrucialX9/flutter_app-astra-*/build/kayan-safe/*) ;; *) echo refused; exit 2;; esac
REPO="$(cd "$(dirname "$0")/.." && pwd)"; DEST="$REPO/build/kayan-safe/astra"; mkdir -p "$DEST"
rm -rf "$DEST/$(basename "$SRC")"; cp -Rp "$SRC" "$DEST/" && ls -laR "$DEST/$(basename "$SRC")" | head -60
