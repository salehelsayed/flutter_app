#!/usr/bin/env bash
# Plan 320 TC-320-01 fixture probe: does the pinned Firebase Admin SDK's
# messaging client honor option.WithEndpoint for Send (so an httptest.Server
# can stand in for FCM), and what response shape populates the typed
# messagingErrorCode the Is* predicates read? Host-side (no container Go).
set -uo pipefail
cd "$(dirname "$0")/../../go-relay-server"

MODCACHE=$(GOTOOLCHAIN=go1.25.0 go env GOMODCACHE 2>/dev/null)
VER=$(grep -oE 'firebase\.google\.com/go/v4 v[0-9.]+' go.mod | awk '{print $2}')
SRC="$MODCACHE/firebase.google.com/go/v4@$VER"

echo "=== messaging client construction + endpoint resolution ==="
grep -n 'fcmEndpoint\|messagingEndpoint\|NewClient\|EndpointURL\|endpoint' "$SRC/messaging/messaging.go" | head -25

echo
echo "=== internal transport: how endpoint/options flow ==="
grep -rn 'WithEndpoint\|Endpoint' "$SRC/internal/http_client.go" | head -10
grep -rn 'Endpoint' "$SRC/internal/internal.go" 2>/dev/null | head -10

echo
echo "=== how messagingErrorCode is populated from the response ==="
grep -n 'messagingErrorCode\|FcmError\|details' "$SRC/messaging/messaging.go" | head -15
sed -n '1060,1100p' "$SRC/messaging/messaging.go"

echo
echo "=== platform error parsing (internal/errors.go) ==="
grep -n 'details\|Details\|errorCode\|Ext\[' "$SRC/internal/errors.go" | head -20
