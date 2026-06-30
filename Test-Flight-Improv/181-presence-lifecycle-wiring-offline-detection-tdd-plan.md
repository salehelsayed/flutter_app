# 181 - Presence lifecycle wiring: connect the dormant `SetPresenceUseCase` producer to `_MyAppState` so the send-side offline short-circuit can fire  (Bug)

Status: awaiting-review
Spec: Test-Flight-Improv/181-presence-lifecycle-wiring-offline-detection-spec.md

> **One-line:** the producer (`SetPresenceUseCase`), the write transport (`relay:presence_set` → native → Go → relay ladder), and the send-side consumer (the `unreachable` short-circuit) **all already exist and are tested**. The single missing wire is the app-lifecycle trigger. This plan adds exactly one production edit (`lib/main.dart`) plus the tests that lock it, and reuses the already-green producer/consumer coverage.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-30 | Evidence Collector | set_presence_use_case.dart, p2p_service.dart/_impl, send_chat_message_use_case.dart:704-783, main.dart:3611-4476, handle_app_paused.dart, GoBridge.swift/.kt, go_bridge_client.dart, presence_store.go, run_test_gates.sh, set_presence_use_case_test.dart, send_presence_emphasis_test.dart, main_deferred_push_rearm_wiring_test.dart | Verdict: pure wiring; producer+consumer already host-tested; native dispatch present (2026-06-27 "absent" caveat is stale) | hand to Planner |
| 2026-06-30 | Planner | (above) | Only edit = main.dart; new RED-first test = _MyAppState wiring lock; map already-covered cases | emit matrix + plan |
| 2026-06-30 | Reviewer (sufficiency) | this plan | see Reviewer Findings | — |
| 2026-06-30 | Arbiter | this plan | see Arbiter Decision | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| | contract extraction (git status --short) | | | scope confirmed | |
| | RED tests added | | (cmd proving they FAIL) | RED for expected reason | |
| | implementation | | | scoped files only | |
| | direct GREEN | | (exact cmd) | reds now green | |
| | preservation GREEN | | (exact cmd) | sentinels green | |
| | named gates | | (exact cmd + counts) | gate green | |
| | QA (independent) | | (re-run cmds) | blocking: none/list | verdict |

