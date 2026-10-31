#!/bin/bash
# Commit exactly the given paths on local main (main checkout). Message from $1, body lines from the file in $2.
#   host-run bash docker-ws/main_commit_paths.sh "<subject>" <body file under repo> <path>...
set -uo pipefail
S=${1:?subject}; : "$S"; B=${2:?body}; shift 2
cd /Volumes/CrucialX9/flutter_app || exit 2
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { echo "STOP not on main"; exit 3; }
git reset -q; git add -- "$@"
git commit -q -F "$B" && echo "commit $(git rev-parse --short HEAD)"
git status --porcelain --untracked-files=normal | head
