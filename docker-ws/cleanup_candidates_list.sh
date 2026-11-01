#!/bin/bash
# Read-only: sizes and ages of flutter_app's own cleanup candidates (DerivedData folders, evidence folders, test APKs,
# own build worktree), plus any symlink from tool dirs that points into them. Deletes nothing.
#   host-run bash docker-ws/cleanup_candidates_list.sh
R=/Volumes/CrucialX9/flutter_app
echo "== disk"; df -h / /Volumes/CrucialX9 | awk 'NR==1||/\//{print $4" free of "$2" on "$NF}'
echo "== DerivedData (home)"; for d in "$HOME"/tmp-dd-*; do echo "$(du -sh "$d" 2>/dev/null | cut -f1) $(stat -f %Sm -t %m-%dT%H:%M "$d") $(basename "$d")"; done
echo "== evidence folders (top 25 by size)"; du -sm "$R"/.codex-test-logs/* 2>/dev/null | sort -rn | head -25 | awk '{printf "%sMB %s\n",$1,$2}' | sed "s#$R/##"
echo "== test APKs in evidence"; find "$R/.codex-test-logs" -name '*.apk' -size +50M 2>/dev/null | while read f; do echo "$(du -sh "$f" | cut -f1) ${f#$R/}"; done
echo "== own worktrees"; for w in "$R"/build/wt-astra-p0; do [ -d "$w" ] && echo "$(du -sh "$w" | cut -f1) ${w#$R/}"; done
echo "== symlinks into candidates"; for s in "$HOME/development" "$HOME/.gradle" "$HOME/Library/Developer" "$HOME/Library/Android" "$HOME/Library/Caches" "$HOME/.cache" "$HOME/go"; do
  [ -d "$s" ] && find "$s" -maxdepth 4 -type l 2>/dev/null | while read l; do t=$(readlink "$l"); case "$t" in *tmp-dd-*|*.codex-test-logs*|*wt-astra-p0*) echo "LINK $l -> $t";; esac; done
done; echo "symlink scan done"
