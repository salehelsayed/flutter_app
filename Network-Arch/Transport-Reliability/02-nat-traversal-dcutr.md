# NAT Traversal & DCUtR Hole-Punching — Problem & Tracking Doc

Prepared on: 2026-05-29
Status: Evidence accepted; product decision baseline-gated (Go tracer, Dart
aggregate diagnostics, and relay-only/no-upgrade evidence present; production
reachability unchanged; production mobile DCUtR unproven)
Tracking ID: NET-REL-02

## Executive Summary

`libp2p.EnableHolePunching()` is configured (`go-mknoon/node/node.go`) with a
Go hole-punch tracer seam in the current working tree, and Dart now has
aggregate, privacy-safe diagnostics for accepted hole-punch and upgrade events.
In principle this lets two NAT'd peers upgrade a relayed connection into a
direct one and lets the app observe attempts, successes, failures, and
relay-to-direct upgrade events.
**In practice, production DCUtR upgrades are still not triggered by default and
are not proven by local loopback, LAN, simulator, or label-mapping evidence**,
for two reasons:

1. **It's self-suppressed.** `libp2p.ForceReachabilityPrivate()`
   (`node.go:315`) hard-pins the host as private for its entire lifetime, so it
   never advertises potentially-reachable addresses. DCUtR coordination is
   unlikely to even initiate without observed-address discovery.
2. **It's physically infeasible for the common case.** Two mobile phones on
   cellular data are typically both behind carrier-grade / symmetric NAT — the
   classic configuration where hole-punching cannot succeed regardless of
   protocol.

The current Go/Dart evidence observes libp2p hole-punch outcomes and surfaces
them as aggregate diagnostics without changing connection policy, but it does
not by itself prove that production mobile pairs will upgrade.
`classifyStreamTransport` still samples direct/relay per-send only for labeling,
not behavior. The old missing-transport default-to-`relay` bias has been
replaced by `unknown`; that improves measurement honesty, but it is still not a
valid production mobile DCUtR harvest.

The honest conclusion remains evidence-gated: for many cross-network
mobile-to-mobile pairs, **relay is the realistic steady state**, and the
"direct" transport we occasionally observe can come from the LAN pre-relay
address dial (NET-REL-01), not DCUtR. A production mobile relay-to-direct DCUtR
success must not be claimed until a valid real-device, discovery-enabled,
debug-mode baseline harvest proves it. This doc documents the feasibility
envelope precisely so we can decide whether chasing DCUtR is worth it, or
whether effort belongs in LAN (NET-REL-01) and relay quality instead.

go-libp2p version in use: **v0.39.1** (`go-mknoon/go.mod`).

## Document Basis

- `go-mknoon/node/node.go` — host options (`:305-329`), event subscription
  (`:365-368`), `classifyStreamTransport` (`:111-124`), `watchConnectionEvents`
  (`:1612-1690`), send path + `WithAllowLimitedConn` (`:1069,1104,1164,1234`),
  self-heal `recoverPeerForSend` (`:1212-1222`), `connectionInfo.Limited` field
  (`:103`, `:1631-1648`).
- `go-mknoon/node/config.go` — relay multiaddrs, AutoRelay cadences.
- `go-mknoon/node/pubsub.go` — the actual source of observed "direct":
  `connectGroupPeerPreferDirect` (defined at `:1878`) and
  `dialKnownGroupMembersDirectOnly` (`:2404-2486`, calls the former).
- `lib/core/services/p2p_service_impl.dart` and
  `lib/core/debug/transport_metrics.dart` — `transport` consumption, aggregate
  counters, accepted upgrade inference, and `unknown` fallback for missing or
  unrecognized inbound labels (note: dir is `core/services`).
- `go-relay-server/main.go` — circuit-relay-v2 only. The host advertises the
  reservation/hop protocol `ProtoIDv2Hop = "/libp2p/circuit/relay/0.2.0/hop"`
  via `libp2p.EnableRelayService(...)` (`main.go:72`); its listen addresses are
  TCP / WS / QUIC only (`main.go:64-67`) — no WebRTC listen address.
