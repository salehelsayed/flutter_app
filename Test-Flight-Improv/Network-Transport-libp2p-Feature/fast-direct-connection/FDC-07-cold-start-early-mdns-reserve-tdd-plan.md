# FDC-07 — Cold-start: earlier mDNS advertise/discover + relay reservation  (Feature Improvement)

Status: **S1 RESOLVED — reorder/sequencing slice implementation-ready; timeout/config slice CLOSED (no-op).** Awaiting-review of this re-grounded revision.

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.4 lifecycle / cold-start, §8 **P1-3**, §3 "cold open → empty discovered-peers map", §10 bullet 1, §11 Q3)

---

## ✅ FDC-S1 RESOLVED (2026-06-26) — this plan is no longer a DRAFT

**`FDC-S1` (cold-start timing spike) is EXECUTED on real devices** (Pixel 6 + iPhone 13) — see
`FDC-S1-cold-start-timing-RESULTS.md §4`. Every value previously marked **`<from FDC-S1>`** is now a
measured FACT, cited inline below; the gate is closed. The two slices resolve as follows:

- **Reorder/sequencing slice = IMPLEMENTATION-READY (host-testable).** Start bonsoir mDNS
  advertise/discover **earlier** (hoist it off the post-`node:start` fire-and-forget `warmBackground`
  body) and surface an **observable early-start anchor** for the relay warm. S1 confirms this is the
  genuine lever: the cold long-pole is the **Dart pre-`node:start` prologue**, not transport
  (`libp2pNewMs` 11–22 ms on both platforms).
- **Timeout/config slice = CLOSED as a NO-OP.** S1 §4 verdict: `FOREGROUND_RELAY_BUDGET_MS = keep 3 s`
  and `DIALTIMEOUT_RETIME = no` — `T_circuit` p90 is **1564 ms (Pixel 6) / 913 ms (iPhone 13)**, both
  inside the existing 3 s foreground budgets. **No `config.go` timeout value moves in FDC-07.** Step 5
  (the formerly-gated config edit) is permanently closed; TC-07-04 now LOCKS this executed verdict
  (it catches the refuted "cap to 3 s"), no longer a placeholder pending S1.

**Key S1-driven correction to the root cause (read before implementing):** the Go relay warm +
auto-register are **already dispatched at the earliest point in `Node.Start`** (immediately after the
`host_ready` emit) and S1 proves they are **sub-second and cheap** (`relay_warm_done` ~108–150 ms
after host_ready; `relayWarmMs` p90 313 ms; `circuitWaitMs` 202 ms). So the Go-side lever buys an
**observable anchor, NOT earlier latency** — there is no slow Go cadence to fix (RC3 restated below).
The absolute cold win lives in (a) the early **bonsoir-discovery hoist** (Dart-only, host-testable)
and (b) the **Dart pre-`node:start` prologue**, which is **plan-164's domain** (see Dependency Impact).
Device/relay rows remain the **closure gate** (real-wire cold timing is not host-reproducible).

> **Re-grounded 2026-06-27** (post-S1 review, 6-agent verify→refute): all `file:line` anchors
> re-pinned against `new-orbit` HEAD (the old anchors drifted **+53…+75 lines** in
> `p2p_service_impl.dart` and **+6…+31** in `node.go`); RC3 refuted; step 5 closed; device thresholds
> filled with the measured numbers; Go gate pinned to `GOTOOLCHAIN=go1.25.0`. See the **Re-Grounding
> Log** at the foot of this doc.

---

## Source Of Truth

- **Proposal** §6.4, §8 **P1-3**, §3, §10 (bullet 1), §11 (Q3) — `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md`.
- **`scripts/run_test_gates.sh` wins over prose** — the literal gate commands (`transport`, `1to1`,
  `feature-host-all`) are the acceptance authority; `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` for Go (toolchain pinned — Go 1.26.x panics, see Known-Failure Interpretation).
- **This epic's roadmap** — `FDC-00-roadmap.md` (Phase 1; Track D `FDC-07→11→{12,15}` on `node.go`/
  `config.go`; "serialize FDC-07's `p2p_service_impl` edits behind FDC-04"; Go-hygiene mandate = `make
  lint` **+ `go test -race`** for shared concurrent state; closure-list FDC-04/06/07/11/12 = real-wire
  device proof; FDC-07 is **move-feature "inherited-safe"** ONLY while the discovery start stays under
  the gated `warmBackground` — see Blind-Spot Sweep).
- **Gating spike — RESOLVED** — `FDC-S1-cold-start-timing-RESULTS.md` (executed numbers + the
  `DIALTIMEOUT_RETIME = no` / `keep-3 s` verdicts this plan now consumes). The spike doc
  `FDC-S1-cold-start-timing-measurement-spike.md` is the method/criteria reference.

## Session Classification

**implementation-ready** (post-S1). The *reorder/sequencing* slice (steps 1–4) is host-closable now;
the *budget/timeout* slice is **CLOSED as a no-op** by the executed S1 verdict (no `config.go` edit
lands). The "fast-path actually improves cold time-to-circuit" claim is **device-only** (host fakes
cannot reproduce real cold QUIC/TLS reserve timing — FDC-00 closure list); S1 already measured it
(`T_circuit` fits budget) so the device row is a **no-regression + observability** proof, not a
"must-improve-by-N-ms" proof (see TC-07-05).

## Exact Problem Statement

> **All `file:line` below re-pinned to `new-orbit` HEAD (2026-06-27).** The originals drifted +53…+75
> in `p2p_service_impl.dart` and +6…+31 in `node.go`. Verify by symbol, not by number, before editing.

On a **cold open** the discovered-peers map is empty, because LAN discovery is started *only after*
`node:start` returns, inside the **fire-and-forget** `warmBackground()` (`p2p_service_impl.dart:643`,
invoked `unawaited(_warmBackgroundSafely())` at `p2p_service_impl.dart:483`), and even then bonsoir
advertise/discover is buried in `_startLocalDiscovery` (`p2p_service_impl.dart:724`) which is added to
the warm-body `Future.wait` list (`:707-715`) **concurrently with** the inbox drain — not ahead of it.
So a same-WiFi peer must be (re)discovered *within the 1500 ms send budget*
(`send_chat_message_use_case.dart:21`) or the message silently falls through to direct/relay
(proposal §3). **S1 makes this worse than "discovery starts late" alone:** even when bonsoir runs,
Android `NsdManager` resolve is ~3.5 s and permission-gated/flaky (the app declares no
`NEARBY_WIFI_DEVICES`), so the LAN map frequently never populates inside the budget regardless of
*when* discovery starts (RESULTS §3.3/§3.3.1).

**The relay reservation, by contrast, is already early — S1 disproves the "leisurely cadence"
premise.** The relay-warm goroutine (`node.go:447-457 warmRelayConnectionForStart`) and auto-register
(`go n.autoRegisterPersonalNamespaceForStart()` at `node.go:482-483`) are dispatched **immediately
after** the `host_ready` emit (`node.go:434-439`), at the earliest synchronous point in `Node.Start`.
The "10 s" wait (`personal_rendezvous_refresh.go:17 waitForCircuitAddressForStart(10 * time.Second)`)
and the "15 s background `DialTimeout`" (`config.go:28`) are **MAX ceilings, not cadence delays** —
`waitForCircuitAddress` polls every 200 ms (`node.go:1739`) and exits on the first `/p2p-circuit`
address. On cold start there is **no explicit `reserveRelaySlot`** (`node.go:729` def is reconnect-only,
called `:927-931` in `refreshRelaySessionOwned`); the cold reservation is **libp2p-autorelay-implicit**
once the warm connection lands, surfaced as the `/p2p-circuit` address the auto-register polls. S1
measured all of this as sub-second (`relay_warm_done` ~108–150 ms after host_ready; `relayWarmMs`
p90 313 ms; `circuitWaitMs` 202 ms; `T_circuit` p90 913 ms iOS / 1564 ms Android — inside the 3 s
budget). So the cold gap is **not** a slow Go cadence: it is (1) bonsoir discovery starting late + the
Dart prologue ahead of `node:start`, and (2) the **absence of an OBSERVABLE early-start anchor** that
lets S1-style instrumentation prove the reserve is already early.

**Who feels it:** the user on "open app → send one message → close" and on cold notif-tap — the first
send in the first ~1.5–2 s after cold open finds no LAN map (and, on a true cold path, no circuit yet)
→ inbox even for a reachable peer (proposal §4 R5).

