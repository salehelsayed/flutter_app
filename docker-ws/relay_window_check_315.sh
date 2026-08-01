#!/bin/bash
# Post-hoc: relay wake/push lines for a given window (arg1 = journal --since).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SINCE="${1:-2026-08-01 07:47}"
ssh -i "$REPO/se.pem" -o StrictHostKeyChecking=accept-new ubuntu@13.60.15.36 \
  "sudo journalctl -u relay-server --since '$SINCE' --no-pager | grep -aE 'GROUP_REACTION_WAKE|Group notification sent|Skip group push|Refusing oversized|Strict routing fallback|payload size' | tail -30"
