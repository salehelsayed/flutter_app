# Mknoon IPv6 and Happy Eyeballs activation — 2026-09-07

## Source baseline and scope

The pending release-build changes and notification investigations were committed
as `298934482` on `feat/audio-prd-implementation`. The worktree was clean before
creating `feat/ipv6-happy-eyeballs`.

This change enables native IPv6 on Mknoon's relay and gives the existing
go-libp2p Happy Eyeballs dialer complete address sets. It does not change the
Apple/iOS connection that delivers APNs notifications.

## Live activation

- Relay IPv4 retained: `13.60.15.36`.
- Relay IPv6 assigned: `2a05:d016:c4d:7100:ec85:94ed:b90d:e20`.
- AWS VPC IPv6 allocation, one subnet allocation, ENI address and internet
  gateway route were added. Existing IPv4 rules/routes were preserved.
- IPv6 ingress permits the application TCP ports 80, 443, 4001 and 4005,
  UDP 4002, and ICMPv6. Internal WebSocket port 4000 and monitoring ports were
  not added to public IPv6 ingress. Existing TURN rules were preserved.
- `/etc/netplan/99-mknoon-ipv6.yaml` enables DHCPv6 and router advertisements.
  The original IPv4 netplan file was unchanged; fresh IPv4 SSH and DHCPv6
  renewal were verified. The temporary network rollback timer was canceled.
- Relay `v1.10.6` was deployed. Binary SHA-256:
  `d933c15e8dfca516de560312640bab137016215d6f59a5c7145207afd200b6d9`.
- The existing relay identity and application environment were retained.
  `/etc/mknoon/relay-ipv6.env` adds `RELAY_SERVER_IP6` and
  `RELAY_SERVER_DNS_IPV6=true`, loaded by the systemd drop-in
  `/etc/systemd/system/relay-server.service.d/60-ipv6.conf`.
- GoDaddy AAAA for `mknoun.xyz` points to the IPv6 address, TTL 600 seconds.
  The save was requested at 19:51:34 UTC and verified on both authoritative
  nameservers. The existing A record remains unchanged.
- Native IPv6 listeners were verified before DNS publication. DNS-based IPv6
  advertisements were enabled at 19:55:16 UTC after DNS verification.

## Code behavior

The relay opts into IPv6 through explicit configuration. It binds the assigned
address for native TCP, WebSocket and QUIC, and rejects activation if a requested
IPv6 listener did not bind. IPv4 remains available. DNS IPv6 advertisements are
separately configurable so deployment can verify reachability before publication.

The client already had IPv4/IPv6 listeners and `/dns/` defaults. Relay warmup
previously split addresses into sequential calls with a full timeout for each.
It now passes the complete same-peer address set to one `Connect` under one
deadline. The pinned go-libp2p v0.39.1 ranker races IPv6 and IPv4, including
QUIC, TCP and WSS. Disabling multi-relay routing retains all addresses for the
first valid relay peer.

Cold relay operations also retain complete address sets. Explicit bounded media
protocol retries preserve the original source-peer and exact-ACK checks. Only
the first attempt may dial; later retries use an existing authenticated
connection with `WithNoDial`, preventing another full connection timeout.

## Live connection evidence

Every successful probe authenticated the expected relay peer and received a
libp2p ping response. Measurements are observations on this Mac/network, not
latency guarantees for other environments.

| Transport | IPv4 connect | IPv6 connect |
| --- | ---: | ---: |
| TCP 4005 | 175 ms | 156 ms |
| QUIC 4002 | 97 ms | 89 ms |
| TLS WebSocket 4001 | 279 ms | 238 ms |

An unreachable IPv6 QUIC candidate alone timed out after 5,001 ms. Providing
that candidate together with the working IPv4 QUIC address connected over IPv4
in 555 ms. No router or firewall rules were changed for this probe.

After publication, a fresh DNS-based race selected IPv6 QUIC in 332 ms.
macOS initially retained its earlier negative AAAA cache while authoritative
DNS already returned the new record. That cache refreshed naturally: the normal
native resolver subsequently connected through `/dns6/` WSS in 252 ms.
No global DNS/cache settings were changed.

## Verification

- Relay complete Go suite passed with Go 1.25.0: 44.677 seconds.
- Relay focused race tests passed, including all six loopback transport/family
  combinations and the existing finite-resource-limit sentinel.
- Flutter bridge suite passed: 73 tests, Flutter 3.47.2.
- Native focused regression suite passed: complete candidates, one warmup
  deadline, ranker timing, IPv6-only loopback, stalled IPv6-to-IPv4 handshake
  fallback, no-redial retries and existing media-custody proof sentinels.
- iOS app/NSE frameworks and Android AAR were rebuilt and passed their existing
  binding-verification scripts with Go 1.25.0.
- The complete native module run finished with two obsolete deadline-test
  cardinality assertions failing; all other tests/packages passed. Only those
  test expectations were updated: one peer keeps both addresses in one attempt,
  while two peers still produce two attempts. All original deadline and stream
  cleanup checks remain. The complete R3 deadline group plus IPv6/media
  preservation tests then passed (13.847 seconds). The complete module was not
  rerun after this test-only correction; production/binding source was unchanged.
- Independent review identified the media retry regression during development;
  the unchanged custody ACK test demonstrated the failure and passed after the
  repair. The repair review found no blocker.

No phone app was reinstalled during this activation. The new client changes
require a rebuilt app to reach installed devices.

## Recovery and artifacts

The previous executable is retained at
`/usr/local/bin/relay-server.before-ipv6-20260907`, SHA-256
`746107033681ea47c8d02d9869befa6b5e31ff0f550e3979a63e188d0abf3f94`.
Restoring it and removing only the new systemd drop-in/environment file restores
the prior application deployment. Remove only the added AAAA record when
reverting public IPv6 discovery, retaining the A record. DNS caches can retain
published records until expiry, so keep the IPv6 path reachable during that
transition when feasible.

Detailed before/after AWS receipts, exact infrastructure reversal commands,
deployment script, test/build logs and probe results are in
`build/ipv6-happy-eyeballs/`. In particular:

- `activation-summary.json`
- `infra/README.md` and `infra/rollback-commands.md`
- `deployment.log` and `deploy-relay.sh`
- `ipv4-*.json`, `ipv6-*.json`, `fallback.json`
- `dns6-wss-native-resolver-final.json`, `default-dns-race-published.json`
- `relay-tests.log`, `ios-bindings.log`, `android-bindings.log`
- `native-full-module.log`, `native-final-regressions.log`

The build directory is local diagnostic evidence and is not included in Git.
