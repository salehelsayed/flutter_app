# Session 19 Plan: Profile Targeted Recovery / Download Indexes And Add Only If Justified

## 1. real scope

Decide whether the two remaining plausible DB index candidates are worth a migration:

- `messages(status, is_incoming, timestamp)`
- `media_attachments(download_status)`

This session is narrow and evidence-first. It is not general DB tuning.

The older broad "we are missing important recovery/download indexes" claim is partly stale, but the remaining question is still real:

- It is partly stale because the repo already has meaningful index coverage, including `idx_messages_contact`, `idx_messages_ts`, `idx_messages_unread`, and `idx_media_attachments_message`, and `05-database-storage-performance.md` already downgraded these two remaining candidates to profile-only follow-up.
- It is still real because the exact candidate predicates still exist in helper/query surfaces and neither candidate index exists today:
  - `lib/core/database/helpers/messages_db_helpers.dart` still runs `dbLoadUnackedOutgoingMessages`, `dbLoadStuckSendingOutgoingMessages`, and `dbRecoverStuckSendingMessages` over `status`, `is_incoming`, and `timestamp`.
  - `lib/core/database/helpers/media_attachments_db_helpers.dart` still runs `dbLoadUploadPendingAttachments` and `dbLoadPendingMediaDownloads` over `download_status`.
  - repo inspection already proves the `upload_pending` path is live, while the batch `pending` path remains a candidate that must be proven reachable before it can justify an index.
  - `lib/main.dart` still wires those helpers into the real repositories used by resume/retry/download flows.

Concrete repo evidence currently leans against speculative migration:

- `messages_db_helpers.dart` explicitly documents that no `(status, is_incoming, timestamp)` index exists and that a full scan is currently acceptable because recovery runs at most once per resume and the table is small.
- `010_media_attachments.dart` creates only `idx_media_attachments_message`, not a status index.
- `full_migration_chain_test.dart` currently asserts the existing `media_attachments` message index but nothing for the two Session 19 candidates.

Valid outcomes:

- evidence says neither index is justified now, and the session ends with no code change
- evidence justifies one or both indexes, and the session lands only that migration work with schema and migration-chain coverage

Out of scope:

- broad SQLite tuning
- unrelated message or media repository refactors
- transport/startup hardening beyond the DB-version/migration side effects of this exact work

## 2. session classification

`profile-gated`

Why:

- `05-database-storage-performance.md` marks both candidate indexes as plausible only after profiling
- `10-network-measurement-strategy.md` calls for DB-helper hotspot measurement rather than speculative schema work
- current helper code and tests prove correctness, but they do not yet prove that either query family is hot enough to justify a migration
- the `messages` helper itself already argues the current full scan is acceptable, which makes this a measurement problem, not an implementation-ready bug

## 3. files and repos to inspect next

Primary DB files:

- `lib/core/database/helpers/messages_db_helpers.dart`
- `lib/core/database/helpers/media_attachments_db_helpers.dart`
- `lib/core/database/migrations/`
- `lib/main.dart`

Primary caller paths to inspect before changing schema:

- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart`
- `lib/features/conversation/application/recover_stuck_sending_messages_use_case.dart`
- `lib/features/conversation/application/retry_unacked_messages_use_case.dart`
- `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`
- `lib/core/services/pending_message_retrier.dart`

Inspect-only reachability checks:

- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/retry_incomplete_group_uploads_use_case.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`

Tests and reference docs:

- `Test-Flight-Improv/05-database-storage-performance.md`
- `Test-Flight-Improv/10-network-measurement-strategy.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`
- `test/core/database/helpers/messages_db_helpers_test.dart`
- `test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart`
- `test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart`
- `test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `test/core/database/integration/full_migration_chain_test.dart`
- `test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `test/features/conversation/integration/media_attachment_flow_test.dart`
- `test/features/conversation/integration/voice_message_exchange_test.dart`

## 4. existing tests covering this area

Current useful coverage already exists:

