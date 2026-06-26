# FDC-04 — LAN-aware eager `warmPeer` + per-(peer,transport) backoff + network-change re-warm  (New Feature)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.1 "Eager warm — but LAN-aware"; §8 P0-1; refined by §12 "warm by peer-identity + bound every warm dial + network-change re-warm trigger + prefer QUIC")

---

## Source Of Truth

- **Proposal** §6.1 (the headline + the §6.1 "trap that defeats LAN-first" + "Honest scope") and §8 **P0-1**, refined by **§12** ("Strongly-validated patterns to borrow verbatim": *"Warm by peer-identity … Bound every warm dial with per-`(peerId,transport)` backoff (libp2p quadratic 5s→5min). Warm only the per-peer you'll use, never the roster … Add network-change (WiFi↔cellular) as a re-warm trigger; prefer QUIC (a network switch closes ALL connections except QUIC)."*).
- **This epic's roadmap** [`FDC-00-roadmap.md`](FDC-00-roadmap.md): FDC-04 row, the **COLLISION MAP** (FDC-01→02→03→**04** all edit `send_chat_message_use_case.dart`, run **sequentially**), the secondary collision on `p2p_service_impl.dart` (FDC-04/05/08), the Phase-0 sequencing, and the **host-test false-positive caveat** (dedup can mask a dead live path → device-proof mandatory for FDC-04).
- **Gating spikes:** [`FDC-S5`](FDC-S5-go-bridge-concurrency-design-note.md) (warm must stay off the serialized send-critical bridge path; gate `warmPeer` behind node-started; bound to the open peer, never the roster) and [`FDC-S1`](FDC-S1-cold-start-timing-measurement-spike.md) (calibrates the warm budgets + the cold-tap aggressiveness verdict; confirms cold notif-tap warm cannot overlap reading time).
- **`scripts/run_test_gates.sh` wins over prose** for what "green" means — the literal arrays/commands in Acceptance Gates below are authoritative.

---

## Session Classification

**Implementation-ready for the warm-open + reuse-gate + backoff + call-site-wiring core** (all host-testable in pure Dart against the existing `p2p_service_impl_test.dart` / `send_chat_message_use_case_test.dart` / `conversation_wired_test.dart` / `prepare_notification_open_use_case_test.dart` fakes).

**Evidence-gated only on two sub-decisions that this plan parameterizes, not blocks on:**
1. The concrete **warm budget values** (discoverLocalPeer timeout, speculative dial timeout, cooldown floor/ceiling) and whether `warmPeer` may fire on the *coldest* notif-tap → **calibrated by FDC-S1** (default conservative values below, swap-in when S1 lands).
2. The **network-change signal source** (no `connectivity_plus` in `pubspec.yaml` today — verified) → this plan ships the *behavior* against an **injectable network-change signal** (`Stream<void>`, default empty) and flags the real OS source (connectivity_plus add OR a native `NWPathMonitor`/`ConnectivityManager` channel) as a bounded follow-up sub-step with a Stop-if. The host-testable contract ("on signal → re-warm active peer + reset cooldown + drop learned `local`") is locked now.

---

## Exact Problem Statement

**What's broken/missing.** Opening a conversation, tapping a notification, or resuming the app **never dials the specific peer**. The first send therefore always pays a full cold `discover → dial → send` (proposal §4 R1, verified: `warmBackground` at `p2p_service_impl.dart:572-647` warms LAN discovery + inbox drain + health-check but **never dials the contact**). The dominant component of the perceived send window on exactly the reported "open app → send one message → close" case is this missing pre-warm.

**Who feels it.** Every 1:1 sender on a warm-open (app already running, node started): they watch a multi-second "sending…" because the connection is established lazily *at* send-time instead of *during* reading/typing.

**The LAN-first trap (correctness, not just latency).** Naively warming with a speculative `dialPeer` makes it *worse* for same-WiFi peers: libp2p has no mDNS and discovers via relay rendezvous, so a speculative dial commonly lands a `/p2p-circuit` **relay** connection. The reuse fast-path at `send_chat_message_use_case.dart:447-451` fires whenever `currentState.connections` contains the peer **without any `isLocalPeer` check** (verified — the `isLocalPeer` read is only computed later at `:516`, *after* the reuse short-circuit can already have returned). So a warmed relay circuit would make the next send route over **RELAY**, silently bypassing the LAN leg on **every** conversation open (proposal §6.1 ⚠).

**Offline-peer backoff hazard.** Repeated opens/taps/resumes to an **offline** peer would each fire a fresh failing `dialPeer`, accruing libp2p swarm per-address backoff (5s→5m, proposal §6.1 last ¶, §10 bullet 2). Without a per-peer cooldown, warming degrades the very reconnect it's meant to accelerate.

**Network-change staleness.** A WiFi↔cellular switch closes all connections except QUIC (proposal §12, Berty risk note); the learned-transport cache and any warm cooldown then point at a dead path, and nothing re-warms (proposal §12 "Add network-change as a re-warm trigger").

**What must improve.**
- A single idempotent `warmPeer(peerId)` overlaps connection setup with reading/typing on the warm-open path → send hits the reuse fast-path → near-instant ack.
- LAN map seeded **first** so the LAN lane can win; a warmed **relay** circuit must **never** satisfy "already connected" when a LAN path is viable.
- Repeated warms to an offline peer are **debounced** (per-`(peerId,transport)` backoff) and never tight-loop a failing dial.
- A network change re-warms the active peer and invalidates stale transport state, preferring QUIC.

**What must stay unchanged → preserved sentinels.**
- `warmPeer` is **speculative only**: it **never sends a message** and never deposits to the inbox (no `sendMessage`/`sendMessageWithReply`/`storeInInbox` from the warm path). → preserved sentinel **PS-1**.
- The existing send ladder for a **non-local** connected peer is byte-for-byte unchanged: reuse fast-path still fires (`:447-465`). → preserved sentinel **PS-2**.
- `warmPeer` is a **no-op when the node is not started** (`!currentState.isStarted`) — it must never contend for the `Node.Start` write lock (FDC-S5 §6). The cold notif-tap win is **FDC-07's**, not this plan's. → preserved sentinel **PS-3**.
- Warm is **bounded to the open/active peer, never the roster** (FDC-S5 decision-criteria 3; Berty "hundreds of peers cripples the phone"). → preserved sentinel **PS-4**.
- `warmBackground` (`:572-647`) keeps its current LAN-discovery/inbox/health-check behavior; `warmPeer` is **additive**, not a replacement. → preserved sentinel **PS-5**.