**What must improve:**
- bonsoir mDNS advertise/discover **starts earlier** in the cold-start sequence (hoisted out of the
  `warmBackground` futures list to a dedicated early seam at node-ready), so the LAN map has a chance
  to populate before the first send window — **kept strictly opportunistic** (the send/relay race
  never blocks on mDNS; S1 Criterion 5).
- The relay-reservation warm / circuit-address acquisition (already dispatched at node-ready) is given
  an **observable early-start anchor** (a `node:startup_timing` phase carrying `sinceProcessStartMs`)
  so FDC-S1-style instrumentation can *prove* the early start. This is an **observability** change, not
  a "make it start earlier" change — S1 shows there is no slower step to move it ahead of.

**What must stay unchanged (preserved sentinels):**
- **No timeout VALUE changes — now PERMANENT** (S1 verdict `DIALTIMEOUT_RETIME=no` / `keep 3 s`):
  `config.go:28 DialTimeout=15s`, `:39-41 ForegroundRelay*Timeout=3s`, `:76-77 Interactive*`
  (`InteractiveDialTimeout=4s`, `InteractiveSendTimeout=3s`) are byte-identical. (Preserved-sentinel
  test TC-07-04 = a Go config assertion locking these durations; it now encodes the *executed* S1
  decision, not a placeholder.)
- The send-path decision still lives in Dart `sendChatMessage`; Go only labels transport
  (`classifyStreamTransport node.go:129-142`) — reordering must not move any path decision into Go.
- `warmBackground` still runs (inbox drain + proactive-send-proof + health check) — we **pull the
  discovery start earlier** (and add the Go observability anchor), we do not delete the warm body.
- **The account-move network gate still wraps discovery.** Today bonsoir start is gated *transitively*
  because `warmBackground` checks `_allowsAccountNetworkSideEffects(...)` (`p2p_service_impl.dart:645`)
  before seeding the futures list. Hoisting `_startLocalDiscovery` out of that body must **re-assert
  the gate at the new early seam** or the move-feature "inherited-safe" property breaks (see Blind-Spot
  Sweep + Scope Guard).
- Existing NET-REL test locks (transport + 1to1 gates) stay green.

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, read & verified on `new-orbit` HEAD) | Why it produces the cold-start gap |
|---|---|---|
| RC1 | `p2p_service_impl.dart:483` fires `unawaited(_warmBackgroundSafely())` **after** `startNodeCore` returns; `warmBackground` (`:643`) does `_startHealthCheck()` (`:662`), schedules a **fire-and-forget** `Future.delayed(Duration(seconds:2), …)` fast-circuit fallback (`:667` — NOT awaited, runs outside the futures barrier), and only then seeds the warm futures list with proactive-send-proof + `_drainOfflineInbox` (`:701-704`) **and** `_startLocalDiscovery` (`:707-713`). | bonsoir advertise/discover is gated behind node-start **and** the `warmBackground` prologue → empty LAN map during the first send window (proposal §3). *(The 2 s `Future.delayed` does NOT sequentially block discovery — see RC2; the gate is that discovery sits inside the warm-body futures list, not the delay.)* |
| RC2 | `_startLocalDiscovery` (`:724-735`, the only cold-start `localP2P.start()`) is added to the warm-body futures and **awaited concurrently inside `Future.wait(futures)` (`:715`)** alongside `_drainOfflineInbox` — not ahead of it. | LAN discovery competes with inbox drain on the same warm pass instead of starting first; on Android the slow/flaky `NsdManager` resolve (S1 ~3.5 s) then routinely misses the send window even once started. |
| RC3 ⚠ **restated post-S1** | The relay-warm goroutine (`node.go:447-457`) and auto-register (`go n.autoRegisterPersonalNamespaceForStart()` `:482-483`) are dispatched **immediately after** the `host_ready` emit (`:434-439`) — the earliest synchronous point in `Node.Start`. The "10 s" (`personal_rendezvous_refresh.go:17`) and "15 s `DialTimeout`" (`config.go:28`, via `BackgroundTimeouts()` `:116-123`) are **MAX ceilings**: `waitForCircuitAddress` polls every 200 ms (`node.go:1739`) and exits on first `/p2p-circuit` addr. On cold start there is **no explicit `reserveRelaySlot`** (`:729` def is reconnect-only, called `:927-931`); the cold reservation is **libp2p-autorelay-implicit**. | The reservation is **NOT** on a leisurely cadence — S1 proves it is already sub-second (`relay_warm_done` ~108–150 ms after host_ready; `relayWarmMs` p90 313 ms; `circuitWaitMs` 202 ms). The actual gap is the **absence of an OBSERVABLE early-start anchor** (so instrumentation cannot prove the early start) + the upstream Dart prologue. FDC-07's Go lever = **add the anchor**, not move the dispatch. |

**Refuted — do NOT re-introduce:**
- ❌ "RC3: the reservation is on a leisurely background cadence." **REFUTED** (S1 + code, 2026-06-27):
  warm + auto-register fire at the earliest point in `Node.Start` (`node.go:447-457`/`:482-483`,
  right after `host_ready` `:434-439`) and complete sub-second. There is **no slower Go step to move
  it ahead of**; the Go-side change is observability only. Do not re-frame FDC-07 as "make the Go
  reserve start earlier."
- ❌ "Cap the cold relay dial to 3 s." **REFUTED by the executed S1 verdict** (`DIALTIMEOUT_RETIME=no`,
  RESULTS §4.2): `config.go:28 DialTimeout=15s` is consumed by the **fire-and-forget** warm goroutine
  (`node.go:447-457 warmRelayConnectionForStart`), **not** the user's send (which uses
  `ForegroundRelay*Timeout=3s` `:39-41` and `Interactive*` `:76-77`); S1 found nothing on the send
  path tracking 15 s and `T_circuit` p90 1564 ms / 913 ms already inside 3 s. Capping it risks
  abandoning a slow-but-succeeding cold QUIC/TLS handshake → **more** inbox fallback. **TC-07-04 is the
  permanent regression lock for this.**
- ❌ "Warm dials the contact eagerly on cold tap." That is **FDC-04** (`warmPeer`), not FDC-07; and on
  the coldest path the Go node isn't started yet so a dial can't overlap reading time (proposal §6.1
  "Honest scope"; S1 §3.4 — the libp2p host is not in the iOS NSE). FDC-07 is *node-start + early
  reserve-anchor/mDNS*, not per-peer warm.
- ❌ "Decouple `node:start` to await only `bridge.initialize()` instead of all of `startLiveServices`."
  Real residual Dart headroom (`main.dart:3097-3135`), but it is **plan-164-owned** restructuring of
  the `_ensureRuntimeServicesReady` idempotent future — out of FDC-07 scope; naively reordering it
  collides with 164 (see Dependency Impact).

## Real Scope

**In scope:**
- Hoist the cold-start sequence so **bonsoir advertise/discover starts earlier** (a dedicated
  early-start seam invoked at/just-after node-ready, hoisted out of the `warmBackground` futures list),
  **kept opportunistic** (the send/relay race never blocks on it). The new seam **re-asserts**
  `_allowsAccountNetworkSideEffects(...)` so the move-feature gate is preserved (today it is gated
  transitively via `warmBackground` `:645`).
- Surface an **observable early-start anchor** for the relay-reservation warm (Go side `node.go` — a
  new `node:startup_timing` phase carrying `sinceProcessStartMs`) so S1-style instrumentation can prove
  the already-early dispatch. **This is observability, not a re-ordering of the Go dispatch** (S1: the
  warm + auto-register already fire at the earliest point in `Node.Start`).
- Wire the early-discovery trigger into `startup_router.dart` `_doStartP2P` (`:626`) and/or
  `p2p_service_impl.dart` start path (`startNode` `:467-486`) **without** changing the send-path
  decision, any timeout, or the `node:start` *ordering* (the latter is gated behind 164's
  `ensureRuntimeServicesReady` — out of scope, see below).
- Lock that **no timeout value changed** (preserved-sentinel Go config test TC-07-04 — now encodes the
  executed S1 `no-retime` verdict).

