# 183 - Active-chat keepalive: proactively probe the live 1:1 peer connection while a chat is open  (New Feature)

Status: IMPLEMENTED + DEVICE-PROVEN (2026-07-01) — TC-183-50 + TC-183-51 both PASS
on Pixel 6 → iPhone 11 (real `peer:ping` RTT 189 ms; drop detected at exactly 2×8 s
→ warmPeer+drain +1 ms, latched; 0 background pings). Cold-start-arming gap found +
fixed (initState arms keepalive+presence on resumed launch; TC-183-52 host lock) +
device-re-verified. See `183-keepalive-device-proof-runsheet.md`.
Spec: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-spec.md`

> **One-line:** add a foreground-only, active-1:1-peer-scoped liveness probe — a `Timer.periodic` (~8 s, well under the ~30 s QUIC idle) modeled verbatim on 181's `SetPresenceUseCase` — that pings the open-chat peer via a NEW `peer:ping` Go command (the node is ping-*responder*-only today), keeps the connection warm, and on M consecutive misses **reuses** the existing `warmPeer` + `drainOfflineInbox`. Host-floor proves the loop with a faked probe; a two-phone device-proof is the PROD-CRITICAL closure for the real ping.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-30 | Evidence Collector | node.go:287/381-404, p2p_service_impl.dart:2522/2659-2713/2020/3866/2711, main.dart:2215-2217/3644/4454/4512/4526, active_conversation_tracker.dart, set_presence_use_case.dart:37-67, p2p_bridge_client.dart (presence precedent), fake_p2p_service.dart | Confirmed post-182: Go ping responder-only; onNetworkChanged drains; main passes networkChangeSignal but NOT activePeerId; 181 template stable | hand to Planner |
| 2026-06-30 | Planner | tier-matrix.md, sufficiency-checklist.md, plan-template.md | New use case + capability iface + Go peer:ping; host floor + device-proof; reuse warmPeer/drain | emit matrix + plan |
| 2026-06-30 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-06-30 | Arbiter | this plan | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-01 | contract extraction | (git status --short) | pre-existing dirty (500ms exp, 181–184 docs) noted, NOT bundled | scope confirmed | RED |
| 2026-07-01 | RED tests added | 4 Dart + 1 Go test | `flutter test` → compile-fail (APIs absent); `go test ./bridge -run TestPeerPing` → `undefined: PeerPing` | RED for expected reason | impl |
| 2026-07-01 | implementation (Dart) | p2p_service.dart, p2p_service_impl.dart, p2p_bridge_client.dart, go_bridge_client.dart, active_peer_keepalive_use_case.dart, main.dart, GoBridge.swift/.kt | scoped files only — base `P2PService` untouched | scoped | Go |
| 2026-07-01 | implementation (Go peer:ping) | bridge_ping.go (new), node/ping.go (new) | `GOTOOLCHAIN=go1.25.0 go test ./bridge -run TestPeerPing` 3/3; `go build ./node ./bridge` clean | gomobile rebuild deferred to device-proof | GREEN |
| 2026-07-01 | direct GREEN | — | use-case+iface+bridge 20/20; wiring 5/5 | reds now green | preserve |
| 2026-07-01 | preservation GREEN | — | p2p_service_impl + handle_app_resumed 122/122 | sentinels green (warmPeer/182/30s intact) | gates |
| 2026-07-01 | named gates | run_test_gates.sh (+ONE_TO_ONE_TESTS) | core-host-all 272/272; completeness 1004/1004; 1to1 +1415/−9 (9 PRE-EXISTING, 0 ref 183); feature-host-all fakes compile | gate green (9 fails proven pre-existing) | review |
| 2026-07-01 | adversarial review | — | 5-dim verify-each workflow | 0 real findings in 183 code | device |
| 2026-07-01 | device-proof | runsheet (new) | (two-phone rig) | PENDING — needs make all/pod install | — |
| 2026-07-01 | QA (independent) | — | analyze 0-new; diff --check clean; graphs refreshed | blocking: none (183) | HOST-GREEN |

## Source Of Truth
- Spec / intent: `Test-Flight-Improv/183-active-chat-keepalive-foreground-peer-liveness-spec.md`
- Gate definitions: `scripts/run_test_gates.sh` → `scripts/run_host_test_gates.sh`
- Discovery/registration: `scripts/run_test_gates.sh completeness-check`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (reuses spec NN=183)

## Session Classification
implementation-ready (host floor fully host-testable with a faked probe + fakeAsync + a source-assertion wiring lock; the Go `peer:ping` real-ping leg + its drop-detection are the device-proof closure — PROD-CRITICAL, not host-fakeable).

## Exact Problem Statement

While a 1:1 conversation is open, the connection to that peer is kept warm only by a one-shot `warmPeer` (chat-open/resume/notif, `p2p_service_impl.dart:2522` — no periodic re-warm) and a dead connection is detected only **passively** — it lapses at the ~30 s quic-go idle default (no custom `MaxIdleTimeout`; `connmgr` grace 1 min `node.go:287`) and is noticed only on the next send or the 30 s relay-health poll (`:2711→:3866`). The libp2p ping protocol is **responder-only** (`node.go:381-404`, no `ping.Ping` caller), so nothing app-level probes the active peer. Result: (1) the warm fast-send path silently decays mid-chat → sends fall back to cold-dial/relay/inbox; (2) a peer dropping with the sender's own network healthy is invisible for up to ~30 s.

**What must improve:** while foreground + in a 1:1 chat, actively probe that one peer on a short cadence — keep it warm and detect a drop in **seconds**, then re-dial (and let the existing drain catch up).

**What must stay unchanged (→ preserved-green sentinels):**
- The 30 s relay-health poll + its drain (`p2p_service_impl_test.dart` health-check group).
- 182's connectivity-restore drain + re-warm in `onNetworkChanged` (the 182 test).
- `warmPeer`'s one-shot triggers + escalating cooldown (`p2p_service_impl_test.dart` warmPeer group, `handle_app_resumed_warm_peer_test.dart`).
- The base `P2PService` interface (no new method → the ~31 fakes).

## Root Cause (verify → refute confirmed — re-verified post-182)
1. **No proactive liveness probe exists.** `node.go:381-404` enables ping by default but nothing calls `ping.Ping` (grep-empty in go-mknoon non-test). `warmPeer` is one-shot per trigger; the only periodic loops are the 30 s health poll and the 60 s presence heartbeat — neither pings the active 1:1 peer.
2. **`drainOfflineInbox` is the public reuse target** (`p2p_service_impl.dart:2020`/public entry), already called by 182's `onNetworkChanged` (`:2687`) and the 30 s poll (`:3866`).
3. **`activePeerId` is available in `main.dart` (`:4526`, from `conversationTracker`)** but NOT passed into `P2PServiceImpl` (the 182 comment at `:2215` defers it) — so the keepalive use case sources the active peer from the tracker directly.

**Refuted / do-NOT-re-introduce:**
- *"Reuse `onNetworkChanged`'s re-warm for drop-detection":* refuted — `onNetworkChanged` fires on the SENDER's OS network edge (182's `connectivityRestoredSignal`), not on the PEER's connection dying; and its re-warm half is dormant (`_activePeerId` null). The keepalive needs its own active-ping probe.
- *"Add `pingPeer` to base `P2PService`":* refuted — breaks the ~31 fakes (see [[reference_p2pservice_interface_addition_breaks_all_fakes]]); use a capability interface (181 `RelayPresenceSet` precedent).
- *"Background keepalive":* refuted — OS suspends background timers; foreground-only (181 parity).
- *"Build a new re-dial/drain":* refuted — `warmPeer` + `drainOfflineInbox` exist; reuse them.

## Real Scope
**In scope:**
1. **New Go bridge command `peer:ping`** — `go-mknoon/bridge/bridge_ping.go` `PeerPing(paramsJSON)` → node `PingPeer(peerId, timeout)` → `ping.Ping(ctx, host, peerId)` (first result), returning `{ok, rttMs}` or a typed failure. Native dispatch (`GoBridge.swift`/`.kt`) + Dart cmd-spec, modeled on the `relay:presence_set` chain.
2. **Capability interface** `PeerLivenessProbe { Future<bool> pingPeer(String peerId, {required int timeoutMs}); }` (`lib/core/services/p2p_service.dart`), implemented by `P2PServiceImpl` (`callP2PPeerPing` → `peer:ping`), **gated by `_allowsAccountNetworkSideEffects`** (returns false while a move paused network side-effects). NOT on base `P2PService`.
3. **New use case** `ActivePeerKeepAliveUseCase` (`lib/core/services/active_peer_keepalive_use_case.dart`), modeled verbatim on `SetPresenceUseCase`: a foreground `Timer.periodic(kKeepAliveInterval≈8s)`; each tick, if `activePeerId()` is a non-null non-`group:` peer, `probe.pingPeer(peer, timeoutMs)`; `kKeepAliveMissThreshold≈2` consecutive failures → `onDropReWarm(peer)` (= `warmPeer`) AND `onDropDrain()` (= `drainOfflineInbox`), then reset the miss count; a success resets the miss count; `onForegrounded()` arms, `onBackgrounded()` cancels, `dispose()` cancels.
4. **Lifecycle wiring in `_MyAppState`** (`lib/main.dart`): construct in `initState` (active peer from `widget.conversationTracker.activePeerId`, probe from `widget.p2pService`, callbacks `warmPeer`/`drainOfflineInbox`); `onForegrounded()` in `_onResumed` (`:4512` region), `onBackgrounded()` in `_onPaused` (`:4454` region), `dispose()` in `_MyAppState.dispose()`.

**Out of scope (owning work):**
- The OS connectivity source + connectivity-restore drain — **182 (implemented)**. 183 reuses `drainOfflineInbox`, never re-wires the source.
- The 30 s relay-health poll — unchanged backstop.
- Wiring `_activePeerId` into `P2PServiceImpl` (the 182 `:2215` follow-up) — not required (the use case scopes itself); do not entangle.
- Groups (pubsub liveness), the 2-tick UI (184), presence (181).

## Files To Inspect Next
- Production (new): `lib/core/services/active_peer_keepalive_use_case.dart`, `go-mknoon/bridge/bridge_ping.go`, node `PingPeer`.
- Production (edit): `lib/core/services/p2p_service.dart` (add `PeerLivenessProbe` iface), `lib/core/services/p2p_service_impl.dart` (`implements PeerLivenessProbe` + `pingPeer` + account-gate), `lib/core/bridge/p2p_bridge_client.dart` (`callP2PPeerPing`), `lib/core/bridge/go_bridge_client.dart` (cmd-spec), `ios/Runner/GoBridge.swift` + `android/.../GoBridge.kt` (native dispatch), `lib/main.dart` (wiring).
- Read-only (template / sentinels): `set_presence_use_case.dart`, `p2p_service_impl.dart:2659-2713` (182 onNetworkChanged), `active_conversation_tracker.dart`.

## Existing Tests Covering This Area
- `test/core/services/p2p_service_impl_test.dart` — warmPeer + onNetworkChanged + health-check groups (preservation sentinels).
- `test/core/lifecycle/handle_app_resumed_warm_peer_test.dart` — resume warm (sentinel).
- `test/core/services/fake_p2p_service.dart` — the ~31-fakes anchor (must NOT gain a method).
- `test/features/push/application/set_presence_use_case_test.dart` — the template's own suite (pattern reference).
- **MISSING (this plan fills):** the keepalive use-case loop; the `peer:ping` bridge command; the lifecycle-wiring lock; the capability-interface purity guard; the device-proof.

## RED Test Catalog  (add BEFORE production code — INV-RED-FIRST)

1. `test/core/services/active_peer_keepalive_use_case_test.dart`::**TC-183-01/02 — arms on foreground + probes on cadence**
   - Tier: unit (`fakeAsync`). Setup: fake `PeerLivenessProbe` (records `pingPeer` calls, returns true), `activePeerId` provider returns a 1:1 peer; `onForegrounded()`; `async.elapse(N*3)`.
   - RED on HEAD: the use case file does not exist → the test does not compile/run (the API is absent).
   - GREEN: exactly 3 `pingPeer(peer)` calls; `isProbeActive == true`.
   - Mutation: drop the `Timer.periodic` tick → 0 pings → red.

2. same::**TC-183-06/07 — M consecutive misses trigger ONE `warmPeer` + ONE `drainOfflineInbox`**
   - Setup: probe returns false; advance time past M intervals; record `onDropReWarm`/`onDropDrain`.
   - RED on HEAD: API absent.
   - GREEN: after M misses, `onDropReWarm(peer)` called once AND `onDropDrain()` once; the miss count resets.
   - Mutation: re-dial per-miss (no threshold) → >1 calls → red; OR remove the `onDropDrain` → drain count 0 → red.
   - **Discriminator:** assert a `KEEPALIVE_PEER_DROP` flow event fires AND it carries the active peerId (distinguishes a real drop-driven re-warm from `warmPeer`'s other one-shot triggers).

3. same::**TC-183-05 — success resets the miss count (no re-dial)**; **TC-183-08 — null/`group:` peer → zero pings**; **TC-183-09 — account-migration-gated probe → no re-dial spam**; **TC-183-10 — a thrown ping never propagates**; **TC-183-11 — rapid foreground↔background churn → one armed loop, bounded pings**; **TC-183-03 cancel on background**; **TC-183-04 cancel when `activePeerId` clears**; **TC-183-12 resume re-arms after pause** — all unit/`fakeAsync`, RED-on-HEAD because the API is absent; each mutation-verified by reverting the matching loop branch.

4. `test/core/lifecycle/main_keepalive_wiring_test.dart`::**TC-183-21 — `_MyAppState` constructs + arms/cancels/disposes the keepalive**
   - Tier: widget/host (source-assertion, TC-164/181 precedent — read `lib/main.dart` as a string).
   - RED on HEAD: `main.dart` contains no `ActivePeerKeepAliveUseCase` reference → `contains` false → red.
   - GREEN: constructed from `widget.p2pService` (probe) + `conversationTracker.activePeerId`; `onForegrounded()` in `_onResumed`, `onBackgrounded()` in `_onPaused`, `dispose()` in `dispose()`.
   - Mutation: remove any of the four wires → red.

5. `test/core/services/p2p_service_peer_liveness_test.dart`::**TC-183-20 — `pingPeer` is on the capability interface, NOT base `P2PService`; account-gated**
   - Tier: unit + structural. Setup: source-assert the `abstract interface class P2PService` block does NOT contain `pingPeer`, the `PeerLivenessProbe` block does; behavioral: `P2PServiceImpl.pingPeer` returns false (no throw) while `_allowsAccountNetworkSideEffects('p2p_peer_ping')` is paused.
   - RED on HEAD: `PeerLivenessProbe`/`pingPeer` absent → red.
   - GREEN: capability iface present + impl gated.
   - Mutation: move `pingPeer` onto base `P2PService` → the ~31 fakes fail to compile (locked also by a clean `core-host-all`/`feature-host-all` run, TC-183-22).

6. `test/core/bridge/p2p_bridge_client_ping_test.dart`::**TC-183-30 — `callP2PPeerPing` sends `peer:ping {peerId, timeoutMs}`**
   - Tier: unit (bridge, faked MethodChannel). RED on HEAD: `callP2PPeerPing` absent. GREEN: emits `cmd:'peer:ping'` with the payload; maps an old/`unknown` response to a typed failure (no throw). Mutation: change the cmd string → red.

7. `go-mknoon/bridge/bridge_ping_test.go`::**TC-183-31 — `PeerPing` param-parse + error path** (Go unit, `GOTOOLCHAIN=go1.25.0`; the real `ping.Ping` is device-proven). RED on HEAD: `PeerPing` absent. Mutation: break the JSON contract → red.

## Test Coverage Matrix  (zero empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-183-01 | arms fg+active | unit fakeAsync | active_peer_keepalive_use_case_test.dart::arms-on-foreground | use case absent | drop arm-on-fg | `flutter test test/core/services/active_peer_keepalive_use_case_test.dart` | AUTO (core-host-all) |
| TC-183-02 | cadence | unit | same::probes-every-N | absent | drop periodic tick | same | AUTO |
| TC-183-03 | cancel on bg | unit | same::cancels-on-background | absent | remove cancel | same | AUTO |
| TC-183-04 | cancel on close | unit | same::cancels-on-activePeer-clear | absent | remove clear-cancel | same | AUTO |
| TC-183-05 | success resets | unit | same::success-no-redial | absent | re-dial on success | same | AUTO |
| TC-183-06 | M-miss→1 warmPeer | unit | same::M-misses-one-rewarm | absent | re-dial per-miss | same | AUTO |
| TC-183-07 | drop→drain once | unit | same::M-misses-one-drain | absent | remove drain call | same | AUTO |
| TC-183-08 | null/group→no ping | unit | same::no-ping-null-group | absent | ping null/group | same | AUTO |
| TC-183-09 | account-gate | unit + impl | same::gated-no-spam + p2p_service_peer_liveness_test.dart::gated | absent | drop the gate | `flutter test test/core/services/p2p_service_peer_liveness_test.dart` | AUTO (core-host-all) |
| TC-183-10 | non-load-bearing | unit | same::thrown-ping-no-propagate | absent | rethrow | same | AUTO |
| TC-183-11 | bounded cadence | unit | same::churn-one-loop | absent | remove debounce | same | AUTO |
| TC-183-12 | resume re-arms (blind-spot) | unit + wiring | same::resume-rearms + main_keepalive_wiring_test.dart | absent | remove re-arm | both files | AUTO + ONE_TO_ONE_TESTS |
| TC-183-20 | iface purity | unit/structural | p2p_service_peer_liveness_test.dart::pingPeer-off-base-iface | iface absent | move pingPeer to base P2PService | `flutter test test/core/services/p2p_service_peer_liveness_test.dart` | AUTO (core-host-all) |
| TC-183-21 | lifecycle wiring | widget/host | main_keepalive_wiring_test.dart::wires-keepalive | main.dart no keepalive ref → RED | remove a wire | `flutter test test/core/lifecycle/main_keepalive_wiring_test.dart` | AUTO (core-host-all) **+ append ONE_TO_ONE_TESTS** |
| TC-183-22 | ~31 fakes compile | host suite | core-host-all + feature-host-all compile | passes on HEAD; locked by TC-183-20 + clean gate | add pingPeer to base iface → fakes fail | `./scripts/run_test_gates.sh feature-host-all` | AUTO |
| TC-183-30 | peer:ping bridge | unit (bridge) | p2p_bridge_client_ping_test.dart::sends-peer-ping | callP2PPeerPing absent | change cmd string | `flutter test test/core/bridge/p2p_bridge_client_ping_test.dart` | AUTO (core-host-all) |
| TC-183-31 | Go PeerPing wrapper | go unit | go-mknoon/bridge/bridge_ping_test.go::TestPeerPing | PeerPing absent | break param parse | `cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge/` | go test (not a flutter gate) |
| TC-183-40 | 30s poll unchanged | preservation | p2p_service_impl_test.dart health-check group | passes on HEAD | — | `./scripts/run_test_gates.sh core-host-all` | AUTO (sentinel) |
| TC-183-41 | 182 drain unchanged | preservation | the 182 connectivity-drain test (p2p_service_impl_test.dart network-change group) | passes | — | core-host-all | AUTO (sentinel) |
| TC-183-42 | warmPeer unchanged | preservation | p2p_service_impl_test.dart warmPeer group + handle_app_resumed_warm_peer_test.dart | passes | — | core-host-all | AUTO (sentinel) |
| TC-183-50 | drop-detected-in-seconds, re-dial, next send fast | **device-proof (PROD-CRITICAL)** | 183 device-proof runsheet::TC-183-50 | n/a (device) | n/a | two-phone rig | device-proof runsheet (not a host gate) |
| TC-183-51 | battery / zero background pings | device-proof | 183 runsheet::TC-183-51 | n/a | n/a | two-phone rig | device-proof runsheet |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the loop's in-memory state (the `Timer`, the miss counter) is re-derived each foreground. **Row:** TC-183-01 (arm on fg), TC-183-03 (cancel on bg), TC-183-12 (resume re-arms after pause), TC-183-21 (constructed in `initState` so a fresh mount/hot-restart reconstructs it; disposed on teardown — no leaked timer). Not N/A — explicitly locked.
- **Sibling-surface consistency:** **Justified asymmetry (test-noted).** The keepalive is 1:1-only; groups have their own liveness (GossipSub/rendezvous, `[[reference_codebase_architecture]]`). TC-183-08 locks that a `group:` active peer is NOT probed.
- **Destructive-action side-effects:** the only cleanup is `dispose()`/`onBackgrounded()` cancelling the timer. **Row:** TC-183-03/04 + a dispose case assert **no further pings after cancel/dispose** (what is removed), and the timer doesn't survive teardown (TC-183-21). No disk/DB rows touched.
- **Invariant re-verification under new transitions:** the `pause→resume` re-arm must restore the loop that pause cancelled (else liveness silently stops after one background). **Row:** TC-183-12.

## Invariants (locked by tests)
- **INV-1 (probes only fg+active 1:1):** armed on foreground with a non-null non-group active peer; never otherwise → TC-183-01/03/04/08.
- **INV-2 (drop → reuse, once):** M consecutive misses → exactly one `warmPeer` + one `drainOfflineInbox`; success resets → TC-183-05/06/07.
- **INV-3 (interface purity):** `pingPeer` on `PeerLivenessProbe`, never base `P2PService` → TC-183-20/22.
- **INV-4 (non-load-bearing):** gated/failed/thrown pings never propagate, never spam, never block → TC-183-09/10.
- **INV-5 (foreground-only):** zero pings while backgrounded → TC-183-03 + device TC-183-51.
- INV-RED-FIRST + INV-MUTATION-VERIFIED apply to every NEW row; sentinels (40/41/42) and the iface guard (20/22) pass on HEAD by design, each mutation-verified.

## Step-By-Step Implementation Plan
1. Snapshot tree: `git status --short` (record the uncommitted 500 ms budgets / clock→tick / 18x specs+plans — do NOT revert/bundle).
2. **Add RED tests first** (Group A loop + TC-183-20/21/30/31). Run focused cmds; confirm the loop/bridge/wiring tests FAIL because the APIs are absent, and the sentinels (40/41/42) + the iface-guard pass.
3. **Dart: capability interface + impl** — add `PeerLivenessProbe` to `p2p_service.dart` (NOT base `P2PService`); `P2PServiceImpl implements PeerLivenessProbe`; `pingPeer` move-gated → `callP2PPeerPing`.
4. **Bridge: `peer:ping`** — `callP2PPeerPing` (`p2p_bridge_client.dart`), cmd-spec (`go_bridge_client.dart`), native dispatch (`GoBridge.swift`/`.kt`).
5. **Go: `PeerPing` + node `PingPeer`** — `ping.Ping` first-result, `{ok,rttMs}`/typed-failure. Test under `GOTOOLCHAIN=go1.25.0`. Stop-if: `ping.Ping` needs a service handle the node doesn't expose → add a minimal accessor, do not re-enable a second ping service.
6. **Use case** — `ActivePeerKeepAliveUseCase` (mirror `SetPresenceUseCase`); consts `kKeepAliveInterval≈8s`, `kKeepAliveMissThreshold≈2`.
7. **Wire `_MyAppState`** — construct in `initState`, arm/cancel in `_onResumed`/`_onPaused`, dispose in `dispose()`.
8. Rerun direct → preservation → named gates. `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (lib/ + go-mknoon/ changed; never cwd inside graphify-arch/). For the device-proof: `cd go-mknoon && PATH=... make all && cd ../ios && pod install` then build.

