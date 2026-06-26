# FDC-07 — Cold-start: earlier mDNS advertise/discover + relay reservation  (Feature Improvement)

Status: awaiting-review

Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.4 lifecycle / cold-start, §8 **P1-3**, §3 "cold open → empty discovered-peers map", §10 bullet 1, §11 Q3)

---

## ⚠ DRAFT — finalize after FDC-S1

**This plan is a DRAFT gated by `FDC-S1` (Cold-start timing measurement spike).** It is *not*
implementation-ready. Every timing/budget value below is a placeholder marked **`<from FDC-S1>`** and
**MUST NOT be hard-coded until S1 produces the measured `T_nodeStart` / `T_circuit` / `T_mdns`
median+p90 tables and the `DIALTIMEOUT_RETIME` verdict** (FDC-S1 §"Expected Output", §"Decision
Criteria"). The proposal explicitly forbids re-timing blind: *"Do NOT blindly cap the cold relay dial
at 3s … Measure cold time-to-circuit first"* (§8 P1-3; §11 Q3; §10 bullet 1).

What is **already host-testable today and given full RED detail below** (does not need S1): the
*ordering/sequencing* change — starting bonsoir mDNS advertise/discover and the relay-reservation
warm **earlier** (off the post-`node:start` fire-and-forget `warmBackground` path), and the
observation that this reordering must not change any timeout value. What is **deferred to the S1
closure gate / device proof**: every concrete millisecond budget, and any edit to
`config.go` timeouts (the whole point of S1 is to decide whether they move at all). Device/relay rows
in the matrices are flagged as the **closure gate**, not host-closable.

---

## Source Of Truth

- **Proposal** §6.4, §8 **P1-3**, §3, §10 (bullet 1), §11 (Q3) — `Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md`.
- **`scripts/run_test_gates.sh` wins over prose** — the literal gate commands (`transport`, `1to1`,
  `feature-host-all`) are the acceptance authority; `cd go-mknoon && go test ./...` for Go.
- **This epic's roadmap** — `FDC-00-roadmap.md` (Phase 1; collision map; "Phase 1 … measure cold
  time-to-circuit (S1) before re-timing anything"; closure-list FDC-04/06/07/11/12 = real-wire device proof).
- **Blocking spike** — `FDC-S1-cold-start-timing-measurement-spike.md` (numbers + DialTimeout-retime verdict).

## Session Classification

**evidence-gated** (DRAFT). The *reordering* slice is implementation-ready; the *budget/timeout* slice
is gated by FDC-S1, and the "fast-path actually improves cold time-to-circuit" claim is **device-only**
(host fakes cannot reproduce real cold QUIC/TLS reserve timing — FDC-00 closure list).

## Exact Problem Statement

On a **cold open** the discovered-peers map is empty and no circuit reservation exists yet, because
**both** LAN discovery and the relay-reservation warm are started *only after* `node:start` returns,
inside the **fire-and-forget** `warmBackground()` (`p2p_service_impl.dart:572`, invoked
`unawaited(_warmBackgroundSafely())` at `p2p_service_impl.dart:430`), and bonsoir advertise/discover
begins even deeper, inside `_startLocalDiscovery` (`p2p_service_impl.dart:649`). So a same-WiFi peer
must be (re)discovered *within the 1500ms send budget* (`send_chat_message_use_case.dart:21`) or the
message silently falls through to direct/relay (proposal §3). The relay-reservation warm goroutine in
Go (`node.go:429-439`) and the auto-register that waits up to 10s for a circuit address
(`personal_rendezvous_refresh.go:16-17 waitForCircuitAddressForStart(10 * time.Second)`) are likewise
only kicked off *inside* `Node.Start`, but they are not surfaced/started any **earlier** relative to
the Dart cold-start critical path, and the warm dial inherits the **15s background** `DialTimeout`
(`config.go:28`).

**Who feels it:** the user on "open app → send one message → close" and on cold notif-tap — the first
send in the first ~1.5–2s after cold open finds no circuit and no LAN map → inbox even for a reachable
peer (proposal §4 R5).

**What must improve:**
- bonsoir mDNS advertise/discover **starts earlier** in the cold-start sequence (not buried behind the
  full `warmBackground` body), so the LAN map has a chance to populate before the first send window.
- The relay-reservation warm / circuit-address acquisition is **kicked off as early as node-ready**
  and is *observably* anchored, so FDC-S1's measured `T_circuit` reflects an early start.

**What must stay unchanged (preserved sentinels):**
- **No timeout VALUE changes** in this slice — `config.go:28 DialTimeout=15s`,
  `:39-41 ForegroundRelay*Timeout=3s`, `:76-79 Interactive*` are byte-identical until S1 says
  otherwise. (Preserved-sentinel test: a Go config assertion locking the current durations.)
- The send-path decision still lives in Dart `sendChatMessage`; Go only labels transport
  (`classifyStreamTransport node.go:123-136`) — reordering must not move any path decision into Go.
- `warmBackground` still runs (inbox drain + proactive-send-proof + health check) — we **pull the
  discovery/reserve start earlier**, we do not delete the warm body.
- Existing NET-REL test locks (transport + 1to1 gates) stay green.

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, read & verified) | Why it produces the cold-start gap |
|---|---|---|
| RC1 | `p2p_service_impl.dart:430` fires `unawaited(_warmBackgroundSafely())` **after** `startNodeCore` returns; `warmBackground` (`:572`) first does a `_startHealthCheck()` + a **fixed `Duration(seconds: 2)`** poll (`:596`) before it even calls `_startLocalDiscovery` (`:649`). | bonsoir advertise/discover is gated behind node-start **and** the warm prologue → empty LAN map during the first send window (proposal §3). |
| RC2 | `_startLocalDiscovery` (`:649-659`) is the only bonsoir `localP2P.start()` call on cold start, and it runs **concurrently inside** `Future.wait(futures)` with inbox drain (`:624-640`) — not ahead of it. | LAN discovery competes with inbox drain on the same warm pass instead of starting first. |
| RC3 | Go relay warm is a background goroutine spawned at `node.go:429-439`; auto-register waits up to **10s** for a circuit address (`personal_rendezvous_refresh.go:17`), and the warm dial uses the **background** `DialTimeout=15s` (`config.go:28`, via `BackgroundTimeouts()` `:116-123`). | The reservation is acquired on a leisurely background cadence with no early-start anchor; the first send finds no circuit (proposal §4 R5). **NOTE:** the 15s is *background*, not the user-send budget — DO NOT cap it without S1 evidence (§8 P1-3). |

