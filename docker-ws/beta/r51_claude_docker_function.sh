#!/bin/bash
# Replace the claude-docker alias in ~/.zshrc with a function that starts the launcher of the git
# checkout you are in (main checkout or any worktree), falling back to the main checkout.
Z="$HOME/.zshrc"
OLD="alias claude-docker='/Volumes/CrucialX9/flutter_app/scripts/run_claude_docker.sh --dangerously-skip-permissions --permission-mode acceptEdits'"
grep -qxF "$OLD" "$Z" || { echo "alias line not found as expected; not changing"; grep -n 'claude-docker' "$Z"; exit 2; }
cp -p "$Z" "$Z.bak-claude-docker-20261002"
python3 - "$Z" "$OLD" <<'PY'
import sys
p, old = sys.argv[1], sys.argv[2]
new = '''# claude-docker: start the launcher of the checkout you are in (main or a worktree).
unalias claude-docker 2>/dev/null
claude-docker() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)"
  [ -x "$root/scripts/run_claude_docker.sh" ] || root=/Volumes/CrucialX9/flutter_app
  "$root/scripts/run_claude_docker.sh" --dangerously-skip-permissions --permission-mode acceptEdits "$@"
}'''
s = open(p).read()
assert s.count(old + "\n") == 1
open(p, 'w').write(s.replace(old + "\n", new + "\n", 1))
PY
zsh -n "$Z" && echo "zshrc syntax ok"
grep -n -A7 'claude-docker: start' "$Z"
# Which launcher would each folder pick?
for d in /Volumes/CrucialX9/flutter_app /Volumes/CrucialX9/flutter_app-ui-update "$HOME"; do
  r=$(cd "$d" && git rev-parse --show-toplevel 2>/dev/null); [ -x "$r/scripts/run_claude_docker.sh" ] || r=/Volumes/CrucialX9/flutter_app
  echo "$d -> $r/scripts/run_claude_docker.sh"
done
echo "R51 DONE"
