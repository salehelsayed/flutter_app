#!/bin/bash
# Fast-forward the main checkout to <target> while keeping the NOT-ours local edit in docs/testing/TESTING.md:
# save it as a patch, reset only that file, fast-forward, re-apply the patch (3-way). The edit stays uncommitted.
# If re-apply fails, the patch file is kept and reported. Never stashes.
#   host-run bash docker-ws/main_ff_keep_testing_md.sh <target> <patch-file-in-repo>
set -uo pipefail
T=${1:?target}; M=/Volumes/CrucialX9/flutter_app; P="$M/${2:?patch}"; F=docs/testing/TESTING.md
cd "$M" || exit 2
mkdir -p "$(dirname "$P")"
git diff -- "$F" > "$P"; echo "saved patch lines=$(wc -l < "$P" | tr -d ' ') sha=$(shasum -a 256 "$P" | cut -c1-16)"
[ -s "$P" ] || { echo "STOP empty patch"; exit 3; }
git checkout -- "$F"
git merge --ff-only "$T" 2>&1 | tail -1; echo "ff exit=${PIPESTATUS[0]} head=$(git rev-parse --short HEAD)"
if git apply -3 "$P" 2>&1; then echo "re-applied the TESTING.md edit (uncommitted)"; else echo "RE-APPLY FAILED: patch kept at $P"; fi
git diff --stat -- "$F"