**Out of scope (owning plan):**
- Per-peer eager `warmPeer` / `isLocalPeer`-gated reuse → **FDC-04** (P0-1).
- Concurrent durable-inbox generalization → **FDC-02/FDC-03** (P0-2/§4.1).
- 2s-serial starvation / `direct_timeout` mis-route fix → **FDC-01/FDC-03** (P0-3 / §4.1).
- Parallel resume re-prime + pause flush → **FDC-05/FDC-06** (P1-2).
- libp2p LAN-direct dial unify (bonsoir-fed) → **FDC-11** (P2-1, device-only, QUIC-hang precondition).
- **`node:start` ordering / the Dart pre-`node:start` prologue** (the real absolute cold win on
  Android, ~1.13 s) → **plan-164** owns `deferredRuntimeStartup` + the idempotent
  `_ensureRuntimeServicesReady` future (`startup_router.dart:627-630` → `main.dart:3636-3654`).
  Decoupling `node:start` to await only `bridge.initialize()` is 164-owned restructuring; FDC-07
  coordinates with it, does not reorder it.
- **`NEARBY_WIFI_DEVICES` Android manifest permission + runtime grant** (the structural reason
  `NsdManager` resolve is flaky/permission-gated, S1 §3.3) → **separate plan**. Even a perfect bonsoir
  hoist leaves `T_mdns` ≈ 3.5 s and resolve flaky on as-shipped Android; the reorder changes *when*
  discovery starts, not *whether* it resolves in budget.
- **The actual budget/timeout values** → **CLOSED by FDC-S1** (`keep 3 s` / `DIALTIMEOUT_RETIME=no`):
  no `config.go` edit lands in FDC-07.

## Files To Inspect Next

**Production (entry / use-case / service / Go host) — anchors verified on `new-orbit` HEAD 2026-06-27:**
- `lib/core/services/p2p_service_impl.dart` — `startNode` `:467-486` (fires `unawaited(_warmBackgroundSafely())` `:483`), `_warmBackgroundSafely` `:488-498`, `warmBackground` `:643-722`, move-gate `_allowsAccountNetworkSideEffects` check `:645`, `_startHealthCheck()` `:662`, fire-and-forget 2 s `Future.delayed` `:667`, warm futures list `:701-713`, `await Future.wait(futures)` `:715`, `_startLocalDiscovery` `:724-735` (`localP2P.start` `:729`, sets `_setLocalDiscoveryActive` `:730`), `_localDiscoveryActive` flag `:174`, `discoverLocalPeer` `:4431-4442`. **(secondary collision file — see Dependency Impact.)**
- `lib/features/identity/presentation/startup_router.dart` — `_startP2PInBackground` `:615-624`, `_doStartP2P` `:626-722` (cold-start orchestration seam: **awaits `ensureRuntimeServicesReady()` `:627-630` [164 gate]** → `startP2PNode` call `:635` → `StartNodeResult.success` branch `:651` → group-rejoin/drain block `:665-720`).
- `lib/features/p2p/application/start_node_use_case.dart` — `startP2PNode` `:30` (awaits `p2pService.startNode()` `:70`; checks migration gate), `StartNodeResult` enum `:7-22`.
- `go-mknoon/node/node.go` — `Node.Start` `:224-499`, `host_ready` emit `:434-439`, `relayWarmStart := time.Now()` `:444`, relay-warm goroutine `:447-457`, `relay_warm_done` emit `:468-473`, `relayReadyCh`/`ctx` local capture `:462-465`, `autoRegisterPersonalNamespaceForStart` dispatch `:482-483`, `classifyStreamTransport` `:129-142`, `waitForCircuitAddress` poll-loop (200 ms `:1739`), `reserveRelaySlot` `:729` (**reconnect-only**, called `:927-931`). **(collision: Go host — Track D.)**
- `go-mknoon/node/personal_rendezvous_refresh.go` — `autoRegisterPersonalNamespaceForStart` `:13-63`, `waitForCircuitAddressForStart(10 * time.Second)` `:17` (**MAX ceiling**, not a delay).
- `go-mknoon/node/config.go` — `DialTimeout=15s` `:28`, `ForegroundRelay*Timeout=3s` `:39-41`, `InteractiveDialTimeout=4s`/`InteractiveSendTimeout=3s` `:76-77`, `BackgroundTimeouts()` `:116-123` (**preserved-sentinel target**).
- `lib/main.dart` (164 cold-start deferral context — **coordinate, do not edit**) — `startLiveServices` def `:3088`, wired `deferredRuntimeStartup` `:3244`, idempotent `_ensureRuntimeServicesReady` `:3636-3654`.

