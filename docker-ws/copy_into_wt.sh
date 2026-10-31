#!/bin/bash
# Copy the listed repo files from the main checkout into build/<tree> (same relative paths), then dart format them there.
#   host-run bash docker-ws/copy_into_wt.sh <tree under build/> <file>...
M=/Volumes/CrucialX9/flutter_app; T=$M/build/${1:?tree}; shift
SDK="$HOME/development/flutter-3.47.2"
for f in "$@"; do cp "$M/$f" "$T/$f" || exit 3; done
cd "$T" && "$SDK/bin/dart" format "$@" | tail -2
for f in "$@"; do cmp -s "$M/$f" "$T/$f" || { echo "formatted differs: $f"; cp "$T/$f" "$M/$f"; }; done
