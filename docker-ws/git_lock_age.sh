#!/bin/bash
# Read-only: age of the main checkout git index.lock, if any.
L=/Volumes/CrucialX9/flutter_app/.git/index.lock; [ -e "$L" ] && echo "lock age_s=$(( $(date +%s) - $(stat -f %m "$L") ))" || echo "no lock"
