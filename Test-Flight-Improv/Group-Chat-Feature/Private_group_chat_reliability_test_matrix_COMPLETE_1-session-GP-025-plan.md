# GP-025 Session Plan: Duplicate Live Deliveries Dedupe At App Layer

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-025`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 02:18:00 CEST | Controller | Source matrix GP-025 row; breakdown row 119; `lib/features/groups/application/group_message_listener.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; existing `test/features/groups/application/group_message_listener_test.dart` duplicate PubSub proof; existing `handle_incoming_group_message_use_case_test.dart` message-id dedupe proof | The source row remains `Open`, but existing production already dedupes duplicate live `group_message:received` events by `messageId`: the use case returns `null` for duplicate IDs before saving, and the listener emits only non-null persisted messages. Existing listener test `LP013 duplicate PubSub delivery preserves first row and notification state` proves the row behavior but lacks a GP-025 row-owned label and current source/breakdown evidence. | Make the existing live duplicate proof exact row-owned GP-025 evidence, run focused listener and lower-layer dedupe gates, then close source/breakdown if they pass. No production code change is expected. |
| 2026-05-13 02:27:00 CEST | Controller | Renamed row-owned listener test, focused GP-025 listener gate, adjacent handle-incoming message-id dedupe gate, dart format, and `git diff --check` | The exact row-owned app-layer proof passes. Production already satisfies the row through listener/use-case idempotency. | Close GP-025 as `Covered`/accepted with tests-only Flutter app proof and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-025 owns duplicate live PubSub delivery handling at the Flutter app layer. The same live event/message id may arrive twice from the Go bridge; the app must leave one visible message row/bubble and avoid duplicate notification/state emissions.

Out of scope: live-plus-inbox replay dedupe (GP-026), deterministic ordering (GP-027), high-volume delivery stress (GP-028), Go raw receive behavior, and durable inbox repair.

## Execution Contract

1. Convert the existing live duplicate listener proof into exact GP-025 row-owned test evidence.
2. Prove two live events with the same `messageId` leave one saved repository row.
3. Prove the listener emits one `groupMessageStream` item, preserving the first trusted payload rather than replacing it with conflicting duplicate metadata.
4. Prove local notification/unread state remains single-entry for the duplicate live delivery.
5. Run the lower-layer `handleIncomingGroupMessage` message-id dedupe selector as adjacent proof.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-025 listener proof | `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GP-025'` |
| Adjacent app-layer message-id dedupe proof | `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-023 closure artifacts. GP-025 scope is limited to the row-owned listener test label, this plan, and closure documentation updates unless focused tests expose a production gap.

## Execution Progress

| Time | Step | Evidence |
|---|---|---|
| 2026-05-13 02:20:00 CEST | Made live duplicate proof row-owned | Renamed `test/features/groups/application/group_message_listener_test.dart` test to `GP-025 LP013 duplicate PubSub delivery preserves first row and notification state`. |
| 2026-05-13 02:27:00 CEST | Production assessment | No production code change was required; `handleIncomingGroupMessage` dedupes non-placeholder existing messages by `messageId` and returns `null`, and `GroupMessageListener` emits only non-null persisted results. |

## Gate Evidence

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'GP-025'` | Passed: `00:00 +1: All tests passed!`. |
| `flutter test --no-pub test/features/groups/application/handle_incoming_group_message_use_case_test.dart --plain-name 'deduplicates by messageId'` | Passed: `00:00 +1: All tests passed!`. |
| `dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart` | Passed after formatting the renamed test. |
| `git diff --check` | Passed for the GP-025 scoped files. |

Environment note: an initial parallel adjacent Flutter invocation failed on the Flutter startup/native-assets lock. The serial rerun above passed and is the accepted gate evidence.

## Closure Bar

- Source row GP-025 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 119, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-025 ownership and does not mask a repo-owned blocker.

## Final Verdict

Verdict: accepted/closed.

GP-025 is covered by exact Flutter app-layer proof. Duplicate live bridge events with the same message id produce one persisted row, one UI stream emission, and one notification while preserving the first trusted payload; no Go, Dart production, durable inbox, or UI code needed to change.