- `messages_db_helpers_stuck_sending_test.dart` proves `dbRecoverStuckSendingMessages(...)` correctness for threshold, outgoing-only filtering, multi-row updates, and wire-envelope preservation.
- `messages_db_helpers_stuck_sending_query_test.dart` proves `dbLoadStuckSendingOutgoingMessages(...)` correctness for threshold filtering and limits.
- `messages_db_helpers_test.dart` covers the broader messages helper surface and current schema prerequisites for the message table.
- `media_attachments_db_helpers_test.dart` proves `dbLoadPendingMediaDownloads(...)` correctness and the general helper CRUD surface.
- `full_migration_chain_test.dart` already proves fresh-install and upgrade-chain schema correctness and checks the current `idx_media_attachments_message` index.
- `incomplete_upload_recovery_test.dart` exercises the real resume ordering around `recoverStuckSendingMessages -> retryIncompleteUploads -> retryFailedMessages`.
- `media_attachment_flow_test.dart` and `voice_message_exchange_test.dart` exercise the pending-download and upload-pending repository paths through realistic conversation flows.

What is missing:

- no test currently captures `EXPLAIN QUERY PLAN` for the two candidate predicates
- no test currently seeds a large-enough dataset to show whether these helpers are meaningfully scan-heavy
- no current assertion proves call frequency is high enough to justify new indexes
- no schema assertion currently checks for either candidate index, because neither exists yet

## 5. regression/tests to add first, if any

Default answer: none.

If the session ends as evidence-only, do not add a regression first.

If profiling/query-plan evidence justifies a migration:

- first reconcile or replace `test/core/database/integration/full_migration_chain_test.dart`, because its current header and coverage do not yet match the real `main.dart` DB chain through version 42, so it cannot be treated as the authoritative fresh-install/upgrade proof until that is corrected
- add the migration and schema assertion first
- extend `test/core/database/integration/full_migration_chain_test.dart` so it explicitly proves the new index or indexes exist after fresh install and after upgrade
- then add the smallest helper-level assertion needed to prove the intended query still returns the same rows under the new schema

Do not start by adding generic benchmark tests to the permanent suite unless the evidence session needs a temporary DB-only harness to make the decision.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Capture evidence before any schema or helper change.

For the `messages` candidate:

- `EXPLAIN QUERY PLAN` for:
  - `SELECT ... FROM messages WHERE status = ? AND is_incoming = 0 AND timestamp < ? ORDER BY timestamp ASC LIMIT ?`
  - `SELECT ... FROM messages WHERE status = ? AND is_incoming = 0 AND wire_envelope IS NOT NULL AND timestamp < ? ORDER BY timestamp ASC LIMIT ?`
  - `UPDATE messages SET status = 'failed' WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ?`
- row counts, match counts, and elapsed time on seeded datasets where:
  - the table is small and realistic
  - the table is large enough to make a full scan visible if it matters
  - the number of matching rows is low relative to total rows

For the `media_attachments` candidate:

- `EXPLAIN QUERY PLAN` for:
  - `SELECT ... FROM media_attachments WHERE download_status = 'upload_pending' ORDER BY created_at ASC LIMIT ?`
  - `SELECT ... FROM media_attachments WHERE download_status = 'pending' ORDER BY created_at ASC`
- row counts, match counts, and elapsed time on seeded datasets with many non-matching attachments
- before profiling the batch `pending` query as a migration candidate, confirm that `getPendingDownloads()` is actually reached by a live production path; repo inspection currently proves `upload_pending` is live, but not yet the batch `pending` helper path
- if no live caller reaches `getPendingDownloads()`, record that the `pending` candidate is not currently justified and do not force profiling for a dead path

Call-frequency evidence:

- use the existing flow-event emitters in `messages_db_helpers.dart` and `media_attachments_db_helpers.dart` where possible before adding any new probes
- confirm from the real call paths that:
  - stuck-message scans are resume-driven and not high-frequency steady-state work
  - unacked-message scans are driven by `PendingMessageRetrier` on reconnect and every 5 minutes while online, not only by one-shot resume recovery
  - upload-pending scans are retry-cycle driven for both 1:1 and group upload recovery paths
  - pending-download scans matter only if a real batch-download caller exists and incoming media volume makes them materially hot

