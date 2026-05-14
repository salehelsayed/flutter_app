# GI-026 Session Plan: History Gap Metadata Preservation

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-026`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:40:00 CEST | Controller | Source matrix GI-026 row; breakdown row 145; `lib/core/bridge/bridge_group_helpers.dart`; `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`; existing bridge parser and PREREQ history-gap repair tests | The source row remained `Open` and the breakdown marked GI-026 `needs_tests_only` / `implementation-ready`. Production already parses valid `historyGaps` from cursor responses into `GroupInboxHistoryGap`, persists detected stubs before cursor commit, and passes the same gap object into repair orchestration. Existing tests covered pieces, but no exact GI-026 row-owned proof asserted the app repair layer receives gap id, boundaries, expected hash/head, and source candidates unchanged. | Close as tests-only with exact Flutter app proof. Add `GI-026 history gap metadata is preserved to app repair layer`, run adjacent parser/repair invariants, update source/breakdown evidence to `Covered`/`accepted`, and leave production code unchanged. |

## Scope

GI-026 owns Flutter app preservation of relay-provided `historyGaps` metadata from cursor inbox retrieval into the repair repository and history-repair request orchestration.

Out of scope: Go relay gap detection, repair range validation/hashing rows GI-027/GI-029/GI-031/GI-032, simulator/device proof, or changing bridge schema.

## Execution Contract

1. Inspect cursor history-gap parsing and offline-drain repair orchestration.
2. Add an exact row-owned Flutter app regression in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`.
3. Return a cursor page with one complete `historyGaps` entry carrying non-default gap id, before/after boundaries, expected hash, expected head id, and ordered candidate sources.
4. Use a custom `requestHistoryRepairRange` callback to capture the exact `GroupInboxHistoryGap` delivered to repair orchestration.
5. Assert every row-owned field and source-candidate order are preserved in the callback and persisted repair record.
6. Return a valid repaired signed replay envelope so the repair completes, proving the captured metadata is usable by the app repair layer.
7. Run focused GI-026, adjacent bridge parser and history-gap repair/invariant tests, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-026 app repair-layer proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` |
| Bridge parser proof | `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'parses valid history gap metadata from cursor response'` |
| First authorized repair proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` |
| Unauthorized/hash fallback proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` |
| Replay application proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows'` |
| Cursor-commit invariant proof | `flutter test --no-pub test/features/groups/application/drain_followup_invariants_test.dart --plain-name 'detected history gaps are persisted before the cursor commit so they survive a Phase 2 transaction failure'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-026 scope is limited to the exact row-owned test, this plan, source matrix row GI-026, and breakdown closure documentation updates.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:40:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-026 history gap metadata is preserved to app repair layer`. The test captures the `GroupInboxHistoryGap` passed into `requestHistoryRepairRange`, asserts `groupId`, `gapId`, missing-before/after boundaries, `expectedRangeHash`, `expectedHeadMessageId`, and ordered `candidateSourcePeerIds`, then verifies the persisted repair record stores the same values and completes with the repaired message id. | Covered the row-owned app repair-layer metadata preservation contract with exact executable proof; no production code change was required. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` | Passed (`+1`). |
| `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'parses valid history gap metadata from cursor response'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR applies repaired envelopes through replay handling without duplicate or out-of-order rows'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_followup_invariants_test.dart --plain-name 'detected history gaps are persisted before the cursor commit so they survive a Phase 2 transaction failure'` | Passed (`+1`). |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed (`0 changed`). |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-026 is covered by exact tests-only Flutter app and bridge evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. Residual-only none for GI-026; continue to GI-031, the next unresolved P0 row.

## Closure Bar

- Source row GI-026 is updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 145, row disposition, session ledger, ordered row, session closure ledger, and closure progress are updated to `covered/accepted`.
- The original `needs_tests_only` disposition remains tests-only; production already satisfied the row-owned contract once exact proof was added.
- No `accepted_with_explicit_follow_up` is used for this row-owned gap.
