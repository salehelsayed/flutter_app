# 145 - 1:1 Notification-Tap: non-blocking route + "catching up" affordance + drain telemetry  (Feature Improvement)

Status: IMPLEMENTED host-green (2026-06-23) — uncommitted on `new-feed`
Spec: free-text intent (no formal spec) — derived from `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md` (v2)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-23 | Evidence Collector | prepare_notification_open_use_case.dart, notification_route_dispatch.dart, app_root_notification_open.dart, conversation_wired.dart, conversation_screen.dart, notification_tap_timing.dart, flow_event_emitter.dart, p2p_service_impl.dart, run_test_gates.sh, existing test inventory | All 3 anchors verified in source; no DB migration; all behaviors host-testable | Build matrix |
| 2026-06-23 | Planner | tier-matrix.md, plan-template.md | 16 TCs across unit/widget/host-telemetry; 1 harness-array recommendation | Emit plan |
| 2026-06-23 | Reviewer (sufficiency) | sufficiency-checklist.md | zero-empty-cell matrix; each fix mutation-verified | — |
| 2026-06-23 | Arbiter | — | host-only closure; device verify = non-blocking follow-up | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-23 | contract extraction (git status --short) | — | baseline snapshot matches plan; new-feed dirty (l10n + gates pre-dirty) | scope confirmed | scout seams |
| 2026-06-23 | scout (workflow, 6 agents) | all seams | exact line numbers + harness shapes extracted; all 3 anchors verified in source | seams match plan (minor drift) | RED-first |
| 2026-06-23 | RED tests added | use-case/screen/wired/benchmark/p2p tests | TC-01 timeout, TC-02 failed+wrong event, TC-06..09 compile-err, TC-10/13 runtime, TC-14 null fields | RED for documented reasons | implement |
| 2026-06-23 | implementation | 5 prod files + 3 arb + gen-l10n + run_test_gates.sh | Change(1) fire-and-forget; Change(2) affordance+l10n; Change(3) live-timing+drainMs+retrieve/ack/replayMs | scoped files only | GREEN |
| 2026-06-23 | direct GREEN | — | prepare 7, benchmark 5, p2p 78, screen 70, wired 91 — all pass | reds now green | preservation |
| 2026-06-23 | preservation GREEN | — | **1to1 1113/1113**; core-host-all notif dispatch/matrix/app-root 54 + p2p green; NT1-5 green | sentinels green (pre-existing fails isolated) | gates+hygiene |
| 2026-06-23 | named gates + hygiene | scripts/run_test_gates.sh | wired test added to ONE_TO_ONE_TESTS; analyze 0-new (only pre-existing :504 lint); git diff --check clean; l10n regen clean | gate green | QA |
| 2026-06-23 | mutation-verify | — | latch removed → TC-12b sees 2 (red); restored → 1 (green) | latch load-bearing | QA review |
| 2026-06-23 | QA (independent, workflow) | — | 3-lens adversarial review + verify in progress | blocking: pending | verdict |

**Pre-existing failures (NOT 145, confirmed out-of-scope):**
- `benchmark` gate: `benchmark_routing_paths_test.dart` R8 + `send_path_budget_hard_gate_test.dart` NET-REL-05 (send-path routing; relay→inbox / delivered→inboxed). Proven pre-existing by stashing my `p2p_service_impl.dart` change and re-running — they still fail (+18 -2). My NT1-NT5 all pass.
- `core-host-all` gate: `intro_db_helpers_test.dart` (`'pending'→'expired'`, date-sensitive intro-expiry relative to 2026-06-23). I touched zero intro/DB code; notification dispatch/matrix/app-root (TC-05) + p2p all green.

