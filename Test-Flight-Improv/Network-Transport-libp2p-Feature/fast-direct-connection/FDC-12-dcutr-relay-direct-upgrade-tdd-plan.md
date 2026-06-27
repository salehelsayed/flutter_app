# FDC-12 — Opportunistic DCUtR relay→direct upgrade + stable peer-identity session + TCP lane  (New Feature)

Status: awaiting-review — **reviewed + re-grounded 2026-06-27 (7-agent verify→refute; see "Plan Review Delta" below)**; **FDC-S2 identify portion resolved (Option A; upgrade-abandon-timeout 750ms)**; DCUtR device-only items (flip-safety / punch payoff / RTT-sync) remain → `EnableDcutrUpgrade` stays default-off. Core design held; anchors corrected, 3 test framings reframed (TC-12-09/10 + new TC-12-09b), harness/gate routes fixed.
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.5, §8 P2-3, §12 punchr correction, §7 per-peer HOT_DIRECT state)

---

## ⚠ PARTIALLY RESOLVED by FDC-S2 — host Go scaffolding unblocked; production flip + real-NAT punch payoff remain DEVICE-ONLY

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
> host/sim. **FDC-S2 has landed (Option A — identify portion; see the sub-banner below): the host-testable
> Go scaffolding is unblocked now. The production reachability-flip + real-NAT punch payoff stay DEVICE-ONLY
> and keep `EnableDcutrUpgrade` default-off until the DCUtR device campaign closes.**

