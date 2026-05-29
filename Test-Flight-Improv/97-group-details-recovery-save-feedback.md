# 1. Title and Type

- Title: Group details save feedback during recovery
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/97-group-details-recovery-save-feedback.md`
- Current status: `closed` on `2026-05-29`

# 2. Problem Statement

Group admins are trying to update a group's name, description, and photo after normal membership changes such as admin promotion, admin demotion, and adding a new member.

Today, an admin can hit a recovery timing window where the app shows an internal error: "Group recovery is in progress. Try again after resync completes." In the reported flow, one edit also appeared to change the photo only on the editing user's device, while other members did not receive the same name, description, or photo update.

This is a user-facing bug because admins should not need to understand "resync" or "group recovery." If the group is still updating, the app should make that waiting state clear before the user presses Save. The preferred user experience is a disabled Save button with simple copy such as "Group is updating. Please wait a moment." and a live elapsed timer such as "Syncing for 4 seconds..."

This spec treats group resync as event-driven catch-up plus routine online maintenance. It can be triggered by startup, app resume, reconnect, explicit recovery signals, group notification drains, and a 30-second online continuity sweep. The UX requirement is not to block Save whenever background maintenance exists. Save should be blocked only during a real active recovery/update window that makes a group details save unsafe.

# 3. Impact Analysis

- Affected users: group admins editing group details after admin role changes, member additions, or recovery from missed group events.
- Affected flow: Group Info -> Edit Group Details -> change group name, description, or photo -> Save.
- Trigger pattern: the issue is most visible when group state is still catching up after promoted admins, demoted admins, or new members are involved.
- Severity: high for trust. The app can look like it accepted a local photo change while other members see no matching update.
- Frequency: not measurable from repo evidence alone, but repo code shows metadata, role, add-member, and remove-member mutations all guard against active group recovery.
- Confusion cost: the current copy exposes internal language, tells the user to try again without saying how long to wait, and can make admins repeat edits without knowing whether a previous attempt partially applied.

# 4. Current State

- `Test-Flight-Improv/60-post-creation-group-metadata-editing.md` records post-creation group metadata editing as shipped: admins can change group name, description, and photo.
- `lib/features/groups/application/group_recovery_gate.dart` defines a shared recovery gate with active depth state and the raw error text: `Group recovery is in progress. Try again after resync completes.`
- `lib/features/groups/application/update_group_metadata_use_case.dart` checks the recovery gate before loading or updating the group. If recovery is active, it throws a `StateError` with the raw recovery text.
- `lib/features/groups/application/update_group_member_role_use_case.dart`, `lib/features/groups/application/add_group_member_use_case.dart`, and `lib/features/groups/application/remove_group_member_use_case.dart` also reject mutations while recovery is active.
- `lib/features/groups/application/send_group_message_use_case.dart` blocks announcement sends during recovery, while discussion sends are covered separately by existing tests.
- Group resync is not one fixed countdown. Repo evidence shows group catch-up happens after startup, app resume, online reconnect, explicit `needsGroupRecovery` state changes, group notification drains, and a recurring online continuity sweep. `lib/core/services/pending_message_retrier.dart` defines a 30-second group continuity sweep while online, a 5-second debounce after becoming online, and a broader 5-minute retry interval.
- Because routine group continuity checks can run while the app is online, the user-visible disabled Save state should represent a real active recovery/update window, not make group editing feel blocked every time normal background maintenance runs.
- `lib/features/groups/presentation/screens/group_info_wired.dart` catches `StateError` from metadata editing and shows the error message directly in a snackbar.
- The same Group Info flow uploads and commits a replacement avatar before calling the metadata update use case. Because the group avatar path is stable for the group id, this can make the editing device appear to have a new photo even if the metadata update is later rejected during recovery.
- `_GroupMetadataEditorSheet` in `lib/features/groups/presentation/screens/group_info_wired.dart` disables Save only when the group name is empty. Repo evidence did not show a recovery-aware disabled Save state or a live elapsed timer in the editor.
- `lib/l10n/app_en.arb` already has general group recovery copy for conversations: `Catching up missed messages. New messages will still appear here.` The metadata editor does not currently have simple recovery-waiting copy for Save.
- `test/features/groups/presentation/group_info_screen_test.dart` covers the admin-only Edit Details affordance.
- `test/features/groups/presentation/group_info_wired_test.dart` covers successful admin metadata edits, signed replay/audit payloads, and signing failure rollback.
- `test/features/groups/application/update_group_metadata_use_case_test.dart` covers metadata success, non-admin rejection, demoted-admin rejection, and empty-name rejection. Repo evidence did not show a metadata-edit recovery UX test.
- `test/features/groups/integration/group_admin_metadata_convergence_test.dart` covers A/B/C group metadata convergence, promoted-admin metadata/photo updates, promoted-admin invites, non-friend member delivery, and admin demotion enforcement.
- `integration_test/group_admin_metadata_convergence_simulator_test.dart` wraps the group admin metadata convergence journeys as simulator tests, including the exact promoted-admin and demotion paths. Current simulator coverage proves positive convergence, but not the recovery-pending Save UX or the no-local-only-photo regression.

# 5. Scope Clarification

In scope:

- Group Info metadata editing while group recovery is active.
- A disabled Save state while the app is not ready to accept a group details update.
- The waiting state should be tied to an actual active recovery/update condition, not to the mere existence of periodic background group checks.
- Simple user-facing waiting copy that avoids "resync" and "group recovery" jargon.
- A live elapsed timer that shows how long the user has been waiting, not a promised time remaining.
- Consistent behavior for name, description, and photo edits: either the update is saved for the group or it is not shown as a completed group change.
- The reported A/B/C pattern: User A and User B are friends, User B and User C are friends, User A and User C are not friends, admin roles change, and all members must converge on the same details after a successful save.
- Required acceptance evidence from integration tests and end-to-end simulator tests.

Non-goals:

- No change to group admin permission policy.
- No change to who can invite whom.
- No change to group recovery, inbox replay, transport, encryption, or key rotation behavior.
- No requirement to promise an exact remaining wait time.
- No broad redesign of Group Info outside the recovery-waiting save experience.
- No manual-only acceptance path as the main proof.

Accepted ambiguities for later implementation:

- Exact localized wording can be decided later, as long as it is simple and does not expose internal recovery or resync terms.
- The exact timer format can be decided later, as long as it clearly counts elapsed waiting time.
- The threshold for longer-wait copy, such as "This is taking longer than usual," can be decided later.

# 6. Test Cases

## Happy Path

- When an admin opens Edit Group Details while group recovery is active, Save is disabled, the editor shows simple waiting copy, and the elapsed timer visibly increments while the user waits.
- When recovery finishes while the editor is still open, Save becomes available without losing the admin's entered name, description, or selected photo.
- When the admin saves after recovery finishes, the updated group name, description, and photo become visible to all current group members.
- When routine online group maintenance runs without an active unsafe recovery/update window, Save remains available and the editor does not show a waiting timer.
- When the same flow happens after User A promotes User C to admin, User C can wait through the updating state and then save group details without seeing raw recovery/resync error text.
- When User A and User C are not friends but are both group members, successful metadata and photo updates still converge for User A, User B, and User C.
- Required acceptance evidence layer: integration, because the outcome spans the editor surface, metadata persistence, avatar handling, group repository state, and user-visible copy.
- Required acceptance evidence layer: simulator/E2E, because the reported bug depends on multiple app users, admin role changes, member addition by a promoted admin, non-friend group membership, and cross-device convergence.

## Edge Cases

- If recovery starts after the editor is already open, the Save button becomes disabled and the user sees the waiting timer before a confusing failed save can occur.
- If recovery starts during a save attempt, the user does not see a raw recovery/resync error and does not end up with a local-only completed group photo.
- If the user selects a new photo while Save is disabled, the app may show it as an unsaved preview, but it must not appear as the completed group photo until the group details update succeeds.
- If the user cancels or closes the editor while recovery is active, the previous group name, description, and photo remain the visible saved group details.
- If an admin is demoted while the editor is waiting, the user does not save stale admin changes after recovery finishes.
- If recovery lasts longer than usual, the timer continues to be truthful and does not pretend to know the remaining time.
- If the 30-second online continuity sweep runs while the editor is open but there is no active recovery/update blocker, Save does not flicker disabled and the elapsed waiting timer does not appear.
- If the group name field is empty while recovery is active, the editor still keeps Save disabled and does not hide the name validation problem behind recovery language.

## Regressions To Preserve

- Bug regression: the Group Info metadata editor must not show `Group recovery is in progress. Try again after resync completes.` to the user when Save is blocked by recovery.
- Bug regression: a failed or blocked group details update must not leave only the editing device showing a new completed group photo while other members keep the old photo.
- Bug regression: after User C is promoted to admin in the reported A/B/C flow, User C's successful name, description, and photo update must reach User A and User B.
- Bug regression: routine event-driven maintenance or the 30-second online continuity sweep must not keep Save disabled when no active metadata-safety recovery window exists.
- Existing admin metadata editing still works when recovery is not active.
- Existing non-admin and demoted-admin metadata edit rejection still works.
- Existing promoted-admin metadata/photo convergence still works.
- Existing promoted-admin member invite behavior still works.
- Existing member messaging still works for A, B, and C even when A and C are not friends.
- Existing admin demotion timeline visibility and demoted-admin restrictions still work.
- Existing discussion group messages remain visible while recovery catches up.

# 7. Closure Evidence

Closed on `2026-05-29` by the GDR rollout:

- GDR-001 implemented recovery-aware group details Save behavior, draft/photo preservation, user-facing wait copy/timer, raw recovery-error mapping, and avatar commit/delete atomicity.
- GDR-002 added promoted-admin A/B/C recovery-save acceptance proof over the reported friend graph and admin-promotion shape.
- GDR-003 recorded the closure in the stable matrix, current test map, closure reference, and session breakdown.

Accepted evidence:

- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart`
- `flutter test --no-pub test/features/groups/application/update_group_metadata_use_case_test.dart`
- `flutter test --no-pub test/l10n/l10n_integrity_test.dart`
- `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart --plain-name 'promoted admin recovery-blocked save waits then metadata and photo converge'`
- `flutter test --no-pub test/features/groups/integration/group_admin_metadata_convergence_test.dart`
- `./scripts/run_test_gates.sh groups`
