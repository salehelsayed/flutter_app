# FDC-12 — Opportunistic DCUtR relay→direct upgrade + stable peer-identity session + TCP lane  (New Feature)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5, §8 P2-3, §12 punchr correction, §7 per-peer HOT_DIRECT state)

---

## ⚠ DRAFT — finalize after FDC-S2

> This is a **spike-gated DRAFT**. It is **gated by FDC-S2** (the DCUtR / hole-punch
> feasibility-and-measurement spike). Every value tagged **`<from FDC-S2>`** is a placeholder the
> spike must supply before this plan goes implementation-ready: the **real-device punch-rate on our
> relay + NAT mix**, the **RTT-sync window**, the **TCP-vs-QUIC upgrade-success delta**, the
> **UPnP/PMP (NATPortMap) reversal payoff**, and whether flipping production reachability off
> `ForceReachabilityPrivate()` is **safe to ship** (or whether AutoNAT must arbitrate). The
> **host-testable Go portion is given full RED detail below** (it reuses the already-present
> `SetForcePublicReachabilityForTests` + `SetHolePunchTracerForTests` loopback seams). The
> **relay→direct upgrade actually firing in production, on cellular/Wi-Fi NATs, is DEVICE-ONLY** and
> is the closure gate — those rows are flagged `DEVICE-PROOF (closure)` and cannot be proven on
> host/sim. Do not start implementation until FDC-S2 lands and this banner is removed.

---

## Source Of Truth

- **Proposal** `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md` — §6.5 (relay→direct
  upgrade DCUtR cannot deliver under `ForceReachabilityPrivate`), §8 **P2-3** (the exact scope:
  flagged DCUtR upgrade, *stable peer-identity session* because DCUtR hands a **second** connection,
  **TCP-direct lane** since punchr shows TCP==QUIC, spend on **RTT-sync precision + UPnP/PMP
  reversal, not retries** — 97.6% of wins are first-attempt), §12 (70%±7.1% network-wide, near-0
  only symmetric-CGNAT cellular↔cellular), §10 ("cross-network direct ≈ 0%" honesty note,
  bridge-serialization, LAN double-delivery dedup-by-messageId), §7 per-peer `HOT_DIRECT` state.
- **`scripts/run_test_gates.sh` wins over prose.** Acceptance is whatever the gate arrays + `go test`
  actually run, not this document's narrative.
- **Epic roadmap FDC-00** owns priority ordering; P2-3 is **lowest priority, flagged, device-only**.
- **Precedent already in tree (do not re-build):** `holepunch_tracer.go` (the production emitting
  `nodeHolePunchTracer`, the `transport:upgraded` event, and `markPeerUpgradedToDirect`), the
  `forcePublicReachabilityForTests` / `holePunchTracerForTests` Start-time seams (`node.go:330-333`,
  `:1922-1938`), and the three existing feasibility/negative-control/label tests.

## Session Classification

**evidence-gated (DRAFT)** — gated by **FDC-S2**. The host-loopback feasibility layer is
implementation-ready (seams exist), but the production reachability flip + measured punch payoff +
RTT/UPnP tuning are spike outputs. Device-proof is the closure gate.

## Exact Problem Statement

**What's missing.** Production runs `libp2p.ForceReachabilityPrivate()` (`node.go:330`), which makes
the DCUtR hole-puncher **observation-only**: `EnableHolePunching` is wired (`node.go:343`) and the
production tracer is installed (`holepunch_tracer.go:25-27`, `node.go:326`), but **zero** relay→direct
upgrades fire **by configuration** — documented as the expected `I1-NC` result
(`holepunch_tracer.go:15-17`). So two reachable peers that connected via `/p2p-circuit` stay on the
relay forever, even when a hole punch (~70% network-wide per punchr, §12) would succeed. The
live-relay circuit is *limited* (2 min / 128 KB / 1 reservation — §6.2), so they never get the durable
direct pipe they could have had.

**Who feels it.** Both-online foreground peers on the common case (one cone-NAT/public side) pay relay
latency + relay limits for the whole conversation. Media and long sessions are forced to inbox even
though a direct path was punchable.

**Why it's hard (the real feature, not a one-liner).** DCUtR does **not** migrate the existing socket
in place (unlike iroh/Tailscale). On a successful punch libp2p **opens a SECOND connection** (a direct
one) to the *same* peer ID and **does not re-fire `EvtPeerConnectednessChanged`**
(`holepunch_tracer.go:66-69`). Our `connections` map is keyed by peer ID and maintained by a single
EventBus subscription (`node.go:1727-1783`) that will therefore **miss the upgrade** — the map keeps
pointing at the stale `/p2p-circuit` address with `Limited=true`. We need a **stable
peer-IDENTITY session layer** that re-points "the peer" onto the new direct conn the instant it
appears, prefers a non-circuit / TCP-or-QUIC conn, and tears the relay leg down gracefully — while the
receiver continues to **dedupe by `messageId`** so any in-flight double-send is harmless.

**What must improve:** behind a flag, a relay-connected reachable pair upgrades to a **direct**
connection (TCP **or** QUIC); subsequent sends label `direct`; the connections map and send fast-path
see the upgraded conn (`Limited=false`, non-circuit `Address`); relay + inbox stay as carriers so **the
user never waits on the punch**.

