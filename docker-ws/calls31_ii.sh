#!/bin/bash
# iPhone-to-iPhone call: caller taps chat_call_button, callee answers as soon as SEL exists (fast element poll).
#   calls31_ii.sh <caller 11|13> <callee 11|13> <out-file> [answer-selector]   (default: in-app call_answer OR CallKit "Answer call")
cd "$(dirname "$0")/.." || exit 2
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
C=$1; R=$2; O="$3"; SEL="${4:-name == 'call_answer' OR label == 'Answer call'}"
{ timeout 60 python3 docker-ws/beta/ap.py $C tap "name == 'chat_call_button'"; echo "dial $(date -u +%T.%3N)"
  timeout 70 python3 docker-ws/beta/ap.py $R wait "$SEL" 45; echo "answer visible $(date -u +%T.%3N)"
  timeout 60 python3 docker-ws/beta/ap.py $R tap "$SEL"; echo "answered $(date -u +%T.%3N)"
} 2>&1 | tee "$O"