- **R1 build-graph footnote (verified 2026-05-29, NET-REL-02 Option A).** The
  pion stack is **not directly imported by any relay source file** (`grep
  -rn "pion/" go-relay-server/*.go` → no hits), but it IS reachable in the
  transitive build graph via go-libp2p's default WebRTC transport, NOT via any
  relay code path. Confirmed with `cd go-relay-server && go mod why`:
  - `go mod why github.com/pion/webrtc/v3` →
    `relay-server → go-libp2p → .../p2p/transport/webrtc → pion/webrtc/v3`
  - `go mod why github.com/pion/stun` / `pion/turn/v2` / `pion/ice/v2` →
    all route `relay-server → go-libp2p → .../p2p/transport/webrtc[/udpmux] →
    pion/{stun,ice/v2,turn/v2}`.
  i.e. every pion dependency is pulled by go-libp2p's bundled WebRTC transport,
  never by relay-server source. The relay neither imports nor listens on
  WebRTC and provides no STUN/TURN service — circuit-relay-v2 (ProtoIDv2Hop) +
  store-and-forward inbox only. This is a build-graph fact recorded here per
  the R1 directive, NOT a runtime assertion.
- `go-mknoon/node/relay_session.go` — relay reservation health (relay is steady state).
- `go-mknoon/integration/relay_test.go` — direct dial falls back to relay; no upgrade assertion.
- `go-mknoon/node/transport_label_test.go` — only checks the label fn on stub conns.
- `go-mknoon/go.mod` — go-libp2p v0.39.1, pubsub v0.15.0 (vendored).

## Current Behavior (Evidence)

- **Hole punching enabled and observed at the Go node seam:**
  `EnableHolePunching()` is wired with `holepunch.WithTracer`. Production uses
  the real emitting tracer; tests may inject a collector before `Start()`.
  The tracer emits `holepunch:attempt`, `holepunch:success`,
  `holepunch:failure`, and `transport:upgraded`.
- **Dart aggregate diagnostics consume the accepted seam:** the bridge forwards
  sanitized hole-punch and upgrade events, `TransportMetrics` records aggregate
  attempt/success/failure and relay-to-direct upgrade counters, and settings
  diagnostics surface aggregate counts without message content, full peer IDs,
  conversation IDs, or raw multiaddrs.
- **Connection recording is corrected only on tracer success:**
  `watchConnectionEvents` records `conns[0].RemoteMultiaddr()` and
  `conns[0].Stat().Limited` when a peer becomes `Connected`/`Limited`. libp2p
  does **not** re-fire `EvtPeerConnectednessChanged` when a relayed `Limited`
  conn is upgraded to direct (the peer was already Connected), so the tracer's
  successful `EndHolePunchEvt` path now clears stale `Limited` state and
  best-effort re-samples a non-circuit address.
- **Transport label is telemetry, not control:** `classifyStreamTransport`
  inspects one stream's multiaddrs for `/p2p-circuit` → `"relay"` else
  `"direct"` (`node.go:111-124`), called at send (`:1308`) and inbound (`:1510`)
  only. Nothing consumes the label to change behavior.
- **Sends prefer no upgrade:** every dial/send sets
  `network.WithAllowLimitedConn(...)` (`node.go:1069,1104,1164,1234`) — happy to
  ride relay. Self-heal `recoverPeerForSend` re-dials via the relay circuit
  (`node.go:1212-1222`), never a direct address.
- **"Direct" actually comes from LAN dialing:** the group path dials
  already-known non-circuit (LAN) addresses before relay
  (`pubsub.go:2401-2486`, events `pre_relay_direct_dial` /
  `known_member_pre_relay_direct_success`). That is direct-*address* dialing,
  not DCUtR across NAT.
- **AutoRelay tuned to stay on relay:** `EnableAutoRelayWithStaticRelays(...,
  WithBootDelay(0), WithBackoff(~1s), WithMinInterval(~1s))` (`node.go:320-327`)
  with the explicit comment that `ForceReachabilityPrivate` tells AutoRelay to
  always seek relay reservations (`node.go:306-307`).
- **Tests distinguish mapping, feasibility, and relay-only safety:**
  `transport_label_test.go` checks multiaddr label mapping only and warns that
  it is not upgrade proof. Tracer unit tests cover attempts, successes,
  failures, `transport:upgraded`, and stale limited-state repair. The loopback
  feasibility test may skip when DCUtR does not materialize. The relay-only
  negative control is the production-shaped safety case.

## DCUTR-004 Closure Status

Recorded: 2026-05-30 CEST

- Closed as stable evidence: Go tracer/event contract, Dart aggregate
  diagnostics/counters, missing inbound `unknown` behavior, relay-only
  no-upgrade negative control, and relay failover/recovery liveness without
  manufactured upgrade events.