---

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, read & verified) | Confirmed / Refuted |
|---|---|---|
| RC1 | **No per-peer eager warm.** `P2PService` (abstract, `lib/core/services/p2p_service.dart:56-…`) has `warmBackground()` (`:90`), `dialPeer(...)` (`:137`), `discoverLocalPeer(...)` (`:194`), `isLocalPeer(...)` (`:189`) but **no `warmPeer`**. `warmBackground` impl (`p2p_service_impl.dart:572-647`) does fast-circuit poll + inbox drain + `_startLocalDiscovery` — it **never calls `dialPeer` for a contact**. | **Confirmed.** New method needed. |
| RC2 | **Reuse fast-path is LAN-blind.** `send_chat_message_use_case.dart:447-451` short-circuits on `currentState.connections.any((c)=>c.peerId==target)` and sends over it with **no `isLocalPeer` gate**; `isLocalPeer` is first read at `:516`, *after* the reuse block can `return`. Sticky short-circuit (`:528-595`) similarly reuses a learned `direct`/`relay` transport; only the learned `'local'` entry is LAN-revalidated (`p2p_service_impl.dart:4117`). | **Confirmed.** A warmed relay conn would bypass LAN. |
| RC3 | **No warm cooldown / backoff in Dart.** No per-peer attempt map exists in `p2p_service_impl.dart`; nothing debounces repeated `dialPeer`. The only backoff is libp2p-swarm-internal (Go), which is exactly what repeated failing warms would trip. | **Confirmed.** New bounded cooldown needed. |
| RC4 | **No network-change trigger / no connectivity source.** `grep` for `connectivity_plus`/`Connectivity`/`NWPathMonitor`/`onConnectivityChanged` across `lib/`, `ios/Runner`, `go-mknoon`, `pubspec.yaml` → **zero** app-level network-change listener (only the libp2p-internal `connectedness` notions in Go vendor). | **Confirmed.** Signal source is a new (injectable) seam. |
| RC5 (refuted — do NOT re-introduce) | "The single bridge serializes warm behind the user's send in the warm state." | **Refuted by FDC-S5** at every layer (iOS concurrent global queue `GoBridge.swift:35-42`; Android cached pool `GoBridge.kt:38`; Go `nodeMu` pointer-read `bridge.go:1027-1029`; `n.mu` RWMutex read-concurrent `node.go:1417-1419`) **and now confirmed empirically** by the host microbench `TestConcurrentSendDialNoSerialize` (`go-mknoon/node/benchmark_bridge_concurrency_test.go`, run under `-race`, GOTOOLCHAIN=go1.25.0): **8 concurrent dials finish in ~0.6 s vs a ~4.8 s serial floor**, and a **real user send completes in <1 ms while 8 speculative warm dials each block ~0.6 s** — the user send is not head-of-line blocked. (Host numbers; device M1 still pending per FDC-S5 Exit Gate.) **Do NOT add a Dart priority queue (Option C) or a second channel (Option D).** The ONE real block is `Node.Start`'s write lock (`node.go:219-220`) — cold path only, host-quantified at ~15 ms via the FDC-S5 M2 `node:startup_timing{phase:start_lock_window}` instrument → handled by **PS-3** (gate warm behind node-started). |
| RC6 (refuted framing) | "Warming makes cold notif-tap instant." | **Refuted by proposal §6.1 Honest scope + FDC-S1.** On cold notif-tap the Go node is not started → `warmPeer` no-ops (PS-3). Do **not** oversell P0 latency on cold starts; that win is FDC-07. |

---

## Real Scope

**In scope (FDC-04):**
- NEW `P2PService.warmPeer(String peerId)` — abstract default no-op (fakes compile unchanged) + `P2PServiceImpl` implementation: gate on `isStarted` (PS-3); per-`(peerId,transport)` cooldown/backoff (RC3); **`discoverLocalPeer` first** to seed the LAN map, in parallel with a speculative `dialPeer` that is **skipped when `isLocalPeer` is already true** (RC1/§6.1); **no send** (PS-1).
- Gate the send **reuse fast-path** (`:447-465`) and **sticky short-circuit** (`:528-595`) behind an `isLocalPeer` check so a warmed relay/direct conn never bypasses a viable LAN path (RC2). **(COLLISION edit — after FDC-03.)**
- Call sites firing `warmPeer`: **conversation-open** (`conversation_wired.dart` `initState` `:498-563`), **notif-tap conversation route** (`prepare_notification_open_use_case.dart` conversation case `:28-44`, plumbed via `prepare_notification_route_target_use_case.dart`), **resume** (`handle_app_resumed.dart:130-191`, the **active conversation peer**, bounded — PS-4, fired in **parallel**, not serialized behind the awaited drain).
- NEW network-change re-warm: an **injectable** `Stream<void>` signal (default empty) → on event, reset the active peer's cooldown, drop its learned `local` transport, and re-fire `warmPeer` preferring QUIC.

**Out of scope → owning FDC-xx:**
- The staggered ranked race / per-leg budgets → **FDC-02**. FDC-04 only adds the `isLocalPeer` reuse gate; it does **not** rewrite the race body.
- Generalizing the concurrent durable inbox / dropping the serial probe→inbox tail → **FDC-03**.
- `direct_timeout`→inbox mis-route correctness fix → **FDC-01**.
- Parallel resume re-prime (relay reserve + mDNS restart fan-out) → **FDC-05** (FDC-04 adds only the per-peer warm call into the resume flow; the broader parallelization is FDC-05).
- Cold-start earlier mDNS/reserve (the cold notif-tap win) → **FDC-07** (gated FDC-S1).
- libp2p LAN-direct dial (bonsoir-fed) / DCUtR upgrade / Redis backend / relay presence lookup → FDC-11 / FDC-12 / FDC-10 / FDC-08.
- The **actual OS connectivity source** (connectivity_plus dependency or native path-monitor channel) — wired into the injectable seam in a bounded follow-up; this plan locks the *behavior*, not the platform plumbing.

---

## Files To Inspect Next

**Production — entry / service:**
- `lib/core/services/p2p_service.dart` — abstract `P2PService`: add `warmPeer` (default no-op) near `warmBackground` `:90`; reference `dialPeer :137`, `isLocalPeer :189`, `discoverLocalPeer :194`, `lastKnownGoodTransport :203`.
- `lib/core/services/p2p_service_impl.dart` — `warmBackground :572-647`, `dialPeer :2092-2145`, `isConnectedToPeer :4092`, `isLocalPeer :4097`, `lastKnownGoodTransport :4100-4122`, `recordSuccessfulTransport :4124-4129`, `discoverLocalPeer :4131-4143`. New: `warmPeer`, `_warmAttempts` map, `onNetworkChanged`.

