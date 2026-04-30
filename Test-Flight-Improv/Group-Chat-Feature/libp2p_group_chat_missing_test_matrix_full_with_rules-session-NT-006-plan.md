# NT-006 Execution Plan

## Final verdict

Reusable for execution. The spawned planner produced only a scaffold under the
bounded wait, so this file is the controller's single local artifact-only plan
fallback for session `NT-006`.

## Final plan

### real scope

Own only matrix row `NT-006`: notification dedupe across live PubSub delivery,
offline inbox/sync replay, remote push announcement, and foreground push drain
for the same group message.

Allowed work:

- collect current repo proof for the row before changing code
- add focused regressions that prove one persisted incoming row, one unread
  increment, and at most one user notification for the same group `messageId`
  across live listener, inbox replay, background push, and foreground drain
- patch only the smallest notification, remote-gate, listener, or drain seam
  needed if the proof fails
- update the source matrix, `test-inventory.md`, this plan evidence, and the
  breakdown ledger only after execution proof is concrete

Out of scope:

- new receipt generation/signing (`NT-005`)
- per-group notification preferences beyond existing mute behavior (`NT-002`)
- read-receipt privacy (`NT-004`)
- OS-state notification matrix closure (`NT-007`)
- broad push payload privacy already closed by `NT-001`
- direct peer sync protocol work (`OS-003`, `OS-006`, `API-007`)

### closure bar

`NT-006` may close only when repo evidence proves the same group message
identity arriving through PubSub/live listener, offline inbox or sync replay,
background push announcement, and foreground push drain:

- persists exactly one incoming `GroupMessage`
- leaves `GroupMessageRepository.getUnreadCount(groupId)` incremented exactly
  once while unread
- displays at most one user notification for that message
- does not consume or clear unrelated notification dedupe entries
- still allows a distinct later message in the same group to notify and count
  normally

If this cannot be proven without a real device or relay fixture, keep the row
`Partial` and record a blocker rather than accepting broad adjacent evidence.

### source of truth

- Primary row: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`, row `NT-006`, now `Covered` after execution.
- Rollout controller state: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`, session `NT-006`, now `accepted` / `closure-verified`.
- Coverage inventory: `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`.
- Current code and tests win over stale prose.
- `scripts/run_test_gates.sh` is the execution source for named gates.

### session classification

`evidence-gated`.

Start by proving the current state. If direct repo evidence already closes the
row, record it and do not change production code. If focused proof exposes a
gap, reclassify execution locally to targeted implementation and land the
smallest code/test delta required for this row.

### exact problem statement

The source matrix says foreground drain dedupe exists, but full PubSub, sync,
push, and unread-count convergence is still broader. Current adjacent evidence
shows:

- `handleIncomingGroupMessage` dedupes by `messageId` before group/member lookup
  and falls back to content/timestamp dedupe for messages without IDs.
- `GroupMessageListener` calls `maybeShowNotification` after a new persisted
  group message and passes `RecentRemoteNotificationGate.consumeIfRecentAnnouncement`
  with route payload `group:<groupId>|message:<messageId>`.
- `firebaseMessagingBackgroundHandler` marks the recent remote notification
  gate for routable `group_message` pushes with a message-aware key.
- `handleForegroundRemoteMessage` routes group pushes into
  `drainGroupOfflineInboxForGroup`.
- `foreground_group_push_drain_test.dart` already proves targeted group drain,
  media drain dedupe on repeated foreground push, live-then-foreground push
  leaves one message/one notification, and 1:1/post routing separation.
- `group_notification_dedupe_integration_test.dart` already proves a background
  group push announcement can suppress a later local group notification for
  the same message.

The missing row-specific proof is the complete same-message cross-path contract,
especially unread count exactly once and remote-push dedupe when foreground
drain or live PubSub overlaps with an already announced remote push.

### files and repos to inspect next

Production candidates:

- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/core/notifications/recent_remote_notification_gate.dart`
- `lib/core/notifications/remote_notification_identity.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository_impl.dart`

Test candidates:

- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/groups/domain/repositories/group_message_repository_impl_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`
- `test/shared/fakes/fake_notification_service.dart`

### existing tests covering this area

- `test/integration/group_notification_dedupe_integration_test.dart` proves a
  background `group_message` push with `groupId` and `message_id` suppresses a
  later local group notification for the same message while the app is paused.
- `integration_test/foreground_group_push_drain_test.dart` proves foreground
  group push drains the targeted group inbox, repeated foreground media push
  drains/downloads once, live delivery followed by foreground push leaves one
  message and one notification, and 1:1/post pushes do not trigger group drain.
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  proves background and terminated group push routes call targeted group
  catch-up before routing.
- `GroupMessageRepository` implementations count unread incoming rows by
  `isIncoming && readAt == null`; duplicate message IDs therefore must not add
  extra persisted rows.

Known missing proof before this session:

- explicit unread-count assertion for the same `messageId` across live and
  foreground drain
