#!/bin/bash
# Run the release-defines python tests in the release-126 worktree.
cd /Volumes/CrucialX9/flutter_app/build/wt-release-126 || exit 3
python3 -m unittest scripts/test/check_update_check_release_defines_test.py 2>&1 | tail -5