**Production — send path (COLLISION):**
- `lib/features/conversation/application/send_chat_message_use_case.dart` — reuse `:447-512`, sticky `:528-595`, `isLocalPeer` read `:516`.

**Production — call sites:**
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — `initState :498-563` (warm on open), already holds `widget.p2pService`.
- `lib/features/push/application/prepare_notification_open_use_case.dart` `:21-72` + `prepare_notification_route_target_use_case.dart :15-66` (notif-tap warm hook, optional injected `warmPeer` fn).
- `lib/core/lifecycle/handle_app_resumed.dart :130-191` (resume warm — active peer, parallel).
- `lib/main.dart` — `ConversationWired(...)` construction `:3290`, `:4118`; conversation notif route `:4014-4053`; lifecycle `_onPaused :4314`, `didChangeAppLifecycleState :4288`.

**Direct + integration tests (where RED tests land):**
- `test/core/services/p2p_service_impl_test.dart` (1to1 array `:48`).
- `test/features/conversation/application/send_chat_message_use_case_test.dart` (1to1 `:36`).
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` (1to1 `:63`).
- `test/features/push/application/prepare_notification_open_use_case_test.dart` (1to1 `:66`).
- NEW `test/core/lifecycle/handle_app_resumed_warm_peer_test.dart` (register in `ONE_TO_ONE_TESTS`).
- NEW `integration_test/warm_peer_lan_aware_smoke_test.dart` (register in `TRANSPORT_TESTS` + sims `classify_path()`).

**Dependency-only context:**
- `lib/core/local_discovery/{local_p2p_service,local_discovery_service}.dart` — `discoverLocalPeer`, `isLocalPeer` LAN-map source.
- `lib/core/services/p2p_service_learned_transport_invalidation_test.dart` — the existing `lastKnownGoodTransport` invalidation locks the network-change drop must not regress.

---

## Existing Tests Covering This Area

| Test | Exists? | Gate array | Relevance |
|---|---|---|---|
| `test/core/services/p2p_service_impl_test.dart` | exists | `ONE_TO_ONE_TESTS:48` | Home for `warmPeer` unit locks (RC1/RC3, PS-1/PS-3/PS-4, backoff, network-change). |
| `test/core/services/p2p_service_learned_transport_invalidation_test.dart` | exists | auto-glob (core-host-all) | Locks `lastKnownGoodTransport` TTL/stale invalidation — network-change `local` drop must be consistent. |
| `test/features/conversation/application/send_chat_message_use_case_test.dart` | exists | `ONE_TO_ONE_TESTS:36` | Home for the reuse/sticky `isLocalPeer` gate (RC2) + PS-2 preservation. |
| `test/features/conversation/presentation/screens/conversation_wired_test.dart` | exists | `ONE_TO_ONE_TESTS:63` | Home for the conv-open warm call-site widget lock. |
| `test/features/push/application/prepare_notification_open_use_case_test.dart` | exists | `ONE_TO_ONE_TESTS:66` | Home for the notif-tap warm hook lock. |
| `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` | exists | `ONE_TO_ONE_TESTS:31` | Sibling resume test; the resume warm gets its own NEW file (registered). |
| `integration_test/transport_e2e_test.dart`, `wifi_relay_fallback_smoke_test.dart` | exist | `TRANSPORT_TESTS:166-167` | Transport-label smokes; the NEW warm-overlap smoke joins this array. |
| `handle_app_resumed_warm_peer_test.dart` | **MISSING (create)** | add to `ONE_TO_ONE_TESTS` | Resume warm-peer lock. |
| `warm_peer_lan_aware_smoke_test.dart` | **MISSING (create)** | add to `TRANSPORT_TESTS` | Host-fake LAN-aware overlap smoke (host-green ≠ validated; device-proof below). |

---

## RED Test Catalog

> Tier legend: **U** = unit/application (pure Dart, fakes); **W** = widget (call-site fires warmPeer); **I** = integration (transport gate, host-fake). Each warm path emits a distinct flow-event so a shared "no-op" result is discriminated by *which* event fired.

### U — `warmPeer` core (`test/core/services/p2p_service_impl_test.dart`)

**TC-04-01 ::  warmPeer seeds the LAN map (discoverLocalPeer) before/parallel with the speculative dial**
- Tier U. Setup: started `P2PServiceImpl` with a fake bridge + a fake `LocalP2PService` recording `discoverLocalPeer` calls; `isLocalPeer→false`. Call `warmPeer(peer)`.
- RED-on-HEAD: `warmPeer` does not exist → compile/`NoSuchMethod`.
- GREEN-asserts: `discoverLocalPeer(peer, timeout: warmLanTimeout)` invoked **and** `callP2PPeerDial`/`dialPeer(peer)` invoked; emits `P2P_SERVICE_WARM_PEER_BEGIN` then both `…_LAN_SEED` and `…_DIAL`. The LAN-seed future is started no later than the dial (assert via recorded begin order).
- Mutation: drop the `discoverLocalPeer` call from `warmPeer` → TC re-reds (LAN never seeded → §6.1 relay-bypass).
- Discriminator: `P2P_SERVICE_WARM_PEER_LAN_SEED` distinguishes the LAN leg from the dial leg.

**TC-04-02 ::  warmPeer skips the speculative dial when isLocalPeer is already true (LAN-only)**
- Tier U. Setup: `isLocalPeer→true`. Call `warmPeer(peer)`.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: `discoverLocalPeer` fires; `dialPeer` **not** called; emits `P2P_SERVICE_WARM_PEER_DIAL_SKIPPED {reason:'is_local'}`.
- Mutation: remove the `if (!isLocalPeer)` guard around the dial → dial fires for a local peer → re-red.

**TC-04-03 ::  warmPeer is debounced — a second call within the cooldown does not re-dial**
- Tier U. Setup: `withClock`; `isLocalPeer→false`, dial fails (offline). Call `warmPeer(peer)` twice within `warmCooldownFloor`.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: `dialPeer` invoked **once**; the second call emits `P2P_SERVICE_WARM_PEER_DEBOUNCED`.
- Mutation: remove the `recentlyWarmed` early-return → second dial fires → re-red.

**TC-04-04 ::  per-(peer,transport) backoff escalates on repeated failing dials (5s→…)**
- Tier U. Setup: `withClock`; dial keeps failing. Call `warmPeer`, advance clock past floor, call again (fails again), advance again.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: the `nextEligibleAt` interval **grows** between consecutive failures (floor→2×→… capped at `warmCooldownCeil`); a call before `nextEligibleAt` is `…_DEBOUNCED`, a call after re-dials.
- Mutation: make the cooldown a fixed constant (no growth) → the "advance to 2× then still debounced" assertion re-reds.

**TC-04-05 ::  warmPeer is a no-op when the node is not started (PS-3 / FDC-S5)**
- Tier U. Setup: `P2PServiceImpl` with `isStarted==false`. Call `warmPeer(peer)`.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: **no** `dialPeer`, **no** `discoverLocalPeer`; emits `P2P_SERVICE_WARM_PEER_SKIPPED {reason:'not_started'}`. (This is the cold-notif-tap honesty lock — warming cannot overlap reading time before `node:start`.)
- Mutation: drop the `if (!currentState.isStarted) return;` gate → warm fires while stopped (contends for `Node.Start` write lock) → re-red.

**TC-04-06 ::  warmPeer never sends a message or deposits to the inbox (PS-1 scope lock)**
- Tier U. Setup: started service; spy on bridge send + `storeInInbox`. Call `warmPeer`.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: `sendMessage`/`sendMessageWithReply`/`storeInInbox` call-count **== 0**.
- Mutation: add a stray `sendMessageWithReply` in the warm body → re-red.

**TC-04-07 ::  network-change re-warms the active peer, resets its cooldown, and drops its learned `local` transport**
- Tier U. Setup: started service with an injected `networkChangeSignal` `StreamController`; `recordSuccessfulTransport(peer,'local')`; warm `peer` once (cooldown now active). Push one event on `networkChangeSignal` (mark `peer` active).
- RED-on-HEAD: no `warmPeer`/`onNetworkChanged`.
- GREEN-asserts: after the event `dialPeer`/`discoverLocalPeer` fires **again despite the live cooldown**; `lastKnownGoodTransport(peer)` returns null (the `local` entry was dropped); emits `P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM`.
- Mutation: make `onNetworkChanged` skip the cooldown reset → no re-warm within cooldown → re-red.
- Discriminator: `…_NETWORK_CHANGE_REWARM` vs the plain `…_BEGIN` proves the re-warm came from the network edge, not a fresh open.

**TC-04-08 ::  network-change re-warm prefers QUIC**
- Tier U. Setup: as TC-04-07. Inspect the `dialPeer` invocation on the network-change re-warm.
- RED-on-HEAD: no `warmPeer`; `dialPeer` has no preference param.
- GREEN-asserts: the re-warm dial passes the new additive `preferQuic: true` (or a QUIC-first `addresses` ordering) — `callP2PPeerDial` receives the QUIC-preference flag.
- Mutation: drop the `preferQuic` flag on the network-change dial → re-red.
- Honesty: this is a **hint**; true transport selection is Go-owned (`classifyStreamTransport node.go:123-136`). The host lock asserts the *hint is passed*; the *actual QUIC win* is device-proof (Device/Relay Proof Profile).

### W — call sites

**TC-04-09 ::  opening the conversation screen fires warmPeer(contact.peerId) once (`conversation_wired_test.dart`)**
- Tier W. Setup: pump `ConversationWired` with a fake `P2PService` recording `warmPeer` calls.
- RED-on-HEAD: `initState` (`:498-563`) never calls `warmPeer`.
- GREEN-asserts: exactly **one** `warmPeer(contact.peerId)` after first frame; not awaited (fire-and-forget).
- Mutation: remove the `warmPeer` call from `initState` → re-red.

**TC-04-10 ::  notif-tap conversation route fires warmPeer for the target peer (`prepare_notification_open_use_case_test.dart`)**
- Tier W/U (application). Setup: call `prepareNotificationOpen` with a `conversation` route target carrying a peerId + an injected `warmPeer` spy.
- RED-on-HEAD: `prepareNotificationOpen` has no warm hook (only `drainOfflineInbox`).
- GREEN-asserts: `warmPeer(targetPeerId)` invoked once for the `conversation` case; **not** for `group`/`intros`/`contactRequest`/`post` cases.
- Mutation: remove the warm hook from the `conversation` case → re-red.
- Honesty: on a **cold** notif-tap the service-level PS-3 gate (TC-04-05) makes the warm a no-op; this lock only proves the *hook fires*, the win is warm-resume.

**TC-04-11 ::  resume warms the active conversation peer, bounded and in parallel (`handle_app_resumed_warm_peer_test.dart`, NEW)**
- Tier U. Setup: call `handleAppResumed` with a fake `P2PService` recording `warmPeer`, an active-peer source (`conversationTracker`/active-peer arg) set to one peer, and a roster of many contacts.
- RED-on-HEAD: resume flow (`:130-191`) never warms a peer.
- GREEN-asserts: `warmPeer(activePeer)` invoked; **roster peers are NOT warmed** (count ≤ bounded N, PS-4); the warm is **not** awaited behind the serial drain (does not increase drain latency).
- Mutation: change resume to warm `for (c in roster) warmPeer(c)` → the "roster not warmed / count ≤ N" assertion re-reds.

### U — send-path reuse/sticky gate (COLLISION; `send_chat_message_use_case_test.dart`)

**TC-04-12 ::  a same-WiFi peer with a (relay) connection does NOT take the reuse fast-path — the LAN leg is attempted (RC2 / §6.1)**
- Tier U. Setup: `isLocalPeer(target)→true`; `currentState.connections` contains `target` (a warmed relay conn); LAN send succeeds.
- RED-on-HEAD: reuse short-circuit at `:447-451` fires regardless of `isLocalPeer` → `sendPath=='reuse'`, transport relay/direct, LAN never attempted.
- GREEN-asserts: `CHAT_MSG_SEND_REUSE_CONNECTION` **not** emitted; the LAN leg fires; final `via=='local'`.
- Mutation: remove the `&& !isLocalPeer` guard from the reuse condition → reuse fires for a local peer → re-red.
- Discriminator: absence of `CHAT_MSG_SEND_REUSE_CONNECTION` + `via=='local'` distinguishes "raced LAN" from "reused relay".

**TC-04-13 ::  a learned `relay`/`direct` sticky transport does NOT short-circuit a LAN-visible peer**
- Tier U. Setup: `isLocalPeer(target)→true`; `lastKnownGoodTransport(target)=='relay'`; LAN send succeeds.
- RED-on-HEAD: sticky short-circuit (`:528-595`) reuses the learned relay path for a local peer.
- GREEN-asserts: `CHAT_MSG_SEND_STICKY_TRANSPORT` for a non-`local` learned value does not short-circuit when `isLocalPeer` is true; `via=='local'`.
- Mutation: remove the `isLocalPeer` guard from the sticky gate → sticky relay fires → re-red.

**TC-04-14 ::  PS-2 preservation — a NON-local connected peer still takes the reuse fast-path (no regression)**
- Tier U. Setup: `isLocalPeer(target)→false`; `connections` contains `target`; reuse send succeeds.
- RED-on-HEAD: passes today (preservation) — written to FAIL if the new gate over-fires (i.e. if the gate accidentally blocks non-local reuse).
- GREEN-asserts: `CHAT_MSG_SEND_REUSE_CONNECTION` emitted; `sendPath=='reuse'`; transport unchanged vs HEAD.
- Mutation: broaden the gate to `if (!isAlreadyConnected || isLocalPeer)`-style over-block → non-local reuse skipped → re-red. (Locks the gate is **LAN-only**, not a blanket reuse disable.)

### I — transport-gate smoke (`integration_test/warm_peer_lan_aware_smoke_test.dart`, NEW)

**TC-04-15 ::  warm-then-send over LAN — warmPeer seeds the LAN map so the subsequent same-WiFi send takes `local`, and a warmed relay conn does not bypass it (host-fake)**
- Tier I. Setup: host harness with a fake LAN stack where `peer` is LAN-visible and also has a relay conn in `connections`. `await warmPeer(peer)`; then `sendChatMessage`.
- RED-on-HEAD: no `warmPeer`; and even stubbed, the reuse path would label `relay`.
- GREEN-asserts: transport label `local`; warm emitted `…_LAN_SEED`; reuse not taken.
- Mutation: revert the `isLocalPeer` reuse gate (TC-04-12 prod edit) → label flips to `relay`/`reuse` → re-red.
- **Honesty (roadmap host-test caveat):** a host fake can pass via `messageId` dedup even if the live LAN leg never fired. Host-green proves *delivery + label wiring*, **not** a real LAN win → device-proof mandatory (below).

---

## Test Coverage Matrix

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| warmPeer seeds LAN first + dials | RC1, §6.1 | U | `p2p_service_impl_test.dart::TC-04-01` | no `warmPeer` method | drop `discoverLocalPeer` call | `run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS:48` |
| skip dial when isLocalPeer | §6.1 | U | `p2p_service_impl_test.dart::TC-04-02` | no `warmPeer` | remove `if(!isLocalPeer)` | `1to1` | `:48` |
| debounce within cooldown | RC3 | U | `p2p_service_impl_test.dart::TC-04-03` | no `warmPeer` | remove `recentlyWarmed` early-return | `1to1` | `:48` |
| backoff escalates 5s→ceil | RC3, §12 | U | `p2p_service_impl_test.dart::TC-04-04` | no `warmPeer` | fixed (non-growing) cooldown | `1to1` | `:48` |
| no-op when node not started | PS-3, FDC-S5 | U | `p2p_service_impl_test.dart::TC-04-05` | no `warmPeer` | drop `isStarted` gate | `1to1` | `:48` |
| never sends / inboxes | PS-1 | U | `p2p_service_impl_test.dart::TC-04-06` | no `warmPeer` | add stray `sendMessageWithReply` | `1to1` | `:48` |
| network-change re-warm + reset + drop local | RC4, §12 | U | `p2p_service_impl_test.dart::TC-04-07` | no `onNetworkChanged` | skip cooldown reset | `1to1` | `:48` |
| network-change prefers QUIC | §12 | U | `p2p_service_impl_test.dart::TC-04-08` | no preferQuic param | drop `preferQuic` flag | `1to1` | `:48` |
| conv-open fires warmPeer | call site | W | `conversation_wired_test.dart::TC-04-09` | initState no warm | remove initState warm | `1to1` | `ONE_TO_ONE_TESTS:63` |
| notif-tap fires warmPeer (conversation only) | call site | W/U | `prepare_notification_open_use_case_test.dart::TC-04-10` | no warm hook | remove conversation-case hook | `1to1` | `:66` |
| resume warms active peer, bounded/parallel | PS-4, call site | U | `handle_app_resumed_warm_peer_test.dart::TC-04-11` | resume no warm | warm whole roster | `1to1` | **ADD to `ONE_TO_ONE_TESTS`** |
| local peer + relay conn → no reuse, LAN attempted | RC2, §6.1 | U | `send_chat_message_use_case_test.dart::TC-04-12` | reuse LAN-blind `:447-451` | remove `&& !isLocalPeer` | `1to1` | `ONE_TO_ONE_TESTS:36` |
| local peer + learned relay → no sticky | RC2 | U | `send_chat_message_use_case_test.dart::TC-04-13` | sticky LAN-blind `:528-595` | remove isLocalPeer sticky gate | `1to1` | `:36` |
| non-local connected → reuse preserved | PS-2 | U | `send_chat_message_use_case_test.dart::TC-04-14` | (preservation) over-block | broaden gate to block non-local | `1to1` | `:36` |
| warm-then-LAN-send label `local` | RC1/RC2 wire | I | `warm_peer_lan_aware_smoke_test.dart::TC-04-15` | no `warmPeer`; relay label | revert reuse gate | `run_test_gates.sh transport` | **ADD to `TRANSPORT_TESTS` + sims `classify_path()`** |

No empty cells.

---

## Blind-Spot Sweep

| Dimension | Row |
|---|---|
| **Lifecycle / derived-state durability** | Network-change drops the learned `local` transport (TC-04-07) — must stay consistent with the existing `lastKnownGoodTransport` TTL/stale-departure invalidation (`p2p_service_learned_transport_invalidation_test.dart`). The drop is *additive* (a new invalidation trigger), not a change to TTL semantics → run that test in core-host-all. The warm cooldown map is in-memory/session-scoped (lost on restart = correct; a restart is a fresh warm). |
| **Sibling-surface consistency** | `warmPeer` is fired from THREE surfaces (conv-open W, notif-tap W, resume U) plus the network-change edge — all four funnel through the single idempotent service method, so the debounce/cooldown/PS-3 gate apply uniformly. TC-04-09/10/11 lock each surface; TC-04-05 (PS-3) and TC-04-03 (debounce) lock the shared guards so no surface can bypass them. Group conversations are **out of scope** (1:1 only) — verified `warmPeer` is not wired into `group_conversation_wired.dart`; documented as an Accepted Difference. |
| **Destructive-action side-effects** | `warmPeer` performs **no destructive action** — no send, no inbox deposit, no state mutation beyond the cooldown map + a speculative dial that libp2p coalesces with the real send dial (FDC-S5 §7: same-peer dials dedupe into one). PS-1 (TC-04-06) locks "no send/inbox." No message can be lost/duplicated by warming. |
| **Invariant re-verification under new transitions** | The reuse/sticky `isLocalPeer` gate is a NEW branch in the hottest send region. PS-2 (TC-04-14) re-verifies the non-local reuse invariant still holds; TC-04-12/13 verify the new local branch. The "stale local preference never traps a send" invariant (`send_chat_message_use_case.dart:526` comment) is preserved — a null/miss still degenerates to the full race. Because this edits the FDC-01/02/03 collision region, **re-run the full `1to1` gate after landing on top of FDC-03's tree**, not against HEAD. |
| **Cold-path honesty** | New transition "cold notif-tap" — PS-3/TC-04-05 explicitly locks the no-op so the plan cannot silently claim a cold-start win that belongs to FDC-07. |
| **Bridge serialization (FDC-S5)** | N/A as a *mutex* problem (refuted RC5), but the bound-to-active-peer constraint (PS-4/TC-04-11) is the thread-pool-saturation guard FDC-S5 decision-criterion 3 requires. |

---

## Invariants (locked by tests)

- **INV-1** `warmPeer` seeds the LAN map (`discoverLocalPeer`) **before/at-least-parallel** with the speculative dial, so the LAN lane can win the FDC-02 ranked race (TC-04-01).
- **INV-2** A warmed **relay/direct** connection never satisfies the send reuse/sticky short-circuit when the peer is LAN-visible (TC-04-12/13); non-local reuse is unchanged (TC-04-14).
- **INV-3** `warmPeer` is single-shot/debounced/backoff-bounded per `(peerId,transport)` — repeated warms to an offline peer never tight-loop a failing dial (TC-04-03/04).
- **INV-4** `warmPeer` is a strict no-op while the node is not started (PS-3, TC-04-05) — never contends for the `Node.Start` write lock; cold-tap warming is honestly empty.
- **INV-5** `warmPeer` never sends or inboxes (PS-1, TC-04-06) — speculative only.
- **INV-6** A network change re-warms the active peer, resets its cooldown, drops its learned `local` transport, and prefers QUIC (TC-04-07/08).
- **INV-7** Warm is bounded to the open/active peer, never the roster (PS-4, TC-04-11).

---

## Step-By-Step Implementation Plan

> RED first for every step. Land **on top of FDC-03's committed tree** (collision file). Each behavior-bearing edit names its seam.

1. **RED:** add TC-04-05 (PS-3 no-op) and TC-04-06 (PS-1 no-send) to `p2p_service_impl_test.dart`. Both fail to compile (no `warmPeer`). *Seam:* `P2PService.warmPeer`.
2. **GREEN (skeleton):** add `Future<void> warmPeer(String peerId)` to `lib/core/services/p2p_service.dart` as an abstract **default no-op** (so all fakes/mocks compile unchanged — mirror the `discoverLocalPeer` default at `:194`). Implement in `p2p_service_impl.dart`: first lines `if (!currentState.isStarted) { emit …SKIPPED not_started; return; }` then `await _allowsAccountNetworkSideEffects('p2p_warm_peer')`. No dial yet. TC-04-05/06 green. *Stop-if:* if `_allowsAccountNetworkSideEffects` gate semantics differ for warm, reuse the existing pattern (`dialPeer` uses `'p2p_dial_peer'` at `:2097`).
3. **RED:** TC-04-01 (LAN-seed + dial) and TC-04-02 (skip dial when local). *Seam:* warmPeer body.
4. **GREEN:** body = `final lan = discoverLocalPeer(peerId, timeout: warmLanTimeout);` started first; `final dial = isLocalPeer(peerId) ? Future.value(false) : dialPeer(peerId, timeoutMs: warmDialTimeout.inMilliseconds);` then `await Future.wait([lan, dial])` with per-leg `catchError`. Emit `…_BEGIN/_LAN_SEED/_DIAL/_DIAL_SKIPPED`. *Seam:* `warmPeer` + `dialPeer :2092` + `discoverLocalPeer :4131`.
5. **RED:** TC-04-03 (debounce) + TC-04-04 (backoff escalation). *Seam:* `_warmAttempts` map.
6. **GREEN:** add `final Map<String,_WarmAttempt> _warmAttempts` (key `peerId` for the dial leg; the proposal's "per-(peer,transport)" is honored by keying the dial-leg cooldown separately from any future LAN-leg cooldown). `recentlyWarmed(peer)` early-returns `…_DEBOUNCED` if `clock.now() < nextEligibleAt`. On dial failure, `nextEligibleAt = now + min(prev*2, warmCooldownCeil)` starting `warmCooldownFloor`; on success, reset/remove the entry. Use `clock.now()` (matches `lastKnownGoodTransport :4105`) so `withClock` drives it. *Stop-if (FDC-S1):* `warmCooldownFloor`/`Ceil`, `warmLanTimeout`, `warmDialTimeout` default to {5s, 5m, 1500ms (=`interactiveLocalBudget`), 4s (=`InteractiveDialTimeout`)} — swap to S1's measured values when S1 lands; record the assumption inline.
7. **RED:** TC-04-07 (network-change re-warm) + TC-04-08 (preferQuic). *Seam:* `onNetworkChanged` + injected `networkChangeSignal`.
8. **GREEN:** add a constructor-injected `Stream<void>? networkChangeSignal` (default null → empty), subscribe in the start path; `void onNetworkChanged()` → for the active/last-warmed peer(s): `_warmAttempts.remove(peer)` (reset cooldown), drop `_learnedTransport[peer]` if `=='local'`, then `warmPeer(peer, preferQuic:true)`. Add additive `bool preferQuic=false` to `dialPeer` (and `callP2PPeerDial`) — passed through to Go as a hint; default false keeps every existing caller unchanged. Emit `…_NETWORK_CHANGE_REWARM`. *Stop-if:* the real OS connectivity source is a **bounded follow-up** — decide between (a) add `connectivity_plus` and map `onConnectivityChanged` → the signal, or (b) a native `NWPathMonitor`/`ConnectivityManager` MethodChannel. This plan wires the *behavior* against the injectable stream; do NOT block FDC-04 on the source choice. Flag in Accepted Differences.
9. **RED:** TC-04-09 (conv-open). *Seam:* `conversation_wired.dart initState`.
10. **GREEN:** in `initState` (`:560` region, alongside the existing notif-tap drain) add `unawaited(widget.p2pService.warmPeer(_contact.peerId));` — fire-and-forget, after the existing setup. *Seam:* `conversation_wired.dart:498-563`.
11. **RED:** TC-04-10 (notif-tap). *Seam:* `prepareNotificationOpen` conversation case.
12. **GREEN:** add an optional `Future<void> Function(String peerId)? warmPeer` param to `prepareNotificationOpen` (default null); in the `conversation` case call `if (warmPeer != null) unawaited(warmPeer(routeTarget.peerId))`. Plumb from `prepareNotificationRouteTarget` (carries the route target + p2p access). *Seam:* `prepare_notification_open_use_case.dart:28-44` + `prepare_notification_route_target_use_case.dart`.
13. **RED:** TC-04-11 (resume, bounded/parallel). *Seam:* `handle_app_resumed.dart`.
14. **GREEN:** in `handleAppResumed`, after the health-check (so the node is confirmed started — PS-3) fire `unawaited(p2pService.warmPeer(activePeer))` for the active conversation peer **only** (source: an injected active-peer getter / `conversationTracker`), **not** the roster (PS-4). Must NOT be awaited inside the serial drain chain. *Seam:* `handle_app_resumed.dart:130-191`. *Stop-if:* if **FDC-05** (parallel resume re-prime) already restructured this `:130-191` block, slot the `warmPeer` call into FDC-05's parallel set instead of the serial chain — do NOT re-serialize. Pin order with FDC-05 (recommend FDC-05 first; see Dependency Impact).
15. **RED:** TC-04-12/13/14 (reuse/sticky `isLocalPeer` gate). *Seam:* `send_chat_message_use_case.dart` reuse `:447-451` + sticky `:528-595`.
16. **GREEN (COLLISION edit):** hoist the `isLocalPeer` read **above** the reuse block; change reuse condition to `if (isAlreadyConnected && !isLocalPeer)`; gate the sticky short-circuit so a non-`local` learned value does not short-circuit a LAN-visible peer (`if (learned != null && (learned == 'local' || !isLocalPeer))`). Preserve the existing `'local'` revalidation. *Seam:* `:447-516`, `:528-595`. *Stop-if:* if FDC-02 already moved this region, rebase onto FDC-02's race body; the gate is the only FDC-04 change here.
17. **RED:** TC-04-15 (transport smoke). *Seam:* new `integration_test/warm_peer_lan_aware_smoke_test.dart`.
18. **GREEN + register:** author the smoke; append it to `TRANSPORT_TESTS` in `scripts/run_test_gates.sh` and add a `classify_path()` + dart-define case in `scripts/check_reliability_simulation_discovery.sh`. Append `handle_app_resumed_warm_peer_test.dart` to `ONE_TO_ONE_TESTS`.
19. **Mutation pass:** for every behavior-bearing edit, apply its catalogued mutation, confirm the named TC re-reds, revert.
20. **Gates:** run the full Acceptance Gates (on the FDC-03 tree), `flutter analyze`, `git diff --check`; then `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (per CLAUDE.md, app-owned edits).

