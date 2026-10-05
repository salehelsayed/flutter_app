# Findings: group key rotation after an admin handover — 2026-10-05

Audit basis: branch `wave3-baseline-20260930` at `bee0290c8`. Found on iOS
simulators during the Wave 3 ML-020 production journey
(`private_admin_role_transfer_delivery`), not by the auditor agent.

---

```yaml
id: group-key-rotation-2026-10-05-001
severity: medium
what-user-sees: >
  Nothing. That is the problem. Alice creates a group, makes Bob an admin,
  and Bob then demotes Alice to a regular member. When Bob later removes
  Charlie, the removal works and Charlie sees "removed", but the group key
  is never replaced. Charlie still holds the current key (epoch 1), so any
  group message he can still capture (pubsub topic, relay copy) stays
  readable to him. Normal delivery to Charlie stops, so no user notices.
  The group never recovers: every later removal or leave hits the same wall.
chain-break-at: >
  rotateAndDistributeGroupKey requires BOTH conditions:
  (1) the caller's role allows GroupMemberPermission.rotateKeys, and
  (2) the caller is the group creator (group.createdBy == selfPeerId).
  After the handover no member meets both: Bob (admin) fails (2), Alice
  (creator, now writer) fails (1). The removal path logs
  GROUP_INFO_FL_REMOVE_REKEY_DEFERRED and relies on a later rotation. The
  creator backstop (GroupOwedKeyRotationSweeper) runs only on the creator's
  device, so it retries every minute and logs
  GROUP_CREATOR_OWED_REKEY_DEFERRED forever.
  The receiving side is already wider: GroupKeyUpdateListener accepts a key
  update from any member whose role allows rotateKeys, creator or not.
same-gap-also-when: >
  The creator leaves the group, is removed, or is demoted for any other
  reason. broadcast_voluntary_leave_use_case.dart says a remaining admin
  re-keys on member_removed, but that admin is not the creator, so the same
  creator check refuses it.
production-files:
  - lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart:267
  - lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart:284
  - lib/features/groups/application/group_owed_key_rotation_sweeper.dart:76
  - lib/features/groups/presentation/screens/group_info_wired.dart:1619
  - lib/features/groups/application/broadcast_voluntary_leave_use_case.dart:124
  - lib/features/groups/application/group_key_update_listener.dart:279
evidence: >
  Device run 2026-10-05 11:49-11:58 UTC, three iOS 26.5 simulators, attempt
  build/sims/proofs/production.group_catalog.private_admin_role_transfer_delivery/attempt-NuPbVK
  (worktree .claude/worktrees/wave3-next). Bob at 11:56:22:
  GROUP_REMOVE_MEMBER_USE_CASE_SUCCESS, GROUP_ROTATE_KEY_PERMISSION_DENIED,
  GROUP_INFO_FL_REMOVE_REKEY_DEFERRED. Alice: GROUP_ROTATE_KEY_PERMISSION_DENIED
  at 11:56:22 and GROUP_CREATOR_OWED_REKEY_DEFERRED at 11:57:58. keyEpoch
  stayed 1 on Alice and Bob for the following 2 minutes. Alice's member row:
  role writer; Bob: admin.
suggested-fix: >
  Goal from the product owner: rotate keys without hurting usability. So the
  fix stays invisible to users: no prompts, no blocked sending, no waiting.
  1. One rotation leader per group, computed the same way on every device
     from the signed member config: the creator while they are a member whose
     role allows rotateKeys; otherwise the member with rotateKeys who joined
     first (tie broken by lowest peer ID). Only the leader rotates, so two
     admins never rotate at the same time and fork the epoch. This is likely
     why the creator-only rule exists; the leader rule keeps that guarantee
     without the dead end.
  2. Replace the creator check in rotateAndDistributeGroupKey with "self is
     the leader". Run GroupOwedKeyRotationSweeper on the leader, not only the
     creator, so an owed re-key after a removal, leave or demotion is done in
     the background within about a minute.
  3. If the leader stays offline, the next member in the same order takes
     over after a grace period (for example 10 minutes since the owed
     removal). If two rotations still race, the existing epoch handling must
     pick one winner deterministically (check before relying on it).
  4. Keep sending on the current key while the new key is distributed; the
     deferred distribution queue already delivers to offline members later.
  Tests: unit tests for the leader rule (creator demoted, creator left,
  two admins, nobody with rotateKeys); a production journey like ML-020 that
  asserts keyEpoch >= 2 on Alice and Bob after Bob removes Charlie.
verifiable-only-by: device-journey
status: open
related-docs:
  - docs/testing/production-bootstrap-migration-crosswalk.md (Wave 3 iOS section, ML-020)
```
