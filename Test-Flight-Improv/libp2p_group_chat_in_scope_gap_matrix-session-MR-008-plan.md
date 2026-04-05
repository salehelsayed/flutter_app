# Session MR-008 Plan - Remove non-member handled cleanly

## Final verdict

`implementation-ready`

Current repo evidence shows `MR-008` is a bounded missing-contract gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `MR-008` as `implementation-ready` with `code changes and tests`
  ownership.
- The repo already proves valid member removal works and that the remove flow
  fans out the expected `member_removed` payload on the success path.
- The remaining row-owned gap is narrower: `remove_group_member_use_case.dart`
  currently treats an already absent peer as a silent remove-plus-config-sync
  no-op, and `GroupInfoWired` currently swallows remove errors instead of
  surfacing a clear user-visible failure.

The smallest safe session is therefore to reject missing members in the remove
use case before any bridge sync starts, add one unit proof for the non-member
error, add one widget proof that a stale remove action shows an error without
emitting `member_removed` side effects, add one membership-smoke proof that a
non-member removal attempt leaves state unchanged, then update the row-owned
docs truthfully.

## Final plan

### real scope

- Close source row `MR-008` only: ensure removing an already absent member
  returns a clear error/no-op outcome and does not emit misleading removal side
  effects.
- Keep the change bounded to:
  - `lib/features/groups/application/remove_group_member_use_case.dart`
  - `lib/features/groups/presentation/screens/group_info_wired.dart`
  - `test/features/groups/application/remove_group_member_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after the
  proof lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- `removeGroupMember()` rejects an already absent peer before repo mutation or
  `group:updateConfig` bridge sync starts.
- The absent-member path leaves membership state unchanged.
- A stale admin remove action surfaces a clear error and emits no
  `group:publish` or `group:inboxStore` removal artifact.
- Direct proof passes, and the named gates below pass or are recorded
  truthfully if an unrelated failure remains outside this row's write scope.
- `MR-008` is updated to `Closed` or `Covered` only after the docs cite the
  landed evidence.

### source of truth

- Governing docs:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`
  - `Test-Flight-Improv/test-gate-definitions.md`
- Current code/tests win over stale prose when they disagree.

### session classification

`implementation-ready`

### exact problem statement

- Valid removal is already implemented and tested.
- What remains open is the already-absent path: there is no explicit
  non-member guard, no asserted error contract, and no caller-level proof that
  the stale remove path suppresses misleading `member_removed` side effects.
- This session should not widen into key rotation redesign, removal notice UX
  redesign, or offline-removal recovery work.

### regression/tests to add first

- Add a unit regression proving `removeGroupMember()` rejects a non-member
  before bridge sync starts and preserves the existing members.
- Add a widget regression proving a stale remove action shows an error without
  sending removal publish/inbox side effects.
- Add a membership-smoke regression proving a non-member removal attempt
  leaves shared member lists unchanged.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on non-member removal
   handling only.
2. Add a bounded missing-member guard to
   `lib/features/groups/application/remove_group_member_use_case.dart`.
3. Surface the remove error in
   `lib/features/groups/presentation/screens/group_info_wired.dart`.
4. Add the unit proof in
   `test/features/groups/application/remove_group_member_use_case_test.dart`.
5. Add the stale-remove caller proof in
   `test/features/groups/presentation/group_info_wired_test.dart`.
6. Add the shared-state smoke proof in
   `test/features/groups/integration/group_membership_smoke_test.dart`.
7. Run the direct suites and named gates below.
8. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Keep the check keyed to `groupId` plus `memberPeerId`; do not reject valid
  removals based only on a stale username.
- Reject before bridge sync; do not allow silent config rewrites for absent
  peers.
- Keep the new UI feedback narrow: show the existing error surface without
  redesigning the remove flow.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` because the
    session changes production membership UI error handling in
    `group_info_wired.dart`

### known-failure interpretation

- If the absent-member path still reaches `group:updateConfig`, the remove flow
  is not cleanly short-circuited.
- If the stale UI remove action still publishes `member_removed` or inbox
  artifacts, the row remains open because the caller contract is still
  misleading.
- If the UI swallows the error without user-visible feedback, the repo still
  lacks the required clear error contract.

### done criteria

- Non-member removal attempts return a clear error before bridge sync.
- Membership state remains unchanged on the absent path.
- The stale-remove widget proof and membership-smoke proof both pass.
- `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart test/features/groups/presentation/group_info_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` passes or is
  recorded truthfully as unrelated drift outside this row's write scope.
- `MR-008` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats non-member removal as an open contract gap.

### scope guard

- Do not redesign valid member removal behavior.
- Do not add new background replay semantics or member-removed message types.
- Do not widen into add-member, admin-transfer, or notification work.

### accepted differences / intentionally out of scope

- Rich localized copy for the remove error remains outside this row; the
  existing snackbar/error surface is enough.
- Cross-device admin conflict resolution beyond the missing-member guard stays
  outside this row.

### dependency impact

- `MR-008` can close independently once absent-member removal is rejected and
  the caller/state proofs land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
