# Session 30 Plan: Close Remaining Group Reliability Gaps vs 1:1 Chat

**Date:** 2026-03-27
**Status:** Plan only

## 1. real scope

This repo is now in closure mode, not backlog mode. Session 30 should only reopen group reliability work if the current tree still proves a real residual trust gap.

Current source-of-truth evidence:
- `Test-Flight-Improv/00-INDEX.md` says Sessions `1` through `29` are closed and group reliability should only be reopened for a clearly justified residual gap
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md` narrows the remaining discussion-reliability work to:
  - voice publish-failure retry residual
  - honest receipt-less status semantics

Based on current repo evidence, there is one concrete repo-local seam that is still real:
- group inbox push metadata is prepared by Flutter and carried by `go-mknoon`, but the relay `group_store` path still ignores it and only stores the group message

There is one additional concrete repo-local seam that is also still real:
- groups recover on resume, but there is no proven group equivalent of the 1:1 online-transition / periodic retrier

This session therefore becomes a narrow reopen session for exactly two implementation slices. It is not a bundled parity program beyond those two seams.

In scope:
- revalidate Session 30 against current closure docs before changing code
- capture concrete repo evidence for the still-open seams
- implement relay-side group push fanout after durable store
- implement online-transition group retry orchestration
- add the direct regressions for both implementation slices
- run the exact direct suites and only the applicable named gates

Not in active scope for this session:
- adding group ACK / receipt semantics
- broad notification redesign
- broad status-model redesign
- restarting the already-closed Sessions `24` through `29` work

Regression-strategy rule for this session:
- each implemented bug closure must land with one permanent direct regression
- add a higher-level orchestration proof only when an implemented slice actually crosses lifecycle, notification-open routing, or multi-step recovery behavior

## 2. session classification

`implementation-ready`

Why:
- the repo has already closed the broad residual group-reliability track
- the remaining target is now narrowed to two concrete repo-local seams
- both seams have direct code evidence and bounded implementation surfaces
- the current send-settlement semantics remain intentionally out of scope for this session

## 3. files and repos to inspect next

Primary planning / rationale docs:
- `Test-Flight-Improv/00-INDEX.md`
- `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
- `Test-Flight-Improv/09-network-group-messaging.md`
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `Test-Flight-Improv/test-gate-definitions.md`

Primary Flutter production files:
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/features/groups/application/retry_failed_group_messages_use_case.dart`
- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/application/recover_stuck_sending_group_messages_use_case.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/main.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/domain/models/group_message.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`

Primary Go / relay files:
- `go-mknoon/node/group_inbox.go`
- `go-mknoon/node/group_inbox_test.go`
- `go-relay-server/inbox.go`
- `go-relay-server/group_inbox_store.go`
- `go-relay-server/backend_memory.go`
- `go-relay-server/backend_redis.go`
- `go-relay-server/inbox_test.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/failover_test.go`

