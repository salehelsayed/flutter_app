#!/bin/bash
# Read-only reachability of the production relay from the Mac: DNS, TCP ports, TLS on 4001, UDP probe.
H=mknoun.xyz
echo "dns: $(dig +short $H | tr '\n' ' ')"
for p in 4001 4005 443; do r=$(nc -z -G 5 $H $p 2>&1 && echo open || echo closed); echo "tcp $p: $r"; done
echo "tls 4001: $(echo | timeout 8 openssl s_client -connect $H:4001 -servername $H 2>/dev/null | grep -m1 -E 'Verify return|subject=' )"
echo "udp 4002 nc: $(echo x | nc -u -w 3 $H 4002 >/dev/null 2>&1; echo rc=$?)"
