# FDC-04 — LAN-aware eager `warmPeer` + per-(peer,transport) backoff + network-change re-warm  (New Feature)

Status: awaiting-review
Spec: Network-Arch/Fast-Direct-Connection-Architecture-Proposal.md (§6.1 "Eager warm — but LAN-aware"; §8 P0-1; refined by §12 "warm by peer-identity + bound every warm dial + network-change re-warm trigger + prefer QUIC")

---

## Source Of Truth

- **Proposal** §6.1 (the headline + the §6.1 "trap that defeats LAN-first" + "Honest scope") and §8 **P0-1**, refined by **§12** ("Strongly-validated patterns to borrow verbatim": *"Warm by peer-identity … Bound every warm dial with per-`(peerId,transport)` backoff (libp2p quadratic 5s→5min). Warm only the per-peer you'll use, never the roster … Add network-change (WiFi↔cellular) as a re-warm trigger; prefer QUIC (a network switch closes ALL connections except QUIC)."*).
- **This epic's roadmap** [`FDC-00-roadmap.md`](FDC-00-roadmap.md): FDC-04 row, the **COLLISION MAP** (FDC-01→02→03→**04** all edit `send_chat_message_use_case.dart`, run **sequentially**), the secondary collision on `p2p_service_impl.dart` (FDC-04/08 — **not** FDC-05, which only reorders `handle_app_resumed.dart` call sites + the test fake), the Phase-0 sequencing, and the **host-test false-positive caveat** (dedup can mask a dead live path → device-proof mandatory for FDC-04).
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

**What's broken/missing.** Opening a conversation, tapping a notification, or resuming the app **never dials the specific peer**. The first send therefore always pays a full cold `discover → dial → send` (proposal §4 R1, verified: `warmBackground` at `p2p_service_impl.dart:596-676` warms LAN discovery + inbox drain + health-check but **never dials the contact**). The dominant component of the perceived send window on exactly the reported "open app → send one message → close" case is this missing pre-warm.

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
- The existing send ladder for a **non-local** connected peer **with a DIRECT connection** is byte-for-byte unchanged: reuse fast-path still fires (block `:447-512`, guard at `:447-451`). → preserved sentinel **PS-2**. ⚠ **Narrowed (C1 / FDC-02 option A, 2026-06-26):** a non-local peer whose ONLY connection is a relay-only `/p2p-circuit` **no longer reuses** — FDC-02 made that block circuit-aware (relay-only ⇒ enter the staggered race). PS-2 now covers the **direct-conn** reuse path only; FDC-04 lands on FDC-02's committed tree, so the circuit-awareness is already present.
- `warmPeer` is a **no-op when the node is not started** (`!currentState.isStarted`) — it must never contend for the `Node.Start` write lock (FDC-S5 §6). The cold notif-tap win is **FDC-07's**, not this plan's. → preserved sentinel **PS-3**.
- Warm is **bounded to the open/active peer, never the roster** (FDC-S5 decision-criteria 3; Berty "hundreds of peers cripples the phone"). → preserved sentinel **PS-4**.
- `warmBackground` (`:596-676`) keeps its current LAN-discovery/inbox/health-check behavior; `warmPeer` is **additive**, not a replacement. → preserved sentinel **PS-5**.

---

## Root Cause (verify→refute confirmed)

| # | Mechanism (file:line, read & verified) | Confirmed / Refuted |
|---|---|---|
| RC1 | **No per-peer eager warm.** `P2PService` (abstract, `lib/core/services/p2p_service.dart:56-…`) has `warmBackground()` (`:90`), `dialPeer(...)` (`:137`), `discoverLocalPeer(...)` (`:194`), `isLocalPeer(...)` (`:189`) but **no `warmPeer`**. `warmBackground` impl (`p2p_service_impl.dart:596-676`) does fast-circuit poll + inbox drain + `_startLocalDiscovery` — it **never calls `dialPeer` for a contact**. | **Confirmed.** New method needed. |
| RC2 | **Reuse fast-path is LAN-blind.** `send_chat_message_use_case.dart:447-451` short-circuits on `currentState.connections.any((c)=>c.peerId==target)` and sends over it with **no `isLocalPeer` gate**; `isLocalPeer` is first read at `:516`, *after* the reuse block can `return`. Sticky short-circuit (`:528-595`) similarly reuses a learned `direct`/`relay` transport; only the learned `'local'` entry is LAN-revalidated (`p2p_service_impl.dart:4161`, inside `lastKnownGoodTransport` `:4144-4166`). | **Confirmed.** A warmed relay conn would bypass LAN. |
| RC3 | **No warm cooldown / backoff in Dart.** No per-peer attempt map exists in `p2p_service_impl.dart`; nothing debounces repeated `dialPeer`. The only backoff is libp2p-swarm-internal (Go), which is exactly what repeated failing warms would trip. | **Confirmed.** New bounded cooldown needed. |
| RC4 | **No network-change trigger / no connectivity source.** `grep` for `connectivity_plus`/`Connectivity`/`NWPathMonitor`/`onConnectivityChanged` across `lib/`, `ios/Runner`, `go-mknoon`, `pubspec.yaml` → **zero** app-level network-change listener (only the libp2p-internal `connectedness` notions in Go vendor). | **Confirmed.** Signal source is a new (injectable) seam. |
| RC5 (refuted — do NOT re-introduce) | "The single bridge serializes warm behind the user's send in the warm state." | **Refuted by FDC-S5** at every layer (iOS concurrent global queue `GoBridge.swift:35-42`; Android cached pool `GoBridge.kt:38`; Go `nodeMu` pointer-read `bridge.go:1027-1029`; `n.mu` RWMutex read-concurrent `node.go:1417-1419`) **and now confirmed empirically** by the host microbench `TestConcurrentSendDialNoSerialize` (`go-mknoon/node/benchmark_bridge_concurrency_test.go`, run under `-race`, GOTOOLCHAIN=go1.25.0): **8 concurrent dials finish in ~0.6 s vs a ~4.8 s serial floor**, and a **real user send completes in <1 ms while 8 speculative warm dials each block ~0.6 s** — the user send is not head-of-line blocked. (Host numbers; device M1 still pending per FDC-S5 Exit Gate.) **Do NOT add a Dart priority queue (Option C) or a second channel (Option D).** The ONE real block is `Node.Start`'s write lock (`node.go:219-220`) — cold path only, host-quantified at ~15 ms via the FDC-S5 M2 `node:startup_timing{phase:start_lock_window}` instrument → handled by **PS-3** (gate warm behind node-started). |
| RC6 (refuted framing) | "Warming makes cold notif-tap instant." | **Refuted by proposal §6.1 Honest scope + FDC-S1.** On cold notif-tap the Go node is not started → `warmPeer` no-ops (PS-3). Do **not** oversell P0 latency on cold starts; that win is FDC-07. |

---

## Real Scope