- Still evidence-gated: production mobile relay-to-direct DCUtR success. No
  concrete repo-local real-device, discovery-enabled, debug-mode
  `baselineReport()`/decision-gate artifact was found that proves a production
  mobile upgrade.
- Proof boundaries: simulator, CLI, loopback, LAN direct, and classifier-label
  evidence are liveness, recovery, protocol-feasibility, or mapping evidence.
  They are not physical NAT traversal proof.
- Residual carried forward: DCUTR-003 `run_transport_e2e.dart` was attempted
  twice; Flutter reported `33/33 passed`; the orchestrator downloaded the
  69-byte blob; the external summary was `29/30 passed` with
  `messageSeen=false`, `attachmentReferenced=false`, and `blobInList=false`.
  This remains an external orchestrator media-metadata residual unless concrete
  later evidence ties it to relay-only/no-upgrade behavior.

## Problems Identified

**P1 — Hole-punch outcomes are now observed, but only as evidence.** The
current working tree installs a hole-punch tracer, accepted Go events, and Dart
aggregate metrics/reporting. This remains observation only until a valid
baseline harvest is captured. *Impact:* production reachability behavior is
unchanged; measurement is possible, but product decisions remain evidence-gated.

**P2 — Upgrades are never triggered or awaited.** Sends ride whatever connection
exists; self-heal re-dials relay. *Impact:* even where DCUtR could succeed, we
apply no pressure toward it.

**P3 — `ForceReachabilityPrivate()` suppresses the prerequisite.** It prevents
advertising observed/reachable addresses, which DCUtR coordination needs.
*Impact:* the one enabled mechanism is configured against itself.

**P4 — Physical infeasibility for cellular CGNAT.** Two phones behind
symmetric/carrier-grade NAT cannot hole-punch. *Impact:* even with everything
else fixed, a large fraction of cross-network pairs will never go direct.

**P5 — Baseline harvest still missing.** The direct/relay/wifi/inbox/unknown
census and hole-punch counters now exist as aggregate diagnostics, and missing
inbound transport falls back to `unknown`. The remaining gap is that no valid
real-device, discovery-enabled, debug-mode baseline harvest has been captured
for the production mobile relay-to-direct question. *Impact:* we still cannot
quantify real cross-network mobile DCUtR success or use the decision gate to
reorder NET-REL-01/02/03/05.

## NAT Traversal Feasibility Analysis

**How DCUtR works (libp2p):** Peers A and B are both behind NAT and connected
via a relay. Each learns its own observed public address (via Identify/AutoNAT)
and, coordinated over the relay, they perform a synchronized simultaneous-open
("hole punch") so each NAT creates a mapping the other can use. On success,
libp2p migrates new streams to the direct connection and closes the relay
connection after a grace period.

**Prerequisites that must all hold:**
- Each peer must discover a usable observed public address — suppressed today by
  `ForceReachabilityPrivate()`.
- The NATs must be **endpoint-independent** (full-cone / address-restricted),
  so the port a peer observes is the same port the remote can reach.
- Reasonably synchronized timing (the relay coordinates this).

**NAT-type outcome matrix (mobile-to-mobile):**

| Peer A | Peer B | DCUtR likely? |
|--------|--------|---------------|
| Same LAN | Same LAN | N/A — LAN direct dial wins first (NET-REL-01), no hole punch needed |
| WiFi, cone NAT | WiFi, cone NAT | **Yes** (favorable) |
| WiFi, cone NAT | Cellular | Maybe — depends on carrier NAT type |
| Cellular CGNAT | Cellular CGNAT | **No** — symmetric NAT defeats hole punching |
| Symmetric NAT | Anything | **No / unreliable** |

**QUIC vs TCP:** go-libp2p supports hole punching over both QUIC and TCP; QUIC
(UDP) is generally friendlier to traversal. But **symmetric NAT defeats both** —
the port mapping is per-destination, so the observed port is useless to a third
party. This is the dominant failure mode for carrier data.

**Bottom line:** the realistic yield of DCUtR for this app is concentrated on
**WiFi-to-WiFi with cone NATs**. For the very common "two phones on cellular"
case, relay is the correct and only steady state. There is no TURN-style media
relay alternative configured beyond circuit-relay-v2 (the relay server provides
circuit relay + store-and-forward inbox; it is not a STUN/TURN server).

## Impact

- **Latency & cost:** cross-network 1:1 traffic traverses `mknoun.xyz` for the
  conversation lifetime, adding a relay round-trip and consuming relay egress.