**Tests (direct + integration):**
- `go-mknoon/node/benchmark_startup_test.go` — `TestBenchmark_NodeStart_EmitsStartupTiming` `:8` reads `node:startup_timing` (`collectEvents` `:28`); the new anchor phase must not break its key reads (extend, don't break).
- `go-mknoon/node/config_test.go` — existing timeout *relationship* tests (`TestInteractiveAndBackgroundTimeoutProfilesRemainDistinct` `:8`, `…NotRequiredForActiveSendPath` `:30`, `…StaysWithinInteractiveSendBudget` `:49`, `…StayShortForForegroundSend` `:62`). **No existing literal-equality lock for the 6 values → TC-07-04 is genuinely NEW** (preserved-sentinel home).
- `go-mknoon/node/node_test.go`, `rendezvous_test.go` — Start/auto-register behavior.
- `test/core/services/p2p_service_impl_test.dart` — warm/discovery ordering; **in `ONE_TO_ONE_TESTS` at `scripts/run_test_gates.sh:52`** + auto-globbed by `core-host-all`.
- `integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e}_test.dart` — cold reconnect + relay-fallback; **`TRANSPORT_TESTS` is `scripts/run_test_gates.sh:173-178` and now has 4 entries** (the 3 above at `:174-176` **plus `media_stable_id_smoke_test.dart` `:177`** — relevant so a transport-gate red isn't mis-attributed).

**Dependency-only context:**
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — `startAdvertising` `~:70` + the `LOCAL_MDNS_ADVERTISE_START` / `LOCAL_MDNS_DISCOVERY_START` flow events (verify by symbol; the discovery the early seam starts) and the S1 `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING` resolve event.
- `lib/main.dart` (164 deferral) — see the Production list above (`startLiveServices :3088`, `deferredRuntimeStartup :3244`, `_ensureRuntimeServicesReady :3636-3654`); node-start is gated behind this on cold launch — **coordinate, do not edit** (Dependency Impact).

## Existing Tests Covering This Area

| Test | Exists? | In which gate array |
|---|---|---|
| `go-mknoon/node/benchmark_startup_test.go::TestBenchmark_NodeStart_EmitsStartupTiming` (`:8`, reads `node:startup_timing` `:28`) | EXISTS | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` |
| `go-mknoon/node/config_test.go` — 4 timeout-*relationship* tests (`:8/:30/:49/:62`), **no literal-equality lock for the 6 values** | EXISTS (no equality lock → TC-07-04 is NEW) | `GOTOOLCHAIN=go1.25.0 go test ./...` |
| `go-mknoon/node/node_test.go` / `rendezvous_test.go` (Start + auto-register) | EXISTS | `GOTOOLCHAIN=go1.25.0 go test ./...` |
| `test/core/services/p2p_service_impl_test.dart` | EXISTS | `run_test_gates.sh 1to1` (explicitly in `ONE_TO_ONE_TESTS` at `scripts/run_test_gates.sh:52` — curated array, NOT auto-globbed) + `run_host_test_gates.sh core-host-all` (auto-globs `test/core/**`) |
| `integration_test/background_reconnect_test.dart` | EXISTS | `run_test_gates.sh transport` (`TRANSPORT_TESTS` `scripts/run_test_gates.sh:174`) |
| `integration_test/wifi_relay_fallback_smoke_test.dart` | EXISTS | `transport` (`:175`) |
| `integration_test/transport_e2e_test.dart` | EXISTS | `transport` (`:176`) |
| `integration_test/media_stable_id_smoke_test.dart` (**4th `TRANSPORT_TESTS` member**) | EXISTS | `transport` (`:177`) — preservation only (media bytes), not edited here |
| early-mDNS-start ordering test (Dart) — TC-07-02 | **MISSING** | add under `test/core/**` (auto-globs `core-host-all`) **AND explicitly append to `ONE_TO_ONE_TESTS`** in `scripts/run_test_gates.sh` for the curated `1to1` gate |
| router-early-discovery test (Dart) — TC-07-03 | **MISSING** | add under `test/features/**` (auto-globs `feature-host-all`) |
| early-reserve-anchor test (Go) — TC-07-01 | **MISSING** | `GOTOOLCHAIN=go1.25.0 go test ./...` (auto). ⚠ confirm it actually REDs (see TC-07-01 note) |
| preserved-timeout-value sentinel (Go) — TC-07-04 | **MISSING** (confirmed no equality lock exists) | `config_test.go`, `GOTOOLCHAIN=go1.25.0 go test ./...` |

## RED Test Catalog  (BEFORE any prod code)

> Host-testable rows (TC-07-01..04) are given full RED detail. Device/relay timing rows (TC-07-05/06)
> are the **closure gate** — their thresholds are now filled from the executed FDC-S1 numbers, but they
> are NOT host-RED-able (dedup can mask a dead live path) and must not be faked green on host/sim.

### TC-07-01 (Go unit) — relay/reserve warm dispatch carries an OBSERVABLE early-start anchor
- **file::name:** `go-mknoon/node/node_start_early_reserve_test.go::TestStart_EmitsReserveDispatchAnchor_AtNodeReady`
- **Tier:** Go unit.
- **Shape/setup:** `New(collector)` + `Start(NodeConfig{RelayAddresses:[<test relay or empty-with-seam>], AutoRegister:true, ProcessStartEpochMs:<anchor>})`; collect `node:startup_timing` events.
- **⚠ AVOID THE TAUTOLOGY (re-grounding 2026-06-27):** `phase:"relay_warm_done"` **already emits** (`node.go:468-473`) **already carrying `sinceProcessStartMs`** (FDC-S1 added the anchor — RESULTS §3.1 shows a measured `relay_warm_done (since proc start)` row), and the warm + auto-register **already dispatch at the earliest point** (`node.go:447-457`/`:482-483`, right after `host_ready` `:434-439`). So "assert a `relay_warm_done` emit + reachable auto-register" is **GREEN on HEAD = vacuous**. The genuinely-new delta is a **dispatch-time** anchor, distinct from the existing completion-time `relay_warm_done`.
- **RED-on-HEAD-because:** today there is **no `phase:"reserve_dispatch"`** emitted at the goroutine-dispatch point (`node.go:444`, the moment warm + auto-register are kicked off). The new assertion — that a `reserve_dispatch` phase fires carrying `sinceProcessStartMs` ≈ node-ready (BEFORE the completion-time `relay_warm_done`) — has no event to read → RED.
- **GREEN-asserts:** a `node:startup_timing{phase:"reserve_dispatch", sinceProcessStartMs:>0}` is emitted, ordered **strictly before** `relay_warm_done`, and `autoRegisterPersonalNamespaceForStart` is dispatched in the same early window.
- **Mutation-that-re-reds:** delete the new `reserve_dispatch` emit (or move the warm-goroutine dispatch behind a synthetic synchronous delay so its `sinceProcessStartMs` jumps past the warm-body) → the dispatch-anchor / ordering assertion fails.
- **Distinct-event discriminator:** assert `phase:"reserve_dispatch"` is present **AND NOT** equal to / merged with the existing `relay_warm_done` (dispatch vs completion), with `reserve_dispatch.sinceProcessStartMs < relay_warm_done.sinceProcessStartMs`.

### TC-07-02 (Dart unit) — bonsoir discovery start is invoked EARLY, ahead of the inbox-drain warm body
- **file::name:** `test/core/services/p2p_service_early_discovery_ordering_test.dart::startNode_startsLocalDiscovery_beforeInboxDrainWarmBody`
- **Tier:** Dart unit (widget-less; fake `LocalP2PService` + fake inbox).
- **Shape/setup:** inject a spy `LocalP2PService` recording the timestamp/order of `start(peerId)` and a spy inbox recording drain order; call `startNode(...)`; assert discovery `start` is observed **before** the inbox-drain phase of the warm pass.
- **RED-on-HEAD-because:** today `_startLocalDiscovery` (`:724`) is added to the warm-body futures list (`:707-713`) and runs *inside* `await Future.wait(futures)` (`:715`) **alongside** `_drainOfflineInbox` (`:701-704`) — after `_startHealthCheck` (`:662`) and the fire-and-forget 2 s `Future.delayed` (`:667`). There is no "discovery-first" ordering → an order assertion fails.
- **GREEN-asserts:** spy order = `[localDiscovery.start, …, inboxDrain]` (discovery strictly first); flow-event `LOCAL_MDNS_DISCOVERY_START` precedes the inbox-drain flow event.
- **Mutation-that-re-reds:** revert the early-start hoist (call discovery inside the original `Future.wait` only) → discovery no longer strictly-first → RED.
- **Distinct-event discriminator:** spy call-order list (discovery vs drain), not just "both happened".
- **⚠ DESIGN CONSTRAINTS (re-grounding 2026-06-27) the GREEN edit MUST satisfy — else it introduces a regression:**
  1. **Exactly-once start (no double-start).** When discovery is hoisted to the new early seam, `warmBackground` must **stop** adding `_startLocalDiscovery` to its futures (`:707-713`) — otherwise the early seam + the warm body both call `localP2P.start(localPeerId)`. `_startLocalDiscovery` has **NO entry-guard**: `_localDiscoveryActive` (`:174`) is set only *after* `localP2P.start()` returns (`:730`), so two concurrent calls both reach `:729` before either flips the flag. The implementation **must add an `if (_localDiscoveryActive) return;` entry guard** (see Blind-Spot Sweep); TC-07-02 requires the guard, it does not assume it.
  2. **Move-feature gate preserved.** The new early seam must call `_allowsAccountNetworkSideEffects('p2p_lan_discovery')` (today gated transitively via `warmBackground` `:645`). Add a RED sub-assert: with the gate denied, the early seam does NOT call `localP2P.start`.

### TC-07-03 (Dart widget) — early discovery is fired by the cold-start orchestrator, not only the warm body
- **file::name:** `test/features/identity/startup_router_early_discovery_test.dart::doStartP2P_triggersEarlyLanDiscovery_onColdStart`
- **Tier:** Dart widget (StartupRouter harness with fake `P2PService`).
- **Shape/setup:** drive `_doStartP2P` success path; fake `P2PService` records whether the early-discovery seam was invoked on the cold-start branch.
- **RED-on-HEAD-because:** `_doStartP2P` (`:626-722`) never calls an early-discovery hook — after awaiting `ensureRuntimeServicesReady()` (`:627-630`, the 164 gate) and `startP2PNode` (`:635`), discovery is entirely delegated to the unawaited `warmBackground` inside `startNode`. A "router triggered early discovery" assertion has no call to observe.
- **GREEN-asserts:** the new early-start seam is invoked exactly once on `StartNodeResult.success` (`:651`), **after** `ensureRuntimeServicesReady` (does NOT reorder node-start — 164-owned) and **before** the group-rejoin/drain block (`:665-720`).
- **Mutation-that-re-reds:** remove the early-discovery call from `_doStartP2P` → RED.
- **Distinct-event discriminator:** `P2P_*` flow-event for early-discovery-start vs the existing `P2P_SERVICE_WARM_BACKGROUND_BEGIN` (confirmed emitted at `p2p_service_impl.dart:658`).
- **⚠ Two seams, one start:** TC-07-02 (hoist inside `startNode`) and TC-07-03 (router trigger) must resolve to a **single** discovery start, not two. Pick ONE owner for the early call and make `_startLocalDiscovery` idempotent (entry guard, TC-07-02 constraint 1) so the non-owner path is a no-op — otherwise the cold path double-starts bonsoir.

### TC-07-04 (Go unit) — S1-VERDICT LOCK: no timeout value moves (`DIALTIMEOUT_RETIME=no`)
- **file::name:** `go-mknoon/node/config_test.go::TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime` (confirmed absent — no existing equality lock; the 4 existing config tests check *relationships*, not literals).
- **Tier:** Go unit.
- **Shape/setup:** assert the literal durations (all six CODE-CONFIRMED present): `DialTimeout == 15*time.Second` (`:28`), `ForegroundRelayDialTimeout == 3*time.Second` (`:39`), `ForegroundRelayReserveTimeout == 3*time.Second` (`:40`), `ForegroundCircuitAddressWaitTimeout == 3*time.Second` (`:41`), `InteractiveDialTimeout == 4*time.Second` (`:76`), `InteractiveSendTimeout == 3*time.Second` (`:77`).
- **RED-on-HEAD-because:** GREEN-on-HEAD by construction — this is a **regression lock encoding the EXECUTED S1 decision** (`FDC-S1-cold-start-timing-RESULTS.md §4`: `FOREGROUND_RELAY_BUDGET_MS=keep 3 s`, `DIALTIMEOUT_RETIME=no`). It is **permanent, not provisional** (S1 ran; there is no future "S1 may move them"). Its job is to RED the moment anyone re-introduces the refuted "cap to 3 s".
- **GREEN-asserts:** all six equalities hold.
- **Mutation-that-re-reds:** change `DialTimeout` to `3*time.Second` (the refuted cap) → RED.
- **Distinct-event discriminator:** N/A (value equality).

### TC-07-05 (Device/relay — CLOSURE GATE) — cold time-to-circuit stays in budget + the early anchor is observable
- **file::name:** sim/device scenario (no host file); driven via `/sims 1to1 --only <N>` (`<scenario id — define with the FDC-S1 measurement vehicle>`).
- **Tier:** device-proof (cold timing).
- **Shape/setup:** real-device cold launch (force-quit → tap), capture `T_circuit` (process-start → first circuit address) per FDC-S1 Method (b); record against the S1 baselines.
- **RED-on-HEAD-because:** **NOT host-RED-able** — host fakes return synthetic circuit timing (FDC-00 closure list: host gate proves delivery, not the fast path). This row is the closure gate.
- **GREEN-asserts (REFRAMED post-S1 — observability + no-regression, NOT "improve by N ms"):** S1 already proved the Go reserve fires early and `T_circuit` p90 **already fits the 3 s budget** (`1564 ms` Pixel 6 / `913 ms` iPhone 13) — there is **no latency headroom to "improve"**. So assert: **(a)** the new `node:startup_timing{phase:"reserve_dispatch"}` anchor fires with `sinceProcessStartMs` ≈ node-ready (dispatch is observably early — TC-07-01 on device); **(b)** post-change `T_circuit` p90 **stays ≤ 3 s** and within ~10% of the recorded baselines (`≤ ~1564 ms` Android / `≤ ~913 ms` iOS — **no regression**); **(c)** no rise in inbox-fallback rate (proposal §10 bullet 1 guardrail).
- **Mutation-that-re-reds:** N/A on host — device measurement.
- **Discriminator:** `node:startup_timing phase:"reserve_dispatch"` `sinceProcessStartMs` (new anchor) vs `relay_warm_done`.

### TC-07-06 (Device — CLOSURE GATE) — same-WiFi mDNS discovery STARTS early + LAN is opportunistic (never blocks the send)
- **file::name:** device scenario (two real devices, one WiFi); `/sims 1to1 --only <N>` `<scenario id>`.
- **Tier:** device-proof.
- **RED-on-HEAD-because:** sim mDNS is host-shared/unreliable → `kDisableLocalDiscovery` (`e2e_test_mode.dart`); cannot be host/sim-proven (proposal §6.5; FDC-S1 §Risks).
- **GREEN-asserts (REFRAMED post-S1 — CANNOT assert `T_mdns ≤ 1500 ms`):** S1 measured `T_mdns` ≈ **3539 ms median ≫ the 1500 ms `interactiveLocalBudget`** (`send_chat_message_use_case.dart:21`) and **flaky** (17 %→62 % resolve; Android `NsdManager` permission-gated, app lacks `NEARBY_WIFI_DEVICES`). So per **S1 Criterion 5**, assert: **(a)** mDNS discovery **STARTS early** — `LOCAL_MDNS_DISCOVERY_START` / `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING` fires at node-ready, ahead of the inbox-drain warm body; **(b)** **LAN is opportunistic** — the first send is delivered within the relay/foreground budget **regardless of whether mDNS resolves in time** (the send/race NEVER blocks on mDNS). Do **NOT** raise the LAN budget to 3.5 s here (that stalls every send on an unreliable resolve) — the budget-raise and the `NEARBY_WIFI_DEVICES` permission fix are **separate plans**.
- **Discriminator:** `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING` (S1 event) fires early **AND** the delivered-transport label is `relay`/`direct` within budget on a non-resolving trial (proves non-blocking).

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Reserve dispatch carries observable early anchor | dispatch-time emit, distinct from completion | Go unit | `node/node_start_early_reserve_test.go::TestStart_EmitsReserveDispatchAnchor_AtNodeReady` | **no `phase:"reserve_dispatch"` exists** (`relay_warm_done` already emits + carries `sinceProcessStartMs` ⇒ asserting *that* is vacuous) | delete `reserve_dispatch` emit | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./... && GOTOOLCHAIN=go1.25.0 go test -race ./node/` | auto (Go `_test.go`) |
| mDNS discovery starts before inbox-drain warm body | spy call-order + idempotent + move-gated | Dart unit | `test/core/services/p2p_service_early_discovery_ordering_test.dart::startNode_startsLocalDiscovery_beforeInboxDrainWarmBody` | discovery sits inside warm-body `Future.wait` (`:715`) w/ drain, not first | un-hoist discovery into the original `Future.wait` | `run_test_gates.sh 1to1` ; `run_host_test_gates.sh core-host-all` | auto-globs `test/core/**` **+ append to `ONE_TO_ONE_TESTS`** (`run_test_gates.sh`) |
| Cold-start orchestrator triggers early discovery | router calls seam once, after 164 gate | Dart widget | `test/features/identity/startup_router_early_discovery_test.dart::doStartP2P_triggersEarlyLanDiscovery_onColdStart` | `_doStartP2P` never calls early-discovery | remove call from `_doStartP2P` | `run_test_gates.sh 1to1` ; `run_host_test_gates.sh feature-host-all` | auto-globs `test/features/**` |
| No timeout value moves (S1 verdict lock) | config equality (6 literals) | Go unit | `node/config_test.go::TestConfig_TimeoutsMatchExecutedS1Verdict_NoRetime` | regression lock encoding executed `DIALTIMEOUT_RETIME=no` (catches refuted cap) | set `DialTimeout=3*time.Second` | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` | auto |
| Cold T_circuit stays in budget + anchor observable | device timing, no-regression | device-proof | sim scenario `<id — define w/ FDC-S1 vehicle>` | not host-RED-able (synthetic timing) | N/A (device) | `/sims 1to1 --only <N>` ; `run_test_gates.sh transport` | `check_reliability_simulation_discovery.sh` `classify_path()` case `<TODO>` + dart-define case |
| Same-WiFi mDNS starts early + LAN opportunistic (never blocks send) | device timing, non-blocking | device-proof | sim scenario `<id>` | sim mDNS unreliable (`kDisableLocalDiscovery`); `T_mdns`≈3.5s ≫ budget (S1) | N/A (device) | `/sims 1to1 --only <N>` ; `run_test_gates.sh transport` | `check_reliability_simulation_discovery.sh` `classify_path()` + dart-define `<TODO>` |

## Blind-Spot Sweep

- **Lifecycle/derived-state durability — ⚠ the idempotency guard does NOT exist yet (re-grounding 2026-06-27):**
  the early-discovery hoist will run on both the cold-start seam and (if not removed) the warm-body
  path, and on warm-open/resume the node is already started. `_startLocalDiscovery` (`:724`) has **NO
  entry guard** — `_localDiscoveryActive` (`:174`) is set only *after* `localP2P.start()` returns
  (`:730`), so two concurrent calls both reach `localP2P.start(localPeerId)` (`:729`). **Required
  fix:** add `if (_localDiscoveryActive) return;` at entry **AND** stop `warmBackground` from also
  seeding `_startLocalDiscovery` into its futures once hoisted (`:707-713`). Row: **TC-07-02 constraint
  1** — a RED assertion that `localP2P.start` is called **exactly once** across cold-start + a
  redundant second trigger. **(host-testable; this is an ADD, not an assert-existing.)**
- **Sibling-surface consistency — move-feature network gate (NEW):** today bonsoir start is gated
  *transitively* because it runs inside `warmBackground`, which checks
  `_allowsAccountNetworkSideEffects(...)` (`p2p_service_impl.dart:645`) before seeding its futures.
  Hoisting `_startLocalDiscovery` to a new earlier seam **bypasses that gate** unless the seam
  re-asserts it — the exact hazard FDC-11 was fixed for (roadmap §Move-feature: a continuous/early
  wire op that node-start gating does not cover). Row: **TC-07-02 constraint 2** — gate-denied ⇒ no
  `localP2P.start`. **(host-testable; do NOT leave as an untested assumption.)**
- **Sibling-surface consistency — resume path:** resume (`handle_app_resumed.dart`, verify the
  re-prime block by symbol) and notif-tap cold-start both reach node-start; the reorder must apply on
  the cold-start branch without regressing resume re-prime (owned by FDC-05). Row: **N/A for the
  reorder** beyond not breaking `background_reconnect_test.dart`.
- **Destructive-action side-effects:** Stop/Start cycle — `node.go` captures `relayReadyCh`/`ctx`
  locally (`:462-465`) to avoid a Start cycle referencing the next cycle's channel; the new
  early-anchor emit must preserve that capture. Row: covered by existing `node_test.go` Start/Stop +
  TC-07-01 not breaking the capture.
- **Invariant re-verification under new transitions:** "Go only labels transport, Dart owns the path
  decision" — verify the reorder adds **no** path decision in Go (`classifyStreamTransport :129-142`
  only). Row: TC-07-04 + a code-review assertion (no new send-routing in `node.go`). **N/A for a new
  automated test** beyond the transport gate staying green.
- **Sequencing collision with plan-164 (NEW — see Dependency Impact):** `node:start` is now gated
  behind 164's `_doStartP2P` → `await ensureRuntimeServicesReady()` (`startup_router.dart:627-630`).
  FDC-07's early-discovery seam fires **after** that gate, on `StartNodeResult.success`; it must NOT
  attempt to move `node:start` ahead of `ensureRuntimeServicesReady` (that idempotent-future
  restructuring is 164-owned). Row: TC-07-03 asserts the seam runs after node-success, not before the
  164 gate. **(host-testable.)**
- **Badge anti-flap (FDC-14 prerequisite):** earlier mDNS/anchor changes WHEN `relayReady`/
  `usabilityReady` flip (`node_state.dart` — verify by symbol), which drives the self online-dot
  (`ConnectionStatusIndicator`). The dot must climb `connecting→online→onlineDotted` MONOTONICALLY
  without flapping back. **Row: assert NO `online→connecting` regression in the cold-start
  `stateStream` sequence** (preservation lock; FDC-14 owns the new `onlineDirect` tier).

## Invariants (locked by tests)

- **INV-1:** No `config.go` timeout value changes — **PERMANENT** (executed S1 verdict
  `DIALTIMEOUT_RETIME=no`); locked by TC-07-04. There is no future "S1 may move them" — S1 ran.
- **INV-2:** bonsoir mDNS discovery `start` happens **before** the inbox-drain warm body on cold start
  (TC-07-02), and is triggered by the cold-start orchestrator (TC-07-03).
- **INV-3:** The relay-warm/auto-register dispatch (already early) carries a NEW **dispatch-time**
  `node:startup_timing{phase:"reserve_dispatch", sinceProcessStartMs}` anchor, strictly before the
  existing completion-time `relay_warm_done` (TC-07-01). *(The `sinceProcessStartMs` field on
  `relay_warm_done` already exists from FDC-S1; the new invariant is the distinct dispatch anchor.)*
- **INV-4:** The send-path decision stays in Dart `sendChatMessage`; Go only labels transport
  (`classifyStreamTransport`) — no test introduces send routing in `node.go`.
- **INV-5:** Discovery starts **exactly once** on cold start (idempotency entry guard), and the new
  early seam **re-asserts the account-move network gate** (TC-07-02 constraints 1 & 2).
- **INV-6:** FDC-07 does **not** reorder `node:start` relative to 164's `ensureRuntimeServicesReady`
  gate (TC-07-03 asserts the seam fires after node-success).
- **INV-7 (device):** the early dispatch is observable AND cold `T_circuit` **stays within the 3 s
  budget** (no regression vs S1 baselines `1564 ms`/`913 ms`) without raising inbox-fallback rate
  (TC-07-05). *(NOT "measurably lowers" — S1 already showed `T_circuit` fits budget; there is no
  latency headroom to claim.)*

## Step-By-Step Implementation Plan  (RED first)

> **S1 RESOLVED:** steps 1–4 are implementation-ready now; **step 5 is CLOSED as a no-op** (S1 verdict
> = keep-3 s / no-retime — no `config.go` edit lands); step 6 (device closure) is the only pending
> gate. **Serialize FDC-07's `p2p_service_impl.dart` edits behind FDC-04** (roadmap Track D).

0. **Dirty-tree snapshot.** `git status --short` first — `new-orbit` is a SHARED tree with concurrent
   active dev and many `M` files (incl. `go-mknoon/testdata/interop_vectors.json`, which a Go test
   rewrites every run). Scope every diff to FDC-07's own files; never `git checkout` a sibling's file.
1. **RED TC-07-04** (S1-verdict lock) — add the 6-literal timeout-equality test in `config_test.go`.
   Seam: `go-mknoon/node/config.go` consts (read-only). GREEN immediately (it guards the refuted cap;
   it encodes the executed `DIALTIMEOUT_RETIME=no`).
2. **RED TC-07-02** — spy-ordering test in `test/core/services/`. Seam: hoist `_startLocalDiscovery`
   to an **early** seam in the cold-start path (`p2p_service_impl.dart` start path near
   `startNode :467-486`, ahead of the `warmBackground` futures-list discovery at `:707-713`).
   **In the same edit:** (a) add an `if (_localDiscoveryActive) return;` entry guard to
   `_startLocalDiscovery` (`:724`); (b) **remove** `_startLocalDiscovery` from `warmBackground`'s
   futures list so discovery starts exactly once; (c) have the new seam call
   `_allowsAccountNetworkSideEffects('p2p_lan_discovery')`. Make GREEN (incl. constraints 1 & 2).
3. **RED TC-07-03** — StartupRouter early-discovery seam. Seam: `_doStartP2P`
   (`startup_router.dart:626`) invokes the new early-discovery hook on `StartNodeResult.success`
   (`:651`), **after** `ensureRuntimeServicesReady` (`:627-630`, 164 gate — do NOT reorder it) and
   before the rejoin/drain block (`:665-720`). Make GREEN.
4. **RED TC-07-01** — Go dispatch-time anchor. Seam: emit a NEW
   `node:startup_timing{phase:"reserve_dispatch", sinceProcessStartMs}` at the warm-goroutine dispatch
   point (`node.go:444`, right after `host_ready` `:434-439`, before the existing completion-time
   `relay_warm_done` `:468-473`). **Factor the emit + any ordering helper into a small
   `node/<concern>.go` helper** (e.g. `startEarlyMdnsReserve` / `emitReserveDispatchAnchor`) — do NOT
   inline new logic into the ~275-line `Start()` (Scope Guard). Make GREEN; run `go test -race ./node/`.
5. **CLOSED (no-op) — S1 verdict = no retime.** `FOREGROUND_RELAY_BUDGET_MS=keep 3 s` +
   `DIALTIMEOUT_RETIME=no` (RESULTS §4.1/4.2). **No `config.go` value moves in FDC-07.** TC-07-04 holds
   the line. *(Recorded as closed, not skipped: the formerly-gated config edit was evaluated against S1
   evidence and deliberately not made.)*
6. **GATED (device closure — pending)** — register the device scenarios (TC-07-05/06) in
   `check_reliability_simulation_discovery.sh` (`classify_path()` case + dart-define case) and run
   `/sims 1to1 --only <N>`; record `T_circuit` p90 (stays ≤ 3 s, no regression vs `1564`/`913 ms`) +
   the `reserve_dispatch` anchor + the LAN-opportunistic non-blocking proof. Deferred-not-waived if no
   2-device + real-relay rig is available.

## Risks And Edge Cases

- **Reorder double-starts bonsoir** (cold seam + warm body, or seam + warm-open/resume) — ⚠ **the
  idempotency guard does NOT exist on HEAD** (`_localDiscoveryActive` set only after `localP2P.start`
  returns, `:730`; no entry check). FDC-07 must ADD it + remove the warm-body discovery seeding. Pinned
  by TC-07-02 constraint 1.
- **Move-feature gate bypass** — hoisting discovery out of the gated `warmBackground` body
  (`:645`) can leak a wire op during account-move unless the new seam re-asserts
  `_allowsAccountNetworkSideEffects` (the FDC-11/08/09 hazard pattern). Pinned by TC-07-02 constraint 2.
- **Plan-164 overlap** — `node:start` is gated behind `ensureRuntimeServicesReady` (164). FDC-07 must
  not reorder node-start; doing so collides with 164's idempotent `_ensureRuntimeServicesReady` future
  (`main.dart:3636-3654`). Pinned by TC-07-03 (seam fires after node-success) + Dependency Impact.
- **TC-07-01 vacuous-green** — `relay_warm_done` + `sinceProcessStartMs` already emit on HEAD (S1); a
  test asserting *that* passes without any edit. Confirm the genuinely-new `reserve_dispatch`
  dispatch-time anchor REDs before claiming RED-first (TC-07-01 note).
- **Go bridge serialization** (proposal §10 bullet 3; **FDC-S5 — RESOLVED**): the bridge is largely
  concurrent in the warm/steady state; the **only** serialization point is `Node.Start`'s write-lock on
  the cold path (FDC-S5 verdict). Early discovery/anchor must stay off the user's first-send critical
  path. Pinned by the FDC-S5 prioritization contract (advisory) + transport gate staying green.
- **Refuted cap regression** (someone caps `DialTimeout` blind) → TC-07-04 re-reds.
- **Cold notif-tap node not started yet** (proposal §6.1 Honest scope; S1 §3.4) — on a notif-driven
  open the node is typically **background-launched (~206 ms iOS) BEFORE the user taps**, so the
  warm-floor is usually already met; FDC-07's win is *early* discovery/anchor once node-ready, not
  pre-node warm. Documented, measured by S1.
- **iOS/Android sim mDNS shared-host + Android `NEARBY_WIFI_DEVICES`** → TC-07-06 device-only, never
  reported from sim; and even on device, as-shipped Android resolve is flaky (S1: 17 %→62 %, missing
  manifest permission) — a **separate plan** owns the permission fix.

## Device/Relay Proof Profile

- **Host-only for closure:** TC-07-01..04 (Go unit + Dart unit/widget) — the **hoist + anchor** and
  **S1-verdict-lock** slice closes on host gates.
- **Requires device (closure gate):** TC-07-05 (cold `T_circuit` **stays in budget + `reserve_dispatch`
  anchor observable**), TC-07-06 (same-WiFi mDNS **starts early + LAN opportunistic / non-blocking**) —
  real-wire cold timing, not host-reproducible (FDC-00 closure list: FDC-04/06/**07**/11/12 need
  real-wire device proof; host-test false-positive caveat — dedup can mask a dead live path).
- **Closure scenario:** `/sims 1to1 --only <N>` `<scenario id — define with FDC-S1's measurement
  vehicle (`fdc-s1-measurement/`)>`; ≥10 cold trials, ≥2 real iOS + ≥2 real Android, median+p90
  (FDC-S1 §Run). Baselines to beat-or-hold: `T_circuit` p90 `1564 ms` (Pixel 6) / `913 ms` (iPhone 13).

## Acceptance Gates  (LITERAL copy/paste)

```bash
# Go host (hoist anchor + S1-verdict-lock) — MUST pin the toolchain (Go 1.26.x PANICS in node/bridge:
#   "crypto/tls bug: where's my session ticket?", quic-go v0.49.0 — MEMORY feedback_go126_quicgo_*)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...   # expected: all pkgs PASS / 0 fail
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -race ./node/   # early-dispatch is a goroutine → -race (roadmap Go-hygiene)
cd go-mknoon && make lint                                    # gofmt -l + go vet, expected: clean
# A Go test rewrites testdata/interop_vectors.json each run — revert so git diff --check stays clean:
git checkout -- go-mknoon/testdata/interop_vectors.json

# 1:1 host gate (Dart ordering test auto-globs test/core/** AND is appended to ONE_TO_ONE_TESTS)
./scripts/run_test_gates.sh 1to1            # expected: 1226 pass / 0 fail

# host floors
./scripts/run_host_test_gates.sh core-host-all       # expected: 0 fail
./scripts/run_host_test_gates.sh feature-host-all    # expected: 0 fail (TC-07-03 lives here)

# group-safety floor (FDC-07 is a SHARED-HOST plan — roadmap 1:1 group-safety mandate)
./scripts/run_test_gates.sh groups          # expected: ~896 pass / 0 fail (group send/pubsub unchanged)
# Go pubsub/group floor is covered by the GOTOOLCHAIN=go1.25.0 go test ./... above (node/ pubsub tests)

# transport gate (4 TRANSPORT_TESTS incl. media_stable_id_smoke — must stay green)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim) pass / 0 fail

# DEVICE CLOSURE GATE (step 6 — pending; scenario id defined with the FDC-S1 vehicle)
./scripts/check_reliability_simulation_discovery.sh   # new scenario MUST list (else classify_path wiring is wrong)
# /sims 1to1 --only <N>   # expected: T_circuit p90 ≤ 3s & ≤~baselines (1564/913ms); reserve_dispatch anchor fires; send within budget on a non-resolving mDNS trial

# hygiene
flutter analyze                              # expected: 0 new
git diff --check                             # expected: clean (after the interop_vectors revert above)
```

## Known-Failure Interpretation

- **Go suite FAILs with 0 `--- FAIL:` lines** = the Go 1.26.x `crypto/tls` "where's my session ticket?"
  panic (quic-go v0.49.0), NOT an FDC-07 bug. Run under `GOTOOLCHAIN=go1.25.0` (the declared toolchain;
  affects node+bridge pkgs which FDC-07 touches). MEMORY: `feedback_go126_quicgo_session_ticket_panic`.
- **`go-mknoon/testdata/interop_vectors.json` shows as `M` after a Go run** = a test rewrites it each
  run (already `M` in the base tree). Revert it; it is not an FDC-07 edit and not a real failure.
- **`core-host-all` `transport_metrics_privacy_test.dart` / `sinceProcessStartMs` privacy-allowlist
  red** = **PRE-EXISTING** (FDC-S0/S1 cold-start instrumentation), proven by stash-revert in sibling
  FDC plans (MEMORY: FDC-01/05/13). Not FDC-07; do not waive a NEW one though.
- Pre-existing transport-gate flakiness (durable-media-upload, per MEMORY) is **not** FDC-07; re-run in
  isolation. A transport-gate red that only appears with the hoist = real regression (likely bridge
  head-of-line or the double-start race) → investigate, do not waive.
- **TC-07-01 GREEN on HEAD before any edit** = vacuous coverage (it asserted the already-emitting
  `relay_warm_done` instead of the new `reserve_dispatch`). Fix the test, not the code.
- TC-07-05/06 cannot go green on host — a "green" there is a false positive (dedup can mask a dead live
  path); they close on device only.

## Done Criteria

- [ ] TC-07-01..04 RED-first then GREEN, each with its mutation re-verified. **TC-07-01 confirmed
      genuinely RED on HEAD** (`reserve_dispatch` absent), not vacuously green on the existing
      `relay_warm_done`.
- [ ] Discovery starts **exactly once** (entry guard added; warm-body seeding removed) AND the new seam
      re-asserts the account-move gate (TC-07-02 constraints 1 & 2 green).
- [ ] `node:start` ordering vs 164's `ensureRuntimeServicesReady` is **unchanged** (TC-07-03 green; no
      edit to `_ensureRuntimeServicesReady`).
