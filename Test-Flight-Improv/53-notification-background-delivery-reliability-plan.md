# 53 - Notification Background Delivery Reliability Plan

## Final Verdict

`implementation-ready`

The current repo already has the main notification routing pieces in place, and
the relay already builds visible Android/APNS alert payloads for chat and group
pushes. The missing reliability seam is narrower: background delivery can still
fail when push registration misses startup and never retries on resume, and the
current app-open recovery path still treats replayed inbox messages as
notification-worthy events. The plan below stays bounded to those seams plus
the two remaining app-side notification findings that are still worth fixing.

## 1. Real Scope

This plan changes only notification reliability and recovery behavior for
message delivery:

- ensure the receiver can recover push-token registration on app resume instead
  of relying on the first startup attempt only
- ensure app-open inbox recovery does not create a second local notification
  for messages that are being replayed because the user opened the app
- remove the blanket `cancelAll()` behavior on normal resume so the app does
  not wipe unrelated reminders just because it was foregrounded
- make background fallback copy honor `pushTitle` / `pushBody` when those keys
  are already emitted by the group send path

This plan does not redesign the full notification product model.

## 2. Closure Bar

This area is good enough for the current architecture when all of the following
are true at the same time:

- if user B backgrounds the app after prior startup, a new 1:1 or group
  message can still produce a push-notification path without requiring user B
  to reopen the app first
- if user B later opens the app and the message is recovered from relay inbox
  or staged replay, that recovery does not trigger a second local notification
- notification-open flows still clear app-owned notifications, but a plain app
  resume does not globally clear every delivered notification
- group/data-only fallback copy does not regress back to the generic
  `New Message` banner when richer `pushTitle` / `pushBody` data already exists
- chat and group dedupe behavior remains exact-message aware where the remote
  payload includes a message id

## 3. Source Of Truth

Primary repo evidence:

- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/push_registration_coordinator.dart`
- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/recent_remote_notification_gate.dart`
- `lib/core/notifications/remote_notification_identity.dart`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`

Primary test and gate docs:

- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`

Disagreement rule:

- current code and passing tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` define named-gate
  expectations
- relay push payload tests in `go-relay-server/inbox_test.go` are the source of
  truth for the repo-owned APNS/FCM alert contract

## 4. Session Classification

`implementation-ready`

## 5. Exact Problem Statement

The current code still allows the following user-visible failure:

- user B backgrounds the app
- user A sends a message
- no notification arrives while user B is backgrounded
- when user B opens the app, recovery drains inbox or replays the message and a
  local notification appears late instead

Repo-backed diagnosis:

- push registration is started in
  `startup_router.dart` via `pushRegistrationCoordinator.ensureStarted()`, but
  `retryNow()` is never wired into normal resume handling
- `registerPushToken()` can return `noToken` on iOS when APNS or FCM token
  readiness lags startup, and the coordinator's scheduled retry does not help
  once the app is suspended in the background
- `maybeShowNotification()` currently shows a local notification for replayed
  messages whenever the user is not already viewing that conversation, even if
  the replay is happening because the user explicitly opened the app to recover
  queued messages
- `handleAppResumed()` currently calls `clearDeliveredNotificationsFn()` on
  every resume, which is broader than the notification-open contract and can
  clear still-useful reminders
- the group send path already persists `pushTitle` / `pushBody`, but the
  background fallback still ignores those keys

What must improve:

- background push reachability after startup token lag
- no second notification on app-open recovery
- more meaningful notification clearing
- richer fallback copy parity

What must stay unchanged:

- shared notification payload routing and tap/open contract
- chat/group recent-remote dedupe model
- repo-owned relay/APNS visible-alert contract for iOS chat/group pushes

## 6. Files And Repos To Inspect Next

Production files expected to change:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`

Production files expected to stay source-of-truth only:

- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/push_registration_coordinator.dart`
- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `go-relay-server/inbox.go`

Tests expected to change or be added:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/features/push/application/push_registration_coordinator_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/integration/chat_notification_dedupe_integration_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- one new integration-style regression for app-open replay suppression
- optionally one narrow wiring/source test for `main.dart` resume registration
  plumbing if the implementation surface benefits from it

## 7. Existing Tests Covering This Area

Already covered:

- `test/features/push/application/push_registration_coordinator_test.dart`
  proves coordinator retry behavior in isolation, including `retryNow()`
- `test/features/push/application/register_push_token_use_case_test.dart`
  proves iOS APNS wait and `noToken` behavior
- `test/features/push/application/show_notification_use_case_test.dart`
  proves current foreground/background notification decisions
- `test/features/push/application/background_push_notification_fallback_test.dart`
  proves fallback decision and copy selection
- `test/features/push/application/background_message_handler_test.dart`
  proves background push handler routing into local fallback and recent-remote
  marking
- `test/integration/chat_notification_dedupe_integration_test.dart`
  proves remote push announcement suppresses later local chat notification
- `test/integration/group_notification_dedupe_integration_test.dart`
  proves the same for groups
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
  proves notification-open clearing and prepare-before-route behavior
- `go-relay-server/inbox_test.go`
  proves chat/group push builders include top-level notification payloads and
  APNS alert payloads

Currently missing:

- direct proof that resume handling triggers push-registration recovery
- direct proof that app-open inbox replay is suppressed from showing a local
  notification
- direct proof that normal resume no longer clears all delivered notifications
- direct proof that `pushTitle` / `pushBody` are honored by fallback copy

Current tests pin behavior that now needs to change:

- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  currently expects delivered notifications to be cleared on every normal
  resume
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
  and the current `show_notification_use_case.dart` contract accept replay-time
  notifications while backgrounded or paused; the new requirement needs a more
  precise recovery suppression rule

## 8. Regression / Tests To Add First

Add or update these first, before production edits:

1. Extend `test/core/lifecycle/app_lifecycle_recovery_test.dart` to cover:
   - resume invokes a new narrow push-registration retry callback
   - resume no longer clears delivered notifications by default
   - push-registration retry failure is swallowed so resume recovery still
     proceeds

2. Extend `test/features/push/application/show_notification_use_case_test.dart`
   with a new recovery-suppression contract:
   - when a message is being surfaced through app-open recovery replay, local
     notification is suppressed even if the user is not already viewing that
     conversation

3. Add one integration-style regression for replay suppression:
   - chat path: replayed inbox message during app-open recovery is persisted but
     does not call `FakeNotificationService.showMessageNotification()`
   - if the implementation touches group replay too, mirror that in the same
     file or a paired group test

4. Extend `test/features/push/application/background_push_notification_fallback_test.dart`
   to prove `pushTitle` / `pushBody` are used when `title` / `body` are absent

5. Keep `go-relay-server/inbox_test.go` as the contract for visible APNS alert
   payloads; do not add an app-side duplicate-alert fallback test as a
   substitute for relay correctness

## 9. Step-By-Step Implementation Plan

1. Add a new optional resume callback in `handleAppResumed()` for push
   registration recovery, and thread `widget.pushRegistrationCoordinator?.retryNow`
   from `main.dart`.

2. Write the failing resume tests first in
   `test/core/lifecycle/app_lifecycle_recovery_test.dart`:
   - callback called once on resume
   - callback failure does not abort inbox drain
   - delivered notifications are not blanket-cleared on normal resume anymore

3. Remove the blanket `clearDeliveredNotificationsFn` call from the generic
   resume path in `handleAppResumed()`.
   Stop if evidence shows another production path still depends on that global
   clear for correctness rather than convenience.

4. Introduce a narrow “recovery replay suppression” seam for local
   notifications.
   Preferred shape:
   - pass an explicit provider or boolean into the notification decision path
     that says the current message surfaced from app-open recovery / inbox replay
   - suppress local notification only for that recovery replay case
   - do not broaden this into unread-count or per-thread notification state

5. Thread that suppression seam through the chat and group listeners only where
   replayed inbox recovery can surface messages because the user opened the app.
   Keep normal foreground/background live-message behavior unchanged.

6. Add the failing unit and integration regressions for replay suppression, then
   implement the minimal production change that makes them pass.

7. Update `background_push_notification_fallback.dart` so title/body resolution
   also reads `pushTitle` / `pushBody` before falling back to generic strings.
   Add the direct fallback tests first.

8. Re-run the existing chat/group dedupe integrations to ensure the new replay
   suppression does not break recent-remote suppression or message-id dedupe.

9. Reconfirm that the repo-owned relay payload contract remains unchanged:
   visible Android notification payload, top-level notification payload, and
   APNS alert payload for chat/group.
   Do not add a second iOS local fallback path unless new evidence proves the
   relay contract is broken in this repo.

10. If manual simulator verification still reproduces “no background
    notification” after the resume registration fix, only then open a follow-up
    diagnostic branch around sender transport selection and direct-ACK behavior.
    That is a second-order investigation, not part of the first bounded fix.

## 10. Risks And Edge Cases

- iOS APNS/FCM token readiness can lag startup; this is the main case the
  resume retry must recover
- scheduled retry timers do not help once the app is background-suspended
- replay suppression must not suppress real live background notifications
- replay suppression must not break recent-remote dedupe for messages that did
  arrive via visible push
- removing blanket `cancelAll()` on resume must not regress tap-open dismissal;
  that behavior is still owned by notification-open flows and per-id dismissal
- group and chat should stay aligned on replay suppression and remote dedupe
- fallback copy changes must not break the generic fallback path for legacy
  payloads that truly lack rich copy

## 11. Exact Tests And Gates To Run

Direct targeted tests first:

```bash
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
flutter test test/features/push/application/push_registration_coordinator_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
flutter test test/features/push/application/background_message_handler_test.dart
```

Notification/regression integrations next:

```bash
flutter test test/integration/chat_notification_dedupe_integration_test.dart
flutter test test/integration/group_notification_dedupe_integration_test.dart
```

Run the new replay-suppression integration file directly once added.

If `main.dart` or lifecycle/bootstrap wiring changes, run the named gates that
match the blast radius:

```bash
./scripts/run_test_gates.sh baseline
./scripts/run_test_gates.sh transport
```

If a specific simulator or host target is required:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh transport
```

