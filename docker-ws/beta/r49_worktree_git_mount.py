#!/usr/bin/env python3
"""Patch the UI-Update worktree's scripts/run_claude_docker.sh so a container started from a git
worktree also mounts the main repository's .git directory at its own Mac path (the worktree's .git
file points there). Run on the Mac: host-run bash docker-ws/beta/r49_worktree_git_mount.sh"""
import pathlib, sys

path = pathlib.Path('/Volumes/CrucialX9/flutter_app-ui-update/scripts/run_claude_docker.sh')
s = path.read_text()
marker = 'git-common-dir'
if marker in s:
    print('already patched'); sys.exit(0)
anchor = '\nstart_host_bridge\n\nDOCKER_RUN_ARGS+=(\n  -e PATH='
if s.count(anchor) != 1:
    print('anchor count', s.count(anchor)); sys.exit(1)
block = '''
# In a git worktree, .git is a file that points into the main repository's
# .git directory by its Mac path. Mount that directory at the same path so
# git works inside the container.
if [ -f "${REPO_ROOT}/.git" ]; then
  GIT_COMMON_DIR="$(git -C "${REPO_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "${GIT_COMMON_DIR}" ] && [ -d "${GIT_COMMON_DIR}" ]; then
    DOCKER_RUN_ARGS+=(-v "${GIT_COMMON_DIR}:${GIT_COMMON_DIR}")
  fi
fi
'''
s = s.replace(anchor, '\n' + block.strip('\n') + '\n' + anchor, 1)
path.write_text(s)
print('patched')