- **Decision risk:** without a valid baseline harvest, we might invest in DCUtR
  plumbing (NET-REL-03) that yields little because P4 dominates our actual user
  population. Measuring first prevents wasted effort.

## Proposed Directions (options, NOT implementation)

**Option A — Instrument first (cheap, do regardless).** The Go tracer and Dart
aggregate diagnostics are accepted evidence in the current working tree:
`holepunch.WithTracer` observes attempts/outcomes, and relay-to-direct
transition telemetry is available to NET-REL-04. This tells us whether upgrades
ever happen and on what fraction of pairs **before** we change connection
policy. The remaining Option A work is harvesting a valid baseline, not changing
routing policy.

**Option B — Adaptive reachability.** Replace `ForceReachabilityPrivate()` with
AutoNAT-driven reachability so peers advertise reachable addresses when they
genuinely have them (WiFi/cone NAT), enabling DCUtR to initiate, while still
defaulting to relay when private. *Tradeoff:* `ForceReachabilityPrivate` was a
deliberate mobile optimization (skips AutoNAT probing, avoids churn); relaxing
it risks reachability mis-detection and AutoRelay churn. Must be measured (A
first) and is the gating decision for NET-REL-03.

**Option C — Accept relay as steady state for cross-network.** Conclude that for
mobile-to-mobile over cellular, relay is correct, and redirect effort to (1) LAN
direct (NET-REL-01), (2) relay path latency/reliability, and (3) honest UX. This
may be the highest-ROI option; A provides the data to justify it.

**Option D — Future: add WebRTC transport.** WebRTC brings ICE/STUN-style
traversal that handles some NAT cases libp2p's DCUtR doesn't, and is the
standard for browser/mobile p2p. *Tradeoff:* significant integration effort,
new dependency surface; only worth it if A shows direct connections are both
valuable and currently blocked by transport rather than NAT physics.

## Acceptance Criteria / How We'll Know It's Fixed

This is partly a *measurement* problem, so "fixed" means we can answer:
1. What fraction of cross-network 1:1 connections are relay vs direct, over time
   (NET-REL-04)?
2. Of relayed connections, how many *attempt* a hole punch and how many succeed
   (requires the accepted instrumentation plus a valid baseline harvest)?
3. For the WiFi-cone-NAT case specifically, do upgrades occur when expected
   (integration test with public/cone reachability)?
4. A documented, data-backed decision: pursue DCUtR (Option B) vs accept relay
   (Option C) vs WebRTC (Option D).

## Test Plan

See **NET-REL-06** for harness inventory and the negative-control principle. This
area is mostly a *measurement* problem, and the realistic NAT cases (cellular
symmetric NAT) **cannot** be hole-punched — so the controls that prove "we
correctly do NOT upgrade" matter as much as the success cases. Note there is no
NAT-type emulation today (only the structural NW002 "must relay" pattern).

### Instrumentation tests (Go) — accepted prerequisite to preserve
- **U1 (happy):** with a holepunch tracer (`holepunch.WithTracer`, go-libp2p
  v0.39.1) wired, assert a hole-punch attempt and a success outcome are captured
  and surfaced as a telemetry event/counter.
- **U2 (label mapping):** extend `transport_label_test.go` so feeding a stub conn that
  flips circuit→non-circuit yields `relay`→`direct`. NOTE: `classifyStreamTransport` is
  already stateless/per-stream (not "sampled once and cached") — this test proves the
  classifier maps inputs correctly, NOT that a real upgrade happened. Also: the existing
  `stubStreamConn.Stat()` returns an empty `ConnStats{}` so `Limited` is always false on
  the stub — the `Limited == true` half must use a real NW002 circuit conn, not the stub.
- **NEGATIVE CONTROL U-N1:** a peer that never upgrades (no reachable address) emits
  ZERO success events and the count stays 0. Proves the detector isn't always-true.

### E2E feasibility — read this first (QA round 2)
A real relay→direct DCUtR **upgrade is NOT exercisable through the production node
path.** Production still defaults to `ForceReachabilityPrivate()`, so the
tracer may correctly observe zero attempts/successes in the production-shaped
relay-only case. The current test-only seam can vary peer reachability for
protocol-feasibility tests, but there is still no NAT emulation. The
in-process harness's historical `ForceReachabilityPublic()` is on the
*relay* host, not the peers (`local_relay_harness_test.go:185`), and NW002
deliberately *destroys* direct addresses — so neither produces a peer that can be
upgraded. The **only** local success-style evidence is a **component/protocol
feasibility** path on loopback — which proves the protocol can be observed, not
that the production app would ever trigger it. So:
- The happy upgrade case (I1/U1-success) is **component/protocol-feasibility**,
  using the test-only reachability + `holepunch.WithTracer` seam in `node`. It is
  not an app-E2E guarantee.
