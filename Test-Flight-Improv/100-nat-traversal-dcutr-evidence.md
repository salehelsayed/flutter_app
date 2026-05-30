# 1. Title and Type

- Title: Trustworthy NAT Traversal and DCUtR Upgrade Evidence
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`

# 2. Problem Statement

Users expect cross-network conversations to use the best available delivery path:
direct when the phones can really reach each other, relay when that is the only
reliable path, and no misleading transport status when the app cannot know.

Today the app has libp2p DCUtR hole punching enabled and now has partial
hole-punch diagnostics in the local working tree, but the product contract is
still not settled from a user-visible point of view. A successful message can
ride relay indefinitely, a favorable relay-to-direct upgrade is only represented
as feasibility evidence, and common mobile NAT conditions may make a direct
upgrade physically impossible.

The problem is not simply "make every cross-network chat direct." The problem is
that the app must truthfully prove which path was used, distinguish a real
relay-to-direct upgrade from a normal relay send or LAN direct dial, and keep
relay delivery trustworthy where NAT traversal cannot succeed.

# 3. Impact Analysis

- Affected users: people sending 1:1 or group messages when peers are not on the
  same LAN, especially mobile-to-mobile users behind carrier or home NAT.
- Affected maintainers: TestFlight and reliability reviewers deciding whether
  NAT traversal work, relay improvements, or LAN direct work deserves priority.
- When it appears: startup, resume, relay recovery, cross-network sends, group
  discovery, and any session where a relayed peer might be expected to become
  direct.
- Severity: medium-high for performance and release confidence. Delivery can
  still work through relay, but latency, relay egress, and prioritization
  decisions are hard to evaluate without truthful upgrade evidence.
- Frequency: likely recurring for cross-network mobile pairs. Repo evidence
  shows production reachability is still forced private, while the source
  tracking doc records that cellular or symmetric NAT pairs commonly cannot be
  hole-punched.
- Confusion cost: a `direct` label from a LAN/pre-relay dial, a per-stream
  classifier, or a protocol-feasibility test can be mistaken for a production
  DCUtR upgrade unless the acceptance contract separates those cases.

# 4. Current State

- Source investigation: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
  identifies NET-REL-02 as a NAT traversal and DCUtR feasibility gap. It records
  that relay is the realistic steady state for many cross-network mobile pairs,
  especially cellular or symmetric-NAT cases.
- The Go node enables libp2p hole punching through `libp2p.EnableHolePunching`
  and keeps production reachability private through `ForceReachabilityPrivate`.
  The same host setup enables AutoRelay with static relays. Evidence:
  `go-mknoon/node/node.go`.
- The current working tree includes a hole-punch tracer that emits
  `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and
  `transport:upgraded` events, plus counters for attempts, successes, and
  failures. It also corrects stale connection state after a real upgrade.
  Evidence: `go-mknoon/node/holepunch_tracer.go`.
- Production reachability remains private. The test-only public-reachability
  path is explicitly described as protocol-feasibility support, not production
  behavior. Evidence: `go-mknoon/node/node.go` and
  `go-mknoon/node/holepunch_feasibility_test.go`.
- Connection events still come from peer connectedness and local address
  updates. The connection watcher records peer address, direction, and limited
  state when connectedness changes, while the tracer is the current explicit
  relay-to-direct transition signal. Evidence: `go-mknoon/node/node.go` and
  `go-mknoon/node/holepunch_tracer.go`.
- The stream transport classifier labels any stream whose local or remote
  multiaddr contains `/p2p-circuit` as `relay`; otherwise it labels the stream
  `direct`. This is per-stream evidence, not by itself proof of a DCUtR upgrade.
  Evidence: `go-mknoon/node/node.go` and
  `go-mknoon/node/transport_label_test.go`.
- 1:1 dial, relay probe, and chat send paths allow limited connections, and the
  send self-heal path closes the peer then re-dials through relay. This means a
  successful conversation can validly remain relay-backed. Evidence:
  `go-mknoon/node/node.go`.
- Group recovery can prefer already-known direct addresses before relay through
  `connectGroupPeerPreferDirect` and `dialKnownGroupMembersDirectOnly`. That is
  direct address dialing, not necessarily a DCUtR relay-to-direct upgrade.
  Evidence: `go-mknoon/node/pubsub.go`.
- The Dart bridge forwards hole-punch and upgrade diagnostics, and the P2P
  service records them into `TransportMetrics`. Missing inbound transport now
  falls back to `unknown` when no live connection inference exists, rather than
  silently becoming `relay`. Evidence: `lib/core/bridge/go_bridge_client.dart`,
  `lib/core/services/p2p_service_impl.dart`, and
  `lib/core/debug/transport_metrics.dart`.
- Existing test evidence is partial and intentionally scoped:
  `go-mknoon/node/holepunch_negative_control_test.go` covers the relay-only
  negative control with zero attempts, zero successes, no upgrade event, and no
  connection thrash.
- Existing protocol-feasibility evidence is not app-E2E evidence:
  `go-mknoon/node/holepunch_feasibility_test.go` can prove a loopback
  relay-to-direct upgrade only when the controlled environment actually produces
  one, and explicitly skips when loopback DCUtR does not materialize.
