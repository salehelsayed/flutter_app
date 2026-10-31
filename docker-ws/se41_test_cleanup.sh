#!/bin/bash
# Remove the finished SE-41 test-variant workspace (rsync copy, test keys, server files). Refuses if the server runs.
set -u
ROOT=/Volumes/CrucialX9/se41_test
[ -d "$ROOT" ] || { echo "nothing to remove"; exit 0; }
/usr/sbin/lsof -nP -iTCP:8443 -sTCP:LISTEN >/dev/null 2>&1 && { echo "refused: something listens on 8443"; exit 2; }
KB=$(du -sk "$ROOT" | cut -f1)
rm -rf -- "$ROOT" && echo "removed $ROOT ($KB KB)"
