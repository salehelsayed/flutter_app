# 139 - Notification tap stacks a duplicate 1:1 conversation screen  (Bug)

Status: IMPLEMENTED — host-green + mutation-verified (sim/device behavioral closure deferred: no simulator pair available). Uncommitted on `new-feed`.
Spec: free-text intent (no formal spec) — root cause adversarially verified (9-agent verify→refute workflow, 3/3 verifiers agree, confidence 0.95)

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-06-21 | Evidence Collector | main.dart (3790-3951, 4004-4080), app_root_notification_open.dart, active_conversation_tracker.dart, conversation_route_transition.dart, notification_route_target.dart, app_root_notification_open_test.dart, notification_tap_smoke_test.dart, notification_open_during_other_chat_harness.dart, flow_event_emitter.dart, run_test_gates.sh | Root cause = 1:1/group asymmetry; decision logic lives in a pure host-testable fn; main.dart handler is private | Build matrix |
| 2026-06-21 | Planner | (as above) | 2 prod edits, 4 tests (2 host floor + 1 host wiring-lock + 1 sim/device behavioral closure); no migration | Emit plan |
| | Reviewer (sufficiency) | | | |
| | Arbiter | | (final structural verdict) | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-06-21 | source re-verify | (read-only) | plan line numbers match HEAD EXACTLY (conv case 3931, group guard 3882, helper 71-79, tracker 2269→3320→4021); INV-3 confirmed (conversation_wired.dart:483 setActive / :4016 clearIfActive-only-on-dispose / :4060 resumed-only) | guard NOT inert; proceed | RED tests |
| 2026-06-21 | RED tests added | T1 (app_root_notification_open_test.dart +3), T2 (NEW app_root_conversation_route_dedup_wiring_test.dart) | T1 = compile-RED ("No named parameter 'conversationTracker'"); T2 = assert-RED ("conversation case must call the already-active guard") | RED for documented reasons | E1/E2 |
| 2026-06-21 | implementation | E1 app_root_notification_open.dart (exhaustive switch + optional conversationTracker), E2 lib/main.dart conversation case (guard + CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE) | scoped to 2 prod edits; pre-existing new-feed feed-redesign hunks in main.dart left untouched | scoped files only | GREEN |
| 2026-06-21 | direct GREEN | (as above) | `flutter test test/core/notifications/` = 158/158 incl. 3 new + wiring-lock | reds now green | mutation |
| 2026-06-21 | mutation-verify | (temp reverts, restored) | revert E1 conv branch → T1 RED (Expected true, Actual false); revert E2 guard → T2 RED (token absent). No MUTATION residue (grep clean) | both edits mutation-verified | preservation |
| 2026-06-21 | preservation GREEN | (no prod change) | notification_tap_smoke 70/70; chat+group dedupe suppression pass; **1to1 gate 1003/1003**; analyze 0 new errors/warnings (only pre-existing harness avoid_print info) | sentinels green | harness + review |
| 2026-06-21 | harness (T3) | notification_open_during_other_chat_harness.dart (replica guard + same-peer no-duplicate phase) | compiles clean (analyze); CANNOT run here (needs 2-sim relay pair) → DEFERRED per Device/Relay Proof Profile | environment-blocked, not product | review |
| 2026-06-21 | QA (independent) | — | 5-dimension adversarial review workflow (code-reviewer agents + adversarial verify pass) | see Reviewer Findings below | verdict |

## Source Of Truth
- Spec / intent: inline below (verified root cause from the debug workflow)
- Gate definitions: `scripts/run_test_gates.sh` (script wins over prose)
- Discovery/registration: `scripts/check_reliability_simulation_discovery.sh`
- Numbering / index: `Test-Flight-Improv/00-INDEX.md` (max existing = 138 → this is 139)

## Session Classification
implementation-ready

## Exact Problem Statement
User-A opens User-B's 1:1 conversation, backgrounds the app, then receives a new message from User-B and taps the notification. The app foregrounds and **pushes a second, identical `ConversationWired(B)` on top of the one that is already mounted**. The user now has two stacked B conversation screens; pressing back from the top one lands on the duplicate B underneath (the still-mounted original) instead of returning to the feed. Expected: tapping the notification surfaces exactly **one** conversation screen for that peer — no overlay/duplicate.

