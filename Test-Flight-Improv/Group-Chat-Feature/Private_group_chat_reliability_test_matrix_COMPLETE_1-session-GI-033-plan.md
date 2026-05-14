# GI-033 Session Plan: History Repair Source Authorization

## Status

Status: accepted/closed

## Source Row

Source matrix row: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1.md` row `GI-033`

## Gap-Closure Reconciliation

| Time | Actor | Inputs Compared | Finding | Action |
|---|---|---|---|---|
| 2026-05-13 05:12:00 CEST | Controller | Source matrix GI-033 row; breakdown row 150; `drain_group_offline_inbox_use_case.dart::_repairHistoryGapsFromPage`; `GroupRepository.getMembers`/`removeMember` behavior; existing PREREQ repair tests | The source row is `Open` and the breakdown marks GI-033 `needs_repo_evidence` / `evidence-gated`. Production builds authorized repair sources from current `groupRepo.getMembers(groupId)` and records unauthorized candidates before attempting repair. Existing tests cover an unknown source plus a bad active source, but not a row-owned removed-member candidate and exact proof that only the current active source is requested. | Add exact row-owned Flutter application proof that removed and unknown repair candidates are recorded as attempted but never requested, while a current authorized source repairs successfully. |

## Scope

GI-033 owns app-layer repair source authorization for history-gap repair candidates.

Out of scope: range-hash rejection (GI-031), head mismatch rejection (GI-032), Go repair request shape, relay-side source authorization, replay signature validity, and notification/UI behavior.

## Execution Contract

1. Inspect current group membership repository behavior and app repair source selection.
2. Add a row-named Flutter test with removed, unknown, and current active repair candidates.
3. Capture the `requestHistoryRepairRange` callback sources.
4. Assert only the active/current source is requested.
5. Assert removed and unknown sources are recorded as attempted, the good source repairs successfully, and the repaired message renders once.
6. Run focused GI-033 and adjacent history repair regression gates, format, and diff hygiene.

## Required Gates

| Gate | Command |
|---|---|
| Focused GI-033 app proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-033'` |
| Adjacent unauthorized/hash fallback proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` |
| Adjacent range/hash integrity proofs | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'`; `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-032'` |
| Metadata preservation proof | `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` |
| Hygiene | `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`; `git diff --check` |

## Dirty Worktree Snapshot

Captured before execution: worktree remained dirty with prior gap-closure rollout code, tests, and accepted plan artifacts. GI-033 scope is limited to the row-owned Flutter app test, this plan, source matrix row GI-033, and breakdown closure documentation updates unless focused gates expose a production defect.

## Execution Evidence

- Added exact row-owned Flutter app proof in `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`: `GI-033 repair source must be a current authorized member`.
- The test seeds a removed prior member and an unknown peer as earlier repair candidates, leaves only `peer-good` as a current group member, and asserts the repair callback is invoked only for `peer-good`.
- The test proves removed/unknown candidates are recorded in `attemptedSourcePeerIds`, the active source repairs successfully, and the repaired signed message is persisted exactly once.
- No production code changed for GI-033. Existing production in `lib/features/groups/application/drain_group_offline_inbox_use_case.dart::_repairHistoryGapsFromPage` builds authorized repair sources from current `groupRepo.getMembers(groupId)` and records unauthorized candidates without requesting repair data.

## Verification

- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-033'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'PREREQ-HISTORY-GAP-REPAIR rejects unauthorized and hash-mismatched sources then repairs from a later authorized source'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-031'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-032'` passed (`+1`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GI-026'` passed (`+1`).
- `dart format --set-exit-if-changed test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` passed (`0 changed`).
- `git diff --check` passed.

## Final Verdict

Accepted/closed. GI-033 is `Covered` by tests-only Flutter app evidence because existing production already restricts repair requests to current authorized group members. Residual-only: none for GI-033. GI-035 is the next unresolved P0 row in session order; no final program verdict was written.

## Closure Bar

- Source row GI-033 must be updated to `Covered` with concrete file/test/gate evidence.
- Breakdown row 150, row disposition, session ledger, ordered row, session closure ledger, and closure progress must be updated to `covered/accepted`.
- No removed or unknown source may be used to fetch repair data in the accepted row proof.
- No `accepted_with_explicit_follow_up` may be used for this row-owned gap.
