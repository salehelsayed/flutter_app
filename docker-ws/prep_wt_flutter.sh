#!/bin/bash
# Prepare a fresh worktree for mknoon_checks: android/local.properties from the main checkout, then flutter pub get.
#   host-run bash docker-ws/prep_wt_flutter.sh <worktree>
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; W="$1"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
[ -e "$W/android/local.properties" ] || { cp "$M/android/local.properties" "$W/android/local.properties" && echo "staged local.properties"; }
cd "$W" && flutter pub get > /tmp/prep_wt_pubget.log 2>&1; rc=$?; tail -2 /tmp/prep_wt_pubget.log; echo "pub get rc=$rc"; exit $rc