> ### ✅ Resolved by FDC-S2 (executed 2026-06-27) — identify portion only
> FDC-S2 (the **QUIC identify-handshake re-validation** spike) is closed = **Option A**. It resolves
> the part of this plan that depends on direct-conn identify, **NOT** the device-only DCUtR items:
> - **A DCUtR-upgraded direct QUIC conn reaches usable, identify-complete, stream-usable state — YES.**
>   Direct QUIC identify is `0/100` hang @ `p95 2ms`, and the freshly-identified conn carries a
>   `ChatProtocol` stream (M1 proves connect → identify-both-ways → stream-usable). So a relay→direct
>   upgrade that completes identify **does** become a usable leg (it won't "succeed at swarm level while
>   the app sees a dead leg").
> - **Upgrade-abandon timeout (abandon back to relay) = `750ms`** (`= max(p95↑250ms, 750ms)`; the same
>   per-leg dial+identify budget FDC-11 consumes). TCP-direct identify is also `0/100` @ p95 2ms, so the
>   TCP lane (§8 P2-3) is a sound fallback.
> - **Reachability (partial signal only):** FDC-S2's M1 public-vs-private pair was identical for a plain
>   direct dial (`0/100`, p95 2ms each) → direct identify itself is not reachability-sensitive. This does
>   **NOT** clear the production `<from FDC-S2>` "is it safe to flip off `ForceReachabilityPrivate()` for
>   DCUtR?" question — AutoNAT arbitration / real-NAT punch behaviour is **device-only** and stays the
>   FDC-12 DEVICE-PROOF closure gate.
> - **Still `<from FDC-S2>` (DEVICE-ONLY, NOT closed here):** real-device punch-rate on our relay+NAT mix,
>   RTT-sync window, TCP-vs-QUIC *upgrade-success* delta, UPnP/PMP reversal payoff. These belong to the
>   DCUtR device campaign, not the host identify spike. Keep the flag **default-off** until they land.
>
> Harness: `go-mknoon/node/quic_identify_revalidation_test.go`.

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
  `forcePublicReachabilityForTests` / `holePunchTracerForTests` Start-time seams
  (`SetForcePublicReachabilityForTests` `node.go:1984-1991` / `SetHolePunchTracerForTests` `:1975-1982`,
  applied before Start at the reachability branch `:345-350`), and the three existing
  feasibility/negative-control/label tests.

## Plan Review Delta — 2026-06-27 (verify→refute re-grounding, 7-agent)

> **Verdict: the core design is SOUND and the spike-gating is correct.** A 7-agent re-grounding against
> the live working tree confirmed every load-bearing premise — **no `network.Notifiee` is registered
> today** (`node.go` uses EventBus only), **`markPeerUpgradedToDirect` already re-points the upgrade
> half** (`holepunch_tracer.go:136-155`, verified zero-drift), **`transport:downgraded` does not exist**
> (genuinely net-new), and **`EnableDcutrUpgrade`/`UpgradeAbandonTimeout` are genuinely absent**. But the
> draft's line anchors drifted heavily and three test framings need correction. The corrected anchors and
> reframes below **supersede** the (stale) inline numbers elsewhere in this doc.

### 1. Anchor drift — node.go shifted +17..+40 lines (concurrent FDC-09 early-reserve edits); Dart ~+330; holepunch_tracer.go CLEAN

| Symbol | Draft anchor | **Corrected (working tree)** |
|---|---|---|
| `ForceReachabilityPrivate` (branch) | node.go:330 / :328-333 | **node.go:347** (branch :345-350; `ForceReachabilityPublic` swap :348-350) |
| hostOpts assembly | :338-347 | **:355-364** |
| `EnableHolePunching` | :343 | **:360** |
| `NATPortMap` | :344 | **:361** |
| listen addrs (QUIC+TCP+WS, v4+v6) | :298-315 | **:315-322** |
| `connectionInfo` struct | :113-116 | **:117-122** |
| `classifyStreamTransport` | :123-136 | **:129-142** |
| `isCircuitAddr` | :118-121 | **:124-127** |
| `watchConnectionEvents` | :1727-1783 | **:1769-1847** (EventBus subscribe :412-420; ConnectednessChanged :1775; LocalAddrs :1826) |
| Start `n.host=h` (Notifiee site) | :367 | **:384** (after SetStreamHandler :407-410 + EventBus.Subscribe :412-420) |
| delete-on-last-conn | :1774-1782 | **:1815-1822** |
| AutoRelay reservation | :348-358 | **:365-376** |
| test seams | :1922-1938 | **:1975-1991** |
| Dart `lastKnownGoodTransport` | :4100 | **:4431** |
| Dart `isConnectedToPeer` | :4092 | **:4423** |
| Dart `warmBackground` | :572-647 | **:649-725** |
| Dart sticky/reuse (send use-case) | :447-465 / :528-595 | **reuse :533-590 / sticky :615-681 / reads LKGT :610 / `recordSuccessfulTransport` :2003** |

holepunch_tracer.go anchors (`:15-17`, `:25-27`, `:33-104`, `:50-54`, `:56-76`, `:66-69`, `:136-155`,
`:29-32`) all **verified correct — zero drift**. Implementers: verify Go anchors by symbol, not line —
`node.go` is being actively edited by concurrent FDC work.

### 2. Reframe TC-12-09 — the `transport:upgraded` consumer ALREADY EXISTS (FDC-13); FDC-12 EXTENDS it

FDC-13 (landed) added `case 'transport:upgraded'` at **p2p_service_impl.dart:3290-3293**, which calls
`recordRelayToDirectUpgrade()` + `_recordPeerUpgrade()` → `_peersUpgradedToDirect` (drives the
`'upgraded'` **badge** via `_inferTransportForPeer` :3303-3314). It does **NOT** call
`recordSuccessfulTransport` (:4456-4460), so `_learnedTransport` / `lastKnownGoodTransport` is **never
updated on upgrade** and the sticky/reuse fast-path keeps choosing `relay`.
- **The TC-12-09 RED *reason* as drafted ("p2p_service doesn't consume transport:upgraded") is STALE** —
  it does consume it (for the badge). The **outcome** (LKGT stays `relay`) is still RED-accurate.
- **Corrected RED reason:** "the existing FDC-13 handler (`:3290-3293`) updates only the badge set
  `_peersUpgradedToDirect`, not the sticky cache `_learnedTransport`; sticky reuse still picks `relay`."
- **Corrected fix seam:** EXTEND the existing `:3290-3293` case with `recordSuccessfulTransport(<fullPeerId>,
  'direct')`. **Do NOT** touch FDC-13's badge logic (scope-guard).
- **Sharpened discriminator:** assert the upgrade flips **both** `lastKnownGoodTransport==direct` (FDC-12,
  new) **AND** the existing `'upgraded'` badge still surfaces (FDC-13, preserved) — proving FDC-12 adds the
  sticky write without regressing the badge.
- **Payload gap (NEW, blocks the fix):** the event carries only `remotePeerShort`, but `_learnedTransport`
  is keyed by **full peer id**. FDC-12 must either (a) add the full remote peer id to the Go emit
  (`holepunch_tracer.go:70-75`, folds into TC-12-07's payload extension) **or** (b) add a Dart short→full
  resolver. Pick before RED.

### 3. Reframe TC-12-10 / flag home — there is NO Dart `NodeConfig`; the flag is a Go `FeatureFlags` entry

The draft says "add `enableDcutrUpgrade` to the Dart NodeConfig DTO (`main.dart:1893-1914`)". **No Dart
`NodeConfig` class exists.** Flags travel as a JSON FeatureFlags map: Dart `StartNode` params →
`bridge.go:565-574` (FeatureFlags :572) → `NodeConfig` build :585-594 → `n.Start(cfg)` :596.
- Put `EnableDcutrUpgrade` in **`feature_flags.go`** (struct :8-32 + `DefaultFeatureFlags()` :35-44),
  consistent with sibling **FDC-11's `EnableLibp2pLANDial`**. ⚠ **Every existing FeatureFlag defaults
  `true`; this one must default `false`** — amend the struct's "All flags default to true" doc-comment and
  set `false` explicitly in `DefaultFeatureFlags()`.
- TC-12-10 becomes: "default `EnableDcutrUpgrade==false` survives `DefaultFeatureFlags()` (the lone false
  flag); explicit Dart `enableDcutrUpgrade:true` plumbs to `cfg.FeatureFlags.EnableDcutrUpgrade`." Mutation:
  make `DefaultFeatureFlags()` return `true` → default-false assert reds.

### 4. REFUTED — the `connections` map is NOT shared with group pubsub

`pubsub.go` / `pubsub_delivery_test.go` never touch `connections`; its only consumers are `Status()`
(:588-594), `State()` (:641), `watchConnectionEvents` (:1800/:1817). So the Scope-Guard "don't disturb
group pubsub connections" and the blind-spot "pubsub shares the map" are **mis-grounded**. Keep
`pubsub_delivery_test.go` as a cheap sentinel, but **the real sibling-surface risk is `Status()/State()`
JSON** — the re-point mutates `Limited`/`Address`, which both 1:1 AND group Dart connection-status surfaces
read via the state snapshot. Re-targeted in the Blind-Spot Sweep below.

### 5. NEW obligation — downgrade must clear the FDC-13 `'upgraded'` badge (invariant-under-new-transition)

TC-12-05 adds `transport:downgraded` Go-side, but the draft never traces it to Dart. After a direct conn
dies, if `_peersUpgradedToDirect` is not cleared, `_inferTransportForPeer` keeps returning `'upgraded'` —
**the badge lies and sticky reuse keeps choosing a dead direct leg.** Add Go emit/forward of
`transport:downgraded` (`bridge/events.go` + `OnEvent` `bridge.go:48-55`) **and a new Dart-host test
TC-12-09b** (in the RED catalog + matrix below).

### 6. Device-proof harness route correction (TC-12-12/13)

The draft registers the device-proof as a `/sims 1to1 --only N` **dart-define sim scenario**
(`DCUTR_UPGRADE=1`). **No 1:1 simulator-scenario dispatch exists** (only `GROUP_SIM_SCENARIO` via
`group_lifecycle_simulator_harness.dart`), and DCUtR needs **real NAT** a sim (shared host stack) cannot
model — wrong on both counts. Correct tier = **device-proof**: NEW `integration_test/dcutr_upgrade_proof_test.dart`
(`@Tags(['device'])`), registered via a `classify_path()` **'device-proof' case** (template: the 1:1 proof
case `integration_test/conversation_swipe_back_proof_test.dart` ~:246-248) **+ an orchestrator `--scenario`
case** (a 1:1 `run_*_device_real.dart` scenario must be added — none exists yet; net-new harness work).

### 7. Acceptance-gate fix — `GOTOOLCHAIN=go1.25.0` is mandatory

System Go is 1.26.4; `go.mod` pins `go 1.25.0`; Makefile / `run_host_test_gates.sh` use plain `go test`
(no toolchain prefix) → Go 1.26 **panics** (`crypto/tls … session ticket`, quic-go v0.49). Every `go test`
gate below is now prefixed `GOTOOLCHAIN=go1.25.0`.

### 8. Cross-plan notes

- **FDC-11 collision (real, manageable):** FDC-11 also edits the `node.go` reachability branch + adds
  `FeatureFlags.EnableLibp2pLANDial`, `lan_dial.go`, and config consts. Land/rebase **FDC-12 after
  FDC-11**; share the single reachability opt (FDC-12 branches it on `EnableDcutrUpgrade`); keep
  `UpgradeAbandonTimeout=750ms` as the single source of truth in `config.go`; if FDC-11 also registers a
  `network.Notifiee`, **use one shared registration site** (don't double-Notify).
- **FDC-14b (`NodeState.directReady`) candidate producer:** FDC-14 shipped the field default-false with an
  **unowned** producer (FDC-14b). FDC-12's relay→direct upgrade is a natural producer candidate —
  cross-referenced (not owned here) so FDC-14b can wire it.
- **FDC-S2 750ms:** confirmed as executable test logic (`quic_identify_revalidation_test.go` `s2Budget`
  :220-221), NOT yet a production constant — FDC-12 adds the production `UpgradeAbandonTimeout`.

## Session Classification

**evidence-gated (DRAFT)** — FDC-S2 resolved the **identify portion** (Option A; abandon-timeout 750ms), so
the host-loopback feasibility/scaffolding layer is **implementation-ready now** (seams exist). The production
reachability flip + measured punch payoff + RTT/UPnP tuning remain **device-only** (NOT resolved by S2).
Device-proof is the closure gate; keep the flag default-off until then.

## Exact Problem Statement

**What's missing.** Production runs `libp2p.ForceReachabilityPrivate()` (`node.go:347`), which makes
the DCUtR hole-puncher **observation-only**: `EnableHolePunching` is wired (`node.go:360`) and the
production tracer is installed (`holepunch_tracer.go:25-27`, via the hole-punch opts near `node.go:360`), but **zero** relay→direct
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
EventBus subscription (`node.go:1769-1847`) that will therefore **miss the upgrade** — the map keeps
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
  `node.go:129-142`).
- Receiver **`messageId` dedup** stays the correctness backstop (§10 LAN double-delivery note); the
  upgrade must never produce a *visible* duplicate even if a leg can't be cancelled.
- Connection-count stability: no phantom upgrade/downgrade thrash (the
  `holepunch_negative_control_test.go` invariant).

## Root Cause (verify→refute confirmed)

- **Mechanism (config, not capability):** `reachabilityOpt := libp2p.ForceReachabilityPrivate()`
  (`node.go:347`) → the holepuncher never *initiates* an active punch in production; `EnableHolePunching`
  (`node.go:360`) + the installed tracer only *observe*. **Verified** in source and explicitly stated
  at `holepunch_tracer.go:15-17`.
- **Second-connection mechanism (verified):** on `EndHolePunchEvt{Success}` the tracer already emits
  `transport:upgraded` and calls `markPeerUpgradedToDirect` (`holepunch_tracer.go:56-76`), which under
  `n.mu` clears `Limited` and re-samples `Address` from the first **non-circuit** conn
  (`holepunch_tracer.go:136-155`). So a *partial* re-point exists — but it (a) only fires from the
  tracer callback, (b) is **dead in production** because no punch ever fires, and (c) is **not** a
  durable Notifiee-driven session layer (it doesn't react to the direct conn closing back to relay-only,
  nor prefer TCP, nor coordinate with the Dart send fast-path).
- **Connections map is EventBus-driven, not Notifiee-driven (verified):** `watchConnectionEvents`
  (`node.go:1769-1847`) reacts to `EvtPeerConnectednessChanged`/`EvtLocalAddressesUpdated` only, and
  libp2p does **not** re-fire connectedness on an in-place upgrade — so without the dedicated path the
  map silently goes stale (`holepunch_tracer.go:66-69`).
- **TCP lane already listened (verified):** listen addrs include `/tcp/0` and `/tcp/0/ws` alongside
  `quic-v1` (`node.go:315-322`); `classifyStreamTransport` is circuit-vs-direct only (`node.go:129-142`),
  so a punched TCP conn already classifies `direct`. The gap is *preferring/observing* the TCP lane on
  upgrade and a feasibility lock that it punches, not new transports.
- **UPnP/PMP already requested (verified):** `libp2p.NATPortMap()` (`node.go:361`) — FDC-S2 must
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
- A **production flag** (`FeatureFlags.EnableDcutrUpgrade`, default **false** — re-grounded: it lives in the
  Go `FeatureFlags` struct, the lone default-false flag, NOT a top-level/Dart `NodeConfig` field) that, when
  ON, lets DCUtR *actively* upgrade a relay conn to direct. The flag's mechanism (off
  `ForceReachabilityPrivate`, or AutoNAT-gated) is **`<from FDC-S2>`** (DEVICE-ONLY — FDC-S2 resolved
  direct-conn identify but **not** the production flip-safety) — DRAFT assumes "do not force private when
  flag ON, keep forcing private when OFF."
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
- Dart consumption: **EXTEND the existing FDC-13 `transport:upgraded` handler** (`p2p_service_impl.dart:3290-3293`,
  today badge-only) to also write `lastKnownGoodTransport` (`:4431`) via `recordSuccessfulTransport`, so the
  next send's sticky/reuse fast-path uses the direct conn; **add a new `transport:downgraded` handler** that
  reverts the badge + sticky; pass the flag through the **feature-flags map** to the Go bridge (no Dart
  `NodeConfig`). **Send-path decision unchanged.**