- Existing label tests cover classifier behavior and mixed-connection labeling,
  but they do not prove a real relay-to-direct upgrade by themselves. Evidence:
  `go-mknoon/node/transport_label_test.go`.
- Existing relay integration evidence verifies direct dial fallback to circuit
  relay and message delivery; it does not assert a relay-to-direct upgrade.
  Evidence: `go-mknoon/integration/relay_test.go`.
- The relay server exposes circuit relay service over TCP, WebSocket, and QUIC
  listen addresses. This repo evidence does not show the relay acting as a
  STUN/TURN or WebRTC traversal service. Evidence: `go-relay-server/main.go`.
- Adjacent decision-gate docs already depend on this evidence:
  `Test-Flight-Improv/99-transport-observability-and-metrics.md`,
  `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md`, and
  `Network-Arch/Transport-Reliability/04-transport-observability.md`.

# 5. Scope Clarification

- In scope:
  - Truthful user-visible distinction between relay delivery, direct delivery,
    unknown transport, and a real relay-to-direct upgrade.
  - Acceptance expectations for DCUtR attempts, successes, failures, and
    upgrade transitions.
  - Negative-control behavior where relay-only peers remain relay-backed without
    false upgrade events.
  - Preservation of successful relay delivery where direct traversal is not
    available.
  - Privacy-safe aggregate diagnostics that avoid message content, full peer
    identifiers, conversation identifiers, and raw addresses.
- Non-goals:
  - No promise that cellular, symmetric-NAT, or otherwise unreachable peer pairs
    must become direct.
  - No routing policy, reachability, WebRTC, TURN, relay-server, or AutoRelay
    architecture decision.
  - No implementation session split, rollout sequencing, or code ownership
    assignment.
  - No claim that a per-stream `direct` label, LAN direct dial, or loopback
    protocol-feasibility result is sufficient by itself to prove production
    DCUtR success.
- Accepted ambiguities:
  - The real user network mix, including WiFi, cellular, and NAT type
    distribution, remains unknown until trustworthy baseline evidence is
    harvested.
  - The exact future UX surface for transport diagnostics remains open.
  - Favorable DCUtR environments may be hard to exercise consistently in local
    or simulator-only automation; acceptance must distinguish feasibility from
    production guarantees.
  - Whether future work should invest further in DCUtR, accept relay as steady
    state, or pursue a different traversal approach remains outside this spec.

# 6. Test Cases

## Happy Path

- A favorable relay-to-direct scenario reports a delivered message as direct only
  after a real non-circuit, non-limited connection exists, and the session
  diagnostics show a matching hole-punch success and relay-to-direct upgrade.
  - Acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/holepunch_feasibility_test.go`.
  - Current gap: this is protocol-feasibility evidence, not a reliable
    production app-E2E guarantee.
- A normal relay-only cross-network conversation delivers messages over relay,
  displays or records relay as the actual transport, and does not require a
  direct upgrade to be considered successful.
  - Acceptance evidence: integration and smoke.
  - Existing partial coverage: `go-mknoon/integration/relay_test.go`.
- A session diagnostics view can distinguish hole-punch attempts, successes,
  failures, relay-to-direct upgrades, relay deliveries, direct deliveries, WiFi
  deliveries, inbox deliveries, and unknown labels without exposing message
  content or full peer identity.
  - Acceptance evidence: unit and smoke.
  - Existing partial coverage: `lib/core/debug/transport_metrics.dart`,
    `test/core/debug/transport_metrics_test.dart`, and
    `test/core/services/p2p_service_inbound_transport_test.dart`.
- A missing or unrecognized inbound transport label appears as `unknown` unless
  a true live connection inference exists; it is not silently counted as relay.
  - Acceptance evidence: unit.
  - Existing partial coverage:
    `test/core/services/p2p_service_inbound_transport_test.dart`.

## Edge Cases

- Relay-only peers with no reachable direct addresses stay on a limited circuit
  connection across a polling window, produce zero hole-punch successes and zero
  upgrade events, and do not oscillate between phantom direct and relay states.
  - Acceptance evidence: integration.
  - Existing partial coverage:
    `go-mknoon/node/holepunch_negative_control_test.go`.
- When both relay and direct connections exist to the same peer, each delivered
  message is labeled according to the stream it actually used, not according to
  a sibling connection.
  - Acceptance evidence: unit and integration.
  - Existing partial coverage: `go-mknoon/node/transport_label_test.go`.
- A group or LAN path that connects to an already-known direct address before
  relay is counted as direct delivery but not as a DCUtR relay-to-direct upgrade
  unless a real upgrade event occurred.
  - Acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/pubsub.go` tests around
    `pre_relay_direct_dial`.
- A peer pair in a NAT condition that cannot be hole-punched continues to use
  relay without surfacing direct success, and any diagnostics make the absence
  of a successful upgrade clear.
  - Acceptance evidence: integration and smoke.
  - Current gap: repo evidence documents feasibility constraints, but local
    automation does not appear to emulate every NAT type.
