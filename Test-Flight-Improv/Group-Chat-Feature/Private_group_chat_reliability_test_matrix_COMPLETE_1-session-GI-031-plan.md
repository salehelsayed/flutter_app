# GI-031 Session Plan: History Repair Range Hash Mismatch Rejection

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-031`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 04:58:00 CEST | Controller | Source matrix GI-031 row; breakdown row 148; `drain_group_offline_inbox_use_case.dart::_validateHistoryRepairResult`; existing PREREQ history repair tests | The source row is `Open` and the breakdown marks GI-031 `needs_code_and_tests` / `implementation-ready`. Production already rejects any repair result whose relay-supplied `rangeHash` or computed message range hash differs from the detected gap `expectedRangeHash` before applying repaired messages. Existing tests cover fallback after one bad source but not the row-owned all-mismatch failure/no-render contract. | Add exact row-owned Flutter application proof that a mismatched repair range hash is rejected, no untrusted message is persisted, and the repair closes failed with `range_hash_mismatch`. |

## Scope

GI-031 owns app-layer rejection of repaired history data when the returned range hash does not match the detected gap integrity metadata.

Out of scope: Go repair request shape (GI-029), repair default limits (GI-028), required request fields (GI-027), head mismatch rejection (GI-032), unauthorized source selection, replay signature validity, and multi-source fallback success.

## Execution Contract

1. Inspect the existing app repair validation path and adjacent history-gap tests.
2. Add a row-named Flutter test that creates a valid signed repair message with a range hash that differs from the persisted gap `expectedRangeHash`.
3. Drain the offline inbox with a repair response from an authorized source.
4. Assert the untrusted message is not rendered/persisted.
5. Assert the gap repair is failed with `range_hash_mismatch`, no repaired message ids, and the attempted source recorded.
6. Run focused GI-031 and adjacent history repair regression gates, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-031 app proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'` |
| Adjacent hash fallback proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` |
| Adjacent repair success proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` |
| Metadata preservation proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-031 scope is limited to the row-owned Flutter app test, this plan, source matrix row GI-031, and breakdown closure documentation updates unless focused gates expose a production defect.

## Execution Evidence

| Time | Actor | Evidence | Result |
|---|---|---|---|
| 2026-05-13 04:58:00 CEST | Executor | Added `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart::GI-031 repair range hash mismatch is rejected without rendering`. The test saves a valid replay key, authorizes `peer-good` as a repair source, computes one expected range hash and a different signed repair-message hash, returns the mismatched hash from `group:historyRepairRange`, drains the inbox, and asserts `gi031-rejected` is absent, the persisted repair is `failed`, `failureReason == 'range_hash_mismatch'`, `repairedMessageIds` is empty, and attempted sources are `['peer-good']`. | Covered the row-owned app rejection/no-render contract with exact Flutter proof; no production code change was required because existing `_validateHistoryRepairResult` already rejects mismatched relay-supplied and computed range hashes before applying repaired messages. |

## Verification

| Gate | Result |
|---|---|
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR detects a history gap and repairs it from the first authorized matching source'` | Passed (`+1`). |
| `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` | Passed (`+1`). |
| `dart format test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed; formatted one test file. |
| `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | Passed after formatting. |
| `git diff --check` | Passed. |

## Final Verdict

Accepted/closed. GI-031 is covered by exact tests-only Flutter app evidence, the source matrix is `Covered`, and no `accepted_with_explicit_follow_up` is used. The original code-and-test disposition closes as an accepted difference because current production already rejects mismatched repair range hashes before application. Residual-only none for GI-031; continue to GI-032, the next unresolved P0 row in session order.

## Closure Bar

- Source row GI-031 must be updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 148, row disposition, session ledger, ordered row, session closure ledger, and closure progress must be updated to `covered/accepted`.
- The original code-and-test disposition can close as tests-only only if executable evidence proves current production already rejects mismatched range hashes before application.
- No `accepted_with_explicit_follow_up` may be used for this row-owned gap.
