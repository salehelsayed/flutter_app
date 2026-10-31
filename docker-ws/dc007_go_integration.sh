#!/bin/bash
# Run the 3 DC007 upload-storage integration Go tests in a worktree.
#   bash docker-ws/dc007_go_integration.sh <worktree>
export GOTOOLCHAIN=go1.27.1 GOMAXPROCS=4 PATH="/opt/homebrew/bin:/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin"
cd "$1/go-relay-server" || exit 2
go test -count=1 -p 4 -tags=integration -run '^TestDirectMediaFixtureUploadStorage' -v . 2>&1 | grep -E "^(=== RUN|--- |PASS|FAIL|ok|panic)" 
exit ${PIPESTATUS[0]}
