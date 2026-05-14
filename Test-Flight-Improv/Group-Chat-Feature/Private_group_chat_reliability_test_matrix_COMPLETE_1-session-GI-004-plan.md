# GI-004 Session Plan: Group Inbox Store Current Recipients

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-004`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 03:36:00 CEST | Controller | Source matrix GI-004 row; breakdown row 125; `lib/features/groups/application/send_group_message_use_case.dart::_loadGroupSendMembership`; existing GM-019/GM-020/GP-008 recipient tests | The source row remains `Open`. Existing tests prove adjacent removed/re-add and latest-config recipient behavior, and production derives `recipientPeerIds` from current group members at send time, excluding sender and future `joinedAt` members. No exact GI-004 row-owned test asserts the current remove/re-add entitlement window for the `group:inboxStore` payload. | Add a focused Flutter application regression labeled GI-004 that sends during a removed window and after re-add, then verifies `recipientPeerIds` exclude removed/self and include the re-added member only after re-add. |

## Scope

GI-004 owns app-level recipient selection for durable `GroupInboxStore` calls. The `group:inboxStore` payload must carry exactly current entitled recipient peer ids for the send timestamp: sender excluded, removed members excluded, and re-added members included only after their re-add/join time.

Out of scope: Go node request serialization, relay-side storage authorization, inbox retry execution, live PubSub fanout, and UI rendering.

## Execution Contract

1. Add row-owned Flutter test `GI-004 group inbox recipients follow current remove and re-add entitlement windows` in `test/features/groups/application/send_group_message_use_case_test.dart`.
2. Seed Alice, Bob, and Charlie; remove Charlie before the first send.
3. Send a message during the removed window and assert `group:inboxStore.recipientPeerIds == ['peer-2']`, excluding Alice/self and Charlie/removed.
4. Re-add Charlie with a later `joinedAt`, send after that timestamp, and assert recipients are exactly Bob and Charlie with no duplicates or sender.
5. Run focused GI-004 and adjacent recipient-window gates plus dart format and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-004 recipient proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-004'` |
| Adjacent recipient-window proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019 removed-window durable recipients exclude re-added member until re-add'` |
| Additional latest-config recipient proof | `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-008 latest membership drives durable fallback after remove add'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted GI-001 through GI-003 artifacts. GI-004 scope is limited to the row-owned Flutter application regression, this plan, and closure documentation updates unless the focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 03:44:00 CEST | Executor | Added `test/features/groups/application/send_group_message_use_case_test.dart::GI-004 group inbox recipients follow current remove and re-add entitlement windows`. The test seeds Alice/Bob/Charlie, removes Charlie, sends during the removed window, verifies `group:inboxStore.recipientPeerIds == ['peer-2']` and excludes Alice/Charlie, then re-adds Charlie and verifies the post-readd durable inbox recipients are exactly Bob and Charlie with no sender or duplicates. | Covered the row-owned current-recipient entitlement contract with tests-only Flutter application evidence; no production code change required. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GI-004'` | Passed (`00:00 +1: All tests passed!`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GM-019 removed-window durable recipients exclude re-added member until re-add'` | Passed (`00:00 +1: All tests passed!`). |
| `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'GP-008 latest membership drives durable fallback after remove add'` | Passed (`00:00 +1: All tests passed!`). |
| `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart` | Passed (`Formatted 1 file (0 changed)`). |
| `git diff --check` | Passed after closure document updates. |

## Final Verdict

Accepted/closed. GI-004 is covered by exact tests-only Flutter application evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-004; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-004 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 125, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-004 ownership and must not mask a repo-owned blocker.
