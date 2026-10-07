#!/bin/bash
d=$(ls -dt "${TMPDIR:-/tmp}"/group_multi_party_* 2>/dev/null | head -1)
grep -a -B2 -A12 "failure 1\b\|FAILED\|EXCEPTION CAUGHT\|Expected:" "$d/alice.log" | grep -av "^\[FLOW\]" | head -30 | cut -c1-200
