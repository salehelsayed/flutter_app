# Relay as Springboard, Not Resting State — Problem & Tracking Doc

Prepared on: 2026-05-29
Status: Evidence-gated; implementation deferred pending a valid NET-REL-02/04 baseline harvest
Tracking ID: NET-REL-03

## Executive Summary

The principle "relay should be a springboard to a direct connection, not a
permanent resting state" is **not realized** in the 1:1 transport path today.
For cross-network (non-LAN) peers, a relay circuit connection is established once
and then used indefinitely. Every 1:1 send rides the relay via
`WithAllowLimitedConn` (`go-mknoon/node/node.go:1234`, `:1069`, `:1104`,
`:1164`), self-heal re-dials the *same* relay path (`recoverPeerForSend` →
`dialPeerViaRelayWithTimeout`, `node.go:1212-1222`), and nothing in production
code ever attempts to upgrade a live relay connection to a direct one.

There is one latent capability: `libp2p.EnableHolePunching()` **is** configured
(`node.go:313`), wiring DCUtR into the host. Per the DCUtR spec, a successful
hole punch migrates new streams to the direct connection automatically. But this
is undercut by `libp2p.ForceReachabilityPrivate()` (`node.go:315`) and — more
importantly — there is **no application-level logic** that detects we are on a
limited/relay connection to a peer, triggers/awaits an upgrade, confirms it,
migrates sends, or backs off on repeated failure. `classifyStreamTransport`
(`node.go:111-124`) samples a single stream's transport label and drives no
behavior.

