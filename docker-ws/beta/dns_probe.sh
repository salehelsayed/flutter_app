#!/bin/bash
# Read-only: what mknoun.xyz resolves to (authoritative servers, public resolvers, this
# Mac's resolver and system cache, the Pixel emulator), and whether the relay answers
# on its ports at the new address.  Usage: dns_probe.sh [expected ip]
. "$(dirname "$0")/beta_env.sh"
NAME=mknoun.xyz
NEW=${1:-51.21.194.144}
echo "expected: $NEW   now: $(date '+%H:%M:%S')"
echo "--- authoritative name servers (answer, record TTL)"
for ns in $(dig +short NS $NAME); do
  printf '%s: ' "$ns"; dig +noall +answer A $NAME @"$ns" | awk '{printf "%s ttl=%s  ", $5, $2}'; echo
done
echo "--- public resolvers (answer, remaining TTL)"
for r in 8.8.8.8 1.1.1.1 9.9.9.9; do
  printf '%s: ' "$r"; dig +noall +answer A $NAME @"$r" | awk '{printf "%s ttl=%s  ", $5, $2}'; echo
done
echo "--- this Mac: resolvers in use"
scutil --dns | awk '/nameserver\[[0-9]+\]/ {print $3}' | sort -u | tr '\n' ' '; echo
echo "--- this Mac: direct query to its first resolver (dig, bypasses the system cache)"
dig +noall +answer A $NAME | awk '{printf "%s ttl=%s  ", $5, $2}'; echo
echo "--- this Mac: system resolver with mDNSResponder cache (the iOS simulator uses this)"
dscacheutil -q host -a name $NAME | awk '/ip_address/ {print $2}' | tr '\n' ' '; echo
echo "--- Pixel emulator ($SERIAL): Android resolver (ping shows the address it resolved)"
timeout 120 $ADB shell 'ping -c 1 -W 3 mknoun.xyz 2>&1 | head -2' 2>&1
echo "--- new address $NEW: TCP ports (connect only)"
for p in 4001 443 3478; do
  printf 'tcp %s: ' $p; nc -z -G 5 -w 5 $NEW $p >/dev/null 2>&1 && echo open || echo "closed or filtered"
done
echo "--- TLS certificate served on $NEW:4001 for $NAME (the app's wss relay address)"
echo | timeout 20 openssl s_client -connect $NEW:4001 -servername $NAME 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates 2>/dev/null || echo "no certificate"
