#!/bin/bash
# User-approved 2026-10-07: store build 1.0.1+122 (Play AAB + App Store IPA) with
# docker-ws/build_store_release.sh, on Flutter 3.47.2. Self-detaches; log in
# release122_build.log, results in docker-ws/build_store_release_result.txt.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/release122_build.log
if [ -z "${REL122_DETACHED:-}" ]; then
  REL122_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
export FLUTTER_XCODE_CLANG_ENABLE_EXPLICIT_MODULES=NO
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "flutter: $(flutter --version 2>/dev/null | head -1)"; date
bash docker-ws/build_store_release.sh
echo "STORE BUILD EXIT=$?"; date