Concrete evidence tools to prefer:

- a temporary sqflite-ffi DB-only test or harness that seeds representative data and runs `EXPLAIN QUERY PLAN`
- targeted integration tests only to confirm call frequency or path reachability, not as the primary place to do timing

If query plans still show scans but elapsed time and call frequency remain small, stop with no migration.

## 7. step-by-step implementation or evidence-collection plan

1. Confirm the exact candidate query shapes in `messages_db_helpers.dart` and `media_attachments_db_helpers.dart`.
2. Confirm the real production call paths from `main.dart` into `message_repository_impl.dart`, `media_attachment_repository_impl.dart`, `recover_stuck_sending_messages_use_case.dart`, `retry_unacked_messages_use_case.dart`, `retry_incomplete_uploads_use_case.dart`, and `pending_message_retrier.dart`.
3. Reuse the existing sqflite-ffi DB-helper test setup patterns instead of inventing a new storage harness from scratch.
4. Add a temporary DB-only evidence harness if needed, preferably under `test/core/database/helpers/`, that:
   - seeds realistic and stress-biased row counts
   - runs `EXPLAIN QUERY PLAN`
   - records elapsed times for the exact helper queries
   - records total rows versus matched rows
5. Compare at least three cases:
   - realistic/small dataset
   - medium/high-cardinality dataset
   - low-match-rate dataset where an index would matter most if justified
6. For `messages`, measure both the `SELECT` recovery helpers and the `UPDATE` recovery helper, because the candidate index is only justified if the resume recovery path is materially scan-heavy.
7. For `media_attachments`, first prove which `download_status` caller paths are actually live:
   - profile `upload_pending` because the retry helpers already call it in production
   - profile the batch `pending` query only if a real production caller reaches `getPendingDownloads()`
   - if no such caller exists, document that `pending` is currently not justified as an index target
8. Use existing helper flow events and targeted integration tests only to verify whether those queries run often enough to matter in real flows.
9. Make an explicit decision:
   - if the plans/timings/call frequency say "rare and cheap", stop with no code change
   - if one or both candidates are clearly justified, add only the minimal migration for the justified index set
10. If a migration is justified:
   - add the new migration first
   - update `lib/main.dart` DB version and migration chain
   - extend `full_migration_chain_test.dart` to assert the index exists after fresh install and upgrade
   - if the landed index is on `media_attachments(download_status)`, re-evaluate group-side verification because the same `upload_pending` scan is shared by group retry/composer flows
   - rerun the exact direct tests and required gates
11. Do not combine this session with unrelated schema cleanup or repository refactors.

## 8. risks and edge cases

- The `messages` candidate may look attractive in query-plan output but still not be worth a migration if resume recovery runs rarely and the table remains small in practice.
- The unacked-message path is not just resume-driven; `PendingMessageRetrier` also reruns it on reconnect and on a 5-minute online cadence, so call-frequency evidence must include that steady-state retry path.
- `dbRecoverStuckSendingMessages(...)` is an `UPDATE`, not only a `SELECT`, so plan evidence must cover both lookup and mutation paths.
- `download_status` covers both `pending` and `upload_pending`; an index that helps one path may not materially help the other, and the batch `pending` helper path may not currently be reachable at all.
- Existing helper tests use small in-memory datasets, so they prove correctness but not scan cost.
- Adding an index without measuring match-rate and call frequency risks permanent schema cost for no user-visible win.
- If a migration lands, `lib/main.dart` versioning and upgrade order must stay correct; this repo already has a non-sequential import/order history, so the migration-chain assertion must be explicit.
- `full_migration_chain_test.dart` currently proves the existing media index only. That test must become the schema source of truth if Session 19 adds an index.

## 9. exact tests to run after implementation, if code changes occur

If the session stays evidence-only with no code changes:

- run only the temporary evidence harness and any direct helper/integration checks used to answer the question

If schema or helper code changes occur, run:

- `flutter test test/core/database/helpers/messages_db_helpers_test.dart`
- `flutter test test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart`
- `flutter test test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart`
- `flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart`
- `flutter test test/core/database/integration/full_migration_chain_test.dart`
- `flutter test test/features/conversation/integration/incomplete_upload_recovery_test.dart`
- `flutter test test/features/conversation/integration/media_attachment_flow_test.dart`
- `flutter test test/features/conversation/integration/voice_message_exchange_test.dart`

If the change is only the `messages` candidate and does not touch media paths, `voice_message_exchange_test.dart` is lower priority, but it should still be run if the migration changes DB version or shared media schema setup.

If the `media_attachments(download_status)` index lands, also run at least one concrete group-side verification file that exercises shared `upload_pending` behavior, or run the full Group Messaging Gate.

## 10. subsystem gate(s), if relevant

`1:1 Reliability Gate` if schema or helper code changes.

Canonical gate from `Test-Flight-Improv/14-regression-test-strategy.md`:

```bash
flutter test \
  test/features/conversation/integration/two_user_message_exchange_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  test/features/conversation/integration/media_attachment_flow_test.dart \
  test/features/conversation/integration/media_retry_smoke_test.dart \
  test/features/conversation/integration/voice_message_exchange_test.dart \
  test/features/conversation/integration/incomplete_upload_recovery_test.dart \
  test/features/conversation/integration/send_then_lock_delivery_test.dart \
  test/features/conversation/integration/stuck_sending_recovery_test.dart \
  test/features/conversation/integration/quote_reply_thread_test.dart
```

For pure evidence work with no schema/helper changes:

- no subsystem gate is required beyond the temporary evidence harness

If the `media_attachments(download_status)` index lands, shared attachment-retry behavior is no longer 1:1-only, so add either one concrete group-side verification file or the full Group Messaging Gate.
- if a shared `media_attachments(download_status)` index lands, re-evaluate whether Group Messaging Gate coverage is also required because group retry paths use the same `upload_pending` scan

## 11. whether Baseline Gate is required

Optional for profile-only / evidence-only work.

Yes if a migration or DB-helper code changes.

Reason:

- Session 19 explicitly allows a no-code-change outcome
- once schema or helper code changes, this is no longer pure measurement

## 12. whether Startup / Transport Gate is required

Run if the DB version or migration chain changes.

Do not run it for pure evidence-only work with no schema change.

Reason:

- Session 19 itself is not transport work
- but a DB version bump or migration-chain change can affect startup/resume behavior and therefore needs the startup/transport validation path

## 13. done criteria

Session 19 is complete when one of these is true:

- explicit evidence shows neither candidate index is worth adding now, and the session ends with no code change
- explicit evidence shows one or both candidates are justified, and only that migration work lands with schema and migration-chain coverage

And all of these are true:

- the decision is based on query plans, row-scan/timing evidence, and call frequency, not inspection alone
- the plan distinguishes the stuck-message recovery path from the periodic unacked retry path
- the plan distinguishes the live `upload_pending` media path from any still-unproven batch `pending` caller path
- if a migration lands, `full_migration_chain_test.dart` proves the new index or indexes exist after fresh install and upgrade
- the session stays narrow to the two candidate indexes

## 14. dependency impact on later sessions if this session blocks

- Later sessions do not need to stop if Session 19 stays unresolved, because current behavior is already treated as acceptable by the repo for the `messages` recovery scan and remains functionally covered by existing tests.
- What cannot happen is speculative schema churn: later sessions must not assume these indexes exist or are needed until Session 19 captures evidence.
- If the session ends with "no migration justified", later DB-related sessions should treat that as the resolved answer, not reopen generic index work without new evidence.
- If the session blocks only on evidence quality, that blocker stays local to Session 19 rather than becoming a reason to widen into general storage tuning.

## 15. scope guard

- Do not add either index from inspection alone.
- Do not broaden into "index every status field" or generic SQLite cleanup.
- Do not change repository APIs unless the smallest justified migration truly requires it.
- Do not treat correctness tests as performance proof.
- Do not skip full migration-chain coverage if a new migration lands.
- If the evidence says the current scans are rare and cheap, stop there.
