#!/bin/bash
# From an open 1:1 chat on iPhone <phone>: Conversation options > Introduce to your circle > search <who> > select exactly one > send.
#   p193_intro.sh <11|13> <who>
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/beta" || exit 2
AP() { timeout 120 python3 ap.py "$@"; }
I=$1; W=$2
AP $I tap "label == 'Back to conversation'" >/dev/null 2>&1 && sleep 2
AP $I tap "label == 'Conversation options'" >/dev/null || exit 3; sleep 2
AP $I tap "label == 'Introduce to your circle'" >/dev/null || exit 3; sleep 3
AP $I tap "type == 'XCUIElementTypeTextField'" >/dev/null; sleep 1; AP $I key "$W" >/dev/null; sleep 2
AP $I tap "type == 'XCUIElementTypeStaticText' AND label == '$W'" >/dev/null || exit 4; sleep 1
AP $I find "label == 'Introduce (1)'" >/dev/null || { echo "selection is not exactly one"; exit 5; }
AP $I tap "label == 'Introduce (1)'" >/dev/null; echo "introduced $(date -u +%T)"; sleep 3
AP $I src 'introduction sent|already' | awk -F'|' '{print $3}'