**Refuted — do NOT re-introduce:**
- ❌ "Cap the cold relay dial to 3s." `config.go:28 DialTimeout=15s` is consumed by the **fire-and-forget**
  warm goroutine (`node.go:429-439 warmRelayConnectionForStart`), **not** the user's send (which uses
  `ForegroundRelay*Timeout=3s` `config.go:39-41` and `Interactive*` `:76-79`). Capping it risks
  abandoning a slow-but-succeeding cold QUIC/TLS handshake → **more** inbox fallback (proposal §8 P1-3,
  §10 bullet 1; FDC-S1 Decision-Criterion 2 default = "DO NOT re-time"). **Only re-time if S1 shows a
  foreground send whose latency tracks 15s** (`DIALTIMEOUT_RETIME` `<from FDC-S1>`).
- ❌ "Warm dials the contact eagerly on cold tap." That is **FDC-04** (`warmPeer`), not FDC-07; and on
  the coldest path the Go node isn't started yet so a dial can't overlap reading time (proposal §6.1
  "Honest scope", §10 bullet 1). FDC-07 is *node-start + early reserve/mDNS*, not per-peer warm.

## Real Scope

**In scope:**
- Reorder the cold-start sequence so **bonsoir advertise/discover starts earlier** (a dedicated
  early-start seam invoked at/just-after node-ready, ahead of the inbox-drain warm body).
- Surface/anchor the **relay-reservation + circuit-address acquisition** as an explicit early step
  (Go side `node.go` / `personal_rendezvous_refresh.go`) so S1's `T_circuit` reflects an early start.
- Wire the early-start trigger into `startup_router.dart` `_doStartP2P` (`:626`) and/or
  `p2p_service_impl.dart` start path (`:413-433`) **without** changing the path decision or any timeout.
- Lock that **no timeout value changed** (preserved-sentinel Go config test).

