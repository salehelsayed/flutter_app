#!/bin/bash
# Restore the given tracked files in build/wt-translate-129 to its HEAD (drops my copied-in test edits).
#   host-run bash docker-ws/wt129_reset_files.sh <file>...
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-129 || exit 2
git checkout -- "$@" && git status --porcelain --untracked-files=no | head