Primary tests:
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/application/retry_incomplete_group_uploads_use_case_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/pending_message_retrier_stuck_sending_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart` if any sender-visible result/status contract changes
- `test/features/push/application/prepare_notification_open_use_case_test.dart` if group push fanout lands
- `test/features/push/application/chat_and_group_push_open_flow_test.dart` if group push fanout lands
- `test/features/push/application/background_push_notification_fallback_test.dart` if group push fanout lands
- `test/integration/notification_deeplink_integration_test.dart` if group push fanout lands
- `go-relay-server/failover_test.go`
- `go-relay-server/group_inbox_test.go`
- `go-relay-server/backend_redis_test.go`
- `go-relay-server/inbox_test.go`

## 4. existing tests covering this area

Already present and useful:
- `test/features/groups/application/send_group_message_use_case_test.dart`
  - pins the current 4-way matrix
  - proves `topicPeers == 0` becomes `successNoPeers`
  - proves `topicPeers > 0 + inbox fail` is treated as `success` / `sent` today
  - proves `publish fail + inbox OK` remains `failed` today
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
  - covers replay of persisted group inbox retry payloads
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - covers resume-time group recovery ordering
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
  - covers resume Step `8e` for `retryFailedGroupInboxStoresFn`
- `test/core/services/pending_message_retrier_test.dart`
  - covers 1:1 online-transition / periodic retry behavior
- `test/core/services/pending_message_retrier_stuck_sending_test.dart`
  - covers 1:1 stuck-sending recovery sequencing
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
  - covers 1:1 recover -> uploads -> failed -> unacked ordering
- `go-mknoon/node/group_inbox_test.go`
  - proves `recipientPeerIds`, `pushTitle`, and `pushBody` are already marshaled into the relay request
- `go-relay-server/group_inbox_test.go`
  - proves shared group inbox storage, cursor pagination, and dedupe/exactly-once page coverage
- `go-relay-server/failover_test.go`
  - proves shared group inbox visibility and cursor continuation across relay instances
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - proves the current group push-open contract expects `type: group_message` plus `groupId`
- `test/features/push/application/background_push_notification_fallback_test.dart`
  - proves current fallback-notification routing for group pushes uses the same `group_message` + `groupId` contract

What is still missing:
- no direct server test currently proves `group_store` persists first and then fans out group push notifications to the intended recipients
- no direct server test currently proves duplicate group-store attempts do not create push storms
- there is no current group online-transition retrier test because group retry is still resume-oriented
- there is no current group online-transition retrier proof in the same style that 1:1 already has

## 5. exact missing product / reliability work

### Gap 1: group inbox persistence is not push-backed like 1:1

Current state:
- Flutter prepares `recipientPeerIds`, `pushTitle`, and `pushBody` for `group:inboxStore`
- `go-mknoon` forwards those fields to the relay request
- the relay `group_store` handler currently ignores them and only stores the group message

Why it matters:
- 1:1 inbox fallback already has relay push wake-up behavior
- group fallback currently relies on later startup/resume drain only
- this is a concrete repo-local seam, not just a hypothetical parity complaint

Minimum acceptable closure:
- relay `group_store` accepts and uses the existing recipient + push metadata
- durable group inbox store remains first; push stays best-effort after successful store
- recipient targeting uses the provided recipient list and never includes the sender
- duplicate store attempts do not create obvious duplicate push sends
- if group push fanout lands, it must use the existing group-notification route contract:
  - `type: group_message`
  - `groupId`
  - optional `title` / `body`

### Gap 2: group retry is not automatically driven by online transition

Current state:
- 1:1 has `PendingMessageRetrier`
- groups already have strong resume recovery:
  - rejoin
  - drain
  - recover stuck group sends
  - retry incomplete group uploads
  - retry failed group messages
  - retry failed group inbox stores
- there is no current group online-transition / periodic retrier

Why it matters:
- a foreground user may regain usable relay health without backgrounding the app
- 1:1 already heals in that state
- group behavior is weaker there today and should be closed in this session

Minimum acceptable closure if evidence proves the gap is worth reopening:
- on healthy online transition, run the same ordered group recovery sweep that matters for parity
- preserve overlap guards and avoid divergent resume vs online order
- if shared 1:1 retrier infrastructure is touched, treat `1to1` as mandatory

## 6. step-by-step implementation plan

1. Reconfirm the source of truth in:
   - `Test-Flight-Improv/00-INDEX.md`
   - `Test-Flight-Improv/18-group-discussion-reliability-audit.md`
   - `Test-Flight-Improv/09-network-group-messaging.md`
2. Capture concrete repo evidence for Gap 1.
   - verify Flutter emits `recipientPeerIds` / `pushTitle` / `pushBody`
   - verify `go-mknoon` forwards those fields
   - verify `go-relay-server` `group_store` currently drops them
3. Capture concrete repo evidence for Gap 2.
   - compare current resume recovery wiring with 1:1 `PendingMessageRetrier`
   - confirm the current absence of a group online-transition / periodic retrier
4. Implement Gap 1 first.
   - add RED relay tests first around `group_store`
   - prove store-first ordering
   - prove recipient-token targeting
   - prove duplicate stores do not re-fanout
   - implement relay use of the existing metadata
   - if the outgoing push payload shape changes, keep it aligned with the current group route contract and run the push-routing direct suites
5. Implement Gap 2 second.
   - add RED deterministic Flutter tests for group online-transition retry behavior
   - choose the smallest clean architecture:
     - extend `PendingMessageRetrier` with explicit group callbacks
     - or add a narrowly parallel group retrier
   - preserve the same ordering already used on resume
   - add overlap guards between resume and online sweeps
6. Re-run the exact direct suites for both slices.
7. Run the applicable named gate(s) only for the code actually changed.
8. If Go relay code changed, run the exact Go direct suites from the Go module directory rather than from the Flutter repo root.

## 7. risks and edge cases

- Do not reopen the already-closed residual track without evidence.
- Do not bundle settlement-contract rewrites into this push-fanout + retrier session.
- If Gap 1 lands, durable store must happen before any push attempt.
- If Gap 1 lands, duplicate `group_store` attempts must not create push storms.
- If Gap 1 lands, group push payloads must preserve the current route contract:
  - `type: group_message`
  - `groupId`
- Do not push to the sender’s own device.
- Do not assume all members should always receive push; use the supplied recipient list unless the product contract changes.
- If Gap 2 lands, do not create overlapping online/resume retry sweeps.
- If shared `PendingMessageRetrier` code changes, do not treat group-only tests as sufficient coverage.
- Do not require Baseline or Transport gates for relay-only work that does not change Flutter production code.

## 8. exact tests to run after implementation

Direct Go tests for Gap 1 if relay group push fanout changes:
- `cd go-relay-server && go test -run 'TestTwoRelayServers_SharedGroupInboxBackend|TestTwoRelayServers_SharedGroupCursorContinuation|TestGroupInboxStore_FailoverDoesNotDuplicateMessages|TestGroupInboxStore_CursorPaginationExactOnceAcrossPages|TestHandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens'`
- `cd go-relay-server && go test -run 'TestRedisGroupInboxBackend_CursorStableAcrossClients'` if Redis-backed group inbox logic changes

Direct Go tests for `go-mknoon` only if the request-shape code changes:
- `cd go-mknoon && go test ./node -run 'TestBuildGroupInboxStoreRequest_MarshalsRecipientPeerIds|TestBuildGroupInboxStoreRequest_MarshalsPushTitle|TestBuildGroupInboxStoreRequest_MarshalsPushBody'`

Direct Flutter tests for Gap 2 if group online-transition retry changes:
- `flutter test test/core/services/pending_message_retrier_test.dart`
- `flutter test test/core/services/pending_message_retrier_stuck_sending_test.dart`
- `flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart` only if `lib/main.dart` wiring changes
- plus the new deterministic group online-retrier regression

Direct Flutter tests for Gap 1 if group push payload/open behavior changes:
- `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`
- `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `flutter test test/features/push/application/background_push_notification_fallback_test.dart`
- `flutter test test/integration/notification_deeplink_integration_test.dart`