What must improve: tapping a 1:1 notification for a peer whose conversation is already the active/top screen must **not** push a second route — it must leave the existing screen in place (which already re-fetches the new message on resume via `ConversationWired.didChangeAppLifecycleState`, `conversation_wired.dart:4060`).

What must stay unchanged (→ preserved-green sentinels):
- The **group** notification-tap already-active guard (`GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE`) — byte-identical behavior.
- Legitimate 1:1 navigation: cold start (no screen open), notification for a **different** peer than the one open, and the whole `prepare → drain → route` dispatch pipeline (`notification_tap_smoke_test.dart`, 70+ cases).
- 1:1 reliability suites (`./scripts/run_test_gates.sh 1to1`) and `baseline`.

## Root Cause (verify → refute confirmed)
The 1:1 conversation case in `_handleNotificationRouteTarget` (`lib/main.dart:3931-3946`) has **no already-active/dedup guard**, while the **group** case (`lib/main.dart:3837-3930`) guards via `isNotificationRouteTargetAlreadyActive(...)` at `lib/main.dart:3882-3898` and early-returns (emitting `GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE`) without pushing when already viewing.

- The shared helper `isNotificationRouteTargetAlreadyActive` (`lib/core/notifications/app_root_notification_open.dart:71-79`) hard-returns `false` for any `kind != group` (lines 75-77) and only accepts `groupConversationTracker`, so the conversation kind is structurally never deduped.
- The conversation case calls `_openConversationForContact` (`lib/main.dart:4004-4032`), an **unconditional** `navigator.push(buildConversationRoute(...))` at `lib/main.dart:4009`. `buildConversationRoute` (`lib/features/conversation/presentation/navigation/conversation_route_transition.dart:15-23`) is a plain anonymous `MaterialPageRoute` with **no `RouteSettings.name`**, so Navigator cannot match/dedup — it stacks.
- The 1:1 `ActiveConversationTracker` already knows the open peer: `isViewing(peerId)` (`active_conversation_tracker.dart:26`) is kept current by `ConversationWired` (`setActive` in `initState`, `conversation_wired.dart:483`; `clearIfActive` only in `dispose`, `:4016`). `didChangeAppLifecycleState` (`:4060`) only handles `resumed`, so **backgrounding neither disposes the route nor clears the tracker** → `isViewing(B)` is still true at tap time. The tracker is consumed only for notification *suppression* (`show_notification_use_case.dart:88-89`), never by navigation.
- All three tap entry points (local `_onNotificationTap` `main.dart:3775`; FCM `onMessageOpenedApp` `main.dart:4399`; iOS APNS bridge `main.dart:3636`) converge on `_handleNotificationRouteTarget`. On warm resume the cold-start deferral guard (`main.dart:3804-3813`) is skipped (`navigator != null && _startupHomeReady`), so it pushes immediately.
- Decisive enabler for the fix: `NotificationRouteTarget.toPayload()` for the conversation kind returns `peerId ?? ''` (`notification_route_target.dart:57`), so the helper can dedup conversation kind **symmetrically** with group via `conversationTracker.isViewing(routeTarget.toPayload())`. `ActiveConversationTracker.normalizeActiveKey` leaves a plain peerId intact (`active_conversation_tracker.dart:28-42`).
- A single, correct tap reproduces this (no double-firing). The existing `_remoteNotificationOpenDedupeGate` (`main.dart:3674`) keys on the **notification payload**, not the active peer, so a fresh-message notification for an already-open peer still re-pushes.

Refuted / do-NOT-re-introduce:
- "Duplicate is a double-firing tap callback" — **refuted**; one correct tap suffices because the original route stays mounted across background.
- "Named-route dedup already exists / should be the fix" — **refuted**; the **group** push (`main.dart:3901-3902`) is also a bare `MaterialPageRoute` with no name. The codebase's established dedup pattern is **tracker-based**, not route-name based. Mirror it.
- Path correction baked into this plan: `buildConversationRoute` lives under `.../presentation/navigation/`, not `.../presentation/widgets/`.

