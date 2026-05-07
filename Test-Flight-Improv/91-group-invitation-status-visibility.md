## 1. Title and Type

- Title: Group Invitation Status Visibility
- Issue type: feature-improvement
- Output doc path: `Test-Flight-Improv/91-group-invitation-status-visibility.md`

## 2. Problem Statement

Group creators need to understand what happened to each invitation after they create a group or add members, especially when the network is unstable.

Today, User A can create a group, see the group and invited members locally, and still receive a failure or warning related to group creation or invite delivery. After the transient snackbar disappears, opening the Group Info `i` screen shows the member list but does not tell User A whether each invite was sent, stored for later delivery, failed, blocked by missing key material, or already accepted through a join event.

From the user's perspective, this creates a trust gap: the app shows the group and members, but User A cannot tell whether invited people actually received invitations or whether User A should manually send them again.

## 3. Impact Analysis

- Affected users: group creators and admins who create groups or add members while direct peer delivery, inbox fallback, secure-key availability, or membership sync is degraded.
- Trigger moments: new group creation with selected members, adding members from Group Info, app/network failure while invite delivery is in progress, and later reopening Group Info after the snackbar is gone.
- Severity: medium to high for group onboarding trust. The group may look created locally while invitation delivery remains ambiguous.
- Frequency: repo evidence shows tested paths for direct invite failure, missing secure keys, no group key, and create/add flows that can still add members locally.
- Confusion cost: users must guess whether to wait, ask invitees out of band, or try sending again without knowing who needs attention.
- Regression risk: existing group creation and add-member flows intentionally keep local group/member state even when invite delivery degrades, so any acceptance criteria must preserve that behavior.

## 4. Current State

- `lib/features/groups/application/send_group_invite_use_case.dart`
  - `SendGroupInviteResult` currently reports `success`, `nodeNotRunning`, `encryptionRequired`, `invalidPayload`, and `sendFailed`.
  - `GroupInviteBatchResult` records per-recipient attempts and can describe failures for transient messages.
  - Direct delivery success and inbox fallback success both return `success`, while failed delivery can be summarized as a failure label.
- `lib/features/groups/application/create_group_with_members_use_case.dart`
  - `CreateGroupWithMembersResult` carries `inviteBatchResult`, missing-key flags, membership sync rollback, and publish-failure warnings.
  - `buildCreateWarningMessage()` can produce copy like "Group created, but ..." when invites or membership setup degrade.
  - The result is returned to the create UI, but repo evidence does not show a later member-list status for individual invitees.
- `lib/features/groups/presentation/screens/create_group_picker_wired.dart`
  - On create success with warning, it navigates to the group conversation and shows a snackbar with the warning.
  - On create exception, it shows localized `group_create_failed`, which tests assert as "Failed to create group".
- `lib/features/groups/presentation/screens/contact_picker_wired.dart`
  - `ContactPickerInviteResult` has transient invite warning data and completion copy such as "Member invited" or "invite issues: ...".
  - Add-member flow can still add members locally when invite delivery fails or when no group key is available.
- `lib/features/groups/presentation/screens/group_info_wired.dart`
  - Group Info loads group data, members, security state, mute state, and admin actions.
  - Add-member completion currently refreshes Group Info and shows a snackbar derived from the transient invite result.
- `lib/features/groups/presentation/screens/group_info_screen.dart`
  - The member section renders the `Members` heading, optional Add Member button, and one row per member.
- `lib/features/groups/presentation/widgets/group_member_row.dart`
  - Member rows show avatar, display name, role badge, identity-change warning, and admin role/remove controls.
  - The row does not currently expose invite delivery status or a resend-needed state.
- `lib/features/groups/application/group_message_listener.dart`
  - Existing `member_joined` system messages produce a durable join timeline event.
  - The current Group Info member list does not appear to use that join observation to clarify invitation status.
- Existing tests partially cover the current behavior:
  - `test/features/groups/application/create_group_with_members_use_case_test.dart` covers local success when P2P invite fails and explicit missing secure-key invite degradation.
  - `test/features/groups/presentation/create_group_picker_wired_test.dart` covers "Failed to create group" and warning snackbar cases.
  - `test/features/groups/presentation/contact_picker_wired_test.dart` covers failed invite warning copy, no-key invite skips, and local member addition despite missing group key.
  - `test/features/groups/presentation/group_info_screen_test.dart` and `test/features/groups/presentation/group_info_wired_test.dart` cover member-list and Group Info behavior, but repo evidence did not show invite-status visibility.
  - `test/features/groups/application/group_message_listener_test.dart` covers `member_joined` timeline behavior, but not Group Info invite-status visibility.

## 5. Scope Clarification

- In scope:
  - User-visible clarity on the Group Info `i` screen for each invited member after group creation or add-member flows.
  - Distinguishing observable invite outcomes that matter to the creator: sent, stored/queued for delivery, needs resend, cannot be sent, joined, and unknown/no recorded attempt.
  - Mixed-outcome group creation where some invitees are sent successfully and others fail.
  - Mixed-outcome add-member flow from Group Info.
  - A persistent user-visible answer after snackbar copy is gone and after the user reopens the group later.
  - A clear indication when the creator should manually send an invitation again.
  - Acceptance evidence that the creator does not mistake local member presence for confirmed invite delivery.
