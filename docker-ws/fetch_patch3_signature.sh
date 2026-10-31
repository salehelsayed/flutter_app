#!/bin/bash
# Copy Codex's patch-3 failure signature into build/kayan-safe/f10/ (read-only source).
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cp /Volumes/CrucialX9/flutter_app_codex_pr15_t3elbg1o/.codex-test-logs/patch3-preinput-hide-20261018/failure-signature.txt "$REPO/build/kayan-safe/f10/patch3-signature.txt" && wc -c "$REPO/build/kayan-safe/f10/patch3-signature.txt"
