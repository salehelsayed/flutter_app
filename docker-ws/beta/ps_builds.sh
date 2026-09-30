#!/bin/bash
# Read-only: list build/test processes on the Mac.
ps -axo pid,ppid,etime,command | grep -E "build_beta_apps|flutter_tools|gomobile|gradle|xcodebuild|run_sims|sims|flutter test|make " | grep -v grep | cut -c1-260
echo "--- aar"
ls -la /Volumes/CrucialX9/flutter_app/android/app/libs/
