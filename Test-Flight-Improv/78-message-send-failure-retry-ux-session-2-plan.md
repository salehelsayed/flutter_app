# 78 Session 2 Plan - Conversation Failed-Message Recovery UX

## Real scope

- Add a direct retry affordance for failed outgoing text rows in the
  conversation surface.
- Keep failed media retry/delete controls available.
- Hide normal Edit for failed outgoing rows.
- Prevent the restored-composer resend trap from creating a second outgoing row
  when the restored draft still belongs to the failed attempt.
- Add focused widget/wired tests for the new UI behavior.

Out of scope: automatic retry race proof, lifecycle/device smoke, relay
changes, broad visual redesign, and stable closure doc updates.

## Closure bar

Session `2` is complete when failed text rows expose a direct retry path, failed
rows no longer present Edit as the recovery path, and sending the unchanged
restored failed draft retries the original failed row instead of creating a new
message ID.

## Source of truth

- `Test-Flight-Improv/78-message-send-failure-retry-ux.md`
- `Test-Flight-Improv/78-message-send-failure-retry-ux-session-breakdown.md`
- Session `1` accepted application contract
- Current `ConversationScreen`, `ConversationWired`, `LetterCard`, and their
  direct tests

## Session classification

`implementation-ready`

## Exact problem statement

Failed text-only rows currently show a failed status but no direct recovery
control. The visible workaround is normal Edit, and a restored composer draft
can create a new optimistic row for the same failed send attempt.

## Files and repos to inspect next

- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/widgets/letter_card_test.dart`

## Existing tests covering this area

- `conversation_screen_test.dart` covers failed media retry/delete controls and
  edit context-menu visibility.
- `conversation_wired_test.dart` covers failed send restoration, edit behavior,
  and same-row edit submission.
- `letter_card_test.dart` covers failed media action rendering and status
  semantics.

## Regression/tests to add first

- `LetterCard`/`ConversationScreen` failed text retry action rendering and tap.
- Failed outgoing rows hide Edit in the context overlay.
- `ConversationWired` restored failed draft retry settles the original row and
  does not call the normal new-send function a second time.

## Step-by-step implementation plan

1. Add a generic failed-message retry callback/key in `LetterCard` while leaving
   failed-media delete behavior unchanged.
2. Add `ConversationScreen.onRetryFailedMessage`, render it for failed outgoing
   text rows, and hide Edit for failed rows.
3. In `ConversationWired`, route failed text retry to `retryFailedMessage(...)`.
4. Track composer snapshots restored from failed text sends; when the unchanged
   restored draft is sent, retry the original failed row instead of creating a
   new optimistic row.
5. Run the direct presentation suites.

## Risks and edge cases

- Do not remove failed media delete.
- Do not hide Edit for delivered/sent eligible messages.
- Do not clear the restored composer draft when a retry fails.
- Do not create a second outgoing row for the unchanged restored failed draft.

## Exact tests and gates to run

- `flutter test --no-pub test/features/conversation/presentation/widgets/letter_card_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart`

Run `./scripts/run_test_gates.sh 1to1` after Session `3` unless Session `2`
changes shared send/retry behavior beyond presentation wiring.

## Known-failure interpretation

Failures outside the listed direct suites are not Session `2` blockers unless
the changed presentation or retry wiring caused them.

## Done criteria

- Direct widget/wired tests pass.
- Failed text row retry is visible and accessible.
- Failed row Edit is hidden.
- Restored failed draft resend targets the original failed row.
- Breakdown ledger records Session `2`.

## Scope guard

No app-wide design rewrite, no new persistence schema, no group chat scope, no
new retry service, and no lifecycle acceptance matrix work in this session.

## Accepted differences / intentionally out of scope

The visible retry label can remain simple and consistent with existing failed
media action copy. Final marketing/product copy is not decided here.

## Dependency impact

Session `3` should test races against the real user-visible retry path from
this session.