**Out of scope (owning plan):**
- Per-peer eager `warmPeer` / `isLocalPeer`-gated reuse → **FDC-04** (P0-1).
- Concurrent durable-inbox generalization → **FDC-02/FDC-03** (P0-2/§4.1).
- 2s-serial starvation / `direct_timeout` mis-route fix → **FDC-03** (P0-3 / §4.1).
- Parallel resume re-prime + pause flush → **FDC-05/FDC-06** (P1-2).
- libp2p LAN-direct dial unify (bonsoir-fed) → **FDC-11** (P2-1, device-only, QUIC-hang precondition).
- **The actual budget/timeout values** → decided by **FDC-S1**, applied here only after.

## Files To Inspect Next

**Production (entry / use-case / service / Go host):**
- `lib/core/services/p2p_service_impl.dart` — `startNode` `:413-433` (fires warm), `_warmBackgroundSafely` `:435`, `warmBackground` `:572-647`, fixed-2s poll `:596-622`, `_startLocalDiscovery` `:649-659`, `discoverLocalPeer` `:4131-4143` (anchors). **(secondary collision file — see Dependency Impact.)**
- `lib/features/identity/presentation/startup_router.dart` — `_startP2PInBackground` `:615-624`, `_doStartP2P` `:626-722` (the cold-start orchestration seam; `startP2PNode` call `:635`).
- `lib/features/p2p/application/start_node_use_case.dart` — `startP2PNode` `:30`, `StartNodeResult` `:7`.
- `go-mknoon/node/node.go` — `Node.Start` `:218-468`, relay-warm goroutine `:429-439`, `host_ready` emit `:417-421`, `relay_warm_done` emit `:444-459`, `autoRegisterPersonalNamespaceForStart` dispatch `:463-465`. **(collision: Go host.)**
- `go-mknoon/node/personal_rendezvous_refresh.go` — `autoRegisterPersonalNamespaceForStart` `:13-63`, `waitForCircuitAddressForStart(10s)` `:17`.
- `go-mknoon/node/config.go` — `DialTimeout=15s` `:28`, `ForegroundRelay*Timeout` `:39-41`, `Interactive*` `:76-79`, `BackgroundTimeouts()` `:116-123` (**preserved-sentinel target**).

