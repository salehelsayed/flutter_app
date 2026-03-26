# Session 20 Plan: Remove Reload-After-Update Rebroadcasts Without Changing Consumer Behavior

## 1. real scope

Remove the unnecessary "update then immediate reload" paths used only to rebroadcast message status updates, while preserving the exact downstream message shape that `ConversationWired`, `FeedWired`, and lifecycle consumers rely on.

This session is narrower than Session 19 and stays centered on one repository boundary, with one lifecycle caller in verification scope:

- primary edit seam: `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- adjacent contract/reference files only: `message_repository.dart`, `messages_db_helpers.dart`, the lifecycle caller in `handle_app_paused.dart`, and the consumers in `conversation_wired.dart` and `feed_wired.dart`

Concrete repo evidence:

- `MessageRepositoryImpl.updateMessageStatus()` currently does:
  - `await dbUpdateMessageStatus(id, status);`
  - `final row = await dbLoadMessage(id);`
  - `_messageChangeController.add(ConversationMessage.fromMap(row));`
- `MessageRepositoryImpl.conditionalTransitionStatus()` also reloads via `dbLoadMessage(id)` before rebroadcasting, and `handle_app_paused.dart` calls it to move `sending -> failed` during pause handling.
- `05-database-storage-performance.md` already calls this out as a real but secondary inefficiency: "After some status updates, the repository reloads the row to rebroadcast it."
- `ConversationWired` consumes `messageChanges` for `sent`, `delivered`, and `failed`.
- `FeedWired` consumes `messageChanges` only for `sent` and `delivered`, not `failed`.

In scope:

- repository-level rebroadcast paths after status updates in both `updateMessageStatus()` and `conditionalTransitionStatus()`
- preserving exactly-once repository emission and consumer-visible message fields
- targeted lifecycle verification for the pause-driven `sending -> failed` path
- targeted feed verification because feed listens to the same stream for `sent` / `delivered`

Out of scope:

- redesigning the repository or thread summary model
- broader DB/helper cleanup
- changing conversation/feed refresh architecture beyond this status-rebroadcast seam

## 2. session classification

`implementation-ready`

Why:

- the inefficiency is explicit in the two live repository rebroadcast paths: `MessageRepositoryImpl.updateMessageStatus()` and `MessageRepositoryImpl.conditionalTransitionStatus()`
- the source report already identified it as real
- the required regression is clear and local: prove the update still emits the correct message shape, with the correct read count and exactly-once emission behavior
- no profiling or external evidence is required before making the change

## 3. files and repos to inspect next

Primary production files:

- `lib/features/conversation/domain/repositories/message_repository_impl.dart`
- `lib/features/conversation/domain/repositories/message_repository.dart`
- `lib/core/database/helpers/messages_db_helpers.dart`

Consumer impact checks:

- `lib/core/lifecycle/handle_app_paused.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`

Primary tests to reuse:

- `test/features/conversation/domain/repositories/message_repository_impl_test.dart`
- `test/features/conversation/domain/repositories/message_repository_impl_stuck_sending_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/core/lifecycle/app_lifecycle_pause_integration_test.dart`
- `test/core/lifecycle/pause_resume_retry_smoke_test.dart`

Feed-adjacent tests:

- `test/features/feed/presentation/screens/feed_wired_test.dart`

## 4. existing tests covering this area

Current useful coverage:

- `message_repository_impl_test.dart` already proves basic repository persistence and currently has a minimal `updateMessageStatus changes status` assertion.
- `message_repository_impl_stuck_sending_test.dart` already covers the separate stuck-sending recovery delegation path.
- `conversation_wired_sending_to_failed_test.dart` already proves open conversation UI reacts to repository change-stream updates for `sending -> failed`.
- `stuck_sending_recovery_test.dart` proves the recovery path transitions the same logical row and the retry path still works.
- `send_then_lock_delivery_test.dart` covers resume/retry behavior through real integration-style flows, including stuck sending and interrupted media sends.
- `app_lifecycle_pause_integration_test.dart` proves pause handling emits repository changes after transitioning sending messages to failed.
- `pause_resume_retry_smoke_test.dart` covers pause/resume retry ordering around those same lifecycle transitions.
- `feed_wired_test.dart` already has a targeted retry-success proof for feed-visible delivered status refresh.

What is missing:

- no repository-level regression currently proves:
  - how many DB reads happen during a status update
  - whether the updated message is emitted exactly once
  - whether the emitted message still includes all consumer-visible fields
- no current test pins the "no immediate reload" behavior directly
- feed coverage exists for retry success updates, but the Feed gate should only become required if the change affects feed-visible `sent` / `delivered` stream behavior

## 5. regression/tests to add first, if any

Add the repository-level regression first in `test/features/conversation/domain/repositories/message_repository_impl_test.dart`.

That regression must explicitly prove:

- `updateMessageStatus(...)` does not perform an unnecessary `dbLoadMessage(...)` reload after the update
- the updated message is emitted exactly once on `messageChanges`
- the emitted message still includes the fields consumers need, not only the new status
  - at minimum: `id`, `contactPeerId`, `senderPeerId`, `text`, `timestamp`, `status`, `isIncoming`, `createdAt`

Add the smallest second repository-level regression for `conditionalTransitionStatus(...)` because it is already a live reload-and-rebroadcast path through pause handling.

Do not start with UI tests. The repository contract is the first proving layer for this session.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Not applicable. Session 20 is not profile-gated or evidence-gated.

## 7. step-by-step implementation or evidence-collection plan

1. Confirm the current `updateMessageStatus(...)` and `conditionalTransitionStatus(...)` flows in `message_repository_impl.dart` and identify the exact extra reads to remove.
2. Confirm the repository change-stream contract in `message_repository.dart`.
3. Confirm current callers/consumers:
   - `handle_app_paused.dart` uses `conditionalTransitionStatus(...)` for pause-driven `sending -> failed`
   - `ConversationWired` listens for `sent`, `delivered`, and `failed`
   - `FeedWired` listens for `sent` and `delivered`
4. Add the repository-level regression first in `message_repository_impl_test.dart`:
   - count `dbLoadMessage(...)` calls
   - subscribe to `messageChanges`
   - update a message status through both repository paths
   - assert exactly-once emission and full message shape
5. Implement the smallest repository change that avoids the immediate reload while preserving the emitted shape across both paths.
6. Re-run the repository tests first.
7. Re-run the lifecycle and conversation UI/integration tests from the roadmap.
8. Run the targeted feed proof in `test/features/feed/presentation/screens/feed_wired_test.dart` because `FeedWired` consumes `sent` / `delivered` repository emissions directly. Treat the existing retry-success feed test as the starting point, and add the smallest `updateMessageStatus()`-specific feed regression there only if repository-path coverage is otherwise missing.
9. Run the full Feed / Surface Gate whenever the repository rebroadcast seam changes, because `FeedWired` listens directly to `messageChanges`.
10. Run the required gates and direct tests from the final scope.

## 8. risks and edge cases

- The repository may currently rely on `dbLoadMessage(...)` to reconstruct fields that are not present in the update call site. Any replacement emission path must preserve those fields.
- `ConversationWired` listens for `failed`, but `FeedWired` does not. This means feed impact is narrower than conversation impact and should not be assumed.
- Some status transitions originate from pause/retry/recovery paths rather than manual send/update paths, so the regressions must use realistic stored message shapes for both repository entry points.
- Emitting twice or emitting a partial message would be a behavior regression even if the DB write count improves.
- Do not turn this into a broader repository redesign or thread-summary optimization session.

## 9. exact tests to run after implementation, if code changes occur

- `flutter test test/features/conversation/domain/repositories`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `flutter test test/features/conversation/integration/stuck_sending_recovery_test.dart`
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `flutter test test/core/lifecycle/app_lifecycle_pause_integration_test.dart`
- `flutter test test/core/lifecycle/pause_resume_retry_smoke_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`

Conditional additional tests:

- `flutter test test/core/database/helpers/messages_db_helpers_test.dart`
- full `Feed / Surface Gate`

Run `messages_db_helpers_test.dart` if preserving full emitted message shape requires helper-contract edits rather than repository-only changes.
Run the targeted `feed_wired_test.dart` proof in addition to, not instead of, the named Feed / Surface Gate.

## 10. subsystem gate(s), if relevant

- `1:1 Reliability Gate`
- targeted `feed_wired_test.dart` direct proof when `updateMessageStatus()` changes
- `Feed / Surface Gate`

Canonical gates from `Test-Flight-Improv/14-regression-test-strategy.md`:

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

```bash
flutter test \
  test/features/feed/integration/feed_card_flow_test.dart \
  test/features/feed/integration/expanded_collapsed_card_test.dart \
  test/features/feed/integration/feed_color_smoke_test.dart