- explicit background-push remote gate plus foreground drain/live overlap proof
  while not viewing the group
- a distinct-later-message control to prove dedupe is not over-broad

### regression/tests to add first

Add proof before production edits. Prefer extending existing tests rather than
creating new harnesses:

1. Extend `test/integration/group_notification_dedupe_integration_test.dart` or
   `integration_test/foreground_group_push_drain_test.dart` to mark a background
   `group_message` push in `RecentRemoteNotificationGate`, then replay the same
   message through the live group listener and/or foreground group inbox drain.
   Assert one persisted message, unread count `1`, and no second local
   notification for the same route payload/message ID.
2. Extend `integration_test/foreground_group_push_drain_test.dart` live-then-push
   coverage to assert `getUnreadCount('group-foreground') == 1` after the
   foreground drain replays the already-live message.
3. Add a distinct message control in the same harness: after the duplicate
   message is suppressed, deliver a second message with a different `messageId`
   and assert unread count increases to `2` and a second notification can be
   shown when not viewing the group.

If these tests already pass without code changes, the row can be closed as
evidence-only. If any test fails, keep the failing test and patch only the
owning seam.

### step-by-step implementation plan

1. Record `git status --short` before execution and treat all existing dirty
   files as prior-session or user work unless this session changes them.
2. Run the existing focused proof bundle:
   - `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`
   - `flutter test --no-pub integration_test/foreground_group_push_drain_test.dart`
   - `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
   - `flutter test --no-pub test/features/push/application/background_message_handler_test.dart`
3. Add the smallest red regression(s) from the previous section.
4. If the regressions pass on current code, do not edit production code. Record
   the evidence and proceed to closure.
5. If a regression fails because resumed foreground drain bypasses a recent
   remote-push announcement, patch `maybeShowNotification` and/or
   `GroupMessageListener` so message-aware remote-push dedupe can suppress the
   same message regardless of lifecycle state when the local notification would
   otherwise be shown. Preserve the existing "viewing conversation" suppression
   and avoid delaying foreground notifications unnecessarily.
6. If a regression fails because duplicate inbox/live replay persists a second
   row or increments unread twice, patch only the message identity propagation
   or dedupe path in `handleIncomingGroupMessage`,
   `drain_group_offline_inbox_use_case.dart`, or the foreground route data so
   the same wire `messageId` is preserved.
7. Re-run focused direct tests after each targeted patch.
8. Run the session gate bundle listed below.
9. Update docs only after proof is green or a real blocker is confirmed:
   source matrix row `NT-006`, `test-inventory.md`, this plan evidence section,
   and the session breakdown ledger/closure ledger.

### risks and edge cases

- Remote push may use `message_id`, `messageId`, `id`, or `msgId`; dedupe must
  normalize the same aliases used by `remoteNotificationMessageIdFromData`.
- Group route payloads may be `group:<groupId>` or
  `group:<groupId>|message:<messageId>`; message-aware keys must not suppress
  unrelated messages in the same group.
- `maybeShowNotification` currently checks the remote gate only when lifecycle
  is not resumed. If changed, avoid adding a foreground delay or suppressing
  distinct messages.
- Foreground drain should not trigger 1:1 drain or post drain for group pushes.
- Duplicate message enrichment for media descriptors must not create extra
  notifications or unread rows.
- A group muted by `isMuted` must remain silent regardless of dedupe behavior.

### exact tests and gates to run

Focused direct tests:

- `flutter test --no-pub test/integration/group_notification_dedupe_integration_test.dart`
- `flutter test --no-pub integration_test/foreground_group_push_drain_test.dart`
- `flutter test --no-pub test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test --no-pub test/features/push/application/background_message_handler_test.dart`
- `flutter test --no-pub test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`

Row/gate checks:

- `flutter test --no-pub test/features/groups`
- `flutter test --no-pub test/features/groups/integration`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Configured device or real-network relay gate when execution relies on device or
relay proof:

- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD MKNOON_RELAY_ADDRESSES=/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g ./scripts/run_test_gates.sh group-real-network-nightly`

`SMOKE-GAP-06` is a source-matrix row grouping unless the repo defines it as a
runner target during execution. Do not invent a new shell command for it.

### known-failure interpretation

- Pre-existing dirty worktree changes are not NT-006 regressions unless this
  session modifies the same files and the failure points at this row.
- A broad groups or integration gate failure outside notification dedupe,
  unread counts, foreground drain, or group message listener behavior must be
  documented as unrelated and not fixed in this session.
- A configured real-network gate that reports missing external fixtures may
  support gate wiring but cannot close a required real-device proof by itself.

### done criteria

The execution session is done when one of these is true:

- Accepted: source matrix `NT-006` is `Covered`, `test-inventory.md` records
  concrete file/test evidence, the breakdown ledger records `NT-006` as
  `accepted` / `closure-verified`, focused tests and required gates are
  recorded in this plan, and no unrelated session deltas are hidden.
