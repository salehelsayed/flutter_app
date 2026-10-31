#!/bin/bash
# Copy git-ignored build inputs (Firebase plists, macOS GoMknoon framework, Android GoMknoon aar) from the main checkout into a worktree. No overwrite. Names only.
#   host-run bash docker-ws/stage_wt_ignored.sh <worktree>
M=/Volumes/CrucialX9/flutter_app; W="$1"; [ -d "$W" ] || { echo "no worktree"; exit 2; }
for p in ios/Runner/GoogleService-Info.plist macos/Runner/GoogleService-Info.plist android/app/google-services.json \
         android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/app/libs/GoMknoon.inputs.sha256; do
  if [ -e "$M/$p" ] && [ ! -e "$W/$p" ]; then mkdir -p "$(dirname "$W/$p")"; cp -a "$M/$p" "$W/$p" && echo "staged $p"; elif [ -e "$W/$p" ]; then echo "present $p"; else echo "absent-in-main $p"; fi
done
bash "$(dirname "$0")/stage_macos_gomknoon.sh" "$W"
# iOS gomobile frameworks (git-ignored): copy from the given source tree (default: the UI-Update worktree).
SRC="${2:-/Volumes/CrucialX9/flutter_app-ui-update}"
for f in ios/Runner/GoMknoon.xcframework ios/Runner/GoMknoonNSE.xcframework; do
  if [ -e "$SRC/$f" ] && [ ! -e "$W/$f" ]; then cp -a "$SRC/$f" "$W/$f" && echo "staged $f"; elif [ -e "$W/$f" ]; then echo "present $f"; else echo "absent-in-source $f"; fi
done