## Source Of Truth
- Spec / intent: `Test-Flight-Improv/181-presence-lifecycle-wiring-offline-detection-spec.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose); host aggregates delegate to `scripts/run_host_test_gates.sh`
- Discovery/registration: `scripts/run_test_gates.sh completeness-check` (every test file must be classified by `classify_path()`)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (this reuses the spec's NN=181)

## Session Classification
implementation-ready.

## Exact Problem Statement

The app ships a complete, host-tested presence self-publish stack (FDC-08 read side + FDC-09 write side) whose purpose is to let the relay tell a *sender* whether a target peer is reachable, so an offline-bound 1:1 message routes straight to durable custody (and the relay's store-driven push-to-wake) instead of waiting for every live transport leg to time out. Every layer is wired **except** the lifecycle trigger: `SetPresenceUseCase` is referenced nowhere in production. Because no peer publishes `foreground`/`background`, the relay `Lookup` ladder never returns `unreachable`, and the committed send-side short-circuit (`send_chat_message_use_case.dart:776-783`) is permanently inert. User-visible effect: a 1:1 text to a backgrounded/offline peer the sender has no live connection to settles to the durable inbox only after the full transport race times out (~1.9 s observed on device), with no early offline signal and no front-loaded push-to-wake.

**What must improve:** the app must call `SetPresenceUseCase.onForegrounded()` on resume and `onBackgrounded()` on pause/hidden, and dispose it on teardown, so a real peer announces `background` and the already-tested send-side `unreachable` short-circuit fires for `unknownPresence`-true sends.

**What must stay unchanged (→ preserved-green sentinels):** the producer behavior (`set_presence_use_case_test.dart`), the send-side consumer behavior (`send_presence_emphasis_test.dart` C5/C6/C7), the bounded FDC-06 pause window (`handle_app_paused_test.dart`, `app_lifecycle_pause_integration_test.dart`), the `P2PService` base interface (no `setPresence` added → the ~31 fakes), and the send path generally (`send_chat_message_use_case_test.dart`).

## Root Cause (verify → refute confirmed)

`SetPresenceUseCase` (`lib/features/push/application/set_presence_use_case.dart:24-101`) is built and unit-tested but **constructed/called nowhere in production** — a repo-wide grep finds it only in its own file and `test/features/push/application/set_presence_use_case_test.dart`. `_MyAppState` (`lib/main.dart:3611`), the single central `WidgetsBindingObserver`, dispatches `resumed→_onResumed()` (`:4478`), `paused||hidden→_onPaused()` (`:4414`), `detached→_onDetached()` (`:4403`) but none of these touch presence. With no producer, the relay `Lookup` ladder (`go-relay-server/presence_store.go:122-177`, Rule 1 at `:149`) never sees a fresh `selfState`, so it never returns `unreachable`; the committed consumer short-circuit (`lib/features/conversation/application/send_chat_message_use_case.dart:776-783`, commit `a32454c2`) is therefore dormant. Confirmed first-hand against the clean working tree this session.

**Refuted / do-NOT-re-introduce:**
- *"Native MethodChannel dispatch for `relay:presence_set/get` is absent until a gomobile rebuild"* (FDC-09 memo, 2026-06-27) — **STALE/refuted.** The cases exist in committed source: `ios/Runner/GoBridge.swift:129-133` (`relayPresenceSet→BridgePresenceSet`), `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt:118-120` (`relayPresenceSet→GoMknoon.presenceSet`), Dart map `go_bridge_client.dart:133`, Go `bridge_presence.go:78`. Do not plan a rebuild as a code-gap prerequisite (a routine `make all`+`pod install` only ensures the *installed device binary* carries the symbols — a build-freshness step for the device-proof, not a code change).
- *"The originally-observed WiFi-off device send will be fixed by this wiring"* — **refuted/out-of-scope.** That send had `unknownPresence==false` (sender held a stale `/p2p-circuit` to the target), so it bypassed the presence block entirely. Wiring presence does not change it (see Scope Guard + TC-181-50).
- *"This needs a new presence mechanism / a choice between SetPresenceUseCase and FDC-09"* — **refuted.** They are one mechanism; `SetPresenceUseCase` *is* the FDC-09 §6.3 lifecycle driver (docstring `set_presence_use_case.dart:6-11`). Do not re-implement the write path.

## Real Scope

**In scope:** one production edit — `lib/main.dart`: add a `SetPresenceUseCase` field on `_MyAppState`, construct it from `widget.p2pService` (concrete `P2PServiceImpl`, which implements `RelayPresenceSet`), call `onForegrounded()` **unawaited** from `_onResumed()`, `onBackgrounded()` from `_onPaused()`, and `dispose()` from `_MyAppState.dispose()`. Plus tests locking this wiring.

**Out of scope (owned elsewhere):**
- Stale-circuit-connected sends (`unknownPresence==false`) — **Known Limitation**, follow-up session (would require changing connection-classification / `unknownPresence` — explicitly forbidden here).
- A dedicated background-task assertion for reliable transient-background publishing — deliberately **best-effort** per locked decision (no new bg assertion).
- The write transport, relay ladder, move-gate, send-side consumer/short-circuit — all exist + tested; untouched.
- Posts location-presence subsystem (`PostPresenceListener` / `ContactPresenceSnapshotRepository` / `publishPostPresenceUpdate`) — unrelated; untouched.

## Files To Inspect Next
- Production (entry/seam): `lib/main.dart` — `_MyAppState` (`:3611`), `initState` (`:3640` region), `_onResumed` (`:4478`), `_onPaused` (`:4414`), `_onDetached` (`:4403`), `dispose` (`:4327`). The ONLY file edited.
- Producer (read-only; do not edit): `lib/features/push/application/set_presence_use_case.dart`.
- Interface invariant (read-only; assert unchanged): `lib/core/services/p2p_service.dart` (`P2PService` base vs `RelayPresenceSet` at `:94-101`).
- Direct tests: `test/features/push/application/set_presence_use_case_test.dart`, `test/features/conversation/application/send_presence_emphasis_test.dart`, and the wiring-precedent `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart`.
- Dependency-only context: `lib/core/lifecycle/handle_app_paused.dart` (pause window), `lib/core/services/p2p_service_impl.dart:4879` (`setPresence`).

## Existing Tests Covering This Area
- `set_presence_use_case_test.dart` — producer unit: **TC-09-04** (foreground once + `PRESENCE_SELF_PUBLISH`), **TC-09-05** (background best-effort non-blocking, `bestEffort:true` discriminator), **TC-09-06** (heartbeat refresh + cancel-on-pause via `fakeAsync`), **TC-09-08** (unsupported → skip, no retry). EXISTS — covers spec TC-181-01/02/03/04/06. Auto-globs into `feature-host-all`.
- `send_presence_emphasis_test.dart` — consumer host-integration via `_PresenceFake extends FakeP2PService implements RelayPresenceLookup`: **C5** (reachable keeps lazy inbox), **C6** (`unreachable` → `CHAT_MSG_PRESENCE_INBOX_FIRST` + inbox-done-before-live ordering), **C7** (wrong-reachable hint still deposits). EXISTS — covers spec TC-181-30/31 and TC-181-32(reachable). **Already in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:102`)** → runs in the curated `1to1` gate. Auto-globs into `feature-host-all`.
- Move-gate (blocked) is locked at the impl layer (`p2p_service_impl_presence_cache_test.dart`, TC-09-07) and the unknown-action→unsupported mapping at the bridge layer (`p2p_bridge_client_presence_test.dart`, TC-09-08) — per `set_presence_use_case_test.dart:10-15`. EXISTS — covers spec TC-181-40/41 at their real tiers.
- **MISSING coverage gaps (this plan fills):**
  1. **The lifecycle wiring itself** — nothing asserts `_MyAppState` constructs/dispatches/disposes `SetPresenceUseCase`. (spec Group B/C, G-60/61) — **NEW** `test/core/lifecycle/main_presence_lifecycle_wiring_test.dart`.
  2. `dispose()` stops the heartbeat with **no further calls** (spec TC-181-05) — **NEW** case in the producer test.
  3. `blocked`/`failed` results never throw (spec TC-181-07) — **NEW** case in the producer test.
  4. `unknown` → `EMPHASIS` but **no** `INBOX_FIRST` (spec TC-181-32 unknown leg) — **NEW** case in `send_presence_emphasis_test.dart`.
  5. Connected peer (`unknownPresence==false`) → **no** presence block (spec TC-181-50, the Known-Limitation negative lock) — **NEW** case in `send_presence_emphasis_test.dart`.
