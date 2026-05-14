# GI-024 Session Plan: Duplicate Replay Idempotence

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-024`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:16:00 CEST | Controller | Source matrix GI-024 row; breakdown row 143; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; adjacent live-plus-inbox dedupe, history-gap repair, and GI-023 replay tests | The source row remained `Open` and the breakdown marked GI-024 `needs_code_and_tests` / `implementation-ready`. Repo inspection found the required production behavior already exists: `handleIncomingGroupMessage` dedupes by `messageId` before normal save when no event-log tamper gate is installed, duplicate handling returns `null`, `GroupMessageListener` emits stream/notification only for non-null new messages, and replay drain routes signed envelopes through the listener/handler path. The missing piece was exact row-owned proof that repeated old replay envelopes cannot duplicate storage, roll back read/status/timestamp fields, or spam notification/listener output. | Keep the original `needs_code_and_tests` classification but close it with tests-only exact Flutter app proof because production already satisfies the row-owned contract. Add `GI-024 duplicate replay is idempotent without status rollback or notification spam`, run adjacent dedupe/replay gates, and update source/breakdown evidence to `Covered`/`accepted`. |

## Scope

GI-024 owns duplicate old signed offline replay behavior at the Flutter app replay/listener boundary. The row closes only when repeated delivery of the same valid replay envelope stores one timeline row, preserves existing message state after later redelivery, and does not emit additional user-visible listener or notification events.

Out of scope: changing relay retention policy, Go inbox storage implementation, media enrichment semantics beyond duplicate-safe adjacent proof, product notification copy, and simulator-only real relay evidence.

## Execution Contract

1. Inspect current replay-to-listener path and duplicate handling in `handleIncomingGroupMessage`.
2. Add an exact row-owned Flutter app regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
3. Feed the same signed old replay envelope twice in the first page and twice again in a later redelivery page.
4. Assert the first drain stores and emits/notifies exactly once.
5. Mark the stored row read, then redeliver the same envelope.
6. Assert storage remains exactly one row and text, timestamp, sender, status, incoming flag, and `readAt` are unchanged.
7. Assert no second stream emission and no second notification.
8. Assert duplicate flow evidence is emitted for the later two redelivered records with `dedupeBy: messageId`.
9. Run focused GI-024, adjacent listener/replay dedupe gates, prior GI-023 replay guard, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-024 offline replay proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-024'` |
| Listener replay emission guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed group messages emit on the listener stream when provided'` |
| Live plus inbox duplicate enrichment guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once'` |
| History repair duplicate/order guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows'` |
| Prior replay epoch guard | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-023'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-024 scope is limited to the exact row-owned test, this plan, source matrix row GI-024, and breakdown closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:16:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-024 duplicate replay is idempotent without status rollback or notification spam`. The test stores the same signed replay envelope twice in one page, verifies one persisted incoming row, one listener stream event, and one notification, marks the row read, redelivers the same envelope twice again, then verifies storage count remains one and text, timestamp, sender, status, incoming flag, and `readAt` are unchanged. It also verifies no additional stream/notification output and two later `GROUP_HANDLE_INCOMING_MSG_DUPLICATE` flow events with `dedupeBy: messageId`. Production inspected: `handle_incoming_group_message_use_case.dart` messageId dedupe returns `null` for existing rows, `group_message_listener.dart` emits stream/notification only when the handler returns a new row, and `drain_group_offline_inbox_use_case.dart` routes signed replay through that listener path. | Covered the row-owned duplicate old replay attack contract with exact Flutter app proof; no production code change was required because existing idempotence behavior already satisfied the contract once row-owned proof was added. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-024'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'replayed group messages emit on the listener stream when provided'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-023'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-024 is covered by exact tests-only Flutter app replay evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-024; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-024 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 143, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- The original implementation-ready disposition is not downgraded to docs-only work; it closes through exact executable row-owned proof after production inspection showed the repo-owned behavior already exists.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-024 ownership and must not mask a repo-owned blocker.
