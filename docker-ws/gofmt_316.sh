#!/bin/bash
cd "$(dirname "$0")/../go-relay-server"
test -z "$(gofmt -l .)" && echo GOFMT_CLEAN || { gofmt -l .; exit 1; }
