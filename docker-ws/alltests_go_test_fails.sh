#!/bin/bash
# Run go-mknoon/node tests matching a pattern; print only failing test names and their assertion lines.
cd /Volumes/CrucialX9/flutter_app/go-mknoon || exit 4
export GOTOOLCHAIN=go1.27.1
go test ./node/ -run "${1:-Send}" -count=1 -v 2>&1 | grep -E "^(--- FAIL|=== RUN|FAIL|ok)|_test.go:[0-9]+:" | grep -B1 -A4 -E "^--- FAIL|_test.go" | grep -vE "^=== RUN" | head -40
