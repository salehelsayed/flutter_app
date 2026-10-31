#!/bin/bash
# git apply --check of one patch against the current checkout (no change).  host-run bash docker-ws/apply_check.sh <patch under build/>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; cd "$REPO" || exit 2
git apply --check -v "$REPO/${1:?patch}" 2>&1 | tail -12; echo "check_exit=${PIPESTATUS[0]}"