**Out of scope (owning FDC-xx)**
- LAN/mDNS unification, `DefaultDialRanker`, `WithForceDirectDial` for LAN → **FDC P2-1** (§6.5 mDNS).
- The concurrent-inbox / staggered ranked race / warmPeer → **FDC P0-1/P0-2/P0-3**.
- Relay presence lookup, durable Redis backend → **FDC P1-1 / P2-2**.
- Pause-flush / lifecycle handoff → **FDC P1-2**.

## Files To Inspect Next

**Production — Go**  *(anchors re-grounded 2026-06-27; node.go drifted +17..+40 lines — verify by symbol)*
- `go-mknoon/node/node.go` — reachability opt `:347` (branch `:345-350`, `ForceReachabilityPublic` swap
  `:348-350`); hostOpts assembly `:355-364`; `EnableHolePunching` `:360`; `NATPortMap` `:361`; listen addrs
  (QUIC+TCP+WS, v4+v6) `:315-322`; `connectionInfo` struct `:117-122`; `classifyStreamTransport` `:129-142`;
  `isCircuitAddr` `:124-127`; `watchConnectionEvents` `:1769-1847` (EventBus subscribe `:412-420`;
  `EvtPeerConnectednessChanged` `:1775`; `EvtLocalAddressesUpdated` `:1826`); Start sets `n.host=h` `:384`
  (Notifiee registers here, after `SetStreamHandler` `:407-410` + `EventBus.Subscribe` `:412-420`);
  delete-on-last-conn `:1815-1822`; AutoRelay reservation `:365-376`; test seams
  `SetHolePunchTracerForTests` `:1975-1982` / `SetForcePublicReachabilityForTests` `:1984-1991`.
  **`connections` map is NOT shared with pubsub** — only `Status()` `:588-594`, `State()` `:641`,
  `watchConnectionEvents` `:1800/:1817` read it.
