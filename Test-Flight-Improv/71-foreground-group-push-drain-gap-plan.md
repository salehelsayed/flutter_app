# 71 - Foreground FCM Push Does Not Drain Group Inbox — TDD Fix Plan

## 1. Title and Type

- Title: Foreground FCM push does not drain group inbox
- Issue type: `bug` (reliability / timing)
- Output doc path: `Test-Flight-Improv/71-foreground-group-push-drain-gap-plan.md`
- Session classification: `implementation-ready`

## 2. Final Verdict

`implementation-ready`

The defect is narrow, fully local to the client, and verifiable. The foreground
`FirebaseMessaging.onMessage` handler in `lib/main.dart` only drains the 1:1
inbox and never routes a `type: "group_message"` push to
`drainGroupOfflineInboxForGroup`. The background handler already does
type-aware route parsing, and the notification-open / resume paths already
dispatch to the correct inbox — the foreground path never caught up.

The fix is a type-aware foreground router that mirrors the background handler's
already-shipped parsing, then dispatches to the existing
`drainGroupOfflineInboxForGroup` for group pushes and the existing 1:1 drain
for conversation pushes. No new transport, no relay change, no schema change.

## 3. Real Scope

This plan changes only the foreground FCM message path:

- route `FirebaseMessaging.onMessage` by `NotificationRouteTarget` kind instead
  of unconditionally draining the 1:1 inbox
- call `drainGroupOfflineInboxForGroup(groupId)` for group pushes so that an
  in-app foregrounded device fetches the stored relay envelope and re-injects
  it through `groupMessageListener.handleReplayEnvelope`
- rely on the existing messageId-based incoming-message dedupe to prevent
  duplicate replay banners; do not add a foreground
  `recentRemoteNotificationGate` write
- preserve existing 1:1 behavior for conversation / contact-request / intros
- add observability so "did foreground drain run, and for which kind" is
  visible in the flow-event stream

This plan does not:

- change relay push payload shape
- change gossipsub topic re-subscription logic (separate concern in
  `66-event-driven-group-continuity-sweep`)
- change OS-level notification display behavior
- reshape the 1:1 inbox staging/ack contract

## 4. Closure Bar

This area is good enough when all of the following are true at the same time:

- user C has the app foregrounded, is a member of Group-1, is registered for
  push, and has temporarily fallen off the Group-1 gossipsub mesh
- user A sends a message in Group-1
- the FCM push arrives while user C is foregrounded
- user C's in-app chat thread reflects the new message within the same
  foreground session (no background/resume cycle required)
- no duplicate in-app banner appears for the same `messageId`
- the existing 1:1 foreground delivery path continues to work for
  conversation / contact-request / intros pushes
- the existing notification-open tap path still drains the correct group
- the existing resume path still drains both inboxes

## 5. Source of Truth

Primary repo evidence:

- `lib/main.dart` — foreground `onMessage` at `:2502-2509` (the defect site)
- `lib/features/push/application/background_message_handler.dart` — the
  type-aware parsing model to mirror (`:58-70`)
- `lib/features/push/application/prepare_notification_open_use_case.dart` —
  reference for kind-based routing (`:25-39`)
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` —
  `drainGroupOfflineInboxForGroup` at `:108`
- `lib/core/services/p2p_service_impl.dart` — `drainOfflineInbox` at `:2850`
  and `_drainOfflineInboxDurably` at `:964` (1:1 inbox path)
- `lib/core/notifications/notification_route_target.dart` — `fromRemoteMessageData`
- `lib/features/push/application/show_notification_use_case.dart` —
  lifecycle-bound local notification suppression (`:69-109`)
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart` —
  messageId dedupe on replay (`:43-67`)
- `lib/features/groups/application/group_message_listener.dart` —
  `handleReplayEnvelope` at `:111`, notification emission at `:243`
- `lib/core/lifecycle/handle_app_resumed.dart` — reference for the full
  resume drain sequence (`:130`, `:184`)
- `go-relay-server/inbox.go` — relay-side `buildGroupPushMessage` sets
  `type: "group_message"` and `groupId` in `data`

Primary test and gate docs:

- `Test-Flight-Improv/52-notification-journey-test-matrix.md`
- `Test-Flight-Improv/53-notification-background-delivery-reliability-plan.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`

Disagreement rule:

- current code on `main` beats stale prose
- behavior defined here must pass the unit / integration / smoke / regression
  suites listed in §10 before the plan is treated as closed

## 6. Exact Problem Statement

