# GP-026 Session Plan: Live Plus Inbox Duplicate Dedupe

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GP-026`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 02:34:00 CEST | Controller | Source matrix GP-026 row; breakdown row 120; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; `lib/features/groups/application/handle_incoming_group_message_use_case.dart`; existing `test/features/groups/integration/group_resume_recovery_test.dart` live-plus-inbox dedupe proof; existing `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` duplicate replay enrichment proof | The source row remains `Open`, but existing production already uses message-id idempotency during inbox drain and re-derives receipt/metadata from the stored row when `handleIncomingGroupMessage` dedupes. Existing tests prove no duplicate row after live plus inbox replay and prove replay can enrich missing quote/media metadata exactly once, but neither is labeled as GP-026 row-owned evidence. | Make the existing live-plus-inbox and enrichment proofs exact GP-026 evidence, run focused gates, then close source/breakdown if they pass. No production code change is expected. |
| 2026-05-13 02:41:00 CEST | Controller | Renamed row-owned resume-recovery and offline-drain tests, focused GP-026 gate output, dart format, and `git diff --check` | The exact row-owned live-plus-inbox duplicate and metadata-enrichment proofs pass. Existing production already satisfies GP-026. | Close GP-026 as `Covered`/accepted with tests-only Flutter app proof and continue from GI-031, the next unresolved P0 row. |

## Scope

GP-026 owns the Flutter app path where a message is already visible from live PubSub and then arrives again from durable group inbox replay with the same `messageId`. The app must keep one visible message and may merge replay metadata without creating a duplicate.

Out of scope: duplicate live-only delivery (GP-025), timeline ordering (GP-027), burst/stress delivery (GP-028), Go raw PubSub fanout, and relay-server storage behavior.

## Execution Contract

1. Convert the existing resume-recovery live-plus-inbox duplicate proof into exact GP-026 evidence.
2. Convert the existing offline-drain duplicate replay enrichment proof into exact GP-026 evidence.
3. Prove live then inbox replay leaves one incoming message with the original trusted content, not a duplicate or tampered overwrite.
4. Prove replay enrichment adds missing quote/media metadata exactly once while preserving one stored message row.
5. Run focused integration/application gates plus formatter and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GP-026 resume-recovery proof | `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GP-026'` |
| Focused GP-026 offline-drain enrichment proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` and `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remains dirty with prior rollout changes and GP-025 closure artifacts. GP-026 scope is limited to row-owned test labels, this plan, and closure documentation updates unless focused tests expose a production gap.

## Execution Progress

| Time | Step | Evidence |
|---|---|---|
| 2026-05-13 02:35:00 CEST | Made live-plus-inbox proofs row-owned | Renamed the resume-recovery test to `GP-026 same message is not duplicated if both pubsub and group inbox deliver it` and the offline-drain test to `GP-026 GMAR-004 duplicate live plus inbox replay enriches video and voice media once`. |
| 2026-05-13 02:41:00 CEST | Production assessment | No production code change was required; inbox drain already routes duplicate message ids through the idempotent incoming-message handler and reuses the stored row for receipt/metadata work when a replay dedupes. |

## Gate Evidence

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GP-026'` | Passed: `00:00 +1: All tests passed!`. |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026'` | Passed: `00:00 +1: All tests passed!`. |
| `dart format --set-exit-if-changed test/features/groups/integration/group_resume_recovery_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed. |
| `git diff --check` | Passed for the GP-026 scoped files. |

## Closure Bar

- Source row GP-026 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 120, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- No `accepted_with_explicit_follow_up` is used for row-owned gaps.
- Residual work, if any, is outside GP-026 ownership and does not mask a repo-owned blocker.

## Final Verdict

Verdict: accepted/closed.

GP-026 is covered by exact Flutter app-layer proof. Live delivery followed by a signed inbox replay with the same message id leaves one visible message, prevents tampered replay overwrite, and can enrich missing quote/media metadata exactly once; no production code needed to change.
