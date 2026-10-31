#!/bin/bash
# Read-only: print sha256 of each given file (Mac host).
#   host-run bash docker-ws/sha256_file.sh <file>...
for f in "$@"; do shasum -a 256 "$f"; done
exit 0
