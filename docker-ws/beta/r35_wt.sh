#!/bin/bash
# Fix-worktree helper (2026-10-01 follow-up). Usage:
#   r35_wt.sh status                 branch, dirty count, files modified in the last 90 minutes
#   r35_wt.sh cat <path> [from] [to] numbered lines of a worktree file
#   r35_wt.sh grep <regex> <path...> grep -rnE in worktree files/dirs
#   r35_wt.sh apply <edits.json>     apply exact-string edits [{file, old, new}] (each old must match exactly once);
#                                    {file, new, create: true} creates a file
#   r35_wt.sh diff <path>            git diff of one file
#   r35_wt.sh run <cmd...>           run a command in the worktree with Flutter 3.47.2 on PATH
W=/Volumes/CrucialX9/flutter_app-r2-fixes-20261001
cd "$W" || exit 1
case "$1" in
  status) echo "branch $(git rev-parse --abbrev-ref HEAD) head $(git rev-parse --short HEAD) dirty $(git status --porcelain | wc -l | tr -d ' ')"
          find lib ios/Runner test android/app/src go-mknoon -type f -newermt '-90 minutes' 2>/dev/null | head; date ;;
  cat) n=$(wc -l < "$2"); a=${3:-1}; b=${4:-$n}; awk -v a="$a" -v b="$b" 'NR>=a && NR<=b {printf "%5d  %s\n", NR, $0}' "$2" ;;
  grep) re=$2; shift 2; grep -rnE "$re" "$@" 2>/dev/null | cut -c1-240 | head -80 ;;
  diff) git diff -- "$2" ;;
  run) shift; . /Volumes/CrucialX9/flutter_app/docker-ws/_flutter_sdk_env.sh; "$@" ;;
  apply) /usr/bin/python3 - "$2" <<'PY'
import json, sys
edits = json.load(open(sys.argv[1]))
for e in edits:
    if e.get("create"):
        open(e["file"], "w").write(e["new"]); print("created", e["file"]); continue
    s = open(e["file"]).read()
    c = s.count(e["old"])
    if c != 1:
        print("FAILED", e["file"], "old matches", c); sys.exit(1)
    open(e["file"], "w").write(s.replace(e["old"], e["new"])); print("edited", e["file"])
PY
  ;;
esac
