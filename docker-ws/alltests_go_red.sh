#!/bin/bash
# Red check: copy the new test into the worktree (no fix yet) and run it there.
cp /Volumes/CrucialX9/flutter_app/go-mknoon/node/stale_relay_resend_test.go /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/go-mknoon/node/
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/go-mknoon || exit 4
export GOTOOLCHAIN=go1.25.0
go test ./node/ -run StaleRelayResend -count=1 -v 2>&1 | grep -E "^(--- |ok|FAIL)|stale_relay_resend_test.go:[0-9]+" | head -10