## Real Scope
In scope:
- **E1**: generalize `isNotificationRouteTargetAlreadyActive` (`lib/core/notifications/app_root_notification_open.dart`) to accept an optional 1:1 `conversationTracker` and handle `NotificationRouteTargetKind.conversation` via `conversationTracker?.isViewing(routeTarget.toPayload()) ?? false`. Group branch byte-identical.
- **E2**: add the guard call to the conversation case in `_handleNotificationRouteTarget` (`lib/main.dart:3931-3946`): when already viewing the target peer, reset `_notificationTappedAt`, emit `CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE` (layer `FL`, mirroring the group event at `main.dart:3887-3896`), and `return` without pushing.

Out of scope (owning work named):
- **Buried-duplicate collapse** (open B → navigate to C → tap B notif): a single-`_activePeerId` tracker cannot see a B route buried under C; only a named-route + `popUntil`-to-existing scheme would. This is **parity with the existing group guard** (same limitation) → Accepted Difference; a future "named conversation routes" session owns it.
- **Swap-to-different-peer "replace instead of stack"** (tap C while on B): out of scope; current/after behavior both push C on top of B (parity with group). No regression.
- Any change to the group guard, the remote dedupe gate, the cold-start deferral path, or notification suppression.

## Files To Inspect Next
Production (entry/use-case, models, helpers):
- `lib/core/notifications/app_root_notification_open.dart` (E1) — the pure guard.
- `lib/main.dart` conversation case `3931-3946`, group template `3882-3898`, `_openConversationForContact` `4004-4032`, tracker fields `2269-2270`/`3320`, `navigatorKey` `3361`/`4512` (E2 + confirm `widget.conversationTracker` is the SAME instance passed to `ConversationWired` at `4021`).
- `lib/core/notifications/active_conversation_tracker.dart`, `lib/core/notifications/notification_route_target.dart` (no edits; confirm `toPayload()`/`normalizeActiveKey` invariants).

Direct tests + integration tests:
- `test/core/notifications/app_root_notification_open_test.dart` (T1, extend; the group case at `:207-237` is the template + a preservation sentinel).
- NEW `test/core/notifications/app_root_conversation_route_dedup_wiring_test.dart` (T2, source-wiring-lock — precedent: Report 120 G1 main.dart wiring-lock).
- `integration_test/notification_open_during_other_chat_harness.dart` (T3, extend with a same-peer no-duplicate scenario; its replicated `_handleNotificationRouteTarget` at `:362-407` must receive the same guard to stay a faithful mirror).
- `test/integration/notification_tap_smoke_test.dart`, `test/integration/chat_notification_dedupe_integration_test.dart` (preservation context only).

Dependency-only context: `lib/core/utils/flow_event_emitter.dart` (`debugSetFlowEventSink` test capture seam; `emitFlowEvent` signature).

