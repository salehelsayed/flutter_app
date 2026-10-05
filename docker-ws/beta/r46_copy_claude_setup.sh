#!/bin/bash
# Copy the local (git-excluded) Claude setup from the main checkout into the UI-Update worktree.
# Tracked .claude files already come from git, so existing files are never overwritten.
SRC=/Volumes/CrucialX9/flutter_app/.claude/
DST=/Volumes/CrucialX9/flutter_app-ui-update/.claude/
[ -d /Volumes/CrucialX9/flutter_app-ui-update/.git ] || [ -f /Volumes/CrucialX9/flutter_app-ui-update/.git ] || { echo "worktree missing"; exit 1; }
rsync -a --ignore-existing --exclude '__pycache__/' --exclude 'worktrees/' --exclude 'scheduled_tasks.lock' "$SRC" "$DST" || exit 1
cd /Volumes/CrucialX9/flutter_app-ui-update || exit 1
for f in settings.json settings.local.json CLAUDE.md tools/jev_sort_findings.py skills/graphify/SKILL.md skills/beta-tester/SKILL.md skills/tdd-plan/SKILL.md skills/tdd-review/SKILL.md skills/sims/SKILL.md hooks/jev_triage_on_red.py; do
  [ -f ".claude/$f" ] && echo "ok .claude/$f" || echo "MISSING .claude/$f"
done
echo "files: src=$(cd "$SRC" && find . -type f -not -path '*/__pycache__/*' -not -name scheduled_tasks.lock | wc -l | tr -d ' ') dst=$(find .claude -type f | wc -l | tr -d ' ')"
echo "git sees .claude as untracked: $(git status --porcelain .claude | grep -c '^??')"
