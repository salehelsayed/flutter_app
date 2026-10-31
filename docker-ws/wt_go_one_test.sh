#!/bin/bash
# Run one Go test by name N times in build/<tree>/go-mknoon/<pkg> (GOMAXPROCS=4), logging to a file.
#   host-run bash docker-ws/wt_go_one_test.sh <tree> <pkg dir> <test name> <count> <log under repo>
M=/Volumes/CrucialX9/flutter_app; L="$M/${5:?log}"
GO=$(ls -d $HOME/sdk/go1.27.1/bin/go /usr/local/go/bin/go 2>/dev/null | head -1); GO=${GO:-go}
cd "$M/build/${1:?tree}/go-mknoon/${2:?pkg}" || exit 2
GOMAXPROCS=4 timeout 900 "$GO" test -run "^${3:?name}\$" -count="${4:-3}" -v . > "$L" 2>&1; rc=$?
grep -E "^(--- (PASS|FAIL)|ok|FAIL)" "$L" | tail -8; echo "exit=$rc"; exit $rc