The current code permits the following user-visible failure:

1. User C's app is foregrounded.
2. User C is a member of Group-1.
3. User C's gossipsub subscription to the Group-1 topic is not live (e.g.,
   mesh not re-formed after a network flap, partial group recovery in flight,
   peer just rejoined but topic peers not settled).
4. User A sends a message in Group-1. The relay stores it in the group inbox
   and fans out an FCM push to user C.
5. FCM delivers the push to user C's device. Because the app is foregrounded,
   iOS does not auto-show a banner and Android also defers to the app.
   Flutter's `FirebaseMessaging.onMessage` fires.
6. `onMessage` calls `widget.p2pService.drainOfflineInbox()` — the **1:1**
   inbox. The group inbox is not drained.
7. The group message stays in the relay group inbox, unread by user C.
8. User C sees nothing new in Group-1 until a later trigger runs the group
   drain (notification tap, app resume, periodic recovery, etc.). That can
   be minutes or longer.

Repo-backed diagnosis:

- `lib/main.dart:2508` unconditionally calls `drainOfflineInbox()`.
- `drainOfflineInbox()` in `p2p_service_impl.dart:2850` delegates to
  `_drainOfflineInboxDurably()`, which only hits the 1:1 inbox via
  `_retrievePendingInboxPage(toPeerId: ...)`.
- There is no call to `drainGroupOfflineInbox` or
  `drainGroupOfflineInboxForGroup` anywhere in the foreground push handler.
- The background handler in `background_message_handler.dart:58-70`
  already builds `NotificationRouteTarget.fromRemoteMessageData(message.data)`.
  The foreground handler does not.
- Relay pushes for groups carry `data["type"] == "group_message"` and
  `data["groupId"]` (see `go-relay-server/inbox.go:369-375`). The
  information required to route is already on the wire.

What must improve:

- foreground FCM path must route by `NotificationRouteTarget` kind
- foreground path must call the targeted group drain for group pushes
- foreground path must keep duplicate behavior on the existing
  messageId-based listener dedupe, without adding a new foreground
  `recentRemoteNotificationGate` write
- foreground path must remain non-blocking for the message loop (drain runs
  via `unawaited(...)` like today)

## 7. Current State

Affected code areas that will change (or get a new adjacent use case):

- `lib/main.dart` — foreground listener wiring
- new: `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- tests:
  - new: `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
  - new: `integration_test/foreground_group_push_drain_test.dart`
  - extend: `test/core/notifications/notification_route_contract_matrix_test.dart`
    (or equivalent existing notification route contract coverage)
  - extend: `Test-Flight-Improv/52-notification-journey-test-matrix.md`

Observability surfaces that already exist and will be reused:

- `emitFlowEvent` (`lib/core/utils/flow_event_emitter.dart`)
- existing `PUSH_FOREGROUND_MESSAGE_RECEIVED` event in `main.dart:2505`
- existing `GROUP_DRAIN_OFFLINE_INBOX_SINGLE_*` events in
  `drain_group_offline_inbox_use_case.dart`

Not in scope but adjacent (will be flagged but not fixed here):

- `shouldFanoutPush` O(N) double-LRANGE on the relay
- missing `relay_group_push_fanout_spread_seconds` histogram
- hybrid `content-available: true` + alert APNs payload

## 8. Target Behavior

Given a remote FCM message received while the app is foregrounded, the
handler must:

1. Emit `PUSH_FOREGROUND_MESSAGE_RECEIVED` with `messageId` and `dataKeys`
   (unchanged).
2. Build `routeTarget = NotificationRouteTarget.fromRemoteMessageData(data)`.
3. If `routeTarget == null` → log
   `PUSH_FOREGROUND_MESSAGE_UNROUTABLE` and return. **Do not** call either
   drain — the prior blanket 1:1 drain was a latent footgun for
   post / post_comment / unknown kinds.
4. If `routeTarget.kind` is one of `conversation`, `contactRequest`,
   `intros` → call `drainOfflineInbox()` (1:1 path; today's behavior for
   these kinds).
5. If `routeTarget.kind == group` and `routeTarget.groupId` is non-empty →
   call `drainGroupOfflineInboxForGroup(groupId)`.
6. Do **not** write to `recentRemoteNotificationGate`. Foreground pushes
   do not create an OS banner, so there is nothing to suppress later.
   Duplicate prevention is handled by messageId dedupe inside
   `handleIncomingGroupMessage` and `handleIncomingChatMessage`
   (see §9.3).
