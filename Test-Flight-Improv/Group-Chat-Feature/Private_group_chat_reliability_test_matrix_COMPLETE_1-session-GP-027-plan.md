# GP-027 Session Plan

Status: accepted/closed

## Source Row

| Row | Title | Priority | Source status | Gap class |
|-----|-------|----------|---------------|-----------|
| GP-027 | Out-of-order live messages render in deterministic order | P1 | Covered | needs_code_and_tests |

## Gap Classification

GP-027 was repo-owned and runnable. The source row remained `Open` because no
exact row-owned proof delivered a later timestamp first, then an earlier
timestamp, verified live timeline order, and verified the same order after a
screen restart. Production inspection found the deterministic ordering path
already present in `group_message_ordering.dart`, `GroupMessageRepositoryImpl`,
`InMemoryGroupMessageRepository`, and `GroupConversationWired._upsertMessage`,
so the row could close with exact regression coverage rather than runtime code.

## Implementation Plan

1. Add a GP-027 widget regression to `group_conversation_wired_test.dart`.
2. Deliver `M2` before `M1` through the same persisted repository and live stream
   path used by `GroupConversationWired`.
3. Assert the live conversation renders by product timeline order.
4. Dispose and rebuild the wired screen against the same repository to model a
   restart/reopen.
5. Assert the persisted reload keeps the same deterministic order.
6. Run focused, adjacent widget, adjacent repository, named groups, and diff
   hygiene gates.

## Execution Evidence

- Added `test/features/groups/presentation/group_conversation_wired_test.dart::GP-027 out-of-order live messages keep deterministic order after restart`.
- Existing production path inspected: `lib/features/groups/domain/utils/group_message_ordering.dart::orderGroupMessagesForTimeline`, `lib/features/groups/domain/repositories/group_message_repository_impl.dart::getMessagesPage`, and `lib/features/groups/presentation/screens/group_conversation_wired.dart::_upsertMessage`.
- `dart format test/features/groups/presentation/group_conversation_wired_test.dart` passed.
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'GP-027 out-of-order live messages keep deterministic order after restart'` passed (`+1`).
- `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --name 'GP-027|MS003 live stream upsert|MS004 live stream upsert'` passed (`+3`).
- `flutter test --no-pub test/features/groups/domain/repositories/group_message_repository_impl_test.dart --name 'uses message id as latest tie-breaker|MS004 orders quoted parent before reply'` passed (`+3`).
- `./scripts/run_test_gates.sh groups` passed (`+160`).

## Final Verdict

Accepted/closed. GP-027 is now `Covered` by exact row-owned widget evidence for
out-of-order live arrival plus restart-stable persisted ordering. No production
runtime change was required because existing shared timeline ordering already
sorts both live upserts and repository reloads deterministically. Residual-only:
none for GP-027. Continue from GI-034, the next unresolved row in ordered ledger
order.
