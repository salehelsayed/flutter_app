#!/bin/bash
# Read-only: newest 8 files in the project root and ~/Downloads (name, size, mtime).
#   host-run bash docker-ws/find_owner_apk.sh
for d in /Volumes/CrucialX9/flutter_app "$HOME/Downloads"; do echo "== $d"; ls -lt "$d" 2>&1 | grep -v "^d" | head -8; done