7. Wrap the drain in try/catch; on error, emit
   `PUSH_FOREGROUND_DRAIN_ERROR` with kind + error and do not rethrow
   (must not crash the FCM stream).
8. All drains remain `unawaited` from the stream callback (non-blocking).

## 9. Design

### 9.1 New use case

```dart
// lib/features/push/application/handle_foreground_remote_message_use_case.dart

typedef DrainOfflineInboxFn = Future<void> Function();
typedef DrainGroupOfflineInboxForGroupFn =
    Future<void> Function(String groupId);

Future<void> handleForegroundRemoteMessage({
  required Map<String, dynamic> data,
  required String? messageId,
  required DrainOfflineInboxFn drainOfflineInbox,
  required DrainGroupOfflineInboxForGroupFn drainGroupOfflineInboxForGroup,
});
```

Responsibilities listed in §8. The use case owns:

- route target resolution
- per-kind dispatch
- error logging

Duplicate prevention stays with the existing incoming-message dedupe in the
group / chat listeners. The foreground use case does not introduce a second
suppression layer.

The call-site in `main.dart` becomes a two-line bridge: build the args and
`unawaited(handleForegroundRemoteMessage(...))`.

### 9.2 Call-site wiring

```dart
// lib/main.dart (replacement for line 2502-2509)

FirebaseMessaging.onMessage.listen((message) {
  emitFlowEvent(
    layer: 'FL',
    event: 'PUSH_FOREGROUND_MESSAGE_RECEIVED',
    details: {'messageId': message.messageId},
  );
  unawaited(
    handleForegroundRemoteMessage(
      data: message.data,
      messageId: message.messageId,
      drainOfflineInbox: widget.p2pService.drainOfflineInbox,
      drainGroupOfflineInboxForGroup: (groupId) =>
          drainGroupOfflineInboxForGroup(
            bridge: widget.bridge,
            groupRepo: widget.groupRepository,
            msgRepo: widget.groupMessageRepository,
            groupId: groupId,
            groupMessageListener: widget.groupMessageListener,
            mediaAttachmentRepo: widget.mediaAttachmentRepository,
            reactionRepo: widget.reactionRepository,
          ),
    ),
  );
});
```

### 9.3 Duplicate-banner analysis (revised twice)

First revision removed the earlier "mark before drain prevents a duplicate
banner" claim because `maybeShowNotification` only consults the gate when
`lifecycleState != AppLifecycleState.resumed`
(`show_notification_use_case.dart:86`). Second revision goes further: the
foreground use case **does not write to the gate at all**. The mark is
useless both on the foreground path (lifecycle == resumed) and on the
resume-drain path (by the time `handleAppResumed` runs its Dart body, the
OS has already flipped lifecycle to `resumed`; `getAppLifecycleState()`
returns `resumed` throughout the drain's `handleReplayEnvelope` chain,
and the gate is skipped there too). Writing the mark from the foreground
handler would be dead code writing to a consumer that never reads it in
either scenario this plan covers.

The background handler keeps its own mark
(`background_message_handler.dart:67-70`) because the OS shows the push
banner automatically when the app is backgrounded; that mark is
consumed by a *later* `maybeShowNotification` call whose lifecycle
happens to be `!= resumed` (e.g., the precise moment the OS resume event
is in-flight but Dart has not observed it yet, which is narrow but real
for background-delivered pushes). The foreground handler does not face
that race — `onMessage` fires in-process, lifecycle is already `resumed`,
and no OS banner was shown — so it has nothing to suppress later.

Duplicate prevention for the three scenarios relies entirely on the
messageId-based dedupe inside `handleIncomingGroupMessage`
(`lib/features/groups/application/handle_incoming_group_message_use_case.dart`
returns `null` for an already-persisted `messageId`):

1. **Only FCM delivers (primary target)**: drain replays → DB insert
   succeeds → `_handleMessage` calls `maybeShowNotification` → one banner
   (unless `isViewingConversation` suppresses). Correct.
2. **Only gossipsub delivers (healthy path)**: live listener → DB insert
   → one banner. Correct.
3. **Both deliver (race)**: first arrival wins at the DB. Second arrival
   hits `handleIncomingGroupMessage`'s null-return dedupe, so
   `_handleMessage` never reaches `maybeShowNotification`. One banner
   only. Correct.

Consequence: the foreground use case has no gate interaction. That
removes a file I/O per push, removes the ordering question entirely, and
eliminates a false-parity argument with the background handler. The
tests below are updated accordingly and do not add gate-specific
foreground assertions.