---

## Risks And Edge Cases

| Risk | Pinned by |
|---|---|
| Warmed relay circuit bypasses LAN (the §6.1 trap) | TC-04-12/13 (reuse+sticky gate) |
| Repeated opens to an offline peer trip swarm backoff | TC-04-03/04 (debounce + escalating cooldown) |
| Warm fires before node-start → contends for `Node.Start` write lock | TC-04-05 (PS-3 no-op) |
| Warm accidentally sends/duplicates a message | TC-04-06 (PS-1) |
| Network switch leaves stale `local` learned transport + dead cooldown | TC-04-07 (drop+reset) |
| Warm fans out across the roster → thread-pool saturation (Berty) | TC-04-11 (bounded to active peer, PS-4) |
| New reuse gate over-blocks non-local reuse → latency regression | TC-04-14 (PS-2 preservation) |
| preferQuic hint mis-asserted as a real QUIC win | TC-04-08 host = hint only; device-proof for the wire |
| Host fake passes via dedup though LAN leg never fired | TC-04-15 honesty note + mandatory device-proof |
| Collision clobber of FDC-01/02/03 edits | land sequentially on FDC-03's committed tree; full `1to1` re-run |

---

## Device/Relay Proof Profile

**Host-logic closure only (NOT full plan closure):** TC-04-01..14 (warm core, gates, call sites, reuse/sticky gate) close the *logic* in pure Dart against existing fakes — but **full plan closure requires the sim/device proof below** (the LAN-`local` win is not host-provable; `messageId` dedup can mask a dead LAN leg).