**In scope (FDC-04):**
- NEW `P2PService.warmPeer(String peerId)` — abstract default no-op (fakes compile unchanged) + `P2PServiceImpl` implementation: gate on `isStarted` (PS-3); per-`(peerId,transport)` cooldown/backoff (RC3); **`discoverLocalPeer` first** to seed the LAN map, in parallel with a speculative `dialPeer` that is **skipped when `isLocalPeer` is already true** (RC1/§6.1); **no send** (PS-1).
- Gate the send **reuse fast-path** (block `:447-512`, guard `:447-451`) and **sticky short-circuit** (`:528-595`) behind an `isLocalPeer` check so a warmed relay/direct conn never bypasses a viable LAN path (RC2). **(COLLISION edit — lands on FDC-02's committed tree, after FDC-03.)** ⚠ **C1 / FDC-02 option A (2026-06-26):** FDC-02 already made this block **circuit-aware** (relay-only `/p2p-circuit` ⇒ enter the race). FDC-04 therefore adds **only the `isLocalPeer` predicate** (belt-and-suspenders for the **direct-conn** case — a direct conn to a LAN-visible peer should also defer to the LAN leg); it does NOT re-implement the relay-only carve-out. The predicates are complementary (connection-type vs peer-locality).
- Call sites firing `warmPeer`: **conversation-open** (`conversation_wired.dart` `initState` `:498-563`), **notif-tap conversation route** (`prepare_notification_open_use_case.dart` conversation case `:28-44`, plumbed via `prepare_notification_route_target_use_case.dart`), **resume** (`handle_app_resumed.dart:130-191`, the **active conversation peer**, bounded — PS-4, fired in **parallel**, not serialized behind the awaited drain).
- NEW network-change re-warm: an **injectable** `Stream<void>` signal (default empty) → on event, reset the active peer's cooldown, drop its learned `local` transport, and re-fire `warmPeer` preferring QUIC.

**Out of scope → owning FDC-xx:**
- The staggered ranked race / per-leg budgets **and the circuit-aware reuse carve-out** → **FDC-02** (C1 / option A). FDC-04 only adds the `isLocalPeer` reuse gate on top; it does **not** rewrite the race body or re-implement the relay-only carve-out.
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
- `lib/core/services/p2p_service_impl.dart` — `warmBackground :596-676`, `dialPeer :2120-2180` (account-gate `'p2p_dial_peer'` at `:2126`), `isConnectedToPeer :4135`, `isLocalPeer :4140`, `lastKnownGoodTransport :4144-4166` (`clock.now()` `:4149`, learned-`'local'` LAN-revalidation `:4161`), `recordSuccessfulTransport :4168-4173`, `discoverLocalPeer :4176-4187`. New: `warmPeer`, `_warmAttempts` map, `onNetworkChanged`. **NB: the `p2p_service_impl.dart` line anchors here are `new-orbit` working-tree-relative and the 4000-block has drifted ~+44 lines across drafts — re-locate every impl anchor by symbol after rebasing on the FDC-03 tree; do not trust the digits.**

**Production — send path (COLLISION):**
- `lib/features/conversation/application/send_chat_message_use_case.dart` — reuse `:447-512`, sticky `:528-595`, `isLocalPeer` read `:516`. ⚠ **FDC-02 (option A) already modified the reuse block (circuit-aware carve-out)** — re-locate the guard by symbol on FDC-02's committed tree; the digits will have drifted.

**Production — call sites:**
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — `initState :498-563` (warm on open), already holds `widget.p2pService`.
- `lib/features/push/application/prepare_notification_open_use_case.dart` `:21-72` + `prepare_notification_route_target_use_case.dart :15-29` (notif-tap warm hook, NEW optional injected `warmPeer` fn). **NB: `prepareNotificationRouteTarget` carries `bridge`/`selfPeerId` only — NO `P2PService` access today; the real `warmPeer` must be added as a param to BOTH use-cases and supplied from the `main.dart` wiring site, not "plumbed from an existing p2p handle".**
- `lib/core/lifecycle/handle_app_resumed.dart` — `handleAppResumed` signature `:37-76` (NO active-peer param today — one must be ADDED), `performImmediateHealthCheck()` `:175`, `await drainOfflineInbox()` `:206`. Place the unawaited `warmPeer` **after `:175`** (node confirmed started, PS-3) and **before the awaited drain at `:206`** so it runs parallel to the drain, not serialized behind it.
- `lib/main.dart` — the TWO actual warm-wiring edit sites: `_prepareNotificationRouteTarget` invocation `:4227` (pass `warmPeer: widget.p2pService.warmPeer`) and `_onResumed` → `handleAppResumed(...)` call `:4388` (thread the active-peer source / `conversationTracker`). *(Context only, NOT edited by Steps 9–14: `ConversationWired(...)` constructions `:3312`/`:4140`, conversation notif-route case `:4036-4075`, `_onPaused :4336`, `didChangeAppLifecycleState :4292`.)*

**Direct + integration tests (where RED tests land):**
- `test/core/services/p2p_service_impl_test.dart` (1to1 array `:48`) — TC-04-01..08 + TC-04-16.
- `test/features/conversation/application/send_chat_message_use_case_test.dart` (1to1 `:36`) — TC-04-12/13/14.
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` (1to1 `:63`) — TC-04-09.
- `test/features/push/application/prepare_notification_open_use_case_test.dart` (1to1 `:66`) — TC-04-10.
- NEW `test/features/push/application/prepare_notification_route_target_use_case_test.dart` — TC-04-10b (forward-wiring lock); register in `ONE_TO_ONE_TESTS`.
- NEW `test/core/lifecycle/handle_app_resumed_warm_peer_test.dart` — TC-04-11; register in `ONE_TO_ONE_TESTS`.
- NEW `integration_test/warm_peer_lan_aware_smoke_test.dart` — TC-04-15; register in `TRANSPORT_TESTS` + sims `classify_path()`.

**Dependency-only context:**
- `lib/core/local_discovery/{local_p2p_service,local_discovery_service}.dart` — `discoverLocalPeer`, `isLocalPeer` LAN-map source.
- `test/core/services/p2p_service_learned_transport_invalidation_test.dart` — the existing `lastKnownGoodTransport` invalidation locks the network-change drop must not regress.

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
| `handle_app_resumed_warm_peer_test.dart` | **MISSING (create)** | add to `ONE_TO_ONE_TESTS` | Resume warm-peer lock (TC-04-11). |
| `prepare_notification_route_target_use_case_test.dart` | **MISSING (create)** | add to `ONE_TO_ONE_TESTS` | Notif-tap warm **forward-wiring** lock (TC-04-10b) — proves the optional hook isn't a dead wire. |
| `warm_peer_lan_aware_smoke_test.dart` | **MISSING (create)** | add to `TRANSPORT_TESTS` | Host-fake LAN-aware overlap smoke (host-green ≠ validated; device-proof below). |

---

## RED Test Catalog

> Tier legend: **U** = unit/application (pure Dart, fakes); **W** = widget (call-site fires warmPeer); **I** = integration (transport gate, host-fake). Each warm path emits a distinct flow-event so a shared "no-op" result is discriminated by *which* event fired.

### U — `warmPeer` core (`test/core/services/p2p_service_impl_test.dart`)

**TC-04-01 ::  warmPeer AWAITS the LAN seed first, then re-evaluates isLocalPeer to gate the speculative dial (DESIGN-1)**
- Tier U. Setup: started `P2PServiceImpl` with a fake bridge + a fake `LocalP2PService` recording `discoverLocalPeer` calls. Two sub-scenarios: **(a)** the peer stays non-LAN after the seed → dial fires; **(b)** the seed makes the peer LAN-visible — the common **cold-LAN-map warm-open**: a same-WiFi contact not messaged this session, so `isLocalPeer` reads false at warm-start and flips true only AFTER the awaited seed. Call `warmPeer(peer)`.
- RED-on-HEAD: `warmPeer` does not exist → compile/`NoSuchMethod`.
- GREEN-asserts: `discoverLocalPeer(peer, timeout: warmLanTimeout)` is invoked **and awaited BEFORE** the `isLocalPeer` re-read that gates the dial; in **(a)** `callP2PPeerDial`/`dialPeer(peer)` fires; in **(b)** the dial is **skipped** (`…_DIAL_SKIPPED {reason:'is_local'}`). Emits `P2P_SERVICE_WARM_PEER_BEGIN` → `…_LAN_SEED` → then either `…_DIAL` or `…_DIAL_SKIPPED`.
- **Why await-first, not parallel:** evaluating `isLocalPeer` at warm-START (the prior `Future.wait([lan, dial])` shape) speculative-dials every same-WiFi peer whose LAN entry isn't seeded yet — landing a wasteful `/p2p-circuit` relay conn and accruing relay backoff. (The send-path reuse gate of RC2/TC-04-12 is the *correctness* backstop — a warmed relay conn won't be reused for a LAN-visible peer — but awaiting the bounded seed first avoids the wasteful dial/conn churn and makes INV-1 real rather than textual.) Tradeoff: a genuinely-remote peer's dial is delayed by ≤ `warmLanTimeout`; acceptable because `discoverLocalPeer` returns as soon as the peer is found and warm overlaps reading/typing anyway.
- Mutation A (ordering): evaluate `isLocalPeer` BEFORE awaiting the seed → scenario (b) speculative-dials a now-LAN peer → re-red.
- Mutation B (LAN-seed present): drop the `discoverLocalPeer` call entirely → scenario (b) never flips local → re-red (LAN never seeded).
- Mutation C (dial-leg present): drop the speculative `dialPeer` from warmPeer → scenario (a) re-reds (no dial).
- Discriminator: `P2P_SERVICE_WARM_PEER_LAN_SEED` distinguishes the LAN leg from the dial leg.

**TC-04-02 ::  warmPeer skips the speculative dial when isLocalPeer is already true (LAN-only)**
- Tier U. Setup: `isLocalPeer→true`. Call `warmPeer(peer)`.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: `discoverLocalPeer` fires; `dialPeer` **not** called; emits `P2P_SERVICE_WARM_PEER_DIAL_SKIPPED {reason:'is_local'}`.
- Mutation: remove the `if (!isLocalPeer)` guard around the dial → dial fires for a local peer → re-red.

**TC-04-03 ::  warmPeer is debounced — both SEQUENTIAL (post-dial) and CONCURRENT (in-flight) repeats collapse to one dial (DESIGN-4)**
- Tier U. Setup: `withClock`; `isLocalPeer→false`. Two sub-scenarios: **(a) sequential** — dial fails (offline); call `warmPeer(peer)`, let the dial resolve, call again within `warmCooldownFloor`. **(b) concurrent burst** — the dial future hangs (not yet resolved); fire two `unawaited(warmPeer(peer))` in the SAME synchronous tick (models conv-open + notif-tap + resume all firing on one warm-open).
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: in BOTH (a) and (b) `dialPeer` is invoked **exactly once**; the second call emits `P2P_SERVICE_WARM_PEER_DEBOUNCED`. **(b) requires an in-flight sentinel recorded SYNCHRONOUSLY at warmPeer entry, BEFORE the first await** — a cooldown set only *after* the dial resolves does not collapse a same-tick burst (libp2p same-peer dial coalescing would mask it on the wire, but the Dart-level debounce headline — the plan's value prop — must hold).
- Mutation A (sequential): remove the `recentlyWarmed` early-return → second sequential dial fires → re-red.
- Mutation B (concurrent): move the in-flight sentinel set to AFTER the dial completes (post-await) → scenario (b) fires two dials → re-red.

**TC-04-04 ::  per-PEER Dart warm-cooldown escalates on repeated failing dials (5s→…), layered over libp2p's Go-owned per-`(peer,transport)` swarm backoff (CONSIST-1)**
- Tier U. Setup: `withClock`; dial keeps failing. Call `warmPeer`, advance clock past floor, call again (fails again), advance again.
- RED-on-HEAD: no `warmPeer`.
- GREEN-asserts: the `nextEligibleAt` interval **grows** between consecutive failures (floor→2×→… capped at `warmCooldownCeil`); a call before `nextEligibleAt` is `…_DEBOUNCED`, a call after re-dials.
- **Keying honesty (CONSIST-1):** warmPeer fires a single **transport-agnostic** `dialPeer(peerId)` (Dart cannot know which transport libp2p chose), so the Dart cooldown is keyed by **peerId only**. The proposal's per-`(peerId,transport)` *quadratic* backoff (5s→5min) is **libp2p-swarm-internal (Go-owned) and unchanged by this plan**; the Dart per-peer cooldown is a thin debounce *layered over* it, not a reimplementation. (There is no separate "LAN-leg cooldown" — drop that framing.)
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

**TC-04-07 ::  network-change re-warms ONLY the active peer, resets its cooldown, and drops its learned `local` transport (MUT-1, DESIGN-3)**
- Tier U. Setup: started service with an injected `networkChangeSignal` `StreamController` **and an injected single active-peer source** (`String? Function()` / `ActiveConversationTracker.activePeerId`) returning `peerA`; `recordSuccessfulTransport(peerA,'local')`; warm `peerA` once (cooldown now active); ALSO warm a second `peerB` earlier this session (so `_warmAttempts` holds both) but leave `peerA` the active peer. Push one event on `networkChangeSignal`.
- RED-on-HEAD: no `warmPeer`/`onNetworkChanged`.
- GREEN-asserts: after the event `dialPeer`/`discoverLocalPeer` fires **again for `peerA` despite the live cooldown**; **`peerB` (warmed but no longer active) is NOT re-warmed** (PS-4 — the re-warm targets the active-peer source, never `_warmAttempts.keys`); `lastKnownGoodTransport(peerA)` returns null (the `local` entry was dropped); emits `P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM`.
- Mutation A (cooldown reset): make `onNetworkChanged` skip the cooldown reset → no re-warm within cooldown → re-red.
- Mutation B (drop-local): remove the `_learnedTransport.remove(peerA)` / `=='local'` drop → the `lastKnownGoodTransport(peerA)==null` assertion re-reds.
- Mutation C (active-only bound): target `_warmAttempts.keys` instead of the active-peer source → `peerB` re-warmed → the "peerB NOT re-warmed" assertion re-reds (PS-4 roster guard).
- Discriminator: `…_NETWORK_CHANGE_REWARM` vs the plain `…_BEGIN` proves the re-warm came from the network edge, not a fresh open.

**TC-04-16 ::  rapid network-change flapping is coalesced — N events within one cooldown window produce ONE re-warm, and escalation is preserved (DESIGN-2)**
- Tier U. Setup: `withClock`; active peer `peerA`, dial keeps failing (unreachable / QUIC down). Push N (`>=3`) events on `networkChangeSignal` within `warmCooldownFloor`.
- RED-on-HEAD: no `onNetworkChanged`.
- GREEN-asserts: `dialPeer` fires **once** across the burst — the network-change path enforces its own minimum re-warm interval (`>= warmCooldownFloor`, keyed on a `lastNetworkRewarmAt` timestamp distinct from the per-peer cooldown); the per-peer backoff **multiplier is preserved** (`onNetworkChanged` resets only `nextEligibleAt` to floor to permit an immediate first re-warm, NOT the escalation counter), so a still-failing peer keeps escalating. WiFi↔cellular flapping (elevators/transit) therefore cannot tight-loop a failing QUIC dial and trip the libp2p 5s→5m swarm backoff — the exact §6.1/§10 degradation the plan exists to prevent.
- Mutation A: drop the network-change self-debounce (`lastNetworkRewarmAt`) → N dials → re-red.
- Mutation B: reset the escalation multiplier (not just `nextEligibleAt`) on every event → the "still-escalating after a flap" assertion re-reds.

**TC-04-08 ::  network-change re-warm threads the (Dart-side) `preferQuic` intent flag to `callP2PPeerDial` — INERT on the wire until a Go change (DESIGN-5)**
- Tier U. Setup: as TC-04-07. Inspect the `dialPeer` invocation on the network-change re-warm.
- RED-on-HEAD: no `warmPeer`; `dialPeer` has no preference param.
- GREEN-asserts: the re-warm dial passes the new additive `preferQuic: true` and `callP2PPeerDial` receives it in the Dart payload.
- Mutation: drop the `preferQuic` flag on the network-change dial → re-red.
- **Honesty (DESIGN-5, verified):** the Dart `preferQuic` flag is **INERT on the wire today**. The Go `peer:dial` handler unmarshals only `{PeerId, Addresses, TimeoutMs}` and calls `DialPeerWithTimeout(peerId, addresses, timeoutMs)` (`bridge.go:962-973`); Go's `json.Unmarshal` **silently drops** an unknown `preferQuic` field, and `callP2PPeerDial` (`p2p_bridge_client.dart:361-378`) sends only `{peerId, addresses?, timeoutMs?}`. So this TC locks only that the *Dart intent is threaded*, NOT any transport effect. The **actual QUIC-first selection requires a Go change** (add `PreferQuic` to the struct + extend `DialPeerWithTimeout` + QUIC-first address ordering in `node.go`) and is **REASSIGNED to a Go-touching follow-up (FDC-11/FDC-12), OUT of FDC-04 scope** — see Accepted Differences. The QUIC device-proof done-criterion moves with it; **FDC-04 does NOT claim a QUIC win**, only that a network change triggers a plain re-warm carrying the (currently inert) intent flag.

### W — call sites

**TC-04-09 ::  opening the conversation screen fires warmPeer(contact.peerId) once (`conversation_wired_test.dart`)**
- Tier W. Setup: pump `ConversationWired` with a fake `P2PService` recording `warmPeer` calls.
- RED-on-HEAD: `initState` (`:498-563`) never calls `warmPeer`.
- GREEN-asserts: exactly **one** `warmPeer(contact.peerId)` after first frame; not awaited (fire-and-forget).
- Mutation: remove the `warmPeer` call from `initState` → re-red.

**TC-04-10 ::  notif-tap conversation route fires warmPeer for the target peer (`prepare_notification_open_use_case_test.dart`)**
- Tier W/U (application). Setup: call `prepareNotificationOpen` with a `conversation` route target carrying a non-null `peerId` + an injected `warmPeer` spy.
- RED-on-HEAD: `prepareNotificationOpen` has no warm hook (only `drainOfflineInbox`).
- GREEN-asserts: `warmPeer(routeTarget.peerId!)` invoked once for the `conversation` case; **not** for `group`/`intros`/`contactRequest`/`post` cases. (`NotificationRouteTarget.peerId` is `String?`; the `.conversation` constructor guarantees non-null, so the call uses `peerId!` — mirrors existing `main.dart` `routeTarget.peerId!` usage at `:4062`.)
- Mutation: remove the warm hook from the `conversation` case → re-red.
- Honesty: on a **cold** notif-tap the service-level PS-3 gate (TC-04-05) makes the warm a no-op; this lock only proves the *hook fires*, the win is warm-resume.

**TC-04-10b ::  the notif-tap warm hook is actually WIRED through `prepareNotificationRouteTarget` — not a dead optional param (`prepare_notification_route_target_use_case_test.dart`) (WIRE-1)**
- Tier U (application). Setup: call the production wrapper `prepareNotificationRouteTarget` with a `conversation` route target and a `warmPeer` recorder threaded through it. Because the hook is an **optional param defaulting null** (TC-04-10), a null/dead wire at the route-target seam OR at `main.dart:4227` passes TC-04-10 green while notif-tap warm silently never fires in production — exactly the host false-positive class flagged for TC-04-15.
- RED-on-HEAD: `prepareNotificationRouteTarget` has no `warmPeer` param to forward (it carries `bridge`/`selfPeerId` only — no `P2PService`).
- GREEN-asserts: a non-null `warmPeer` supplied to `prepareNotificationRouteTarget` is forwarded to `prepareNotificationOpen` and fires for the `conversation` case.
- Mutation: drop the forward (stop passing `warmPeer` from `prepareNotificationRouteTarget` into `prepareNotificationOpen`) → re-red.
- Source-wiring lock: the `main.dart:4227` supply of `warmPeer: widget.p2pService.warmPeer` is verified by inspection (Step 12) — there is no host seam above `_prepareNotificationRouteTarget`.

**TC-04-11 ::  resume warms the active conversation peer (and ONLY it), bounded and in parallel (`handle_app_resumed_warm_peer_test.dart`, NEW) (DESIGN-3/SRC-1)**
- Tier U. Setup: call `handleAppResumed` with a fake `P2PService` recording `warmPeer` and a **NEW injected active-peer source**. *(Today `handleAppResumed` has NO active-peer/`conversationTracker` param, and `ActiveConversationTracker` exposes NO active-peer getter — only `setActive`/`isViewing`. Step 14 must ADD both: `String? get activePeerId` on the tracker and an active-peer param on `handleAppResumed`, threaded from `main.dart:4388`.)* Two sub-cases: **(a)** the active-peer source returns one `peerA` with a roster of many contacts; **(b)** the active-peer source returns null (no conversation open).
- RED-on-HEAD: resume flow never warms a peer; `handleAppResumed` has no active-peer param to read.
- GREEN-asserts: **(a)** `warmPeer(peerA)` invoked exactly once; **roster peers are NOT warmed** (PS-4); the warm is **`unawaited`**, placed after `performImmediateHealthCheck()` (`:175`) and before the awaited `drainOfflineInbox()` (`:206`) so it runs parallel to the drain and does not increase drain latency. **(b)** active peer null → **no** `warmPeer` fires.
- Mutation A (roster bound): change resume to warm `for (c in roster) warmPeer(c)` → "roster not warmed" re-reds.
- Mutation B (null guard): warm unconditionally even when the active-peer source is null → sub-case (b) re-reds.

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

**TC-04-14 ::  PS-2 preservation — a NON-local connected peer with a DIRECT conn still takes the reuse fast-path (no regression)**
- Tier U. Setup: `isLocalPeer(target)→false`; `connections` contains `target` **via a DIRECT (non-`/p2p-circuit`) multiaddr** (e.g. `/ip4/.../tcp/4001`, NOT a relay circuit); reuse send succeeds. ⚠ **C1 / FDC-02 option A:** do NOT seed a relay-only `/p2p-circuit` conn here — under FDC-02 a relay-only conn now enters the race, so a circuit-seeded setup would (correctly) NOT reuse and this preservation test would mis-fire. PS-2 preserves the **direct-conn** reuse path only.
- RED-on-HEAD: passes today (preservation) — written to FAIL if the new gate over-fires (i.e. if the gate accidentally blocks non-local **direct** reuse).
- GREEN-asserts: `CHAT_MSG_SEND_REUSE_CONNECTION` emitted; `sendPath=='reuse'`; transport unchanged vs HEAD.
- Mutation: broaden the gate to `if (!isAlreadyConnected || isLocalPeer)`-style over-block → non-local direct reuse skipped → re-red. (Locks the gate is **LAN-only**, not a blanket reuse disable.)

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
| warmPeer awaits LAN seed, THEN gates dial | RC1, §6.1, DESIGN-1 | U | `p2p_service_impl_test.dart::TC-04-01` | no `warmPeer` method | A: eval isLocalPeer before seed; B: drop `discoverLocalPeer`; C: drop dial | `run_test_gates.sh 1to1` | already in `ONE_TO_ONE_TESTS:48` |
| skip dial when isLocalPeer | §6.1 | U | `p2p_service_impl_test.dart::TC-04-02` | no `warmPeer` | remove `if(!isLocalPeer)` | `1to1` | `:48` |
| debounce within cooldown | RC3 | U | `p2p_service_impl_test.dart::TC-04-03` | no `warmPeer` | remove `recentlyWarmed` early-return | `1to1` | `:48` |
| backoff escalates 5s→ceil | RC3, §12 | U | `p2p_service_impl_test.dart::TC-04-04` | no `warmPeer` | fixed (non-growing) cooldown | `1to1` | `:48` |
| no-op when node not started | PS-3, FDC-S5 | U | `p2p_service_impl_test.dart::TC-04-05` | no `warmPeer` | drop `isStarted` gate | `1to1` | `:48` |
| never sends / inboxes | PS-1 | U | `p2p_service_impl_test.dart::TC-04-06` | no `warmPeer` | add stray `sendMessageWithReply` | `1to1` | `:48` |
| network-change re-warm: active-only + reset + drop local | RC4, §12, MUT-1, DESIGN-3 | U | `p2p_service_impl_test.dart::TC-04-07` | no `onNetworkChanged` | A: skip cooldown reset; B: skip local-drop; C: target `_warmAttempts.keys` | `1to1` | `:48` |
| network-change threads (Go-inert) preferQuic flag | §12, DESIGN-5 | U | `p2p_service_impl_test.dart::TC-04-08` | no preferQuic param | drop `preferQuic` flag | `1to1` | `:48` |
| network-change flap coalesced to ONE re-warm | DESIGN-2 | U | `p2p_service_impl_test.dart::TC-04-16` | no `onNetworkChanged` | A: drop self-debounce; B: reset escalation multiplier | `1to1` | `:48` |
| conv-open fires warmPeer | call site | W | `conversation_wired_test.dart::TC-04-09` | initState no warm | remove initState warm | `1to1` | `ONE_TO_ONE_TESTS:63` |
| notif-tap fires warmPeer (conversation only) | call site | W/U | `prepare_notification_open_use_case_test.dart::TC-04-10` | no warm hook | remove conversation-case hook | `1to1` | `:66` |
| notif-tap warm hook WIRED through route-target (not dead) | WIRE-1 | U | `prepare_notification_route_target_use_case_test.dart::TC-04-10b` | no `warmPeer` param to forward | drop the forward to `prepareNotificationOpen` | `1to1` | **NEW file → ADD to `ONE_TO_ONE_TESTS`** |
| resume warms active peer (and ONLY it), bounded/parallel | PS-4, call site, DESIGN-3 | U | `handle_app_resumed_warm_peer_test.dart::TC-04-11` | resume no warm; no active-peer param | A: warm whole roster; B: warm when active==null | `1to1` | **ADD to `ONE_TO_ONE_TESTS`** |
| local peer + relay conn → no reuse, LAN attempted | RC2, §6.1 | U | `send_chat_message_use_case_test.dart::TC-04-12` | reuse LAN-blind `:447-451` | remove `&& !isLocalPeer` | `1to1` | `ONE_TO_ONE_TESTS:36` |
| local peer + learned relay → no sticky | RC2 | U | `send_chat_message_use_case_test.dart::TC-04-13` | sticky LAN-blind `:528-595` | remove isLocalPeer sticky gate | `1to1` | `:36` |
| non-local connected **via DIRECT conn** → reuse preserved | PS-2 | U | `send_chat_message_use_case_test.dart::TC-04-14` | (preservation) over-block | broaden gate to block non-local direct | `1to1` | `:36` |
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

- **INV-1** `warmPeer` **awaits** the bounded LAN seed (`discoverLocalPeer`) and re-reads `isLocalPeer` **before** deciding the speculative dial, so a same-WiFi peer is never needlessly relay-dialed and the LAN lane can win the FDC-02 ranked race (TC-04-01). The send-path reuse gate (INV-2) is the *correctness* backstop; this ordering is the *efficiency/churn* guard that makes the LAN-first intent real, not textual.
- **INV-2** A warmed **relay/direct** connection never satisfies the send reuse/sticky short-circuit when the peer is LAN-visible (TC-04-12/13); non-local **direct** reuse is unchanged (TC-04-14). (A non-local **relay-only** conn is handled upstream by FDC-02's circuit-aware reuse — C1 / option A — not by this `isLocalPeer` gate.)
- **INV-3** `warmPeer` is single-shot/debounced per **peerId** in Dart (in-flight sentinel for same-tick bursts + post-dial escalating cooldown), layered over libp2p's Go-owned per-`(peerId,transport)` swarm backoff — repeated **and concurrent** warms to an offline peer never tight-loop a failing dial (TC-04-03/04).
- **INV-4** `warmPeer` is a strict no-op while the node is not started (PS-3, TC-04-05) — never contends for the `Node.Start` write lock; cold-tap warming is honestly empty.
- **INV-5** `warmPeer` never sends or inboxes (PS-1, TC-04-06) — speculative only.
- **INV-6** A network change re-warms **only the active peer** (never `_warmAttempts.keys`), resets its `nextEligibleAt` (preserving the escalation counter), drops its learned `local` transport, **coalesces flap-bursts to one re-warm**, and threads a (currently Go-inert) `preferQuic` intent flag (TC-04-07/08/16).
- **INV-7** Warm is bounded to the open/active peer, never the roster (PS-4, TC-04-11).

---

## Step-By-Step Implementation Plan

> RED first for every step. Land **on top of FDC-03's committed tree** (collision file). Each behavior-bearing edit names its seam.

1. **RED:** add TC-04-05 (PS-3 no-op) and TC-04-06 (PS-1 no-send) to `p2p_service_impl_test.dart`. Both fail to compile (no `warmPeer`). *Seam:* `P2PService.warmPeer`.
2. **GREEN (skeleton):** add `Future<void> warmPeer(String peerId, {bool preferQuic = false})` to `lib/core/services/p2p_service.dart` as an abstract **default no-op** (so all fakes/mocks compile unchanged — mirror the `discoverLocalPeer` default at `:194`). Implement in `p2p_service_impl.dart` with the **whole body wrapped in a top-level `try/catch` that completes normally** — `warmPeer` is a **total, never-throwing** contract (ROBUST-1): all 4 call sites fire it as bare `unawaited(...)` with no error handler, so any throw from the gate/emit/`_warmAttempts` body would otherwise leak as an unhandled async error (test-zone failure / prod `PlatformDispatcher.onError`). First lines: `if (!currentState.isStarted) { emit …SKIPPED not_started; return; }` then `if (!await _allowsAccountNetworkSideEffects('p2p_warm_peer')) return;`. No dial yet. TC-04-05/06 green. *Note:* the `'p2p_warm_peer'` account-gate mirrors `dialPeer`'s existing `'p2p_dial_peer'` gate (`:2126`) — a non-behavioral reuse of the established pattern, exercised transitively (denied gate ⇒ no dial/seed, same observable as PS-3), so it carries no independent TC (GATE-1).
3. **RED:** TC-04-01 (LAN-seed + dial) and TC-04-02 (skip dial when local). *Seam:* warmPeer body.
4. **GREEN (await-seed-FIRST, then gate — DESIGN-1):** body = `final local = await discoverLocalPeer(peerId, timeout: warmLanTimeout).catchError((_) => false);` then `if (local || isLocalPeer(peerId)) { emit …_DIAL_SKIPPED {reason:'is_local'}; }` else fire the **non-blocking** dial: `unawaited(dialPeer(peerId, timeoutMs: warmDialTimeout.inMilliseconds, preferQuic: preferQuic).then(_onWarmDialOutcome).catchError(_onWarmDialError)); emit …_DIAL;`. Emit `…_BEGIN` at entry and `…_LAN_SEED` around the seed. Awaiting the bounded seed before deciding the dial avoids relay-dialing a same-WiFi peer whose LAN entry isn't seeded yet; the dial stays non-blocking so the call site is never delayed beyond `warmLanTimeout`. *Seam:* `warmPeer` + `dialPeer :2120` + `discoverLocalPeer :4176`.
5. **RED:** TC-04-03 (debounce) + TC-04-04 (backoff escalation). *Seam:* `_warmAttempts` map.
6. **GREEN:** add `final Map<String,_WarmAttempt> _warmAttempts` keyed by **peerId** (transport-agnostic — CONSIST-1; the per-`(peer,transport)` quadratic backoff is libp2p-swarm-internal, NOT reimplemented here). `_WarmAttempt` carries an **`inFlight` flag set SYNCHRONOUSLY at warmPeer entry, before the first await** (DESIGN-4), plus `nextEligibleAt` + the escalation count. `recentlyWarmed(peer)` early-returns `…_DEBOUNCED` if `inFlight` **or** `clock.now() < nextEligibleAt` — so a same-tick conv-open+notif-tap+resume burst collapses to one dial, not just sequential repeats. On dial completion: success clears the entry; failure sets `nextEligibleAt = now + min(prev*2, warmCooldownCeil)` from `warmCooldownFloor` and bumps the escalation count; always clear `inFlight`. Use `clock.now()` (matches `lastKnownGoodTransport :4149`) so `withClock` drives it. *Stop-if (FDC-S1):* `warmCooldownFloor`/`Ceil`, `warmLanTimeout`, `warmDialTimeout` default to {5s, 5m, 1500ms (=`interactiveLocalBudget`), 4s (=`InteractiveDialTimeout`)} — swap to S1's measured values when S1 lands; record the assumption inline.
7. **RED:** TC-04-07 (network-change re-warm) + TC-04-08 (preferQuic). *Seam:* `onNetworkChanged` + injected `networkChangeSignal`.
8. **GREEN:** add a constructor-injected `Stream<void>? networkChangeSignal` (default null → empty) **and an injected single active-peer source** `String? Function()? activePeerId` (default null; in prod = `ActiveConversationTracker.activePeerId` from Step 14 — DESIGN-3). Subscribe to the signal in the start path; `void onNetworkChanged()` → resolve the **ONE** active peer via `activePeerId?.call()`; **null ⇒ no-op** (never iterate `_warmAttempts.keys` — PS-4). For that peer: self-debounce the signal (`if (clock.now() - _lastNetworkRewarmAt < warmCooldownFloor) return;` then set `_lastNetworkRewarmAt`) so WiFi↔cellular flapping coalesces to one re-warm (DESIGN-2); reset only `nextEligibleAt` to floor **preserving** the escalation count; drop `_learnedTransport[peer]` if `=='local'`; then `warmPeer(peer, preferQuic:true)`. Add additive `bool preferQuic=false` to `dialPeer` (and `callP2PPeerDial`); default false keeps every existing caller unchanged. **Honesty (DESIGN-5):** `preferQuic` is **Dart-only and INERT on the wire** — the Go `peer:dial` handler drops unknown JSON fields (`bridge.go:962-973`); the real QUIC-first ordering is a Go-touching follow-up (FDC-11/FDC-12), out of scope. Emit `…_NETWORK_CHANGE_REWARM`. *Stop-if:* the real OS connectivity source is a **bounded follow-up** — (a) add `connectivity_plus` and map `onConnectivityChanged` → the signal, or (b) a native `NWPathMonitor`/`ConnectivityManager` MethodChannel. This plan wires the *behavior* against the injectable stream; do NOT block FDC-04 on the source choice. Flag in Accepted Differences.
9. **RED:** TC-04-09 (conv-open). *Seam:* `conversation_wired.dart initState`.
10. **GREEN:** add `unawaited(widget.p2pService.warmPeer(widget.contact.peerId));` — fire-and-forget — **UNCONDITIONALLY at the end of `initState` (after the `:560-562` notif-tap-drain block), NOT inside the `if (widget.notificationTappedAt != null)` block** (CONV-6): TC-04-09 requires warm on **every** open, including a normal (non-notif) open. *Seam:* `conversation_wired.dart:498-563`.
11. **RED:** TC-04-10 (notif-tap). *Seam:* `prepareNotificationOpen` conversation case.
12. **GREEN:** add an optional `Future<void> Function(String peerId)? warmPeer` param to **BOTH** `prepareNotificationOpen` AND `prepareNotificationRouteTarget` (default null on each). In `prepareNotificationOpen`'s `conversation` case: `final pid = routeTarget.peerId; if (warmPeer != null && pid != null) unawaited(warmPeer(pid));` (NOTIF-5 — `peerId` is `String?`). `prepareNotificationRouteTarget` **forwards** its `warmPeer` to `prepareNotificationOpen` — it carries NO `P2PService` of its own (`bridge`/`selfPeerId` only — SRC-2). Supply the real fn at the only seam that holds p2p: `main.dart:4227` (`_prepareNotificationRouteTarget` → `prepareNotificationRouteTarget(..., warmPeer: widget.p2pService.warmPeer)`). *Seam:* `prepare_notification_open_use_case.dart:28-44` + `prepare_notification_route_target_use_case.dart:15-29` + `main.dart:4227`. Locked by TC-04-10 (hook) **and TC-04-10b (forward wiring)**.
13. **RED:** TC-04-11 (resume, bounded/parallel). *Seam:* `handle_app_resumed.dart`.
14. **GREEN (the active-peer source must be CREATED — DESIGN-3/SRC-1):** (a) add `String? get activePeerId => _activePeerId;` to `ActiveConversationTracker` (today it exposes only `setActive`/`clear`/`isViewing` — no read-back); (b) add an active-peer param to `handleAppResumed` (e.g. `String? Function()? activeConversationPeerId`, or pass the `ActiveConversationTracker`) — it has **no** such param today; (c) thread it at `main.dart:4388` (`widget.conversationTracker` is already in scope at that call site); (d) fire `unawaited(p2pService.warmPeer(activePeer))` for the resolved active peer **only** (PS-4), **null ⇒ no warm**, placed **after `performImmediateHealthCheck()` (`:175`, node confirmed started — PS-3) and before the awaited `drainOfflineInbox()` (`:206`)** so it runs parallel to the drain, never serialized behind it. *Seam:* `handle_app_resumed.dart` signature `:37-76` + body `:175-206`; `active_conversation_tracker.dart`; `main.dart:4388`. *Stop-if:* if **FDC-05** (parallel resume re-prime) already restructured the resume block, slot the `warmPeer` call into FDC-05's parallel set — do NOT re-serialize. Pin order with FDC-05 (recommend FDC-05 first; see Dependency Impact).
15. **RED:** TC-04-12/13 (reuse/sticky `isLocalPeer` gate, red-on-HEAD); write **TC-04-14 green-on-HEAD as a preservation lock** — it does NOT red on HEAD, only under its broaden-gate mutation (RED-1). *Seam:* `send_chat_message_use_case.dart` reuse guard `:447-451` + sticky `:528-595`.
16. **GREEN (COLLISION edit):** hoist the `isLocalPeer` read **from `:516` to above the reuse guard at `:447-451`**; **AND the `isLocalPeer` predicate into the reuse condition that FDC-02/option A already made circuit-aware** → effectively `if (isAlreadyConnected && !isRelayOnlyCircuit && !isLocalPeer)` (re-locate FDC-02's exact circuit-aware condition by symbol and add `&& !isLocalPeer`); gate the sticky short-circuit so a non-`local` learned value does not short-circuit a LAN-visible peer (`if (learned != null && (learned == 'local' || !isLocalPeer))`). Preserve the existing `'local'` revalidation. **`CHAT_MSG_SEND_REUSE_CONNECTION`/`CHAT_MSG_SEND_STICKY_TRANSPORT` are EXISTING emits** (`:454`/`:530`) — the gate only changes the *condition guarding* them, it does not add emits (EVT-1). *Seam:* hoist `:516`→`:447`, reuse guard `:447-451`, sticky `:528-595`. *Stop-if (CONSIST-2 — UPDATED for C1/option A):* this reuse short-circuit (`:447-451`) fires **before** FDC-02's ranked race (`:514+`). ⚠ **Under C1/option A, FDC-02 ALREADY modified this short-circuit** to be circuit-aware (a relay-only `/p2p-circuit` conn now falls into the race), so FDC-04 lands on a tree where relay-only conns already bypass reuse; FDC-04 adds **only the `isLocalPeer` predicate** for the **direct-conn-to-a-LAN-peer** case. Confirm FDC-02's circuit-aware condition is present before adding `&& !isLocalPeer`; the `isLocalPeer` gate is the only FDC-04 change here. (The earlier "FDC-02 rewrites only the race body, not this short-circuit" framing is **superseded by option A**.)
17. **RED:** TC-04-15 (transport smoke). *Seam:* new `integration_test/warm_peer_lan_aware_smoke_test.dart`.
18. **GREEN + register:** author the smoke; append it to `TRANSPORT_TESTS` in `scripts/run_test_gates.sh` and add a **`classify_path()` rule** in `scripts/check_reliability_simulation_discovery.sh` (e.g. `record "1to1" "$path" "test" "1:1 warm-peer LAN-aware transport smoke"`) so the auto-discovered file is classified — otherwise `discover_candidates` falls through to `record "unclassified"` and the discovery check FAILs. *(No `--dart-define` here — that dispatch lives only in `run_test_gates.sh`, not in `check_reliability_simulation_discovery.sh`, whose `classify_path()` is a plain `case`/`record` matcher — HG-2.)* Append `handle_app_resumed_warm_peer_test.dart` to `ONE_TO_ONE_TESTS`.
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
| preferQuic mis-asserted as a real QUIC win | TC-04-08 = Dart-intent only; INERT on the wire (Go drops the field) → QUIC win reassigned to FDC-11/12 (DESIGN-5) |
| Concurrent conv-open+notif-tap+resume burst fires duplicate dials | TC-04-03(b) — synchronous in-flight sentinel (DESIGN-4) |
| WiFi↔cellular flapping tight-loops a failing QUIC re-warm | TC-04-16 — network-change self-debounce + escalation preserved (DESIGN-2) |
| Resume can't identify the active peer (no source today) | Step 14 adds `ActiveConversationTracker.activePeerId` + `handleAppResumed` param (TC-04-11 / DESIGN-3) |
| Notif-tap warm hook left a dead/null wire (passes host green) | TC-04-10b — forward-through-`prepareNotificationRouteTarget` lock (WIRE-1) |
| `warmPeer` body throws → unhandled async error at a bare `unawaited` site | Step 2 total/never-throws contract (ROBUST-1) |
| Host fake passes via dedup though LAN leg never fired | TC-04-15 honesty note + mandatory device-proof |
| Collision clobber of FDC-01/02/03 edits | land sequentially on FDC-03's committed tree; full `1to1` re-run |

---

## Device/Relay Proof Profile

**Host-logic closure only (NOT full plan closure):** TC-04-01..14 + TC-04-10b + TC-04-16 (warm core, gates, call sites, forward-wiring, flap-coalesce, reuse/sticky gate) close the *logic* in pure Dart against existing fakes — but **full plan closure requires the sim/device proof below** (the LAN-`local` win is not host-provable; `messageId` dedup can mask a dead LAN leg).

**Requires sim/device (NOT host-closable):**
- **TC-04-15 wire behavior** — host-green proves label-wiring + delivery only; `messageId` dedup can mask a dead LAN leg (roadmap host-test caveat). 
- **Closure scenario:** a real **two-device same-WiFi pair**: open the conversation (fires `warmPeer`), observe (via flow-events / transport label) that the subsequent send takes **`local`** and that a pre-existing relay conn did **not** bypass it; then toggle WiFi→cellular and confirm the **network-change re-warm fires** (the `…_NETWORK_CHANGE_REWARM` event emits and re-dials the active peer). **The actual QUIC-first transport selection is NOT validated here — it is reassigned to the Go-touching FDC-11/FDC-12 (DESIGN-5).** Run `./scripts/check_reliability_simulation_discovery.sh` then `/sims 1to1 --only N` (after adding the `classify_path()` case). Note: iOS sim shares a host mDNS stack → LAN-`local` validation is **device-only** (`e2e_test_mode.dart:2 kDisableLocalDiscovery`; proposal §6.5).
- **Cold notif-tap** — device-confirm the PS-3 no-op (warm empty before node-start); the cold win is FDC-07, gated FDC-S1.

---

## Acceptance Gates

```bash
# 1:1 home gate (warmPeer unit + reuse/sticky gate + call sites). Run on the FDC-03 tree.
./scripts/run_test_gates.sh 1to1            # expected: >= FDC-03-green baseline (~1226) + ~16 new warmPeer/gate/wiring TCs (≈1242). This is the regression FLOOR, NOT an exact match — count rises as TC-04-01..16 + TC-04-10b + handle_app_resumed_warm_peer land.

# transport gate (warm-overlap smoke joins TRANSPORT_TESTS)
./scripts/run_test_gates.sh transport       # expected: device/fixture-gated (skips on lone sim)

# feed regression floor
./scripts/run_test_gates.sh feed            # expected: 279 (FDC-S0/FDC-03 baseline floor; FDC-04 adds NO feed tests → unchanged)

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

No Go/relay changes in FDC-04: the `preferQuic` flag is a **Dart-only** param that the Go `peer:dial` handler silently drops (`bridge.go:962-973` unmarshals only `{PeerId,Addresses,TimeoutMs}`), so it is **inert on the wire** and needs no Go edit — the real QUIC-first ordering is reassigned to a Go-touching follow-up (FDC-11/FDC-12). Because FDC-04 plumbs no bridge param the Go suite is unaffected; if a future rebase DOES touch the bridge, run it under the declared toolchain — `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./...` (Go 1.26.x panics `crypto/tls bug: where's my session ticket?` — quic-go v0.49.0 vs Go 1.26 crypto/tls — a FAIL with zero `--- FAIL:` lines; the RC5 microbench row uses the same pin).

---

## Known-Failure Interpretation

- A `1to1` failure **only** in `send_chat_message_use_case_test.dart` reuse/sticky cases after step 16 = the collision rebase onto FDC-03 is off — re-diff against FDC-03's tree, not HEAD.
- `p2p_service_learned_transport_invalidation_test.dart` red = the network-change `local` drop changed TTL semantics it shouldn't — the drop must be an *additional* trigger, not a TTL edit.
- A `transport` smoke that passes only via the inbox copy (label `inbox`/`relay`, not `local`) = the host false-positive (dedup masking a dead LAN leg) — **not** a real green for the fast path; needs device-proof.
- Pre-existing flakes (durable-media-upload `ML-004`, ambient_background guard) are NOT FDC-04 — confirm by running the named test in isolation.

---

## Done Criteria

- [ ] `warmPeer` added (abstract default no-op + impl): **await-LAN-seed-first THEN gate dial**, isLocalPeer-skip-dial, **in-flight + escalating per-peer** debounce (collapses concurrent bursts), PS-3 not-started no-op, PS-1 never-send, **total/never-throws** (top-level try/catch).
- [ ] Reuse + sticky short-circuit gated behind `isLocalPeer` (RC2); non-local reuse preserved (PS-2).
- [ ] Call sites wired: conv-open (**unconditional**), notif-tap (conversation only, **forwarded through `prepareNotificationRouteTarget` + supplied at `main.dart:4227`**), resume (active peer via **NEW `ActiveConversationTracker.activePeerId` getter + new `handleAppResumed` param threaded at `main.dart:4388`**, bounded, parallel).
- [ ] Network-change re-warm: **active-peer-only** + reset `nextEligibleAt` (keep escalation) + drop learned `local` + **flap-coalesce** + thread the (Go-inert) `preferQuic` flag, against the injectable signal.
- [ ] TC-04-01..16 + TC-04-10b RED-first then GREEN; every behavior edit mutation-verified (re-red + revert).
- [ ] `handle_app_resumed_warm_peer_test.dart` + NEW `prepare_notification_route_target_use_case_test.dart` added to `ONE_TO_ONE_TESTS`; `warm_peer_lan_aware_smoke_test.dart` added to `TRANSPORT_TESTS` + sims `classify_path()`.
- [ ] All Acceptance Gates green on the FDC-03 tree; `flutter analyze` 0-new; `git diff --check` clean.
- [ ] Two-device same-WiFi smoke shows `local` on warm-open and the network-change re-warm fires on WiFi→cellular (device-proof, deferred-not-waived with FDC-S1). **The actual QUIC-pref transport win is NOT an FDC-04 done-criterion — it requires the Go change reassigned to FDC-11/FDC-12.**
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
- **preferQuic is INERT in FDC-04 (DESIGN-5)** — the Dart `preferQuic` flag is threaded to `callP2PPeerDial` and host-asserted (TC-04-08), but the Go `peer:dial` handler drops unknown JSON fields (`bridge.go:962-973`), so it has **zero wire effect** here. The actual QUIC-first transport selection (Go struct field + `DialPeerWithTimeout` param + `node.go` ordering) and its device-proof are **reassigned to a Go-touching follow-up (FDC-11/FDC-12)**. FDC-04 ships only the network-change-triggered plain re-warm carrying the intent flag.
- **Cold notif-tap warm is intentionally empty** (PS-3) — accepted; the cold win is FDC-07.

---

## Dependency Impact

- **Gated by FDC-S5** (advisory, honored as hard constraints): warm off the cold-start critical path (PS-3 node-started gate), bound to the open peer (PS-4), no Dart queue/second channel; the bridge is true-parallel in the warm state so the parallel `Future.wait([lan, dial])` is real concurrency.
- **Calibrated by FDC-S1**: the warm budget/cooldown constants (step 6) and the cold-tap aggressiveness verdict (PS-3) plug in S1's numbers; defaults conservative until then.
- **COLLISION (sequential, after FDC-03)**: `lib/features/conversation/application/send_chat_message_use_case.dart` — the reuse/sticky `isLocalPeer` gate. Land on FDC-03's committed tree per the FDC-00 collision rule (FDC-01→02→03→04).
- **Secondary collision** (different phases — serialize only if co-scheduled): `lib/core/services/p2p_service_impl.dart` with FDC-08 (presence-lookup cache). *(FDC-05 does NOT edit `p2p_service_impl.dart` — it reorders call sites in `handle_app_resumed.dart` + the test fake only.)*
- **Tertiary collision (real FDC-04↔FDC-05 overlap):** `lib/core/lifecycle/handle_app_resumed.dart` (`:130-191`) — this plan's resume `warmPeer` call-site (step 14) and FDC-05's un-serialization of that block touch the same region. **Land FDC-05 first** and slot the warm call into its parallel block; if FDC-04 lands first, rebase the resume call when FDC-05 restructures (see Step-14 stop-if).
- **Feeds**: FDC-02's ranked race **benefits from** INV-1 (LAN seeded first; FDC-02's local leg does its own `discoverLocalPeer`, so it benefits-from rather than requires the pre-seed). ⚠ **C1 / option A reconciliation:** FDC-02 made the reuse block **circuit-aware** (relay-only `/p2p-circuit` ⇒ race), so FDC-04's `isLocalPeer` reuse gate is **complementary, not redundant** — it covers the **direct-conn-to-a-LAN-visible-peer** case that FDC-02's connection-type carve-out does not. (The earlier framing that the gate is "redundant belt-and-suspenders" and that FDC-02 "rewrites only the race body, not this short-circuit" is **superseded by option A**.) A future ranking-only refinement MAY still drop the gate per proposal §6.2. FDC-07 owns the cold-start win this plan honestly defers. **preferQuic QUIC-first ordering is reassigned to FDC-11/FDC-12 (Go-touching).**
