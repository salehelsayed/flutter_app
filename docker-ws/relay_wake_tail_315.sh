#!/bin/bash
# Live tail of reaction-wake + group-push lines on the production relay.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
exec ssh -i "$REPO/se.pem" -o StrictHostKeyChecking=accept-new ubuntu@13.60.15.36 \
  "sudo journalctl -u relay-server -f --no-pager | grep --line-buffered -aE 'GROUP_REACTION_WAKE|Group notification sent|Skip group push|Refusing oversized|Strict routing fallback'"