**Requires sim/device (NOT host-closable):**
- **TC-04-15 wire behavior** — host-green proves label-wiring + delivery only; `messageId` dedup can mask a dead LAN leg (roadmap host-test caveat). 
- **Closure scenario:** a real **two-device same-WiFi pair**: open the conversation (fires `warmPeer`), observe (via flow-events / transport label) that the subsequent send takes **`local`** and that a pre-existing relay conn did **not** bypass it; then toggle WiFi→cellular and confirm the **network-change re-warm** prefers QUIC. Run `./scripts/check_reliability_simulation_discovery.sh` then `/sims 1to1 --only N` (after adding the `classify_path()` case). Note: iOS sim shares a host mDNS stack → LAN-`local` validation is **device-only** (`e2e_test_mode.dart:2 kDisableLocalDiscovery`; proposal §6.5).
- **Cold notif-tap** — device-confirm the PS-3 no-op (warm empty before node-start); the cold win is FDC-07, gated FDC-S1.

---

## Acceptance Gates

```bash
# 1:1 home gate (warmPeer unit + reuse/sticky gate + call sites). Run on the FDC-03 tree.
./scripts/run_test_gates.sh 1to1            # expected pass count: 1226 (capture FDC-03-green baseline; prior 1:1 ~1226)

# transport gate (warm-overlap smoke joins TRANSPORT_TESTS)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim)

# feed regression floor
./scripts/run_test_gates.sh feed            # expected: 279 (prior ~276)

# host floors
./scripts/run_host_test_gates.sh feature-host-all   # 0 fail
./scripts/run_host_test_gates.sh core-host-all      # 0 fail (incl. p2p_service_learned_transport_invalidation_test.dart)

# group-safety floor (warmPeer must not touch the shared host's group behavior — Scope Guard)
./scripts/run_test_gates.sh groups                  # 0 fail (no group regression)

# hygiene
flutter analyze                              # 0 new
git diff --check

# closure (Phase-0 → before Phase 1): reliability sims + a two-device same-WiFi smoke
./scripts/check_reliability_simulation_discovery.sh
/sims 1to1 --only N                          # asserts transport label local (NOT relay) on warm-open
```

