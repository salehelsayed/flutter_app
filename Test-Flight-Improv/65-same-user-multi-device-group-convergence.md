# 1. Title and Type

- Title: Same-User Multi-Device Group Convergence
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md`
- Matrix row: `UX-013`

# 2. Problem Statement

- The repo proves group behavior across multiple different peers, but it does not currently define what should happen when the same user uses the same account or identity on more than one device and group state changes on one of them.
- Users in that situation need a predictable contract for membership state, message visibility, mute preferences, unread state, and notification behavior across their own devices.
- Without that contract, the product cannot honestly claim same-user multi-device convergence even though many underlying group features already exist on a single device.

# 3. Impact Analysis

- Affects users who restore or use the same identity on multiple devices and expect their group experience to stay coherent across them.
- Appears when one device is active and another is offline, muted differently, or resumes later after membership or message changes.
- The current gap is partly policy and partly coverage: the repo has strong multi-peer tests, but not a same-user multi-device rule for which pieces of group state are shared versus device-local.
- This matters most for trust and predictability, because users can reasonably expect “my second device” to behave differently from “another member.”

# 4. Current State

- Group convergence proof in the current repo is built around distinct peers/users. The main smoke and recovery suites instantiate separate `GroupTestUser` stacks with unique peer IDs such as `peer-admin`, `peer-bob`, and `peer-charlie`. Evidence: `test/shared/fakes/group_test_user.dart`, `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`
- The local identity contract is single-instance per app database: `IdentityRepository` stores at most one active identity row for the current installation. That is compatible with one device’s local state, but it does not define cross-device convergence for the same user. Evidence: `lib/features/identity/domain/repositories/identity_repository.dart`
- Per-group mute is now a shipped feature, but the current proof is repo-local and device-local: the group model persists `is_muted`, group info toggles it, and `GroupMessageListener` suppresses local notifications for muted groups. The repo does not yet define whether mute should propagate across a user’s other devices or remain per-device. Evidence: `lib/features/groups/domain/models/group_model.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/set_group_muted_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, `Test-Flight-Improv/09-network-group-messaging.md`
- Existing docs and matrices explicitly keep same-user multi-device convergence as contract-undefined. Evidence: `Test-Flight-Improv/libp2p_group_chat_policy_needed_matrix.md`, `Test-Flight-Improv/libp2p_group_chat_test_matrix_full_with_rules.md`
- Current direct tests cover membership convergence, replay recovery, notification suppression, mute, invite decisions, admin-role changes, metadata edits, and dissolve across peers, but they do not run one logical user across two devices and assert a shared-device contract. Evidence: `test/features/groups/integration/group_membership_smoke_test.dart`, `test/features/groups/integration/group_resume_recovery_test.dart`

# 5. Scope Clarification

- In scope:
  - the same-user multi-device contract for group membership state
  - same-user behavior for new messages and replayed backlog across devices
  - whether mute, unread counters, and notification behavior are shared or device-local
  - reconnect and offline recovery behavior when one device changes group state and another resumes later
- Explicit non-goals:
  - redesigning broader account, backup, or restore flows outside what group convergence needs to define
  - changing the existing multi-peer correctness contract for different users
  - introducing a new cross-device sync system beyond whatever product-facing group contract is later chosen
- Accepted ambiguities for the later implementation pass:
  - whether mute and unread are account-wide or device-local
  - whether notification suppression is coordinated across devices or left local
  - how the product labels or explains device-specific versus shared state, as long as the contract becomes explicit and testable

# 6. Test Cases

## Happy Path

- When the same user has two devices and one device receives new group messages, the other device later reflects the correct group state according to the product’s chosen rule.
- Membership changes that affect the user or the group converge on both devices after normal replay or reconnect behavior.
- If the product chooses shared mute behavior, muting or unmuting on one device eventually produces the same mute state on the other; if the product chooses local-only mute, both devices still behave consistently with that local-only rule.

## Edge Cases

- One device being offline during membership, metadata, or dissolve changes still converges later to the same supported final group state for that user.
- Notification and unread behavior across the two devices follow one explicit rule instead of drifting unpredictably.
- Accepting, declining, or expiring a pending invite on one device produces the correct outcome on the other device for the same user according to the chosen product contract.
- A same-user second device does not appear to the system as an unrelated extra member or create duplicate membership entries for the group.

## Regressions To Preserve

- Existing single-device group behavior remains correct for users who never use a second device.
- Existing multi-peer convergence for different users remains unchanged.
- Existing group mute, invite-decision, metadata, admin-role, and dissolve behavior continues to work on a single device while the multi-device contract is added.
