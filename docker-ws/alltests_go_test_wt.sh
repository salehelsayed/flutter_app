#!/bin/bash
cd /Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree/go-mknoon || exit 4
export GOTOOLCHAIN=go1.27.1
go vet ./node/ && go test ./node/ -run "${1:-.}" -count=1 2>&1 | tail -3
