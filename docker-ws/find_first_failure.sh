#!/bin/bash
# Read-only: recent first-failure.txt files from sims proof folders under the repo and the Mac temp dir.
find /Volumes/CrucialX9/flutter_app/build /Volumes/CrucialX9/flutter_app/.codex-test-logs "$TMPDIR" -name first-failure.txt -mmin -30 2>/dev/null | head -3 | while read f; do echo "== $f"; head -12 "$f" | cut -c1-220; done
