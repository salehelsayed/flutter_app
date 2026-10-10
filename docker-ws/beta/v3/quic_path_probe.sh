#!/bin/bash
# Read-only: QUIC smoke dial from the Mac to production and to the Hetzner test relay (temp copy of the test).
export PATH="/opt/homebrew/bin:/usr/local/go/bin:$PATH"
T=$(mktemp -d /tmp/quicprobe.XXXX)
rsync -a --exclude '.git' /Volumes/CrucialX9/flutter_app/go-relay-server/ "$T/"
cd "$T" || exit 1
echo "== production mknoun.xyz =="
go test -count=1 -run '^TestQUICSmokeIdentify$' . 2>&1 | grep -aE '^(ok|FAIL|---)|identify|failed' | head -4
sed -i '' -e 's#12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g#12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM#' \
  -e 's#/dns4/mknoun.xyz/udp/4002#/dns4/2-29-62-121.sslip.io/udp/4002#' quic_smoke_test.go
echo "== hetzner 2-29-62-121.sslip.io =="
go test -count=1 -run '^TestQUICSmokeIdentify$' . 2>&1 | grep -aE '^(ok|FAIL|---)|identify|failed' | head -4
echo "== mac route/ip =="; route -n get 51.21.194.144 2>/dev/null | grep -E 'interface|gateway'
cd /; rm -rf "$T"
