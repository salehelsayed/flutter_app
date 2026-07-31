#!/bin/bash
# Run go-relay-server tests with the repo-pinned toolchain. Arg 1 = -run pattern (optional).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO/go-relay-server"
PATTERN="${1:-}"
if [ -n "$PATTERN" ]; then
  GOTOOLCHAIN=go1.25.0 go test ./... -run "$PATTERN" -count=1 2>&1
else
  GOTOOLCHAIN=go1.25.0 go test ./... -count=1 2>&1
fi
