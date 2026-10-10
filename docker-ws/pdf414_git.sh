#!/bin/bash
# Plan 414: run git in this worktree on the Mac (container git cannot resolve
# the worktree's Mac gitdir).
cd "$(cd "$(dirname "$0")/.." && pwd)"
exec git "$@"
