#!/usr/bin/env bash
# Plan 309 focused Go gate (bridge denies bare `go`/`bash -c`; own module).
set -euo pipefail
cd "$(dirname "$0")/../../go-relay-server"
GOTOOLCHAIN=go1.25.0 go test . -run 'TestRelayNotificationClosure_GroupReaction(CollapseKeyOmittedForAndroid|ApnsCollapseIdRemainsPerGroup)' -count=1 -v
