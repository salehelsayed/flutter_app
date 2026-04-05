# 1. Title and Type

- Title: Post-Creation Admin Role Management
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/59-post-creation-admin-role-management.md`
- Matrix rows: `MR-016`, `MR-017`, `MR-018`, `MR-019`, `MR-021`, `UX-011`, `SC-013`, `SC-014`

# 2. Problem Statement

- Users can create groups with role-aware membership, but after creation there is no supported product flow for promoting another admin, revoking admin, or handling deliberate multi-admin ownership changes.
- Current group owners cannot hand off responsibility, cannot formalize shared administration, and cannot satisfy multi-admin journeys that the test matrix now tracks explicitly.
- This becomes a user-facing problem when the original admin needs help moderating, needs to leave safely, or needs another admin to continue running the group.

# 3. Impact Analysis

- Affects admins of longer-lived or higher-coordination groups, especially when one person should not remain the only effective owner forever.
- Appears whenever a group needs admin continuity, shared moderation, or explicit role changes after the initial creation flow.
- The current product already blocks the last admin from leaving, so users can hit a real dead end: the app requires admin continuity but does not provide a supported way to create it after group creation.
- The gap also prevents the repo from truthfully closing multi-admin correctness and convergence scenarios as product-owned behavior.

# 4. Current State

- The repo models group and member roles, but the landed product flow only exposes admin-gated add/remove membership rather than richer post-creation admin management. Evidence: `lib/features/groups/domain/models/group_member.dart`, `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/presentation/screens/group_info_screen.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`
- The group info UI currently shows member rows, `Add Member`, per-member removal, and `Leave Group`. It does not surface promote, demote, or transfer-admin actions. Evidence: `lib/features/groups/presentation/screens/group_info_screen.dart`, `test/features/groups/presentation/group_info_screen_test.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- `leaveGroup` blocks the sole admin from leaving, which confirms the current product expects continuity of admin responsibility without yet offering a supported role-management flow to satisfy that need. Evidence: `lib/features/groups/application/leave_group_use_case.dart`, `test/features/groups/presentation/group_info_wired_test.dart`
- The repository interface exposes `updateMemberRole`, but repo-local usage does not show a shipped user-facing path invoking it. Current matches are the interface and repository-level persistence coverage only. Evidence: `lib/features/groups/domain/repositories/group_repository.dart`, `lib/features/groups/domain/repositories/group_repository_impl.dart`, `test/features/groups/domain/repositories/group_repository_impl_test.dart`
- Existing rollout docs still describe richer admin-role work as unsupported scope. Evidence: `Test-Flight-Improv/11-group-discussion-use-case-audit.md`, `Test-Flight-Improv/09-network-group-messaging.md`
- Current direct tests cover the existing add/remove/leave behavior, not promotion, demotion, multi-admin leave, or concurrent admin-change outcomes. Evidence: `test/features/groups/presentation/group_info_wired_test.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`

# 5. Scope Clarification

- In scope:
  - post-creation admin promotion, demotion/revocation, and safe admin continuity behavior in existing groups
  - user-visible multi-admin state, including badges and admin-only action permissions
  - product-visible role-change outcomes for affected members and other group participants
  - deterministic end-user outcomes for the matrix scenarios listed above, including multi-admin leave and conflicting admin changes
- Explicit non-goals:
  - introducing unrelated moderation systems beyond admin/member role management
  - redesigning group creation, invite cryptography, or ordinary message delivery
  - inventing brand-new role taxonomies beyond what the product later chooses to support
- Accepted ambiguities for the later implementation pass:
  - whether the product exposes promote, transfer, and demote as separate actions or as a narrower contract
  - exact copy and timeline wording for role-change system events
  - exact conflict-resolution rule, as long as the visible contract becomes explicit and deterministic

# 6. Test Cases

## Happy Path

- An admin promotes an existing member to admin, and all peers show that member with admin status plus immediate access to admin-only actions.
- A group with at least two admins lets one admin leave without breaking the group, and the remaining admin can continue normal admin actions.
- When admin-role changes are part of the product contract, members see the updated role state consistently in the member list and any product-visible role-change event surface.

## Edge Cases

- A non-admin attempting to grant self admin rights is blocked visibly and does not change role state on any peer.
- Promoting a non-member fails cleanly, and no phantom member or phantom admin entry appears in the group.
- Demoting or revoking an admin immediately removes admin-only permissions across peers once the change becomes effective.
- Near-simultaneous admin changes on different peers still converge to one final visible member/admin state.
- Conflicting remove, re-add, or promote actions around the same member converge deterministically to one visible outcome.

## Regressions To Preserve

- Existing add-member, remove-member, and ordinary announcement-writer enforcement flows keep working for groups that never use admin-role changes.
- Existing last-admin leave blocking remains correct until the product has a supported continuity path for another admin.
- Existing invite, resume, and membership recovery flows remain intact when no admin-role changes occur.
