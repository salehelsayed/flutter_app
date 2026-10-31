#!/bin/bash
# VC-014: chain of locked-style rounds; each idle counts from the end of the previous round.
#   bash docker-ws/vc014p_chain.sh <since-utc> <label:min> ...
cd "$(dirname "$0")/.." || exit 2
S="$1"; shift
for lm in "$@"; do
  L=${lm%%:*}; M=${lm##*:}
  bash docker-ws/vc014p_round_locked.sh "$L" "$M" "$S"
  S=$(date -u +%FT%TZ)
done
echo CHAIN DONE
