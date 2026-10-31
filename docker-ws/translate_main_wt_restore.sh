#!/bin/bash
# Restore one build-modified tracked path in build/wt-translate-main to its committed state.
#   host-run bash docker-ws/translate_main_wt_restore.sh <path>
cd /Volumes/CrucialX9/flutter_app/build/wt-translate-main && git checkout -- "${1:?path}" && git status --porcelain | head
