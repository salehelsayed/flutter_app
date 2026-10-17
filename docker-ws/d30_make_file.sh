#!/bin/bash
# SE-42 D30: make the one synthetic random file (200 MB) under build/tmp/d30 and print its hash and the LAN IPv4.
#   host-run bash docker-ws/d30_make_file.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tmp/d30
F=build/tmp/d30/d30-synthetic-200MB.bin
head -c 209715200 /dev/urandom > "$F"
echo "bytes=$(stat -f %z "$F") sha256=$(shasum -a 256 "$F" | cut -c1-16) ip=$(ipconfig getifaddr en0)"
