#!/bin/bash
mknoon_real_path() { python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$1"; }
# Resolve existing symlinks before allowing an outside or gitignored output.
mknoon_require_output() {
  python3 - "$1" "$2" "${3:-ignored-ok}" <<'PY'
import os, subprocess, sys
repo, target = (os.path.realpath(p) for p in sys.argv[1:3])
if os.path.commonpath([repo, target]) == repo:
    if sys.argv[3] == 'outside' or subprocess.run(
        ['git', '-C', repo, 'check-ignore', '-q', '--', target],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode != 0:
        sys.exit('refused output in an unignored repository path')
PY
}