If relay code is touched during execution, also run:

```bash
go test ./go-relay-server/...
```

## 12. Known-Failure Interpretation

- if the new direct Dart tests fail, treat them as real blockers
- if `baseline` fails in newly touched notification/lifecycle suites, treat that
  as a blocker
- if `transport` fails with the pre-existing macOS app-launch/debug-connection
  or stale integration harness issues already documented in
  `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`,
  record those as pre-existing only if the failure signature matches exactly
- any new failure in `app_lifecycle_recovery_test.dart`,
  `show_notification_use_case_test.dart`,
  `background_push_notification_fallback_test.dart`,
  `chat_notification_dedupe_integration_test.dart`, or
  `group_notification_dedupe_integration_test.dart`
  is a regression against this plan

## 13. Done Criteria

This plan is done when:

- resume-time push-registration recovery is wired and directly tested
- normal resume no longer clears all delivered notifications
- app-open recovery replay no longer triggers a second local notification
- chat and group recent-remote dedupe tests still pass
- fallback copy prefers `pushTitle` / `pushBody` when present
- notification-open clearing tests remain green
- targeted tests pass
- `baseline` and `transport` gates are run, with any exact pre-existing gate
  failures documented rather than hand-waved

## 14. Scope Guard

Do not broaden this work into:

- unread counts
- badge counts
- server-side read-state synchronization
- notification tray grouping redesign
- app-wide notification-center mirroring
- new push payload formats beyond the existing repo-owned contract
- transport redesign unless the bounded fix fails and fresh evidence demands it

Overengineering for this session would be:

- adding a second app-side iOS fallback path on top of the repo-owned APNS
  visible alert contract
- building a general notification-state store just to suppress replay banners
- coupling notification clearing to new unread/read models

## 15. Accepted Differences / Intentionally Out Of Scope

- chat/group on iOS will continue to rely on the relay's visible APNS alert
  contract instead of adding a second local fallback path in the app
- exact behavior for true cold-start replay outside the bounded app-open
  recovery seam stays unchanged unless the new regression proves it is part of
  the same bug
- direct transport-selection changes are intentionally deferred unless the
  resume push-registration fix fails to restore background delivery in manual
  verification

## 16. Dependency Impact

- this plan tightens notification reliability without reopening the larger
  report `41` inbox-recovery contract
- later manual two-simulator notification journeys should use this plan's
  recovery contract as the new expectation:
  background push before open, no second banner from inbox replay after open
- if execution evidence disproves the push-registration diagnosis, the next
  dependency is a second bounded plan focused on sender transport selection and
  deferred-direct-ACK verification, not an immediate expansion of this session

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

- whether to use one combined chat/group replay-suppression integration file or
  two smaller files
- whether to add a lightweight `main.dart` source-wiring test in addition to
  `app_lifecycle_recovery_test.dart`
- whether relay tests need rerun if execution stays entirely inside Flutter

## Accepted Differences Intentionally Left Unchanged

- repo-owned visible APNS alert contract for chat/group push
- current notification payload routing and deep-link contract
- current recent-remote dedupe TTL model unless fresh evidence shows it still
  causes real duplicate banners after the bounded fix

## Exact Docs/Files Used As Evidence

- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/push_registration_coordinator.dart`
- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/core/notifications/flutter_notification_service.dart`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/features/push/application/push_registration_coordinator_test.dart`
- `test/features/push/application/register_push_token_use_case_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/background_message_handler_test.dart`
- `test/integration/chat_notification_dedupe_integration_test.dart`
- `test/integration/group_notification_dedupe_integration_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `go-mknoon/node/node.go`
- `go-mknoon/node/feature_flags.go`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/41-notification-open-missing-incoming-messages-session-breakdown.md`

## Why The Plan Is Safe To Implement Now

This plan is safe because it stays on the notification and recovery seam that
the repo evidence actually supports:

- relay push payload construction already exists and is tested
- coordinator retry behavior already exists and only needs real resume wiring
- replay-time notifications are already isolated behind one use case
  (`maybeShowNotification()`), which gives a narrow place to change the
  contract
- the notification-clearing regression is local to resume handling and does not
  require a broader unread/read architecture

The only deferred question is whether a second transport-layer issue remains
after the bounded fix. The plan explicitly stops before redesigning transport
selection and opens that follow-up only if the first fix does not restore the
manual background-delivery behavior.
