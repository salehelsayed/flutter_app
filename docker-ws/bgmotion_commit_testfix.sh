#!/bin/bash
# Background motion 129 gate: commit the test-only go-core link-local fix in build/wt-bgmotion-129 on top of its HEAD.
#   host-run bash docker-ws/bgmotion_commit_testfix.sh
set -uo pipefail
cd /Volumes/CrucialX9/flutter_app/build/wt-bgmotion-129 || exit 2
F=go-mknoon/node/network_handoff_nat_observation_test.go
[ "$(git status --porcelain --untracked-files=no)" = " M $F" ] || { git status --porcelain --untracked-files=no; echo "STOP unexpected tracked changes"; exit 3; }
git add "$F"
git commit -q -F - <<'MSG'
test: skip link-local IPv4 in the NAT observation fixture

The relay fixture picked the first up non-loopback IPv4 address. After a
Mac restart that can be a 169.254.x.x link-local address, where the relay
dial times out, so the test failed on every run with no Go change.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
MSG
echo "commit exit=$? head=$(git rev-parse HEAD) parent=$(git rev-parse HEAD~1)"
git show --stat --format='%h %s' HEAD | tail -3
echo "tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
