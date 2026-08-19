#!/bin/bash
# Host-side guard: is any Flutter/Gradle/Xcode/Dart build running against this
# checkout right now? Deleting build caches under a live build corrupts it.
# Run: /claude-host-bin/host-run bash docker-ws/check_active_builds.sh
set -uo pipefail
echo "== candidate build processes =="
ps ax -o pid=,etime=,command= 2>/dev/null \
  | grep -iE "gradle|xcodebuild|flutter_tools|dart .*(build|test)|flutter (build|test|run)" \
  | grep -v grep | head -15
echo "== (empty above = nothing building) =="
