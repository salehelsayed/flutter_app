# 1. Title and Type

- Title: Group membership actions show recovery-safe feedback
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/98-group-membership-recovery-action-feedback.md`

# 2. Problem Statement

Group admins are trying to manage membership while a group is still catching up:
adding members, removing members, and changing member roles.

In some recovery timing windows, membership actions can still surface internal
copy such as `Group recovery is in progress. Try again after resync completes.`
or collapse into a generic failure with no clear waiting state. This leaves the
admin unsure whether the action failed, partially applied, or only needs to wait
until the group finishes updating.

This is the remaining gap after Report 97. Report 97 closed the recovery
feedback bug for group details edits: name, description, and photo. It did not
close the equivalent user-facing feedback contract for membership-control
actions.

# 3. Impact Analysis

- Affected users: group admins who add members, remove members, promote members,
  or demote members while group recovery is active.
- Affected flows:
  - Group Info -> Add Member -> Contact Picker -> invite selected members.
  - Group Info -> Members -> remove a member.
  - Group Info -> Members -> promote or demote a member.
- Trigger pattern: the issue appears when the shared group recovery gate is
  active during a membership-control action.
- Severity: high for trust during group administration. Membership changes are
  privileged actions, and internal recovery/resync language makes the app feel
  inconsistent with the recovered group-details editing behavior.
- Frequency: not measurable from repo evidence alone. Repo code proves add,
  remove, and role-change use cases all reject active recovery windows, so this
  can happen whenever a user acts during that window.
- Confusion cost: the admin may repeat an action, assume membership changed
  when it did not, or believe the group is broken because the snackbar exposes
  internal synchronization language.

# 4. Current State

- `lib/features/groups/application/group_recovery_gate.dart` defines the shared
  active recovery gate and the internal raw message:
  `Group recovery is in progress. Try again after resync completes.`
- `lib/features/groups/application/add_group_member_use_case.dart` rejects add
  member actions while recovery is active and throws the raw recovery
  `StateError`.
- `lib/features/groups/application/remove_group_member_use_case.dart` rejects
  remove member actions while recovery is active and throws the raw recovery
  `StateError`.
- `lib/features/groups/application/update_group_member_role_use_case.dart`
  rejects promote/demote actions while recovery is active and throws the raw
  recovery `StateError`.
- `lib/features/groups/presentation/screens/group_info_wired.dart` shows
  remove-member and role-change `StateError.message` directly in a snackbar.
  That means the raw recovery/resync copy can be user-visible for those
  membership actions.
- `lib/features/groups/presentation/screens/contact_picker_wired.dart` catches
  individual add-member failures, records the error in flow events, and if no
  selected member can be added shows a generic invite failure message. This path
  does not currently provide a recovery-specific waiting state for add-member
  failures.
- `lib/features/groups/presentation/screens/group_info_wired.dart` already uses
  the localized `group_info_dissolved_recovery` snackbar for a dissolved-group
  recovery visibility state, showing adjacent prior art for recovery-aware group
  administration copy that is not raw exception text.
- Repo evidence for active-recovery rejection does not establish that the member
  list or role badges optimistically change before the recovery feedback is
  shown. The fake-success cases below are observable safety criteria, not a
  claim that the current active-recovery path always mutates local UI first.
- `lib/l10n/app_en.arb`, `lib/l10n/app_ar.arb`, and `lib/l10n/app_de.arb`
  contain generic membership failure copy such as invite failed, remove failed,
  and role update failed. Report 97 also added group-details recovery-waiting
  copy for metadata/photo edits, but the membership action surfaces are not
  recorded as covered by that closure.
- `test/features/groups/application/add_group_member_use_case_test.dart`,
  `test/features/groups/application/remove_group_member_use_case_test.dart`, and
  `test/features/groups/application/update_group_member_role_use_case_test.dart`
  cover lower-level recovery rejection for membership mutations.
- Existing direct presentation tests cover many Group Info and Contact Picker
  behaviors, but repo evidence did not show a user-visible regression proving
  that add, remove, promote, or demote actions avoid raw recovery/resync copy
  during active recovery.
- `Test-Flight-Improv/97-group-details-recovery-save-feedback.md` is closed on
  `2026-05-29` and explicitly targets Group Info metadata editing. Its accepted
  closure says the raw internal recovery error may remain in lower-level use
  cases for non-editor callers. That leaves membership-action feedback as a
  separate user-facing gap.

# 5. Scope Clarification

In scope:

- User-visible feedback for membership actions blocked by active group recovery.
- Add-member, remove-member, promote-member, and demote-member flows from the
  existing group administration surfaces.
- Clear waiting or retry-safe copy that does not expose `resync`, `group
  recovery`, or internal exception text.
- Observable behavior when recovery starts before the user acts or while a
  membership action is being attempted.
- Preserving the distinction between recovery-waiting feedback and ordinary
  permission, membership-limit, not-found, or last-admin failures.
- Preserving the existing group details metadata/photo recovery-save behavior
  closed by Report 97.

Non-goals:

- No change to group admin permission policy.
- No change to who can invite whom.
- No change to membership event authorization, stale-event validation, key
  rotation, relay behavior, inbox replay, or recovery mechanics.
- No broad redesign of the Group Info screen, member list, or Contact Picker.
- No requirement to promise an exact remaining wait time.
- No requirement to reopen Report 97's metadata/photo closure.

Accepted ambiguities for later implementation:

- The exact user-facing wording can be chosen later as long as it avoids
  internal recovery/resync language.
- The final UI shape can vary by action surface as long as the observable
  behavior is clear, localized, and consistent enough for admins.
- Multi-select add-member behavior can decide later how to phrase partial
  outcomes, as long as the user is not shown fake success for members that were
  not actually added.
- Whether the current member-management surfaces mutate optimistically or only
  refresh after repository state changes remains an evidence question for the
  later acceptance pass; either way, blocked recovery actions must settle on the
  unchanged visible membership state.

# 6. Test Cases

## Happy Path

- When an admin adds members while no active recovery window exists, the members
  are added or invited according to the existing policy and the user sees the
  existing successful completion feedback.
- When an admin removes a member while no active recovery window exists, the
  member is removed according to the existing policy and the user sees the
  existing successful completion feedback.
- When an admin promotes or demotes a member while no active recovery window
  exists, the role change applies according to the existing policy and the user
  sees the existing successful completion feedback.
- When a membership action is blocked because group recovery is active, the user
  sees clear waiting feedback and does not see raw `resync`, `group recovery`, or
  exception-style text.
- When recovery clears after a blocked membership action, the admin can retry
  the same action without stale UI state implying that the previous blocked
  action already succeeded.
- Required acceptance evidence layer: integration, because the visible outcome
  spans group administration surfaces, recovery-window state, membership
  mutation results, repository state, and user-facing feedback.
- Required broad confidence layer: smoke, because add/remove/role changes are
  central group administration flows and regressions here can affect adjacent
  group membership journeys.

## Edge Cases

- If recovery starts after the admin opens the member-management UI but before
  the action completes, the user does not see the raw recovery/resync snackbar.
- If a multi-select add-member attempt is fully blocked by recovery, the user
  does not see fake success and no selected member appears as added after the UI
  settles solely due to the blocked attempt.
- If a multi-select add-member attempt has a mixed outcome, the visible feedback
  does not imply that every selected member was added when some were blocked or
  failed.
- Whether the member list refreshes from unchanged repository state or recovers
  from a partial local attempt, a recovery-blocked remove-member action leaves
  the member visible as a current member after the UI settles.
- Whether role badges refresh from unchanged repository state or recover from a
  partial local attempt, a recovery-blocked role-change action leaves the member
  on the previous role after the UI settles.
- If a permission failure, membership limit, last-admin boundary, member-not-
  found case, or stale-membership case happens outside active recovery, the user
  still receives the correct non-recovery feedback.
- If routine online maintenance runs but the active recovery gate is not entered,
  membership actions do not show recovery-waiting feedback just because the app
  is doing background continuity work.

## Regressions To Preserve

- Bug regression: add, remove, promote, and demote membership actions must not
  show `Group recovery is in progress. Try again after resync completes.` in any
  user-visible snackbar, dialog, or inline error while blocked by active
  recovery.
- Bug regression: after the UI settles, a recovery-blocked remove-member attempt
  must not leave the UI or local group state looking as if the member was
  removed.
- Bug regression: a recovery-blocked promote or demote attempt must not leave
  the settled UI or local group state looking as if the role changed.
- Bug regression: after the UI settles, a recovery-blocked add-member attempt
  must not leave the UI or local group state looking as if a member was added
  when the action did not actually apply.
- Preservation/regression case: existing successful add-member, remove-member,
  promote, demote, invite, and member-list refresh behavior remains intact when
  recovery is not active.
- Preservation/regression case: existing membership authorization and boundary
  failures remain distinct from recovery-waiting feedback.
- Preservation/regression case: Report 97 group details recovery-save behavior
  remains closed for metadata/photo edits while membership-action feedback is
  handled separately.
