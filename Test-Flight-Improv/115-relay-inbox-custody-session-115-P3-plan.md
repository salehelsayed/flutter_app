Status: accepted

# Doc 115 Session 115-P3 Plan - Flutter Custody Sweep And Retry Truthfulness

## Planning Progress

- 2026-06-13T06:40:30Z - Intake started from `115-relay-inbox-custody-session-breakdown.md`. P1/P2 remain stale/already-covered; P3 is the first pending executable session.
- 2026-06-13T06:41:30Z - Evidence collected from current tests and code. Existing RED tests already cover retry-unacked truthfulness, custody query helper behavior, custody sweep semantics, and detailed store parsing. Focused P3 run fails on missing `inbox_store_outcome.dart` and `verify_inbox_custody_use_case.dart`, and current `retry_unacked_messages_use_case.dart` still mints false `delivered` from inbox store success and blind `transport == 'inbox'` rows.

## real scope

Implement app-side P3 only:

- `InboxStoreOutcome` value model and detailed relay store parsing.
- `verifyInboxCustody` top-level use case with expiry-margin, old-relay, duplicate, full, and race-safe status handling.
- DB helper and repository implementation methods for loading custody rows and marking checks.
- Retry-unacked truthfulness: successful inbox store becomes `inboxed` with retained envelope.
- Pending retrier and app-resume wiring for custody verification.

Out of scope:

- No relay-server, go-mknoon, bridge binding generation, EC2 deploy, or protocol changes; P4 owns those.
- No final gate-array promotion or whole-doc closure; P5 owns those.
- No docs 114/116 edits except preserving prerequisites already recorded.

## source of truth

- `Test-Flight-Improv/115-relay-inbox-custody.md` Phase 3.
- `Test-Flight-Improv/115-relay-inbox-custody-session-breakdown.md`.
- Current tests:
  - `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
  - `test/features/conversation/application/verify_inbox_custody_use_case_test.dart`
  - `test/core/database/helpers/messages_db_helpers_test.dart`
  - `test/core/services/p2p_service_impl_test.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/core/lifecycle/handle_app_resumed_inbox_custody_test.dart` if present or added.

## implementation steps

1. Add `lib/core/services/inbox_store_outcome.dart` with `InboxStoreStatus`, `InboxStoreOutcome`, and `StoreInInboxDetailedFn`.
2. Add `lib/features/conversation/application/verify_inbox_custody_use_case.dart`.
3. Extend message DB helpers and `MessageRepositoryImpl` with impl-level custody load/mark methods, without changing the abstract `MessageRepository` interface.
4. Add `P2PServiceImpl.storeInInboxDetailed`, leaving `P2PService.storeInInbox` unchanged.
5. Change `retryUnackedMessages` so a successful re-store writes `status: 'inboxed'`, `transport: 'inbox'`, and retains `wireEnvelope`; remove the blind `transport == 'inbox'` delivered flip.
6. Thread custody verification through `PendingMessageRetrier`, `handleAppResumed`, and `main.dart`.
7. Run focused P3 tests, then `1to1`, completeness, diff hygiene, and arch graph refresh.

## closure bar

P3 is accepted when focused P3 tests pass, `1to1` and completeness are green or precisely classified, and the source/breakdown record the accepted Flutter-only scope with P4 relay work still pending.

## Execution Progress

- 2026-06-13T06:49:00Z - Implemented `InboxStoreOutcome` and `StoreInInboxDetailedFn`, app-side custody verification, custody DB helpers, repository impl methods, detailed `P2PServiceImpl.storeInInboxDetailed`, retry-unacked truthfulness, and pending-retrier/app-resume/main wiring.
- 2026-06-13T06:50:00Z - Added focused scheduler/resume ordering coverage in the existing retrier and lifecycle ordering suites instead of creating a parallel one-off file.
- 2026-06-13T06:51:00Z - Cleaned the focused analyzer surface and ran P3-focused host tests.
- 2026-06-13T06:52:00Z - Ran named `1to1`, completeness, diff hygiene, and the repo-root arch-graph refresh script.

## Verification Evidence

- `dart analyze lib/core/services/inbox_store_outcome.dart lib/features/conversation/application/verify_inbox_custody_use_case.dart lib/core/database/helpers/messages_db_helpers.dart lib/features/conversation/domain/repositories/message_repository_impl.dart lib/core/services/p2p_service_impl.dart lib/main.dart lib/core/services/pending_message_retrier.dart lib/core/lifecycle/handle_app_resumed.dart lib/features/conversation/application/retry_unacked_messages_use_case.dart` - pass, no issues.
- `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart test/features/conversation/application/verify_inbox_custody_use_case_test.dart test/core/database/helpers/messages_db_helpers_test.dart test/core/services/p2p_service_impl_test.dart test/core/services/pending_message_retrier_test.dart test/core/services/pending_message_retrier_upload_ordering_test.dart test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart test/core/lifecycle/handle_app_resumed_group_inbox_retry_test.dart` - pass, 183 tests. Log: `/tmp/doc115_p3_focused_2.log`.
- `./scripts/run_test_gates.sh 1to1` - pass, 593 tests. Log: `/tmp/doc115_p3_1to1.log`.
- `./scripts/run_test_gates.sh completeness-check` - pass, 841/841 classified. Log: `/tmp/doc115_p3_completeness.log`.
- `git diff --check` - pass. Log: `/tmp/doc115_p3_diff_check.log`.
- `./graphify-arch/refresh_arch_graph.sh` from the repo root - pass; refreshed `graphify-arch/graphify-out/graph.json`, `GRAPH_SELECTION.md`, and `comparison.json`. Log: `/tmp/doc115_p3_graph_refresh.log`.

## Verdict

Accepted. Session `115-P3` is closed for the Flutter/database/lifecycle scope. The app now treats relay inbox re-store success as truthful non-terminal custody (`inboxed`), periodically re-proves unconfirmed custody against old and new relay responses, preserves envelopes for repair, and avoids late-sweep downgrades via conditional status transitions. Relay/server/client protocol work remains explicitly open for `115-P4`, and final gate/deploy/device evidence remains open for `115-P5`.