## Existing Tests Covering This Area
- `test/core/notifications/app_root_notification_open_test.dart` — covers the pipeline + the **group** already-active guard, incl. an assertion that a conversation target with only the group tracker is `false` (`:230-236`). (exists; the conversation-tracker dedup path is **MISSING**.)
- `test/integration/notification_tap_smoke_test.dart` — exhaustive `prepare→drain→route` per kind; does NOT exercise `_handleNotificationRouteTarget` push behavior. (exists; no dedup coverage.)
- `integration_test/notification_open_during_other_chat_harness.dart` — replicated handler + real `ConversationWired` + `NavigatorObserver`; reproduces the **different-peer** routing bug, NOT the same-peer duplicate. (exists; same-peer no-duplicate scenario MISSING.)
- `test/integration/chat_notification_dedupe_integration_test.dart` / `group_notification_dedupe_integration_test.dart` — notification *suppression* dedupe (tracker's original purpose), not navigation dedup. (exists; unrelated to the push.)

Missing coverage gaps: (1) `isNotificationRouteTargetAlreadyActive` for the conversation kind; (2) main.dart conversation-case wiring of that guard; (3) end-to-end "no second route for an already-open peer."

Already in curated family arrays?: `conversation_route_transition_test.dart` and the chat-listener suite are in `ONE_TO_ONE_TESTS` (`run_test_gates.sh:17-63`). `notification_open_ui_smoke_test.dart` + `notification_deeplink_integration_test.dart` are in `OPTIONAL_MANUAL_TESTS` (`:165-207`). The new core tests auto-glob (`test/core/**`); no family-array edit needed. The notif-open harness is orchestrator-driven (not in a `_TESTS` array).

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/core/notifications/app_root_notification_open_test.dart`::`active 1:1 conversation route is skipped when its tracker is viewing that peer`
   - Tier: unit/application (host).
   - Shape/setup: `conv = ActiveConversationTracker()..setActive('peer-123')`. Call `isNotificationRouteTargetAlreadyActive(routeTarget: NotificationRouteTarget.conversation('peer-123'), groupConversationTracker: ActiveConversationTracker(), conversationTracker: conv)`.
   - RED on HEAD because: the helper hard-returns `false` for non-group kinds (`app_root_notification_open.dart:75-77`) — and `conversationTracker` is not even a parameter today, so the test won't compile until E1 adds it (compile-RED is acceptable and documented). Expectation: `isTrue`.
   - GREEN after fix asserts: `isTrue` for matching peer.
   - Mutation that re-reds: revert E1 (restore `if (kind != group) return false;`) → this assertion flips RED (or fails to compile).

2. `test/core/notifications/app_root_notification_open_test.dart`::`1:1 conversation route is NOT skipped for a different peer or a null tracker`
   - Tier: unit/application (host).
   - Shape/setup: tracker viewing `peer-123`; assert `conversation('peer-999')` → `isFalse` (different peer); assert `conversation('peer-123')` with `conversationTracker: null` → `isFalse` (null fallback); assert `conversation('peer-123')` with the default group-only call (no `conversationTracker`) → `isFalse` (backward-compat — the existing `:230-236` assertion stays green).
   - RED on HEAD because: pairs with RED #1 to make it **non-vacuous** — proves the GREEN of #1 is peer-specific, not "always true." On HEAD these are vacuously false; the mutation guard is that E1 must make #1 true **without** making these true.
   - GREEN after fix asserts: all `isFalse`.
   - Mutation that re-reds: change E1 to `return conversationTracker != null` (ignoring the peer) → the different-peer assertion flips RED.
   - Distinct-event discriminator: the decision is **peer-keyed** (uses the tracker's active peer), not payload/messageId-keyed — distinct from `_remoteNotificationOpenDedupeGate` (`main.dart:3674`).

3. `test/core/notifications/app_root_notification_open_test.dart`::`group already-active guard is unchanged when the 1:1 tracker is also supplied` (preservation lock)
   - Tier: unit/application (host).
   - Shape/setup: group tracker viewing `group:group-123`; assert `group('group-123', messageId:'m')` → `isTrue` and `group('group-456')` → `isFalse`, **with** a non-null `conversationTracker` also passed.
   - RED on HEAD because: not RED on HEAD (preservation sentinel) — but goes RED if E1 accidentally routes the group kind through the conversation branch.
   - GREEN after fix asserts: group behavior identical regardless of `conversationTracker`.
   - Mutation that re-reds: collapse E1's `switch` so group falls into the conversation branch → this flips RED.

4. NEW `test/core/notifications/app_root_conversation_route_dedup_wiring_test.dart`::`main.dart conversation notification case consults the already-active guard and emits the skip event`
   - Tier: unit (host source-wiring-lock; precedent Report 120 G1).
   - Shape/setup: read `lib/main.dart` as a string; locate the `case NotificationRouteTargetKind.conversation:` block; assert it contains a call to `isNotificationRouteTargetAlreadyActive(` **with** `conversationTracker:` **and** the literal `'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE'`, before/around the `_openConversationForContact` call. (Token/regex match, not exact whitespace.)
   - RED on HEAD because: today the conversation case calls neither the guard nor emits that event.
   - GREEN after fix asserts: the wiring tokens are present in the conversation case.
   - Mutation that re-reds: revert E2 → the tokens vanish → RED.
   - Note: this is a deliberately lightweight existence-lock for un-unit-testable private main.dart glue; the **behavioral** proof is #5.

5. `integration_test/notification_open_during_other_chat_harness.dart`::`Alice(notif-open already in same chat) — no duplicate` (NEW scenario; PROD-CRITICAL behavioral closure)
   - Tier: simulator / device-proof (integration_test, real `ConversationWired` + `NavigatorObserver` + real `ActiveConversationTracker`).
   - Shape/setup: Alice opens **Bob's** conversation (`setActive(bobPeerId)`, push `conversation:user-b`), logically backgrounds, then **re-taps Bob's already-delivered notification** (reuses the warm-path notification — no second Bob send needed; the bug is a single correct tap). Port the E1/E2 guard into the harness's replicated `_handleNotificationRouteTarget` (`:362-407`) so the mirror stays faithful.
   - **Refinement vs plan (IMPLEMENTED)**: the replica records routing decisions in its `trace` list, **not** via `emitFlowEvent`/`debugSetFlowEventSink` (production's mechanism). So the faithful mirror adds `trace.add('conversation-already-active:<label>')` on a guard hit, and the scenario asserts that trace entry instead of a flow-sink capture. The production behavioral identity (`CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE`) is locked by the host wiring-lock T2; the harness proves the no-push behavior.
   - RED on HEAD because: without the guard the replica pushes a second `conversation:user-b` route → `NavigatorObserver` records a 2nd `push` and two `alice-conversation-user-b` subtrees exist.
   - GREEN after fix asserts: after the tap, the Bob-route push count is **unchanged** (`bobPushesAfterTap == bobPushesBeforeTap`); exactly **one** `alice-conversation-user-b` route in tree (`bobRouteCount == 1`); the `conversation-already-active:user-b` trace entry is present (`programmaticPass`). The existing different-peer scenario (tap B while on user-C) still pushes (regression-preserved — the guard's `isViewing(bob)` is false when the tracker holds user-C).
   - Mutation that re-reds: revert E2's guard in the replica → the 2nd push reappears → `reproducedBug` true.
   - Distinct-event discriminator: the guard fires for a **fresh** notification keyed on the **active peer**, distinct from the payload-keyed remote dedupe gate.

## Test Coverage Matrix  (zero empty cells in tier / mutation / gate / registration)
| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-01 core: already-viewing B → skip | pure decision | unit (host) | app_root_notification_open_test.dart::active 1:1 conversation route is skipped… | helper returns false for conversation kind (param absent) | revert E1 → RED | `flutter test test/core/notifications/app_root_notification_open_test.dart` | AUTO (`test/core/**`); classify_path "core notifications direct suite" |
| TC-02 cold start / not-viewing → push | pure decision | unit (host) | app_root_notification_open_test.dart::…NOT skipped for a different peer or a null tracker | vacuous-false guard (non-vacuity pair) | E1→`conversationTracker!=null` → RED | `flutter test test/core/notifications/app_root_notification_open_test.dart` | AUTO (`test/core/**`) |
| TC-03 different peer → push | pure decision | unit (host) | app_root_notification_open_test.dart::…NOT skipped for a different peer or a null tracker | (same row as TC-02) | E1 ignores peer → RED | `flutter test test/core/notifications/app_root_notification_open_test.dart` | AUTO (`test/core/**`) |
| TC-04 group parity preserved | pure decision | unit (host) | app_root_notification_open_test.dart::group already-active guard is unchanged… (+existing `:207-237`) | preservation sentinel (RED if group misrouted) | collapse E1 switch → RED | `flutter test test/core/notifications/app_root_notification_open_test.dart` | AUTO (`test/core/**`) |
| TC-05 null tracker → push, no crash | null-safety | unit (host) | app_root_notification_open_test.dart::…null tracker (in TC-02 row) | (covered by TC-02 null case) | E1 drops `?? false` → RED/throws | `flutter test test/core/notifications/app_root_notification_open_test.dart` | AUTO (`test/core/**`) |
| TC-06 peer-keyed not payload-keyed | discriminator | sim/device | notification_open_during_other_chat_harness.dart::…no duplicate (event assert) | n/a on HEAD (new scenario) | revert E2 → 2nd push + RED | `./scripts/check_reliability_simulation_discovery.sh` then `/sims <notif-open scope> --only N` | classify_path case (already a notif harness) + notif-open orchestrator scenario |
| TC-06w wiring: main.dart calls guard | private glue | unit (host source-lock) | app_root_conversation_route_dedup_wiring_test.dart::main.dart conversation… emits skip event | conversation case lacks guard + event | revert E2 → RED | `flutter test test/core/notifications/app_root_conversation_route_dedup_wiring_test.dart` | AUTO (`test/core/**`) |
| TC-07 buried duplicate (B under C) | accepted limitation | (none — documented) | — (Accepted Differences; parity with group) | — | — | — | — |

## Invariants (locked by tests)
- INV-1: A 1:1 notification tap for the **currently-viewed** peer does not push a new route. → TC-01 + TC-06.
- INV-2: A 1:1 notification tap for a **non-viewed** peer (incl. cold start, different peer) **does** push. → TC-02/TC-03 + existing harness different-peer scenario.
- INV-3: The guard's `conversationTracker` is the **same `ActiveConversationTracker` instance** that `ConversationWired` calls `setActive` on (`main.dart:2269` created → `4021` passed to `ConversationWired` → `:483` setActive). If a different instance is wired, the guard is a silent no-op. → confirmed in code review during E2; behaviorally locked by TC-06.
- INV-4: Group already-active behavior is byte-identical. → TC-04 (+ `GROUP_NOTIFICATION_ROUTE_ALREADY_ACTIVE` unchanged).
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. `git status --short` snapshot (dirty tree already present on `new-feed`; do not revert unrelated files).
2. Add RED tests #1–#4 (host) and scaffold #5 (harness scenario). Run the focused host commands; confirm #1 fails (compile/assert) for the documented reason, #4 fails on token-absence.
3. **E1** — `lib/core/notifications/app_root_notification_open.dart`: change `isNotificationRouteTargetAlreadyActive` to
   ```dart
   bool isNotificationRouteTargetAlreadyActive({
     required NotificationRouteTarget routeTarget,
     required ActiveConversationTracker groupConversationTracker,
     ActiveConversationTracker? conversationTracker,
   }) {
     switch (routeTarget.kind) {
       case NotificationRouteTargetKind.group:
         return groupConversationTracker.isViewing(routeTarget.toPayload());
       case NotificationRouteTargetKind.conversation:
         return conversationTracker?.isViewing(routeTarget.toPayload()) ?? false;
       default:
         return false;
     }
   }
   ```
   (group branch identical to today; new optional param keeps every existing caller compiling.)
4. **E2** — `lib/main.dart` conversation case (`3931-3946`): at the **top** of the case (before `getContact`, since the decision needs only `routeTarget` + tracker and the suppress path must not depend on a repo hit), add the group-mirrored guard:
   ```dart
   case NotificationRouteTargetKind.conversation:
     if (isNotificationRouteTargetAlreadyActive(
       routeTarget: routeTarget,
       groupConversationTracker: widget.groupConversationTracker,
       conversationTracker: widget.conversationTracker,
     )) {
       _notificationTappedAt = null;
       emitFlowEvent(
         layer: 'FL',
         event: 'CONVERSATION_NOTIFICATION_ROUTE_ALREADY_ACTIVE',
         details: {
           'peerId': routeTarget.peerId!.length > 8
               ? routeTarget.peerId!.substring(0, 8)
               : routeTarget.peerId!,
         },
       );
       return;
     }
     final contact = await widget.contactRepository.getContact(routeTarget.peerId!);
     // …unchanged…
   ```
   Stop-if: `widget.conversationTracker` turns out NOT to be the instance `ConversationWired` mutates (INV-3) → replan (the guard would be inert); do not hack a second tracker.
5. Port the same guard into the harness replica (#5) so it mirrors production.
6. Rerun: direct GREEN (host) → preservation (`1to1`, `baseline`) → discovery + `/sims` for #5 (sim/device) → `flutter analyze` + `git diff --check`.

## Risks And Edge Cases
- **Inert-guard risk** (INV-3): wrong tracker instance → silent no-op. Pinned by code review + TC-06 behavioral.
- **Suppress path UX**: when suppressed, the user stays on the existing B screen, which re-fetches on resume (`conversation_wired.dart:4060`) — so the new message still appears. No extra scroll-to-message (parity with group, which also just suppresses).
- **Guard-before-getContact ordering**: chosen so suppression is a pure decision (no DB hit, simpler test). Acceptable because when `isViewing(B)` is true the contact necessarily exists.
- **Buried duplicate / swap-to-different-peer**: Accepted Differences (parity with group). Documented, not fixed.

## Device/Relay Proof Profile
host-only is sufficient for the **decision + wiring** (TC-01..TC-05 + TC-06w are mutation-verified host gates, no hardware). The defect is pure-Dart routing logic, so host coverage is unusually strong here — the OS boundary is only the trigger, not where the bug lives.
Closure scenario (behavioral, added confidence): `integration_test/notification_open_during_other_chat_harness.dart` same-peer no-duplicate scenario → run via the notif-open orchestrator / `/sims`; confirm it lists in `./scripts/check_reliability_simulation_discovery.sh` first. No feature flag.
Deferred device work → none blocking; the sim/device scenario can be run when a simulator pair is available.
Relay defaults if needed: `/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g` (see `run_test_gates.sh:163`).

## Acceptance Gates  (literal — copy/paste, with expected counts)
```bash
# Dirty-tree snapshot (do not revert unrelated new-feed changes)
git status --short

# RED (before production edits) — must FAIL for the documented reason
flutter test test/core/notifications/app_root_notification_open_test.dart \
  --plain-name 'active 1:1 conversation route is skipped'        # compile/assert RED
flutter test test/core/notifications/app_root_conversation_route_dedup_wiring_test.dart  # token-absence RED

# Direct GREEN (after E1 + E2)
flutter test test/core/notifications/app_root_notification_open_test.dart
flutter test test/core/notifications/app_root_conversation_route_dedup_wiring_test.dart

# Core-notifications direct suite (host) — both new tests auto-glob here
flutter test test/core/notifications/

# Preservation sentinels (must stay green)
./scripts/run_test_gates.sh 1to1            # expect: all pass (no new failures vs HEAD)
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline   # expect: all pass
flutter test test/integration/notification_tap_smoke_test.dart # expect: all pass (pipeline unchanged)

# Behavioral closure (sim/device) — confirm discovery, then run
./scripts/check_reliability_simulation_discovery.sh            # new notif-open scenario MUST list
# /sims <notif-open scope> --list  → note --only N  → /sims <notif-open scope> --only N

# Hygiene
flutter analyze            # 0 new issues
git diff --check
```

## Known-Failure Interpretation
- Expected RED: tests #1 and #4 before the fix (compile/assert and token-absence).
- Pre-existing dirty: `new-feed` has many modified/deleted files (feed redesign) — unrelated; do not revert.
- Environment blocker (NOT product): no simulator pair available → the #5 sim/device scenario is deferred; host TC-01..TC-06w still fully prove the fix.
- Scope drift (BLOCKING): any failure in the group guard, the dispatch pipeline, or `1to1`/`baseline` outside the two scoped edits.

## Done Criteria
- [x] RED added first (#1, #4), failed for the expected reason. (T1 compile-RED on absent param; T2 assert-RED on token absence.)
- [x] Mutation-verified: revert E1 → #1 RED (Expected true / Actual false); revert E2 → #4 RED (token absent). #5 2nd-push RED is the deferred sim/device reproduction.
- [x] Direct GREEN + `1to1` (1003/1003) + `notification_tap_smoke_test` (70/70) pass. (`baseline` not separately run; the touched code is covered by core/notifications + 1to1.)
- [x] No migration (none needed) — N/A.
- [~] Behavioral sim/device scenario green — **explicitly deferred (environment-blocked: no simulator pair available)**; scenario written + compiles, runs when a sim pair is available.
- [x] INV-3 confirmed in code (same tracker instance: main.dart 2269→3320→4021, mutated at conversation_wired.dart:483/:4016).
- [x] `flutter analyze` 0 new errors/warnings; `git diff --check` clean; no Scope Guard violations (139 diff = exactly E1+E2+tests; pre-existing new-feed feed hunks untouched).

## Scope Guard (hard "Do not")
- Do not change the group already-active guard, the remote dedupe gate (`main.dart:3674`), the cold-start deferral (`main.dart:3804-3813`), or notification suppression.
- Do not introduce named conversation routes / `popUntil` collapse (owned by a future "named conversation routes" session — see Accepted Differences).
- Do not edit any `_TESTS` family array (new tests auto-glob `test/core/**`).

## Accepted Differences / Intentionally Out Of Scope
- **Buried-duplicate** (B open → C open → tap B notif): not collapsed — single-`_activePeerId` tracker can't see a buried route. This is identical to the current **group** guard limitation. Future "named conversation routes + popUntil-to-existing" session owns it.
- **Swap-to-different-peer replace** (tap C while on B stacks C on B): unchanged; parity with group.

## Dependency Impact
- None. E1 adds an optional parameter (backward-compatible); E2 is additive in the conversation case. The group path and all other callers are unaffected.

## Reviewer Findings
5-dimension adversarial review workflow (7 agents: code-reviewer finders + adversarial verify pass), 2026-06-21. **Zero confirmed defects.**
- **inv3-tracker-instance** — CLEAN. The guard's `widget.conversationTracker` is the SAME `ActiveConversationTracker` instance `ConversationWired` mutates (`main.dart:2269`→field `:3320`→`ConversationWired` `:4021`; `setActive` `conversation_wired.dart:483`, `clearIfActive` dispose-only `:4016`, lifecycle resumed-only `:4060`). Backgrounding leaves `isViewing(peer)` true at tap time → guard fires correctly, not inert.
- **logic-correctness** — CLEAN. Group branch byte-equivalent; exhaustive switch (no missing-case warning); null-tracker fallback safe; `toPayload()` returns bare peerId matching `setActive`; 8-char `peerId` detail SURVIVES `emitFlowEvent` sanitization (peerId-key redaction only triggers at `length > 12` — parity with the group case's 8-char `groupId`).
- **scope-guard** — CLEAN. 139 diff = exactly E1 (helper) + E2 (conversation case) + tests. No touch to the group guard, remote dedupe gate, cold-start deferral, or suppression. Pre-existing `new-feed` feed-redesign hunks in main.dart correctly left alone.
- **harness-faithfulness** — CLEAN. Same-peer scenario logically sound: `popUntil` clears the prior tracker, `setActive(bob)` + ConversationWired init both set the same instance; `bobPushCount()` before==after proves zero new pushes; reuses the single existing Bob notification (no 2nd send); no orchestrator signal-contract break.
- **test-sufficiency** — CONCERNS (0 confirmed; 2 findings REFUTED). Suite is sufficient + mutation-verifiable; non-vacuity sound (`conversationTracker != null` mutant caught by the different-peer assertion); wiring-lock slice `[3931,3971)` excludes the group case. **Actioned LOW→hardening**: added a guard-before-`getContact` **ordering lock** to the wiring-lock test (locks the "pure decision / no DB hit" design intent). Non-actioned nits: relative-path read (standard under `flutter test` CWD), unanchored `conversationTracker:` token (only occurrence in-slice is the guard call).

## Arbiter Decision
SHIP (host scope). Both production edits are mutation-verified; INV-1..INV-4 hold; review surfaced no real defect. The sim/device behavioral closure (#5) is environment-blocked (no simulator pair) and explicitly deferred — host coverage (TC-01..TC-06w, all mutation-verified) is unusually strong here because the defect is pure-Dart routing logic, not an OS-boundary failure.

## Final Execution Verdict
IMPLEMENTED, host-green, mutation-verified, review-clean. Gates: `test/core/notifications/` 158/158 (3 decision tests + hardened wiring-lock), `1to1` 1003/1003, `notification_tap_smoke_test` 70/70, dedupe-suppression pass, `flutter analyze` 0 new errors/warnings, `git diff --check` clean. Remaining: run the same-peer harness scenario when a 2-simulator relay pair is available; commit is pending (uncommitted on `new-feed` alongside the feed redesign).