- A relay drop or relay recovery journey preserves bounded message recovery
  behavior without emitting a relay-to-direct upgrade unless a real direct
  upgrade occurs.
  - Acceptance evidence: integration and smoke.

## Regressions to Preserve

- Preservation/regression: existing 1:1 relay delivery still works when direct
  dial fails or is unavailable.
  - Acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/integration/relay_test.go`.
- Preservation/regression: successful relay-backed sends remain valid results;
  the app must not block user delivery while waiting for a direct upgrade that
  may never be possible.
  - Acceptance evidence: smoke and integration.
- Preservation/regression: transport labels remain truthful across `direct`,
  `relay`, `wifi`, `inbox`, and `unknown`, and `unknown` does not regress back
  to a silent relay default.
  - Acceptance evidence: unit.
  - Existing partial coverage:
    `test/core/services/p2p_service_inbound_transport_test.dart`.
- Preservation/regression: relay server behavior remains circuit-relay service
  for relay delivery; tests and docs must not imply it provides STUN/TURN or
  WebRTC traversal when repo evidence does not support that claim.
  - Acceptance evidence: integration.
- Preservation/regression: transport diagnostics remain aggregate and
  privacy-safe, with no message text, full peer IDs, raw multiaddrs, or
  conversation identifiers in user-visible diagnostics.
  - Acceptance evidence: unit and smoke.

# 7. DCUTR Evidence Closure

Recorded: 2026-05-30 CEST

Overall verdict for this evidence run:
`accepted_with_explicit_follow_up`. DCUTR-001, DCUTR-002, and DCUTR-003
are accepted as stable evidence for their scoped contracts, but production
mobile DCUtR success remains unproven until a valid real-device baseline harvest
exists.

## Accepted Evidence Folded Into This Source Doc

- DCUTR-001 accepted the Go observation and anti-false-upgrade contract:
  `holepunch:attempt`, `holepunch:success`, `holepunch:failure`, and
  `transport:upgraded` are the accepted event names; production reachability
  remains private; the public-reachability path is test-only feasibility
  support; stale limited-state repair is tied to a real tracer success; classifier
  labels are mapping evidence rather than upgrade proof; and the relay-only
  negative control records zero false successes.
- DCUTR-002 accepted the Dart aggregate diagnostics contract: accepted Go
  hole-punch events are forwarded through the bridge as sanitized diagnostic
  payloads; `TransportMetrics` records aggregate hole-punch and relay-to-direct
  counters; missing inbound transport remains `unknown` unless a true live
  connection or matching accepted upgrade signal exists; and settings/debug
  diagnostics stay aggregate and privacy-safe.
- DCUTR-003 accepted relay-only/no-upgrade behavior with explicit follow-up:
  strict limited-circuit relay delivery is a valid successful outcome; forced
  relay-only proof recorded zero forced relay-only attempts and successes, no
  `holepunch:success`, no `transport:upgraded`, stable target-peer connection
  count, and relay failover/recovery without manufactured upgrade evidence.

## Test-Case Closure Map

- Favorable relay-to-direct remains protocol-feasibility evidence only. Local
  loopback, test-only reachability, LAN direct dialing, and per-stream `direct`
  labels do not prove production mobile DCUtR success.
- Normal relay-only cross-network delivery is accepted as successful when the
  peer is unpunchable or no real upgrade is observed.
- Diagnostics can distinguish `direct`, `relay`, `wifi`, `inbox`, `unknown`,
  hole-punch counts, and relay-to-direct upgrade counts without exposing message
  content, full peer IDs, conversation IDs, or raw multiaddrs.
- Missing or unrecognized inbound transport remains `unknown` unless true live
  connection evidence or a matching accepted upgrade signal supports a stronger
  label.
- Relay drop and relay recovery simulator/CLI proof is relay/recovery liveness
  evidence. It is not physical NAT traversal proof.

## Residuals And Evidence Gates

- Production mobile DCUtR success is unproven and evidence-gated. No concrete
  repo-local artifact was found that contains a valid real-device,
  discovery-enabled, debug-mode `baselineReport()`/decision-gate harvest for a
  1:1 run with raw counts, hole-punch attempt/success/failure counts,
  relay-to-direct upgrade count, cross-network metadata, and enough context to
  satisfy the baseline decision-gate validity rules.
- Simulator, CLI, loopback, LAN-direct, and reliability-sim proof must not be
  cited as physical mobile NAT traversal proof. They can support liveness,
  recovery, protocol-feasibility, classifier, and relay-only safety claims only.
- The repeated DCUTR-003 `run_transport_e2e.dart` E8 media metadata residual is
  classified as an external orchestrator media-metadata residual: the reliability
  sim runner was attempted twice; Flutter reported `33/33 passed`; the
  orchestrator downloaded the 69-byte blob; the external proof produced
  `29/30 passed` with `messageSeen=false`, `attachmentReferenced=false`, and
  `blobInList=false`. This does not reopen DCUTR-003 unless later concrete
  evidence ties that residual to the relay-only/no-upgrade tests.
