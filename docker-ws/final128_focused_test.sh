#!/bin/bash
# Run one flutter test file in build/<tree>, log to <evid>/<name>.log.  host-run bash docker-ws/final128_focused_test.sh <tree> <test path> <evid>
REPO=/Volumes/CrucialX9/flutter_app; cd "$REPO/build/${1:?tree}" || exit 2
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
E="$REPO/${3:?evid}"; mkdir -p "$E"; L="$E/$(basename "${2:?test}" .dart).log"
flutter test --no-pub "$2" > "$L" 2>&1; rc=$?; tail -3 "$L"; echo "exit=$rc"; exit $rc
