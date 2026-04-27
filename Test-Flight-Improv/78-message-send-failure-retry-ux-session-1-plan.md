# 78 Session 1 Plan - Same-Attempt Failed-Send Recovery Contract

## Real scope

- Keep manual failed-message recovery on the existing failed row and message ID.
- Prevent failed outgoing rows from being submitted through normal edit
  semantics.
- Prove failed text recovery uses first-delivery chat semantics, not
  `actionEdit`, and does not create a new optimistic UUID.

Out of scope: conversation button placement, accessibility wording, lifecycle
race proof, relay redesign, group chat retry UX, and broad edit-message
redesign.

## Closure bar

Session `1` is complete when application-level recovery of a failed outgoing
1:1 text row:

- targets only the original failed row when it is still `failed`
- reuses the original message ID and timestamp
- sends a normal chat-message payload for first delivery
- never uses normal `editChatMessage(...)` for failed outgoing rows
- leaves existing encrypted v2 `wireEnvelope` replay and failed media retry
  behavior intact

## Source of truth

- `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- `Test-Flight-Improv/19-1to1-message-reliability-closure-reference.md`
- `Test-Flight-Improv/test-gate-definitions.md`
- Current code and tests win over stale prose.

## Session classification

`implementation-ready`

## Exact problem statement

The app already has targeted failed-row retry, but normal edit still accepts a
failed outgoing message and can produce `actionEdit` wire semantics for what the
sender experiences as failed-send recovery. The application layer needs to make
that boundary explicit before UI work exposes recovery affordances.

## Files and repos to inspect next

- `lib/features/conversation/application/send_chat_message_use_case.dart`
- `lib/features/conversation/application/retry_failed_messages_use_case.dart`
- `test/features/conversation/application/send_chat_message_use_case_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `test/core/bridge/fake_bridge.dart`
- `test/core/services/fake_p2p_service.dart`

## Existing tests covering this area

- `retry_failed_messages_use_case_test.dart` covers failed-row retry, targeted
  retry, encrypted v2 replay, legacy envelope guards, and media retry adjuncts.
- `send_chat_message_use_case_test.dart` covers edit payload semantics for
  eligible messages.
- Missing: direct proof that failed-row recovery does not emit `actionEdit`, and
  direct proof that `editChatMessage(...)` rejects failed outgoing rows.

## Regression/tests to add first

- Add application tests proving targeted failed text retry reuses the original
  row ID and timestamp and sends a non-edit payload.
- Add a send-use-case test proving `editChatMessage(...)` rejects failed
  outgoing rows before encryption or network send.

## Step-by-step implementation plan

1. Add the two failing application-level regressions.
2. Tighten `editChatMessage(...)` to reject `originalMessage.status == 'failed'`.
3. Keep `retryFailedMessage(...)` as the canonical same-row manual recovery
   primitive unless the new tests prove it is insufficient.
4. Run the directly affected application suites.
5. Update the breakdown ledger with Session `1` results.

## Risks and edge cases

- Do not break normal edit for already delivered eligible messages.
- Do not block automatic failed-row retry or encrypted v2 envelope replay.
- Do not change delivery status semantics.

## Exact tests and gates to run

- `flutter test --no-pub test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/application/send_chat_message_use_case_test.dart`
- `./scripts/run_test_gates.sh 1to1` if production send/retry semantics changed
  beyond the failed-edit guard and covered targeted retry path.

## Known-failure interpretation

Pre-existing unrelated failures in dirty worktree test files are not Session
`1` blockers unless they are in the direct command outputs above and tied to the
changed send or retry behavior.

## Done criteria

- Direct application tests pass.
- Failed outgoing edit is rejected.
- Targeted failed text retry remains same-row and non-edit.
- Breakdown ledger records Session `1` as accepted or honestly blocked.

## Scope guard

No UI changes, lifecycle race tests, relay changes, new DB schema, or product
copy decisions in this session.

## Accepted differences / intentionally out of scope

Manual failed-message recovery can reuse the existing targeted retry machinery
when it satisfies the same-attempt contract; a new use-case wrapper is not
required unless tests expose a semantic gap.

## Dependency impact

Session `2` can expose failed-message recovery in the conversation UI only after
this session establishes that the application-layer target is safe.
