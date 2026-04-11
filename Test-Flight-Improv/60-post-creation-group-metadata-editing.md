# 1. Title and Type

- Title: Post-Creation Group Metadata Editing
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/60-post-creation-group-metadata-editing.md`
- Matrix rows: `MR-023`, `SC-002`, `UX-002`, `UX-003`
- Current status: `shipped` on `2026-04-05`

# 2. Problem Statement

- This document originally captured the missing post-creation group metadata-editing gap.
- That gap is now closed: admins can rename a group and update its description and photo from the shipped group-info surface.
- The repo now also defines the user-visible enforcement contract: non-admins do not get the edit affordance, unauthorized raw `group_metadata_updated` envelopes are ignored, and offline peers converge to the newest metadata state.

# 3. Impact Analysis

- Affects any active group whose identity needs to evolve after creation, including renamed projects, rotating communities, or groups that want a clearer description or picture later.
- Appears after the initial creation flow. The current shipped create path only collects an optional group name, so description and photo updates are naturally post-creation concerns.
- Users see group metadata across list, info, invite, and conversation surfaces, so propagation and recovery need to stay consistent whenever metadata changes.
- The correctness bar is no longer "add the feature"; it is "preserve the shipped contract" across admin editing, non-admin gating, listener rejection, and offline convergence.

# 4. Current State

- The current shipped create flow is the picker route. It collects contacts plus an optional group name, not a description field. Evidence: `lib/features/groups/presentation/screens/create_group_picker_screen.dart`, `lib/features/groups/presentation/screens/create_group_picker_wired.dart`, `lib/features/groups/application/create_group_with_members_use_case.dart`
- The group info surface displays the current name, type, description, avatar, member count, and member list, and it now exposes an admin-only edit action for metadata. Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- Group cards already render the metadata-backed group avatar when present and fall back gracefully when no group photo exists. Evidence: `lib/features/groups/presentation/widgets/group_card.dart`, `test/features/groups/presentation/group_card_test.dart`
- The domain model, metadata update use case, and message listener now persist and replay the canonical metadata contract, including authorization and stale-event handling. Evidence: `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/application/update_group_metadata_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/update_group_metadata_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`
- Existing audit docs now describe post-creation metadata editing as a shipped capability rather than an open gap. Evidence: `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`
- Direct tests now cover admin edits, non-admin affordance gating, unauthorized raw metadata mutation rejection, and offline convergence to the newest metadata state. Evidence: `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`

# 5. Scope Clarification

- In scope for the shipped contract:
  - post-creation rename behavior
  - post-creation description update behavior
  - post-creation group picture/avatar update behavior
  - admin versus non-admin permissions for metadata edits
  - user-visible propagation and replay of metadata changes across existing group surfaces
- Explicit non-goals:
  - redesigning the broader group info screen beyond what metadata editing requires
  - advanced image tooling such as cropping, filters, or theme systems
  - widening the current create-group picker to collect description during creation
- Outside the current shipped contract:
  - exact image constraints beyond the current normalization and upload flow
  - richer image tooling such as cropping or filters
  - broader group-info redesign unrelated to metadata editing

# 6. Test Cases

## Happy Path

- An allowed admin renames a group, and every member later sees the new name in the group list, conversation header, group info surface, and any later invite/rejoin context that uses current metadata.
- An allowed admin updates the group description, and members later see the refreshed description consistently.
- An allowed admin updates the group picture, and members later see the refreshed group image instead of the previous placeholder presentation.

## Edge Cases

- A non-admin attempting to rename the group or change picture/description is blocked visibly and does not change canonical metadata on any peer.
- A raw unauthorized metadata change submitted outside the normal UI is rejected, and the group keeps its last valid metadata.
- A member who was offline during one or more metadata changes later converges to the final metadata state after recovery.
- Repeated metadata edits settle on one final visible group identity instead of leaving peers on different names, descriptions, or pictures.

## Regressions To Preserve

- Group creation with an optional initial name continues to work exactly as it does today.
- Existing invite, join, and resume flows continue to carry or recover the group metadata that is currently considered canonical.
- Existing membership add/remove and message-delivery flows remain unaffected when no metadata edit occurs.
