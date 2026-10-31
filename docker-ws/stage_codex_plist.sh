#!/bin/bash
# Copy the git-ignored GoogleService-Info.plist from a verified worktree into a target worktree (no overwrite) and print sha256 prefixes only.
#   host-run bash docker-ws/stage_codex_plist.sh <source-worktree> <target-worktree>
S="$1/ios/Runner/GoogleService-Info.plist"; D="$2/ios/Runner/GoogleService-Info.plist"
[ -f "$S" ] || { echo "no source"; exit 2; }
if [ -e "$D" ]; then echo "target exists"; else cp -p "$S" "$D" || exit 3; echo "copied"; fi
echo "src $(shasum -a 256 "$S" | cut -c1-12)"; echo "dst $(shasum -a 256 "$D" | cut -c1-12)"
git -C "$2" check-ignore -q ios/Runner/GoogleService-Info.plist && echo "git-ignored in target"
exit 0
