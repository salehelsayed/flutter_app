#!/bin/bash
# Re-run only the live relay smoke tests (go-relay-server quic_smoke_test.go) on the Mac.
cd /Volumes/CrucialX9/flutter_app/.claude/worktrees/wave3-next/go-relay-server || exit 1
export PATH="/usr/local/go/bin:/opt/homebrew/bin:$PATH"
GOTOOLCHAIN=auto go test -count=1 -run 'TestQUICSmokeIdentify|TestTCPSmokeIdentify|TestQUICSmokeRelayReservation|TestAllTransportsSmokeCompare' -v . 2>&1 | grep -E "^(=== RUN|--- |ok|FAIL|PASS)|smoke_test.go" | head -40
