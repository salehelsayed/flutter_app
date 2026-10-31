#!/bin/bash
# Run one flutter test file in a tree under build/ (serial).   host-run bash docker-ws/translate_main_one_test.sh <tree under build/> <test file> <log under repo>
REPO=/Volumes/CrucialX9/flutter_app; cd "$REPO/build/${1:?tree}" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
echo "head=$(git rev-parse --short HEAD)" > "$REPO/${3:?log}"
flutter test --no-pub -r expanded "${2:?test}" >> "$REPO/$3" 2>&1; rc=$?; echo "exit=$rc" >> "$REPO/$3"; tail -4 "$REPO/$3"; exit $rc
