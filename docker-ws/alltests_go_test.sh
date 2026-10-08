#!/bin/bash
# Run go tests for go-mknoon/node matching a pattern in this checkout.
set -o pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../go-mknoon" || exit 4
export GOTOOLCHAIN=go1.27.1
go test ./node/ -run "${1:-Send}" -count=1 2>&1 | tail -15
