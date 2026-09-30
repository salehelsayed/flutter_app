#!/bin/bash
# Read-only: the relay's IPv6 (AAAA) record from the authoritative servers and this
# Mac's resolvers, and whether the IPv6 address answers on the relay/TURN ports.
NAME=mknoun.xyz
echo "--- AAAA at the authoritative name servers"
for ns in $(dig +short NS $NAME); do printf '%s: ' "$ns"; dig +noall +answer AAAA $NAME @"$ns" | awk '{printf "%s ttl=%s  ", $5, $2}'; echo; done
echo "--- AAAA at public resolvers"
for r in 8.8.8.8 1.1.1.1; do printf '%s: ' "$r"; dig +noall +answer AAAA $NAME @"$r" | awk '{printf "%s ttl=%s  ", $5, $2}'; echo; done
echo "--- this Mac's system cache (A and AAAA)"
dscacheutil -q host -a name $NAME | awk '/address/ {print $1, $2}' | tr '\n' ' '; echo
V6=$(dig +short AAAA $NAME @8.8.8.8 | head -1)
echo "--- IPv6 $V6: TCP ports (connect only)"
for p in 4001 443 3478; do
  printf 'tcp %s: ' $p; nc -6 -z -G 5 -w 5 "$V6" $p >/dev/null 2>&1 && echo open || echo "closed or filtered"
done
echo "--- TLS certificate on [$V6]:4001 for $NAME"
echo | timeout 20 openssl s_client -connect "[$V6]:4001" -servername $NAME 2>/dev/null \
  | openssl x509 -noout -subject -dates 2>/dev/null || echo "no certificate"
