#!/usr/bin/env bash
# Plan 320 probe: what permanent-token error predicates does the pinned Firebase
# Admin SDK actually expose, and what do they inspect? The container has no Go
# toolchain/module cache, so this runs host-side (bridge-allowed repo script).
set -uo pipefail
cd "$(dirname "$0")/../../go-relay-server"

echo "=== pinned SDK version ==="
grep -E 'firebase.google.com/go' go.mod

echo
echo "=== exported Is* predicates in messaging ==="
GOTOOLCHAIN=go1.25.0 go doc firebase.google.com/go/v4/messaging 2>/dev/null | grep -E '^func Is' || echo "(go doc returned nothing)"

MODCACHE=$(GOTOOLCHAIN=go1.25.0 go env GOMODCACHE 2>/dev/null)
VER=$(grep -oE 'firebase\.google\.com/go/v4 v[0-9.]+' go.mod | awk '{print $2}')
SRC="$MODCACHE/firebase.google.com/go/v4@$VER/messaging"
echo
echo "=== source: $SRC ==="
if [ -d "$SRC" ]; then
  echo "--- predicate definitions ---"
  grep -rn '^func Is[A-Za-z]*(' "$SRC"/*.go | grep -v _test.go
  echo "--- predicate bodies + the codes they compare ---"
  sed -n '996,1020p' "$SRC"/messaging.go
  echo "--- error-code constants ---"
  grep -rnE '(NotRegistered|Unregistered|SenderIDMismatch|senderIDMismatch|registrationTokenNotRegistered)' "$SRC"/messaging.go | grep -v '^.*func Is' | head -12
else
  echo "MODULE SOURCE NOT FOUND at that path; listing candidates:"
  ls -d "$MODCACHE"/firebase.google.com/go/* 2>/dev/null | head
fi