- Non-goals:
  - No claim that a sent or queued invite means the recipient accepted it.
  - No requirement for a protocol-level invite acknowledgment or delivery receipt.
  - No group invite wire-format change is claimed by this spec.
  - No requirement that non-updated recipient apps understand any new creator-side status.
  - No change to group membership policy, admin permissions, key exchange rules, or invite authenticity rules.
  - No broad redesign of Group Info, group creation, or group onboarding.
  - No final decision in this spec about exact badge copy, iconography, storage shape, or control placement.
- Accepted ambiguities for the later implementation pass:
  - The final wording for each status can be decided later, as long as it is understandable and does not imply acceptance before a join is observed.
  - The later pass can decide whether manual resend is shown as a row action, contextual action, or another discoverable Group Info affordance.
  - The later pass can decide how long invite status should remain visible for legacy or already-joined members, as long as `unknown` does not look like failure.

## 6. Test Cases

Happy path:

- Given User A creates a group with selected members and invitations are sent, when User A opens the Group Info `i` screen, then each invited member has a clear status indicating the invite attempt was sent.
- Given direct invite delivery is unavailable but the app can store the invite for later delivery, when User A opens Group Info, then the affected member is shown as waiting/queued rather than as fully joined or needing immediate resend.
- Given an invited member later joins through the existing group flow, when User A opens Group Info, then that member is shown as joined rather than merely invited.
- Given User A adds a member from Group Info and the invite succeeds, when the add-member flow returns to Group Info, then the new member row communicates the successful invite attempt after the snackbar disappears.
- Given multiple selected invitees have different outcomes, when User A opens Group Info, then each member row communicates that member's own outcome instead of showing one generic group-level warning.

Edge cases:

- Given group creation shows "Failed to create group" or a warning while the group still appears locally, when User A later opens the created group's Group Info, then the member list resolves the invite uncertainty instead of leaving all members looking equivalent.
- Given direct delivery and fallback delivery both fail for an invitee, when User A opens Group Info, then that member is visibly marked as needing resend.
- Given an invite cannot be sent because the recipient lacks required secure key material, when User A opens Group Info, then the member is not shown as sent or joined.
- Given the group has no current key at invite time, when User A opens Group Info, then locally added members do not look as if their invites were successfully sent.
- Given the app is closed and reopened after group creation with invite degradation, when User A opens Group Info again, then the same invite uncertainty/resend-needed information is still available.
- Given a legacy group or member has no recorded invite attempt information, when User A opens Group Info, then the member is shown with an unknown or neutral state rather than a false failure.
- Given User A manually sends again for a member marked as needing resend, when Group Info refreshes, then the row no longer leaves User A uncertain about whether the resend attempt happened.
- Given a member joins before User A reopens Group Info, when User A views the member list, then the joined state takes precedence over an older failed or queued invite-attempt state.
- Given User A is not an admin, when viewing Group Info, then invite status remains understandable without exposing admin-only member-management actions.

Regressions to preserve:

- Group creation with invite delivery degradation can still leave the group and locally added members visible when that is the current tested behavior.
- Add-member flow can still add members locally even when invite delivery fails or the group key is missing, matching current covered behavior.
- Existing group invite payload authenticity, invite freshness, membership limits, and selected-member-only fanout behavior remain observable.
- Existing `member_joined` timeline behavior remains observable.
- Existing Group Info role badges, identity warnings, add-member button, admin role controls, remove-member controls, mute state, and dissolved-group behavior remain observable.
- A sent or queued invite must not be presented as accepted until the app observes an actual join.
- Older or non-updated apps are not required to display or interpret the creator-side invite-status visibility.

Preservation/regression case:

- If a group is created during network failure, the app must not regress into hiding the local group or members solely to avoid invite-status ambiguity; instead, the user-visible member list must make the invitation uncertainty explicit.

Existing coverage and gaps:

- Existing unit and widget coverage partially proves group invite fanout, invite failure warnings, missing-key warnings, local member persistence, and Group Info member rendering.
- Missing acceptance evidence: no current test found proves invite-delivery outcome is visible on Group Info after navigation.
- Missing acceptance evidence: no current test found proves invite-delivery outcome survives app restart or later reopening.
- Missing acceptance evidence: no current test found proves mixed per-member invite outcomes are visible after a multi-member create/add flow.
- Missing acceptance evidence: no current test found proves a resend-needed member can be identified from the Group Info member list.
- Missing acceptance evidence: no current test found proves `member_joined` changes the Group Info interpretation from invited/queued/failed to joined.
- Required acceptance evidence layers:
  - unit: deterministic status wording and state distinctions where they affect what the user sees.
  - integration: create-group and add-member journeys across invite outcome, stored group/member state, and Group Info visibility.
  - smoke: group invitation journey remains understandable after transient network failure and does not break existing group creation or add-member flows.