**Tests (direct + integration):**
- `go-mknoon/node/benchmark_startup_test.go` — existing `node:startup_timing` assertions (extend, don't break).
- `go-mknoon/node/config_test.go` — config value locks (preserved-sentinel home).
- `go-mknoon/node/node_test.go`, `rendezvous_test.go` — Start/auto-register behavior.
- `test/core/services/p2p_service_impl_test.dart` (1to1 gate array) — warm/discovery ordering.
- `integration_test/{background_reconnect,wifi_relay_fallback_smoke,transport_e2e}_test.dart` (transport gate) — cold reconnect + relay-fallback.

**Dependency-only context:**
- `lib/core/local_discovery/bonsoir_discovery_service.dart` — `LOCAL_MDNS_ADVERTISE_START` `:82-84`, `LOCAL_MDNS_DISCOVERY_START` `:95-97` (the discovery the early seam starts; FDC-S1 adds the resolve-complete event).
- `lib/main.dart` — `startLiveServices` `:3066`, `deferredRuntimeStartup` wiring `:3222`/`:3620-3627` (164 cold-start deferral — node-start is later on cold launch).

## Existing Tests Covering This Area

| Test | Exists? | In which gate array |
|---|---|---|
| `go-mknoon/node/benchmark_startup_test.go::TestBenchmark_NodeStart_EmitsStartupTiming` | EXISTS | `cd go-mknoon && go test ./...` |
| `go-mknoon/node/config_test.go` (config value locks) | EXISTS (verify scope) | `go test ./...` |
| `go-mknoon/node/node_test.go` / `rendezvous_test.go` (Start + auto-register) | EXISTS | `go test ./...` |
| `test/core/services/p2p_service_impl_test.dart` | EXISTS | `run_test_gates.sh 1to1` (explicitly in `ONE_TO_ONE_TESTS` — curated array, NOT auto-globbed) + `run_host_test_gates.sh core-host-all` (auto-globs `test/core/**`) |
| `integration_test/background_reconnect_test.dart` | EXISTS | `run_test_gates.sh transport` (`scripts/run_test_gates.sh:165`) |
| `integration_test/wifi_relay_fallback_smoke_test.dart` | EXISTS | `transport` (`:166`) |
| `integration_test/transport_e2e_test.dart` | EXISTS | `transport` (`:167`) |
| early-mDNS-start ordering test (Dart) | **MISSING** | add under `test/core/**` (auto-globs `core-host-all`) **AND explicitly append to `ONE_TO_ONE_TESTS`** in `scripts/run_test_gates.sh` for the curated `1to1` gate |
| early-reserve-start anchor test (Go) | **MISSING** | `go test ./...` (auto) |
| preserved-timeout-value sentinel (Go) | **MISSING / verify** | `config_test.go`, `go test ./...` |

## RED Test Catalog  (BEFORE any prod code)

> Host-testable rows are given full RED detail. Device/relay timing rows are the **closure gate** and
> carry `<from FDC-S1>` placeholders — they are NOT host-RED-able and must not be faked green.

### TC-07-01 (Go unit) — relay/reserve warm is dispatched as an early step of `Node.Start`
- **file::name:** `go-mknoon/node/node_start_early_reserve_test.go::TestStart_DispatchesRelayWarmAndAutoRegister_AsEarlyStep`
- **Tier:** Go unit.
- **Shape/setup:** `New(collector)` + `Start(NodeConfig{RelayAddresses:[<test relay or empty-with-seam>], AutoRegister:true, ProcessStartEpochMs:<anchor>})`; collect `node:startup_timing` events.
- **RED-on-HEAD-because:** today the relay warm goroutine and auto-register are spawned but emit **no** "early dispatch / sinceProcessStartMs" anchor — the new ordering assertion (warm/auto-register dispatched before the warm-body inbox phase, with a process-start anchor) has no event to read. *(Anchor field itself lands in FDC-S1; this test asserts the **ordering/dispatch**, and is RED until the early-dispatch emit exists.)*
- **GREEN-asserts:** a `node:startup_timing` with `phase:"relay_warm_done"` (or a new `phase:"reserve_dispatch"`) is emitted, and `autoRegisterPersonalNamespaceForStart` is reachable before `Start` returns control to a blocking warm-body step.
- **Mutation-that-re-reds:** move the relay-warm goroutine dispatch to after a synchronous delay / behind the warm body → ordering assertion fails.
- **Distinct-event discriminator:** `phase` field value (`relay_warm_done` vs `host_ready`).

### TC-07-02 (Dart unit) — bonsoir discovery start is invoked EARLY, ahead of the inbox-drain warm body
- **file::name:** `test/core/services/p2p_service_early_discovery_ordering_test.dart::startNode_startsLocalDiscovery_beforeInboxDrainWarmBody`
- **Tier:** Dart unit (widget-less; fake `LocalP2PService` + fake inbox).
- **Shape/setup:** inject a spy `LocalP2PService` recording the timestamp/order of `start(peerId)` and a spy inbox recording drain order; call `startNode(...)`; assert discovery `start` is observed **before** the inbox-drain phase of the warm pass.
- **RED-on-HEAD-because:** today `_startLocalDiscovery` (`:649`) runs *inside* `Future.wait(futures)` alongside inbox drain (`:624-640`), after a `_startHealthCheck` + (in real time) the 2s poll scheduling — there is no "discovery-first" ordering, so an order assertion fails.
- **GREEN-asserts:** spy order = `[localDiscovery.start, …, inboxDrain]` (discovery strictly first); flow-event `LOCAL_MDNS_DISCOVERY_START` precedes the inbox-drain flow event.
- **Mutation-that-re-reds:** revert the early-start hoist (call discovery inside the original `Future.wait` only) → discovery no longer strictly-first → RED.
- **Distinct-event discriminator:** spy call-order list (discovery vs drain), not just "both happened".

### TC-07-03 (Dart unit) — early discovery is fired by the cold-start orchestrator, not only the warm body
- **file::name:** `test/features/identity/startup_router_early_discovery_test.dart::doStartP2P_triggersEarlyLanDiscovery_onColdStart`
- **Tier:** Dart unit / widget (StartupRouter harness with fake `P2PService`).
- **Shape/setup:** drive `_doStartP2P` success path (`:651`); fake `P2PService` records whether the early-discovery seam was invoked on the cold-start branch.
- **RED-on-HEAD-because:** `_doStartP2P` (`:626-722`) never calls an early-discovery hook — discovery is entirely delegated to the unawaited `warmBackground`. A "router triggered early discovery" assertion has no call to observe.
- **GREEN-asserts:** the new early-start seam is invoked exactly once on `StartNodeResult.success`, before the group-rejoin/drain block (`:665-720`).
- **Mutation-that-re-reds:** remove the early-discovery call from `_doStartP2P` → RED.
- **Distinct-event discriminator:** `P2P_*` flow-event for early-discovery-start vs the existing `P2P_SERVICE_WARM_BACKGROUND_BEGIN`.

### TC-07-04 (Go unit, preserved sentinel) — no timeout VALUE changed by the reordering
- **file::name:** `go-mknoon/node/config_test.go::TestConfig_TimeoutsUnchanged_ByColdStartReorder` (add if absent)
- **Tier:** Go unit.
- **Shape/setup:** assert the literal durations: `DialTimeout == 15*time.Second`, `ForegroundRelayDialTimeout == 3*time.Second`, `ForegroundRelayReserveTimeout == 3*time.Second`, `ForegroundCircuitAddressWaitTimeout == 3*time.Second`, `InteractiveDialTimeout == 4*time.Second`, `InteractiveSendTimeout == 3*time.Second`.
- **RED-on-HEAD-because:** preservation lock — **RED only if a future edit (or an over-eager S1-blind cap) changes a value**. On HEAD it is GREEN by construction; it exists to *catch the refuted "cap to 3s" change*. (This is a preservation sentinel, justified: the proposal's explicit do-NOT.)
- **GREEN-asserts:** all six equalities hold.
- **Mutation-that-re-reds:** change `DialTimeout` to `3*time.Second` (the refuted cap) → RED.
- **Distinct-event discriminator:** N/A (value equality).

### TC-07-05 (Device/relay — CLOSURE GATE, `<from FDC-S1>`) — cold time-to-circuit improves with early reserve
- **file::name:** sim/device scenario (no host file); driven via `/sims 1to1 --only <N>` (`<TODO scenario id from FDC-S1>`).
- **Tier:** device-proof (cold timing).
- **Shape/setup:** real-device cold launch (force-quit → tap), capture `T_circuit` (process-start → first circuit address) per FDC-S1 Method (b); compare pre/post reorder.
- **RED-on-HEAD-because:** **NOT host-RED-able** — host fakes return synthetic circuit timing (FDC-00 closure list: host gate proves delivery, not the fast path). This row is the closure gate.
- **GREEN-asserts:** post-reorder median/p90 `T_circuit` ≤ pre-reorder by the threshold `<from FDC-S1>`; no rise in inbox-fallback rate (proposal §10 bullet 1 guardrail).
- **Mutation-that-re-reds:** N/A on host — device measurement.
- **Discriminator:** `node:startup_timing phase:"discoverable"` `sinceProcessStartMs` (S1 anchor).

### TC-07-06 (Device — CLOSURE GATE, `<from FDC-S1>`) — same-WiFi mDNS resolve lands within the LAN send budget on cold open
- **file::name:** device scenario (two real devices, one WiFi); `/sims 1to1 --only <N>` `<TODO>`.
- **Tier:** device-proof.
- **RED-on-HEAD-because:** sim mDNS is host-shared/unreliable → `kDisableLocalDiscovery` (`e2e_test_mode.dart:2`); cannot be host/sim-proven (proposal §6.5; FDC-S1 §Risks).
- **GREEN-asserts:** `T_mdns` p90 ≤ `interactiveLocalBudget` (1500ms, `send_chat_message_use_case.dart:21`) on cold open with the early start; else FDC-S1 Criterion 5 routes to a budget raise (separate plan).
- **Discriminator:** `FDC_COLDSTART_FIRST_MDNS_RESOLVE_TIMING` (S1 event).

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Relay/reserve dispatched as early step | ordering + anchored emit | Go unit | `node/node_start_early_reserve_test.go::TestStart_DispatchesRelayWarmAndAutoRegister_AsEarlyStep` | no early-dispatch/anchor emit today | move warm dispatch behind warm body | `cd go-mknoon && go test ./...` | auto (Go `_test.go`) |
| mDNS discovery starts before inbox-drain warm body | spy call-order | Dart unit | `test/core/services/p2p_service_early_discovery_ordering_test.dart::startNode_startsLocalDiscovery_beforeInboxDrainWarmBody` | discovery runs inside `Future.wait` w/ drain, not first | un-hoist discovery | `run_test_gates.sh 1to1` ; `run_host_test_gates.sh core-host-all` | auto-globs `test/core/**` |
| Cold-start orchestrator triggers early discovery | router calls seam once | Dart widget | `test/features/identity/startup_router_early_discovery_test.dart::doStartP2P_triggersEarlyLanDiscovery_onColdStart` | `_doStartP2P` never calls early-discovery | remove call from `_doStartP2P` | `run_test_gates.sh 1to1` ; `run_host_test_gates.sh feature-host-all` | auto-globs `test/features/**` |
| No timeout value changed | config equality | Go unit | `node/config_test.go::TestConfig_TimeoutsUnchanged_ByColdStartReorder` | preservation lock (catches refuted cap) | set `DialTimeout=3s` | `cd go-mknoon && go test ./...` | auto |
| Cold time-to-circuit improves | device timing | device-proof | sim scenario `<TODO id from FDC-S1>` | not host-RED-able (synthetic timing) | N/A (device) | `/sims 1to1 --only <N>` ; `run_test_gates.sh transport` | `check_reliability_simulation_discovery.sh` `classify_path()` case `<TODO>` |
| Same-WiFi mDNS resolve ≤ LAN budget on cold open | device timing | device-proof | sim scenario `<TODO id from FDC-S1>` | sim mDNS unreliable (`kDisableLocalDiscovery`) | N/A (device) | `/sims 1to1 --only <N>` ; `run_test_gates.sh transport` | `check_reliability_simulation_discovery.sh` `<TODO>` |

## Blind-Spot Sweep

- **Lifecycle/derived-state durability:** the early-discovery hoist must not double-start bonsoir on
  the warm-open path (node already started). Row: TC-07-02 + a guard assertion that
  `_startLocalDiscovery` is idempotent / `_setLocalDiscoveryActive` not toggled twice. **(host-testable.)**
- **Sibling-surface consistency:** resume path (`handle_app_resumed.dart:136-191`) and notif-tap
  cold-start both reach node-start; reorder must apply on the cold-start branch without regressing
  resume re-prime (owned by FDC-05). Row: assert resume path unchanged (preserved sentinel) / **N/A
  for the reorder** beyond not breaking `background_reconnect_test.dart`.
- **Destructive-action side-effects:** Stop/Start cycle — node.go captures `relayReadyCh`/`ctx`
  locally (`:443-446`) to avoid a Start cycle referencing the next cycle's channel; early-dispatch
  reorder must preserve that capture. Row: covered by existing `node_test.go` Start/Stop + TC-07-01
  not breaking the capture.
- **Invariant re-verification under new transitions:** "Go only labels transport, Dart owns the path
  decision" — verify the reorder adds **no** path decision in Go. Row: TC-07-04 (no value change) +
  a code-review assertion (no new send-routing in `node.go`). **N/A for a new automated test** beyond
  the transport gate staying green.
- **Badge anti-flap (FDC-14 prerequisite):** earlier mDNS/reserve changes WHEN `relayReady`/
  `usabilityReady` flip (`node_state.dart:136-153`), which drives the self online-dot
  (`ConnectionStatusIndicator`). The dot must climb `connecting→online→onlineDotted` MONOTONICALLY
  without flapping back. **Row: assert NO `online→connecting` regression in the cold-start
  `stateStream` sequence** (preservation lock; FDC-14 owns the new `onlineDirect` tier).

## Invariants (locked by tests)

- **INV-1:** No `config.go` timeout value changes in this slice (TC-07-04). *(S1 may later move them —
  that is a separate gated edit.)*
- **INV-2:** bonsoir mDNS discovery `start` happens **before** the inbox-drain warm body on cold start
  (TC-07-02), and is triggered by the cold-start orchestrator (TC-07-03).
- **INV-3:** Relay-warm + auto-register are dispatched as an early step of `Node.Start`, anchored to a
  process-start epoch (TC-07-01) — the anchor field itself lands via FDC-S1.
- **INV-4:** The send path decision stays in Dart `sendChatMessage`; Go only labels transport (no test
  introduces send routing in `node.go`).
- **INV-5 (device, `<from FDC-S1>`):** early start measurably lowers cold `T_circuit` without raising
  inbox-fallback rate (TC-07-05).

## Step-By-Step Implementation Plan  (RED first)

> **Stop-if:** FDC-S1 is not yet resolved → land ONLY the reordering + preservation-sentinel steps
> (1–4); do **not** touch any `config.go` value. Steps 5–6 are unlocked by S1's
> `FOREGROUND_RELAY_BUDGET_MS` / `DIALTIMEOUT_RETIME` outputs.

1. **RED TC-07-04** (preserved sentinel) — add the timeout-value equality lock in `config_test.go`.
   Seam: `go-mknoon/node/config.go` consts (read-only). GREEN immediately (it guards the refuted cap).
2. **RED TC-07-02** — spy-ordering test in `test/core/services/`. Seam: hoist the
   `_startLocalDiscovery` call to an **early** point in the cold-start path
   (`p2p_service_impl.dart` start path `:413-433`, ahead of the `warmBackground` inbox-drain body),
   keeping `warmBackground` otherwise intact. Make GREEN.
3. **RED TC-07-03** — StartupRouter early-discovery seam. Seam: `_doStartP2P` (`startup_router.dart:626`)
   invokes the new early-discovery hook on `StartNodeResult.success` before the rejoin/drain block.
   Make GREEN.
4. **RED TC-07-01** — Go early-dispatch ordering/anchor emit. Seam: `node.go:429-465` — emit an
   early `reserve_dispatch`/`relay_warm_done` ordering anchor; ensure auto-register dispatch
   (`:463-465`) is reachable as an early step. Make GREEN. *(The `sinceProcessStartMs` field is the
   FDC-S1 instrumentation; here assert only ordering/dispatch.)*
5. **GATED (post-S1)** — apply `FOREGROUND_RELAY_BUDGET_MS` / `DIALTIMEOUT_RETIME` **only if** S1's
   evidence rule fires (Decision-Criteria 1–2). Each value edit = its own mutation-verified RED test +
   re-run 1to1/feed gates (proposal §10 last bullet). **Stop-if** S1 verdict = "keep 3s / do-not-cap":
   skip step 5 entirely.
6. **GATED (closure)** — register the device scenarios (TC-07-05/06) in
   `check_reliability_simulation_discovery.sh` (`classify_path()` case + dart-define case) and run
   `/sims 1to1 --only <N>`; record median+p90 deltas.

## Risks And Edge Cases

- **Reorder double-starts bonsoir on warm-open** → idempotency guard; pinned by TC-07-02 + active-flag
  assertion.
- **Go bridge serialization** (proposal §10 bullet 3; FDC-S5) — early discovery + reserve + the user's
  first send funnel through one bridge; early-start must not head-of-line block the user send. Pinned
  by: prioritization contract from FDC-S5 (advisory) + transport gate staying green.
- **Refuted cap regression** (someone caps `DialTimeout` blind) → TC-07-04 sentinel re-reds.
- **Cold notif-tap node not started yet** (proposal §6.1 Honest scope) — FDC-07 cannot help before
  node-ready; the win is *early* reserve once node-ready, not pre-node warm. Documented, measured by S1.
- **iOS sim mDNS shared-host** → TC-07-06 device-only, never reported from sim.

## Device/Relay Proof Profile

- **Host-only for closure:** TC-07-01..04 (Go unit + Dart unit/widget) — the **reordering** and
  **preservation** slice closes on host gates.
- **Requires device (closure gate):** TC-07-05 (cold `T_circuit` improvement), TC-07-06 (same-WiFi
  mDNS resolve ≤ LAN budget) — real-wire cold timing, not host-reproducible (FDC-00 closure list:
  FDC-04/06/**07**/11/12 need real-wire device proof).
- **Closure scenario:** `/sims 1to1 --only <N>` `<TODO scenario id — defined with FDC-S1's
  measurement vehicle>`; ≥10 cold trials, ≥2 real iOS + ≥2 real Android, median+p90 (FDC-S1 §Run).

## Acceptance Gates  (LITERAL copy/paste)

```bash
# Go host (reorder + preserved-sentinel)
cd /Users/I560101/Project-Sat/mknoon-2/flutter_app/go-mknoon && go test ./...   # expected: PASS (count: all pkgs PASS / 0 fail (go1.25.0, ~1171 tests))
cd go-mknoon && make lint   # gofmt -l + go vet, expected: clean

# 1:1 host gate (Dart ordering test auto-globs test/core/**)
./scripts/run_test_gates.sh 1to1            # expected: 1226 pass / 0 fail

# host floors
./scripts/run_host_test_gates.sh core-host-all       # expected: 0 fail
./scripts/run_host_test_gates.sh feature-host-all    # expected: 0 fail

# transport gate (background_reconnect / wifi_relay_fallback_smoke / transport_e2e must stay green)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim) pass / 0 fail

# DEVICE CLOSURE GATE (post-S1, scenario id <TODO>)
./scripts/check_reliability_simulation_discovery.sh
# /sims 1to1 --only <N>                # expected: cold T_circuit delta <from FDC-S1>

# hygiene
flutter analyze                              # expected: 0 new
git diff --check                             # expected: clean
```

## Known-Failure Interpretation

- Pre-existing transport-gate flakiness (durable-media-upload, per MEMORY) is **not** FDC-07; re-run
  in isolation. A transport-gate red that only appears with the reorder = real regression (likely
  bridge head-of-line or double-start) → investigate, do not waive.
- TC-07-05/06 cannot go green on host — a "green" there is a false positive; they close on device only.

## Done Criteria

- [ ] TC-07-01..04 RED-first then GREEN, each with its mutation re-verified.
- [ ] No `config.go` value changed (TC-07-04 green; `git diff` shows no const edit) unless S1 unlocked step 5.
- [ ] `go test ./...`, `1to1`, `core-host-all`, `feature-host-all`, `transport` gates green; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] FDC-S1 numbers (`FOREGROUND_RELAY_BUDGET_MS`, `DIALTIMEOUT_RETIME`, `T_circuit`, `T_mdns`) cited in step 5/6 — **not invented**.
- [ ] Every NEW exported Go identifier carries a doc comment beginning with the identifier name (Go convention; the package already does this).
- [ ] Device closure (TC-07-05/06) run and median+p90 recorded, OR explicitly deferred-not-waived with rationale.

## Scope Guard (hard Do-not)

- **Do NOT** reorder, gate, or disturb the group-rejoin/drain block (`:665-720`) — the early mDNS/reservation start must run BEFORE it without changing group reconnect behavior. **Group-safety floor:** Go group/pubsub tests (`cd go-mknoon && go test ./...`) stay green.
- **Do NOT** cap `config.go:28 DialTimeout` (or any timeout) without an FDC-S1 send-path-blocks-on-15s
  evidence record (refuted; proposal §8 P1-3 / §10 bullet 1).
- **Do NOT** add per-peer `warmPeer`/`dialPeer` here (that's FDC-04).
- **Do NOT** move any send-path decision into Go (`node.go` only labels transport).
- **Do NOT** delete `warmBackground`'s inbox-drain / health-check / proactive-send-proof body — only
  hoist the discovery/reserve start earlier.
- **Do NOT** fake TC-07-05/06 green on host/sim.
- **Do NOT** inline the early-anchor emit + reserve-ordering into the already-oversized `node.go` `Start()` (~252 lines) — new feature logic belongs in its own `node/<concern>.go`; factor FDC-07's early reserve/mDNS dispatch into a small helper (e.g. `startEarlyMdnsReserve`), with only minimal registration/teardown touching `Start`.

## Accepted Differences

- The reordering slice can land and re-green host gates **before** FDC-S1 finishes (it changes
  ordering, not values); the budget/timeout slice is strictly S1-gated.
- On the coldest notif-tap path, FDC-07 deliberately does **not** promise pre-node warm overlap
  (proposal §6.1 Honest scope) — accepted, by design.

## Dependency Impact

- **gatedBy:** `FDC-S1` (all budget/timeout values + the device-timing closure thresholds).
- **Collision (sequential):**
  - `lib/core/services/p2p_service_impl.dart` (4250 lines) — also edited by **FDC-04** (`warmPeer`,
    `isLocalPeer` gating) and **FDC-05** (resume re-prime). Same-file → serialize (roadmap "Secondary
    collision"; MEMORY 160→163 feed_wired precedent). Land FDC-07's hoist relative to FDC-04 in a
    fixed order, re-green 1to1 between.
  - `go-mknoon/node/node.go` — Go host, also touched by Go-side plans (e.g. FDC-11 mDNS, FDC-12 DCUtR);
    serialize Go edits.
- **Phase:** Phase 1 (roadmap) — after Phase-0 Dart-only FDC-01..04, gated by S1.
- **No DB migration. Additive-only on Go (`NodeConfig.ProcessStartEpochMs` anchor lands via FDC-S1),
  NET-REL-07 safe (no relay/protocol change).**
