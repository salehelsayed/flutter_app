#!/bin/bash
# Write the Mac's private LAN IPv4 as the fixture host pins into the ignored docker-ws/local_devices.env (never printed).
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; F="$REPO/docker-ws/local_devices.env"
git -C "$REPO" check-ignore -q "$F" || { echo "refused: env file not ignored"; exit 2; }
IP=""; for i in en0 en1 en2 en3 en4 en5 en6 en7 en8; do IP=$(ipconfig getifaddr "$i" 2>/dev/null) && [ -n "$IP" ] && break; done
case "$IP" in 10.*|192.168.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*) ;; *) echo "no private LAN IPv4 found"; exit 2;; esac
grep -v -E '^(PLAN399|PLAN347)_FIXTURE_HOST_IP=' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
printf 'PLAN399_FIXTURE_HOST_IP=%s\nPLAN347_FIXTURE_HOST_IP=%s\n' "$IP" "$IP" >> "$F"
echo "fixture host pins written (private LAN, interface found)"