### 9.4 Non-goals inside the use case

- no re-subscribe attempt to the gossipsub topic (separate concern)
- no retry on drain failure (existing retry paths cover next resume)
- no direct notification display (`group_message_listener` already does this)

## 10. TDD Layering

All tests below are written **before** implementation. Each layer has a
failing-first expectation and a green bar.

### 10.1 Unit tests — `handle_foreground_remote_message_use_case_test.dart`

Fake collaborators: stub `DrainOfflineInboxFn`, stub
`DrainGroupOfflineInboxForGroupFn`, and capture emitted flow events.

Required cases:

| # | Name | Input | Assertion |
|---|---|---|---|
| U1 | group_message routes to group drain | `{type: group_message, groupId: g1, message_id: m1}` | `drainGroupOfflineInboxForGroup('g1')` called once, 1:1 drain not called |
| U2 | new_message routes to 1:1 drain | `{type: new_message, sender_id: p1}` | 1:1 drain called once, group drain not called |
| U3 | contact_request / intros / group_invite stay on the 1:1 path | `{type: contact_request}` / `{type: intros}` / `{type: group_invite}` | each routes to `drainOfflineInbox()` and never to the group drain |
| U4 | post / post_comment / unknown kinds are unroutable | `{type: post_create, postId: p1}` or `{type: weird}` | neither drain called; `PUSH_FOREGROUND_MESSAGE_UNROUTABLE` emitted |
| U5 | empty groupId on group_message is unroutable | `{type: group_message, groupId: ''}` | neither drain called; unroutable event emitted |
| U6 | payload-only fallback still routes a group push | no `type`, only `payload: group:g1` | target resolves via `fromPayload`; group drain called with `g1` |
| U7 | group drain failure is swallowed | group drain returns `Future.error('boom')` | no rethrow; `PUSH_FOREGROUND_DRAIN_ERROR` emitted with `kind: group` |
| U8 | 1:1 drain failure is swallowed | 1:1 drain returns `Future.error('boom')` | no rethrow; `PUSH_FOREGROUND_DRAIN_ERROR` emitted with `kind: conversation` |
| U9 | missing or non-string message ids do not block routing | `{type: group_message, groupId: g1}` or `{type: group_message, groupId: g1, id: 42}` | does not crash; group drain still runs |

Fixtures: move the `data` map builders into a shared helper
`test/features/push/application/remote_message_fixtures.dart` so
background-handler tests and foreground tests share the same wire shape.

### 10.2 Unit tests — route_target fixtures

Extend `notification_route_target_test.dart` only where current coverage is
missing:

- payload-only `group:g1` resolves to a group target
- malformed `group_message` with an empty `groupId` returns `null`
- keep the existing route-contract matrix as the shared guard for
  conversation / group / post dispatch policy

### 10.3 Unit tests — `main` wiring smoke

Do **not** introduce a new `main_push_listener_builder.dart` or any other
test-only production seam for this bug. `main.dart` should stay a thin bridge
that emits `PUSH_FOREGROUND_MESSAGE_RECEIVED` and delegates once via
`unawaited(handleForegroundRemoteMessage(...))`.

If an equivalent root-listener test already exists and can be extended
cheaply, use it. Otherwise rely on the use-case unit tests plus the foreground
integration test below.

### 10.4 Integration tests — `integration_test/foreground_group_push_drain_test.dart`

Use the existing Flutter integration_test rig plus a stubbed relay client
(or the existing `test_driver` relay fakes). Do not require a live EC2
connection.

| # | Scenario | Setup | Act | Assert |
|---|---|---|---|---|
| I1 | foreground group push drains and surfaces message | join Group-1, stop gossipsub topic subscription, pre-stage a group envelope in the fake relay group inbox under messageId m1 | inject an `onMessage` event with `type: group_message, groupId: G1, message_id: m1` | after `pumpAndSettle`, group message repo has a row with id m1 AND exactly one in-app notification was emitted |
| I2 | foreground group push does NOT duplicate when gossipsub delivers first | subscribe to topic normally; deliver via gossipsub pipe, then inject the FCM `onMessage` a moment later | — | exactly one message row for m1; exactly one in-app notification |
| I3 | foreground 1:1 push still drains 1:1 | pre-stage a 1:1 inbox entry | inject `onMessage` with `type: new_message, sender_id: p1` | 1:1 thread shows the new row; group drain not invoked |
| I4 | foreground post push does not trigger any drain | — | inject `type: post_create, postId: p1` | neither drain invoked; no error |

