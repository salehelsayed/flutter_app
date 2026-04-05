# 1. Title and Type

- Title: Post-Creation Group Metadata Editing
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- Matrix rows: `MR-023`, `SC-002`, `UX-002`, `UX-003`

# 2. Problem Statement

- Users can set a group name and optional description when creating a group, but the product does not currently surface a supported way to rename the group or update its picture/description afterward.
- This leaves groups stuck with stale names, stale descriptions, and placeholder-only imagery even when the group purpose changes or the original metadata was incomplete.
- The missing product surface also means the repo does not yet define how non-admins should be blocked from metadata edits or how unauthorized raw metadata changes should be rejected as a user-visible contract.

# 3. Impact Analysis

- Affects any active group whose identity needs to evolve after creation, including renamed projects, rotating communities, or groups that want a clearer description or picture later.
- Appears after the initial creation flow, especially when a group starts quickly with temporary metadata and later needs cleanup.
- Users currently see the group name and description in several places, so stale metadata can create confusion across list, info, invite, and conversation surfaces.
- Because the product has no post-creation metadata contract today, both normal edit flows and unauthorized-edit rejection remain explicit product debt rather than normal coverage gaps.

# 4. Current State

- The creation screen captures the group name and optional description during group creation. Evidence: `lib/features/groups/presentation/screens/create_group_screen.dart`, `test/features/groups/presentation/create_group_screen_test.dart`
- The group info screen displays the current name, type, description, member count, and member list, but only surfaces `Add Member` and `Leave Group` actions. There is no landed edit action for metadata. Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- Group cards currently use a placeholder avatar derived from initials rather than a user-managed group picture flow. Evidence: `lib/features/groups/presentation/widgets/group_card.dart`, `test/features/groups/presentation/group_card_test.dart`
- The domain model and invite/join flows already carry description data, which shows that metadata exists in the product but is effectively fixed after creation. Evidence: `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `test/features/groups/integration/invite_round_trip_test.dart`
- Existing audit docs explicitly call out missing post-creation group avatar, rename, and description-edit support. Evidence: `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`
- Current direct tests cover creation-time metadata persistence and display, not post-creation edits or unauthorized metadata mutation rejection. Evidence: `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`, `test/features/groups/integration/invite_round_trip_test.dart`

# 5. Scope Clarification

- In scope:
  - post-creation rename behavior
  - post-creation description update behavior
  - post-creation group picture/avatar update behavior
  - admin versus non-admin permissions for metadata edits
  - user-visible propagation of the new metadata across existing group surfaces
- Explicit non-goals:
  - redesigning the broader group info screen beyond what metadata editing requires
  - advanced image tooling such as cropping, filters, or theme systems
  - changing the existing group-creation metadata contract except where preservation is required
- Accepted ambiguities for the later implementation pass:
  - exact placement of edit entry points in the UI
  - exact image constraints, cache-refresh policy, or upload affordances
  - whether metadata changes appear in a timeline/system-event surface, as long as the user-visible contract is explicit

# 6. Test Cases

## Happy Path

- An allowed admin renames a group, and every member later sees the new name in the group list, conversation header, group info surface, and any later invite/rejoin context that uses current metadata.
- An allowed admin updates the group description, and members later see the refreshed description consistently.
- An allowed admin updates the group picture, and members later see the refreshed group image instead of the previous placeholder-derived presentation.

## Edge Cases

- A non-admin attempting to rename the group or change picture/description is blocked visibly and does not change canonical metadata on any peer.
- A raw unauthorized metadata change submitted outside the normal UI is rejected, and the group keeps its last valid metadata.
- A member who was offline during one or more metadata changes later converges to the final metadata state after recovery.
- Repeated metadata edits settle on one final visible group identity instead of leaving peers on different names, descriptions, or pictures.

## Regressions To Preserve

- Group creation with initial name and optional description continues to work exactly as it does today.
- Existing invite, join, and resume flows continue to carry or recover the group metadata that is currently considered canonical.
- Existing membership add/remove and message-delivery flows remain unaffected when no metadata edit occurs.
