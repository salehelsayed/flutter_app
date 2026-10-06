#!/bin/bash
# Read-only: the Mac's public IPv4 and any VPN/proxy interfaces.
curl -s -4 --max-time 8 https://ifconfig.me; echo
ifconfig | grep -E "^(utun|ppp|ipsec|tun)[0-9]" | cut -d: -f1 | tr '\n' ' '; echo
scutil --nc list 2>/dev/null | grep -i connected | head -3