- Wiring-test precedent: `test/core/lifecycle/main_deferred_push_rearm_wiring_test.dart` (TC-164-02) establishes the house pattern — read `lib/main.dart` as a string and assert wiring substrings, with behavioral closure deferred to device-proof. The new wiring test follows this exactly.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/core/lifecycle/main_presence_lifecycle_wiring_test.dart`::**TC-181-W1 — `_MyAppState` constructs `SetPresenceUseCase` from the p2p service**
   - Tier: widget/host (source-assertion lock, per the TC-164-02 precedent — pumping full `MyApp` host-side is infeasible).
   - Shape/setup: `final src = await File('lib/main.dart').readAsString();` scope to the `_MyAppState` region; assert `src.contains('SetPresenceUseCase(')` and that its `presenceSetter:` argument is wired from `p2pService` (e.g. `contains('SetPresenceUseCase(')` AND the construction references `widget.p2pService` / `p2pService`).
   - RED on HEAD because: `main.dart` never references `SetPresenceUseCase` (grep-confirmed) → `contains` is false → fails.
   - GREEN after fix asserts: the producer is constructed once from the concrete `P2PServiceImpl` field (no cast, no new interface method).
   - Mutation that re-reds: revert the construction line in `main.dart` → red.
   - Distinct discriminator: assert the wire is `presenceSetter:` (the `RelayPresenceSet` param), NOT a base-`P2PService` method, so it cannot be confused with an interface addition.

2. same file::**TC-181-W2 — resume announces foreground (unawaited)**
   - Tier: widget/host (source-assertion).
   - Shape/setup: scope `src` to the `_onResumed` body; assert it contains a call to `.onForegrounded()` and that the call is **unawaited** (e.g. `contains('unawaited(') ... onForegrounded` OR the call is a bare statement, NOT `await …onForegrounded`). Assert NOT `await ` immediately preceding `onForegrounded()`.
   - RED on HEAD because: `_onResumed` has no presence call.
   - GREEN asserts: resume fires `onForegrounded()` without adding latency to the resume orchestration.
   - Mutation that re-reds: remove the `onForegrounded()` call from `_onResumed` → red. (Second mutation: change it to `await …onForegrounded()` → the unawaited assertion reds.)

3. same file::**TC-181-W3 — pause/hidden announces background**
   - Tier: widget/host (source-assertion).
   - Shape/setup: scope `src` to `_onPaused`; assert it contains `.onBackgrounded()`. (No need to re-test the paused||hidden routing — `didChangeAppLifecycleState:4388-4391` already routes both to `_onPaused`; assert that routing is unchanged by also checking `_onPaused` is still the paused/hidden target.)
   - RED on HEAD because: `_onPaused` has no presence call.
   - GREEN asserts: backgrounding fires the best-effort `onBackgrounded()` publish.
   - Mutation that re-reds: remove the `onBackgrounded()` call from `_onPaused` → red.

4. same file::**TC-181-W4 — teardown disposes the producer (no Timer leak)**
   - Tier: widget/host (source-assertion).
   - Shape/setup: scope `src` to `_MyAppState`'s `dispose()` (after `removeObserver(this)` at `:4328`); assert it contains a `.dispose()` call on the presence use case (e.g. a field like `_setPresenceUseCase.dispose()`).
   - RED on HEAD because: no presence dispose exists.
   - GREEN asserts: the 60 s `Timer.periodic` is cancelled on teardown (no leak across hot-restart/node-reinit).
   - Mutation that re-reds: remove the dispose call → red.

5. same file::**TC-181-W5 — detached does NOT announce background (negative)**
   - Tier: widget/host (source-assertion).
   - Shape/setup: scope `src` to the `_onDetached` body; assert it does **NOT** contain `onBackgrounded`.
   - RED on HEAD because: this passes trivially on HEAD (no presence anywhere) — so it is a **guard lock**, NOT RED-first. It re-reds only if a future edit wrongly adds `onBackgrounded()` to `_onDetached`. (Documented as a regression/negative lock, mutation-verifiable.)
   - GREEN asserts: presence is announced only on the resume/pause edges, never on terminal detach.
   - Mutation that re-reds: add `onBackgrounded()` to `_onDetached` → red.

6. same file::**TC-181-W6 — base `P2PService` interface gains no `setPresence` (the ~31-fakes invariant)**
   - Tier: widget/host (source-assertion).
   - Shape/setup: `final p2p = await File('lib/core/services/p2p_service.dart').readAsString();` isolate the `abstract interface class P2PService` block (substring up to the next top-level `abstract`/`enum`); assert that block does **NOT** contain `setPresence`, while the `RelayPresenceSet` block DOES.
   - RED on HEAD because: passes on HEAD (correct today) — a **guard lock**, not RED-first; re-reds if `setPresence` is ever hoisted onto the base interface.
   - GREEN asserts: wiring uses the concrete `P2PServiceImpl`/`RelayPresenceSet`, never the base interface.
   - Mutation that re-reds: move `setPresence` into `abstract interface class P2PService` → red (and would also break ~31 fakes).

7. `test/features/push/application/set_presence_use_case_test.dart`::**TC-181-05 — `dispose()` stops the heartbeat, no further publishes**
   - Tier: unit (`fakeAsync`).
   - Shape/setup: `onForegrounded()`; `expect(isHeartbeatActive, isTrue)`; `dispose()`; `async.elapse(Duration(seconds: 180))`; record `setter.calls.length` and assert it is unchanged after dispose (only the initial foreground publish) and `isHeartbeatActive` is false.
   - RED on HEAD because: **passes on HEAD** (producer already correct) — coverage lock, not RED-for-this-edit.
   - GREEN asserts: no timer survives dispose.
   - Mutation that re-reds: remove `_stopHeartbeat()` from `SetPresenceUseCase.dispose()` (`:68`) → ticks continue → red.

8. same file::**TC-181-07 — `blocked` and `failed` results never throw**
   - Tier: unit.
   - Shape/setup: `setter.result = PresenceSetResult.blocked`; `await useCase.onForegrounded()` and `await useCase.onBackgrounded()` complete without throwing; repeat with `PresenceSetResult.failed`; assert exactly one publish per call (no retry) and no exception.
   - RED on HEAD because: **passes on HEAD** — coverage lock (the only result currently asserted is `unsupported`).
   - GREEN asserts: non-load-bearing degradation for all non-`published` results.
   - Mutation that re-reds: change `_publish` to rethrow on a non-`published` result → red.

9. `test/features/conversation/application/send_presence_emphasis_test.dart`::**TC-181-32u — `unknown` presence emits EMPHASIS but NOT INBOX_FIRST**
   - Tier: integration (host; reuses the `_PresenceFake` harness).
   - Shape/setup: `_PresenceFake(presence: RelayPresence.unknown, storeInInboxResult: true)`; send; assert `CHAT_MSG_PRESENCE_EMPHASIS{presence:'unknown'}` present AND `CHAT_MSG_PRESENCE_INBOX_FIRST` **absent**; durable inbox still fired (fully-concurrent behavior unchanged).
   - RED on HEAD because: **passes on HEAD** (consumer already correct) — completes the C5/C6 pair with the unknown leg; regression lock.
   - GREEN asserts: only `unreachable` triggers the short-circuit; `unknown` keeps today's behavior.
   - Mutation that re-reds: broaden the consumer guard from `== RelayPresence.unreachable` to include `unknown` (`send_chat_message_use_case.dart:776`) → `INBOX_FIRST` appears → red.
   - Distinct discriminator: assert `CHAT_MSG_PRESENCE_EMPHASIS` present AND `CHAT_MSG_PRESENCE_INBOX_FIRST` absent (distinguishes the two same-custody paths by event, not by deposit count).

10. same file::**TC-181-50 — connected peer (`unknownPresence==false`) does NOT enter the presence block (Known-Limitation lock)**
    - Tier: integration (host).
    - Shape/setup: configure the fake so `isConnectedToPeer(target)`/`isAlreadyConnected` is true (extend `_PresenceFake`/`FakeP2PService` with a connected-peer flag if not already supported); send; assert **no** `CHAT_MSG_PRESENCE_EMPHASIS` is emitted (the `if (unknownPresence)` block is skipped) and `lookupRelayPresence` is **not** called (`presenceLookupCount == 0`).
    - RED on HEAD because: **passes on HEAD** (the block is already skipped for connected peers) — documents/locks the out-of-scope stale-circuit boundary; it re-reds only if a future change makes a connected peer enter the presence block.
    - GREEN asserts: presence wiring does not change connected-peer sends — the boundary the device evidence captured.
    - Mutation that re-reds: change `unknownPresence` to drop the `!isConnectedToPeer` term (`send_chat_message_use_case.dart:704-707`) → connected peer enters the block, emits EMPHASIS → red.

11. **TC-181-33 / TC-181-34 / TC-181-51 — device-proof** (see Device/Relay Proof Profile). Two-phone rig; **PROD-CRITICAL** end-to-end leg. Not a host gate.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-181-01 | foreground publish once | unit | set_presence_use_case_test.dart::TC-09-04 (EXISTS) | covered (no new RED) | drop initial `_publish('foreground')` | `flutter test test/features/push/application/set_presence_use_case_test.dart` | AUTO (feature-host-all glob) |
| TC-181-02 | heartbeat refresh | unit | set_presence_use_case_test.dart::TC-09-06 (EXISTS) | covered | drop `_startHeartbeat` tick | same file | AUTO (feature-host-all) |
| TC-181-03 | bg cancels heartbeat + publishes | unit | set_presence_use_case_test.dart::TC-09-05/06 (EXISTS) | covered | drop `_stopHeartbeat` in onBackgrounded | same file | AUTO (feature-host-all) |
| TC-181-04 | bg non-blocking | unit | set_presence_use_case_test.dart::TC-09-05 (EXISTS) | covered | `await` the bg publish | same file | AUTO (feature-host-all) |
| TC-181-05 | dispose stops timer | unit | set_presence_use_case_test.dart::TC-181-05 (NEW) | passes on HEAD — coverage lock | remove `_stopHeartbeat()` from `dispose()` | same file | AUTO (feature-host-all) |
| TC-181-06 | unsupported no-retry | unit | set_presence_use_case_test.dart::TC-09-08 (EXISTS) | covered | retry on unsupported | same file | AUTO (feature-host-all) |
| TC-181-07 | blocked/failed never throw | unit | set_presence_use_case_test.dart::TC-181-07 (NEW) | passes on HEAD — coverage lock | rethrow on non-published | same file | AUTO (feature-host-all) |
| TC-181-10 | resume→foreground | widget/host | main_presence_lifecycle_wiring_test.dart::TC-181-W2 (NEW) | `_onResumed` lacks onForegrounded → RED | remove onForegrounded from `_onResumed` | `flutter test test/core/lifecycle/main_presence_lifecycle_wiring_test.dart` | AUTO (core-host-all) **+ append to `ONE_TO_ONE_TESTS`** |
| TC-181-11 | paused→background | widget/host | …::TC-181-W3 (NEW) | `_onPaused` lacks onBackgrounded → RED | remove onBackgrounded from `_onPaused` | same file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-12 | hidden→background | widget/host | …::TC-181-W3 (NEW) — routing via `:4388-4391` | covered by W3 + existing route | break `paused||hidden` routing | same file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-13 | detached does NOT announce | widget/host | …::TC-181-W5 (NEW, negative) | passes on HEAD — guard lock | add onBackgrounded to `_onDetached` | same file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-14 | resume re-arms heartbeat | unit + widget/host | set_presence_use_case_test.dart::TC-09-06 (cancel) + …::TC-181-W2 (resume calls onForegrounded which re-arms) | covered (W2 RED carries the wire) | remove onForegrounded from `_onResumed` | both files | AUTO + ONE_TO_ONE_TESTS |
| TC-181-15 | teardown disposes | widget/host | …::TC-181-W4 (NEW) | `dispose()` lacks presence dispose → RED | remove dispose call | same file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-16 | no stuck state on churn | unit | set_presence_use_case_test.dart::TC-09-06 (EXISTS, fakeAsync churn) | covered | — | same file | AUTO (feature-host-all) |
| TC-181-20 | concrete impl, no new iface method | widget/host | …::TC-181-W1 + TC-181-W6 (NEW) | W1 RED (no construction); W6 guard | W6: hoist setPresence to base iface | wiring file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-21 | ~31 fakes compile unchanged | host suite | core-host-all + feature-host-all compile (no fake edits) | passes on HEAD — locked by W6 + a clean gate run | add setPresence to base iface → fakes fail to compile | `./scripts/run_test_gates.sh feature-host-all` | AUTO |
| TC-181-22 | no new observer | widget/host | …::TC-181-W1 (construction in existing `_MyAppState`) | covered by W1 (wires into `_MyAppState`, no `addObserver`) | add a 2nd `addObserver` for presence | wiring file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-30 | unreachable→INBOX_FIRST | integration | send_presence_emphasis_test.dart::C6 (EXISTS) | covered | narrow consumer guard off unreachable | `flutter test test/features/conversation/application/send_presence_emphasis_test.dart` | AUTO (feature-host-all) + in ONE_TO_ONE_TESTS |
| TC-181-31 | live legs still run after short-circuit | integration | send_presence_emphasis_test.dart::C6 (EXISTS, order assert) | covered | drop the live legs after inbox-first | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-181-32 | reachable/unknown keep behavior | integration | C5 (reachable, EXISTS) + TC-181-32u (unknown, NEW) | reachable covered; unknown is regression lock | broaden guard to include unknown | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-181-33 | backgrounded-peer send commits inbox first (real devices) | **device-proof** | 181 device-proof runsheet::TC-181-33 (NEW) — **PROD-CRITICAL** | n/a (device) | n/a | two-phone rig (see profile) | device-proof runsheet (not a host gate) |
| TC-181-34 | foregrounded peer NOT short-circuited | device-proof | 181 runsheet::TC-181-34 (NEW) | n/a | n/a | two-phone rig | device-proof runsheet |
| TC-181-40 | move-pause blocks announce, harmless | unit (impl) | p2p_service_impl_presence_cache_test.dart::TC-09-07 (EXISTS) + producer TC-181-07 (no-throw) | covered at impl tier | remove move-gate first line | `flutter test test/core/services/p2p_service_impl_presence_cache_test.dart` | AUTO (core-host-all) |
| TC-181-41 | old relay degrades | unit (bridge) | p2p_bridge_client_presence_test.dart::TC-09-08 (EXISTS) + producer TC-09-08 | covered | map unknown-action to error not unsupported | `flutter test test/core/bridge/p2p_bridge_client_presence_test.dart` | AUTO (core-host-all) |
| TC-181-42 | failed publish never blocks a send | integration | send_presence_emphasis_test.dart::C7 (EXISTS, wrong-hint still delivers) + producer TC-181-07 | covered | make presence gate delivery | same file | AUTO + ONE_TO_ONE_TESTS |
| TC-181-43 | no announce spam under churn | unit | set_presence_use_case_test.dart::TC-09-06 (one publish per edge) | covered | publish in a loop | same file | AUTO (feature-host-all) |
| TC-181-50 | connected peer bypasses gate (Known Limitation) | integration | send_presence_emphasis_test.dart::TC-181-50 (NEW, negative) | passes on HEAD — boundary lock | drop `!isConnectedToPeer` from unknownPresence | same file | AUTO (feature-host-all) + ONE_TO_ONE_TESTS |
| TC-181-51 | transient-bg may lose publish (accepted) | unit (best-effort) + device | set_presence_use_case_test.dart::TC-09-05 (non-blocking, EXISTS) + 181 runsheet::TC-181-51 | covered host-side as best-effort; device confirms acceptable loss | await the bg publish | producer file + runsheet | AUTO + device-proof |
| TC-181-60 | pause window not widened | integration | handle_app_paused_test.dart + app_lifecycle_pause_integration_test.dart (preservation) + …::TC-181-W3 asserts onBackgrounded is the unawaited bg call (no new `callBgBegin`) | passes on HEAD; W3 guards no new bg assertion | add a `callBgBegin` around the presence publish | `./scripts/run_test_gates.sh core-host-all` | AUTO (core-host-all) |
| TC-181-61 | detached teardown unchanged | widget/host | …::TC-181-W5 (NEW) | guard lock | announce on detach | wiring file | AUTO (core-host-all) + ONE_TO_ONE_TESTS |
| TC-181-62 | fast paths unchanged | integration | send_chat_message_use_case_test.dart (EXISTS, connected/local fast path) + TC-181-50 | covered | — | `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` | AUTO (feature-host-all) + in ONE_TO_ONE_TESTS |
| TC-181-63 | posts presence untouched | n/a (scope guard) | no edit to posts-presence files; `git diff --name-only` asserts only main.dart + test files changed | n/a | n/a | `git diff --name-only` review in QA | scope-guard check |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability:** the change adds in-memory state (the `SetPresenceUseCase` instance + its 60 s heartbeat `Timer`) on `_MyAppState`. On a fresh mount / hot-restart / cold start, `initState` must reconstruct it and the first `resumed` must re-arm the heartbeat. **Row:** TC-181-W1 (construction is in `_MyAppState` build/initState, so a fresh mount reconstructs it) + TC-181-W4 (old instance disposed on teardown, no leaked timer) + TC-09-06/TC-181-W2 (resume re-arms). Not N/A — explicitly locked.
- **Sibling-surface consistency:** **Justified N/A.** Presence (`foreground`/`background`) is an app-global lifecycle signal, not a per-capability gate (react/attach/quote/voice/retry/delete). There is no sibling capability to apply it to; the send-side consumer already treats every `unknownPresence` 1:1 send uniformly (the matrix locks reachable/unreachable/unknown legs).
- **Destructive-action side-effects:** the only "cleanup" added is `dispose()` cancelling the heartbeat. **Row:** TC-181-05 asserts what is removed (no further publishes after dispose) and TC-181-W4 asserts the wire exists; the producer's degradation cases (TC-181-07) assert delivery/UI is preserved. No disk/DB rows are created or removed by this change.
- **Invariant re-verification under new transitions:** the new `pause→resume` interaction must re-arm the heartbeat that pause cancelled — otherwise after one pause/resume the `foreground` entry stops refreshing and lapses to `unknown`, silently degrading the feature. **Row:** TC-09-06 (cancel-on-pause) + TC-181-W2 (resume calls `onForegrounded()` which re-arms via `_startHeartbeat`). Asserted, not assumed.

## Invariants (locked by tests)
- **INV-1 (wired):** `_MyAppState` constructs `SetPresenceUseCase` from the concrete p2p service and calls `onForegrounded()`/`onBackgrounded()`/`dispose()` on resume/pause/teardown → TC-181-W1/W2/W3/W4.
- **INV-2 (interface purity):** `setPresence` never on the base `P2PService` interface (~31 fakes spared) → TC-181-W6.
- **INV-3 (non-load-bearing):** `blocked`/`unsupported`/`failed` publishes never throw, never gate delivery, never retry-spam → TC-181-07, TC-09-08, C7.
- **INV-4 (consumer activation, not change):** only `unreachable` triggers `CHAT_MSG_PRESENCE_INBOX_FIRST`; reachable/unknown unchanged → C5, C6, TC-181-32u.
- **INV-5 (pause window not widened):** the background publish stays the existing unawaited call with no new `callBgBegin` → TC-181-W3 + preservation of `handle_app_paused_test.dart`.
- **INV-6 (boundary):** a connected peer (`unknownPresence==false`) never enters the presence block → TC-181-50.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every NEW row (the wiring locks W1–W4 are RED-on-HEAD; W5/W6 and the coverage/negative locks are mutation-verified guard locks, flagged as such — they pass on HEAD by design because they protect existing-correct behavior).

## Step-By-Step Implementation Plan
1. Snapshot the tree: `git status --short` (record pre-existing dirty `info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, and the untracked `180-…-spec.md` — do NOT revert/bundle).
2. **Add RED tests first** (`test/core/lifecycle/main_presence_lifecycle_wiring_test.dart` with W1–W6; new producer cases TC-181-05/07; new emphasis cases TC-181-32u/TC-181-50). Run the focused cmds; confirm W1–W4 FAIL on HEAD for the documented reason (no `SetPresenceUseCase` in `main.dart`) and the guard/coverage locks pass.
3. **Implementation (the one seam):** in `lib/main.dart` `_MyAppState`:
   - add a field `late final SetPresenceUseCase _setPresenceUseCase;` (or nullable, matching the file's DI style) constructed from `widget.p2pService` in `initState` (after `addObserver`, alongside the existing service wiring);
   - in `_onResumed()`, add `unawaited(_setPresenceUseCase.onForegrounded());` next to the existing unawaited warm-peer/drain re-prime;
   - in `_onPaused()`, add `_setPresenceUseCase.onBackgrounded();` (its publish is already unawaited internally — do NOT wrap in a new `callBgBegin`);
   - in `dispose()`, after `removeObserver(this)`, add `_setPresenceUseCase.dispose();`.
   - Stop-if: constructing from `widget.p2pService` requires a cast or a new `P2PService` interface method → **replan, do not hack** (the field is concrete `P2PServiceImpl` and already implements `RelayPresenceSet`; if a refactor has changed that, surface it).
4. Rerun direct → preservation → named gates (below). Then `graphify update .` + `./graphify-arch/refresh_arch_graph.sh` (lib/ changed).

## Risks And Edge Cases
- **Double-announce on `paused`+`hidden` in one transition** — `_onPaused` fires for both; iOS typically emits one or the other per backgrounding. Bounded/harmless (best-effort, dedup-on-relay by TTL refresh). Pinned by TC-09-06 (one publish per edge) + manual device observation.
- **Heartbeat leak across hot-restart** — pinned by TC-181-W4 + TC-181-05.
- **Account-move in progress on pause** — `setPresence` returns `blocked`; correct (device must not announce while migrating). Pinned by TC-09-07 (impl) + TC-181-07 (no-throw).
- **Transient app-switch chatter** — best-effort means a publish per background; acceptable (no new bg assertion, no widened window). Pinned by TC-181-W3/INV-5.

## Device/Relay Proof Profile
**requires device for behavioral closure** (the host wiring locks are source-assertion; the end-to-end producer→relay→consumer loop is **PROD-CRITICAL** and proven only on real devices). Create `Test-Flight-Improv/181-presence-lifecycle-wiring-device-proof-runsheet.md`.
- Rig: Pixel 6 `adb -s 21071FDF600CSC`; iPhone 11 `idevicesyslog -u 00008030-001A6D2801BB802E` / `devicectl --device 5763A494-757C-5B37-AC70-3AA2775FBEFF`. TAP-launch the iPhone app. Keep collision iPhones (13/17) off WiFi.
- Build: `flutter build apk --profile --dart-define=FDC_FLOW_LOG=1` (Dart-only ⇒ gomobile cached ⇒ fast). For the device binary to carry presence symbols, ensure the installed build post-dates the committed `GoBridge.*` presence cases (already committed; a routine `make all && pod install` for iOS guarantees it).

> **⚠️ LOAD-BEARING PRECONDITIONS (resolve BEFORE picking up the phones).** Because the host wiring locks are source-assertions, this device-proof is the **only** behavioral verification in the plan — and it silently *cannot observe its signals* unless both setup conditions hold. The same `unknownPresence==false` trap that put the original observation out of scope will make TC-181-33 look "broken" when it is actually "set up wrong."
> 1. **Sender A must hold NO connection to B — not even a relay `/p2p-circuit`** (so `unknownPresence==true` and A enters the presence block). Two recently-chatting same-WiFi peers almost always hold a circuit that can survive B backgrounding. Guarantee it by EITHER (a) using a contact A has **never dialed live this app-run**, OR (b) **cold-restarting A** right before the send so no circuit exists, OR (c) confirming the circuit **tore down** when B backgrounded. **Verify on A's log before sending:** `isConnectedToPeer(B)==false` and no `/p2p-circuit` to B in A's connection set. If A still holds a circuit, the proof is invalid — fix the setup, do not record a failure.
> 2. **Recipient B must have network AT pause time** (e.g. B on cellular *or* WiFi, app backgrounded — **NOT** radio-off). This is the in-scope scenario (spec Scope reason B): a radio-off peer cannot publish `background`, so the relay would return `reachable`/`unknown`, never `unreachable`. **Verify on B's log:** `PRESENCE_SELF_PUBLISH{state:background}` AND that the publish did **not** return `failed`/`blocked`.
> 3. **A and B must not be LAN-discoverable to each other** (else `isLocalPeer==true` skips the block) — keep B off A's shared WiFi for this case.

- **TC-181-33 (PROD-CRITICAL):** with preconditions 1–3 satisfied, A sends 1:1 text to B after B has backgrounded long enough to announce `background`. Expect on A: `CHAT_MSG_PRESENCE_EMPHASIS{presence:unreachable}` → `CHAT_MSG_PRESENCE_INBOX_FIRST`; B receives via relay push-to-wake; A settles to inbox WITHOUT the full ~1.9 s race timeout. **Failure triage:** if A logs **no** `CHAT_MSG_PRESENCE_EMPHASIS`, the block was skipped → re-check precondition 1 (A had a connection/circuit) or 3 (LAN) FIRST; if A logs `EMPHASIS{reachable|unknown}` but no `INBOX_FIRST`, re-check precondition 2 (B did not publish `background` — likely no network at pause).
- **TC-181-34:** B kept foregrounded (heartbeat refreshing `foreground`), preconditions 1+3 still satisfied. A sends. Expect `CHAT_MSG_PRESENCE_EMPHASIS{presence:reachable}`, **no** `INBOX_FIRST`, live delivery.
- **TC-181-51:** background B momentarily with no in-flight sends, suspend before the round-trip; acceptable for `background` not to reach the relay (entry lapses to `unknown` after ~180 s). No crash/stuck state. (Note the symmetric window — see Accepted Differences: a publish that *does* briefly land marks B `unreachable` until re-foreground, costing senders only the front-loaded inbox await while live legs still deliver.)
- Relay defaults if needed: see `/sims` resolver. Do NOT flip any feature-flag default ON.

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# RED (before production edits) — the wiring locks MUST FAIL for the documented reason
flutter test test/core/lifecycle/main_presence_lifecycle_wiring_test.dart
#   expect: TC-181-W1/W2/W3/W4 FAIL (main.dart has no SetPresenceUseCase wire);
#           TC-181-W5/W6 PASS (guard locks protect existing-correct behavior)

# Direct GREEN (after the main.dart edit)
flutter test test/core/lifecycle/main_presence_lifecycle_wiring_test.dart   # expect: all pass (6 tests)
flutter test test/features/push/application/set_presence_use_case_test.dart # expect: 6 pass (4 existing + TC-181-05/07)
flutter test test/features/conversation/application/send_presence_emphasis_test.dart # expect: 5 pass (3 existing + TC-181-32u/TC-181-50)

# Preservation sentinels (must stay green)
flutter test test/core/lifecycle/handle_app_paused_test.dart                 # pause window unchanged
flutter test test/core/lifecycle/app_lifecycle_pause_integration_test.dart   # pause integration unchanged
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart  # send path unchanged

# Named gate(s) for the touched subsystem
./scripts/run_test_gates.sh 1to1          # curated 1:1 gate — includes send_presence_emphasis + (after registration) the wiring lock; expect: <NNN>/<NNN> pass
./scripts/run_test_gates.sh core-host-all # globs the new wiring test; expect: <NNNN>/<NNNN> pass
./scripts/run_test_gates.sh feature-host-all # globs the producer + emphasis extensions; expect: <NNNN>/<NNNN> pass
./scripts/run_test_gates.sh completeness-check  # the new test file MUST classify (test/core/lifecycle/ subdir)

# Hygiene
flutter analyze            # 0 new issues
git diff --check
# Post-change graph refresh (lib/ changed):
graphify update . && ./graphify-arch/refresh_arch_graph.sh
```
> Replace `<NNN>`/`<NNNN>` with the observed baseline counts at execution time (record the pre-edit count, then assert +N).

**Harness registration step (do during implementation):** append `"test/core/lifecycle/main_presence_lifecycle_wiring_test.dart"` to the `ONE_TO_ONE_TESTS` array in `scripts/run_test_gates.sh` (near the FDC-08/12/15/179 entries around line 119), with a one-line comment — `test/core/**` is NOT auto-globbed into the curated `1to1` gate. The producer/emphasis extensions need no registration (already auto-globbed; `send_presence_emphasis_test.dart` is already in `ONE_TO_ONE_TESTS:102`).

## Known-Failure Interpretation
- **Expected RED:** TC-181-W1/W2/W3/W4 before the `main.dart` edit.
- **Guard/coverage locks** (TC-181-W5/W6, TC-181-05/07, TC-181-32u, TC-181-50): pass on HEAD by design (they protect existing-correct behavior); each is mutation-verified by the named revert.
- **Pre-existing dirty:** `info.plist`, `ios/Runner.xcodeproj/project.pbxproj`, untracked `Test-Flight-Improv/180-…-spec.md` — leave; do not bundle.
- **Environment blocker (NOT product):** absence of the two-phone rig blocks only TC-181-33/34/51 (device-proof), not the host gates.
- **Scope drift (BLOCKING):** any failure outside `lib/main.dart` + the named test files, or any edit to the producer/consumer/relay/interface, or to the posts-presence subsystem.

## Done Criteria
- [ ] RED added first (TC-181-W1–W4), failed for the expected reason (no `SetPresenceUseCase` wire in `main.dart`).
- [ ] Mutation-verified (each NEW lock has a named re-red revert).
- [ ] Direct GREEN + preservation sentinels + `1to1`/`core-host-all`/`feature-host-all` gates pass.
- [ ] No `DB v##` change (none needed).
- [ ] PROD-CRITICAL end-to-end leg (TC-181-33) proven on the two-phone rig, not a fake.
- [ ] Wiring test registered (appended to `ONE_TO_ONE_TESTS`) and verified present in a `1to1` gate run; `completeness-check` PASS.
- [ ] `flutter analyze` 0 new; `git diff --check` clean; no Scope Guard violations; graph refreshed.

## Scope Guard (hard "Do not")
- Do NOT edit the producer (`set_presence_use_case.dart`), the write path, the bridge command, the relay ladder, the move-gate, or the send-side consumer/short-circuit — all exist + tested.
- Do NOT add `setPresence` to the base `P2PService` interface (breaks ~31 fakes) — wire the concrete `P2PServiceImpl`.
- Do NOT add a new `WidgetsBindingObserver` — use the existing `_MyAppState`.
- Do NOT add a dedicated background-task assertion / widen the FDC-06 pause window (best-effort is the locked decision).
- Do NOT touch the connection-classification / `unknownPresence` definition (the stale-circuit case is a separate session).
- Do NOT touch the posts location-presence subsystem.
- Do NOT change the `{'foreground','background'}` vocabulary or add a peerId to the payload.

## Accepted Differences / Intentionally Out Of Scope
- **Stale-circuit-connected sends** (`unknownPresence==false`) — **out-of-scope reason A:** the exact originally-observed device case is NOT fixed here — locked as a Known Limitation by TC-181-50; a follow-up session owns any connection-classification change.
- **No-network / radio-off peers** — **out-of-scope reason B (independent of A):** this mechanism only reports `unreachable` for a peer that backgrounded its app **while still having network at pause time** (so `onBackgrounded()`'s publish reached the relay). A genuinely offline/radio-off peer cannot publish `background`, so the relay returns `reachable`/`unknown`, never `unreachable`. Fixing reason A alone would therefore still NOT resolve the observed Wi-Fi-off report. Detecting a peer that loses network while foregrounded (or after its announce-TTL lapses) needs **relay-side connection-drop detection** — a separate follow-up. (This is why the device-proof preconditions require B to have network at pause time.)
- **Transient-background reliability** (best-effort by decision, two-sided): (i) a quick background with no in-flight sends may **lose** the publish (TC-181-51) — acceptable (~180 s self-TTL → `unknown`); (ii) a transient background whose publish **briefly lands** marks B `unreachable` until re-foreground re-publishes `foreground` — a short window where senders front-load the inbox await (~100–400 ms). Window (ii) is acceptable because `unreachable` is **not** inbox-only: it commits the durable copy first and **still runs every live leg** (locked by TC-181-31 / C6), so the message delivers live regardless. A producer-side re-foreground debounce is the lever if (ii) is ever worth eliminating — it would edit the producer, so it is **separate scope**.

## Dependency Impact
- Any future "push-to-wake on known-offline" or offline-presence UI depends on this wire, because it is the only thing that makes the relay emit `unreachable` to senders. Until this lands, the FDC-08 consumer and the FDC-09 transport are inert in production.

## Reviewer Findings
Sufficiency: every spec TC-181-XX maps to ≥1 tiered row (matrix has zero empty cells). The single production edit (`main.dart`) is RED-first and mutation-verified by TC-181-W1–W4. The PROD-CRITICAL end-to-end leg is named (TC-181-33, device-proof) and not faked. Preservation sentinels and literal gates with `+N` count guidance are present. Coverage/negative/guard locks that pass on HEAD are honestly flagged (not RED-first) with their re-red mutations. Harness registration is concrete (auto-glob + one explicit `ONE_TO_ONE_TESTS` append) and `completeness-check` is included. No `DB v##`. Blind-spot sweep done with one justified N/A (sibling-surface) and three locked rows.

## Arbiter Decision
Structural blockers: none. The plan is implementation-ready: one scoped file edit, a RED-first wiring lock following the established TC-164 precedent, and reuse of already-green producer/consumer coverage. Deferred details: the literal gate counts (`<NNN>`) to be filled from the pre-edit baseline at execution. Accepted differences: stale-circuit case + best-effort transient-background loss, both test-locked as boundaries. Hand off to execution.

## Final Execution Verdict
Verdict: (pending execution) | Files changed: lib/main.dart (+ scripts/run_test_gates.sh registration) + 1 new test file + 2 extended test files + 1 device-proof runsheet | Tests run (+counts): (fill at execution) | Blocking: (fill) | QA verdict: (fill) | Non-blocking follow-ups (owner): stale-circuit `unknownPresence` broadening (future session).
