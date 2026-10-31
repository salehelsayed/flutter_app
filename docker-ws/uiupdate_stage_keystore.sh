#!/bin/bash
# Stage (or remove) the git-ignored release keystore in the UI-Update worktree. Prints names/sizes only.
#   host-run bash docker-ws/uiupdate_stage_keystore.sh stage|remove|check
SRC=/Volumes/CrucialX9/flutter_app/android/app/upload-keystore.jks
DST=/Volumes/CrucialX9/flutter_app-ui-update/android/app/upload-keystore.jks
case "$1" in
  check) ls -la "$SRC" "$DST" 2>&1 | awk '{print $5, $NF}'
         grep -c storeFile /Volumes/CrucialX9/flutter_app-ui-update/android/key.properties
         cmp -s /Volumes/CrucialX9/flutter_app/android/key.properties /Volumes/CrucialX9/flutter_app-ui-update/android/key.properties && echo key.properties-same || echo key.properties-differs ;;
  stage) [ -e "$DST" ] && { echo "already present"; exit 0; }; cp "$SRC" "$DST" && echo staged ;;
  remove) [ -e "$DST" ] && cmp -s "$SRC" "$DST" && rm "$DST" && echo removed ;;
esac