### 10.5 Smoke tests — `notification-sound-smoke-plan.md` extension

Add to the notification smoke matrix
(`Test-Flight-Improv/52-notification-journey-test-matrix.md`) as a new row:

```
JRN-FG-GRP-01
  Pre: App foreground, Group-1 joined, user C off Group-1 mesh
  Action: User A sends message in Group-1
  Expect: Within 5s of FCM receipt, Group-1 thread reflects the new row;
          exactly one in-app banner (or zero if thread open and tracker
          says it is visible); no duplicate on later resume.
  Evidence: PUSH_FOREGROUND_MESSAGE_RECEIVED → GROUP_DRAIN_OFFLINE_INBOX_SINGLE_BEGIN → GROUP_DRAIN_OFFLINE_INBOX_SINGLE_DONE
```

Plus manual smoke steps in
`71-foreground-group-push-drain-gap-session-1-plan.md` (to be authored
alongside the first implementation session) covering:

- two physical devices, user A sends while user C has app foregrounded
- confirm the Apr 21 log-shape reproduction: relay fanout timestamp ≤ 1s
  apart, client foreground drain fires within 1s of FCM receipt
- the mesh-gap condition is non-deterministic on real devices (leaving
  and rejoining a group is the best manual approximation but does not
  guarantee the target state). For CI-reproducible coverage, the I1-I4
  integration tests use a stubbed gossipsub subscription so the target
  state is deterministically induced; the two-device manual smoke is
  attested separately as "best-effort manual verification," not part
  of the CI gate. §16 criterion 6 is marked `manual-attested` rather
  than `ci-enforced` for this reason

### 10.6 Regression tests

These protect surfaces that must not break:

- R1: `handle_app_resumed_test.dart` — assert both 1:1 drain and group drain
  still run on resume (not replaced by the new foreground routing).
- R2: `prepare_notification_open_use_case_test.dart` — assert tap-open
  group drain still runs (independent of foreground path).
- R3: `background_message_handler_test.dart` — assert background remote
  dedupe mark still fires (unchanged behavior).
- R4: `show_notification_use_case_test.dart` — keep the resumed / background
  suppression boundary green so this fix does not shift local notification
  behavior while routing foreground pushes correctly.

### 10.7 Negative / failure-mode coverage

- N1: `NotificationRouteTarget.fromRemoteMessageData` returns null for
  garbled payload → no drain, no throw (covered by U4 / U5).
- N2: `drainGroupOfflineInboxForGroup` hangs → foreground stream must
  still accept the next `onMessage` event (use cases are dispatched via
  `unawaited`, and the test exercises this by not awaiting the first
  future).

### 10.8 Test gates and CI

Do **not** add a new named gate or widen `scripts/run_test_gates.sh` for this
fix. The existing gate lists are intentionally bounded.

Required verification is:

- direct suites for U1-U9, I1-I4, and R1-R4
- existing `./scripts/run_test_gates.sh groups`
- existing `./scripts/run_test_gates.sh baseline` if the final change remains
  rooted in `lib/main.dart` / app-root wiring
- existing `./scripts/run_test_gates.sh transport` only if implementation
  expands beyond the foreground listener seam into broader lifecycle /
  bootstrap / transport behavior

## 11. Observability

New flow events (authoritative for post-release monitoring):

- `PUSH_FOREGROUND_MESSAGE_ROUTED` — details: `kind`, `hasGroupId`,
  `hasMessageId`
- `PUSH_FOREGROUND_MESSAGE_UNROUTABLE` — details: `type`, `dataKeys`
- `PUSH_FOREGROUND_DRAIN_ERROR` — details: `kind`, `error`

Existing events that become load-bearing here:

- `PUSH_FOREGROUND_MESSAGE_RECEIVED` (already emitted)
- `GROUP_DRAIN_OFFLINE_INBOX_SINGLE_BEGIN` / `_DONE` / `_TIMING` (already
  emitted by the group drain)

Dashboard row to add in the internal observability doc (not a code change):

- `foreground group drain success ratio (24h)` =
  count(`_DONE`) / count(`PUSH_FOREGROUND_MESSAGE_ROUTED` with
  `kind=group`). A sustained drop below 0.95 is the regression signal.

## 12. Rollout

