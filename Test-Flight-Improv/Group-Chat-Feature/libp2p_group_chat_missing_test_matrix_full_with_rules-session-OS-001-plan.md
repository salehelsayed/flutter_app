# OS-001 Offline Send Queue Deterministic Restart Plan

## Session Intake

- breakdown artifact: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules-session-breakdown.md`
- source matrix: `Test-Flight-Improv/Group-Chat-Feature/libp2p_group_chat_missing_test_matrix_full_with_rules.md`
- source row: `OS-001 | Offline send queue publishes in deterministic order after restart`
- disposition: `needs_tests_only`
- execution classification: `implementation-ready`
- local plan fallback: used after the spawned planning attempt no-progressed without leaving a reusable plan

## Current Gap

The repository and retry owners already have queue-like primitives:

- failed outgoing group messages are loaded by `timestamp ASC, id ASC`
- failed inbox-store message rows are loaded by `timestamp ASC, id ASC`
- reaction replay outbox rows are loaded by `created_at ASC, reaction_id ASC`
- media attachment retry ownership is separate from failed message publish retry

The matrix row is still `Partial` because there is no row-specific test proving that, after a restart-style reload from persisted rows, text/quote/media message retries and reaction/inbox-store retries publish in deterministic valid order without losing IDs, quote metadata, or attachment state.

## Scope

Add focused tests only:

- prove failed outgoing text, quote, and done-media rows retry in persisted chronological order even when inserted out of order
- prove retry uses original message IDs, timestamps, quote IDs, and persisted media attachment state
- prove failed inbox-store message rows retry before reaction replay rows, while each owner keeps its deterministic persisted ordering
- keep upload-pending media ownership out of failed message retry

## Files In Scope

- `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- source matrix, inventory, and breakdown docs after execution

## Scope Guard

- Do not change production retry algorithms unless focused tests expose a real ordering or persistence gap.
- Do not implement broader anti-entropy sync, multi-peer history repair, local-only UI, backoff policy, or real-network partition proof; those are separate OS rows.
- Do not touch media upload retry behavior except to assert upload-pending rows stay owned by `retryIncompleteGroupUploads`.
- Do not alter unrelated group send, inbox drain, membership, key, or notification code.

## Acceptance Criteria

- Direct tests prove deterministic retry ordering by persisted timestamp/id for failed outgoing message rows after restart-style reload.
- Direct tests prove text, quote, and done-media retry rows preserve message IDs, timestamps, quote IDs, and media attachment state.
- Direct tests prove failed inbox-store message retries run in deterministic message order before reaction replay retries, with reaction retries ordered by persisted creation time/id.
- Existing retry behavior remains unchanged unless a real test failure requires a narrow fix.
- Source matrix row OS-001 is updated from `Partial` to `Covered` only if the focused tests pass.

## Direct Tests

- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name "deterministic"`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --name "deterministic"`

## Session Gates

- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

## Execution Evidence

- Added deterministic restart retry coverage in `test/features/groups/application/retry_failed_group_messages_use_case_test.dart` for text, quote, and done-media failed outgoing rows inserted out of order and retried by persisted `timestamp ASC, id ASC`.
- Added deterministic restart retry coverage in `test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` for failed message inbox rows draining before reaction replay rows, with each owner ordered by persisted timestamp/id.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart --name "deterministic"`: PASS.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart --name "deterministic"`: PASS.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_messages_use_case_test.dart`: PASS.
- `flutter test --no-pub test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart`: PASS.
- `./scripts/run_test_gates.sh completeness-check`: PASS (`694/694 test files classified`).
- `git diff --check`: PASS.

## Done Criteria

- focused tests land and pass
- no production behavior is changed unless required by a failing focused test
- OS-001 source matrix row and `test-inventory.md` record concrete file/test evidence
- session breakdown ledger records OS-001 as `accepted | closure-verified` or truthfully blocked with blocker classes
