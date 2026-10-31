#!/bin/bash
# iPhone 13 cold launch via Appium terminate/activate, then poll the Settings > Media & storage translator row.
cd /workspace; export AP_BASE=http://192.168.65.254:4725; A(){ timeout 90 python3 docker-ws/beta/ap.py 13 "$@"; }
A app terminate; sleep 2; echo "state after terminate: $(A app state)"
echo "launch $(date -u +%T)"; A app activate
A wait "label == 'Open settings'" 20; A tap "label == 'Open settings'"; sleep 1
A wait "label CONTAINS 'Media'" 10; A tapxy 195 633; sleep 1
A swipe 195 700 195 250 300 >/dev/null; A swipe 195 700 195 250 300 >/dev/null
for i in $(seq 1 ${1:-5}); do echo "$(date -u +%T) $(A src 'translator|Downloading|Pause|Resume|On this phone|Remove' | cut -d'|' -f3 | tr '\n' ' ')"; sleep 2; done
