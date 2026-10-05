#!/bin/bash
# Remove the main checkout's .git/index.lock only when it is older than 10 minutes and no git process runs on the Mac.
L=/Volumes/CrucialX9/flutter_app/.git/index.lock
[ -e "$L" ] || { echo "no lock"; exit 0; }
pgrep -x git >/dev/null && { echo "a git process is running; not removing"; pgrep -lx git; exit 1; }
[ -n "$(find "$L" -mmin +10)" ] || { echo "lock is recent; not removing"; exit 1; }
rm -f "$L" && echo "removed stale lock"