**What must stay unchanged (preserved sentinels):**
- **PROD DEFAULT = `ForceReachabilityPrivate()` and ZERO production punches when the flag is OFF.**
  This is the `holepunch_tracer.go:15-17` invariant; flag-off must be byte-identical to HEAD.
- The production tracer stays **pure observation** of policy — it changes no *send decision*; the path
  decision stays in Dart `sendChatMessage`. Go only **labels** transport (`classifyStreamTransport`
  `node.go:123-136`).
- Receiver **`messageId` dedup** stays the correctness backstop (§10 LAN double-delivery note); the
  upgrade must never produce a *visible* duplicate even if a leg can't be cancelled.
- Connection-count stability: no phantom upgrade/downgrade thrash (the
  `holepunch_negative_control_test.go` invariant).

## Root Cause (verify→refute confirmed)

- **Mechanism (config, not capability):** `reachabilityOpt := libp2p.ForceReachabilityPrivate()`
  (`node.go:330`) → the holepuncher never *initiates* an active punch in production; `EnableHolePunching`
  (`node.go:343`) + the installed tracer only *observe*. **Verified** in source and explicitly stated
  at `holepunch_tracer.go:15-17`.
- **Second-connection mechanism (verified):** on `EndHolePunchEvt{Success}` the tracer already emits
  `transport:upgraded` and calls `markPeerUpgradedToDirect` (`holepunch_tracer.go:56-76`), which under
  `n.mu` clears `Limited` and re-samples `Address` from the first **non-circuit** conn
  (`holepunch_tracer.go:136-155`). So a *partial* re-point exists — but it (a) only fires from the
  tracer callback, (b) is **dead in production** because no punch ever fires, and (c) is **not** a
  durable Notifiee-driven session layer (it doesn't react to the direct conn closing back to relay-only,
  nor prefer TCP, nor coordinate with the Dart send fast-path).
- **Connections map is EventBus-driven, not Notifiee-driven (verified):** `watchConnectionEvents`
  (`node.go:1727-1783`) reacts to `EvtPeerConnectednessChanged`/`EvtLocalAddressesUpdated` only, and
  libp2p does **not** re-fire connectedness on an in-place upgrade — so without the dedicated path the
  map silently goes stale (`holepunch_tracer.go:66-69`).
- **TCP lane already listened (verified):** listen addrs include `/tcp/0` and `/tcp/0/ws` alongside
  `quic-v1` (`node.go:298-315`); `classifyStreamTransport` is circuit-vs-direct only (`node.go:123-136`),
  so a punched TCP conn already classifies `direct`. The gap is *preferring/observing* the TCP lane on
  upgrade and a feasibility lock that it punches, not new transports.
- **UPnP/PMP already requested (verified):** `libp2p.NATPortMap()` (`node.go:344`) — FDC-S2 must
  *measure* its reversal payoff, not add it.

**Refuted / do-NOT-re-introduce:**
- **Do NOT add server-side store idempotency** — it exists (`backend_memory.go:121-142`,
  `backend_redis.go:272-295`, `inbox_store.go:7,14`; appendix). Dedup is the *receiver/store* backstop.
- **Do NOT rebuild `markPeerUpgradedToDirect` / `transport:upgraded`** — extend them.
- **Do NOT plan retry loops or aggressive re-punch** — §8 P2-3 / §12: 97.6% of wins are first-attempt;
  effort goes to RTT-sync precision + UPnP/PMP reversal, not retries.
- **Do NOT make Go decide the path** — §2/§6, the decision stays in Dart `sendChatMessage`.
- **Do NOT promise cross-network gains** — §10: symmetric-CGNAT cellular↔cellular ≈ 0%; this is an
  *opportunistic upgrade*, relay+inbox always backstop.

## Real Scope

**In scope**
- A **production flag** (`NodeConfig.EnableDcutrUpgrade`, default **false**) that, when ON, lets DCUtR
  *actively* upgrade a relay conn to direct. The flag's mechanism (off `ForceReachabilityPrivate`, or
  AutoNAT-gated) is **`<from FDC-S2>`** — DRAFT assumes "do not force private when flag ON, keep
  forcing private when OFF."
- A **stable peer-identity session layer** (new `go-mknoon/node/peer_session.go`) registered as a
  `network.Notifiee` that re-points the `connections[peerID]` entry onto the **best** (non-circuit,
  TCP-or-QUIC) conn on `Connected`, falls back to relay on direct-conn `Disconnected`, and emits a
  single authoritative `transport:upgraded` / `transport:downgraded` discriminator.
- **TCP-direct lane**: feasibility lock that a punched conn classifies `direct` over **TCP** (not only
  QUIC), and the session layer's "best conn" preference treats TCP and QUIC direct as equal-rank
  (punchr TCP==QUIC), both ranked above circuit.
- **RTT-sync precision + UPnP/PMP reversal**: surface the punch RTT (`StartHolePunchEvt.RTT`,
  `holepunch_tracer.go:50-54`) and elapsed time as measurable telemetry; FDC-S2 tunes the synchronized
  dial window. No retry logic.
