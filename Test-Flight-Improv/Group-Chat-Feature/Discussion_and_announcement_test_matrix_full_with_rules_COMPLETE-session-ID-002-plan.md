# Session ID-002 Plan - Identity and avatar consistency across surfaces

## Final verdict

`implementation-ready`

## Final plan

### real scope

- Resolve source row `ID-002` only: member-list and conversation surfaces
  should show consistent participant identity, including avatars, for current
  members.
- Keep the change row-scoped. The specific repo gap is that group conversation
  rows already use `UserAvatar`, while `GroupMemberRow` still renders a separate
  initial-circle placeholder.
- Align the member-list surface with the existing conversation surface by
  reusing the shared avatar component instead of inventing a third identity
  style.
- Update only the row truth in:
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
  - `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
  - `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`

### closure bar

- Group member rows use the same shared avatar widget family as conversation
  rows.
- Direct tests prove member-list identity uses `UserAvatar`.
- Direct tests also prove conversation rows continue to render sender identity
  with `UserAvatar`.
- Required direct tests pass.
- The source matrix row can be updated from `Partial` to `Covered` with
  file-and-test evidence tied to `ID-002`.

### source of truth

- Active breakdown contract:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE-session-breakdown.md`
- Source matrix:
  `Test-Flight-Improv/Group-Chat-Feature/Discussion_and_announcement_test_matrix_full_with_rules_COMPLETE.md`
- Repo coverage inventory:
  `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- Verified seam files:
  - `lib/features/groups/presentation/widgets/group_member_row.dart`
  - `lib/features/conversation/presentation/widgets/letter_card.dart`
  - `test/features/groups/presentation/group_info_screen_test.dart`
  - `test/features/groups/presentation/group_conversation_screen_test.dart`

### exact problem statement

- Current repo evidence already shows conversation rows render names with the
  shared `UserAvatar` component via `LetterCard`.
- Member-list rows still use a custom placeholder initial-circle, so the same
  participant can look materially different between group info and
  conversation.
- This session should fix the member-list surface and pin both sides of the
  consistency contract with direct tests.

### regression/tests to add first

- Add a member-list test proving `GroupInfoScreen` renders `UserAvatar` for each
  member row.
- Add a conversation test proving `GroupConversationScreen` renders sender
  identity with `UserAvatar`.

### step-by-step implementation plan

1. Replace the member-row placeholder avatar with the shared `UserAvatar`
   component.
2. Add the row-owned member-list and conversation avatar regressions.
3. Run the exact direct test slice for this row.
4. Update the matrix row, inventory evidence, and breakdown ledger only after
   the proof is green.

### risks and edge cases

- Do not broaden into non-friend onboarding (`ID-004`) or non-friend fallback
  readability (`ID-010`).
- Do not claim full profile-photo parity beyond what `UserAvatar` already owns.
- Keep the change presentation-scoped; this row does not require transport or
  identity-repo work.

### exact tests and gates to run

- `flutter test --no-pub test/features/groups/presentation/group_info_screen_test.dart`
- `flutter test --no-pub test/features/groups/presentation/group_conversation_screen_test.dart`

### done criteria

- `ID-002` has exact row-owned automated proof in repo-local tests.
- Member list and conversation surfaces use the same avatar component family.
- The direct proof suite passes.
- The source matrix row and breakdown can truthfully mark `ID-002` resolved.
