# GI-034 Session Plan: Offline Replay Notification Suppression

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-034`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-14 02:52 CEST | Controller | Source matrix GI-034 row; breakdown session ledger row 210; prior GI-024 duplicate replay proof; listener notification path in `lib/features/groups/application/group_message_listener.dart`; replay drain path in `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `RecentRemoteNotificationGate`; unread-count repository behavior; test inventory application section | The source row remained `Open` and no adjacent GI-034 plan existed. GI-024 proved duplicate replay idempotence for one old envelope, but no GI-034-owned proof combined offline replay, a recent remote-push announcement, duplicate replay delivery, local notification suppression, and unread-count preservation after a later re-drain. | Add exact row-owned Flutter app proof in the offline-inbox suite. The proof should drain through the real `GroupMessageListener`, seed one recent remote-push marker, replay a duplicate pushed message plus a distinct message, assert one local notification and two unread rows, mark the group read, replay both messages again, and assert no notification or unread resurrection. |

## Scope

GI-034 owns the app-side offline replay notification and unread-count contract. Replayed group messages should not create duplicate local notifications when a recent remote push already announced the same message or when the same replay is delivered again, and duplicate re-drain must not re-open messages the user already marked read.

Out of scope: inbox relay plaintext privacy, repair-range metadata, native stream cleanup, native relay storage, live PubSub notification routing, full push-device integration, notification UI rendering, and product changes to unread policy.

## Execution Contract

1. Add `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-034 offline replay suppresses duplicate notifications and preserves unread state`.
2. Use signed offline replay envelopes for two incoming group messages.
3. Mark one replay message as recently announced by remote push through `RecentRemoteNotificationGate`.
4. Drain a cursor page through `GroupMessageListener` with `FakeNotificationService`, including a duplicate of the already-pushed replay.
5. Assert two persisted incoming rows, one local notification for the non-pushed distinct replay, and unread totals of two.
6. Mark the group read, redeliver both signed replays, and assert storage count, listener emissions, notification count, and unread totals remain unchanged.
7. Run focused GI-034, required Go/relay inbox owners, Flutter drain/retry inbox owners, named groups gate, format, and diff hygiene gates.

## Required Gates

| Gate | Command |
|---|---|
| Format | `dart format test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Focused GI-034 app proof | `flutter test --no-pub --plain-name 'GI-034 offline replay suppresses duplicate notifications and preserves unread state' test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` |
| Go inbox/history proof | `cd go-mknoon && go test ./node -run 'GroupInbox\|HistoryRepair' -count=1` |
| Relay inbox/dedup proof | `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` |
| Flutter drain/retry inbox proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` |
| Named groups gate | `./scripts/run_test_gates.sh groups` |
| Hygiene | `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior gap-closure rollout changes and accepted session artifacts. GI-034 scope is limited to the exact row-owned Flutter replay-notification regression, this adjacent plan, source/breakdown closure updates, and test inventory counts unless focused proof exposes a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-14 02:52 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-034 offline replay suppresses duplicate notifications and preserves unread state`. The test uses signed offline replay envelopes, a unique `RecentRemoteNotificationGate`, `FakeNotificationService`, and the real `GroupMessageListener` replay path. It proves the remote-pushed replay suppresses local notification, an in-page duplicate replay emits no extra notification/row, the distinct replay notifies once, unread totals are exactly two, and a second duplicate re-drain after `markAsRead` does not resurrect unread state or notifications. | Covered the row-owned offline replay notification/unread contract with tests-only Flutter app evidence; no production code change required because existing messageId dedupe, remote-push notification gate, and read-state preservation already satisfy the contract once exact proof exists. |

## Verification

| Gate | Result |
|---|---|
| `dart format test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed. |
| `flutter test --no-pub --plain-name 'GI-034 offline replay suppresses duplicate notifications and preserves unread state' test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`+1 All tests passed`). |
| `cd go-mknoon && go test ./node -run 'GroupInbox\|HistoryRepair' -count=1` | Passed (`ok github.com/mknoon/go-mknoon/node 0.813s`). |
| `cd go-relay-server && go test ./... -run 'GroupInbox\|InboxDedup' -count=1` | Passed (`ok github.com/mknoon/relay-server 0.781s`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/application/retry_failed_group_inbox_stores_use_case_test.dart` | Passed (`+93 All tests passed`). |
| `./scripts/run_test_gates.sh groups` | Passed (`+160 All tests passed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-034 is covered by exact tests-only Flutter app evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-034; GR-002 is the next unresolved session in ordered ledger order.

## Closure Bar

- Source row GI-034 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row inventory, row disposition, session ledger row 210, ordered row 210, closure progress, and session closure ledger are updated to `covered/accepted`.
- Test inventory includes the added GI-034 Dart application test and aggregate count updates.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
- Residual work, if any, must be outside GI-034 ownership and must not mask a repo-owned blocker.