Named gates:
- `./scripts/run_test_gates.sh groups` only if Flutter group production code changes
- `./scripts/run_test_gates.sh baseline` only if Flutter production code changes
- `FLUTTER_DEVICE_ID=<device-id> ./scripts/run_test_gates.sh transport` only if lifecycle / bootstrap / transport Flutter code changes

Conditional named gate if shared 1:1 retry infrastructure changes:
- `./scripts/run_test_gates.sh 1to1`

Interpretation rule:
- use the named gate script commands as the public source of truth
- do not use `go test ./go-relay-server ...` from the Flutter repo root; run Go commands from the Go module directory
- if a named gate failure is already listed as a known unrelated failure in `Test-Flight-Improv/test-gate-definitions.md`, document that explicitly rather than treating it as a Session 30 regression by default

## 9. subsystem gate(s), if relevant

`Group Messaging Gate`

Reason:
- relevant only if Flutter group send / retry / recovery production behavior changes

`Startup / Transport Gate`

Reason:
- relevant only if Session 30 changes lifecycle, resume, startup, or online-transition retry wiring in Flutter

`1:1 Reliability Gate`

Reason:
- relevant only if Session 30 changes shared `PendingMessageRetrier` or other shared 1:1 retry infrastructure

## 10. whether Baseline Gate is required

Conditional.

Reason:
- required when Flutter production code changes
- not required for relay-only `go-relay-server` work that does not modify Flutter production code

## 11. done criteria

Session 30 is complete when all of these are true:

- the plan revalidates Session 30 against the current closure docs before reopening work
- the session stays limited to Gap 1 and Gap 2 only
- Gap 1 is closed:
  - relay `group_store` no longer drops the already-supplied group push metadata
  - durable store still happens before any push attempt
  - duplicate store attempts do not create duplicate push fanout
  - current group notification routing/open tests still pass if the push payload path is touched
- Gap 2 is closed:
  - group retry has a deterministic online-transition proof
  - overlap guards keep resume and online sweeps safe
  - shared 1:1 retrier coverage runs if shared infrastructure changed
- the exact direct suites and only the applicable named gates pass, or any unrelated pre-existing failures are explicitly identified as such

## 12. scope guard

- Do not broaden this into a generic “group parity with 1:1” program.
- Do not reopen closed Sessions `24` through `29` findings without new evidence.
- Do not change `topicPeers > 0 + inbox fail` semantics in this session.
- Do not change `publish failed + inbox stored` semantics in this session.
- Do not redesign the whole notification system.
- If group push fanout lands, preserve the existing remote-message route contract for groups.
- Do not replace group inbox cursor recovery.
- Do not broaden this into announcement feature work.
- Keep the target: prove and close the two justified repo-local seams with the smallest coherent set of changes.
