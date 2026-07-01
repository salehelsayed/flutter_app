# 182 - Drain Offline Inbox the Instant Connectivity Returns  (Bug)

Status: EXECUTED 2026-06-30 (host floor landed + mutation-verified; OS-source wired; device-proof TC-182-08 deferred to rig) — see Final Execution Verdict
Spec: free-text intent (no formal spec) — grounded + verify→refute confirmed in this plan

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-30 | Evidence Collector | p2p_service_impl.dart (176/385/405/512/2659-2700/4749/2020-2049/3866/2711), main.dart:2206-2311, handle_app_resumed.dart:219-220, p2p_service_impl_test.dart:307-660/5765, go-mknoon/node/{inbox.go,node.go}, pubspec.yaml, scripts/run_test_gates.sh, scripts/check_reliability_simulation_discovery.sh, Reports 41/48 | Root cause confirmed; 30s health-check is the existing partial mitigation; fix seam is in-class self-call | hand to Planner |
| 2026-06-30 | Planner | tier-matrix.md, harness arrays | Host-floor + migration-gate + debounce + device-proof rows | build matrix |
| 2026-06-30 | Reviewer (sufficiency) | sufficiency-checklist.md | blind-spot sweep (durability/sibling/destructive/invariant) all addressed | self-check below |
| 2026-06-30 | Arbiter | — | structurally complete; ONE open impl decision (connectivity source A vs B) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-30 | contract extraction (git status --short) | — | dirty: info.plist, project.pbxproj, send_chat_message_use_case.dart, letter_card.dart (pre-existing, NOT mine) | scope confirmed | RED |
| 2026-06-30 | RED tests added | p2p_service_impl_test.dart (+TC-182-01..06), connectivity_signal_test.dart (+TC-182-07) | `flutter test … --plain-name '182 connectivity-restore inbox drain'` → 0 +6 -6 (all RED for "no drain on HEAD") | RED for expected reason | implement |
| 2026-06-30 | implementation | p2p_service_impl.dart (onNetworkChanged drain), connectivity_signal.dart (new), main.dart:2206 (networkChangeSignal wired), pubspec.yaml (connectivity_plus ^6.1.0) | — | scoped files only | GREEN |
| 2026-06-30 | direct GREEN | (as above) | TC-182-01..06 → +6 all pass; connectivity_signal_test → +3 pass | reds now green | preservation |
| 2026-06-30 | preservation GREEN | — | full `p2p_service_impl_test.dart` → **118/118 pass** (FDC-04 re-warm TC-04-07/08/16, 141 drain, health-check poll intact) | sentinels green | gates |
| 2026-06-30 | named gates | check_reliability_simulation_discovery.sh (+classify_path) | `run_test_gates.sh 1to1` → +1398 -16; **16 isolated as pre-existing dirty** (stash-revert → those 4 files 345/345 pass); discovery exit 0, proof classified `1to1` | gate green (mod pre-existing dirt) | QA |
| 2026-06-30 | QA (independent) | — | `flutter analyze` new files: 0 issues; `git diff --check` clean; 1 pre-existing lint (:3658, commit 208be686) not mine | blocking: none | verdict ✅ |