- The **stay-on-relay negative control is the first-class E2E test** — it IS achievable
  today with real hosts via NW002.

### Integration (Go)
- **I1 (component-level, BUILD seam first):** with a test-only public-reachability +
  tracer seam, mirror `holepunch_test.go`: establish a relayed conn, force a hole
  punch, assert a direct conn opens, a new chat stream rides it (`conn.Stat().Limited
  == false`, `transport == 'direct'`), and the tracer recorded a success. Label this
  PROTOCOL-feasibility, not app behavior.
- **I1-NC (PRIMARY, E2E, dominant real case):** force relay-only via NW002 clear-addrs
  (no reachable direct address) and over a **polled wall-clock window** assert: (1)
  `assertNW002LimitedCircuitConn` holds *throughout* (re-poll, not once), (2) the
  holepunch tracer records **zero successful upgrades and zero/bounded attempts**
  (expected count is **0** — without a reachable address DCUtR never initiates; assert
  `== 0`, not "bounded > 0"), and (3) the connection identity to the peer is stable
  (`ConnsToPeer` count doesn't oscillate → no thrash). NOTE: assertions (2)/(3) depend
  on the accepted tracer counters and are part of the relay-only negative-control proof.
- **I2 (unhappy — relay drop):** `watchdog_failover_test.go` relay-drop is a *failover*
  harness, not an upgrade harness — there is no upgrade in flight to disrupt. As an
  upgrade test I2 is not implementable; scope it instead to "relay drop with
  `WithAllowLimitedConn` sends → bounded re-dial," which the existing watchdog tests
  already largely cover.
- **NEW (mixed-conn race):** when both a `Limited` circuit conn and a direct conn exist,
  assert `classifyStreamTransport` reports `direct` only when the stream actually rides
  the non-circuit conn (`WithAllowLimitedConn` everywhere means a stream can ride
  either) — guards a real mislabel/double-count false positive.

### Relay server
- **R1:** confirm `go-relay-server` exposes circuit-relay-v2 — assert (mocknet style,
  `inbox_test.go`) the relay advertises the `ProtoIDv2Hop` reservation protocol. NOTE:
  "pion deps are unused" is NOT a runtime test — it's a build-graph fact; verify it via
  `go mod why`/lint or a doc footnote, not an `inbox_test.go`-style assertion.

### Baseline measurement (depends on NET-REL-04)
- **M1:** before changing connection policy, produce a baseline report of
  direct/relay split and hole-punch attempt/success counts (drive a known forced mix
  and assert exact counts — not "> 0"). This is what tells us whether Option B/C/D is
  worth pursuing vs accepting relay as the steady state.

### Anti-false-result notes specific to this doc
- Do NOT accept the `{direct, relay}` set for an upgrade-success test — that would
  pass even if no upgrade ever happened. Pin `direct` AND `Limited == false`.
- Preserve the fixed `unknown` fallback: a "we're on relay" assertion must
  distinguish a true relay conn (`Limited == true`) from a missing or
  unrecognized label that should remain `unknown`.

## Open Questions

1. Should we relax `ForceReachabilityPrivate()` (Option B) — and only after
   Option A data justifies it? (Shared pivotal decision with NET-REL-03.)
2. What is our actual user network mix (WiFi vs cellular, NAT types)? We don't
   know today; Option A would reveal proxies for it.
3. Is WebRTC (Option D) on the roadmap, or is circuit-relay-v2 the permanent
   cross-network answer?
4. Does the relay server have headroom to remain the steady-state data path at
   scale (informs Option C)? Cross-ref relay capacity planning.

## References

- Code anchors in Document Basis.
- libp2p DCUtR spec (`libp2p/specs` relay/DCUtR.md) — initiation requires
  advertised reachable addresses; migration + relay-close-after-grace on success.
- Cross-ref **NET-REL-03** (relay springboard depends on this feasibility
  decision), **NET-REL-04** (the metrics that gate the decision),
  **NET-REL-01** (LAN is where direct actually works today).
