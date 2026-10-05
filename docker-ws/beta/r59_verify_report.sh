#!/bin/bash
# Re-run SIMS report verification for one report and time it.
cd /Volumes/CrucialX9/flutter_app
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:$PATH"
start=$(date +%s); dart tool/sims/sims.dart verify-report "$1" 2>&1 | tail -5; echo "rc=${PIPESTATUS[0]} seconds=$(($(date +%s)-start))"
