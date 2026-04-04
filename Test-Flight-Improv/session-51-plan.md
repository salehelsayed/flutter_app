# Session 51 Plan: Introduction Accept-Before-Send Durability

## Final verdict

`ready_to_execute`

## Final plan

### 1. real scope

- Fix the introduction accept/pass race where a response can arrive before the matching intro `send` exists locally.
- Make that out-of-order response durable across direct delivery, relay inbox replay, and app restart.
- Preserve the existing introduction data model and mutual-acceptance behavior for in-order delivery.
- Keep the scope strictly inside introduction persistence, introduction replay, and recovered inbox handling.
- Explicit non-goals:
  redesigning the intro protocol, adding new wire fields, changing chat unknown-sender policy beyond intro-related recovery, or reopening unrelated message reliability work.

### 2. closure bar

- If an intro `accept` or `pass` reaches a device before the corresponding intro `send`, that device must not lose the response.
- When the matching intro `send` later arrives, the deferred response must replay automatically and produce the same final intro state as if messages had arrived in order.
- Recovered inbox introduction messages must only be deleted after they were either applied or durably deferred.
- Mutual acceptance must still create the contact exactly once and converge to `mutualAccepted`.
- Existing in-order intro tests must continue to pass unchanged.

### 3. source of truth

- Current repo code is the source of truth:
  `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
  `lib/features/introduction/application/introduction_listener.dart`
  `lib/core/services/p2p_service_impl.dart`
  `lib/features/introduction/domain/repositories/introduction_repository.dart`
  `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
  `lib/core/database/helpers/introductions_db_helpers.dart`
  `lib/main.dart`
- Existing repo-local staging pattern:
  `lib/core/database/migrations/028_posts_engagement.dart`
  `lib/core/database/helpers/post_pending_child_events_db_helpers.dart`
  `lib/features/posts/domain/repositories/post_repository_impl.dart`
- Existing durable inbox replay contract:
  `lib/core/services/p2p_service_impl.dart`
  `test/core/services/p2p_service_impl_test.dart`
- Existing intro coverage baseline:
  `test/features/introduction/application/handle_incoming_introduction_test.dart`
  `test/features/introduction/application/introduction_listener_test.dart`
  `test/features/introduction/integration/introduction_multi_node_test.dart`
  `test/features/introduction/regression/introduction_regression_test.dart`

### 4. session classification

- `bugfix`
- `reliability`
- `tdd_required`
- `migration_and_repository_change`

### 5. exact problem statement

- `_handleResponse` in `handle_incoming_introduction_use_case.dart` drops intro `accept` and `pass` permanently when the intro row does not exist yet.
- That ordering inversion is realistic because intro `send` and intro `accept` each take independent direct-first then inbox-fallback delivery paths.
- Current relay inbox replay only gives durable committed/retryable/rejected semantics to `chat_message`; intro messages are forwarded to the typed stream and deleted immediately.
- Result:
  one side can remain `pending` forever, contacts may never be created, later chat recovery can strand on `unknownSender`, and users experience intros as unreliable even when notifications arrive.

### 6. storage contract to enforce

- Add a durable intro-response staging store owned by the introduction repository.
- Store enough data to deterministically replay the response:
  `response_key`
  `introduction_id`
  `action`
  `responder_id`
  `responder_username`
  `created_at`
- Use additive storage only.
- Order replay by `created_at ASC, response_key ASC`.
- Deduplicate replayable rows by a stable response key derived from `introductionId + responderId + action`.
- Keep storage semantics intro-specific; do not overload chat or inbox tables with intro state.

### 7. files and repos to inspect next

