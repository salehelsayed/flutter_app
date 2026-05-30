# 1. Title and Type

- Title: Relay Should Not Be a Permanent 1:1 Transport Resting State
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/101-relay-springboard-direct-escalation.md`

# 2. Problem Statement

Users expect a 1:1 conversation to use the best available connection path:
relay when relay is the only reliable path, and direct when the devices can
really reach each other.

Today a cross-network 1:1 conversation can establish a relay circuit and keep
using that relay path for the conversation lifetime. The app can now observe
some hole-punch and transport-upgrade signals, but production reachability still
keeps the Go node private and the 1:1 send path remains willing to use limited
relay connections.

From the user's perspective, this means messages may keep paying relay latency
and relay dependency costs even when a better path might be available. The
product risk is also measurement confusion: a relay delivery, LAN direct dial,
per-stream `direct` label, and real relay-to-direct upgrade must remain
distinguishable.

# 3. Impact Analysis

- Affected users: people sending 1:1 messages across networks, especially
  mobile users outside the same LAN.
- Affected flows: 1:1 send, retry/self-heal after stream-open failure, startup
  and resume recovery, relay health, and transport diagnostics.
- When it appears: after a peer is reachable through relay and the conversation
  continues without any confirmed direct transition.
- Severity: medium-high for latency, reliability confidence, and relay egress
  cost. Message delivery can still work through relay, but the steady-state path
  remains relay-dependent.
- Frequency: likely recurring for cross-network 1:1 pairs. Existing evidence
  states production reachability remains forced private, and the relay-only
  negative control is the dominant expected case for peers without reachable
  direct addresses.
- Confusion cost: reviewers can overread a `direct` stream label, loopback
  feasibility result, or LAN direct connection as proof that production mobile
  relay-to-direct behavior exists.

# 4. Current State

- Source issue: `Network-Arch/Transport-Reliability/03-relay-springboard.md`
  identifies NET-REL-03 as the gap where relay acts as a 1:1 resting state
  instead of a temporary path toward direct when direct is feasible.
- Current dependency status: `Network-Arch/Transport-Reliability/02-nat-traversal-dcutr.md`
  records that hole-punch observation exists, but production mobile
  relay-to-direct success is still evidence-gated.
- Production host setup enables relay and hole punching, then keeps
  reachability private. The public-reachability path is explicitly test-only
  feasibility support. Evidence: `go-mknoon/node/node.go` lines 315-344 and
  1843-1849.
- The 1:1 dial, relay probe, and chat send paths allow limited connections.
  Evidence: `go-mknoon/node/node.go` lines 1094-1099, 1129-1134,
  1189-1195, and 1258-1263.
- The 1:1 send self-heal path closes the peer and re-dials through the relay
  circuit. Evidence: `go-mknoon/node/node.go` lines 1240-1249.
- Send and receive telemetry classify the transport from the stream's own
  multiaddrs: `/p2p-circuit` becomes `relay`; otherwise the stream is labeled
  `direct`. Evidence: `go-mknoon/node/node.go` lines 121-133, 1336, and 1538.
- Peer connection events record address, direction, and limited state when
  connectedness changes. Evidence: `go-mknoon/node/node.go` lines 1639-1684.
- A hole-punch tracer now emits privacy-limited attempt, success, failure, and
  `transport:upgraded` diagnostics and corrects stale limited connection state
  after a real tracer success. It states that it changes no connection policy.
  Evidence: `go-mknoon/node/holepunch_tracer.go` lines 10-17, 40-76, and
  133-155.
- Relay session state tracks relay reservation health, refresh failures, and
  watchdog recovery. It does not describe a user peer as being temporarily on
  relay pending a direct transition. Evidence: `go-mknoon/node/relay_session.go`
  lines 18-40, 54-62, 184-252, and 575-640.
- Group transport has a narrower direct-first behavior for already-known
  non-circuit addresses through `collectDirectMultiaddrs`,
  `connectGroupPeerPreferDirect`, and `dialKnownGroupMembersDirectOnly`.
  Evidence: `go-mknoon/node/pubsub.go` lines 1871-1933 and 2401-2440.
- Existing tests distinguish evidence types:
  `go-mknoon/node/holepunch_tracer_test.go` covers emitted attempt/success/
  failure and upgrade diagnostics; `go-mknoon/node/holepunch_negative_control_test.go`
  covers relay-only delivery with zero upgrade attempts, zero successes, no
  upgrade event, and no connection-count thrash; `go-mknoon/node/holepunch_feasibility_test.go`
  is loopback protocol-feasibility only and may skip when DCUtR does not
  materialize; `go-mknoon/node/transport_label_test.go` covers label mapping
  and explicitly says it is not real upgrade proof.
- Adjacent decision evidence in
  `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md` and
  `Test-Flight-Improv/NET-REL-04-baseline-decision-gate.md` says production
  mobile DCUtR success remains unproven, and NET-REL-03 should inherit the
  NET-REL-02 evidence gate.

# 5. Scope Clarification

- In scope:
  - User-visible expectation that an active 1:1 conversation should not be
    reported or treated as direct unless real direct evidence exists.
  - User-visible expectation that relay-only peers continue to deliver reliably
    through relay without false upgrade diagnostics.
  - Observable distinction between relay delivery, LAN/direct-address delivery,
    loopback feasibility, and real relay-to-direct upgrade.
  - Acceptance evidence for the effect on latency/reliability only when the
    underlying network can actually support a direct path.
  - Preservation of existing relay health, group direct-first behavior, and
    successful 1:1 relay delivery.
- Non-goals:
  - No claim that cellular, symmetric-NAT, or otherwise unreachable peer pairs
    must become direct.
  - No routing policy, reachability policy, AutoRelay, WebRTC, TURN, or relay
    server architecture decision.
  - No implementation session split, rollout sequencing, code ownership, or
    new code seam proposal.
  - No claim that a stream label, LAN direct dial, or loopback protocol result
    proves production mobile relay-to-direct success.
- Accepted ambiguities:
  - Whether enough real cross-network pairs are upgradeable remains open until
    trustworthy baseline evidence exists.
  - The future UX surface for transport diagnostics remains open.
  - The exact acceptable wait window for a possible relay-to-direct transition
    remains a later product and evidence decision.
  - Relay may remain the correct steady state for many real mobile pairs.

# 6. Test Cases

## Happy Path

- A 1:1 conversation that starts on relay and later has real direct connectivity
  available reports a relay-to-direct transition only after a non-circuit,
  non-limited connection is observed.
  - Required acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/holepunch_tracer_test.go` and
    `go-mknoon/node/holepunch_feasibility_test.go`.
  - Current gap: no production-shaped 1:1 flow proves this outcome on mobile
    with current production reachability.

