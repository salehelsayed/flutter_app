#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$root/docker-ws/create_agent_worktree.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

origin="$fixture/origin"
main="$fixture/flutter_app"
name=contract
branch=contract/agent-wt
worktree="$fixture/flutter_app-$name"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

git init -q -b main "$origin"
mkdir -p "$origin/scripts"
printf '%s\n' '#!/bin/bash' ': "${KAYAN_AGENT-}"' >"$origin/scripts/run_claude_docker.sh"
git -C "$origin" add scripts/run_claude_docker.sh
git -C "$origin" -c user.name='Worktree fixture' -c user.email=fixture@example.invalid \
  -c commit.gpgSign=false -c core.hooksPath=/dev/null commit -qm fixture
git clone -q "$origin" "$main"

files=(CLAUDE.md AGENTS.md .claude/fixture .env ios/Runner/GoMknoon.inputs.sha256)
mkdir -p "$main/.claude/skills/kayan-launch/state" "$main/ios/Runner"
printf '%s\n' "${files[@]}" .claude/skills/kayan-launch/state/ >"$main/.git/info/exclude"
for file in "${files[@]}" .claude/skills/kayan-launch/state/fixture; do
  printf 'synthetic fixture for %s\n' "$file" >"$main/$file"
done

export AGENT_WT_MAIN="$main" AGENT_WT_BASE="$fixture" AGENT_WT_SKIP_PUBGET=1 AGENT_WT_OVERLAY=

mkdir "$worktree"
rc=0
out=$(bash "$script" "$name" "$branch" 2>&1) || rc=$?
{ [ "$rc" = 2 ] && grep -q 'already exists' <<<"$out"; } ||
  fail "existing path not refused (rc $rc)"
if git -C "$main" show-ref --verify -q "refs/heads/$branch"; then
  fail 'refusal still created the branch'
fi
rmdir "$worktree"

rc=0
bash "$script" 'Bad/Name' "$branch" >/dev/null 2>&1 || rc=$?
[ "$rc" = 2 ] || fail "bad name not refused (rc $rc)"

rc=0
out=$(bash "$script" "$name" "$branch" 2>&1) || rc=$?
[ "$rc" = 0 ] || fail "create failed (rc $rc): $(tail -3 <<<"$out")"
[ -f "$worktree/.git" ] || fail 'no worktree .git file'
grep -q 'locked: 1' <<<"$out" || fail 'worktree not locked'
grep -q 'tracked changes: 0' <<<"$out" || fail 'new worktree has tracked changes'
for file in "${files[@]}"; do
  cmp -s "$main/$file" "$worktree/$file" || fail "missing or changed copied file $file"
done
[ ! -e "$worktree/.claude/skills/kayan-launch/state" ] || fail 'flutter mailbox state was copied'
echo 'PASS: create_agent_worktree contract'