The group path already embodies a *weaker* form of this principle ("prefer
direct first, then relay fallback") via `connectGroupPeerPreferDirect` /
`dialKnownGroupMembersDirectOnly` (`pubsub.go:1878`, `:2404`). The 1:1 path has
**no equivalent**. This is the central asymmetry.

This doc maps the relay lifecycle and state machine, performs a step-by-step gap
analysis of what "springboard" requires, and proposes bounded options — honest
that feasibility depends on NAT traversal actually succeeding, which is gated by
NET-REL-02 (`ForceReachabilityPrivate` tension) and measured by NET-REL-04.

## RSD-001 Decision Gate

Recorded: 2026-05-30 CEST.

RSD-001 reran the proceed/defer decision for this tracking item. The run found
live physical devices available to Flutter, but no repo-local copied
real-device, discovery-enabled, debug-mode, 1:1-focused `baselineReport()` or
filled decision-gate artifact with the required transport counts,
hole-punch counts, relay-to-direct upgrade count, and cross-network metadata.

Decision: do not proceed to NET-REL-03 relay springboard implementation yet.
RSD-002/RSD-003 remain prerequisite-blocked. The next safe action is to capture
a valid NET-REL-04 baseline harvest, then revisit whether cross-network 1:1
relay-to-direct escalation is justified.

## Document Basis

- `go-mknoon/node/node.go` — host options (`:305-329`), conn manager (`:235`),
  warm/refresh/reconnect relay (`:668-690`, `:931-944`), send/dial path
  (`:1033-1337`), self-heal (`:1212-1222`), conn watcher (`:1612-1690`),
  `classifyStreamTransport` (`:111-124`).
- `go-mknoon/node/relay_session.go` — per-relay reservation state machine
  (`:18-25`, `:47-57`, `:62`, `:185-306`, `:336-463`, `:578-640`).
- `go-mknoon/node/config.go` — cadence/timeout constants (`:38-55`).
- `go-mknoon/node/pubsub.go` — group prefer-direct dialing (`:1878-1933`, `:2404-2486`).
- libp2p DCUtR spec — migration semantics on successful hole punch.

## Current Behavior (Evidence)

### Relay connection lifecycle, end-to-end
1. **Relay-first host posture** (`node.go:305-329`): `EnableRelay()`,
   `EnableHolePunching()`, `NATPortMap()`, `ForceReachabilityPrivate()`, and
   `EnableAutoRelayWithStaticRelays(..., WithBootDelay(0),
   WithBackoff(~1s), WithMinInterval(~1s))`. The inline comment is explicit:
   `ForceReachabilityPrivate` tells AutoRelay to always seek relay reservations
   (`node.go:306-307`). By design this *stays* on relay.
2. **Connection manager** (`node.go:235`): `NewConnManager(10, 100,
   WithGracePeriod(1m))` — LowWater 10, HighWater 100, 1-minute grace.
3. **Warm/establish:** `warmRelayConnectionForStart` dials static relay(s);
   `waitForCircuitAddress` polls until a `/p2p-circuit` address appears.
4. **Keep-alive/recovery:** `RefreshRelaySession`, `ReconnectRelays` →
   in-place re-reservation first (when `EnableInPlaceRelayRecovery`), full
   host Stop+Start fallback. Recovery coalesced via singleflight
   (`BeginRecovery`/`CompleteRecovery`/`Wait`, 30s `RecoveryWaitTimeout`).
5. **Send rides relay:** `SendMessageWithTransport` → `openChatStreamForSend`
   sets `WithAllowLimitedConn(ctx,"chat-send")` (`node.go:1234`). On retryable
   open error, `recoverPeerForSend` does `ClosePeer` + `dialPeerViaRelayWithTimeout`
   (`:1212-1222`) — relay→relay; never a direct address.

### Relay session state machine (`relay_session.go`)
Per-relay states (`:18-25`, **six** states): `disconnected → connected →
reserving → reserved`, plus `degraded` / `cooldown`. (An earlier draft omitted
`reserving` — corrected after QA.) Transitions: `OnConnected` (`:276`),
`OnReservationOpened` (`:185`, resets FailCount), `OnReservationEnded`/`OnDisconnected`
→ degraded (assignment at `:217`/`:304`), `OnRequestFailed` (`:225`) → cooldown
**only when currently `reserving`** (`:245-246`); otherwise it just increments
`FailCount` with no state change. `OnRefreshFailed`/`OnRefreshSucceeded`
watchdog (`:578`/`:622`, `WatchdogMaxConsecutiveFailures = 5` at `:57`). Aggregate
states (`:47-52`): `starting`/`online`/`recovering`/`watchdog_restart`.

**Critical observation:** every state describes the *relay's own reservation
health*. There is **no state/field/transition that models a per-remote-peer
connection as "on relay, candidate for upgrade to direct."** The machine keeps
the relay reservation healthy (NET-REL-02 territory), not escalating individual
peer connections off relay. This is the structural reason relay is the resting
state.

### Why relay is the resting state (summary)
- Reachability forced private (`node.go:315`) → advertises only circuit
  addresses; AutoRelay continuously maintains reservations.
- Every send opts into limited conns (`:1234`); self-heal re-dials circuit
  (`:1212-1222`).
- Conn watcher records `limited` per peer for telemetry but takes **no upgrade
  action** (`node.go:1620-1648`). Observe-only.

## Problems Identified

**P1 — No relay→direct escalation for 1:1 peers (the core gap).** Send always
allows limited conns (`node.go:1234`); self-heal re-dials relay; no code reads
`conn.Stat().Limited` and reacts. *Impact:* cross-network conversations pay
relay latency and relay egress for the conversation lifetime even when a direct
path is feasible.

**P2 — DCUtR enabled but neutered and unobserved.** `EnableHolePunching()`
coexists with `ForceReachabilityPrivate()` (suppresses advertising reachable
addresses → hole punch unlikely to fire); and no code observes an upgrade if it
did. *Impact:* the one mechanism that could deliver "springboard" is configured
against itself and invisible. (Cross-ref NET-REL-02.)

**P3 — Asymmetry with the group path.** Groups try direct first
(`connectGroupPeerPreferDirect`, `pubsub.go:1878`; `dialKnownGroupMembersDirectOnly`,
`:2404`) with relay fallback. 1:1 has no analog. *Impact:* the same two devices
may go direct in a group and relay in a 1:1 chat.

**P4 — No backoff/cooldown structure for upgrade attempts (none exist).** The
only backoff machinery (`FailCount`, `ConsecutiveRefreshFailures`, `cooldown`) is
relay-reservation-scoped, not peer-upgrade-scoped. *Impact:* any future feature
starts from zero on anti-thrash; naive attempts risk battery drain (especially
symmetric NAT where they always fail).

**P5 — Transport classification is one-shot, not lifetime tracking.**
`classifyStreamTransport` samples one stream at one instant; no record of
"started relay at T0, upgraded at T1." *Impact:* no signal to drive migration or
to measure time-on-relay.

## What "Springboard" Requires (Gap Analysis)

| Step | Exists today? | What's missing |
|---|---|---|
| **(a) Detect on-relay to a specific peer** | Partial — `watchConnectionEvents` records `limited` per peer (`node.go:1631-1648`); `classifyStreamTransport` labels per-stream. | No durable per-peer "on-relay" record that triggers anything; `limited` is stored for telemetry only, never read to start an upgrade. |
| **(b) Attempt a direct upgrade** | Latent — `EnableHolePunching()` (`:313`); group direct-dial pattern (`pubsub.go:1878`). | For 1:1: no path dials peer-advertised direct addresses; DCUtR suppressed by `ForceReachabilityPrivate`; no "try direct now" trigger for a relay-connected 1:1 peer. |
| **(c) Detect success** | No. | libp2p would migrate streams automatically, but no event subscription/check records "peer is now direct"; no `relay_to_direct_upgraded` telemetry. |
| **(d) Migrate future sends to direct** | Partial (automatic IF a direct conn opens). | Never established (b fails). Also `WithAllowLimitedConn` (`:1234`) means even with a direct conn available the send still accepts relay — no preference enforced. |
| **(e) Backoff/cooldown to avoid thrash** | No. | No per-peer attempt counter/timestamp/history/cooldown; existing fields are relay-scoped. Must be built from scratch. |

## Impact

- **Latency & reliability:** cross-network 1:1 messages route through `mknoun.xyz`
  for the conversation lifetime and inherit relay health (NET-REL-02 recovery
  cycles). Direct would reduce latency and decouple steady-state delivery from
  relay uptime.
- **Relay cost & scaling:** the relay carries all cross-network 1:1 bytes
  indefinitely. Springboarding off relay shifts steady-state traffic to p2p,
  reducing relay egress and reservation pressure as the user base grows.
- **Consistency:** P3's asymmetry complicates reasoning and support.
- **Battery (counter-pressure):** escalation adds hole-punch/direct-dial
  attempts; unbounded attempts (esp. symmetric NAT) drain battery. (e) is
  mandatory, not optional.

## Proposed Directions (options, NOT implementation)

All depend on NAT feasibility (NET-REL-02) and measurement (NET-REL-04).

**Option A — Let DCUtR do its job (remove the self-sabotage).** Reconsider
`ForceReachabilityPrivate()` in favor of AutoNAT-driven reachability; add a
connection-event observer recording relay→direct transitions. *Tradeoffs:* most
aligned with libp2p design, least custom code; but relaxing reachability risks
AutoRelay churn/mis-detection. Hard dependency on NET-REL-02.

**Option B — App-level opportunistic direct upgrade for active 1:1 peers.**
Mirror `connectGroupPeerPreferDirect` for 1:1: when a relay-connected peer
becomes active and we hold direct addresses, attempt a background direct dial; on
success libp2p migrates streams. *Tradeoffs:* reuses a tested pattern, keeps
`ForceReachabilityPrivate`; only works when direct addresses are known/reachable
(LAN, port-mapped, cone NAT) — must be paired with Option D cooldown.

**Option C — Trigger-on-demand hole punch.** Keep `ForceReachabilityPrivate`,
but on a heuristic explicitly request a DCUtR attempt for an active peer.
*Tradeoffs:* targeted but requires reaching into libp2p's holepunch service;
highest complexity/coupling.

**Option D — Bounded escalation policy (required for A/B/C).** Per-peer upgrade
ledger (attempts, last-attempt time, last-success transport, consecutive
failures) with capped exponential backoff (mirror `MaxGroupDiscoveryBackoff = 1m`,
`config.go:49`) and a per-session ceiling. Suppress in background (`bg:begin`/
`bg:end` exist) and tune by network type. *Tradeoffs:* this is the battery/cost
guardrail; not optional. Adds the peer-scoped state `relay_session.go` lacks.

**Honest constraint:** for symmetric-NAT cross-network peers, no option reliably
yields direct — relay remains correct for those peers. The win is concentrated
on LAN / port-mapped / cone-NAT peers. Measure (NET-REL-04) before assuming
broad benefit.

## Acceptance Criteria / How We'll Know It's Fixed

1. A per-peer signal that a 1:1 connection started on relay, plus a record of
   whether/when it upgraded (new telemetry, e.g.
   `peer:transport_upgraded {peerId, fromRelay, toDirect, elapsedMs}`).
2. For LAN/port-mapped/cone-NAT pairs, an active relay-connected conversation
   upgrades to direct within a bounded window and subsequent sends report
   `transport:"direct"`.
3. Upgrade attempts are bounded (per-peer cooldown/ceiling; test asserts no
   further dials after the ceiling).
4. Symmetric-NAT/unreachable peers stay on relay with no thrash (attempt-count
   telemetry plateaus).
5. No regression to relay health (`RelaySessionManager` aggregate stays
   `online`; watchdog restart counts unchanged in steady state).
6. Group transport behavior unchanged.

## Test Plan

See **NET-REL-06** for harness inventory and the negative-control principle. The
backoff/anti-thrash controls are as important as the upgrade-success cases, since
the realistic mobile case is "upgrade is impossible — don't keep trying."

> **All U1–U3 below test code that does NOT exist yet** — the per-peer upgrade ledger,
> trigger, and migration logic are all unbuilt (grep-confirmed: no
> `upgrade`/`transport_upgraded`/`escalat` in `go-mknoon/node`). They are red-tests for
> future code, not validations of existing behavior.

### Unit (Go, `node`) — the per-peer upgrade ledger (BUILD)
- **U1 (happy):** ledger records relay→direct success; cooldown resets on success.
- **U2 (unhappy — anti-thrash):** repeated failures grow backoff (capped, mirror the
  real, tested `groupPeerDialBackoff`/`MaxGroupDiscoveryBackoff = 1m`, `config.go:49`)
  and stop at the per-session ceiling. Pattern after `relay_session_test.go` (state
  injection) + `send_message_recovery_test.go` (hooks).
- **U3 (background suppression):** with background state active, no upgrade attempts
  fire. **PREREQUISITE:** `bg:begin`/`bg:end` exist only on the Dart/iOS side
  (`bridge.dart`, `go_bridge_client.dart`); the Go node has NO background-state signal
  (only `Interactive`/`Background` timeout profiles). So U3 needs background state
  plumbed into the node first, OR move this test to the Dart layer where the signal
  exists.
- **NEGATIVE CONTROL U-N1:** assert that after the ceiling, NO further dials occur
  (count is exact, not "≤") — proves the ceiling is enforced, not cosmetic. Depends on
  the ledger exposing an attempt counter via `Status()`/a test seam.

### Transport label / classification
- **U4:** extend `transport_label_test.go` so feeding a stub conn that flips
  circuit→non-circuit yields `relay`→`direct`. (Proves the classifier maps inputs;
  not a real upgrade.)
- **NEGATIVE CONTROL U-N2 (must be SPLIT):** the `relay`-label half is testable via the
  stub (`transport_label_test.go:219`); but the `conn.Stat().Limited == true` half is
  NOT assertable on the stub (its `Stat()` returns empty `ConnStats{}`). Assert
  `Limited == true` with a **real** NW002 circuit conn instead.

### Integration (Go) — upgrade + migration
> **Harness correction:** the live limited-circuit-conn primitive (`DialPeerViaRelay` +
> `assertNW002LimitedCircuitConn`) lives in the **node-package** test
> `pubsub_delivery_test.go` (NW002), NOT in `local_relay_harness_test.go` (whose relay
> only registers rendezvous + inbox handlers, no circuit-conn assertions).

- **PREREQUISITE (BUILD):** I1 needs two app nodes that hold a live circuit conn AND
  each retain a *reachable direct address* to upgrade onto. NW002 destroys direct addrs
  (`ClearAddrs` both ways) and production nodes are `ForceReachabilityPrivate`. So a
  brand-new harness variant that starts the two app nodes with `ForceReachabilityPublic`
  is required first — this seam does not exist (`startNW002RelayNode`/`startNodeWithRelays`
  don't expose reachability override).
- **I1 (happy, after prerequisite):** establish a relay (limited) conn, trigger the
  upgrade, assert (a) `ConnsToPeer(pid)` gains a conn with `Limited == false`, and (b) a
  newly opened chat stream's `Conn().Stat().Limited == false` (= `transport == 'direct'`).
  Migration IS observable this way (open a new stream, check which conn it landed on).
- **I1 — relay drop after grace (RE-SPECIFIED):** "ConnManager trims the relay conn"
  is NOT deterministically testable in a 2-node test — relay conns aren't `Protect`-ed,
  but HighWater is 100, so a 2-node harness never trims. Instead assert the
  implementation **proactively closes** the relay conn after upgrade: `ConnsToPeer(pid)`
  no longer contains a `Limited` conn within a bounded window. (If we want to prove the
  ConnManager-trim path, that needs a separate >100-conn stress test with a `Protect`-ed
  control — heavy/brittle; document as out of scope.)
- **I1 NEGATIVE CONTROL (PRIMARY, dominant case):** force relay-only (NW002 clear-addrs)
  → over a polled window assert the conn STAYS `Limited == true`, **zero** upgrade
  attempts/successes (no reachable addr ⇒ never initiates), and stable `ConnsToPeer`
  count (no thrash). The connectivity half is testable today; the attempt-count half
  depends on the ledger counter (U1).
- **I2 (unhappy — relay drop):** `watchdog_failover_test.go` `stop()`/`restart()` is a
  *failover* harness with no upgrade in flight; scope I2 to "delivery continues
  (inbox/relay) and recovery bounded," not "relay drop mid-upgrade."
- **REGRESSION GUARD:** assert group transport behavior (`connectGroupPeerPreferDirect`)
  is unchanged and relay aggregate stays `online` with unchanged watchdog-restart count.

### Device matrix (manual/E2E) — honest about feasibility
- same-LAN (expect upgrade/`local`), cross-network cone NAT (expect upgrade where
  possible), cross-network **symmetric NAT (expect graceful stay-on-relay)**. The last
  is the pass criterion most likely to be mistaken for a failure — assert it explicitly
  as success-by-staying-on-relay-without-thrash.

### Latency & battery (BUILD hard gates)
- **L1:** convert relevant `benchmark_*_test.go` percentile logs into `t.Fatalf`
  budget assertions for upgraded-direct vs relay send latency.
- **B1:** radio wakeups / attempt counts bounded in the symmetric-NAT control (I1
  negative control) — assert the count plateaus.

## Open Questions

1. Relax `ForceReachabilityPrivate()` (Option A) or app-level upgrade (Option B)?
   Pivotal, shared with NET-REL-02.
2. Where do peer-advertised *direct* addresses come from for 1:1 peers? Groups
   get them from rendezvous + peerstore (`collectDirectMultiaddrs`,
   `pubsub.go:1871-1876`). Does the 1:1 contact/discovery flow populate the
   peerstore with non-circuit addresses today, or must that be added?
3. What is the right "peer is active" trigger (first send / Nth send / recent
   receive)? (Routing concern — NET-REL-05.)
4. After a direct conn opens, proactively close the relay conn (spec) or leave it
   to ConnManager grace trimming? HighWater 100 + 1m grace makes relying on
   ConnManager alone risky. (Verified after QA: production code does **not**
   `Protect` relay conns, so they are subject to normal trimming — there is no
   pin keeping a relay conn alive once a direct one exists.)
5. With `WithAllowLimitedConn` always set, must we *stop* allowing limited conns
   once direct exists to force migration, or is libp2p prioritization sufficient?
6. How do background/foreground and cellular-vs-WiFi interact with the
   upgrade-attempt budget?

## References

- Code anchors in Document Basis.
- Cross-ref **NET-REL-02** (reachability/NAT feasibility — Option A cannot
  proceed without it), **NET-REL-04** (transport upgrade telemetry),
  **NET-REL-05** ("peer is active" trigger and per-send preference enforcement).
- libp2p DCUtR spec — on success, prioritize direct conn for new streams, close
  relay after grace; upgrade attempted only when peer advertises reachable addrs.