- [ ] **No `config.go` value changed — PERMANENT** (TC-07-04 green; `git diff` shows no const edit).
      Step 5 closed as no-op per executed S1 verdict.
- [ ] `GOTOOLCHAIN=go1.25.0 go test ./...`, `go test -race ./node/`, `make lint`, `1to1`,
      `core-host-all`, `feature-host-all`, `groups`, `transport` gates green; `flutter analyze` 0-new;
      `git diff --check` clean (after the `interop_vectors.json` revert).
- [ ] FDC-S1 numbers (`keep 3 s`, `DIALTIMEOUT_RETIME=no`, `T_circuit` 1564/913 ms, `T_mdns` ≈3.5 s)
      cited as **facts** (RESULTS §4), not invented.
- [ ] Every NEW exported Go identifier carries a doc comment beginning with the identifier name (Go
      convention; the package already does this).
- [ ] Device closure (TC-07-05/06) run and median+p90 recorded, OR explicitly deferred-not-waived with
      rationale.

## Scope Guard (hard Do-not)

- **Do NOT** reorder, gate, or disturb the group-rejoin/drain block (`startup_router.dart:665-720`) —
  the early mDNS start must run BEFORE it without changing group reconnect behavior. **Group-safety
  floor (shared-host plan):** `./scripts/run_test_gates.sh groups` + Go pubsub/group tests
  (`GOTOOLCHAIN=go1.25.0 go test ./...`) stay green.
