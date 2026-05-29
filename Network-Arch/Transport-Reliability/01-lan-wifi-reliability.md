# LAN / Same-WiFi Delivery Reliability — Problem & Tracking Doc

Prepared on: 2026-05-29
Status: Proposed (investigation complete, no code changed)
Tracking ID: NET-REL-01

## Executive Summary

Same-WiFi 1:1 delivery is handled by a **separate Dart stack** that bypasses
go-libp2p entirely: Bonsoir (Bonjour on iOS / NSD on Android — both mDNS) for
discovery, a local plaintext `ws://` WebSocket server for transport, and a
local HTTP media server for files. This is the **only** path where we reliably
get a true direct connection today (NET-REL-02 shows cross-network DCUtR is
effectively not happening), so its reliability matters a lot.

It **is live in production** (gated by `kDisableLocalDiscovery`, which defaults
to `false`; only test builds disable it). But it has three concrete reliability
gaps: (1) the local tier only competes in the send race if the peer was
**already discovered** — there is no discover-on-send, so newly-foregrounded
peers miss the LAN path during the discovery window; (2) the discovered-peers
map has **no TTL/freshness check**, so stale entries linger until mDNS happens
to emit a "lost" event; and (3) **local media transfer is effectively dead in
production** because the media server is never wired outside tests. This doc
maps the path with evidence and proposes contained fixes.

## Document Basis

- `lib/main.dart` (~1373-1387) — production wiring of real vs disabled discovery.
- `lib/core/debug/e2e_test_mode.dart` (2-4) — `kDisableLocalDiscovery` flag.
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — mDNS advertise/discover, `_peers` map.
- `lib/core/local_discovery/local_p2p_service.dart` — facade; "requires prior discovery" guard.
- `lib/core/local_discovery/local_ws_server.dart` — WS transport, ack correlation, connection pool, `configureMediaServer`.
- `lib/core/local_discovery/local_media_server.dart` — local media HTTP server (PUT/GET, token auth, SHA-256).
- `lib/core/local_discovery/disabled_local_discovery_service.dart` — no-op used in test builds.
- `lib/core/services/p2p_service_impl.dart` (~159-179, 393-399, 2883, 2929-2946) — `start`, `restartAdvertising`, `isLocalPeer`, `sendLocalMessage`, incoming local merge.
- `lib/features/conversation/application/send_chat_message_use_case.dart` (~18-24, 303-456, 761-785) — the local-vs-direct race and budgets.
- `ios/Runner/Info.plist` (~42-51) — `NSBonjourServices` + `NSLocalNetworkUsageDescription`.
- `reset_simulators.sh` (~39, 93) — the only place `DISABLE_LOCAL_DISCOVERY=true` is set.

## Current Behavior (Evidence)

