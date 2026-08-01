#!/usr/bin/env bash
# Plan 320 focused Go gate: permanent push-error classification + eviction and
# wake measurability. Host-side (the bridge denies bare `go`; go-relay-server is
# its own module) with the pinned toolchain, mirroring run_test_gates.sh:1041.
set -euo pipefail
cd "$(dirname "$0")/../../go-relay-server"
GOTOOLCHAIN=go1.25.0 go test . -run '^TestRelayNotificationClosure_' -count=1 -v 2>&1 | tail -60