- **Do NOT** reorder `node:start` relative to **plan-164's** `ensureRuntimeServicesReady`
  (`startup_router.dart:627-630` → `main.dart:3636-3654`) — the idempotent `_ensureRuntimeServicesReady`
  future is 164-owned; decoupling node-start from the full `startLiveServices` is a 164 task, not FDC-07.
- **Do NOT** cap `config.go:28 DialTimeout` (or any timeout) — **REFUTED by the executed S1 verdict**
  (`DIALTIMEOUT_RETIME=no`); no `config.go` value moves in FDC-07 (TC-07-04).
- **Do NOT** hoist `_startLocalDiscovery` out of the gated `warmBackground` body WITHOUT re-asserting
  `_allowsAccountNetworkSideEffects` at the new seam (move-feature gate) AND adding the idempotency
  entry guard + removing the warm-body discovery seeding (no double-start).
- **Do NOT** add per-peer `warmPeer`/`dialPeer` here (that's FDC-04).
- **Do NOT** add the `NEARBY_WIFI_DEVICES` Android permission or raise the LAN/`interactiveLocalBudget`
  here — both are **separate plans** (S1 Criterion 5); FDC-07 only starts discovery early + keeps it
  opportunistic.
- **Do NOT** move any send-path decision into Go (`node.go` only labels transport).
- **Do NOT** delete `warmBackground`'s inbox-drain / health-check / proactive-send-proof body — only
  hoist the discovery start earlier (+ the Go observability anchor).
- **Do NOT** fake TC-07-05/06 green on host/sim.
- **Do NOT** inline the early-anchor emit into the already-oversized `node.go` `Start()` (~275 lines,
  `:224-499`) — new feature logic belongs in its own `node/<concern>.go`; factor FDC-07's
  `reserve_dispatch` emit into a small helper (e.g. `emitReserveDispatchAnchor` / `startEarlyMdnsReserve`),
  with only minimal registration touching `Start`.

## Accepted Differences

- **The config/timeout slice is CLOSED as a no-op** (executed S1 verdict = keep-3 s / no-retime). FDC-07
  ships the hoist + observability anchor only; this is the whole point now that S1 ran.
- **The Go-side change buys observability, NOT latency.** S1 proved the relay warm/reserve already fire
  at the earliest point in `Node.Start` and are sub-second; the absolute cold win lives in the Dart
  pre-`node:start` prologue, which is **plan-164's** domain — accepted, by design.
- **`T_mdns` stays ≈ 3.5 s and Android resolve stays permission-flaky** even after a perfect hoist
  (Android `NsdManager` + missing `NEARBY_WIFI_DEVICES`, S1 §3.3). FDC-07 makes LAN start *early* and
  *opportunistic*; the resolve-latency/permission fix is a **separate plan** — accepted.
- On the coldest notif-tap path, FDC-07 does **not** promise pre-node warm overlap (proposal §6.1
  Honest scope); S1 §3.4 shows the node is usually background-launched (~206 ms iOS) before the tap, so
  the warm-floor is typically already met — accepted.

## Dependency Impact

- **gatedBy:** `FDC-S1` — **RESOLVED** (`FDC-S1-cold-start-timing-RESULTS.md §4`). This plan now
  *consumes* its numbers (`keep 3 s`, `DIALTIMEOUT_RETIME=no`, `T_circuit` 1564/913 ms, `T_mdns`≈3.5 s)
  rather than waiting on them.
- **⚠ Reconcile with plan-164 (NEW — the real overlap).** 164 (`deferredRuntimeStartup`) already gates
  `node:start` behind the idempotent `_ensureRuntimeServicesReady` future (`startup_router.dart:627-630`
  → `main.dart:3636-3654`). FDC-07 must NOT touch `node:start` ordering; its early-discovery seam fires
  *after* node-success. Decoupling node-start to await only `bridge.initialize()` (real residual Dart
  headroom, `main.dart:3097-3135`) is **164-owned** and would collide with 164's idempotent contract —
  out of FDC-07 scope.
- **Collision (sequential):**
  - `lib/core/services/p2p_service_impl.dart` (4250+ lines) — also edited by **FDC-04** (`warmPeer`,
    `isLocalPeer` gating), **FDC-08** (presence cache), and others (roadmap "Secondary collision"; the
    region is disjoint but one writer at a time). **FDC-05 does NOT edit this file** (it reorders
    `handle_app_resumed.dart` + a fake). Same-file → serialize behind **FDC-04** (roadmap Track D);
    re-green `1to1` between. (MEMORY 160→163 `feed_wired` precedent.)
  - `go-mknoon/node/node.go` / `config.go` — Go host (Track D: **FDC-07 → FDC-11 → {FDC-12, FDC-15}**;
    also FDC-10). Serialize Go edits; FDC-07 before FDC-11.
- **Phase / Wave:** Phase 1 / Wave W2 (roadmap) — after Phase-0 Dart-only FDC-01..04; S1 gate resolved.
- **No DB migration. Additive-only on Go** (`NodeConfig.ProcessStartEpochMs` anchor **already landed via
  FDC-S1**; FDC-07 adds only the `reserve_dispatch` emit), **NET-REL-07 safe** (no relay/protocol
  change). Go-hygiene: `make lint` + **`go test -race ./node/`** (early dispatch is a goroutine).

## Re-Grounding Log

**2026-06-27 — post-S1 review (6-agent verify→refute workflow + main-loop synthesis).** Triggered by
`/tdd-plan` "review + update". Read-only grounding agents re-pinned every anchor against `new-orbit`
HEAD; the main loop applied all edits (review agents never mutated the tree — MEMORY hazard). Changes:

1. **FDC-S1 is EXECUTED** (`FDC-S1-cold-start-timing-RESULTS.md`, Jun 26) → removed the "⚠ DRAFT /
   gated / `<from FDC-S1>`" framing; filled every placeholder with measured numbers; flipped Status.
2. **Step 5 (config edit) CLOSED as a no-op** — S1 `DIALTIMEOUT_RETIME=no` / `keep 3 s`. TC-07-04
   reframed from a placeholder sentinel to the **permanent S1-verdict regression lock**.
3. **RC3 "leisurely background cadence" REFUTED** — the relay warm/auto-register already dispatch at
   the earliest point in `Node.Start` (`node.go:447-457`/`:482-483`, post-`host_ready` `:434-439`) and
   are sub-second (S1). Restated RC3 as *"missing observable anchor + Dart prologue"*; corrected a
   warm-vs-reservation conflation (cold reservation is libp2p-autorelay-implicit; explicit
   `reserveRelaySlot :729` is reconnect-only). Go lever = observability, not latency.
4. **TC-07-01 de-vacuumed** — `relay_warm_done` + `sinceProcessStartMs` already emit on HEAD; the
   genuinely-new RED-able delta is a **dispatch-time `phase:"reserve_dispatch"`** anchor.
5. **TC-07-05/06 reframed** — `T_circuit` already fits budget (no "improve" claim → no-regression +
   anchor); `T_mdns`≈3.5 s ≫ 1500 ms + flaky (cannot assert ≤budget → early-start + LAN-opportunistic).
6. **Anchor drift corrected** — `p2p_service_impl.dart` +53…+75, `node.go` +6…+31, `main.dart` 164
   context, `run_test_gates.sh` TRANSPORT_TESTS `:173-178` (4 entries). `startup_router.dart` /
   `start_node_use_case.dart` / `personal_rendezvous_refresh.go` / `config.go` consts confirmed CLEAN.
7. **New blind-spots added** — (a) **plan-164 overlap** (`node:start` gated behind
   `ensureRuntimeServicesReady`; scope it out); (b) **`_startLocalDiscovery` has no entry-guard** → the
   hoist must ADD one + stop warm-body seeding (double-start race); (c) **move-feature gate** must be
   re-asserted at the new seam (FDC-11 hazard pattern); (d) **`NEARBY_WIFI_DEVICES`** is a separate-plan
   prerequisite bounding TC-07-06.
8. **Gate hygiene** — Go gate pinned to `GOTOOLCHAIN=go1.25.0` (+`go test -race`); added the
   `interop_vectors.json` revert + the group-safety floor (`run_test_gates.sh groups`); corrected the
   FDC-05 collision claim (FDC-05 does NOT edit `p2p_service_impl.dart`).