## Source Of Truth
- Spec / intent: inline below + `Test-Flight-Improv/notification-tap-to-message-load-delay-investigation.md`
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh` (NOT used — no sim/device rows)
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (next-free = 145)

## Session Classification
implementation-ready

---

## Exact Problem Statement

When a user taps a 1:1 message notification, the message takes "a few seconds" to appear, which reads as a buggy/stuck app. The investigation report isolated three independently-shippable contributors in scope here:

1. **Routing is blocked on a relay drain.** `prepareNotificationOpen` for the `conversation` kind does `await drainOfflineInbox()` (`lib/features/push/application/prepare_notification_open_use_case.dart:29`), and the dispatcher awaits this `onBeforeRouteTarget` hook **before** pushing the conversation screen (`lib/core/notifications/notification_route_dispatch.dart:21-22`; the app-root variant `routeRemoteNotificationOpenWithResult` in `lib/core/notifications/app_root_notification_open.dart:70-71`). On warm resume this delays the screen from even appearing by up to `foregroundInboxTimeout = 3s` (`lib/core/services/p2p_service_impl.dart:252`). The conversation screen already self-heals via its own `unawaited(_drainAndReloadOnce('notif_tap', …))` (`conversation_wired.dart:530-531`), so the pre-route await is redundant for the conversation kind.

2. **No progress affordance during the screen's drain.** The flag `_drainReloadInFlight` exists (`conversation_wired.dart:1165`) but is read/written only inside `_drainAndReloadOnce` (`:1183/1187/1221`) and is **never threaded into `build()`/`ConversationScreen`** — so during the relay round-trip the user sees a static stale list with no indication anything is happening.

3. **Telemetry fires at the wrong milestone and has no durations.** `NOTIFICATION_TAP_TO_MESSAGE_TIMING` (`lib/core/utils/notification_tap_timing.dart`) is emitted at the **stale-history** render (`conversation_wired.dart:512/1149`), not the post-drain render that surfaces the new message; `CONV_FL_NOTIF_DRAIN_REFETCH` (`conversation_wired.dart:1208`) carries only before/after **counts**; the relay round-trips and replay are untimed.

**What must improve:** (1) the conversation screen is pushed without waiting on the relay drain; (2) a non-intrusive "catching up…" affordance is visible while the screen's notification/resume drain is in flight; (3) additive telemetry captures the post-drain ("live") render milestone and per-segment drain durations.

**What must stay unchanged (→ preserved-green sentinels):** group-kind targeted drain stays awaited; contactRequest/intros drains stay awaited; the dispatcher's prepare-before-route ordering; the existing stale-render `NOTIFICATION_TAP_TO_MESSAGE_TIMING` event; the existing notif-tap/resume drain+coalesce behavior of `_drainAndReloadOnce`; the already-active suppression path (relies on the mounted screen's resume drain).

## Root Cause (verify → refute confirmed)
- **(1)** `prepare_notification_open_use_case.dart:25-30` — `conversation` shares one fall-through `await drainOfflineInbox()` branch with `contactRequest` and `intros`; `notification_route_dispatch.dart:21-22` / `app_root_notification_open.dart:70-71` await `onBeforeRouteTarget` before `onRouteTarget`. **Verified in source.** Refute check: is the screen-side drain sufficient on its own? Yes — `conversation_wired.dart:530-531` fires `_drainAndReloadOnce('notif_tap')` whenever `notificationTappedAt != null`, and the already-active path relies on the resume drain (`:4027`). So dropping the pre-route await for `conversation` does not lose the message.
- **(2)** `conversation_wired.dart:1165` flag is local to `_drainAndReloadOnce`; `build()` at `:4043-4112` forwards `initialLoadDone/isLoadingMore/isSending` but not the drain flag. **Verified.** The only list spinner is the older-pagination `isLoadingMore` row (`conversation_screen.dart` loading-indicator item), which is unrelated.
- **(3)** `notification_tap_timing.dart:14` measures `now - tappedAt` at the stale render; `CONV_FL_NOTIF_DRAIN_REFETCH` details = `{trigger, before, after}` (`conversation_wired.dart:1211-1215`); `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` details = `{staged, replayed, note}` (`p2p_service_impl.dart:1679-1688`) — no durations. **Verified.**

Refuted / do-NOT-re-introduce:
- "The cold `getInitialMessage` screen-drain early-returns on `!isStarted`" — **false** (report v2): that route dispatches after `startP2PNode()` succeeds, so the screen-drain is a real started-path drain. Do not plan logic that assumes the screen-drain no-ops on cold launch.
- "Only page 1 is awaited" — confirmed true; do not assume a single drain surfaces a message beyond inbox page 1 (it lands via the background continuation). Out of scope here.
- A **release-safe production FlowEvent sink** (flow events are `kDebugMode`-gated, `flow_event_emitter.dart:6`) — explicitly OUT of scope (see Accepted Differences). This plan makes the telemetry debug/test-observable and ready to attach.

## Real Scope
**In scope:**
- Change (1): split `conversation` out of the shared drain branch in `prepareNotificationOpen`; make it fire-and-forget with swallowed+logged errors.
- Change (2): add `isSyncingNewMessages` bool to `ConversationScreen`; render a thin keyed banner between the upload-progress banner and the message body (outside the ListView); thread a `setState`-backed flag from `_drainAndReloadOnce`. Add `conversation_catching_up` l10n key (en/ar/de).
- Change (3): add `emitNotificationTapLiveRenderTiming` + `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING`; emit it once per notif-tap (distinct one-shot latch); add `drainMs` to `CONV_FL_NOTIF_DRAIN_REFETCH`; add `retrieveMs`/`ackMs`/`replayMs` to `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS`; optionally tag existing/new tap-timing events with `milestone: 'stale_render' | 'live_render'`.

**Out of scope (owning work):**
- Production analytics sink for flow events → future telemetry session.
- Push-prefetch / persist-from-push (eliminate the drain) → separate large effort.
- Parallelizing the per-message replay / moving the delivery-receipt send off the critical path → separate p2p-performance session.
- Passing `initialMessages` on the notif-tap entry → separate session.
- Any change to group/contactRequest/intros/post drain timing.

## Files To Inspect Next
Production: `lib/features/push/application/prepare_notification_open_use_case.dart`; `lib/features/conversation/presentation/screens/conversation_wired.dart` (`_drainAndReloadOnce` 1179-1224, `_reloadLatestPageForRecovery` 1230-1255, `build` 4043-4112, `_emitNotificationTapTimingIfNeeded` 535-542, `_loadInitialPage` 1122-1163); `lib/features/conversation/presentation/screens/conversation_screen.dart` (constructor 93-…, body Column 270-318); `lib/core/utils/notification_tap_timing.dart`; `lib/core/services/p2p_service_impl.dart` (`_drainOfflineInboxDurably` 1645-1694, `_retrievePendingInboxPage` ~1394-1520); `lib/l10n/app_{en,ar,de}.arb`.
Direct tests: `test/features/push/application/prepare_notification_open_use_case_test.dart`; `test/core/notifications/notification_route_dispatch_test.dart`; `test/core/notifications/app_root_notification_open_test.dart`; `test/core/notifications/notification_route_contract_matrix_test.dart`; `test/features/conversation/presentation/screens/conversation_screen_test.dart`; `test/features/conversation/presentation/screens/conversation_wired_test.dart`; `test/performance/benchmark_notification_tap_to_message_test.dart`; `test/core/services/p2p_service_impl_test.dart` and/or `test/core/inbox/inbox_round_trip_test.dart`; `test/core/utils/flow_event_emitter_test.dart` (sink pattern).
Dependency-only context: `lib/core/notifications/notification_route_dispatch.dart`, `app_root_notification_open.dart`.

## Existing Tests Covering This Area
- `prepare_notification_open_use_case_test.dart` (4 tests) covers per-kind drain invocation — but **NO** test asserts await-vs-fire-and-forget (the gap change 1 fills). In `ONE_TO_ONE_TESTS` (`run_test_gates.sh:63`).
- `notification_route_dispatch_test.dart` asserts `callOrder == ['prepare','route']` (preservation). Auto-glob `core-host-all`.
- `app_root_notification_open_test.dart` covers `routeRemoteNotificationOpenWithResult` + prepare-throws (preservation). Auto-glob `core-host-all`.
- `conversation_screen_test.dart` (2445 lines, `buildTestWidget` 31-112) — pure-UI flags; **MISSING** any `isSyncingNewMessages` coverage. In `ONE_TO_ONE_TESTS` (`:62`).
- `conversation_wired_test.dart` (7290 lines) covers notif-tap/resume drain via fakes `FakeP2PService`/`DrainPersistsP2PService`/`GatedDrainP2PService`/`ThrowingDrainP2PService` (drain tests at L3190/3248/3274/3367/3427); **MISSING** affordance + live-timing + drainMs coverage. **NOT in any curated array** — only auto-glob `feature-host-all`/`host-all`.
- `benchmark_notification_tap_to_message_test.dart` (NT1-NT4) covers the stale-render timing event; **MISSING** the live-render event. Runs via `benchmark`/`performance-host` (excluded from `host-all`).
- `p2p_service_impl_test.dart` / `inbox_round_trip_test.dart` drive the real drain with a fake bridge — the host seam for the drain-duration fields.

Missing coverage gaps: await/fire-and-forget contract per route-kind; syncing affordance render + scroll-safety + flag plumbing; live-render timing event + one-shot latch; drainMs / retrieveMs / ackMs / replayMs fields.
Already in curated family arrays?: `prepare_notification_open_use_case_test.dart` and `conversation_screen_test.dart` in `ONE_TO_ONE_TESTS`; the rest auto-glob only.

---

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

### Change (1) — non-blocking conversation drain

1. `test/features/push/application/prepare_notification_open_use_case_test.dart::conversation drain is fire-and-forget — prepareNotificationOpen returns before the drain completes`
   - Tier: unit/application
   - Shape/setup: pass `drainOfflineInbox` returning a `Completer<void>().future` that is **never** completed; call `await prepareNotificationOpen(routeTarget: conversation, …)`. Assert it **completes** (returns `.ok`) while the drain future is still pending, and the drain was invoked exactly once (count==1).
   - RED on HEAD because: HEAD `await`s the drain (`:29`), so `prepareNotificationOpen(conversation)` never completes → the test hangs to timeout / fails.
   - GREEN after fix asserts: returns `ok==true` with the drain still pending; `drainCount==1`.
   - Mutation that re-reds: revert the `unawaited(...)` split back to `await drainOfflineInbox()` for `conversation` → re-red.

2. `…::conversation drain that throws does not propagate and is logged`
   - Tier: unit/application
   - Shape/setup: `drainOfflineInbox` throws synchronously/async; capture flow events via `debugSetFlowEventSink`. Assert `prepareNotificationOpen(conversation)` returns `ok==true`, no exception propagates, and a `NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR` event is emitted.
   - RED on HEAD because: HEAD awaits inside try/catch → returns `failed(...)` (not `ok`) and emits `NOTIFICATION_OPEN_PREPARATION_ERROR`, not the new event.
   - GREEN after fix asserts: `ok==true` + `NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR` present.
   - Mutation that re-reds: drop the `.catchError(...)` on the unawaited drain → unhandled async error / event absent → re-red.

3. `…::contactRequest and intros drains stay awaited (scope guard / INV-1)`
   - Tier: unit/application
   - Shape/setup: never-completing drain; assert `prepareNotificationOpen(contactRequest)` and `(intros)` do **NOT** complete while the drain is pending (e.g. race a short timeout; the call must still be pending).
   - RED on HEAD because: N/A — passes on HEAD (they await). This is the **over-broaden mutation lock**.
   - GREEN after fix asserts: still awaited (unchanged).
   - Mutation that re-reds: make `contactRequest`/`intros` also fire-and-forget → re-red.

### Change (2) — "catching up" affordance

4. `test/features/conversation/presentation/screens/conversation_screen_test.dart::renders syncing affordance when isSyncingNewMessages is true`
   - Tier: widget
   - Shape/setup: `buildTestWidget(messages: [<some stale rows>], initialLoadDone: true, isSyncingNewMessages: true)`. Assert `find.byKey(ValueKey('conversation-syncing-banner'))` finds one, containing a `CircularProgressIndicator` (small).
   - RED on HEAD because: the `isSyncingNewMessages` param does not exist (won't compile) / no such keyed widget.
   - GREEN after fix asserts: banner present.
   - Mutation that re-reds: revert the banner render branch → re-red.

5. `…::syncing affordance hidden when isSyncingNewMessages is false`
   - Tier: widget
   - Shape/setup: same but `isSyncingNewMessages: false`. Assert the banner key finds **nothing**.
   - RED on HEAD because: param absent (compile) — after scaffolding the param, this guards always-on.
   - Mutation that re-reds: render the banner unconditionally → re-red.

6. `…::syncing affordance is outside the message ListView and does not shift scroll`
   - Tier: widget
   - Shape/setup: with a scrollable message list, capture `scrollController.offset`; toggle `isSyncingNewMessages` false→true via `pumpWidget`; assert offset unchanged AND the banner is NOT a descendant of `find.byKey(ValueKey('messages'))` (the ListView).
   - RED on HEAD because: param absent — locks the placement requirement once added.
   - GREEN after fix asserts: banner sits in the outer Column (between upload banner `:298` and `Expanded` body `:300`); offset stable.
   - Mutation that re-reds: move the banner inside `_buildMessageList()` → descendant assertion red.

7. `…::syncing affordance is distinct from the older-pagination spinner`
   - Tier: widget
   - Shape/setup: `isLoadingMore: true, isSyncingNewMessages: false` → pagination indicator present, syncing banner absent; then `isLoadingMore: false, isSyncingNewMessages: true` → inverse. Assert the two use different keys.
   - RED on HEAD because: param absent.
   - Mutation that re-reds: key the syncing banner the same as / gate it on `isLoadingMore` → re-red.

8. `test/features/conversation/presentation/screens/conversation_wired_test.dart::syncing affordance is visible during an in-flight notif-tap drain and gone after it completes`
   - Tier: widget (integration of state→view)
   - Shape/setup: `pumpScreen(notificationTappedAt: <now>, p2pService: GatedDrainP2PService(gate))`. After initial pump, while the gate is **open** (drain in flight), assert `find.byKey(ValueKey('conversation-syncing-banner'))` present; complete the gate, `pumpAndSettle` (bounded), assert it's gone.
   - RED on HEAD because: `_drainReloadInFlight` is never threaded to the view → banner never appears.
   - GREEN after fix asserts: visible mid-drain, hidden after.
   - Mutation that re-reds: revert the `setState`-backed flag plumbing in `_drainAndReloadOnce` → re-red.

### Change (3) — telemetry

9. `test/performance/benchmark_notification_tap_to_message_test.dart::NT5 emitNotificationTapLiveRenderTiming emits NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING with liveRenderMs/addedIncoming/routeKind`
   - Tier: unit (perf-dir)
   - Shape/setup: call the new `emitNotificationTapLiveRenderTiming(tappedAt:…, routeKind:'conversation', addedIncoming:true)`; capture via `BenchmarkHarness.captureFlowEvents`. Assert event name, `elapsedMs`(or `liveRenderMs`) int ≥ 0, `addedIncoming==true`, `routeKind=='conversation'`, `milestone=='live_render'`.
   - RED on HEAD because: the function and event do not exist.
   - Mutation that re-reds: revert the new helper → re-red.

10. `test/features/conversation/presentation/screens/conversation_wired_test.dart::live-render timing event is emitted exactly once after a notif-tap drain surfaces a new message`
    - Tier: widget
    - Shape/setup: `pumpScreen(notificationTappedAt: <now>, p2pService: DrainPersistsP2PService(pending:[freshMsg]))`; capture events via `debugSetFlowEventSink` (SYNC teardown). After the drain completes, assert exactly **one** `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING` with `addedIncoming==true`. Then add a coalesced second pass (`GatedDrainP2PService` + a resume mid-flight, mirroring the L3367 coalescing test) and assert the count stays **1**. Also assert plain-orbit entry (`notificationTappedAt: null`) emits **zero**.
    - RED on HEAD because: event is never emitted.
    - GREEN after fix asserts: exactly one; zero on orbit entry; not double-emitted on coalesced passes.
    - Mutation that re-reds: remove the emit → 0 (red); remove the distinct one-shot latch `_notificationLiveTimingEmitted` → 2 on the coalesced case (red).
    - Distinct-event discriminator: assert `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING` (post-drain) is emitted IN ADDITION TO the existing `NOTIFICATION_TAP_TO_MESSAGE_TIMING` (`milestone:'stale_render'`), and the live one carries `addedIncoming`.

11. `…conversation_wired_test.dart::CONV_FL_NOTIF_DRAIN_REFETCH carries a numeric drainMs`
    - Tier: widget
    - Shape/setup: capture events; run a notif-tap drain (`DrainPersistsP2PService`); find `CONV_FL_NOTIF_DRAIN_REFETCH`; assert `details['drainMs']` is an int ≥ 0 (in addition to existing `trigger/before/after`).
    - RED on HEAD because: details are `{trigger, before, after}` only.
    - Mutation that re-reds: revert the Stopwatch/`drainMs` field → re-red.

12. `test/core/services/p2p_service_impl_test.dart::P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS carries numeric retrieveMs/ackMs/replayMs`  (if this file's harness drives a real `_drainOfflineInboxDurably`; else use `test/core/inbox/inbox_round_trip_test.dart`)
    - Tier: integration/host (real impl + fake bridge)
    - Shape/setup: drive a drain that stages+replays ≥1 entry (fake bridge `message.decrypt` canned ok); capture events via `debugSetFlowEventSink`; find `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS`; assert `retrieveMs`,`ackMs`,`replayMs` are ints ≥ 0 (in addition to `staged/replayed/note`).
    - RED on HEAD because: those fields are absent (`p2p_service_impl.dart:1682-1686`).
    - Mutation that re-reds: revert the Stopwatch fields → re-red.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 (1) conv fire-and-forget | pure logic / async | unit | prepare_notification_open_use_case_test.dart::conversation drain is fire-and-forget | HEAD awaits → call never completes | restore `await` for conversation | `./scripts/run_test_gates.sh 1to1` | in `ONE_TO_ONE_TESTS:63` (array) |
| TC-02 (1) throw swallowed+logged | error handling | unit | …::conversation drain that throws does not propagate | HEAD returns `failed`+wrong event | drop `.catchError` | `./scripts/run_test_gates.sh 1to1` | array (as above) |
| TC-03 (1) scope guard | preservation/INV | unit | …::contactRequest and intros stay awaited | n/a (HEAD green) — over-broaden lock | make them fire-and-forget | `./scripts/run_test_gates.sh 1to1` | array |
| TC-04 (1) group unchanged | preservation | unit | …::group target → drainGroupOfflineInboxForGroup (existing) | n/a | n/a | `./scripts/run_test_gates.sh 1to1` | array (existing) |
| TC-05 (1) dispatch order intact | preservation | unit | notification_route_dispatch_test.dart::callOrder ['prepare','route'] (existing) | n/a | n/a | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (core/** glob) |
| TC-06 (2) banner on | widget | widget | conversation_screen_test.dart::renders syncing affordance when true | param absent (compile) | revert banner render | `./scripts/run_test_gates.sh 1to1` | in `ONE_TO_ONE_TESTS:62` (array) |
| TC-07 (2) banner off | widget | widget | …::syncing affordance hidden when false | param absent | render unconditionally | `./scripts/run_test_gates.sh 1to1` | array |
| TC-08 (2) no scroll shift / outside list | widget | widget | …::affordance outside ListView, no scroll shift | param absent | move banner into list | `./scripts/run_test_gates.sh 1to1` | array |
| TC-09 (2) distinct from pagination | widget | widget | …::distinct from older-pagination spinner | param absent | share key / gate on isLoadingMore | `./scripts/run_test_gates.sh 1to1` | array |
| TC-10 (2) flag plumbing | widget | widget | conversation_wired_test.dart::affordance visible during in-flight notif-tap drain | flag not threaded → never shows | revert setState plumbing | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` | AUTO (feature-host-all glob); RECOMMEND add to `ONE_TO_ONE_TESTS` |
| TC-11 (3) live timing helper | pure logic | unit | benchmark_notification_tap_to_message_test.dart::NT5 live-render helper | function/event absent | revert helper | `./scripts/run_test_gates.sh benchmark` | AUTO (`test/performance/**`); runs via `benchmark`/`performance-host` (excluded from host-all) |
| TC-12 (3) live emit once + latch | widget / event | widget | conversation_wired_test.dart::live-render emitted exactly once | event never emitted | remove emit (→0) / remove latch (→2) | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` | AUTO (feature-host-all); RECOMMEND `ONE_TO_ONE_TESTS` |
| TC-13 (3) drainMs field | widget / event | widget | conversation_wired_test.dart::CONV_FL_NOTIF_DRAIN_REFETCH carries drainMs | field absent | revert Stopwatch/drainMs | `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` | AUTO (feature-host-all) |
| TC-14 (3) retrieve/ack/replay ms | host (real impl + fake bridge) | integration/host | p2p_service_impl_test.dart (or inbox_round_trip_test.dart)::STAGED_DRAIN_SUCCESS carries retrieveMs/ackMs/replayMs | fields absent | revert Stopwatch fields | `./scripts/run_host_test_gates.sh core-host-all` | AUTO (`test/core/**` glob) |
| TC-15 (3) stale-timing preserved | preservation | unit | benchmark_notification_tap_to_message_test.dart::NT1-NT4 (existing) | n/a | n/a | `./scripts/run_test_gates.sh benchmark` | AUTO (perf) |
| TC-16 (2) screen self-heal preserved | preservation | widget | conversation_wired_test.dart::notification-tap entry drains and re-fetches (existing L3190) | n/a | n/a | `flutter test …conversation_wired_test.dart` | AUTO (feature-host-all) |

## Invariants (locked by tests)
- INV-1: contactRequest/intros/group/post drain timing is unchanged by change (1) → TC-03, TC-04.
- INV-2: dispatcher prepares before routing (the use case returning fast does not reorder the dispatcher) → TC-05.
- INV-3: the syncing affordance never shifts scroll and is never confused with older-pagination → TC-08, TC-09.
- INV-4: the live-render timing event is emitted at most once per notif-tap (distinct one-shot latch), zero on non-notif entry → TC-12.
- INV-5: all telemetry changes are purely additive — existing events keep their existing fields → TC-13/TC-14 assert "in addition to", TC-15 preserves the stale event.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **RED first.** Add TC-01,02,03 (push unit), TC-06..09 (screen widget), TC-10/12/13 (wired widget), TC-11 (perf), TC-14 (p2p host). Run the focused commands; confirm each fails for the documented reason. Stop-if any "RED" actually passes → the seam differs from the plan; re-verify before editing.
2. **Change (1)** — `prepare_notification_open_use_case.dart`: split `case NotificationRouteTargetKind.conversation:` out of the shared branch; replace its `await drainOfflineInbox()` with `unawaited(drainOfflineInbox().catchError((e) { emitFlowEvent(layer:'FL', event:'NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR', details:{'error': e.toString()}); }));`. Leave `contactRequest`/`intros` awaited, `group` awaited. (Import `package:flutter/foundation.dart` `unawaited` or `dart:async`.)
3. **Change (2a)** — `conversation_screen.dart`: add `final bool isSyncingNewMessages;` (default `false`) to the constructor; in the body `Column` insert between the upload-progress banner (`:294-298`) and the `Expanded` body (`:300`) a `if (widget.isSyncingNewMessages) _ConversationSyncingBanner(...)` — a thin row (small `CircularProgressIndicator` + localized text), `key: const ValueKey('conversation-syncing-banner')`. Add l10n key `conversation_catching_up` (= "Catching up…") to `app_en.arb`, `app_ar.arb`, `app_de.arb`; run `flutter gen-l10n`.
4. **Change (2b)** — `conversation_wired.dart`: add `bool _isSyncingNewMessages = false;`. In `_drainAndReloadOnce`, set it true (inside `setState`, guarded by `mounted`) at entry of the try (`:1188`) and false in the `finally` (`:1220-1222`). Thread `isSyncingNewMessages: _isSyncingNewMessages` into the `ConversationScreen(...)` call (`:4043`). (Keep `_drainReloadInFlight` as-is for coalescing; the new field is the view-facing mirror, or convert the existing flag's mutations to `setState` — pick one and keep coalescing semantics intact.)
5. **Change (3a)** — `notification_tap_timing.dart`: add `emitNotificationTapLiveRenderTiming({required DateTime tappedAt, required String routeKind, required bool addedIncoming, String? messageId})` emitting `NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING` with `{elapsedMs, routeKind, addedIncoming, milestone:'live_render', messageId}`. Tag the existing `emitNotificationTapTiming` event with `milestone:'stale_render'` (additive).
6. **Change (3b)** — `conversation_wired.dart`: add `bool _notificationLiveTimingEmitted = false;`. Have `_reloadLatestPageForRecovery` surface `addedIncoming` (return it / set a field). In `_drainAndReloadOnce`, on the **first** pass when `trigger=='notif_tap' && addedIncoming && widget.notificationTappedAt != null && !_notificationLiveTimingEmitted`, set the latch and call `emitNotificationTapLiveRenderTiming(...)`. Add `drainMs` (Stopwatch around the per-pass drain+reload) to the `CONV_FL_NOTIF_DRAIN_REFETCH` details (`:1208-1216`).
7. **Change (3c)** — `p2p_service_impl.dart`: in `_drainOfflineInboxDurably`, wrap `_replayStagedInboxEntries()` (`:1648`) and `_retrievePendingInboxPage(...)` (`:1649`) in Stopwatches; extend `_retrievePendingInboxPage`'s result record with `retrieveMs`/`ackMs` (measure the retrieve vs the internal ack), and add `retrieveMs`/`ackMs`/`replayMs` to the `P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS` details (`:1682-1686`). Additive only.
8. **GREEN** — run direct test files; confirm reds flip green.
9. **Preservation + named gates** — run the sentinels (below). Stop-if any sentinel goes red outside the Scope Guard → replan, do not hack.
10. **Harness registration** — (recommended) add `test/features/conversation/presentation/screens/conversation_wired_test.dart` to the `ONE_TO_ONE_TESTS` array in `scripts/run_test_gates.sh` so the new affordance/telemetry coverage runs in the focused `1to1` gate, not just the broad host sweep. Verify with `./scripts/run_test_gates.sh 1to1`.

## Risks And Edge Cases
- **Unhandled async error** from the now-unawaited conversation drain → pinned by TC-02 (`.catchError`).
- **Always-on / scroll-jank affordance** → pinned by TC-07, TC-08.
- **Double-emit on coalesced drain passes** (the `_drainReloadPending` do/while at `:1190-1219`) → pinned by TC-12's distinct one-shot latch.
- **Toggling `_isSyncingNewMessages` outside `setState`** (the existing flag is mutated without `setState`) → would not rebuild; implementation step 4 mandates `setState`; TC-10 fails if it doesn't rebuild.
- **`_retrievePendingInboxPage` result-record change** (adding `retrieveMs`/`ackMs`) must not disturb existing `.staged/.replayed/.hasMore/.retrieveSucceeded` consumers → preservation via the p2p service suites.
- **l10n completeness** — missing `conversation_catching_up` in any of en/ar/de fails `flutter gen-l10n`/analyze; TC-06 uses a `ValueKey` (not the literal string) so it is robust to copy.

## Device/Relay Proof Profile
**host-only for closure.** All three changes are provable at host tier (use-case async semantics, widget render/plumbing, debug-observable flow events with a fake bridge for the real drain). No DB migration. No OS-callback / multi-device / real-ML-KEM / real-relay behavior is altered — the changes sit *after* the OS boundary, so a device-proof is **not** a closure gate.
Non-blocking device verification (follow-up): on a warm-resume notif-tap, confirm the conversation screen appears immediately and the "catching up…" strip shows during the relay round-trip, then clears as the message lands. (Manual / `/verify`; not required for plan closure.)
Relay defaults if needed: see `/sims` (not used here).

## Acceptance Gates  (literal — copy/paste)
```bash
# 0) Baseline snapshot (so preservation counts are interpretable)
git status --short

# 1) RED (before production edits) — must FAIL for the documented reason
flutter test test/features/push/application/prepare_notification_open_use_case_test.dart \
  --plain-name 'conversation drain is fire-and-forget'
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart \
  --plain-name 'renders syncing affordance when'
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'affordance visible during in-flight notif-tap drain'
flutter test test/performance/benchmark_notification_tap_to_message_test.dart \
  --plain-name 'NT5'
flutter test test/core/services/p2p_service_impl_test.dart \
  --plain-name 'STAGED_DRAIN_SUCCESS carries'

# 2) Direct GREEN (after fix) — whole files
flutter test test/features/push/application/prepare_notification_open_use_case_test.dart
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/performance/benchmark_notification_tap_to_message_test.dart   # NT1-NT4 preserved + NT5(+)
flutter test test/core/services/p2p_service_impl_test.dart
flutter test test/core/inbox/inbox_round_trip_test.dart                          # if TC-14 lands here

# 3) Preservation sentinels (must stay green — record baseline counts, expect 0 new failures)
./scripts/run_test_gates.sh 1to1                 # expect: same count as baseline, 0 new fails
./scripts/run_host_test_gates.sh core-host-all   # notification dispatch + matrix + p2p service
./scripts/run_test_gates.sh benchmark            # timing events (NT1-NT5)

# 4) l10n regen (after ARB edits)
flutter gen-l10n

# 5) Hygiene
flutter analyze            # 0 new issues
git diff --check
```
> Expected count deltas: `prepare_notification_open_use_case_test.dart` 4 → 6 (+TC-01,02); `conversation_screen_test.dart` +4 (TC-06..09); `conversation_wired_test.dart` +3 (TC-10,12,13); `benchmark_notification_tap_to_message_test.dart` 4 → 5/6 (+NT5[/NT6]); `p2p_service_impl_test.dart` or `inbox_round_trip_test.dart` +1 (TC-14). Record exact suite totals from the baseline run; preservation = baseline_total + new, 0 regressions.

## Known-Failure Interpretation
- Expected RED: TC-01,02,06..14 before their fixes (documented reasons above).
- Pre-existing dirty: the `new-feed` tree carries uncommitted work; capture `git status --short` first and do not revert unrelated files.
- Environment blocker (NOT product): none — no sim/device rows.
- Scope drift (BLOCKING): any failure in `group`/`contactRequest`/`intros`/`post` drain tests, the dispatcher order test, or NT1-NT4 → stop and replan (you broke a preserved invariant).

## Done Criteria
- [x] RED added first, failed for the expected reason (TC-01 timeout, TC-02 failed+PREPARATION_ERROR, TC-06..09 compile-err, TC-10/13 runtime, TC-14 null fields).
- [x] Mutation-verified — REDs flipped GREEN for each fix; one-shot latch directly mutation-checked (remove → TC-12b sees 2, red; restore → 1, green).
- [x] Direct GREEN + preservation sentinels: `1to1` 1113/1113 (now includes wired test); `core-host-all` notif dispatch/matrix/app-root + p2p green; `benchmark` NT1-5 green. (`core-host-all` intro_db + `benchmark` send-path fails are pre-existing, isolated above.)
- [x] No migration (no `DB v##` touched; p2p record change is in-memory only).
- [x] All telemetry additive — existing events keep existing fields; `milestone` added inside `details` (en/ar/de copy), new event/fields are new.
- [x] `conversation_wired_test.dart` runs in a gate (added to `ONE_TO_ONE_TESTS`; also auto-glob feature-host-all).
- [x] l10n key `conversation_catching_up` present in en/ar/de; `flutter gen-l10n` clean (getter in all 4 generated files).
- [x] `flutter analyze` 0 new (only pre-existing `:504` lint, identical on HEAD); `git diff --check` clean; no Scope Guard violations.

## Scope Guard (hard "Do not")
- Do not change group/contactRequest/intros/post drain timing (only `conversation` becomes fire-and-forget).
- Do not add a production/analytics FlowEvent sink (future telemetry session) — keep `flowEventLoggingEnabled` as-is.
- Do not implement push-prefetch, replay parallelization, delivery-receipt reordering, or `initialMessages`-on-notif-entry here.
- Do not alter the dispatcher's prepare-before-route ordering or the already-active suppression path.
- Do not couple the syncing banner to `isLoadingMore` (older-pagination spinner).

## Accepted Differences / Intentionally Out Of Scope
- Release-safe production telemetry sink → owned by a future telemetry session; this plan makes the events debug/test-observable and ready to attach.
- Eliminating the drain (push-prefetch / persist-from-push) → large separate effort (report §8).
- OS-tap-timestamp vs process-time and cold-vs-warm tagging of the tap metric → telemetry follow-up (not required by these three changes).

## Dependency Impact
- A future telemetry-sink session depends on the additive events/fields landed here (`NOTIFICATION_TAP_TO_LIVE_MESSAGE_TIMING`, `drainMs`, `retrieveMs/ackMs/replayMs`, `milestone`) as its data contract.

## Reviewer Findings
3-lens adversarial review workflow (concurrency/affordance-lifecycle, scope-guard/INV-1/2/3, p2p-record-additive/telemetry), each verifying against actual on-disk source: **ZERO blocker/major findings.** Verified explicitly: `_isSyncingNewMessages` cannot stick on (finally always resets, mounted-guarded); the `await Future<void>.value()` yield prevents setState-during-build on both notif_tap (initState) and resume paths; coalescing window + `_drainReloadInFlight` re-entrancy guard intact; contactRequest/intros/group/post drains byte-identical (only conversation fire-and-forget); `Future.sync` prevents a synchronous drain throw from reaching the outer catch; dispatcher prepare-before-route order unchanged; banner is a direct outer-Column child outside the ListView with a unique key gated only on `isSyncingNewMessages`; all 6 `_retrievePendingInboxPage` return literals set the 8 record fields; telemetry additive with `milestone`/`addedIncoming`/`*Ms` keys that sanitize cleanly (no sensitive-fragment match).

## Arbiter Decision
Structural blockers: none identified (host-only closure, no migration). | Deferred details: exact preservation counts (record at execution). | Accepted differences: production sink + larger fixes deferred as listed.

## Final Execution Verdict
Verdict: **SHIP (host-green)** — all three changes implemented TDD on `new-feed` (uncommitted), no migration.
Files changed (10 code + 3 arb + gen-l10n + 1 gate): `prepare_notification_open_use_case.dart` (conversation fire-and-forget + `NOTIFICATION_OPEN_CONVERSATION_DRAIN_ERROR`), `notification_tap_timing.dart` (`emitNotificationTapLiveRenderTiming` + `milestone` tags), `p2p_service_impl.dart` (`retrieveMs`/`ackMs`/`replayMs` on the record + `STAGED_DRAIN_SUCCESS`), `conversation_screen.dart` (`isSyncingNewMessages` + `_ConversationSyncingBanner`), `conversation_wired.dart` (`_isSyncingNewMessages` setState plumbing + `drainMs` + one-shot live-timing latch + `_reloadLatestPageForRecovery`→`Future<bool>`); tests in 5 files; `app_{en,ar,de}.arb` + regenerated `app_localizations*`; `run_test_gates.sh` ONE_TO_ONE_TESTS += wired test.
Tests run (+counts): prepare 4→7 (+TC-01/02/03), screen 70 (+TC-06..09), wired 91 (+TC-10/12a/12b/12c/13), benchmark 4→5 (+NT5), p2p 78 (+TC-14). Preservation: **1to1 1113/1113**; core-host-all notif dispatch/matrix/app-root 54 + p2p green; analyze 0-new; git diff --check clean.
Blocking: none. QA verdict: 3-lens adversarial review = ZERO blocker/major.
Pre-existing (NOT 145): `benchmark` send-path routing (R8 relay / NET-REL-05 — proven via stash) + `core-host-all` `intro_db_helpers` (date-sensitive `'expired'`).
Non-blocking follow-ups (owner): device verify of perceived latency on warm-resume notif-tap (screen appears immediately, "catching up…" shows during the relay round-trip then clears); future telemetry-sink session consumes the additive events/fields.
