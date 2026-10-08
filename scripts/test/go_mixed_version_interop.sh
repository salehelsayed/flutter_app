#!/usr/bin/env bash
# Plan 406 — mixed-version interop gate. Builds an OLD (pre-406, go1.25.0) and
# a NEW (this tree, go1.27.1) testpeer + relay and checks every OLD/NEW pair
# against both relays: direct QUIC (twice), direct TCP, relay circuit, 1:1
# message, relay inbox, GossipSub group message and relay media.
# Extra arguments go to the Python driver (see --help).
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 -I "$repo_root/scripts/test/go_mixed_version_interop.py" --repo "$repo_root" "$@"