### Discovery (mDNS via Bonsoir)
- Service type `_mknoon._tcp`, name `mknoon`; advertises a TXT attribute
  `{'peerId': peerId}` and `port: wsPort` (the local WS server's bound port)
  (`bonsoir_discovery_service.dart:12-40`).
- On `discoveryServiceFound` it must explicitly `service.resolve(...)`; on
  `discoveryServiceResolved` it reads `peerId`, skips self, and stores a
  `LocalPeer{peerId, host, port, discoveredAt}` in the in-memory `_peers` map
  (`:69-85`). On `discoveryServiceLost` it removes the entry (`:93-106`).
- `printLogs: false` is set deliberately to avoid a native iOS Bonsoir logging
  crash (`:36-38`).

### Transport (local WebSocket)
- Plaintext `ws://` server bound on `InternetAddress.anyIPv4` random port
  (`local_ws_server.dart:69-81`).
- Outbound send pools a `WebSocket.connect('ws://$host:$port')`, sends JSON
  `{from, to, content, nonce}`, and awaits an ack frame matching `nonce`
  (`:258-338`, `:409-431`). Connections are pooled per-peer and idle-closed
  after 60s (`:449-470`).
- **The `content` is the already-built ML-KEM v2 encrypted envelope** (from
  `MessagePayload.buildEncryptedEnvelope`, `send_chat_message_use_case.dart:268-275`),
  so message *contents* stay E2E-encrypted. Only the WS framing metadata
  (`from`/`to` peer IDs, nonce) is in clear on the LAN.

### Production enablement (definitive)
- `const bool kDisableLocalDiscovery = bool.fromEnvironment('DISABLE_LOCAL_DISCOVERY');`
  defaults to **false** (`e2e_test_mode.dart:2-4`).
- `main.dart:1373`: `final localDiscovery = kDisableLocalDiscovery ? DisabledLocalDiscoveryService() : BonsoirDiscoveryService();`
- The only place `DISABLE_LOCAL_DISCOVERY=true` is set is `reset_simulators.sh:39`
  (test simulators). No release build sets it. **→ The local text path runs in production.**
- `LocalP2PService.start()` runs at runtime (`p2p_service_impl.dart:393-399`),
  re-advertises on foreground (`:2883` `restartAdvertising`), and incoming local
  messages merge into the unified stream tagged `transport:'wifi'` (`:168-179`).

### The send race (`send_chat_message_use_case.dart`)
- Fast-path: reuse an existing connection if already connected (`~303-366`).
- Otherwise a **true parallel first-wins `Completer` race** (`~368-456`):
  - Local future added **only if `p2pService.isLocalPeer(targetPeerId)` is true**
    (`:376`), budget `interactiveLocalBudget = 1500ms` (`:18`).
  - Direct future always added, budget `interactiveDirectBudget = 2s` (`:21`).
  - Both start simultaneously; first success wins. No head-start/grace window.
- Sequential tail on race failure: relay-probe (`_tryRelayProbeSend`) then inbox
  store-and-forward (`interactiveInboxBudget = 3s`). (Detailed in NET-REL-05.)

### Scope note (added after QA)
The local-first `sendLocalMessage` pattern is **not** used only by chat text. The
same LAN path also carries introductions (`introduction_outbound_delivery.dart:482`),
contact requests (`send_contact_request_use_case.dart:238`), message
delete/tombstones (`delete_message_use_case.dart:625`), and share-batch delivery
(`share_batch_delivery_coordinator.dart:281`). All remain 1:1 (groups do **not**
use the LAN path — confirmed: no `sendLocalMessage`/`isLocalPeer` in
`lib/features/groups`), so any reliability fix here also affects these control
flows.

## Problems Identified

### P1 — Local tier requires prior discovery (no discover-on-send)
The race only adds the local attempt when `isLocalPeer(targetPeerId)` is already
true (`send_chat_message_use_case.dart:376`), and
`LocalP2PService.sendMessage` returns `false` immediately if
`_discovery.getLocalPeer(peerId) == null` (`local_p2p_service.dart:90-91`).
There is **no on-demand discovery at send time** — it relies on the background
mDNS map being already populated.
**Impact:** Two users who just opened the app on the same WiFi will not use the
LAN path until Bonsoir has resolved each other (resolve is a multi-step
found→resolve→resolved flow). During that window, messages go over relay even
though both are on the same network — the exact case we most want to be fast.

### P2 — No TTL / freshness guard on the discovered-peers map
`LocalPeer.discoveredAt` is recorded but **never checked for expiry**
(`bonsoir_discovery_service.dart:79-85`). Entries are removed only on
`discoveryServiceLost` (`:93-106`), which mDNS may emit late or not at all when
a peer drops off WiFi abruptly.
**Impact:** A stale `host:port` causes the WS connect/ack to fail, costing up to
the full 1500ms local budget for a peer that is no longer reachable. It is not a
correctness bug (direct runs in parallel and carries the message), but it is
wasted latency on every send to a since-departed peer and pollutes any
"is on LAN" signal.

### P3 — Local media transfer fails in production (two compounding gaps)
**Correction after QA:** production is **not** missing the local-media *send* —
`conversation_wired.dart:1766-1775` (images) and `:2639-2648` (voice) call
`p2pService.sendLocalMedia(...)` whenever `isLocalPeer` is true, with relay CDN
fallback at `:1805-1825`. The capability is *reached* but *fails* for two
compounding reasons on the receiver:
1. `LocalWsServer.configureMediaServer(...)` is never called in `lib/` (only in
   tests), so the receiver has no media server: inbound `PUT /media/<id>` → 404
   (`local_ws_server.dart:134-140`) and `_handleMediaOffer` replies
   `media_offer_rejected / media_not_supported` (`:214-227`).
2. Even if the media server were wired, **nothing in production subscribes to
   `mediaReadyStream`** — it is exposed via `LocalP2PService:79` but
   `P2PServiceImpl` never listens to it (contrast `localMessageStream` merged at
   `p2p_service_impl.dart:168`). So inbound local media would never reach the
   incoming pipeline.
**Impact:** Local file/image transfer silently falls back to the relay CDN path
even when both peers are on the same WiFi. **Fixing P3 requires BOTH wiring
`configureMediaServer` AND adding a `mediaReadyStream` consumer** — not just the
former. Media has test-only coverage (`test/core/local_discovery/local_media_server_test.dart`,
`local_media_integration_test.dart`, `integration_test/wifi_transport_test.dart`),
all of which wire the media server themselves; there is no production-path test.

### P4 — iOS Local Network permission can silently kill the path
iOS requires Local Network permission; `NSBonjourServices = [_mknoon._tcp]` and
`NSLocalNetworkUsageDescription` are present (`ios/Runner/Info.plist:42-51`).
But if the user denies the prompt, mDNS silently yields zero peers and the local
tier is permanently skipped with no user-visible signal or recovery path. No
permission-status API is consulted anywhere in the code.
**Android note (added after QA):** Android needs `CHANGE_WIFI_MULTICAST_STATE`
for mDNS/NSD, and it **is** present (`android/app/src/main/AndroidManifest.xml:2`,
`minSdk = 24`). Android has no runtime Local-Network prompt equivalent, so the
"silent denial" failure mode is iOS-specific.
**Impact:** A subset of iOS users get no LAN path and no indication why; we have
no telemetry to detect this (see NET-REL-04).

### P5 — Plaintext `ws://` metadata exposure on LAN
The WS transport is unencrypted; while message bodies are E2E-encrypted, the
`from`/`to` peer IDs and nonces are visible to anyone sniffing the LAN
(`local_ws_server.dart:280-309`).
**Impact:** Minor metadata leak on shared/hostile WiFi. Worth a documented
decision (accept vs. add transport encryption) rather than leaving implicit.

### P6 — No freshness/identity binding between mDNS TXT peerId and the connection
The local path trusts the advertised TXT `peerId`; the actual delivery
authenticity rests on the inner E2E envelope, but the LAN routing layer itself
has no challenge.
**Impact:** Low (E2E protects content), but worth noting for the security model.

## Impact

The LAN path is our only reliable direct transport (NET-REL-02). When it works,
it is the fastest, cheapest, and most private channel — no relay hop, no relay
bandwidth, stays on the local network. Every gap above pushes traffic that
*could* be LAN-local onto relay instead, increasing latency and relay cost and
undercutting the "seamless when nearby" experience. P3 in particular means an
entire media use case (sharing photos with someone in the same room) never uses
the fast path.

## Proposed Directions (options, NOT implementation)

**P1 — discover-on-send / faster discovery**
- *Option A:* Keep continuous background discovery but add a short
  discover-on-send probe: when sending to a peer not yet in `_peers`, kick a
  bounded mDNS resolve and let it join the race if it resolves within the local
  budget. Tradeoff: adds a little send-time work; bounded by the existing 1500ms.
- *Option B:* Warm discovery earlier/more aggressively on foreground and on
  conversation-open (we already have `restartAdvertising`). Tradeoff: more mDNS
  chatter/battery; simpler than A.
- *Option C:* Pre-resolve known contacts' advertised services proactively so the
  map is populated before the user sends. Tradeoff: continuous resolve cost.

**P2 — TTL / freshness**
- Add a TTL check on `LocalPeer.discoveredAt` (e.g. treat entries older than
  N seconds as stale and skip them or re-resolve before use), plus periodic
  re-resolution to refresh `host:port`. Tradeoff: choosing N (too low → drop
  valid peers; too high → keep stale ones). Pair with a fast connect timeout so
  a stale entry fails quickly rather than burning the full budget.

**P3 — local media in production (two-part fix)**
- (a) Wire `configureMediaServer(...)` into the production `LocalWsServer`
  construction in `main.dart`/`p2p_service_impl.dart`, gated by the same
  `kDisableLocalDiscovery` flag; AND (b) subscribe to `mediaReadyStream` in
  `P2PServiceImpl` and merge inbound local media into the incoming pipeline
  (mirroring how `localMessageStream` is merged at `p2p_service_impl.dart:168`).
  The send side already fires (`conversation_wired.dart`), so no send change is
  needed. Tradeoff: must add production-path tests and verify the SHA-256
  integrity + token-auth path under real conditions before enabling.

**P4 — permission visibility**
- Detect denied Local Network permission and surface a one-time, non-blocking
  hint; record a local diagnostic flag (NET-REL-04) so we can measure how often
  the LAN path is unavailable.

**P5 — metadata exposure**
- Decision doc: accept (E2E protects content) or add lightweight transport
  encryption (e.g. Noise over the local WS). Likely accept + document.

## Acceptance Criteria / How We'll Know It's Fixed

1. When two devices are on the same WiFi and both have the app foregrounded,
   the first message between them uses the local (`transport:'wifi'`) path
   within a bounded discovery window (target: < ~2s after both foreground),
   measurable via NET-REL-04 transport census.
2. Sends to a peer that has left WiFi do not waste the full local budget — stale
   entries are skipped/expired (assert via unit test on TTL logic).
3. Same-LAN media transfers use the local media server (observable: media bytes
   not seen at the relay for same-LAN pairs) with relay CDN fallback intact.
4. Denied iOS Local Network permission is detected and recorded; no infinite
   silent skip.
5. No regression: cross-network sends are unaffected; the parallel direct path
   still carries messages whenever local is unavailable.

## Test Plan

See **NET-REL-06** for the harness inventory and the negative-control principle.
The hardest requirement here: **prove the message used the LAN/`local` path, not
relay.** Today nothing does this end-to-end (`wifi_transport_test.dart` tests the
WS server in isolation; `reset_simulators.sh` *disables* discovery), so item (I3)
below is a capability we must BUILD.

### Unit (host, deterministic — exact transport assertion)
Pattern: extend `test/features/conversation/application/send_chat_message_use_case_test.dart`
with `FakeP2PService`/`FakeP2PNetwork` (`test/shared/fakes/fake_p2p_network.dart`).
- **U1 (happy):** peer in `localPeers` → assert `message.transport == 'local'`,
  `localSendCallCount == 1`, `probeRelayCallCount == 0`. (Mirrors existing test at ~1197.)
- **U2 (TTL — unhappy/degraded):** `LocalPeer.discoveredAt` older than N is treated
  stale → local future is NOT added (or re-resolves first); assert it does not burn
  the full 1500ms before direct carries it.
- **U3 (discover-on-send):** sending to an unknown-but-LAN-present peer triggers a
  bounded resolve and the local future joins the race within budget.
- **U4 (media wiring — SEQUENCE AFTER P3 IMPL):** the production receive half does not
  exist yet (no `configureMediaServer` call, no `mediaReadyStream` consumer), so U4 can
  only be written *after* P3 is implemented. Then: with `configureMediaServer` wired AND
  a `mediaReadyStream` consumer, inbound `PUT/GET` serves, enforces token-auth +
  declared-size + streaming SHA-256, and the received media reaches the incoming
  pipeline. (Port `test/core/local_discovery/local_media_server_test.dart` to a
  production-wiring test.)
- **NEGATIVE CONTROL U-N1:** same scenario but peer NOT in `localPeers` and LAN send
  forced to fail → assert `message.transport != 'local'` (it must be `direct`/`relay`/
  `inbox`) and `localSendCallCount == 0` won the race. This is what proves U1 isn't
  hard-coding `local`.
- **NEGATIVE CONTROL U-N2:** media with NO `mediaReadyStream` consumer → assert
  inbound media does NOT surface (reproduces today's P3 bug), so a future regression
  that drops the consumer is caught.

### Integration (Dart — LAN/WS mechanism)
- **I1 (happy):** `integration_test/wifi_transport_test.dart`-style two `LocalWsServer`
  over loopback: send text + media, assert ack + SHA-256. (Exists; keep, and add the
  media production-wiring variant.) Also build on `test/core/local_discovery/local_p2p_service_test.dart`
  — the closest existing real-stack integration (real `LocalWsServer` + real
  `LocalP2PService` with a fake discovery), which the plan previously omitted.
- **I2 (unhappy):** silent server never acks → `sendMessage` returns false within the
  5s ack timeout; stale `host:port` → connect fails fast; max-inbound rejection +
  recovery. (Several exist in `wifi_transport_test.dart` F2/F8/F9 — extend.)
- **Note:** `BonsoirDiscoveryService` is NEVER instantiated in any test (only in
  `main.dart`). All current LAN tests use `FakeLocalDiscoveryService`, so real mDNS
  discovery (and P1/P2) is entirely uncovered today.

### Integration (device / real-network — the capability to BUILD)
- **I3 (happy, MUST BUILD):** two real app instances on the **same LAN** with mDNS
  enabled AND relay reachable, run the real `sendChatMessage` race, and assert the
  receiver stored `transport == 'local'`. Without this, "same-WiFi beats relay" is
  unproven. Do NOT use the `direct||relay||inbox` set-acceptance here — pin `local`.
  **Environment constraint (verified):** the standard 4-simulator harness CANNOT run
  this — iOS sims share the host's single Bonjour/mDNS stack and every sim run sets
  `DISABLE_LOCAL_DISCOVERY=true` for that reason. I3 requires **two real physical iOS
  devices on the same WiFi** (or a discovery-enabled build variant), not simulators.
- **I3 NEGATIVE CONTROL:** identical setup but LAN path blocked (relay reachable) →
  assert `transport != 'local'`. If both I3 and its control report `local`, the
  assertion is meaningless.
- **I4 (unhappy — leave WiFi):** start on LAN (`local`), then one device drops WiFi →
  next message falls back to relay/inbox with no user-visible failure; assert the
  transport label changes accordingly.

### Permission / platform matrix (manual + automated where possible)
- **P-iOS:** allow vs **deny** Local Network → on deny, discovery yields zero peers,
  the race silently uses direct/relay (no crash, no hang), and a diagnostic flag is
  recorded (NET-REL-04). NEGATIVE CONTROL: allow → `local` is reachable.
- **P-Android:** NSD works with `CHANGE_WIFI_MULTICAST_STATE`; no runtime prompt.
- **P-lifecycle:** background→foreground recovery via `restartAdvertising` re-populates
  the peer map.

### Simulation / gates
- Place I1/I2 in the `transport` gate (`scripts/run_test_gates.sh`); I3 + controls in
  the reliability sim (`run_reliability_simulations.sh`) once the LAN-pinning harness
  exists. Note: `reset_simulators.sh` sets `DISABLE_LOCAL_DISCOVERY=true` — I3 needs a
  variant that leaves discovery ON.

## Open Questions

1. What TTL value balances dropping departed peers vs. keeping valid ones on
   typical home/office WiFi?
2. Should discover-on-send be always-on or only for peers we have an open
   conversation with (battery vs. coverage)?
3. For local media, do we reuse the relay CDN's encryption/blob model or a
   LAN-specific one? What is the fallback trigger ordering?
4. Is the plaintext `ws://` metadata exposure acceptable for the threat model,
   or do we add Noise/local TLS?
5. Should the LAN path also serve **group** messages on the same network, or
   stay 1:1-only? (Groups currently use libp2p direct-dial; see NET-REL-03.)

## References

- Code anchors listed in Document Basis above.
- Cross-ref **NET-REL-02** (why LAN is the only reliable direct path today),
  **NET-REL-04** (transport census needed to measure LAN hit-rate and permission
  denials), **NET-REL-05** (the race/ladder this tier participates in).
