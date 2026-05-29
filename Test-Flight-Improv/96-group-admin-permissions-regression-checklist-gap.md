# 1. Title and Type

Title: Group admin permissions regression does not yet cover the full checklist

Issue type: feature-improvement

Output doc path: `Test-Flight-Improv/96-group-admin-permissions-regression-checklist-gap.md`

# 2. Problem Statement

The user is trying to use the group reliability simulator regression as a release-confidence check for the full four-user group admin permissions checklist.

Today, `group --only 87` maps to `regression_group_admin_permissions_and_message_reliability_four_users`, and that scenario exercises the main four-role Alice/Bob/Charlie/Dana journey. It verifies important happy-path and state-convergence behavior, but it does not yet prove every forbidden admin option, every requested system-event visibility assertion, or every requested convergence field from the original checklist.

This is a problem because a passing simulator regression could be read as full checklist coverage even while some user-visible admin-permission failures remain untested.

# 3. Impact Analysis

- Affected users: group chat users whose group membership, admin role, group details, or removed-member access depends on consistent enforcement across devices.
- Affected workflows: group creation, group invite acceptance, admin promotion/demotion, group detail editing, member removal, group photo propagation, and post-removal message access.
- Severity: critical for reliability confidence because the existing scenario is intended to guard group admin correctness across four online app instances.
- Frequency: the gap appears whenever the current regression is used as evidence that the entire original admin-permission checklist is covered.
- Confusion cost: `group --only 87` can pass or fail as a strong simulator signal, but it should not be described as complete coverage of every checklist item until the missing observable cases are represented.

# 4. Current State

Current repo evidence shows the scenario is real and discoverable:

