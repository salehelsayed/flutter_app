#!/bin/bash
# Plan 414: show flutter test driver processes and their working directories.
for p in $(pgrep -f "flutter_tools.snapshot test"); do
  echo "PID $p cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p') $(ps -o etime= -p $p)"
done
if [ "${1:-}" = "--kill-worktree" ]; then
  ROOT="$(cd "$(dirname "$0")/.." && pwd)"
  for p in $(pgrep -f "flutter_tools.snapshot test"); do
    cwd=$(lsof -a -p $p -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')
    [ "$cwd" = "$ROOT" ] && kill "$p" && echo "killed $p"
  done
fi
