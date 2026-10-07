#!/bin/bash
# Read-only: scan the diff of unpushed commits for secret-looking content and list changed files' total size.
cd /Volumes/CrucialX9/flutter_app || exit 1
git diff --stat origin/wave3-baseline-20260930..HEAD | tail -1
git diff origin/wave3-baseline-20260930..HEAD | grep -nE "^\+" | grep -iE "BEGIN (RSA|EC|OPENSSH|PRIVATE)|private_key\"|\"private_key_id\"|AIza[0-9A-Za-z_-]{30}|ghp_[0-9A-Za-z]{30}|xox[bp]-|password\s*[:=]\s*\"[^\"]{6}|secret\s*[:=]\s*\"[^\"]{8}" | head -5 | cut -c1-160
echo "scan done"
git diff --name-only origin/wave3-baseline-20260930..HEAD | grep -iE "\.pem$|\.p12$|service.account|adminsdk|\.env$|private/" | head
