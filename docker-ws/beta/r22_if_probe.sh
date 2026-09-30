#!/bin/bash
# Read-only: the Mac's network interfaces (index, name, flags, addresses) to pick ones that stay on this Mac.
/usr/bin/python3 -c 'import socket; print(" ".join("%d=%s" % p for p in socket.if_nameindex()))'
for i in $(ifconfig -l); do echo "--- $i"; ifconfig "$i" | head -3 | cut -c1-150; ifconfig "$i" | grep -E "inet |member|status|type" | head -4 | cut -c1-120; done
