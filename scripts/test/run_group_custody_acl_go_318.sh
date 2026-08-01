#!/usr/bin/env bash
# Plan 318 focused Go gate: the host bridge denies bare `go` and `bash -c`,
# and go-relay-server is its own module — mirror the curated lane's invocation
# (run_test_gates.sh:1038) with the pinned toolchain.
set -euo pipefail
cd "$(dirname "$0")/../../go-relay-server"
GOTOOLCHAIN=go1.25.0 go test . -run 'TestRelayNotificationClosure_GroupCustodyAclVerbs' -count=1 -v
