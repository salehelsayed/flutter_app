#!/usr/bin/env bash
# Plan 321 TC-12: read the LIVE relay version + binary sha256 for the staging
# manifest declaration (the campaign's relay-provenance guard).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
SSH="ssh -i $REPO/se.pem -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 ubuntu@13.60.15.36"
$SSH '/usr/local/bin/relay-server version; sha256sum /usr/local/bin/relay-server'