- Blocked: source matrix remains `Partial`, this plan and the breakdown record
  the blocker class, exact missing evidence, commands run, and the next safe
  action.

### scope guard

Do not:

- redesign notification routing
- add receipt protocols
- add direct peer sync APIs
- change push payload privacy beyond the dedupe fields needed here
- rewrite feed unread projection
- introduce new global notification throttling that suppresses distinct group
  messages
- mark `NT-006` covered without row-specific PubSub/inbox/push/foreground drain
  and unread-count evidence

### accepted differences / intentionally out of scope

- Device-lab OS foreground/background/locked/resume breadth remains `NT-007`.
- Delivery receipts remain `NT-005`.
- A fake-network/integration proof may close repo-owned dedupe behavior only if
  it directly exercises the same listener, inbox drain, foreground push, and
  remote-gate seams used in production.

### dependency impact

Closing `NT-006` contributes to `SMOKE-GAP-06` and reduces risk for later
notification and UI trust rows. If this plan finds that dedupe depends on
missing real OS-state fixtures, keep later `NT-007` work blocked or separate
instead of broadening this session.

## Structural blockers remaining

None for planning. Execution may still discover a real product/test blocker.

## Incremental details intentionally deferred

- Broader per-group mention-only/privacy notification settings remain `NT-002`.
- Real OS-state notification matrix remains `NT-007`.

## Accepted differences intentionally left unchanged

- Existing `NT-001` push privacy closure is not reopened.
- Existing `RecentRemoteNotificationGate` payload TTL and message-aware TTL
  values remain unchanged unless a direct NT-006 regression proves they are the
  cause of duplicate same-message notification behavior.

## Exact docs/files used as evidence

- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `lib/features/groups/application/handle_incoming_group_message_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/core/notifications/recent_remote_notification_gate.dart`
- `lib/core/notifications/remote_notification_identity.dart`
- `lib/core/notifications/notification_route_target.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `integration_test/foreground_group_push_drain_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

## Why the plan is safe or unsafe to implement now

Safe to execute now. The row has no dependency, the plan is evidence-first, the
scope is limited to existing notification/listener/drain seams, direct tests
already exist near the behavior, and the stop rule prevents broad notification
or sync redesign. The worktree is dirty, so execution must record
`git status --short` before changing anything and classify only current-session
deltas.

## Execution Result

### Final execution verdict

Accepted. The row-specific proof exposed a foreground-state remote-push dedupe
gap, and the implementation was limited to `maybeShowNotification`: it now
consults the recent remote-push announcement gate whenever a local notification
would otherwise be shown, including resumed foreground state, while preserving
active-conversation suppression and avoiding any foreground delay.

### Production and test deltas

- `lib/features/push/application/show_notification_use_case.dart` now checks
  `consumeRecentRemoteNotificationAnnouncement` for resumed foreground
  notifications as well as background/inactive notifications.
- `test/features/push/application/show_notification_use_case_test.dart` proves
  resumed group-message notifications are suppressed when the exact recent
  remote push announcement is present.
- `integration_test/foreground_group_push_drain_test.dart` now proves:
  live-plus-foreground-push same-message dedupe leaves one persisted message,
  unread count `1`, and one notification; background-announced-plus-foreground
  drain leaves one persisted message, unread count `1`, and no duplicate local
  notification; unrelated dedupe entries remain consumable; and a distinct
  later message increments unread to `2` and notifies normally.

### Verification

Passed:

- `flutter test --no-pub --reporter compact test/features/push/application/show_notification_use_case_test.dart test/integration/group_notification_dedupe_integration_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart test/features/push/application/background_message_handler_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/groups/application/group_message_listener_test.dart`
- `flutter test --no-pub --reporter compact test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name "drain after watchdog restart retrieves messages exactly once|drain after in-place recovery still allowed and idempotent|resume drains missed announcement messages exactly once|watchdog restart drains missed group messages exactly once"`
- `FLUTTER_DEVICE_ID=347FB118-10D0-40C8-A05B-B0C3BD6B8CCD flutter test --no-pub -d 347FB118-10D0-40C8-A05B-B0C3BD6B8CCD --reporter expanded integration_test/foreground_group_push_drain_test.dart`
- `flutter test --no-pub --reporter compact test/features/groups/integration`
- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check` (`694/694 test files classified`)

Observed unrelated failure:

- `flutter test --no-pub --reporter compact test/features/groups` failed one
  MD-011 media/epoch replay assertion in
  `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  (`MD-011 removed member cannot decode future media replay with only the old
  epoch`, expected `null` but got a `GroupMessage`). The focused NT-006 drain
  replay subset and canonical `groups` gate passed, so this is not treated as
  an NT-006 blocker.

### Closure docs updated

- Source matrix row `NT-006` is `Covered`.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` records NT-006 as
  `Covered`.
- The session breakdown ledger, ordered row, and `NT-006 Closure Ledger` record
  `accepted` / `closure-verified`.
