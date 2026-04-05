# Session MR-004 Plan - Add existing member handled cleanly

## Final verdict

`implementation-ready`

Current repo evidence shows `MR-004` is a bounded duplicate-add contract gap:

- `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  classifies `MR-004` as `implementation-ready` with `code changes and tests`
  ownership.
- The repo already has one normal-path guard: `ContactPickerWired` excludes
  current members from the selectable add flow.
- The remaining row-owned gap is narrower: the direct add-member use case still
  upserts an existing peer instead of returning a clear duplicate/no-op error,
  so there is no direct proof that the duplicate path stops before config sync
  and before any `member_added` broadcast could be emitted by the caller.

The smallest safe session is therefore to reject duplicate adds in
`add_group_member_use_case.dart`, add one unit proof for the duplicate error,
add one caller-level stale-selection proof that the picker emits no config sync
or system publish when a selected contact becomes an existing member before
confirm, add one membership-smoke proof that a duplicate re-add attempt leaves
state unchanged, then update the row-owned docs truthfully.

## Final plan

### real scope

- Close source row `MR-004` only: ensure adding an already active member
  returns a clear error/no-op outcome and does not fan out duplicate membership
  side effects.
- Keep the change bounded to:
  - `lib/features/groups/application/add_group_member_use_case.dart`
  - `test/features/groups/application/add_group_member_use_case_test.dart`
  - `test/features/groups/presentation/contact_picker_wired_test.dart`
  - `test/features/groups/integration/group_membership_smoke_test.dart`
- Update only the row-owned closure docs named by the breakdown after the
  proof lands:
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix.md`
  - `Test-Flight-Improv/libp2p_group_chat_in_scope_gap_matrix-session-breakdown.md`
  - `Test-Flight-Improv/11-group-discussion-use-case-audit.md`

### closure bar

- `addGroupMember()` rejects a duplicate peer before repo mutation or bridge
  config sync starts.
- The duplicate path preserves the existing member row instead of silently
  overwriting it.
- A stale UI selection that becomes duplicate before confirm fails cleanly and
  emits no `group:updateConfig` or `group:publish` side effect.
- A duplicate re-add attempt in the membership smoke flow leaves the shared
  member list unchanged.
- Direct proof passes, and the named gate below passes or is recorded
  truthfully if an unrelated failure remains outside this row's write scope.
- `MR-004` is updated to `Closed` or `Covered` only after the docs cite the
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

- Normal UI selection already avoids obvious duplicate adds.
- The bypass path is still wrong: `addGroupMember()` currently saves an
  existing peer again and relies on repository upsert behavior.
- This session should not widen into invite transport redesign, member role
  management, or a larger membership UX rewrite.

### regression/tests to add first

- Add a unit regression proving `addGroupMember()` rejects a duplicate member
  before any bridge sync starts and keeps the original row intact.
- Add a widget regression proving a stale selection that becomes duplicate
  before confirm shows the failure path without emitting config-sync or
  `members_added` publish side effects.
- Add a membership-smoke regression proving a duplicate re-add attempt leaves
  the shared member list unchanged for the existing participants.

### step-by-step implementation plan

1. Preserve unrelated local edits and keep the scope on duplicate-add
   detection only.
2. Add a bounded duplicate-member guard to
   `lib/features/groups/application/add_group_member_use_case.dart`.
3. Update the unit regression in
   `test/features/groups/application/add_group_member_use_case_test.dart`.
4. Add the stale-selection caller proof in
   `test/features/groups/presentation/contact_picker_wired_test.dart`.
5. Add the duplicate re-add smoke proof in
   `test/features/groups/integration/group_membership_smoke_test.dart`.
6. Run the direct suites and named gate below.
7. Update the matrix row, breakdown ledger/notes, and
   `11-group-discussion-use-case-audit.md` only after the proof passes.

### risks and edge cases

- Keep the duplicate check keyed to `groupId` plus `peerId`; do not reject
  legitimate first-time adds for the same username on a different peer.
- Reject before side effects; do not save then roll back when a direct
  existence check is sufficient.
- Do not widen the meaning of "cleanly handled" into new UI copy or a full
  no-op success contract if the landed behavior is an explicit error.

### exact tests and gates to run

- Direct tests:
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
- Named gates:
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
  - `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` only if the
    session ends up changing production membership UI behavior instead of the
    use case plus proofs

### known-failure interpretation

- If the duplicate attempt still reaches `group:updateConfig`, the add path is
  not cleanly short-circuited.
- If the original member row is overwritten by the duplicate attempt, the row
  remains open because the behavior is still silent upsert, not clear reject.
- If the picker publishes a `members_added` system message after the duplicate
  becomes stale, the caller-level suppression proof is missing and the row
  remains open.

### done criteria

- Duplicate add attempts return a clear error before bridge sync.
- Existing member rows remain unchanged after the duplicate attempt.
- The stale-selection caller proof and the membership-smoke proof both pass.
- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/presentation/contact_picker_wired_test.dart test/features/groups/integration/group_membership_smoke_test.dart`
  passes.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` passes.
- `MR-004` is updated in the source matrix and breakdown with concrete
  file-and-test evidence, and `11-group-discussion-use-case-audit.md` no
  longer treats duplicate member adds as an open contract gap.

### scope guard

- Do not redesign the batch invite flow.
- Do not add new system-message types for duplicate outcomes.
- Do not widen into removal, offline replay, or role-transfer work.

### accepted differences / intentionally out of scope

- Rich end-user copy beyond the existing generic invite failure path remains
  outside this row.
- Cross-device concurrent admin conflict resolution beyond the duplicate check
  stays outside this row.

### dependency impact

- `MR-004` can close independently once duplicate adds are rejected and the
  caller/state proofs land.
- `CLOSURE-001` depends on this row being truthfully updated after execution.
