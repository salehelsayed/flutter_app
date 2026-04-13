# Session ID-001 Plan - Creator identity resolves to username

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `ID-001` only: creator/admin identity should resolve to a
  username instead of falling back to raw peer ID when a username exists.
- Fix the authoritative data path first, not the render widgets: the creator's
  persisted self-member row must keep the username from the create flow.
- Prove the row at three levels only:
  - the create use case stores the creator username on the admin membership row
  - the create-with-members flow exports that same username into persisted
    `groupConfig`
  - the member-list UI renders the creator as `Admin` for another member rather
    than falling back to `peer-admin`
- Update only the row truth in:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

### closure bar

- The real create path persists the creator/admin member with a username when
  one exists.
- The same create path propagates that username into the generated
  `group:updateConfig` payload so downstream viewers receive authoritative
  human-readable identity.
- A user-facing member-list test proves another member sees `Admin` rather than
  a raw creator peer ID.
- Required direct tests pass.
- The source matrix row can be updated from `Open` to `Covered` with concrete
  file-and-test evidence tied to `ID-001`.

### source of truth

- Active breakdown contract:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- Repo coverage inventory:
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Gate definitions:
  `Test-Flight-Improv/test-gate-definitions.md`
- Verified seam files:
  - `lib/features/groups/application/create_group_use_case.dart`
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
  - `test/features/groups/application/create_group_use_case_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`

### exact problem statement

- The current repo already prefers `member.username` in `GroupMemberRow`, but
  the creator's initial self-member row is persisted with `username: null` by
  `createGroup(...)`.
- That leaves downstream member-list and admin-badge surfaces with no
  authoritative username for the creator, so they fall back to a truncated peer
  ID.
- This session must fix the persistence seam and add direct proof that the UI
  now receives and renders the creator username.

### files and repos to inspect next

- Primary implementation seam:
  - `lib/features/groups/application/create_group_use_case.dart`
- Upstream caller:
  - `lib/features/groups/application/create_group_with_members_use_case.dart`
- UI fallback seam:
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
- Primary proof targets:
  - `test/features/groups/application/create_group_use_case_test.dart`
  - `test/features/groups/application/create_group_with_members_use_case_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`

### regression/tests to add first

- Add a use-case regression proving `createGroup(...)` stores the creator's
  username on the admin member row.
- Add a create-with-members regression proving the generated `groupConfig`
  carries the creator username for `peer-admin`.
- Add a widget regression that uses the real create path, opens `GroupInfoWired`
  from another member's perspective, and verifies the creator renders as
  `Admin`, not `peer-admin`.

### step-by-step implementation plan

1. Extend `createGroup(...)` with an optional `creatorUsername` and persist it
   on the self-member row.
2. Pass `identity.username` from `createGroupWithMembers(...)`.
3. Add the row-owned direct regressions in the application and presentation
   suites.
4. Run only the exact direct test slice for this row.
5. Update the matrix row, inventory evidence, and breakdown ledger only after
   the proof is green.

### risks and edge cases

- Do not broaden into avatar-resolution or non-friend fallback rows (`ID-002`,
  `ID-010`).
- Do not rewrite render widgets if the only missing contract is authoritative
  source data.
- Do not accept the session from unit-only proof; keep one user-facing member
  list assertion in scope.

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/application/create_group_use_case_test.dart`
- `flutter test --no-pub test/features/groups/application/create_group_with_members_use_case_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`

### done criteria

- `ID-001` has exact row-owned automated proof in repo-local tests.
- The fix is limited to the creator identity persistence seam and its immediate
  caller.
- The direct proof suite passes.
- The source matrix row and breakdown can truthfully mark `ID-001` resolved.

### scope guard

- Non-goals:
  - broader avatar parity
  - non-friend onboarding
  - conversation identity styling
  - role-transfer UX
- Overengineering for this session would be broad profile-resolution work or
  large member-list refactors unrelated to the missing creator username.