No Go/relay changes in FDC-04 (the `preferQuic` hint is an additive Dart→bridge param; the Go-side honoring of it, if any, is flagged but not required for host closure). `cd go-mknoon && go test ./...` must stay green if the bridge param is plumbed.

---

## Known-Failure Interpretation

- A `1to1` failure **only** in `send_chat_message_use_case_test.dart` reuse/sticky cases after step 16 = the collision rebase onto FDC-03 is off — re-diff against FDC-03's tree, not HEAD.
- `p2p_service_learned_transport_invalidation_test.dart` red = the network-change `local` drop changed TTL semantics it shouldn't — the drop must be an *additional* trigger, not a TTL edit.
- A `transport` smoke that passes only via the inbox copy (label `inbox`/`relay`, not `local`) = the host false-positive (dedup masking a dead LAN leg) — **not** a real green for the fast path; needs device-proof.
- Pre-existing flakes (durable-media-upload `ML-004`, ambient_background guard) are NOT FDC-04 — confirm by running the named test in isolation.

---

## Done Criteria

- [ ] `warmPeer` added (abstract default no-op + impl): LAN-seed-first, isLocalPeer-skip-dial, debounce + escalating per-peer backoff, PS-3 not-started no-op, PS-1 never-send.
- [ ] Reuse + sticky short-circuit gated behind `isLocalPeer` (RC2); non-local reuse preserved (PS-2).
- [ ] Call sites wired: conv-open, notif-tap (conversation only), resume (active peer, bounded, parallel).
- [ ] Network-change re-warm: reset cooldown + drop learned `local` + preferQuic, against the injectable signal.
- [ ] TC-04-01..15 RED-first then GREEN; every behavior edit mutation-verified (re-red + revert).
- [ ] `handle_app_resumed_warm_peer_test.dart` added to `ONE_TO_ONE_TESTS`; `warm_peer_lan_aware_smoke_test.dart` added to `TRANSPORT_TESTS` + sims `classify_path()`.
- [ ] All Acceptance Gates green on the FDC-03 tree; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Two-device same-WiFi smoke shows `local` on warm-open and QUIC-pref on WiFi→cellular (device-proof, can be deferred-not-waived with FDC-S1).
- [ ] `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` run.

