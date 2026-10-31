#!/bin/bash
# Copy the listed repo files (any type, no formatting) from the main checkout into build/<tree>.
#   host-run bash docker-ws/copy_plain_into_wt.sh <tree under build/> <file>...
M=/Volumes/CrucialX9/flutter_app; T=$M/build/${1:?tree}; shift
for f in "$@"; do cp "$M/$f" "$T/$f" && echo "copied $f"; done