## Source Of Truth
- Spec / intent: inline below (free-text bug, verify→refute confirmed)
- Gate definitions: `scripts/run_test_gates.sh`  (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md`  (this is report **182**, next-free after 181)

## Session Classification
implementation-ready (host floor is fully host-testable on an existing harness; the OS-source half + its device-proof are the only manual-closure legs)

## Exact Problem Statement

When connectivity is **restored while the app is already foreground** — Wi‑Fi auto‑reconnects, the router comes back, or a Wi‑Fi↔cellular handoff completes — the app does **not** pull the relay's stored offline inbox at that moment. New, live messages start flowing **immediately** (libp2p AutoRelay re‑establishes the relay circuit at the Go layer, independent of any Dart signal — `go-mknoon/node/node.go:393`), arriving on the live `ChatProtocol` stream. But messages that were **queued on the relay while the device was offline** must be **pulled** by an explicit, client‑initiated `inbox:retrieve_pending` drain — and that drain has **no connectivity trigger**. The user observed exactly this: after turning Wi‑Fi back on, the iPhone received **3 new** messages from the Pixel **before** it downloaded the **3 previously‑stored** ones.

The stored backlog is not lost — it is eventually caught up by the **30‑second periodic health‑check poll** (`Timer.periodic` at `p2p_service_impl.dart:2711` → `_performHealthCheck` → `await _drainOfflineInbox()` at `:3866`). That poll is why the user experienced a *delay* ("it took a while") rather than a permanent miss. The bug is therefore **latency/ordering**, not silent loss: the app waits up to ~30s (the next healthy poll tick) instead of draining the **instant** the network is back.

**What must improve:** the moment connectivity is restored, the app pulls the offline inbox via the existing durable drain — no resume, notification, or screen‑open required, and no waiting for the 30s poll.

**What must stay unchanged (→ preserved‑green sentinels):**
- The 30s health‑check drain keeps working as a backstop (`p2p_service_impl_test.dart` health‑check group, ~`:4125`).
- The FDC‑04 network‑change **re‑warm** behavior is unchanged (`TC-04-07/08/16`).
- The drain uses the **durable** `inbox:retrieve_pending → stage → ack` path only; it must NEVER re‑introduce the destructive `inbox:retrieve`/`_retrieveInboxPage` fallback that Report 48 deliberately removed.
- The account‑migration network gate continues to gate every network side‑effect (incl. this new drain trigger).

## Root Cause (verify → refute confirmed — all 5 claims SURVIVED an adversarial refute pass)

The connectivity→drain seam exists internally but is **doubly inert** in production, and even if live it would not drain:

1. **C1 (survives):** `onNetworkChanged()` (`p2p_service_impl.dart:2659‑2700`) is the only network‑change handler, and its sole outbound action is `unawaited(warmPeer(peerId, preferQuic: true))` at `:2696`. It **never calls `drainOfflineInbox`**. No connectivity‑triggered drain exists anywhere in `lib/`.
2. **C3 (survives):** `_networkChangeSignal` (`Stream<void>?`, `:176`) is fed only by an optional constructor param (`:385`) that the **sole** production construction site `lib/main.dart:2206‑2311` **omits**, so it stays `null`; the null‑aware subscription at `:512` is never created → `onNetworkChanged` never fires from the OS in production. (`pubspec.yaml` has **no** `connectivity_plus`; there is **no** native `NWPathMonitor`/`ConnectivityManager` channel.)
3. **C4 (survives):** confirmed independently — `onNetworkChanged` only re‑warms; no transitive drain via `warmPeer` (`:2522‑2627`).
4. **C2 (survives, with a precision):** the resume‑triggered drain is gated **solely** on `AppLifecycleState.resumed` (`main.dart:4391` → `_onResumed` → `handleAppResumed` → `drainOfflineInbox` at `handle_app_resumed.dart:219‑220`). A foreground connectivity restore that carries **no lifecycle transition** (Wi‑Fi auto‑reconnect / handoff / router‑back) emits no `resumed`, so the resume drain never fires. *Precision:* the original "Control Center toggle is not a resume" example is imprecise at the iOS layer — dismissing Control Center fires `resumed`, which would drain on dismissal. The genuinely‑never‑fires class is the no‑lifecycle‑transition restore. The user's observed *delay* is fully explained by the 30s poll regardless.
5. **C5 (survives):** libp2p **AutoRelay** (Go, `node.go:393` `EnableAutoRelayWithStaticRelays`) reconnects autonomously → live `ChatProtocol` messages render immediately (`node.go:450/1715`); the relay **never pushes** the stored backlog — `inbox:retrieve_pending` is **client‑initiated and non‑destructive** (`p2p_service_impl.dart:251`; `p2p_bridge_client.dart:854‑855`; `go-mknoon/node/inbox.go:668‑690`). With no connectivity trigger for the pull, **live beats stored**.

**Refuted / do‑NOT‑re‑introduce / do‑NOT‑mis‑plan:**
- *Not "never drains":* the 30s health‑check poll (`:3866`, timer `:2711`) **is** a non‑resume drain trigger that mitigates within ~30s. Do **not** plan as if the backlog is permanently lost, and do **not** remove/replace the poll — keep it as the backstop and add the immediate trigger alongside.
- *Not the sender‑side re‑warm:* the live‑message recovery is Go‑side AutoRelay (recipient reachability), **not** the Dart `onNetworkChanged`→`warmPeer` re‑warm (which is sender‑side and inert in prod). Don't conflate them.
- *Destructive fallback (Report 48):* the connectivity drain must call the **public `drainOfflineInbox`** (durable). Never wire it to `inbox:retrieve`/`_retrieveInboxPage`.

## Real Scope
**In scope:**
1. `p2p_service_impl.dart` — inside `onNetworkChanged()`, after the 5s flap‑debounce early‑return (`:2664‑2669`) and **before** the `peerId == null` return (`:2673`): emit a new discriminator flow event `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` and call `unawaited(drainOfflineInbox().catchError((_) {}))` (the **public** entry `:4749`, so it inherits the 141 not‑started defer, the account‑migration gate, and single‑in‑flight coalescing).
2. Wire an **OS connectivity source** in `lib/main.dart:2206` so `networkChangeSignal:` (and `activePeerId:`) are passed in production — a `Stream<void>` that emits on **network‑restored** edges. **DECISION (user‑confirmed 2026‑06‑30): Option A — `connectivity_plus`.** Add the package, map `Connectivity().onConnectivityChanged`, filtering to restored edges (drop `none`/no‑op repeats). The mapping adapter is its own host‑testable unit (`connectivity_signal.dart` / TC‑182‑07). **Option B (documented fallback only):** a native `EventChannel` (iOS `NWPathMonitor` + Android `ConnectivityManager.registerDefaultNetworkCallback`) modeled on the existing `mknoon/mdns_resolver` channel — switch to it **only if** the TC‑182‑08 device run shows Option A firing too chattily; the `Stream<void>` contract makes the swap test‑surface‑neutral.

**Out of scope (owning work):**
- Presence re‑publish on connectivity restore — owned by the **181 presence lifecycle** wiring (`SetPresenceUseCase`, already device‑proven). Not re‑opened here.
- Removing or re‑tuning the 30s health‑check poll — separate transport‑tuning work; here it stays as the backstop.
- The FDC‑04 sender‑side re‑warm semantics (peer‑scoped) — unchanged; we only ride its existing debounce.

## Files To Inspect Next
**Production (entry/use‑case, models, repos, helpers):**
- `lib/core/services/p2p_service_impl.dart`: `onNetworkChanged` `:2659‑2700` (edit), `drainOfflineInbox` `:4749`, `_drainOfflineInbox` in‑flight guard `:2020‑2049`, flap floor `:2664‑2669`/`:2515`, peer guard `:2672‑2673`, ctor param `:385`/sub `:512`, health‑check drain `:3866`/timer `:2711`.
- `lib/main.dart`: sole construction site `:2206‑2311` (add `networkChangeSignal:` + `activePeerId:`).
- (Option A) `pubspec.yaml` (add `connectivity_plus`) + a new adapter `lib/core/services/connectivity_signal.dart`. (Option B) native `EventChannel` in `ios/Runner/` + `android/app/.../`.

**Direct tests + integration tests:**
- `test/core/services/p2p_service_impl_test.dart` — `FDC-04 warmPeer` group `:307` (helper `startWarmService` `:310`, rewarm tests `:534/:589/:612`), `141 notif-open deferred startup drain` group `:5765` (drain‑assert idiom, `inbox:retrieve_pending` counter `:5769`).
- New adapter test (Option A): `test/core/services/connectivity_signal_test.dart`.

**Dependency‑only context:**
- `lib/core/lifecycle/handle_app_resumed.dart:219‑234` (resume drain + `APP_LIFECYCLE_RESUME_*` discriminators); `go-mknoon/node/inbox.go` (pull‑only relay); Reports `41`/`48` (durable‑path mandate).

## Existing Tests Covering This Area
- `p2p_service_impl_test.dart` `TC-04-07/08/16` — network‑change **re‑warm** behavior (exists, PASS). Will stay green (fix adds drain, leaves re‑warm path intact).
- `p2p_service_impl_test.dart` `141` deferred‑startup‑drain group — drain defer/fire + `inbox:retrieve_pending` counting (exists, PASS). Reused as the assertion idiom.
- `p2p_service_impl_test.dart` health‑check group (~`:4125`) — 30s poll drain ordering (exists, PASS). Preservation sentinel.
- **MISSING:** any test asserting a connectivity event triggers a **drain** (only re‑warm is covered); any test asserting the drain is **roster‑wide** (fires with no active peer); any test asserting the connectivity drain respects the **migration gate**; any `connectivity_plus`/native‑source adapter test; any **device‑proof** of the OS edge firing without a resume.
- **Already in curated family arrays?** `test/core/services/p2p_service_impl_test.dart` is listed in `ONE_TO_ONE_TESTS` (`scripts/run_test_gates.sh:52`) **and** auto‑globbed under `test/core/**` → new host tests in this file need **no** new array entry. A new trigger‑side integration smoke would go in `TRANSPORT_TESTS` (`:222`).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

> All host tests land in `test/core/services/p2p_service_impl_test.dart`, in or beside the `FDC-04 warmPeer` group, reusing `startWarmService(networkChangeSignal:, activePeerId:)` (`:310`) and the `bridge.whenCommand('inbox:retrieve_pending', …)` counter idiom (`:5769`).

1. **`p2p_service_impl_test.dart`::`TC-182-01: connectivity event drains the inbox even with NO active peer`**  — **PROD-CRITICAL (drain‑trigger leg)**
   - Tier: unit/application (host).
   - Shape/setup: `bridge.whenCommand('inbox:retrieve_pending', (_) { retrieveCount++; return ok-empty })`; `startWarmService(networkChangeSignal: signal.stream, activePeerId: () => null)` (started node, **no** active peer); `_captureFlowEvents(() async { signal.add(null); await _waitForCondition(() => retrieveCount >= 1) })`.
   - RED on HEAD because: `onNetworkChanged` never calls `drainOfflineInbox`; with `activePeerId:()=>null` it also returns at `:2673` — `retrieveCount` stays 0 → `_waitForCondition` times out.
   - GREEN after fix asserts: `retrieveCount >= 1` **AND** event `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` present **AND** `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN` present.
   - Distinct‑event discriminator (drain vs re‑warm): assert `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` **AND NOT** `P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM` (no active peer ⇒ re‑warm correctly skipped, yet the drain still fired ⇒ proves the drain is roster‑wide, placed before the `:2673` guard).
   - Mutation that re‑reds: remove the `unawaited(drainOfflineInbox()…)` line from `onNetworkChanged` → `retrieveCount` 0 → RED. (Second mutation: move the drain call *after* the `:2673` peer guard → with `activePeerId:()=>null` it never fires → RED.)

2. **`p2p_service_impl_test.dart`::`TC-182-02: connectivity drain uses the DURABLE retrieve, never the destructive read`**
   - Tier: unit/application (host).
   - Shape/setup: as TC‑182‑01; register both `inbox:retrieve_pending` and `inbox:retrieve` command stubs with counters; fire `signal.add(null)`.
   - RED on HEAD because: no drain fires at all → `retrieve_pending` count 0 (assertion `>=1` fails).
   - GREEN after fix asserts: `inbox:retrieve_pending` called `>= 1` **AND** `inbox:retrieve` (destructive) count `== 0`.
   - Mutation that re‑reds: revert the drain wiring → RED (locks the Report‑48 durable‑path constraint at the connectivity entry).

3. **`p2p_service_impl_test.dart`::`TC-182-03: connectivity drain AND re-warm both fire when an active peer exists`**
   - Tier: unit/application (host).
   - Shape/setup: `startWarmService(networkChangeSignal: signal.stream, activePeerId: () => 'peer-A')`; fire `signal.add(null)`.
   - RED on HEAD because: only the re‑warm fires; `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` never emitted.
   - GREEN after fix asserts: **both** `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` **and** `P2P_SERVICE_WARM_PEER_NETWORK_CHANGE_REWARM` present (proves adding the drain did not break, gate, or reorder the existing re‑warm).
   - Mutation that re‑reds: revert drain line → drain event absent → RED. (Sentinel against regressing TC‑04‑07.)

4. **`p2p_service_impl_test.dart`::`TC-182-04: flap-burst coalesces to ONE connectivity drain (5s debounce)`**
   - Tier: unit/application (host), `withClock`.
   - Shape/setup: mirror `TC-04-16` (`:612`); 3 rapid `signal.add(null)` within the 5s floor (clock not advanced); count `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` events.
   - RED on HEAD because: no drain event ever emitted (count 0 ≠ expected 1).
   - GREEN after fix asserts: exactly **one** `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` across the burst (drain inherits the existing flap floor because it sits **after** the `:2664‑2669` early‑return).
   - Mutation that re‑reds: move the drain call *above* the debounce early‑return → 3 drain events → RED (proves placement, not just presence).

5. **`p2p_service_impl_test.dart`::`TC-182-05: connectivity drain respects the account-migration network gate`** — **INV (new transition re‑verifies a pre‑existing invariant)**
   - Tier: unit/application (host).
   - Shape/setup: `startWarmService(...)` with the account‑migration gate denying `'p2p_drain_offline_inbox'` (existing gate‑injection pattern used by the "account migration runtime gate" group `:662`); fire `signal.add(null)`.
   - RED on HEAD because: there is no connectivity drain to gate — but written to assert *no destructive escape*; on HEAD it is vacuously green for "no retrieve", so this test is authored to RED **after** TC‑182‑01 lands by also asserting `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` **is** emitted (proving the path runs) while `inbox:retrieve_pending` count `== 0` (gate blocked the side‑effect). On HEAD the drain event is absent → RED.
   - GREEN after fix asserts: `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` present, `P2P_SERVICE_ACCOUNT_MIGRATION_NETWORK_BLOCKED` present, `inbox:retrieve_pending` count `== 0`.
   - Mutation that re‑reds: call the **private** `_drainOfflineInbox()` (bypassing the gate) instead of public `drainOfflineInbox()` → retrieve fires despite the deny → RED. (This is exactly why the plan mandates the public entry.)

6. **`p2p_service_impl_test.dart`::`TC-182-06: connectivity event while node NOT started defers the drain (141 inheritance)`** — **lifecycle durability**
   - Tier: unit/application (host).
   - Shape/setup: construct via the standard (not `startWarmService`) path so the node is **not** started, with `networkChangeSignal: signal.stream`; fire `signal.add(null)`; then drive `startNodeCore(...)`.
   - RED on HEAD because: no connectivity drain exists → no `P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED`, and after start no deferred fire.
   - GREEN after fix asserts: before start, `P2P_SERVICE_PENDING_STARTUP_DRAIN_SCHEDULED` present and `inbox:retrieve_pending` count `== 0`; after stopped→started, the deferred drain fires exactly once (`retrieveCount` becomes `>= 1`). Proves the connectivity trigger inherits the 141 defer‑not‑drop guard.
   - Mutation that re‑reds: revert drain wiring → no scheduled/fired events → RED.

7. **`connectivity_signal_test.dart`::`TC-182-07: adapter emits on restored edges only, never on loss`**  *(Option A; if Option B native channel is chosen, this becomes the Dart‑side EventChannel‑decode test)*
   - Tier: unit (host, pure logic) — `test/core/services/`.
   - Shape/setup: drive a fake connectivity result stream (`[none] → [wifi]`, `[wifi] → [none]`, `[wifi] → [mobile]`) into the adapter that maps to `Stream<void>`.
   - RED on HEAD because: no adapter exists (compile/import failure for the new file is the RED).
   - GREEN after fix asserts: emits exactly once on `none→wifi` and `none→mobile` (restored), emits **zero** times on `wifi→none` (loss) and on duplicate `wifi→wifi` no‑ops.
   - Mutation that re‑reds: drop the `none`/loss filter (emit on every change) → loss‑edge emits → RED.

8. **`integration_test/connectivity_restore_inbox_drain_proof_test.dart`::`TC-182-08: foreground Wi‑Fi restore drains the relay backlog with NO resume`** — **PROD-CRITICAL (OS‑source leg), CLOSURE GATE**
   - Tier: device‑proof (physical, two devices). Host fakes cannot prove `NWPathMonitor`/`ConnectivityManager` actually fires on a foreground toggle.
   - Shape/setup: Device B foreground + idle (no conversation open). Device A sends 3 messages to B while **B's Wi‑Fi is OFF** (they queue on the relay inbox). With B still foreground, toggle B's Wi‑Fi **ON**.
   - GREEN asserts: B's 3 stored messages surface **within a few seconds** (not waiting ~30s), and B's flow‑event log shows `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` + `P2P_SERVICE_DRAIN_OFFLINE_INBOX_BEGIN` with **NO** `APP_LIFECYCLE_RESUME_*` event in that window (proves the drain was connectivity‑triggered, not a resume).
   - Mutation that re‑reds: revert the `main.dart:2206` wiring (signal back to null) → B falls back to the ~30s poll, log shows no `NETWORK_CHANGE_DRAIN_BEGIN` → fails the "within seconds + connectivity discriminator" assertion.

## Test Coverage Matrix  (ZERO empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| Connectivity → drain (roster‑wide) | handler self‑call, peer‑independent | unit/app host | `p2p_service_impl_test.dart::TC-182-01` | `onNetworkChanged` never drains; `:2673` returns w/ null peer → retrieveCount 0 | remove `drainOfflineInbox()` call → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-01'` | AUTO (`test/core/**`) + already in `ONE_TO_ONE_TESTS` (file `:52`) |
| Durable path only (Report 48) | non‑destructive retrieve | unit/app host | `p2p_service_impl_test.dart::TC-182-02` | no drain → `retrieve_pending` 0 | revert drain wiring → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-02'` | AUTO + `ONE_TO_ONE_TESTS` |
| Drain + re‑warm coexist | no regression of FDC‑04 | unit/app host | `p2p_service_impl_test.dart::TC-182-03` | drain event never emitted | revert drain line → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-03'` | AUTO + `ONE_TO_ONE_TESTS` |
| Flap debounce coalesces drain | 5s floor placement | unit/app host (`withClock`) | `p2p_service_impl_test.dart::TC-182-04` | no drain event (count 0) | move drain above debounce return → 3 events → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-04'` | AUTO + `ONE_TO_ONE_TESTS` |
| Migration gate honored (INV) | new side‑effect re‑checks gate | unit/app host | `p2p_service_impl_test.dart::TC-182-05` | drain path absent → discriminator event missing | call private `_drainOfflineInbox` (bypass gate) → retrieve fires → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-05'` | AUTO + `ONE_TO_ONE_TESTS` |
| Not‑started defer (141) | lifecycle durability | unit/app host | `p2p_service_impl_test.dart::TC-182-06` | no scheduled/fired deferred drain | revert drain wiring → RED | `flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-06'` | AUTO + `ONE_TO_ONE_TESTS` |
| OS source maps restored edges | pure adapter logic | unit host | `connectivity_signal_test.dart::TC-182-07` | adapter file does not exist (import RED) | drop loss filter → emits on loss → RED | `flutter test test/core/services/connectivity_signal_test.dart` | AUTO (`test/core/**`) |
| OS edge fires drain, no resume | OS‑boundary, 2‑device | device‑proof | `integration_test/connectivity_restore_inbox_drain_proof_test.dart::TC-182-08` | signal unwired in prod (`main.dart:2206`) → ~30s poll, no discriminator | revert `main.dart:2206` wiring → RED | manual physical device (steps below); related sims: `/sims 1to1 --list` | `classify_path()` 'device-proof' case in `check_reliability_simulation_discovery.sh` (see Device/Relay Proof Profile) |

## Blind-Spot Sweep  (evergreen classes — row added OR justified N/A)
- **Lifecycle / derived-state durability:** **TC-182-06** — a connectivity event while the node is stopped must **defer** (141) and fire once on stopped→started, not be dropped. The drain's payload durability is already covered by the existing `InboxStagingRepository` round‑trip (no new derived in‑memory state is introduced — the trigger is transient and re‑derived on each event). The `_networkChangeSub` is created in the ctor and cancelled in `dispose` (`:512`/`:5162`); a fresh instance re‑subscribes — no persisted derived state to reconstruct.
- **Sibling-surface consistency:** the connectivity restore now drives **two** sibling actions in `onNetworkChanged`: the roster‑wide **drain** (covers 1:1 **and** group via the unified offline inbox) and the peer‑scoped **re‑warm** (TC‑182‑03 locks both fire). Other connectivity‑reactive surfaces are deliberately **not** added here: **presence re‑publish** is owned by the 181 lifecycle wiring (Accepted Difference); group inbox needs no separate trigger because `drainOfflineInbox` is the unified inbox drain. Asymmetry (drain before `:2673`, re‑warm after) is **test‑locked** by TC‑182‑01 (drain fires with null peer) + TC‑182‑03 (both fire with a peer).
- **Destructive-action side-effects:** **TC-182-02** asserts the connectivity drain issues `inbox:retrieve_pending` (durable, non‑destructive) and **never** `inbox:retrieve` (the destructive read Report 48 removed). No new delete/cleanup path is introduced — the existing durable stage→ack pipeline is reused, not re‑implemented.
- **Invariant re-verification under new transitions:** **TC-182-05** — the new connectivity transition re‑verifies the **account‑migration network gate** invariant (every network side‑effect must be gated during a Move export pause); locked by routing through the **public** `drainOfflineInbox`, with the mutation (private‑bypass) proving it. The drain's own **single‑in‑flight coalescing** invariant (`_drainInProgress`, `:2020‑2049`) is re‑verified under the new caller by TC‑182‑04 (a flap burst yields one drain) — no two parallel drains.

## Invariants (locked by tests)
- **INV-1** connectivity restore triggers a drain **independent of any active conversation peer** → TC‑182‑01.
- **INV-2** the connectivity drain uses the **durable, non‑destructive** retrieve only → TC‑182‑02.
- **INV-3** adding the drain does **not** alter the existing FDC‑04 re‑warm → TC‑182‑03 + preserved TC‑04‑07/08/16.
- **INV-4** flap bursts coalesce to **one** drain (debounce honored) → TC‑182‑04.
- **INV-5** the connectivity drain **respects the migration gate** → TC‑182‑05.
- **INV-6** a connectivity event before node‑start **defers, never drops** → TC‑182‑06.
- **INV-7** the production OS source fires the drain **without** a lifecycle resume → TC‑182‑08 (device‑proof).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Snapshot** `git status --short` (record the pre‑existing dirty files; see Known‑Failure Interpretation) so unrelated changes are not reverted.
2. **Add RED host tests** TC‑182‑01..06 to `p2p_service_impl_test.dart` (+ TC‑182‑07 adapter test). Run the focused `--plain-name` commands; confirm each fails for its documented reason.
3. **Edit `onNetworkChanged`** (`p2p_service_impl.dart`): immediately after `_lastNetworkRewarmAt = now;` (`:2669`) and **before** `final peerId = _activePeerId?.call();` (`:2672`), insert:
   - `emitFlowEvent(layer: 'FL', event: 'P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN', details: {});`
   - `unawaited(drainOfflineInbox().catchError((Object _) {}));`  ← **public** entry (`:4749`).
   Stop‑if: `drainOfflineInbox` is not in scope / a layering rule forbids the self‑call → replan (do not reach for a callback param; it is the same instance).
4. **Build the OS connectivity source (Option A — `connectivity_plus`, user‑confirmed):** add `connectivity_plus` to `pubspec.yaml`; create `lib/core/services/connectivity_signal.dart` mapping `onConnectivityChanged` → `Stream<void>` on restored edges (drop `none`/duplicate no‑ops). Make TC‑182‑07 green.
5. **Wire production** at `lib/main.dart:2206`: pass `networkChangeSignal: connectivitySignal` and `activePeerId: () => conversationTracker.activePeerId` (lighting up both the drain and the dormant FDC‑04 re‑warm). Stop‑if: `conversationTracker` is not in scope at the construction site → pass only `networkChangeSignal:` (drain half) and leave `activePeerId:` for a follow‑up; the drain is the bug fix and is peer‑independent.
6. **Add the device‑proof** `integration_test/connectivity_restore_inbox_drain_proof_test.dart` (TC‑182‑08) + its `classify_path()` registration.
7. Rerun **direct → preservation → named gates** (below). Then `flutter analyze` (0 new) and `git diff --check`.

## Risks And Edge Cases
- **Drain storm on Wi‑Fi flapping** (elevators/transit) → pinned by TC‑182‑04 (5s flap floor) + the existing single‑in‑flight coalescing (`:2020‑2049`).
- **`connectivity_plus` chattiness / "connected ≠ reachable"** (esp. iOS reports interface changes): acceptable — the drain is cheap, debounced, gated, and idempotent; a spurious trigger costs one non‑destructive `retrieve_pending`. If it proves too noisy on device, switch to Option B (native `NWPathMonitor`/`ConnectivityManager`) behind the same `Stream<void>` contract — no `onNetworkChanged` change needed.
- **Event during Move export pause** → migration gate blocks the side‑effect; pinned by TC‑182‑05.
- **Event before node start** → 141 defer; pinned by TC‑182‑06.
- **Double drain (poll + connectivity within the same window)** → coalesced by `_drainInProgress`; no duplicate relay reads.

## Device/Relay Proof Profile
**requires physical 2‑device for closure** (host floor closes the wiring; the OS‑source emission is device‑only).
- Closure scenario: **TC‑182‑08** — manual, physical, two phones. Steps: (1) B foreground + idle; (2) A sends 3 msgs while B Wi‑Fi OFF (queue to relay inbox); (3) toggle B Wi‑Fi ON while B stays foreground; (4) assert the 3 stored msgs surface within seconds and B's log shows `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` with **no** `APP_LIFECYCLE_RESUME_*` in‑window.
- **Why not a `/sims` scenario:** the simulator orchestrator cannot toggle the OS network path of a *foregrounded* app mid‑run (that is the exact OS boundary under test), so this proof is **manual physical‑device**, not `/sims`‑automatable. Register the `classify_path()` case so the proof file is *discovered/classified* (not silently orphaned), but expect closure evidence to come from a device run, not the sim gate. Related transport sims remain runnable: `/sims 1to1 --list`.
- Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooW…` (see `/sims`).

## Acceptance Gates  (literal — copy/paste)
```bash
# 0. Dirty-tree snapshot (do NOT revert these later)
git status --short

# 1. RED (before production edits) — each MUST FAIL for its documented reason
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-01'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-02'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-03'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-04'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-05'
flutter test test/core/services/p2p_service_impl_test.dart --plain-name 'TC-182-06'
flutter test test/core/services/connectivity_signal_test.dart            # RED: file/adapter absent

# 2. Direct GREEN (after fix) — the whole touched file
flutter test test/core/services/p2p_service_impl_test.dart test/core/services/connectivity_signal_test.dart

# 3. Preservation sentinels (must stay green) — record each suite's baseline count first, expect 0 failures
./scripts/run_test_gates.sh 1to1          # p2p_service_impl_test.dart lives here (run_test_gates.sh:52)
./scripts/run_test_gates.sh transport     # TRANSPORT_TESTS — re-warm/reconnect smokes

# 4. Named gate for the touched subsystem (host floor)
./scripts/run_host_test_gates.sh core-host-all   # expect: 0 failures (baseline + 7 new tests)

# 5. Simulator/device discovery (proof must classify, not orphan)
./scripts/check_reliability_simulation_discovery.sh    # connectivity_restore_inbox_drain_proof_test.dart MUST be classified
# Device-proof TC-182-08 is MANUAL physical-device (see Device/Relay Proof Profile)

# 6. Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- **Expected RED:** TC‑182‑01..07 before the fix (documented reasons above).
- **Pre-existing dirty (NOT this work):** `info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/presentation/widgets/letter_card.dart` (modified before this session), plus the `graphify-arch/**` arch‑graph refresh artifacts. Do not revert these.
- **Environment blocker (NOT product):** absence of two physical devices blocks TC‑182‑08 only; it is not a product failure — the host floor (TC‑182‑01..07) fully proves the wiring‑given‑event.
- **Scope drift (BLOCKING):** any failure outside `p2p_service_impl.dart` / `main.dart` / the new connectivity adapter / the new tests — stop and replan.

## Done Criteria
- [ ] RED added first (TC‑182‑01..07), each failed for the expected reason.
- [ ] Mutation‑verified (each fix row has a named re‑red revert).
- [ ] Direct GREEN + preservation sentinels (`1to1`, `transport`, FDC‑04 re‑warm, health‑check poll) + `core-host-all` pass.
- [ ] No migration (no schema change) — N/A by design (transient trigger; durable persistence is the existing `InboxStagingRepository`).
- [ ] OS‑boundary path proven on a physical device (TC‑182‑08), not a fake.
- [ ] New host tests auto‑globbed/`ONE_TO_ONE_TESTS`‑covered; device‑proof `classify_path` case added & shows in discovery.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do **not** remove, replace, or re‑tune the 30s health‑check poll drain (`:3866`) — it stays as the backstop.
- Do **not** call the private `_drainOfflineInbox()` from `onNetworkChanged` — use the **public** `drainOfflineInbox()` so the 141 defer + migration gate apply.
- Do **not** re‑introduce `inbox:retrieve`/`_retrieveInboxPage` (the destructive read removed by Report 48).
- Do **not** change FDC‑04 re‑warm semantics, or move the re‑warm out from behind the `:2673` peer guard.
- Do **not** add presence‑on‑connectivity here (owned by 181).

## Accepted Differences / Intentionally Out Of Scope
- **Presence re‑publish on connectivity** — could ride the same handler, but is owned by the 181 presence‑lifecycle wiring; not added here.
- **`activePeerId:` production wiring** — if not cleanly in scope at `main.dart:2206`, the re‑warm half may ship in a follow‑up; the **drain** (the actual bug fix) is peer‑independent and ships now.
- **Option B native channel** — only if `connectivity_plus` proves too chatty/unreliable on device; same `Stream<void>` contract, so no test‑surface change.

## Dependency Impact
- Completes the FDC‑04 "bounded follow‑up" the source comment (`p2p_service_impl.dart:172‑175`) explicitly anticipated ("until the OS source is wired"). Once `networkChangeSignal` is non‑null in production, the previously‑inert re‑warm path (TC‑04‑07/08/16) also becomes live — which is why TC‑182‑03 locks "drain + re‑warm both fire."

## Reviewer Findings
Sufficiency self‑check (Step 4) passed: every behavior maps to ≥1 tiered test with a re‑red mutation and a literal gate; the destructive‑path, migration‑gate, debounce, lifecycle‑defer, and OS‑boundary blind spots each have a row; the host floor is mutation‑verifiable on an existing harness; the one genuinely OS‑only assertion is a named device‑proof (not faked). Thin spot honestly flagged: the production `main.dart` wiring itself has no clean host test (composition‑root) — it is proven by TC‑182‑08 (device) and indirectly by TC‑182‑01..06 proving the seam behaves once a stream is injected.

## Arbiter Decision
Structural blockers: none. **Resolved:** connectivity source = **Option A `connectivity_plus`** (user‑confirmed 2026‑06‑30); Option B native is the device‑evidence fallback only. Remaining open detail: whether `activePeerId:` ships in the same PR (drain half is the bug fix and is peer‑independent — re‑warm wiring may follow). Accepted differences: presence‑on‑connectivity (181), re‑warm wiring follow‑up. Hand off to execution.

## Final Execution Verdict
**Verdict: ACCEPTED (host floor landed + mutation-verified; OS-source half wired, device-proof deferred to rig).**

**Files changed:**
- `lib/core/services/p2p_service_impl.dart` — `onNetworkChanged` now emits `P2P_SERVICE_NETWORK_CHANGE_DRAIN_BEGIN` + `unawaited(drainOfflineInbox())` after the 5s flap floor, before the active-peer guard.
- `lib/core/services/connectivity_signal.dart` (NEW) — `connectivityRestoredSignal()` / `restoredEdges()` adapter mapping `connectivity_plus` → `Stream<void>` on restored edges only.
- `lib/main.dart:2206` — passes `networkChangeSignal: connectivityRestoredSignal()` (the FDC-04 hook is now live in production).
- `pubspec.yaml` — `connectivity_plus: ^6.1.0` (resolved 6.1.5).
- `test/core/services/p2p_service_impl_test.dart` — group `182 connectivity-restore inbox drain` (TC-182-01..06).
- `test/core/services/connectivity_signal_test.dart` (NEW) — TC-182-07 (+07b/07c).
- `integration_test/connectivity_restore_inbox_drain_proof_test.dart` (NEW) — TC-182-08 device-proof (skips silently off-rig).
- `scripts/check_reliability_simulation_discovery.sh` — `classify_path()` case for the proof (classified `1to1`, Unclassified: 0).

**Tests run (+counts):** TC-182-01..06 RED→GREEN (+6); TC-182-07/07b/07c (+3); full `p2p_service_impl_test.dart` 118/118; `run_test_gates.sh 1to1` +1398 (the −16 are pre-existing dirty-tree failures in the conversation feature, proven by stash-revert → 345/345). `flutter analyze` 0 new; `git diff --check` clean.

**Blocking:** none.

**QA verdict:** Host floor is complete and mutation-verified (every RED failed for the documented reason on HEAD; the single `onNetworkChanged` edit flips all six GREEN; reverting it re-reds). The durable-path (TC-182-02), migration-gate (TC-182-05), debounce (TC-182-04), roster-wide (TC-182-01), no-regression (TC-182-03), and not-started-defer (TC-182-06) invariants all hold.

**Non-blocking follow-ups (owner):**
- **Device-proof TC-182-08** (rig owner) — run on a 2-phone rig with `--dart-define=CONNECTIVITY_DRAIN_DEVICE_PROOF=1`; closes the OS-source-emission leg (host fakes cannot prove `NWPathMonitor`/`ConnectivityManager` fires on a foreground toggle).
- **`activePeerId:` re-warm wiring** (this codebase) — `ActiveConversationTracker` is constructed after the `P2PServiceImpl` build site, so the peer-scoped re-warm half stays dormant; reorder or late-bind in a follow-up (the drain — the actual bug fix — is peer-independent and now live).
- **iOS `Info.plist` / Android manifest** — verify `connectivity_plus` needs no extra capability (it does not on iOS/Android for path monitoring); confirm at native build time.
```
```