---

## Scope Guard (hard Do-not)

- **Do NOT** wire `warmPeer`/`dialPeer`/`discoverLocalPeer` into any group surface (`group_conversation_wired.dart`) or let the warm path change group messaging — `warmPeer` is **1:1-only**. **Group-safety floor:** `./scripts/run_test_gates.sh groups` 0-regress.
- **Do NOT** add a Dart priority queue or a second MethodChannel (FDC-S5 rejects Options C/D — solves an absent problem and re-serializes the FDC-02/03 race).
- **Do NOT** rewrite the race body / per-leg budgets (FDC-02) or generalize the inbox (FDC-03) or touch `direct_timeout` (FDC-01) — FDC-04 only adds the `isLocalPeer` reuse/sticky gate in that file.
- **Do NOT** warm the roster — active/open peer only (PS-4).
- **Do NOT** fire `warmPeer` before node-start (PS-3) — no cold-start latency claim.
- **Do NOT** make `warmPeer` send or inbox (PS-1).
- **Do NOT** re-time `DialTimeout`/foreground budgets here (FDC-07/FDC-S1).
- **Do NOT** run any mutating git/graphify-build inside `graphify-arch/`.

---

## Accepted Differences

- **Group conversations** are not warmed (1:1 only) — `warmPeer` is wired into 1:1 surfaces only; group warm is a future plan if measured worthwhile.
- **Network-change OS source deferred** — FDC-04 ships the behavior against an injectable `Stream<void>`; the real `connectivity_plus`/native-path-monitor wiring is a bounded follow-up (no `connectivity_plus` in `pubspec.yaml` today, verified). The behavior is fully host-locked now (TC-04-07/08).
- **preferQuic is a hint** — the Dart→bridge flag is asserted host-side; the actual QUIC transport selection is Go-owned and device-proven.
- **Cold notif-tap warm is intentionally empty** (PS-3) — accepted; the cold win is FDC-07.

