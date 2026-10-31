#!/bin/bash
# relay-hz-86b786747: run idle rounds in sequence.   bash docker-ws/rhz86_chain.sh <label:min> ...
cd "$(dirname "$0")/.." || exit 2
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
for lm in "$@"; do bash docker-ws/rhz86_round.sh "${lm%%:*}" "${lm##*:}"; done; echo CHAIN DONE