```

## 11. whether Baseline Gate is required

Yes.

Reason:

- Session 20 is implementation-ready and is expected to change Flutter production code in the repository layer
- the roadmap explicitly marks Baseline Gate as required

## 12. whether Startup / Transport Gate is required

No, in planned scope.

Reason:

- this session is about repository rebroadcast behavior after status updates
- it does not change startup ordering, DB versioning, or transport orchestration

Re-evaluate only if the implementation unexpectedly expands into shared recovery/startup behavior outside the repository seam.

## 13. done criteria

- The repository no longer performs an unnecessary "update then immediate reload" cycle purely to rebroadcast.
- The new repository-level regression proves:
  - DB read count is reduced as intended
  - the updated message is emitted exactly once
  - consumers still receive the fields they need
- Downstream UI behavior remains unchanged for the covered conversation, lifecycle, and recovery flows.
- The targeted feed proof passes, and the full Feed / Surface Gate is also green because `FeedWired` consumes the changed repository rebroadcast seam directly.

## 14. dependency impact on later sessions if this session blocks

- Later sessions do not need to stop entirely, but this low-severity storage cleanup remains unresolved until the rebroadcast contract is pinned.
- If Session 20 blocks, future repository or recovery work must avoid assuming the reload-after-update path has already been removed.
- The main dependency is local correctness: later sessions touching message status updates will have a weaker regression net until this repository-level contract exists.

## 15. scope guard

- Do not redesign the message repository or thread summary model.
- Keep the session about the rebroadcast path after updates.
- Do not broaden into generic DB/helper cleanup.
- Keep the feed requirement narrow but mandatory: run `feed_wired_test.dart` as targeted proof, but do not treat it as a substitute for the named Feed / Surface Gate.
- Do not weaken consumer-visible message shape just to remove one DB read.