---

## Dependency Impact

- **Gated by FDC-S5** (advisory, honored as hard constraints): warm off the cold-start critical path (PS-3 node-started gate), bound to the open peer (PS-4), no Dart queue/second channel; the bridge is true-parallel in the warm state so the parallel `Future.wait([lan, dial])` is real concurrency.
- **Calibrated by FDC-S1**: the warm budget/cooldown constants (step 6) and the cold-tap aggressiveness verdict (PS-3) plug in S1's numbers; defaults conservative until then.
- **COLLISION (sequential, after FDC-03)**: `lib/features/conversation/application/send_chat_message_use_case.dart` — the reuse/sticky `isLocalPeer` gate. Land on FDC-03's committed tree per the FDC-00 collision rule (FDC-01→02→03→04).
- **Secondary collision** (different phases — serialize only if co-scheduled): `lib/core/services/p2p_service_impl.dart` with FDC-08 (presence-lookup cache). *(FDC-05 does NOT edit `p2p_service_impl.dart` — it reorders call sites in `handle_app_resumed.dart` + the test fake only.)*
- **Tertiary collision (real FDC-04↔FDC-05 overlap):** `lib/core/lifecycle/handle_app_resumed.dart` (`:130-191`) — this plan's resume `warmPeer` call-site (step 14) and FDC-05's un-serialization of that block touch the same region. **Land FDC-05 first** and slot the warm call into its parallel block; if FDC-04 lands first, rebase the resume call when FDC-05 restructures (see Step-14 stop-if).
- **Feeds**: FDC-02's ranked race relies on INV-1 (LAN seeded first) and can later drop the explicit `isLocalPeer` gate in favor of ranking (proposal §6.2: "keep it only as belt-and-suspenders"). FDC-07 owns the cold-start win this plan honestly defers.