- `go-mknoon/node/holepunch_tracer.go` — production tracer `:25-27`/`:33-104`; `transport:upgraded` emit
  `:70-75` + `markPeerUpgradedToDirect` call `:76`; `markPeerUpgradedToDirect` body (Lock `:137`,
  `Limited=false` `:145`, non-circuit `Address` re-sample `:147-151`) `:136-155`; RTT surface
  (`rttMs: e.RTT.Milliseconds()` `:52`) `:50-54`. *(All holepunch_tracer.go anchors verified ZERO drift.)*
- `go-mknoon/node/feature_flags.go` — **flag home.** Add `EnableDcutrUpgrade bool` to `FeatureFlags`
  `:8-32` + `DefaultFeatureFlags()` `:35-44`. **⚠ Convention break:** every existing flag defaults `true`;
  `EnableDcutrUpgrade` is the lone **default-false** flag (mirrors FDC-11's `EnableLibp2pLANDial`); amend the
  "All flags default to true" doc-comment.
- `go-mknoon/node/config.go` — **timeout home.** Add `UpgradeAbandonTimeout = 750ms` (FDC-S2 Option A) to the
  Timeouts const block `:28-41` (next to `ForegroundRelayDialTimeout`). `NodeConfig` struct `:150-166`; no
  `NewNodeConfig` constructor (defaults via helpers like `EffectiveKeyRotationGracePeriod()` `:190-195`).
- `go-mknoon/bridge/bridge.go` — **flag plumbing.** Thread `EnableDcutrUpgrade` through the `StartNode`
  params struct `:565-574` (FeatureFlags field `:572`) → `NodeConfig` build `:585-594` → `n.Start(cfg)`
  `:596`. `go-mknoon/bridge/events.go:22` already documents `transport:upgraded`; **`transport:downgraded`
  must be added there + forwarded** via the `OnEvent` chain `bridge.go:48-55`.
- **NEW** `go-mknoon/node/peer_session.go` — the Notifiee-backed session re-point layer (this plan creates
  it). Register via `h.Network().Notify(...)` in `Start` after `n.host=h` `:384`.

**Production — Dart**  *(anchors re-grounded 2026-06-27; p2p_service_impl.dart drifted ~+330 lines)*
- `lib/core/services/p2p_service_impl.dart` — **the `transport:upgraded` handler ALREADY EXISTS** (FDC-13)
  at `:3290-3293`: it calls `recordRelayToDirectUpgrade()` + `_recordPeerUpgrade()` → `_peersUpgradedToDirect`
  set (badge only). `_inferTransportForPeer` returns `'upgraded'` from that set `:3303-3314`.
  `recordSuccessfulTransport` (writes `_learnedTransport`) `:4456-4460`; `lastKnownGoodTransport` `:4431`;
  `isConnectedToPeer` `:4423`; `warmBackground` `:649-725` (context only). **FDC-12 EXTENDS the existing
  `:3290-3293` case (adds the sticky write) and adds a NEW `transport:downgraded` case — it does NOT add a
  new upgrade consumer.**
- `lib/main.dart` — **there is NO Dart `NodeConfig` class.** Flags reach Go as a JSON FeatureFlags map
  handed to `StartNode`; `LocalP2PService` is constructed `:1933` (the draft's `:1893-1914` is wrong). Pass
  `enableDcutrUpgrade:false` through the existing feature-flags map, not a DTO field.
- `lib/features/conversation/application/send_chat_message_use_case.dart` — reuse `:533-590`, sticky
  `:615-681`, reads `lastKnownGoodTransport` `:610`, calls `recordSuccessfulTransport` after a delivered send
  `:2003` (READ-ONLY context; FDC-12 must NOT alter the decision — it only feeds a fresher
  `lastKnownGoodTransport`).

**Tests (existing, this area)**
- `go-mknoon/node/holepunch_feasibility_test.go` — loopback relay→direct upgrade proof (forced-public
  seam, helper `startNW002RelayNodeWithTracer` `:35-62`); `classifyStreamTransportConn` helper `:156-169`;
  SKIP-not-fail logic `:115-119` (design note `:15-20`).
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
| transport integration suite (`background_reconnect`, `wifi_relay_fallback_smoke`, `transport_e2e`, `warm_peer_lan_aware_smoke`) | EXISTS (TRANSPORT_TESTS, 5 files) | `run_test_gates.sh transport` |
| `transport:upgraded` Dart handler | **EXISTS (FDC-13, `p2p_service_impl.dart:3290-3293`) — badge ONLY** (`_peersUpgradedToDirect`); does NOT write `_learnedTransport` | n/a |
| `transport:upgraded` → **sticky `lastKnownGoodTransport`** write (TC-12-09) | **MISSING** (extend the FDC-13 handler) | `run_test_gates.sh 1to1` |
| `transport:downgraded` → revert badge + sticky (TC-12-09b) | **MISSING** (no Dart case; no Go emit) | `run_test_gates.sh 1to1` |
| Notifiee-driven session re-point unit test (TC-12-03..06) | **MISSING** (`peer_session.go` does not exist) | `GOTOOLCHAIN=go1.25.0 go test ./...` |

## RED Test Catalog  (BEFORE any prod code)

> Tiers: **Go-unit** (node package, host, `go test`), **Go-feasibility** (loopback forced-public seam,
> may SKIP), **Dart-host** (`run_test_gates.sh 1to1`), **DEVICE-PROOF** (closure gate — `/sims` /
> real-device, cannot run on host). Distinct-event discriminator throughout: `transport:upgraded`
> (relay→direct) vs `transport:downgraded` (direct→relay fallback) vs `peer:connected` (initial),
> because all three leave the peer "connected".

### Go-unit / host

**TC-12-01 — flag OFF preserves ForceReachabilityPrivate + ZERO punches (PRESERVATION).**
`node/dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches`
- Tier: Go-unit. Setup: Start a node with `NodeConfig{FeatureFlags: DefaultFeatureFlags()}` (the flag is a
  **`FeatureFlags.EnableDcutrUpgrade`** entry, NOT a top-level `NodeConfig` field — re-grounded; see Delta
  §3) + an injected counting tracer + a local circuit relay; reserve; idle the punch window.
- RED-on-HEAD-because: `FeatureFlags.EnableDcutrUpgrade` doesn't exist → won't compile (the canonical RED
  for a new field).
- GREEN-asserts: **`DefaultFeatureFlags().EnableDcutrUpgrade==false`** (⚠ the lone default-false flag — all
  others default true), host built with `ForceReachabilityPrivate()` (assert via the same observable the
  feasibility test uses — no active punch), tracer `Successes()==0`, no `transport:upgraded` event.
- Mutation-that-re-reds: (a) make `DefaultFeatureFlags()` return `EnableDcutrUpgrade:true` → default-false
  assert reds; (b) make the flag-off branch use `ForceReachabilityPublic()` → punch/Successes may fire →
  red. **This is the `holepunch_tracer.go:15-17` invariant lock.**

**TC-12-02 — flag ON selects the upgrade reachability mode.**
`node/dcutr_upgrade_flag_test.go::TestDcutrFlagOn_SelectsUpgradeReachability`
- Tier: Go-unit. Setup: `FeatureFlags{EnableDcutrUpgrade:true}`; assert the chosen reachability opt is the
  upgrade mode **`<from FDC-S2>`** (not-force-private vs AutoNAT-gated). DRAFT asserts "not
  `ForceReachabilityPrivate`". Branch the opt at `node.go:347` (re-grounded).
- RED-on-HEAD-because: no flag → field/branch absent.
- GREEN-asserts: flag-ON path constructs the upgrade-permitting host opt; flag-OFF path unchanged.
- Mutation: invert the flag→opt mapping → red.
- **Collision note:** FDC-11 also branches this reachability opt — share one branch keyed on both flags
  (`EnableLibp2pLANDial` || `EnableDcutrUpgrade`), don't write two competing branches (Delta §8).

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
- **Distinct-trigger discriminator (CRITICAL — else this just re-tests `markPeerUpgradedToDirect`):** drive
  this **without firing a tracer `EndHolePunchEvt`**. The existing `markPeerUpgradedToDirect`
  (`holepunch_tracer.go:136-155`) already re-points, but only from the tracer callback. TC-12-03 must prove
  the **Notifiee path** re-points independently of the tracer (the EventBus/tracer gap the feature exists to
  close). Assert the re-point happens with the tracer's `Successes()` still `0`.

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
  preserving the `node.go:1815-1822` semantics).
- Mutation: delete the peer on any disconnect → red (peer wrongly offline while circuit alive).
- Discriminator: `transport:downgraded` vs `peer:disconnected`.
- **Wire-through obligation:** `transport:downgraded` is net-new end-to-end — it must also be added to
  `bridge/events.go` + forwarded (`bridge.go:48-55`) and consumed Dart-side (see NEW **TC-12-09b**) so the
  FDC-13 `'upgraded'` badge does not lie after the direct conn dies.

**TC-12-06 — no phantom upgrade/downgrade thrash (NEGATIVE CONTROL, mirrors existing).**
`node/peer_session_test.go::TestPeerSession_NoThrash_StableConnCount`
- Tier: Go-unit. Setup: repeated identical `Connected` callbacks for the *same* direct conn.
- RED-on-HEAD-because: a naive Notifiee re-emits on every callback.
- GREEN-asserts: exactly ONE `transport:upgraded` across N duplicate callbacks; `ConnsToPeer` count
  stable (parity with `holepunch_negative_control_test.go:144-145`).
- Mutation: drop the idempotency guard → N events → red.

**TC-12-07 — RTT + elapsed (+ full peer id) surfaced on `transport:upgraded` (telemetry + plumbing lock).**
`node/holepunch_tracer_test.go::TestTracer_EmitsRttAndElapsed` (extend existing file; slot **after
`TestHolePunchTracer_FailureAndNoEnd_NoSuccessEmitted` :153-219**).
- Tier: Go-unit. Setup: drive `StartHolePunchEvt{RTT}` then `EndHolePunchEvt{Success,EllapsedTime}`.
- RED-on-HEAD-because: today `holepunch:attempt{step:started}` carries `rttMs` (`:52`) but the
  **`transport:upgraded`** payload (`:70-75`) carries only `elapsedMs` + `remotePeerShort` — add
  `rttMs`/sync-window **and the full remote peer id** the spike + the Dart sticky write need. New assert
  fails on HEAD.
- GREEN-asserts: `transport:upgraded` includes `rttMs`, the **full remote peer id** (so the Dart handler can
  key `recordSuccessfulTransport` — see TC-12-09 payload gap), and the `<from FDC-S2>` sync-window field.
- Mutation: drop any field → red.

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

**TC-12-09 — `transport:upgraded` ALSO populates the sticky cache `lastKnownGoodTransport` (EXTENDS FDC-13).**
`test/core/services/p2p_service_transport_upgrade_test.dart::populates sticky transport on upgrade`
- Tier: Dart-host. Setup: fake bridge emits `transport:upgraded{remotePeer:<full P>, …}` for peer P after a
  relay send.
- RED-on-HEAD-because (**REFRAMED — re-grounded 2026-06-27**): the `transport:upgraded` handler **already
  exists** (FDC-13, `p2p_service_impl.dart:3290-3293`) but updates **only** the badge set
  `_peersUpgradedToDirect` — it never calls `recordSuccessfulTransport`, so `_learnedTransport` /
  `lastKnownGoodTransport(P)` stays `relay`. (The draft's "doesn't consume the event" reason was stale.)
- GREEN-asserts: extend the existing `:3290-3293` case to call `recordSuccessfulTransport(P,'direct')` →
  `lastKnownGoodTransport(P)=="direct"` so the next send's sticky fast-path
  (`send_chat_message_use_case.dart:615-681`, reads LKGT `:610`) reuses direct.
- Mutation: remove the new `recordSuccessfulTransport` call → stays `relay` → red.
- **Sharpened discriminator (no-regress on FDC-13):** assert the upgrade flips **both**
  `lastKnownGoodTransport==direct` (FDC-12, new) **AND** the existing `'upgraded'` badge still surfaces via
  `_inferTransportForPeer` (FDC-13, preserved). Proves FDC-12 adds the sticky write without touching the
  badge.
- **Payload-keying obligation:** the handler currently receives only `remotePeerShort`; `_learnedTransport`
  is keyed by **full** peer id → depends on TC-12-07 adding the full peer id to the Go emit (or a Dart
  short→full resolver). Name the choice before RED.
- **Scope-guard:** do NOT alter FDC-13's `_recordPeerUpgrade` / `_peersUpgradedToDirect` / badge logic.

**TC-12-09b — `transport:downgraded` reverts the FDC-13 badge + resets sticky (NEW; invariant-under-transition).**
`test/core/services/p2p_service_transport_upgrade_test.dart::downgrade reverts upgraded badge and sticky`
- Tier: Dart-host. Setup: after an upgrade made P `'upgraded'`, the fake bridge emits
  `transport:downgraded{remotePeer:<P>}` (direct conn died).
- RED-on-HEAD-because: **no `transport:downgraded` case exists** in `p2p_service_impl` → P stays in
  `_peersUpgradedToDirect` → `_inferTransportForPeer(P)` keeps returning `'upgraded'` (the badge lies) and
  `lastKnownGoodTransport(P)` keeps returning `direct` (sticky keeps a dead leg).
- GREEN-asserts: a NEW `case 'transport:downgraded'` removes P from `_peersUpgradedToDirect` (badge reverts
  to `relay`/`direct` from live conns) AND clears/resets `lastKnownGoodTransport(P)` so the next send
  re-probes.
- Mutation: drop the `_peersUpgradedToDirect.remove` → badge stays `'upgraded'` after downgrade → red.
- Discriminator: assert reaction to `transport:downgraded`, NOT `peer:disconnected`.
- Registration: same file as TC-12-09 → appended to `ONE_TO_ONE_TESTS`.

**TC-12-10 — flag defaults OFF and plumbs through `FeatureFlags` (NOT a Dart NodeConfig).**
`test/core/services/p2p_service_dcutr_flag_test.dart::passes enableDcutrUpgrade default false`
- Tier: Dart-host (+ a Go-unit half on `DefaultFeatureFlags()`). Setup: build the service with defaults;
  capture the **FeatureFlags map** handed to the Go bridge `StartNode` (re-grounded: there is **no Dart
  `NodeConfig` class** — Delta §3).
- RED-on-HEAD-because: no `enableDcutrUpgrade` key in the feature-flags map / `FeatureFlags` struct.
- GREEN-asserts: the default feature-flags map omits or sets `enableDcutrUpgrade:false`; explicit `true`
  plumbs through to `cfg.FeatureFlags.EnableDcutrUpgrade`.
- Mutation: hardcode `true` (or make `DefaultFeatureFlags()` default it true) → default-false assert red.

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
- File: **NEW `integration_test/dcutr_upgrade_proof_test.dart`** (`@Tags(['device'])`).
- Two real devices on the §12 punchable mix (one cone-NAT/public), flag ON: an established relay
  conversation upgrades to direct within `<from FDC-S2>` ms; subsequent sends label `direct`; relay
  socket no longer carries chat; **user never observed a stall** (relay+inbox carried until punch).
- **Harness route (CORRECTED — re-grounded 2026-06-27):** this is a **device-proof**, NOT a `/sims`
  dart-define sim scenario. There is **no 1:1 simulator-scenario dispatch** (only `GROUP_SIM_SCENARIO`
  exists), and DCUtR needs **real NAT** a sim's shared host stack cannot model. Register via (a) a
  `classify_path()` **'device-proof' case** in `check_reliability_simulation_discovery.sh` (template: the
  1:1 proof case `integration_test/conversation_swipe_back_proof_test.dart` ~:246-248) **and** (b) an
  orchestrator `--scenario` case in a 1:1 `run_*_device_real.dart` — **none exists yet; adding the 1:1
  device-real orchestrator is net-new harness work this row owns.** `/sims` only RUNS it. **Cannot be
  host-proven** (§6.5/§10). This row is the closure gate, not the Go feasibility SKIP.

**TC-12-13 — symmetric-CGNAT cellular↔cellular gracefully does NOT upgrade (DEVICE-PROOF, negative).**
- Both peers behind symmetric CGNAT (§12 near-0 case): no punch, stays on relay+inbox, **no
  user-visible failure or delay**. Proves the "opportunistic, relay always backstops" contract.

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Flag OFF = prod default | ForcePrivate + 0 punches | Go-unit | `dcutr_upgrade_flag_test.go::TestDcutrFlagOff_ForcesPrivate_ZeroPunches` | `FeatureFlags.EnableDcutrUpgrade` absent (no compile) | default→true **or** flag-off→public | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| Flag ON = upgrade mode | not-force-private `<from FDC-S2>` | Go-unit | `…::TestDcutrFlagOn_SelectsUpgradeReachability` | flag absent | invert flag→opt | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| Session re-point (indep of tracer) | map→direct, 1 upgrade evt, `Successes()==0` | Go-unit | `peer_session_test.go::TestPeerSession_RepointsToDirectConn` | no Notifiee/file | no-op re-point | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| TCP lane equal QUIC | non-circuit pref TCP|QUIC | Go-unit | `peer_session_test.go::TestPeerSession_PrefersTcpOrQuicOverCircuit` | no selector | rank circuit top / QUIC-only | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| Graceful downgrade | relay fallback, no orphan | Go-unit | `peer_session_test.go::TestPeerSession_DirectClose_FallsBackToRelay` | no downgrade | delete-on-disconnect | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| No thrash | 1 evt / N callbacks | Go-unit | `peer_session_test.go::TestPeerSession_NoThrash_StableConnCount` | naive re-emit | drop idempotency | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| RTT+peerId telemetry | rttMs + full peer id on upgraded | Go-unit | `holepunch_tracer_test.go::TestTracer_EmitsRttAndElapsed` | fields absent | drop field | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| TCP punch classifies direct | TCP conn==direct | Go-feasibility | `holepunch_feasibility_test.go::TestFeasibility_DirectUpgrade_TcpLane` | no TCP assert (SKIP-able) | circuit→direct | `GOTOOLCHAIN=go1.25.0 go test ./...` | go pkg auto |
| Upgrade populates sticky (extends FDC-13) | LKGT→direct **+** badge preserved | Dart-host | `p2p_service_transport_upgrade_test.dart::populates sticky transport on upgrade` | FDC-13 handler updates badge only, never `_learnedTransport` | remove new `recordSuccessfulTransport` call | `./scripts/run_test_gates.sh 1to1` | **append to `ONE_TO_ONE_TESTS`** — `test/core/**` is NOT auto-globbed into the curated `1to1` gate (it runs under `core-host-all` / its own suite); explicit append required |
| Downgrade reverts badge+sticky (NEW) | badge→relay, LKGT reset | Dart-host | `p2p_service_transport_upgrade_test.dart::downgrade reverts upgraded badge and sticky` | no `transport:downgraded` case in p2p_service | drop `_peersUpgradedToDirect.remove` | `./scripts/run_test_gates.sh 1to1` | same file → append to `ONE_TO_ONE_TESTS` |
| Flag plumbs (default off) | enableDcutrUpgrade=false via FeatureFlags | Dart-host + Go-unit | `p2p_service_dcutr_flag_test.dart::passes enableDcutrUpgrade default false` | no `FeatureFlags`/map key | hardcode true / default→true | `./scripts/run_test_gates.sh 1to1` | **append to `ONE_TO_ONE_TESTS`** (Go half: go pkg auto) |
| No visible dup (preserve) | one bubble | Dart-host | `…dedup test::duplicate id renders once` | preservation (green on HEAD) | re-inject on upgrade | `./scripts/run_test_gates.sh 1to1` | `test/**` auto-globs (already in a gate) |
| Real upgrade fires+sticks | direct label, no stall | DEVICE-PROOF | `integration_test/dcutr_upgrade_proof_test.dart` (TC-12-12, closure) | host cannot punch real NAT | n/a (device) | `/sims 1to1 --only <N>` `<from FDC-S2>` | NEW `classify_path()` **'device-proof' case** + 1:1 `run_*_device_real.dart` **`--scenario`** (orchestrator is net-new; NOT a dart-define sim) |
| Symmetric-CGNAT graceful | no upgrade, no fail | DEVICE-PROOF | `dcutr_upgrade_proof_test.dart` (TC-12-13, negative) | host cannot model CGNAT | n/a (device) | `/sims 1to1 --only <N>` `<from FDC-S2>` | same proof file + `--scenario` case |

## Blind-Spot Sweep

- **Lifecycle / derived-state durability:** after upgrade, `lastKnownGoodTransport` must survive until
  the next send (TC-12-09) **and the FDC-13 `'upgraded'` badge + sticky must be REVERTED when the direct
  conn dies (TC-12-09b)** — otherwise the in-memory `_peersUpgradedToDirect` latch outlives the conn it was
  derived from (the classic derived-state-stale trap). A later background→resume must not resurrect a stale
  direct conn (background drops direct, §6.4); **TC-12-05** covers Go-side direct-close, **TC-12-09b** covers
  the Dart-side derived-state revert. On a network change (Wi-Fi↔cellular, §12 "closes all but QUIC") the
  direct conn may die → downgrade path (TC-12-05 + TC-12-09b) must fire; a re-punch is NOT auto-retried (§8
  P2-3 no-retries) — relay carries until a new organic upgrade. N/A for further retry logic by design.
- **Sibling-surface consistency (RE-GROUNDED — pubsub claim REFUTED):** the `connections` map is **NOT
  shared with group pubsub** (`pubsub.go`/`pubsub_delivery_test.go` never read it; verified 2026-06-27). The
  real shared surface is **`Status()` `:588-594` / `State()` `:641` JSON**, which serializes
  `Limited`/`Direction`/`Address` to Dart and feeds **both** the 1:1 and group connection-status surfaces.
  Obligation: assert the re-point's `Limited=false`/non-circuit `Address` flows through `Status()/State()`
  to Dart (`isConnectedToPeer` `:4423` still true; no peer spuriously dropped). Keep `pubsub_delivery_test.go`
  as a cheap regression sentinel (harmless), but the scope-guard rationale is "don't corrupt the
  Status()/State() snapshot," not "don't disturb pubsub conns."
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

1. **RED:** write TC-12-01/02 (flag) — they won't compile (no field). Seam: add **`EnableDcutrUpgrade bool`
   to `FeatureFlags` (`feature_flags.go:8-32`) + `DefaultFeatureFlags()` `:35-44` defaulting it `false`**
   (the lone false flag — amend the "all default true" doc-comment); add `UpgradeAbandonTimeout = 750ms` to
   the `config.go` Timeouts block `:28-41`; branch the `reachabilityOpt` at **`node.go:347`** on the flag
   (**Stop-if:** FDC-S2 hasn't ruled whether flag-ON drops `ForceReachabilityPrivate` or uses AutoNAT — DO
   NOT pick blind). Plumb the flag through `bridge.go:565-574/585-594/596` (TC-12-10).
2. **RED:** TC-12-03/04/05/06 — create `go-mknoon/node/peer_session.go`: a `network.Notifiee` (impl
   `Connected`/`Disconnected`) that calls a new `n.repointPeerToBestConn(peerID)` helper (mirror the
   `markPeerUpgradedToDirect` lock discipline, `holepunch_tracer.go:136-155`). Register it in `Start`
   after `n.host=h` (**`node.go:384`**) via `h.Network().Notify(...)` — **share one registration site with
   FDC-11 if it also Notifies.** Best-conn selector: prefer non-circuit (TCP==QUIC), idempotent (one event
   per real transition). **Reuse** `markPeerUpgradedToDirect` as the upgrade half; add the downgrade half
   (emit `transport:downgraded`, new in `bridge/events.go`).
3. **RED:** TC-12-07 — extend the `transport:upgraded` payload (`holepunch_tracer.go:70-75`) with
   `rttMs`, the **full remote peer id** (needed by the Dart sticky write, TC-12-09), and the
   `<from FDC-S2>` sync-window field; thread the last `StartHolePunchEvt.RTT` through.
4. **RED:** TC-12-08 — add the TCP-lane feasibility sibling (reuse `startNW002RelayNodeWithTracer` `:35-62`
   + `classifyStreamTransportConn` `:156-169`). SKIP-tolerant.
5. **RED:** TC-12-09/09b/10 (Dart) — **EXTEND the existing FDC-13 `transport:upgraded` case
   (`p2p_service_impl.dart:3290-3293`)** to also call `recordSuccessfulTransport(<fullPeerId>,'direct')`
   (→ `_learnedTransport`/`lastKnownGoodTransport` `:4431`); **add a NEW `case 'transport:downgraded'`** that
   removes the peer from `_peersUpgradedToDirect` and resets sticky; pass `enableDcutrUpgrade:false` through
   the **feature-flags map** handed to `StartNode` (there is **no Dart `NodeConfig` class**). **Do NOT touch
   FDC-13's badge logic or `send_chat_message_use_case.dart` logic.**
6. **Preservation:** run TC-12-11 + `pubsub_delivery_test.go` + the full `holepunch_*` suite green
   (`GOTOOLCHAIN=go1.25.0`).
7. **GREEN → mutation-verify** every row; then **DEVICE-PROOF** TC-12-12/13 (new `dcutr_upgrade_proof_test.dart`
   + 1:1 device-real orchestrator) as the closure gate.
8. **Stop-if blockers:** (a) FDC-S2 says the production flip is unsafe ⇒ keep flag default-off and ship
   only the host-observable scaffolding + telemetry, defer the flip; (b) the single-bridge serialization
   shows the Notifiee callback blocking sends ⇒ move re-point work fully off the bridge before enabling.

## Risks And Edge Cases

- **Flipping reachability in prod may regress AutoRelay reservation behavior** (`node.go:365-376`) →
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
  preservation, downgrade-badge-revert (TC-12-01..11 + 09b) close on `GOTOOLCHAIN=go1.25.0 go test ./...`
  + `run_test_gates.sh 1to1`.
- **Requires device (closure):** TC-12-12 (real punch fires+sticks) + TC-12-13 (symmetric-CGNAT
  graceful) — **device-proof** `integration_test/dcutr_upgrade_proof_test.dart` via a new 1:1
  `run_*_device_real.dart` `--scenario` (NOT a `/sims` dart-define sim — no 1:1 sim dispatch exists and a
  sim can't model real NAT), on a real-device pair on a punchable NAT mix. **The host feasibility SKIP
  (TC-12-08) is NOT a substitute** (§6.5/§10).

## Acceptance Gates  (literal; expected counts TODO until FDC-S2)

```
# GOTOOLCHAIN=go1.25.0 is MANDATORY — system Go is 1.26.x which PANICS (crypto/tls session ticket, quic-go v0.49).
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...           # expect: ok (all-pass baseline +new)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node/   # lock-discipline (Notifiee)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 make lint               # gofmt/vet/lint clean (new peer_session.go + feature flag)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./...     # unchanged (no relay edits)
./scripts/run_test_gates.sh 1to1            # expect: PASS (~1226 baseline) — adds transport-upgrade + downgrade + flag tests
./scripts/run_test_gates.sh transport       # expect: PASS (device/fixture-gated (skips on lone sim))
./scripts/run_host_test_gates.sh core-host-all   # expect: 0 fail
flutter analyze                              # expect: 0 new
git diff --check                             # expect: clean
# DEVICE-PROOF (closure, post-FDC-S2) — device-proof tier, NOT a /sims dart-define scenario:
./scripts/check_reliability_simulation_discovery.sh    # NEW dcutr_upgrade_proof_test.dart MUST list under '1to1' device-proof
/sims 1to1 --only <N>                       # runs integration_test/dcutr_upgrade_proof_test.dart on a real punchable pair
```

## Known-Failure Interpretation

- TC-12-08 **SKIP** (no loopback punch in CI window) = expected, NOT failure (parity with
  `holepunch_feasibility_test.go:15-20`). A `go test` SKIP is green for gate purposes.
- TC-12-12/13 cannot run on host → "host green ≠ validated" (§9 Phase-0 false-positive caveat); they
  remain OPEN until device-proof, like FDC-164's deferred-not-waived device rows.

## Done Criteria (checkbox)

- [x] FDC-S2 **identify portion** landed (Option A: direct QUIC reaches usable identify; **upgrade-abandon-timeout = 750ms**).
- [ ] DCUtR **device-only** items still owed (flip-safety / reachability mode, RTT-sync-window, real-NAT punch payoff, proof index `N`) — the FDC-12 DEVICE-PROOF closure gate; keep `EnableDcutrUpgrade` **default-off** until they land.
- [ ] `FeatureFlags.EnableDcutrUpgrade` added — **the lone default-false flag** (`DefaultFeatureFlags()` returns false; "all default true" doc-comment amended); plumbed `bridge.go`; flag-OFF byte-identical (TC-12-01 green + mutation-verified).
- [ ] `UpgradeAbandonTimeout = 750ms` added to `config.go` Timeouts (single source of truth, not duplicated in FDC-11).
- [ ] `peer_session.go` Notifiee re-point landed; TC-12-03/04/05/06 green + mutation-verified; TC-12-03 proven independent of the tracer (`Successes()==0`).
- [ ] Stop tears down the registered `network.Notifiee` (`h.Network().StopNotify(...)`) so no re-point fires after Stop — OR explicitly documents `host.Close()`/GC teardown reliance (parity with FDC-11's clear-on-Stop test).
- [ ] `transport:upgraded` carries RTT/sync telemetry **+ the full remote peer id**; TC-12-07 green.
- [ ] `transport:downgraded` emitted Go-side + forwarded via `bridge/events.go` (net-new event).
- [ ] Every NEW exported Go identifier (the `peer_session.go` Notifiee type/funcs, `FeatureFlags.EnableDcutrUpgrade`) carries a doc comment; `make lint`/`go vet` clean.
- [ ] TCP-lane feasibility TC-12-08 added (SKIP-tolerant).
- [ ] Dart EXTENDS the FDC-13 upgrade handler → `lastKnownGoodTransport` (TC-12-09, badge preserved); NEW `transport:downgraded` handler reverts badge+sticky (TC-12-09b); flag plumbs default-off (TC-12-10) — all green.
- [ ] Dedup preservation TC-12-11 green; FDC-13 badge logic + `send_chat_message_use_case.dart` UNCHANGED.
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...` + `-race` + `run_test_gates.sh 1to1`/`transport` + `core-host-all` green; analyze 0-new; `git diff --check` clean.
- [ ] DEVICE-PROOF TC-12-12/13 closed on a real punchable pair (device-proof `dcutr_upgrade_proof_test.dart` + new 1:1 device-real orchestrator; closure gate).

## Scope Guard (hard Do-not)

- **Do NOT** corrupt the `Status()`/`State()` connection snapshot during the re-point — the connections map
  is NOT shared with pubsub (re-grounded), but it IS serialized to Dart via `Status()` `:588-594` / `State()`
  `:641` and read by both 1:1 and group connection-status surfaces. **Floor:** `pubsub_delivery_test.go` stays
  green as a cheap regression sentinel (`GOTOOLCHAIN=go1.25.0 go test ./...`).
- **Do NOT** change `ForceReachabilityPrivate` default; flag-OFF must equal HEAD.
- **Do NOT** add retry/re-punch loops (§8 P2-3 / §12).
- **Do NOT** rebuild server store idempotency, `markPeerUpgradedToDirect`, or `transport:upgraded`.
- **Do NOT** touch FDC-13's Dart badge logic (`_recordPeerUpgrade` / `_peersUpgradedToDirect` / the
  `'upgraded'` return in `_inferTransportForPeer`) — FDC-12 only ADDS the sticky write + the downgrade revert.
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
- **Collision (sequential w/ FDC-11 = P2-1):** FDC-11 also edits the `node.go` reachability branch (`:347`),
  adds `FeatureFlags.EnableLibp2pLANDial`, `lan_dial.go`, and config consts (libp2p LAN-direct dial,
  `DefaultDialRanker` / `WithForceDirectDial`). **Land/rebase FDC-12 AFTER FDC-11.** Concrete merge rules:
  (a) **share one reachability branch** keyed on both flags, don't write two; (b) keep `UpgradeAbandonTimeout
  = 750ms` as the **single source of truth in `config.go`** (don't let both plans define it); (c) if FDC-11
  also registers a `network.Notifiee`, **use one shared `h.Network().Notify` site** at `node.go:384` — don't
  double-Notify; (d) both add a `FeatureFlags` entry + `bridge.go` plumbing — append, don't clobber.
- **Dart co-edit:** `lib/core/services/p2p_service_impl.dart` (the FDC-13 event-handler block `:3290-3293`)
  is the shared edit point; FDC-12 EXTENDS it (sticky write + downgrade case) without touching FDC-13's badge
  logic. `lib/main.dart` feature-flags map is co-edited by P0-1/P1-1 — append the key.
- **FDC-14b cross-ref:** `NodeState.directReady` (FDC-14, default-false, **unowned producer = FDC-14b**) — the
  FDC-12 relay→direct upgrade signal is a natural producer candidate; **not owned here**, flagged so FDC-14b
  can wire it.
- **No relay-server change** (additive presence/Redis are P1-1/P2-2) → `go-relay-server` untouched.
- **No DB migration.**
