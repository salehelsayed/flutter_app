#!/bin/bash
# Make (or move) a detached build worktree build/wt-astra-p0 at <sha> and run pub get there (pinned SDK).
#   host-run bash docker-ws/wt_astra_base_setup.sh <sha>
S=${1:?sha}; M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-astra-p0
SDK="$HOME/development/flutter-3.47.2"
cd "$M" || exit 2
if [ -d "$W" ]; then git -C "$W" checkout -q --detach "$S"; else git worktree add -q --detach "$W" "$S"; fi
echo "head=$(git -C "$W" rev-parse --short HEAD)"
cp -n "$M/.env" "$W/.env" 2>/dev/null
cd "$W" && "$SDK/bin/flutter" pub get > /dev/null 2>&1; echo "pubget=$?"