- Dart consumption: `p2p_service_impl` observes `transport:upgraded`, updates
  `lastKnownGoodTransport` (`:4100`) so the next send's sticky/reuse fast-path uses the direct conn;
  pass the flag through `NodeConfig`. **Send-path decision unchanged.**

**Out of scope (owning FDC-xx)**
- LAN/mDNS unification, `DefaultDialRanker`, `WithForceDirectDial` for LAN → **FDC P2-1** (§6.5 mDNS).
- The concurrent-inbox / staggered ranked race / warmPeer → **FDC P0-1/P0-2/P0-3**.
- Relay presence lookup, durable Redis backend → **FDC P1-1 / P2-2**.
- Pause-flush / lifecycle handoff → **FDC P1-2**.

## Files To Inspect Next

**Production — Go**
- `go-mknoon/node/node.go` — reachability opt `:330-333`; hostOpts `:338-347`; `EnableHolePunching`
  `:343`; `NATPortMap` `:344`; listen addrs (TCP+QUIC+WS) `:298-315`; `connectionInfo` struct `:113-116`;
  `classifyStreamTransport` `:123-136`; `isCircuitAddr` `:118-121`; `watchConnectionEvents` `:1727-1783`;
  Start (where a Notifiee would register, after `n.host=h` `:367`) `:367-405`; the test seams
  `:1922-1938`.
- `go-mknoon/node/holepunch_tracer.go` — production tracer `:25-27`/`:33-104`; `transport:upgraded`
  emit `:70-76`; `markPeerUpgradedToDirect` `:136-155`; RTT surface `:50-54`.
- `go-mknoon/node/config.go` — flag + timeout home (`DialTimeout`/`PeerDialTimeout`/cadences `:28-41`);
  add `EnableDcutrUpgrade` default + any RTT/`<from FDC-S2>` consts here.
- `go-mknoon/bridge/events.go` — already references holepunch/upgrade events; flag plumbing.
- **NEW** `go-mknoon/node/peer_session.go` — the Notifiee-backed session re-point layer (this plan
  creates it).

**Production — Dart**
- `lib/core/services/p2p_service_impl.dart` — `lastKnownGoodTransport` `:4100`, `isConnectedToPeer`
  `:4092`, event consumption; `warmBackground` `:572-647` (context only — not edited here).
- `lib/main.dart` — `NodeConfig` construction / `LocalP2PService` wiring `:1893-1914` (pass the flag).
- `lib/features/conversation/application/send_chat_message_use_case.dart` — reuse `:447-465`, sticky
  `:528-595` (READ-ONLY context; the decision is here but FDC-12 must NOT alter it — it only feeds a
  fresher `lastKnownGoodTransport`).

**Tests (existing, this area)**
- `go-mknoon/node/holepunch_feasibility_test.go` — loopback relay→direct upgrade proof (forced-public
  seam); `classifyStreamTransportConn` helper `:156-166`.
- `go-mknoon/node/holepunch_negative_control_test.go` — conn-count stability / no-thrash + ZERO punches
  under private reachability.
- `go-mknoon/node/holepunch_tracer_test.go` — tracer counters/event-emit unit coverage.
- `go-mknoon/node/transport_label_test.go` — `classifyStreamTransport` circuit-vs-direct mapping.

## Existing Tests Covering This Area

