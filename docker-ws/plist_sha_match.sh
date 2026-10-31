#!/bin/bash
# Compare the sha256 of the iOS Firebase plist in a worktree with the main checkout's copy. Prints only match=yes/no.
#   host-run bash docker-ws/plist_sha_match.sh <worktree>
M=/Volumes/CrucialX9/flutter_app/ios/Runner/GoogleService-Info.plist; T="${1:?worktree}/ios/Runner/GoogleService-Info.plist"
[ -f "$T" ] || { echo "match=missing"; exit 1; }
[ "$(shasum -a 256 < "$M")" = "$(shasum -a 256 < "$T")" ] && echo "match=yes" || { echo "match=no"; exit 1; }
