#!/bin/bash
# Run flutter test on the main checkout, detached, logging to voice_test_<tag>.log.
# Usage: voice_flutter_test.sh <tag> <flutter test args...>
set -u
TAG=$1; shift
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/voice_test_$TAG.log
if [ -z "${VOICE_TEST_DETACHED:-}" ]; then
  VOICE_TEST_DETACHED=1 nohup bash "$0" "$TAG" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app || exit 1
date
"$HOME/development/flutter-3.47.2/bin/flutter" test --no-pub "$@"
echo "TEST EXIT=$?"; date