- `integration_test/scripts/run_group_multi_party_device_real.dart` registers `regression_group_admin_permissions_and_message_reliability_four_users` as a selectable group scenario.
- `integration_test/scripts/group_multi_party_device_criteria.dart` registers the scenario requirement with four roles and validates the scenario-specific proof.
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md` records that `$run-flutter-reliability-sims group --list` maps the scenario to command 87 in the current local ordering.

Current scenario coverage includes:

- Four roles: Alice, Bob, Charlie, and Dana.
- Friend graph shape where Alice is not friends with Charlie or Dana, while Bob/Charlie/Dana relationships support the invite cases.
- Bob accepts Alice's initial group invite.
- Bob becomes a promoted admin, changes group metadata and image, and invites Charlie.
- Charlie becomes a promoted admin, changes group metadata and image, and invites Dana.
- Bob is demoted and remains a normal member.
- Bob has blocked attempts after demotion, including member-add, role update, and removal attempts.
- Alice updates the group image after Bob's demotion.
- Charlie removes Dana.
- Dana is checked for removed-member send rejection and no post-removal plaintext delivery.
- Message matrices are represented for phases after Bob accepts, after Charlie accepts, after Dana accepts, and after Dana removal.
- Final active/admin/member/image/hash state is validated across active users.

Current checklist gaps visible in the harness and criteria:

- Unauthorized metadata rejection is represented as one combined name/description metadata attempt, not independent name, description, and image attempts.
- Non-admin Bob is not separately checked for promoting himself, demoting Alice, or removing Alice before promotion.
- Non-admin Charlie is not separately checked for promoting himself, demoting Bob, or removing Bob.
- Demoted Bob is not separately checked for changing image, demoting Charlie, or every post-Dana forbidden admin variant.
- The scenario does not assert user-visible system event text for admin promotion, admin demotion, or member removal.
- The convergence proof checks name, description, avatar metadata/bytes/hash, active members, admins, key epoch, and state hash, but does not separately prove pending invites, latest group event id, or group state version.
- The rejected-action proof is local state-hash based. It proves the local action is blocked or rejected and the local transition hash remains unchanged, while remote no-op and no fake success are mostly inferred from later convergence checks.
- Dana is checked for removed-member message exclusion, but not for attempting admin actions after removal.

Relevant evidence files:

- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `integration_test/scripts/run_group_multi_party_device_real.dart`
- `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md`

# 5. Scope Clarification

In scope:

- The regression should visibly distinguish full-checklist coverage from partial happy-path coverage.
- Every forbidden admin option in the original checklist should have observable rejection evidence for the relevant actor state: non-admin, demoted admin, and removed member where applicable.
- Rejected actions should be observable as no user-visible success, no local state mutation, and no remote state mutation.
- Active members should show converged group state after each group-control operation before the next operation is treated as successful.
- The scenario should continue to be represented as a four-user simulator reliability case for Alice, Bob, Charlie, and Dana.

Non-goals:

- This spec does not change group admin policy.
- This spec does not request new group product features.
- This spec does not require UI redesign.
- This spec does not require a new simulator framework or new scenario numbering scheme.
- This spec does not define implementation ownership, helper names, or code structure.

Accepted ambiguities for later implementation:

- Whether system event visibility is proven through timeline text, persisted event records, or another user-visible event surface remains open.
- The exact evidence shape for pending invites, latest event id, and group state version remains open as long as the acceptance result is observable and comparable across active members.
- Command number 87 is current local ordering evidence, but the stable scenario identity is `regression_group_admin_permissions_and_message_reliability_four_users`.

# 6. Test Cases

## Happy Path

- When the group reliability suite lists available group scenarios, the four-user admin permissions regression is selectable by its stable scenario identity and maps to Alice, Bob, Charlie, and Dana.
- When Alice creates the group and Bob accepts, Alice and Bob see the same group name, description, image bytes, active members, admins, key epoch where applicable, and message delivery matrix.
- When Bob is promoted to admin, Bob's group detail changes and image update become visible to Alice and Bob, including loadable image bytes.
- When Bob invites Charlie, Charlie receives the latest group details, image bytes, admin list, member list, and can exchange group messages with both Alice and Bob even though Alice and Charlie are not friends.
- When Charlie is promoted to admin, Charlie's group detail changes and image update become visible to all active members.
- When Bob is demoted, all active members agree that Bob remains a member but is no longer an admin.
- When Charlie invites Dana, all four active members agree on the latest group details, image bytes, members, admins, and full message matrix.
- When Charlie removes Dana, remaining active members agree Dana is removed, Dana cannot send new group messages, and Dana receives no new post-removal group messages.

Required acceptance evidence layer: simulator, because the behavior depends on four online app instances, invite propagation, avatar byte availability, and cross-peer message delivery.

## Edge Cases

- A non-admin Bob before promotion cannot independently change the group name, change the group description, change the group image, promote himself, demote Alice, remove Alice, or add a member.
- A non-admin Charlie cannot independently change the group name, change the group description, change the group image, promote himself, demote Bob, remove Bob, or invite Dana, even though Charlie and Dana are friends.
- Admin Alice cannot invite Dana while Alice and Dana are not friends, and Dana receives no invitation from that rejected action.
- A demoted Bob cannot independently change the group name, change the group description, change the group image, invite Dana, promote Dana, demote Charlie, or remove Dana.
- After Dana joins, Bob's forbidden admin attempts still fail against valid current-member targets.
- After Dana is removed, Dana cannot perform admin actions, cannot send group messages, and does not receive new active-member messages.
- Each forbidden action shows no successful user-visible mutation for the actor and no applied state change for active remote peers.
- Promotion, demotion, and member-removal events are visible to the relevant group members as user-understandable group events.
- After each group-control operation, active members converge on name, description, image metadata, image bytes, active members, admins, removed members, pending invite state where relevant, latest group event identity, group state version where available, state hash, and key epoch where encrypted.

Required acceptance evidence layers: simulator for multi-device behavior, and integration for persisted state/event consistency across app layers.

## Regressions To Preserve

- The existing four-role happy path remains covered: friend graph shape, promoted-admin metadata updates, Charlie and Dana joins, Bob demotion, Alice's post-demotion image update, Dana removal, and message matrices after major membership phases.
- Accepted group members do not need to be friends with every other member to send and receive group messages.
- Admins can invite only their own friends.
- Avatar checks continue to prove both metadata convergence and loadable image bytes.
- Message matrix evidence continues to prove exactly-once persistence for sender self-delivery and active peer delivery.
- Removed members remain excluded from post-removal message delivery.
- Preservation/regression case: a future passing result for this scenario must not weaken any existing final-state validation for active members, admins, removed members, avatar hash, state hash, key epoch, or matrix message keys.
