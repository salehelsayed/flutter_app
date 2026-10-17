#!/bin/bash
# Debug run of the SQLCipher capability integration test on one iOS simulator,
# with verbose Flutter output streamed to a log file so a hang can be diagnosed.
#   host-run bash docker-ws/h04_ios_sqlcipher_debug.sh <simulator-udid> <log-file-in-repo> [reporter]
set -uo pipefail
cd "$(dirname "$0")/.."
UDID="${1:?simulator udid}"
LOG="${2:?log file}"
REPORTER="${3:-expanded}"
flutter test -v --no-pub integration_test/migration_database_sqlcipher_capability_test.dart \
  -d "$UDID" --reporter="$REPORTER" > "$LOG" 2>&1
rc=$?
echo "exit=$rc" >> "$LOG"
exit "$rc"
