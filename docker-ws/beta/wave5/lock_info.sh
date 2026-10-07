#!/bin/bash
L=/Volumes/CrucialX9/flutter_app/.git/index.lock
[ -e "$L" ] && echo "lock age $(( $(date +%s) - $(stat -f %m "$L") ))s" || echo "no lock"
pgrep -fl "^git |/git " | head -5
