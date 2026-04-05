# 1. Title and Type

- Title: Group Membership Size Limit Contract
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/64-group-membership-size-limit-contract.md`
- Matrix row: `UX-009`

# 2. Problem Statement

- Users can add members to a group, but the product does not currently define whether groups have a hard membership cap, what that cap is, or how the UI should behave when someone tries to exceed it.
- This leaves admins without a clear expectation for how large a supported group can become and prevents the repo from honestly verifying “one more member beyond the limit fails cleanly” behavior.
- The gap matters because the current docs talk about tested and unprofiled size ranges, but those ranges are not the same thing as an enforced product limit.

# 3. Impact Analysis

- Affects admins who create or grow larger groups, especially as groups approach the upper end of the repo’s current small/medium scale expectations.
- Appears when adding members one by one or in batches and when product, QA, or support needs a truthful answer to “how big can a group be?”
- Without an explicit cap contract, growth past the intended scale can fail ambiguously, stay technically possible but unsupported, or create inconsistent expectations across UI, tests, and operational guidance.
- This is primarily a contract-definition and clean-failure problem rather than proof that small/medium groups are currently broken.

# 4. Current State

- The architecture doc explicitly positions current group messaging as robust for small/medium groups, calls `10-50` a reasonable current target, and treats larger sizes as unprofiled or not currently justified rather than as a hard enforced cap. Evidence: `Test-Flight-Improv/09-network-group-messaging.md`
- The add-member use case checks admin rights and duplicate membership but does not enforce a max-member count. Evidence: `lib/features/groups/application/add_group_member_use_case.dart`
- The contact-picker batch-invite flow filters out existing members and self, then adds every selected contact without a member-count guard. Evidence: `lib/features/groups/presentation/screens/contact_picker_wired.dart`
- Current repo-local group tests exercise multi-peer membership behavior and recovery, but they do not define or assert a product max-group-size rejection rule. Evidence: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`, `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`
- Existing limits in nearby group code are about pagination or retry batch sizes, not group-size enforcement. Evidence: `lib/features/groups/domain/repositories/group_message_repository.dart`, `lib/features/groups/application/retry_failed_group_inbox_stores_use_case.dart`

# 5. Scope Clarification

- In scope:
  - whether the product has a supported max group size
  - what happens when an admin tries to add members up to that limit
  - what happens when an admin tries to add one or more members beyond that limit
  - user-visible feedback and health of the pre-existing group when the limit is reached
- Explicit non-goals:
  - redesigning discovery, transport, or large-scale architecture beyond the product contract itself
  - changing unrelated message-size, attachment-count, or pagination limits
  - promising support for very large groups beyond what the product later chooses to own
- Accepted ambiguities for the later implementation pass:
  - exact numeric cap, if any
  - whether the cap applies identically to create-time member selection and later add-member flows
  - batch-overflow policy, such as all-or-nothing versus partial acceptance, as long as the user-visible rule is explicit and deterministic

# 6. Test Cases

## Happy Path

- An admin can create and grow a group normally up to the supported member limit without degrading the existing add-member experience.
- A group that stays within the supported size continues to deliver membership updates and ordinary group messaging as it does today.

## Edge Cases

- When the group has reached the supported limit, attempting to add one more member fails cleanly with clear feedback and without corrupting the existing group.
- A batch invite that would exceed the supported limit behaves according to one explicit rule and does not leave ghost members or mismatched local/remote state.
- Retrying an over-limit add does not create duplicates, partial phantom entries, or admin-only state drift.
- Existing members keep their ability to message and recover normally after an over-limit attempt is rejected.

## Regressions To Preserve

- Existing add-member success flows for supported small/medium groups remain intact.
- Existing duplicate-add rejection, admin gating, and recovery behavior continue to work below the supported limit.
- Existing group replay, notification, and recovery flows remain unaffected for groups that stay inside the supported size contract.
