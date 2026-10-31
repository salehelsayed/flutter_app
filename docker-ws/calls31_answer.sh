#!/bin/bash
# Pixel dials the open chat, the iPhone answers as soon as its in-app Answer button exists.
#   IP=<11|13> calls31_answer.sh <out-file> [answer-selector]
cd "$(dirname "$0")/.." || exit 2
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
I=${IP:-13}; O="$1"; SEL="${2:-name == 'call_answer'}"
{ bash docker-ws/calls31.sh ptap 'Start voice call'
  timeout 60 python3 docker-ws/beta/ap.py $I wait "$SEL" 40 && echo "answer visible $(date -u +%T.%3N)"
  timeout 60 python3 docker-ws/beta/ap.py $I tap "$SEL"; echo "answered $(date -u +%T.%3N)"
} 2>&1 | tee "$O"
