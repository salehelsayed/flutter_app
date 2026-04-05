# 1. Title and Type

- Title: Admin-Initiated Group Dissolve
- Issue type: `new-feature`
- Output doc path: `Test-Flight-Improv/62-admin-initiated-group-dissolve.md`
- Matrix rows: `UX-014`

# 2. Problem Statement

- Users currently have a personal `Leave Group` flow, but there is no supported product workflow for an allowed actor to dissolve or delete a group for everyone.
- This leaves no shared final-state contract for groups that should end permanently, and it keeps “group dissolve” as an explicit unsupported journey in the matrix.
- The gap is especially visible when a group should be shut down intentionally rather than merely abandoned member by member.

# 3. Impact Analysis

- Affects admins or group owners who need to end a temporary or project-based group cleanly.
- Affects all members of a group once a shared end-of-life state matters more than individual local leave behavior.
- The lack of a dissolve workflow can create lingering stale groups, unclear ownership expectations, and inconsistent assumptions about whether the group is still active.
- Because the current product already distinguishes ordinary leave behavior, adding a true dissolve flow requires a separate user-visible contract rather than stretching the meaning of local leave.

# 4. Current State

- The current group info UI exposes `Leave Group` but no dissolve or delete-for-everyone action. Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- `leaveGroup` leaves the topic and deletes the caller’s local group members, keys, and group row. That is personal exit behavior, not a shared group shutdown contract. Evidence: `lib/features/groups/application/leave_group_use_case.dart`
- The repo also contains local archive/unarchive primitives, which are separate local-state behaviors rather than a group-wide dissolve contract. Evidence: `lib/features/groups/application/archive_group_use_case.dart`, `lib/features/groups/application/unarchive_group_use_case.dart`
- Existing audit docs explicitly say there is no admin-initiated dissolve workflow and keep richer admin transfer/dissolution flows as unsupported scope. Evidence: `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Current direct tests cover leaving a group and last-admin leave blocking, not shared dissolve behavior across peers. Evidence: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/integration/group_edge_cases_smoke_test.dart`

# 5. Scope Clarification

- In scope:
  - an explicit admin-initiated group dissolve or delete-for-everyone contract
  - the final user-visible state for all current members once a group is dissolved
  - send/receive behavior after dissolution, including what members observe if they try to interact with the dissolved group later
  - reconnect or offline recovery behavior for members who were not online at the moment of dissolution
- Explicit non-goals:
  - replacing ordinary personal leave or local archive behavior
  - redefining unrelated admin-role-management flows outside what dissolution itself requires
  - broad account-level retention or legal-policy decisions outside this group feature contract
- Accepted ambiguities for the later implementation pass:
  - exact copy for the dissolve action and final-state messaging
  - whether dissolved groups remain locally visible as read-only history or disappear from the main list
  - whether only one actor type or several actor types are allowed to dissolve, as long as the policy becomes explicit

# 6. Test Cases

## Happy Path

- An allowed actor dissolves a group, and all members later observe the same final group state rather than continuing to treat the group as active.
- After dissolution becomes effective, members can no longer send new messages to that group.
- Members who open the dissolved group later see a clear final-state outcome instead of a silently broken conversation.

## Edge Cases

- A non-admin or otherwise unauthorized actor cannot dissolve the group.
- A member who was offline during dissolution later converges to the same dissolved-state outcome after reconnecting.
- Repeating the dissolve action or receiving duplicate dissolve-related state does not produce inconsistent final states across peers.
- Attempts to send after dissolution fail predictably instead of creating ghost messages or partial delivery.

## Regressions To Preserve

- Ordinary personal `Leave Group` behavior remains available and keeps its current meaning for users who are only leaving for themselves.
- Existing archive and unarchive behavior remains distinct from full group dissolution.
- Non-dissolved groups keep their current membership, invite, recovery, and notification behavior.
