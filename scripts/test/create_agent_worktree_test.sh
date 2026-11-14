#!/bin/bash
# Mac-only contract for docker-ws/create_agent_worktree.sh: refuses an existing path and a bad
# name, and creates a locked worktree with the excluded files. Cleans up its own worktree and branch.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
S="$ROOT/docker-ws/create_agent_worktree.sh"
MAIN=/Volumes/CrucialX9/flutter_app
BASE="$(mktemp -d)"; NAME="contract$$"; BR="contract/agent-wt-$$"; WT="$BASE/flutter_app-$NAME"
cleanup() {
  git -C "$MAIN" worktree unlock "$WT" 2>/dev/null; git -C "$MAIN" worktree remove --force "$WT" 2>/dev/null
  git -C "$MAIN" branch -D "$BR" >/dev/null 2>&1; rm -rf "$BASE"
}
fail() { echo "FAIL: $1"; cleanup; exit 1; }
mkdir -p "$WT"
out=$(AGENT_WT_BASE="$BASE" bash "$S" "$NAME" "$BR" 2>&1); rc=$?
{ [ $rc = 2 ] && grep -q 'already exists' <<<"$out"; } || fail "existing path not refused (rc $rc)"
git -C "$MAIN" rev-parse -q --verify "refs/heads/$BR" >/dev/null && fail 'refusal still created the branch'
rmdir "$WT"
AGENT_WT_BASE="$BASE" bash "$S" 'Bad/Name' "$BR" >/dev/null 2>&1; rc=$?
[ $rc = 2 ] || fail "bad name not refused (rc $rc)"
out=$(AGENT_WT_BASE="$BASE" AGENT_WT_SKIP_PUBGET=1 bash "$S" "$NAME" "$BR" 2>&1); rc=$?
[ $rc = 0 ] || fail "create failed (rc $rc): $(tail -3 <<<"$out")"
[ -f "$WT/.git" ] || fail 'no worktree .git file'
grep -q 'locked: 1' <<<"$out" || fail 'worktree not locked'
grep -q 'tracked changes: 0' <<<"$out" || fail 'new worktree has tracked changes'
for f in CLAUDE.md AGENTS.md .claude .env ios/Runner/GoMknoon.inputs.sha256; do
  [ -e "$WT/$f" ] || fail "missing copied file $f"
done
[ -e "$WT/.claude/skills/kayan-launch/state" ] && fail 'flutter mailbox state was copied'
cleanup
echo 'PASS: create_agent_worktree contract'
