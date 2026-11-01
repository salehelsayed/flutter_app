#!/bin/bash
# Notification Center on a USB iPhone, filtered in the same command to Mknoon cards only (owner rule: never keep other apps' cards).
#   p193_ios_nc.sh <11|13> [tap <card-text>]   open NC, print Mknoon card lines (TestFlight cards dropped); with "tap", tap the card whose label contains <card-text>
export AP_BASE=${AP_BASE:-http://192.168.65.254:4725}
cd "$(dirname "$0")/beta" || exit 2
AP() { timeout 120 python3 ap.py "$@"; }
[ "$(AP "$1" app state)" = 4 ] && { AP "$1" app background -1 >/dev/null; sleep 2; }   # an in-app top swipe does not open NC; from Home it does
AP "$1" swipe 80 2 80 600 400 >/dev/null; sleep 2.5
N=$(AP "$1" src '.' | awk -F' [|] ' '$2 ~ /^(NotificationShortLookView|ListCell)$/' | wc -l)
echo "nc $1 $(date -u +%T) nc_cards_total=$N (0 means NC not open or empty)"
AP "$1" src '(?i)mknoon|New Introduction|New contact request' | grep -viE 'testflight|ready to test' | awk -F'|' '$1 ~ /ListCell|Button/ {print $1"|"$3"|"$5}'
if [ "${2:-}" = tap ]; then
  AP "$1" tap "type == 'XCUIElementTypeButton' AND label CONTAINS '${3:?card text}' AND NOT (label CONTAINS[c] 'testflight')" && echo "tapped card $(date -u +%T)"
else
  AP "$1" app activate com.mknoon.app >/dev/null; sleep 2; echo "back state=$(AP "$1" app state)"
fi
