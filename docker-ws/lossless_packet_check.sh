#!/bin/bash
# Read-only: list the Codex original-lossless packet and verify its SHA256SUMS. Prints names and verdicts only.
#   host-run bash docker-ws/lossless_packet_check.sh
P=/Volumes/CrucialX9/flutter_app_codex_original_lossless_20261022/build/kayan-safe/original-lossless
ls -la "$P" 2>&1 | head -20
cd "$P" 2>/dev/null || exit 2
shasum -a 256 SHA256SUMS | cut -c1-16
R=$(shasum -a 256 -c SHA256SUMS 2>&1); echo "ok=$(echo "$R" | grep -c ": OK$") notok=$(echo "$R" | grep -vc ": OK$")"
exit 0
