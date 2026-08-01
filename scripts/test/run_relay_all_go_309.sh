#!/usr/bin/env bash
# Plan 309 re-land: unfiltered relay module run (TC-09 + collateral sweep).
set -euo pipefail
cd "$(dirname "$0")/../../go-relay-server"
GOTOOLCHAIN=go1.25.0 go test ./... -count=1
