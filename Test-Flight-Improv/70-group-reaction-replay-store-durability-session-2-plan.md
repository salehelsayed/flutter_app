# 70 Session 2 Plan: Retry/Resume Orchestration and Offline Convergence

## Final Verdict

- Status:
  `accepted`
- Accepted on:
  `2026-04-13`
- Why:
  - the existing `retryFailedGroupInboxStores(...)` owner now retries durable
    reaction replay rows after failed message inbox-store rows instead of
    leaving reaction add/remove durability outside shipped recovery
  - `main.dart` now passes the reaction replay outbox repository through the
    real resume and pending-retrier callbacks
  - the new integration and lifecycle proof shows offline add/remove replay
    failures converge to the final truthful state, and the named repo gates
    stayed green

## Landed Scope

- reuse `retryFailedGroupInboxStores(...)` as the shared retry owner instead of
  inventing a second reaction-only lifecycle path
- retry reaction replay rows by reusing the exact staged inbox payload and then
  mark rows `stored` or `failed`
- preserve message-first ordering and fault isolation when both message rows
  and reaction rows are retryable
- strengthen announcement-reader and resume-recovery proof for reaction
  add/remove convergence

Out of scope for this session:

- changing receive-side reaction semantics
- refreshing maintained audit or matrix docs

## Files

Production:

- `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`

Direct tests:

- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `test/features/groups/integration/announcement_happy_path_test.dart`
- `test/features/groups/integration/group_resume_recovery_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/core/services/pending_message_retrier_upload_ordering_test.dart`
- `test/features/identity/presentation/screens/startup_router_recovery_test.dart`

## Verification

Focused tests:

- `flutter test test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `flutter test test/features/groups/integration/announcement_happy_path_test.dart`
- `flutter test test/features/groups/integration/group_resume_recovery_test.dart --plain-name "resume retry replays failed reaction add/remove stores and converges to the final removed state"`
- `flutter test test/features/identity/presentation/screens/startup_router_recovery_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart`
- `flutter test test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `flutter test test/core/lifecycle/main_resume_group_upload_wiring_test.dart`
- `flutter test test/core/services/pending_message_retrier_test.dart`
- `flutter test test/core/services/pending_message_retrier_upload_ordering_test.dart`

Named gates:

- `./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh baseline`
- `FLUTTER_DEVICE_ID=5BA69F1C-B112-47BE-B1FF-8C1003728C8F ./scripts/run_test_gates.sh transport`

## Accepted Differences

- Session `2` keeps one shared retry owner. Message rows still drain before
  reaction rows so the older inbox-store contract retains priority.
- The only non-product fix pulled into this session was the removal of a stray
  `groupReactionReplayOutboxRepository` route argument in
  `startup_router.dart` that baseline verification exposed.

## Scope Guard

- do not add a separate reaction-resume controller
- do not reopen send/remove staging, which stays accepted in Session `1`
- do not close maintained docs here; Session `3` owns that pass
