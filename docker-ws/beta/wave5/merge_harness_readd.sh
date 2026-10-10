#!/bin/bash
# User-approved 2026-10-07: fast-forward main and wave3-baseline-20260930 to
# fix/original-multi-party-harness-readd (7a4551998) and push both.
set -eu
cd /Volumes/CrucialX9/flutter_app
SRC=refs/remotes/origin/fix/original-multi-party-harness-readd
git rev-parse --short "$SRC"
# checked-out branch: ff-only merge updates the working tree
git merge --ff-only "$SRC"
# main is not checked out: fetch from self refuses a non-fast-forward
git fetch . "$SRC:refs/heads/main"
git log --oneline -1 main
git log --oneline -1 wave3-baseline-20260930
git push origin main wave3-baseline-20260930
git status --short | head
