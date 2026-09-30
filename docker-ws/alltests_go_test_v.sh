#!/bin/bash
# Verbose single go test run (bounded output) in main checkout.
cd /Volumes/CrucialX9/flutter_app/go-mknoon || exit 4
export GOTOOLCHAIN=go1.25.0
go test ./node/ -run "$1" -count=1 -v 2>&1 | grep -vE "^\s*$|\[NODE\]|\[RELAY|\[PUBSUB|\[CONN\]" | head -${2:-60}