- `lib/core/database/migrations/045_inbox_staging_entries.dart`
- `lib/core/database/migrations/019_introductions_table.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/features/introduction/domain/models/introduction_model.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `test/shared/fakes/in_memory_introduction_repository.dart`

### 8. existing tests covering this area

- `test/features/introduction/application/handle_incoming_introduction_test.dart`
  covers normal `send`, `accept`, `pass`, and mutual acceptance, but not response-before-send.
- `test/features/introduction/application/introduction_listener_test.dart`
  covers listener dispatch and blocked-sender semantics, but not deferred response durability or direct confirmation semantics.
- `test/features/introduction/integration/introduction_multi_node_test.dart`
  covers live convergence only after both peers already received the original `send`.
- `test/core/services/p2p_service_impl_test.dart`
  covers durable replay for staged chat inbox rows, but not introduction-specific replay contracts.

### 9. regressions/tests to add first

1. Add a failing unit test in `test/features/introduction/application/handle_incoming_introduction_test.dart`:
   `accept before send is deferred and replays when send arrives`.
2. Add a second failing unit test in the same file:
   `pass before send is deferred and replays when send arrives`.
3. Add a failing inbox replay test in `test/core/services/p2p_service_impl_test.dart`:
   `staged introduction rows remain durable until intro replay callback commits them`.
4. Add a listener-level regression in `test/features/introduction/application/introduction_listener_test.dart` only if needed to pin direct-message confirmation and deferred handling.
5. Extend the multi-node introduction test only after the lower-level regressions pass, and only if the fake network can reproduce the order inversion without brittle timing.

### 10. implementation plan

1. Add a new additive migration for deferred intro responses.
   Use the next DB version and wire both `onCreate` and `onUpgrade`.
2. Add DB helpers for:
   insert deferred response,
   load deferred responses for one intro,
   delete one deferred response.
3. Extend `IntroductionRepository` and `IntroductionRepositoryImpl` with deferred-response methods.
4. Extend the in-memory intro repository used by tests with the same deferred-response contract.
5. Update `handleIncomingIntroduction`:
   on `accept`/`pass` with missing intro row, persist a deferred response and return a new non-error result.
6. Update the `send` path inside `handleIncomingIntroduction`:
   after saving the intro row, load deferred responses, replay them in order through the same response application logic, and delete them only after successful application.
7. Refactor response application into a small helper so direct handling and deferred replay use exactly the same status/update logic.
8. Update `IntroductionListener` to expose a structured `processIncomingMessage(...)` outcome, similar to `ChatMessageListener`.
9. Add intro-specific recovered inbox replay support in `P2PServiceImpl`.
   Recovered intro rows must use committed/retryable/rejected semantics instead of fire-and-forget forwarding.
10. Wire the new intro replay callback from `main.dart` through the existing app stack.
11. Re-run the targeted tests, then run analyze on touched files.

### 11. risks and edge cases

- Duplicate accept/pass deliveries must remain idempotent.
- Replaying two deferred responses for the same intro must not create duplicate contacts.
- Deferred replay must respect `alreadyConnected` and `passed` outcomes exactly as the live path does today.
- Inbox replay must not delete intro rows before the intro listener or handler durably accepts responsibility.
- The fix must not require new fields in the intro wire payload.

### 12. exact tests and gates to run

- `flutter test test/features/introduction/application/handle_incoming_introduction_test.dart`
- `flutter test test/features/introduction/application/introduction_listener_test.dart`
- `flutter test test/core/services/p2p_service_impl_test.dart`
- `flutter test test/features/introduction/application/mutual_acceptance_test.dart`
- `flutter test test/features/introduction/integration/introduction_multi_node_test.dart`
- `flutter test test/features/introduction/regression/introduction_regression_test.dart`
- `flutter analyze lib/main.dart lib/core/services/p2p_service_impl.dart lib/features/introduction/application/handle_incoming_introduction_use_case.dart lib/features/introduction/application/introduction_listener.dart lib/features/introduction/domain/repositories/introduction_repository.dart lib/features/introduction/domain/repositories/introduction_repository_impl.dart`

### 13. known-failure interpretation

- If the new handler tests fail before the migration/repository work lands, that is expected and confirms the regression is real.
- If the inbox replay test fails after handler deferral is added, that means relay replay still has a delete-before-commit hole.
- If mutual acceptance tests fail after replay wiring, the new helper changed status derivation or contact creation semantics and must be corrected before merge.

### 14. done criteria

- Direct or inbox-delivered out-of-order intro responses are durably staged instead of dropped.
- A later intro `send` automatically applies staged responses and converges to the correct intro state.
- Recovered inbox intro replay no longer deletes intro rows before a committed or durable-deferred outcome.
- All targeted tests and analyze commands pass.

### 15. scope guard

- No protocol redesign.
- No new push or notification routing work.
- No chat schema changes unrelated to intro recovery.
- No destructive migration of existing intro rows.
- No expansion of intro UX copy or screens.

### 16. accepted differences / intentionally out of scope

- This session improves intro durability; it does not solve every possible chat unknown-sender path unrelated to introductions.
- The fix may reuse existing intro row timestamps and current overall-status derivation without adding richer event metadata.
- If fake multi-node tests cannot deterministically reproduce reorder at the integration layer, unit and inbox replay tests remain the mandatory closure bar.

### 17. dependency impact

- Database version bump is required.
- Full migration chain coverage must include the new intro-response table.
- Main app composition must inject the new intro replay callback and repository closures.
- Existing intro tests and fakes must adopt the extended introduction repository contract.

## Structural blockers remaining

- None. The repo already has the necessary patterns for additive migration, helper-backed repository methods, deferred-event staging, and durable inbox replay.

## Incremental details intentionally deferred

- No separate background repair job is added in this session.
- No attempt is made to retroactively heal already-stranded production intro rows beyond the normal replay path.

## Accepted differences intentionally left unchanged

- Intro `accept` and `pass` payloads remain compact and do not include the full intro object.
- `IntroductionModel` remains the source of derived status once the base intro row exists locally.

## Exact docs/files used as evidence

- `Test-Flight-Improv/session-50-plan.md`
- `lib/features/introduction/application/handle_incoming_introduction_use_case.dart`
- `lib/features/introduction/application/introduction_listener.dart`
- `lib/features/introduction/domain/repositories/introduction_repository.dart`
- `lib/features/introduction/domain/repositories/introduction_repository_impl.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/main.dart`
- `lib/core/database/migrations/019_introductions_table.dart`
- `lib/core/database/migrations/028_posts_engagement.dart`
- `lib/core/database/migrations/045_inbox_staging_entries.dart`
- `lib/core/database/helpers/introductions_db_helpers.dart`
- `lib/core/database/helpers/post_pending_child_events_db_helpers.dart`
- `test/features/introduction/application/handle_incoming_introduction_test.dart`
- `test/features/introduction/application/introduction_listener_test.dart`
- `test/features/introduction/integration/introduction_multi_node_test.dart`
- `test/core/services/p2p_service_impl_test.dart`

## Why the plan is safe or unsafe to implement now

- Safe:
  the change is additive, the repo already contains the right staging and migration patterns, and the broken ordering seam is clearly localized.
- Unsafe if done partially:
  fixing only the use case without durable inbox replay still leaves a delete-before-commit gap, and fixing only inbox replay without deferred intro storage still loses direct out-of-order responses.
