# GI-032 Session Plan: History Repair Head Mismatch Rejection

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-032`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:05:00 CEST | Controller | Source matrix GI-032 row; breakdown row 149; `drain_group_offline_inbox_use_case.dart::_validateHistoryRepairResult`; GI-031 range-hash proof; existing PREREQ repair tests | The source row is `Open` and the breakdown marks GI-032 `needs_code_and_tests` / `implementation-ready`. Production already rejects repair results whose returned `headMessageId` differs from the detected gap `expectedHeadMessageId` before applying repaired messages. Existing tests did not have an exact row-owned all-mismatch failure/no-render proof for the head metadata. | Add exact row-owned Flutter application proof that a wrong repair head id is rejected, no untrusted message is persisted, and the repair closes failed with `head_mismatch`. |

## Scope

GI-032 owns app-layer rejection of repaired history data when the returned `headMessageId` does not match the detected gap integrity metadata.

Out of scope: repair range-hash rejection (GI-031), Go repair request shape, default limit behavior, required request fields, unauthorized source selection, replay signature validity, and multi-source fallback success.

## Execution Contract

1. Inspect the existing app repair validation path and adjacent history-gap tests.
2. Add a row-named Flutter test that creates a valid signed repair message whose range hash matches the detected gap but whose returned `headMessageId` differs.
3. Drain the offline inbox with a repair response from an authorized source.
4. Assert the untrusted message is not rendered/persisted.
5. Assert the gap repair is failed with `head_mismatch`, no repaired message ids, and the attempted source recorded.
6. Run focused GI-032 and adjacent history repair regression gates, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-032 app proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-032'` |
| Adjacent range-hash proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'` |
| Adjacent repair success proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` |
| Metadata preservation proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-032 scope is limited to the row-owned Flutter app test, this plan, source matrix row GI-032, and breakdown closure documentation updates unless focused gates expose a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 05:05:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-032 repair head mismatch is rejected without rendering`. The test saves a valid replay key, authorizes `peer-good` as a repair source, returns a signed repair message whose computed and relay-supplied range hash match the detected gap but whose `headMessageId` is `wrong-head`, drains the inbox, and asserts `gi032-rejected` is absent, the persisted repair is `failed`, `failureReason == 'head_mismatch'`, `repairedMessageIds` is empty, and attempted sources are `['peer-good']`. | Covered the row-owned app rejection/no-render contract with exact Flutter proof; no production code change was required because existing `_validateHistoryRepairResult` already rejects head mismatches before applying repaired messages. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-032'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` | Passed (`+1`). |
| `dart format test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed; formatted one test file. |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed after formatting. |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-032 is covered by exact tests-only Flutter app evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. The original code-and-test disposition closes as an accepted difference because current production already rejects mismatched repair head ids before application. Residual-only none for GI-032; continue to GI-033, the next unresolved P0 row in session order.

## Closure Bar

- Source row GI-032 must be updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 149, row disposition, session ledger, ordered row, session closure ledger, and closure progress must be updated to `covered/accepted`.
- The original code-and-test disposition can close as tests-only only if executable evidence proves current production already rejects head id mismatches before application.
- No `accepted_with_explicit_follow_up` may be used for this row-owned gap.