- No remote feature flag. The earlier draft proposed a build-time
  constant `kForegroundGroupDrainEnabled` defaulting to `true`. Review
  cycle 2 correctly identified this as cosmetic — a committed
  `const bool = true` requires a new binary to flip to `false`, which
  is the same cost as any other code change. Dropped.
- If an emergency off-switch is ever needed, add a proper
  `--dart-define` (`MKNOON_FOREGROUND_GROUP_DRAIN=false`) at that time,
  consumed via `String.fromEnvironment` inside the use case. Do not
  pre-build this scaffolding without a concrete need.
- Ship in the next TestFlight build; monitor for 48h on
  `PUSH_FOREGROUND_DRAIN_ERROR` spikes before promoting.

## 13. Migration / Back-compat

- No on-disk schema change.
- `recent_remote_notification_gate` file format unchanged — the foreground
  path does not add new writes.
- Remote payload shape is unchanged; older clients interoperate and rollback
  is safe.

## 14. Non-Goals (explicitly out of scope)

- fixing the relay-side `shouldFanoutPush` O(N) double-LRANGE
- adding `relay_group_push_fanout_spread_seconds` histogram
- auditing `content-available: true` + alert APNs payload shape
- gossipsub topic re-subscription on resume (66-event-driven-group-continuity-sweep)
- fixing the foreground push token re-registration doubling visible in
  relay logs

Each of these is a real concern surfaced by yesterday's incident analysis;
they belong in their own plans so this fix stays narrow and shippable.

## 15. Open Questions

- Q1: Should the foreground path also call `drainOfflineInbox()` (1:1) for
  group pushes as a belt-and-suspenders? **Tentative answer: no.** The
  sender peer of a group push is the group, and the relay does not post a
  1:1 inbox entry for it. Calling 1:1 drain on group pushes would re-emit
  the load that yesterday's analysis already flagged (`shouldFanoutPush`
  scans). Test U1 encodes the "only group drain" expectation.
- Q2: Should we wire the missing `groupId` case to the non-targeted
  `drainGroupOfflineInbox()` (all groups)? **Tentative answer: no for
  this plan.** The relay always sets `groupId` in the payload
  (`go-relay-server/inbox.go:371`). If we see `PUSH_FOREGROUND_MESSAGE_UNROUTABLE`
  with `type=group_message` in telemetry, that is a relay regression, not a
  client fix.
- Q3: How does this interact with a freshly-logged-in user on a new
  device who receives a group push before they have joined the topic
  locally? Leave existing `drain_group_offline_inbox_use_case.dart`
  behavior unchanged for this plan. This foreground fix should only route
  to the targeted drain; it does not need a new foreground-specific
  unknown-group contract beyond the existing drain/listener coverage.

## 16. Acceptance Criteria

The plan is closed when all of the following hold on `main`:

1. `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
   contains all U1-U9 cases and passes.
2. `integration_test/foreground_group_push_drain_test.dart` contains all
   I1-I4 cases and passes on the supported Flutter test runner.
3. R1-R4 regression tests pass without modification beyond fixture
   updates.
4. `Test-Flight-Improv/52-notification-journey-test-matrix.md` includes
   `JRN-FG-GRP-01` row.
5. Any new direct test coverage is classified in
   `Test-Flight-Improv/test-gate-definitions.md` without widening the frozen
   named gate lists or changing `scripts/run_test_gates.sh`.
6. Two-device manual smoke (user A sends, user C foregrounded) is
   attested by the engineer who lands the session-3 plan. Marked
   `manual-attested` per §10.5 — the mesh-gap state is not CI-reproducible
   on real devices, so CI coverage for the target scenario is delegated to
   I1-I4 with the stubbed gossipsub subscription.
7. 48h of TestFlight telemetry shows
   `PUSH_FOREGROUND_DRAIN_ERROR` rate < 1% of
   `PUSH_FOREGROUND_MESSAGE_ROUTED{kind=group}`.

## 17. Session Breakdown (forward reference)

Session plans to be authored once this plan is accepted:

- `71-foreground-group-push-drain-gap-session-1-plan.md` — write U1-U9
  and R1-R4 red, introduce `handle_foreground_remote_message_use_case.dart`
  skeleton (no logic), land the thin `main.dart` bridge, all tests still red.
- `71-foreground-group-push-drain-gap-session-2-plan.md` — implement the
  use case to make U1-U9 green; wire integration harness for I1-I4.
- `71-foreground-group-push-drain-gap-session-3-plan.md` — integration
  green, matrix updated, direct-test classification recorded as needed,
  TestFlight build.