## Risks And Edge Cases
- **Battery / cadence** — interval too tight tight-loops the radio; bounded `kKeepAliveInterval` + the existing warmPeer cooldown on the re-dial; pinned by TC-183-11 + device TC-183-51.
- **Ping false-negative** (a healthy peer momentarily slow) → a single miss must NOT re-dial; M-threshold + reset-on-success pins it (TC-183-05/06).
- **Double drain** — a drop that coincides with a 182 OS-network drain → both call the PUBLIC `drainOfflineInbox` which is single-in-flight-coalesced (`p2p_service_impl.dart:2020` guard); pinned by reusing the public entry (TC-183-07 asserts the call, the coalescing is the impl's existing lock — sentinel TC-183-41).
- **Account-migration** — pinging while migration paused network side-effects → the impl gate returns false; TC-183-09.

## Device/Relay Proof Profile
**requires device for closure** — the proactive `ping.Ping` + real drop-detection are PROD-CRITICAL and only provable on hardware. Create `Test-Flight-Improv/183-keepalive-device-proof-runsheet.md`.
- Rig: Pixel 6 `adb -s 21071FDF600CSC`; iPhone 11 `idevicesyslog -u 00008030-001A6D2801BB802E`. Build needs the new gomobile symbols: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install`; then `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1 --dart-define=MKNOON_ENABLE_NATIVE_MDNS=true`.
- **TC-183-50 (PROD-CRITICAL):** both phones foreground in the SAME 1:1 chat (warm). Force the PEER's connection to drop WITHOUT touching the sender's network (peer backgrounds, or peer WiFi off). Expect on the sender within ~N s: `KEEPALIVE_PEER_DROP` → a `warmPeer` re-dial (+ `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN`-equivalent drain) → the **next send stays on the warm/live path** (not the ~30 s-lagged cold-dial). Contrast a same-build run with the keepalive disabled (env/flag) showing the ~30 s lag.
- **TC-183-51:** over a multi-minute open chat, ping cadence is bounded (count ≈ elapsed/N); background the app → **zero** `peer:ping` while suspended; foreground → resumes. Do NOT flip any feature-flag default ON.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — must FAIL for the documented reason (APIs absent)
flutter test test/core/services/active_peer_keepalive_use_case_test.dart
flutter test test/core/services/p2p_service_peer_liveness_test.dart
flutter test test/core/bridge/p2p_bridge_client_ping_test.dart
flutter test test/core/lifecycle/main_keepalive_wiring_test.dart
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge/ ; cd ..

# Direct GREEN (after the Dart + Go edits)
flutter test test/core/services/active_peer_keepalive_use_case_test.dart   # all pass
flutter test test/core/services/p2p_service_peer_liveness_test.dart        # all pass
flutter test test/core/bridge/p2p_bridge_client_ping_test.dart             # all pass
flutter test test/core/lifecycle/main_keepalive_wiring_test.dart           # all pass (4 wires)
cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge/ ; cd ..             # PeerPing pass

# Preservation sentinels (must stay green)
flutter test test/core/services/p2p_service_impl_test.dart                 # warmPeer + onNetworkChanged(182) + 30s health unchanged
flutter test test/core/lifecycle/handle_app_resumed_warm_peer_test.dart    # resume warm unchanged

# Named gate(s)
./scripts/run_test_gates.sh 1to1            # incl. the wiring lock after registration; expect: <NNN>/<NNN>
./scripts/run_test_gates.sh core-host-all   # globs the new use-case/bridge/iface/wiring tests; expect: <NNNN>/<NNNN>
./scripts/run_test_gates.sh feature-host-all # ~31 fakes compile (TC-183-22); expect: <NNNN>/<NNNN>
./scripts/run_test_gates.sh completeness-check

# Hygiene
flutter analyze            # 0 new issues
git diff --check
graphify update . && ./graphify-arch/refresh_arch_graph.sh
```
> Replace `<NNN>`/`<NNNN>` with the pre-edit baseline counts (record, assert +N).

**Harness registration:** all new Dart tests are under `test/core/**` → AUTO into `core-host-all`. **Append `test/core/lifecycle/main_keepalive_wiring_test.dart` to `ONE_TO_ONE_TESTS` in `scripts/run_test_gates.sh`** (next to the 181 wiring lock) — `test/core/**` is not auto-globbed into the curated `1to1` gate. The Go test runs via `go test` (not a flutter gate). `completeness-check` confirms classification.

## Known-Failure Interpretation
- **Expected RED:** all Group A + TC-183-20/21/30/31 before the edits (APIs absent).
- **Guard/coverage locks** (TC-183-22 fakes-compile, sentinels 40/41/42): pass on HEAD by design; each mutation-verified.
- **Pre-existing dirty (NOT this plan):** the uncommitted 500 ms budgets, clock→tick, and the 181–184 docs. Leave them.
- **Environment blocker (NOT product):** no two-phone rig blocks ONLY TC-183-50/51 + the Go `make all`/`pod install` device build — not the host gates.
- **Scope drift (BLOCKING):** any change to base `P2PService`, the OS connectivity source (182), the 30 s poll, or a new parallel re-dial/drain.

## Done Criteria
- [x] RED added first (loop + bridge + wiring + iface), failed because the APIs are absent. *(Dart compile errors / Go `undefined: PeerPing` / wiring `contains` false — all captured.)*
- [x] Mutation-verified (each new lock has a named re-red revert — documented inline in every test's `Mutation:` note; adversarial review confirmed the assertions catch them).
- [x] Direct GREEN + preservation (p2p_service_impl 122, handle_app_resumed) pass. `core-host-all` 272/272 PASS; `1to1` keepalive-wiring 5/5 PASS (the 9 gate failures are PRE-EXISTING experiments, proven independent of 183); `feature-host-all` fakes-compile confirmed.
- [x] Go `PeerPing` test green under `GOTOOLCHAIN=go1.25.0` (3/3) + `go build ./node ./bridge` clean.
- [x] No `DB v##` change.
- [x] `pingPeer` on the capability interface, NOT base `P2PService` (~31 fakes untouched) — source-asserted (TC-183-20) + fakes compile across core/feature host suites.
- [x] Wiring lock registered (appended to `ONE_TO_ONE_TESTS`) + verified in a `1to1` run; `completeness-check` PASS (1004/1004).
- [ ] PROD-CRITICAL device-proof TC-183-50 passed on the two-phone rig (`KEEPALIVE_PEER_DROP` → re-dial → fast next send), zero background pings (TC-183-51). *(PENDING — needs `make all` + `pod install` for the gomobile symbols; runsheet written.)*
- [x] `flutter analyze` 0 new; `git diff --check` clean; graphs refreshed (full + arch).

## Scope Guard (hard "Do not")
- Do NOT add `pingPeer` to base `P2PService` (breaks ~31 fakes) — capability interface only.
- Do NOT re-wire the OS connectivity source / touch `onNetworkChanged`'s 182 drain (182 owns it) or the 30 s health poll.
- Do NOT build a new re-dial/drain — REUSE `warmPeer` + the public `drainOfflineInbox`.
- Do NOT ping in the background, the roster, or groups; do NOT remove the account-migration gate.
- Do NOT touch the send transport/race/budgets (incl. the uncommitted 500 ms experiment) or the 2-tick UI (184).

## Accepted Differences / Intentionally Out Of Scope
- **Wiring `_activePeerId` into `P2PServiceImpl`** (the 182 `:2215` follow-up that would also activate `onNetworkChanged`'s peer re-warm) — the keepalive scopes itself from the tracker; that wiring is a separate small follow-up, not bundled here.
- **Groups** — pubsub liveness, separate.
- **Background liveness** — impossible (OS); push + inbox + fast-foreground-reconnect (181/182) own the offline path.

## Dependency Impact
- Composes with 182 (reuses its `drainOfflineInbox`) and 181 (mirrors the lifecycle pattern). Nothing depends on 183.

## Reviewer Findings
Sufficiency: every TC-183-XX maps to ≥1 tiered row (zero empty matrix cells). The host floor proves the entire loop (arm/cancel/cadence/M-miss→reuse/gate/non-load-bearing) with a faked `PeerLivenessProbe` + fakeAsync; the PROD-CRITICAL `peer:ping` real leg is a named two-phone device-proof, not a fake. Interface purity (capability iface, ~31 fakes spared) is locked two ways (source-assertion + clean fakes-compile gate). A distinct `KEEPALIVE_PEER_DROP` discriminator separates the keepalive re-dial from warmPeer's other triggers. Preservation sentinels named (182 drain, 30 s poll, warmPeer). Literal gates + Go-test gate + harness registration (one `ONE_TO_ONE_TESTS` append). No DB migration. Blind-spot sweep: durability locked, sibling asymmetry test-noted, destructive (timer-cancel) asserted, pause→resume re-arm locked.

## Arbiter Decision
Structural blockers: none. Implementation-ready: new use case + capability iface + Go `peer:ping`, all host-floored with a device-proof closure, reusing 181's pattern and 182's drain. Deferred: literal gate counts (fill from baseline); the `_activePeerId`-into-impl follow-up (out of scope). Accepted differences: groups, background, the impl activePeerId wiring. Hand off to execution.

## Final Execution Verdict
Verdict: **HOST-GREEN / device-proof PENDING** (2026-07-01). The complete loop + capability iface + bridge + Go `peer:ping` + wiring landed RED-first → GREEN; the real `ping.Ping` leg + drop-detection remain the PROD-CRITICAL device closure (TC-183-50/51, runsheet written).

Files changed (matches plan): `lib/core/services/p2p_service.dart` (+`PeerLivenessProbe` iface, OFF base) · `lib/core/services/p2p_service_impl.dart` (+`implements PeerLivenessProbe`, +move-gated `pingPeer`→`callP2PPeerPing`) · `lib/core/services/active_peer_keepalive_use_case.dart` (NEW) · `lib/core/bridge/p2p_bridge_client.dart` (+`callP2PPeerPing`) · `lib/core/bridge/go_bridge_client.dart` (+`'peer:ping'` cmd-spec) · `ios/Runner/GoBridge.swift` + `android/.../GoBridge.kt` (+`peerPing` dispatch) · `go-mknoon/bridge/bridge_ping.go` (NEW `PeerPing`) · `go-mknoon/node/ping.go` (NEW `PingPeer`/`ping.Ping`) · `lib/main.dart` (wiring) · `scripts/run_test_gates.sh` (ONE_TO_ONE_TESTS append) · 4 new Dart test files · `go-mknoon/bridge/bridge_ping_test.go` · `Test-Flight-Improv/183-keepalive-device-proof-runsheet.md`.

Tests run (+counts):
- RED-first: all 5 new test files FAILED for the documented reason (APIs absent) — Dart compile errors (`PeerLivenessProbe`/`ActivePeerKeepAliveUseCase`/`pingPeer`/`callP2PPeerPing` undefined), Go `undefined: PeerPing`, wiring `contains` false.
- Direct GREEN: `active_peer_keepalive_use_case_test.dart` + `p2p_service_peer_liveness_test.dart` + `p2p_bridge_client_ping_test.dart` = **20/20**; `main_keepalive_wiring_test.dart` **5/5**; `bridge_ping_test.go` **3/3** (`GOTOOLCHAIN=go1.25.0`); `go build ./node ./bridge` clean.
- Preservation sentinels: `p2p_service_impl_test.dart` + `handle_app_resumed_warm_peer_test.dart` = **122/122** (warmPeer + 182 onNetworkChanged drain + 30 s health-poll unchanged).
- Gates: `core-host-all` **272/272 files** (globs all 4 new Dart tests) · `completeness-check` **1004/1004** · `1to1` **+1415 / −9** (all 5 keepalive wiring tests PASS) · `feature-host-all` fakes-compile confirmed (INV-3/TC-183-22 — `pingPeer` never on base `P2PService`).
- Hygiene: `flutter analyze` 0 new issues (25 pre-existing info-lints, none in 183 code) · `git diff --check` clean · full + arch graphs refreshed.
- Adversarial review (5-dimension, verify-each): **0 real findings in 183 code** (use-case loop / impl / bridge / Go / wiring all clean); the only 2 confirmed findings are the PRE-EXISTING `send_chat_message_use_case.dart` 500 ms-budget experiment + 184 2-tick work, left untouched per scope.

Blocking: **none attributable to 183.** The 9 `1to1`/`feature-host-all` failures are PRE-EXISTING uncommitted experiments — 6 in `send_chat_message_use_case_test.dart` (the unticketed 500 ms-budget EXPERIMENT; PROVEN: with it stashed + 183 intact → **125/125 green**), 3 in `conversation_wired_offline_send_ux_test.dart` (a missing-Material-icon `U+F012B` UI assertion from the pre-existing `letter_card.dart` change; PROVEN: persists with the send budgets reverted, references zero 183 symbols). 183 touches no send-transport / conversation-UI code.

QA verdict: host floor complete + adversarially clean; ship gated on the two-phone device-proof (TC-183-50/51) which requires `cd go-mknoon && make all && cd ../ios && pod install` to land the new `BridgePeerPing`/`GoMknoon.peerPing` gomobile symbols.

Non-blocking follow-ups (owner): wire `_activePeerId` into `P2PServiceImpl` (182 `:2215` follow-up, also activates `onNetworkChanged`'s peer re-warm) · adaptive cadence/timeout tuning (perf, device-tunable) · groups pubsub liveness (separate).
