#!/bin/bash
# Read-only: GET WDA /status on a local forwarded port, verbose headers only.
curl -s -m 8 -o - -w "\nhttp=%{http_code}\n" "http://127.0.0.1:${1:?port}/status" | head -c 600; echo; lsof -nP -iTCP:"$1" -sTCP:LISTEN | tail -n +2 | cut -c1-80