- After a confirmed relay-to-direct transition, a subsequent 1:1 message is
  observed as direct from the actual stream used for that message, not from a
  stale peer-level label.
  - Required acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/transport_label_test.go`.
  - Current gap: label mapping exists, but it does not prove a real transition.

- Privacy-safe diagnostics distinguish hole-punch attempt, success, failure,
  and relay-to-direct upgrade counts without exposing message content, full peer
  IDs, conversation IDs, or raw addresses.
  - Required acceptance evidence: unit and integration.
  - Existing partial coverage: `go-mknoon/node/holepunch_tracer_test.go` and
    `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.

## Edge Cases

- A relay-only peer with no reachable direct address keeps delivering 1:1
  messages over relay, emits no false upgrade success, and shows no repeated
  upgrade/downgrade connection churn.
  - Required acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/holepunch_negative_control_test.go`.

- A stream labeled `direct` because it used a non-circuit address is not counted
  as a relay-to-direct upgrade unless matching upgrade evidence exists.
  - Required acceptance evidence: unit.
  - Existing partial coverage: `go-mknoon/node/transport_label_test.go`.

- A favorable loopback or LAN direct result is accepted only as feasibility or
  local-network evidence, not as proof that production mobile NAT traversal
  succeeds.
  - Required acceptance evidence: smoke or simulator where device context is
    being evaluated; unit/integration for local protocol evidence.
  - Existing partial coverage: `go-mknoon/node/holepunch_feasibility_test.go`
    and `Test-Flight-Improv/100-nat-traversal-dcutr-evidence.md`.

- Production-shaped relay delivery remains successful when a peer is
  unpunchable or when no real direct evidence appears.
  - Required acceptance evidence: integration.
  - Existing partial coverage: `go-mknoon/node/holepunch_negative_control_test.go`.

## Regressions To Preserve

- Preservation/regression: existing 1:1 sends that require relay still deliver
  through relay and still report `relay` for the stream actually used.
  - Existing partial coverage: `go-mknoon/node/holepunch_negative_control_test.go`
    and `go-mknoon/node/send_message_recovery_test.go`.

- Preservation/regression: self-heal after a retryable 1:1 stream-open failure
  does not break message delivery for relay-reachable peers.
  - Existing partial coverage: `go-mknoon/node/send_message_recovery_test.go`.

- Preservation/regression: group direct-first behavior for already-known
  non-circuit addresses remains unchanged while 1:1 relay springboard behavior
  is evaluated separately.
  - Existing partial coverage: `go-mknoon/node/pubsub_test.go`.

- Preservation/regression: relay reservation health and watchdog recovery remain
  truthful and stable; relay-only success must not be treated as a failure just
  because no direct upgrade occurred.
  - Existing partial coverage: `go-mknoon/node/node_test.go`,
    `go-mknoon/node/relay_session.go`, and
    `go-mknoon/node/holepunch_negative_control_test.go`.

- Bug regression: a relay-only 1:1 conversation must not emit or display a
  relay-to-direct upgrade when no non-circuit, non-limited connection exists.
  - Existing partial coverage: `go-mknoon/node/holepunch_negative_control_test.go`.

- Bug regression: a stale limited peer connection record must not keep showing
  relay after a real accepted upgrade signal has corrected the connection state.
  - Existing partial coverage: `go-mknoon/node/holepunch_tracer_test.go`.

- Current test gap: no valid repo-local real-device, discovery-enabled baseline
  artifact was found that proves production mobile relay-to-direct success for
  a 1:1 conversation under production reachability.

# 7. RSD-001 Decision Gate Result

Recorded: 2026-05-30 CEST.

RSD-001 reran the NET-REL-03 evidence gate against the current repo docs,
baseline decision gate, harvest runbook, and live device inventory. Physical
devices are available to Flutter (`Pixel 6` `21071FDF600CSC`,
`Saleh's iPhone` `00008030-001A6D2801BB802E`, and `iPhone`
`00008110-00184D622289801E`), but the repo still does not contain a copied
real-device, discovery-enabled, debug-mode, 1:1-focused `baselineReport()` or
decision-gate artifact with direct/relay/wifi/inbox/unknown counts,
hole-punch attempt/success/failure counts, relay-to-direct upgrade count, and
cross-network/co-location metadata.

Decision: no proceed verdict for relay springboard implementation. RSD-002 and
RSD-003 remain prerequisite-blocked, and this doc must not be used as authority
to add a 1:1 direct-escalation policy, routing policy, reachability policy,
WebRTC/TURN/STUN, AutoRelay, or relay-server protocol change. RSD-004 may close
the rollout only by preserving this evidence-gated residual unless a later
valid harvest artifact is added.
