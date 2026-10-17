#!/bin/bash
# Pull exactly the coturn image digest pinned in tool/call_audio_oracle/coturn.lock.json and verify it.
#   host-run bash docker-ws/pull_pinned_coturn.sh
set -uo pipefail
cd "$(dirname "$0")/.."
REF="coturn/coturn@sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e"
grep -q "aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e" tool/call_audio_oracle/coturn.lock.json \
  || { echo "refused: digest not in coturn.lock.json" >&2; exit 2; }
docker pull "$REF" > /dev/null 2>&1 || { echo "pull failed"; exit 1; }
docker image inspect --format '{{join .RepoDigests ","}}' "$REF" | grep -q "@sha256:aa68aab64a3b929d57fc2924c98ea447bf996cf8dade2508e7b71eaf23f1f14e" \
  && echo "pinned coturn image present and digest verified" || { echo "digest mismatch"; exit 1; }