| Test | Status | Gate array |
|---|---|---|
| `go-mknoon/node/holepunch_feasibility_test.go` | EXISTS (loopback upgrade proof, SKIPs if punch doesn't materialize) | `cd go-mknoon && go test ./...` |
| `go-mknoon/node/holepunch_negative_control_test.go` | EXISTS (ZERO-punch-under-private + no conn-count thrash) | `go test ./...` |
| `go-mknoon/node/holepunch_tracer_test.go` | EXISTS (tracer counters + emit) | `go test ./...` |
| `go-mknoon/node/transport_label_test.go` | EXISTS (`classifyStreamTransport` mapping) | `go test ./...` |
| `send_chat_message_use_case_test.dart` | EXISTS (send ladder; sticky/reuse) | `run_test_gates.sh 1to1` |
| `p2p_service_impl_test.dart` | EXISTS (service events / transport) | `run_test_gates.sh 1to1` |
| transport integration suite (`background_reconnect`, `wifi_relay_fallback_smoke`, `transport_e2e`) | EXISTS | `run_test_gates.sh transport` |
| `transport:upgraded` → Dart `lastKnownGoodTransport` consumption test | **MISSING** (add, see RED) | `run_test_gates.sh 1to1` |
| Notifiee-driven session re-point unit test | **MISSING** (add, see RED) | `go test ./...` |

## RED Test Catalog  (BEFORE any prod code)

> Tiers: **Go-unit** (node package, host, `go test`), **Go-feasibility** (loopback forced-public seam,
> may SKIP), **Dart-host** (`run_test_gates.sh 1to1`), **DEVICE-PROOF** (closure gate — `/sims` /
> real-device, cannot run on host). Distinct-event discriminator throughout: `transport:upgraded`
> (relay→direct) vs `transport:downgraded` (direct→relay fallback) vs `peer:connected` (initial),
> because all three leave the peer "connected".

### Go-unit / host

**TC-12-01 — flag OFF preserves ForceReachabilityPrivate + ZERO punches (PRESERVATION).**
`node/dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches`
- Tier: Go-unit. Setup: Start a node with `NodeConfig{EnableDcutrUpgrade:false}` + an injected counting
  tracer + a local circuit relay; reserve; idle the punch window.
- RED-on-HEAD-because: `NodeConfig.EnableDcutrUpgrade` doesn't exist → won't compile (the canonical RED
  for a new field).
- GREEN-asserts: host built with `ForceReachabilityPrivate()` (assert via the same observable the
  feasibility test uses — no active punch), tracer `Successes()==0`, no `transport:upgraded` event.
- Mutation-that-re-reds: make the flag-off branch use `ForceReachabilityPublic()` → punch/Successes may
  fire → test red. **This is the `holepunch_tracer.go:15-17` invariant lock.**

**TC-12-02 — flag ON selects the upgrade reachability mode.**
`node/dcutr_upgrade_flag_test.go::TestDcutrFlagOn_SelectsUpgradeReachability`
- Tier: Go-unit. Setup: `NodeConfig{EnableDcutrUpgrade:true}`; assert the chosen reachability opt is the
  upgrade mode **`<from FDC-S2>`** (not-force-private vs AutoNAT-gated). DRAFT asserts "not
  `ForceReachabilityPrivate`".
- RED-on-HEAD-because: no flag → field/branch absent.
- GREEN-asserts: flag-ON path constructs the upgrade-permitting host opt; flag-OFF path unchanged.
- Mutation: invert the flag→opt mapping → red.

**TC-12-03 — Notifiee re-points connections[peer] onto the direct conn (SESSION LAYER).**
`node/peer_session_test.go::TestPeerSession_RepointsToDirectConn`
- Tier: Go-unit. Setup: build a node, seed `connections[peerID]={Limited:true, Address:<circuit>}`,
  then drive the registered `network.Notifiee.Connected` with a fake **non-circuit** conn to the same
  peer ID (a second connection).
- RED-on-HEAD-because: no `peer_session.go` / no Notifiee registered → the map stays `Limited:true`
  circuit.
- GREEN-asserts: `connections[peerID].Limited==false`, `.Address` is the non-circuit addr, exactly one
  `transport:upgraded{fromTransport:"relay",toTransport:"direct"}` emitted.
- Mutation: drop the re-point (no-op the Notifiee) → map stays circuit → red.
- Discriminator: assert `transport:upgraded` NOT `peer:connected` (initial conns must still be
  `peer:connected`).

**TC-12-04 — TCP-direct conn ranks equal to QUIC, both above circuit (best-conn pref).**
`node/peer_session_test.go::TestPeerSession_PrefersTcpOrQuicOverCircuit`
- Tier: Go-unit. Setup: peer has THREE conns to same ID — circuit, direct-TCP, direct-QUIC.
- RED-on-HEAD-because: no best-conn selector.
- GREEN-asserts: selected `Address` is a **non-circuit** addr (TCP **or** QUIC accepted; circuit
  rejected); `Limited==false`. With only circuit+TCP → selects TCP.
- Mutation: rank circuit above direct → selects circuit → red. Mutation: reject TCP (QUIC-only) → with
  circuit+TCP it keeps circuit → red.

**TC-12-05 — direct conn closes → graceful downgrade to relay, no orphan.**
`node/peer_session_test.go::TestPeerSession_DirectClose_FallsBackToRelay`
- Tier: Go-unit. Setup: post-upgrade (direct + circuit both present), drive Notifiee `Disconnected`
  for the direct conn while circuit remains.
- RED-on-HEAD-because: no downgrade handling.
- GREEN-asserts: `connections[peerID]` re-points to the surviving circuit (`Limited==true`), one
  `transport:downgraded` emitted; peer still "connected" (not deleted — delete only on last conn,
  preserving `node.go:1774-1782` semantics).
- Mutation: delete the peer on any disconnect → red (peer wrongly offline while circuit alive).
- Discriminator: `transport:downgraded` vs `peer:disconnected`.

**TC-12-06 — no phantom upgrade/downgrade thrash (NEGATIVE CONTROL, mirrors existing).**
`node/peer_session_test.go::TestPeerSession_NoThrash_StableConnCount`
- Tier: Go-unit. Setup: repeated identical `Connected` callbacks for the *same* direct conn.
- RED-on-HEAD-because: a naive Notifiee re-emits on every callback.
- GREEN-asserts: exactly ONE `transport:upgraded` across N duplicate callbacks; `ConnsToPeer` count
  stable (parity with `holepunch_negative_control_test.go:144-145`).
- Mutation: drop the idempotency guard → N events → red.

**TC-12-07 — RTT + elapsed surfaced for FDC-S2 measurement (telemetry lock).**
`node/holepunch_tracer_test.go::TestTracer_EmitsRttAndElapsed` (extend existing file)
- Tier: Go-unit. Setup: drive `StartHolePunchEvt{RTT}` then `EndHolePunchEvt{Success,EllapsedTime}`.
- RED-on-HEAD-because: today `holepunch:attempt{step:started}` carries `rttMs` (`:50-54`) but the
  **`transport:upgraded`** payload carries only `elapsedMs` — add `rttMs`/sync-window fields the spike
  needs. New assert fails on HEAD.
- GREEN-asserts: `transport:upgraded` includes `rttMs` (and `<from FDC-S2>` sync-window field).
- Mutation: drop the field → red.

### Go-feasibility (loopback, forced-public seam — may SKIP, NOT fail)

**TC-12-08 — punched conn classifies `direct` over BOTH TCP and QUIC.**
`node/holepunch_feasibility_test.go::TestFeasibility_DirectUpgrade_TcpLane` (sibling of the existing
QUIC feasibility test)
- Tier: Go-feasibility. Setup: forced-public + collecting tracer + local circuit relay (reuse
  `startNW002RelayNodeWithTracer`); constrain the upgrade to a TCP direct addr.
- RED-on-HEAD-because: no TCP-lane assertion exists; HEAD only proves a (QUIC-capable) upgrade.
- GREEN-asserts (when punch materializes): a non-circuit **TCP** conn exists,
  `classifyStreamTransportConn(tcpConn)=="direct"`, tracer `Successes()>=1`. **SKIPs** (clear reason)
  if no punch within the window — same discipline as `holepunch_feasibility_test.go:15-20`.
- Mutation: classify circuit as direct → the negative (`isCircuitAddr` reject) breaks → red.
- Note: SKIP-able ⇒ NOT a closure gate by itself; pairs with TC-12-12 device-proof.

### Dart-host (`run_test_gates.sh 1to1`)

**TC-12-09 — `transport:upgraded` updates `lastKnownGoodTransport` to direct.**
`test/core/services/p2p_service_transport_upgrade_test.dart::reframes sticky transport on upgrade`
- Tier: Dart-host. Setup: fake bridge emits `transport:upgraded{fromTransport:relay,toTransport:direct}`
  for peer P after a relay send.
- RED-on-HEAD-because: `p2p_service_impl` doesn't consume `transport:upgraded` → `lastKnownGoodTransport`
  stays `relay`.
- GREEN-asserts: `lastKnownGoodTransport(P)=="direct"` so the next send's sticky fast-path
  (`send_chat_message_use_case.dart:528-595`) reuses direct.
- Mutation: ignore the event → stays relay → red.
- Discriminator: assert it reacts to `transport:upgraded`, not to a plain `peer:connected`.

**TC-12-10 — flag plumbs through NodeConfig (default OFF).**
`test/core/services/p2p_service_dcutr_flag_test.dart::passes EnableDcutrUpgrade default false`
- Tier: Dart-host. Setup: build the service with default config; capture the `NodeConfig` handed to the
  bridge.
- RED-on-HEAD-because: no flag field on the Dart-side config DTO.
- GREEN-asserts: default `enableDcutrUpgrade==false`; explicit true plumbs true.
- Mutation: hardcode true → default-false assert red.

**TC-12-11 — upgrade never yields a VISIBLE duplicate (receiver dedup preserved).**
`test/.../inbox or conversation dedup test::duplicate id across relay+direct legs renders once`
- Tier: Dart-host. Setup: same `messageId` arrives over the relay leg and again over the upgraded
  direct leg (uncancellable loser, §6.2 honesty note).
- RED-on-HEAD-because: N/A-preservation — **this MUST already be green on HEAD** (dedup exists). It is a
  **preservation lock**: it proves FDC-12 introduces no path that bypasses messageId dedup.
- GREEN-asserts: exactly one visible message; one bubble.
- Mutation (in FDC-12 code): if the session re-point ever re-injected the buffered relay message on
  upgrade → second render → red.

### DEVICE-PROOF (closure gate — cannot run on host)

**TC-12-12 — real two-device relay→direct upgrade fires & sticks (DEVICE-PROOF, closure).**
- Two real devices on the §12 punchable mix (one cone-NAT/public), flag ON: an established relay
  conversation upgrades to direct within `<from FDC-S2>` ms; subsequent sends label `direct`; relay
  socket no longer carries chat; **user never observed a stall** (relay+inbox carried until punch).
- Closure scenario: `/sims 1to1 --only <N>` registrar case **`<from FDC-S2>`** (a dart-define
  `DCUTR_UPGRADE=1` + a `classify_path()` case must be added — see Harness registration). **Cannot be
  host-proven** (§6.5/§10: sim shares a host mDNS/NAT stack; punch needs real NAT). This row is the
  gate, not the Go feasibility SKIP.

**TC-12-13 — symmetric-CGNAT cellular↔cellular gracefully does NOT upgrade (DEVICE-PROOF, negative).**
- Both peers behind symmetric CGNAT (§12 near-0 case): no punch, stays on relay+inbox, **no
  user-visible failure or delay**. Proves the "opportunistic, relay always backstops" contract.

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Flag OFF = prod default | ForcePrivate + 0 punches | Go-unit | `dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches` | `EnableDcutrUpgrade` absent (no compile) | flag-off→public | `cd go-mknoon && go test ./...` | go pkg auto |
| Flag ON = upgrade mode | not-force-private `<from FDC-S2>` | Go-unit | `…::TestDcutrFlagOn_SelectsUpgradeReachability` | flag absent | invert flag→opt | `cd go-mknoon && go test ./...` | go pkg auto |
| Session re-point | map→direct, 1 upgrade evt | Go-unit | `peer_session_test.go::TestPeerSession_RepointsToDirectConn` | no Notifiee/file | no-op re-point | `cd go-mknoon && go test ./...` | go pkg auto |
| TCP lane equal QUIC | non-circuit pref TCP|QUIC | Go-unit | `peer_session_test.go::TestPeerSession_PrefersTcpOrQuicOverCircuit` | no selector | rank circuit top / QUIC-only | `cd go-mknoon && go test ./...` | go pkg auto |
| Graceful downgrade | relay fallback, no orphan | Go-unit | `peer_session_test.go::TestPeerSession_DirectClose_FallsBackToRelay` | no downgrade | delete-on-disconnect | `cd go-mknoon && go test ./...` | go pkg auto |
| No thrash | 1 evt / N callbacks | Go-unit | `peer_session_test.go::TestPeerSession_NoThrash_StableConnCount` | naive re-emit | drop idempotency | `cd go-mknoon && go test ./...` | go pkg auto |
| RTT telemetry | rttMs on upgraded | Go-unit | `holepunch_tracer_test.go::TestTracer_EmitsRttAndElapsed` | field absent | drop field | `cd go-mknoon && go test ./...` | go pkg auto |
| TCP punch classifies direct | TCP conn==direct | Go-feasibility | `holepunch_feasibility_test.go::TestFeasibility_DirectUpgrade_TcpLane` | no TCP assert (SKIP-able) | circuit→direct | `cd go-mknoon && go test ./...` | go pkg auto |
| Dart consumes upgrade | LKGT→direct | Dart-host | `p2p_service_transport_upgrade_test.dart::reframes sticky transport on upgrade` | event unconsumed | ignore event | `./scripts/run_test_gates.sh 1to1` | **append `p2p_service_transport_upgrade_test.dart` to `ONE_TO_ONE_TESTS`** — `test/core/**` auto-globs only `core-host-all`, NOT the curated `1to1` gate |
| Flag plumbs (default off) | enableDcutrUpgrade=false | Dart-host | `p2p_service_dcutr_flag_test.dart::passes EnableDcutrUpgrade default false` | no DTO field | hardcode true | `./scripts/run_test_gates.sh 1to1` | **append `p2p_service_dcutr_flag_test.dart` to `ONE_TO_ONE_TESTS`** (same — `core-host-all` auto-globs it; the `1to1` gate does not) |
| No visible dup (preserve) | one bubble | Dart-host | `…dedup test::duplicate id renders once` | preservation (green on HEAD) | re-inject on upgrade | `./scripts/run_test_gates.sh 1to1` | `test/**` auto-globs |
| Real upgrade fires+sticks | direct label, no stall | DEVICE-PROOF | TC-12-12 (closure) | host cannot punch real NAT | n/a (device) | `/sims 1to1 --only <N>` `<from FDC-S2>` | NEW `classify_path()` + `DCUTR_UPGRADE=1` dart-define |
| Symmetric-CGNAT graceful | no upgrade, no fail | DEVICE-PROOF | TC-12-13 (negative) | host cannot model CGNAT | n/a (device) | `/sims 1to1 --only <N>` `<from FDC-S2>` | same registrar case |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** after upgrade, `lastKnownGoodTransport` must survive until
  the next send and a later background→resume must not resurrect a stale direct conn (background drops
  direct, §6.4) → TC-12-09 + relies on §6.4-owned downgrade; **TC-12-05** covers direct-close. On a
  network change (Wi-Fi↔cellular, §12 "closes all but QUIC") the direct conn may die → downgrade path
  (TC-12-05) must fire; a re-punch is NOT auto-retried (§8 P2-3 no-retries) — relay carries until a new
  organic upgrade. N/A for further retry logic by design.
- **Sibling-surface consistency:** group messaging shares the host. The session layer keys by **peer
  ID** and the connections map is shared; assert the re-point doesn't disturb group pubsub conns (a
  group peer's relay conn must not be spuriously "upgraded"/torn) → covered by TC-12-06 thrash + the
  existing `pubsub_delivery_test.go` connection assertions as a preservation run.
- **Destructive-action side-effects:** the upgrade tears down nothing the user owns (relay leg is
  collapsed only after the direct conn is healthy; downgrade re-points to circuit, never deletes the
  peer while a conn survives) → TC-12-05.
- **Invariant re-verification under new transitions:** the `holepunch_tracer.go:15-17` ZERO-punch
  invariant must still hold with flag OFF → TC-12-01; the no-thrash invariant under the *new* Notifiee
  → TC-12-06; receiver dedup under the *new* double-send window → TC-12-11.
- **Bridge serialization (§10):** the Notifiee callback runs on libp2p goroutines (NOT under `n.mu`,
  like the tracer `holepunch_tracer.go:29-32`) and must take `n.mu` only inside the dedicated re-point
  helper — never on the host-construction lock; it must not block the single Go bridge. **N/A to add a
  test** beyond TC-12-06 (host-race detector `-race` in `go test` covers the lock discipline).

## Invariants (locked by tests)

1. Flag OFF ⇒ byte-identical to HEAD: `ForceReachabilityPrivate`, ZERO punches, no upgrade events
   (TC-12-01).
2. The peer's identity is stable across the relay→direct second-connection swap; the connections map
   always reflects the BEST live conn (non-circuit > circuit; TCP==QUIC) (TC-12-03/04/05).
3. Exactly one `transport:upgraded` per real upgrade; exactly one `transport:downgraded` per real
   direct-loss; no thrash (TC-12-06).
4. Receiver `messageId` dedup remains the correctness backstop; the upgrade never produces a visible
   duplicate (TC-12-11).
5. Go labels transport only; the path decision stays in Dart `sendChatMessage` (no test asserts a Go
   path decision; Dart only consumes the label into `lastKnownGoodTransport`).

## Step-By-Step Implementation Plan  (RED first)

1. **RED:** write TC-12-01/02 (flag) — they won't compile (no field). Seam:
   `go-mknoon/node/config.go` add `EnableDcutrUpgrade bool` (default false) + `NodeConfig` field;
   `node.go:328-333` branch the `reachabilityOpt` on the flag (**Stop-if:** FDC-S2 hasn't ruled
   whether flag-ON drops `ForceReachabilityPrivate` or uses AutoNAT — DO NOT pick blind).
2. **RED:** TC-12-03/04/05/06 — create `go-mknoon/node/peer_session.go`: a `network.Notifiee` (impl
   `Connected`/`Disconnected`) that calls a new `n.repointPeerToBestConn(peerID)` helper (mirror the
   `markPeerUpgradedToDirect` lock discipline, `holepunch_tracer.go:136-155`). Register it in `Start`
   after `n.host=h` (`node.go:367`) via `h.Network().Notify(...)`. Best-conn selector: prefer
   non-circuit (TCP==QUIC), idempotent (one event per real transition). **Reuse**
   `markPeerUpgradedToDirect` as the upgrade half; add the downgrade half.
3. **RED:** TC-12-07 — extend the `transport:upgraded` payload (`holepunch_tracer.go:70-76`) with
   `rttMs` + `<from FDC-S2>` sync-window field; thread the last `StartHolePunchEvt.RTT` through.
4. **RED:** TC-12-08 — add the TCP-lane feasibility sibling (reuse `startNW002RelayNodeWithTracer` +
   `classifyStreamTransportConn`). SKIP-tolerant.
5. **RED:** TC-12-09/10 (Dart) — add `enableDcutrUpgrade` to the Dart `NodeConfig` DTO + `main.dart`
   wiring (`:1893-1914`); consume `transport:upgraded` in `p2p_service_impl` to update
   `lastKnownGoodTransport` (`:4100`). **Do NOT touch `send_chat_message_use_case.dart` logic.**
6. **Preservation:** run TC-12-11 + `pubsub_delivery_test.go` + the full `holepunch_*` suite green.
7. **GREEN → mutation-verify** every row; then **DEVICE-PROOF** TC-12-12/13 as the closure gate.
8. **Stop-if blockers:** (a) FDC-S2 says the production flip is unsafe ⇒ keep flag default-off and ship
   only the host-observable scaffolding + telemetry, defer the flip; (b) the single-bridge serialization
   shows the Notifiee callback blocking sends ⇒ move re-point work fully off the bridge before enabling.

## Risks And Edge Cases

- **Flipping reachability in prod may regress AutoRelay reservation behavior** (`node.go:348-358`) →
  pinned by TC-12-01 (OFF unchanged) + FDC-S2 device measurement before default-on.
- **Second-connection race**: direct conn appears then immediately dies → TC-12-05 + TC-12-06
  (idempotent, no orphan).
- **Network switch kills direct** (§12) → downgrade (TC-12-05); no auto re-punch by design (§8 P2-3).
- **Uncancellable losing leg double-send** (§6.2) → TC-12-11 dedup preservation.
- **Bridge head-of-line block** (§10) → lock-discipline (Notifiee off `n.mu`-construction lock) +
  `-race`; Stop-if 8(b).
- **Loopback feasibility flakiness** → SKIP-not-fail (TC-12-08), device-proof is the real gate.

## Device/Relay Proof Profile

- **Host-only closure for the scaffolding:** flag wiring, session re-point logic, telemetry, dedup
  preservation (TC-12-01..11) close on `go test ./...` + `run_test_gates.sh 1to1`.
- **Requires device (closure):** TC-12-12 (real punch fires+sticks) + TC-12-13 (symmetric-CGNAT
  graceful) — `/sims 1to1 --only <N>` `<from FDC-S2>`, plus a real-device pair on a punchable NAT
  mix. **The host feasibility SKIP (TC-12-08) is NOT a substitute** (§6.5/§10).

## Acceptance Gates  (literal; expected counts TODO until FDC-S2)

```
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...           # expect: ok (go1.25.0 all-pass baseline +new)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test -race ./node/   # lock-discipline (Notifiee)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && make lint                # gofmt/vet/lint clean (new peer_session.go + config flag)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && go test ./...      # unchanged (no relay edits)
./scripts/run_test_gates.sh 1to1            # expect: PASS (1226 baseline) — adds transport-upgrade + flag tests
./scripts/run_test_gates.sh transport       # expect: PASS (device/fixture-gated (skips on lone sim))
./scripts/run_host_test_gates.sh core-host-all   # expect: 0 fail
flutter analyze                              # expect: 0 new
git diff --check                             # expect: clean
# DEVICE-PROOF (closure, post-FDC-S2):
./scripts/check_reliability_simulation_discovery.sh
/sims 1to1 --only <N from FDC-S2>       # DCUTR_UPGRADE=1 registrar case (NEW classify_path)
```

## Known-Failure Interpretation

- TC-12-08 **SKIP** (no loopback punch in CI window) = expected, NOT failure (parity with
  `holepunch_feasibility_test.go:15-20`). A `go test` SKIP is green for gate purposes.
- TC-12-12/13 cannot run on host → "host green ≠ validated" (§9 Phase-0 false-positive caveat); they
  remain OPEN until device-proof, like FDC-164's deferred-not-waived device rows.

## Done Criteria (checkbox)

- [ ] FDC-S2 landed; banner removed; all `<from FDC-S2>` placeholders replaced (flip-safety,
  RTT/sync-window, punch payoff, sim case `N`).
- [ ] `NodeConfig.EnableDcutrUpgrade` added (default false); flag-OFF byte-identical (TC-12-01 green +
  mutation-verified).
- [ ] `peer_session.go` Notifiee re-point landed; TC-12-03/04/05/06 green + mutation-verified.
- [ ] Stop tears down the registered `network.Notifiee` (`h.Network().StopNotify(...)`) so no re-point fires after Stop — OR explicitly documents `host.Close()`/GC teardown reliance (parity with FDC-11's clear-on-Stop test).
- [ ] `transport:upgraded` carries RTT/sync telemetry; TC-12-07 green.
- [ ] Every NEW exported Go identifier (the `peer_session.go` Notifiee type/funcs, `NodeConfig.EnableDcutrUpgrade`) carries a doc comment; `make lint`/`go vet` clean.
- [ ] TCP-lane feasibility TC-12-08 added (SKIP-tolerant).
- [ ] Dart consumes upgrade → `lastKnownGoodTransport`; flag plumbs default-off; TC-12-09/10 green.
- [ ] Dedup preservation TC-12-11 green; `send_chat_message_use_case.dart` UNCHANGED.
- [ ] `go test ./...` + `-race` + `run_test_gates.sh 1to1`/`transport` + `core-host-all` green; analyze
  0-new; `git diff --check` clean.
- [ ] DEVICE-PROOF TC-12-12/13 closed on a real punchable pair (closure gate).

## Scope Guard (hard Do-not)

- **Do NOT** disturb group pubsub connections during the relay→direct re-point — the peer-session layer keys by peer ID on the **SHARED connections map** that group pubsub uses; **group-safety floor:** `pubsub_delivery_test.go` must stay green (`cd go-mknoon && go test ./...`).
- **Do NOT** change `ForceReachabilityPrivate` default; flag-OFF must equal HEAD.
- **Do NOT** add retry/re-punch loops (§8 P2-3 / §12).
- **Do NOT** rebuild server store idempotency, `markPeerUpgradedToDirect`, or `transport:upgraded`.
- **Do NOT** move the path decision into Go; Dart `sendChatMessage` stays authoritative.
- **Do NOT** edit any other FDC plan's files; **do NOT** touch `send_chat_message_use_case.dart` logic
  (read-only context).
- **Do NOT** hold a direct conn alive in background (§6.4 — that's FDC P1-2's lifecycle territory).

## Accepted Differences

- A duplicate may still be transmitted on an uncancellable losing leg; correctness leans on receiver
  `messageId` dedup, not cancellation (§6.2 honesty note) — accepted.
- Cross-network / symmetric-CGNAT pairs get **no** upgrade and stay on relay+inbox — accepted by design
  (§10), proven graceful by TC-12-13.
- Loopback feasibility may SKIP in CI — accepted; device-proof is the gate.

## Dependency Impact

- **gatedBy:** FDC-S2 (feasibility + measurement + flip-safety spike). Lowest priority in FDC-00.
- **Collision (sequential w/ siblings):** `go-mknoon/node/node.go` + `config.go` are co-edited by **FDC
  P2-1** (libp2p LAN-direct dial, bonsoir-fed / `DefaultDialRanker` / `WithForceDirectDial`); `lib/main.dart` `NodeConfig`
  build & `lib/core/services/p2p_service_impl.dart` are co-edited by P0-1/P1-1. Run FDC-12 **after**
  P2-1's Go host changes (or rebase onto them) to avoid hostOpts churn.
- **No relay-server change** (additive presence/Redis are P1-1/P2-2) → `go-relay-server` untouched.
- **No DB migration.**
