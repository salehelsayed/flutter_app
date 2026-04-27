# 78 - Session 3 Plan: Retry Race, Lifecycle, and Dedupe Acceptance Proof

## Scope

- Prove the user-visible failed-draft recovery path cannot create a second
  outgoing row after automatic retry settles the original failed row.
- Prove retry services no-op once the canonical row has already settled.
- Prove same-ID receiver dedupe remains observable for encrypted v2 retry
  envelopes.
- Prove periodic online sweeps do not resurrect a settled failed attempt.

## Implementation Plan

1. Patch `ConversationWired` so a send from an unchanged restored failed draft
   first checks the restored row. If the row is already `sent` or `delivered`,
   clear the restored composer state instead of creating a new message.
2. Add a `conversation_wired_test.dart` regression for automatic retry settling
   a failed row while the restored draft is still visible.
3. Add retry use-case tests that exercise post-settlement no-op behavior for
   failed-row and unacked retry paths.
4. Add an encrypted v2 duplicate-delivery integration test using the existing
   two-user listener stack.
5. Add a pending retrier test proving a periodic sweep after settlement finds no
   failed/unacked work and performs no transport replay.

## Acceptance Gates

- `flutter test --no-pub test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name 'automatic retry settling a restored failed draft prevents a second send'`
- `flutter test --no-pub test/features/conversation/application/retry_failed_messages_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/application/retry_unacked_messages_use_case_test.dart`
- `flutter test --no-pub test/features/conversation/integration/two_user_message_exchange_test.dart --plain-name 'encrypted v2 retry envelope duplicates materialize once for the receiver'`
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'periodic sweep does not replay a row already settled by manual recovery'`

## Closure Bar

- Sender history remains one visible row for the failed-send attempt after any
  automatic/manual retry ordering covered here.
- Receiver history remains one visible row for duplicate encrypted v2 replay.
- Already-delivered rows are outside failed and unacked retry query windows.
