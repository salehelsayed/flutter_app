# BUG: a non-admin member cannot voluntarily leave a group

**Status:** open · candidate P1 (silent dead-end on a common action) · found 2026-06-15 while validating the new `private_voluntary_leave_convergence` (H01) reliability-sim row on iOS 26.1 simulators.
**Confidence:** high on the mechanism (source + device logs); the *intended* product behavior should be confirmed by the TDD-plan investigation (a deliberate admins-only-leave policy is possible but contradicted by the UI showing Leave to everyone).

## Problem (plain English)
When a regular member (a **writer** — i.e. not an admin) taps **Leave Group**, the leave **fails** and they stay in the group. The app tries to re-key the group as part of leaving, but **only admins are allowed to re-key**, so a normal member's leave dead-ends with an error.

## Symptom
- UI: the leave fails; the user remains a member. The surfaced error maps to **"Failed to rotate group key before leaving"** (`voluntaryLeaveRotationFailedMessage`).
- Logs (device): `GROUP_ROTATE_KEY_PERMISSION_DENIED` → `Bad state: Failed to rotate group key before leaving`.

## Repro (observed)
3 sims, alice = creator/admin, bob + charlie = writers (added members). charlie (a writer) attempts to leave. Captured in `group-h01-recheck*.log` (charlie role) on 2026-06-15:
```
[CHARLIE] GROUP_ROTATE_KEY_PERMISSION_DENIED
[CHARLIE] Bad state: Failed to rotate group key before leaving
```
The leave only succeeds when the leaver is an **admin with `rotateKeys`** (this is exactly how the *passing* host tests `member_removal_integration_test.dart` set up their leaver: `MemberRole.admin` + `GroupMemberPermissions(rotateKeys: true)`).

## Root cause (source, to be confirmed by the plan)
1. Every member's "Leave Group" goes through `_onLeave` → `_broadcastSelfRemovalIfNeeded()` → **`broadcastVoluntaryLeaveAndRotateKey`** (`lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`).
2. That use case **always** rotates the key when there are remaining members, and throws if rotation returns null:
   - `broadcast_voluntary_leave_use_case.dart:184-201` — `rotateAndDistributeGroupKey(...)`; `if (rotatedKey == null) throw StateError(voluntaryLeaveRotationFailedMessage);`
3. `rotateAndDistributeGroupKey` is permission-gated and returns null for a non-permitted caller:
   - `rotate_and_distribute_group_key_use_case.dart` — `canRotate = selfMember.permissions.allows(GroupMemberPermission.rotateKeys, selfMember.role)`; if false → emits `GROUP_ROTATE_KEY_PERMISSION_DENIED` and returns null.
4. A plain **writer** does not hold `rotateKeys` (admin-only by default), so the gate fails → leave fails.
5. UI shows **Leave** to every member (`group_info_screen.dart`, leave button rendered when `!group.isDissolved`), so the action is offered to users who cannot complete it.

## Impact
A regular member has **no working way to leave a group** — a core, common action. They either stay stuck or must be removed by an admin. Likely affects all non-admin members in every multi-member group.

## Why the H01 sim row can't pass as written
H01 modeled a non-creator (writer) leaver, which the app rejects. The row is therefore **blocked on this bug**, not on test wiring. Options once the bug is fixed: H01 validates a normal member's leave end-to-end. Until then, H01 is a known-red marker for this bug (or temporarily reshaped to an admin leaver — deferred to the fix plan).

## Likely fix direction (for the TDD plan to evaluate — NOT decided here)
A member should be able to leave regardless of role. Candidate approaches the plan should weigh:
- Don't require the **leaver** to hold `rotateKeys`; the forward-secrecy re-key on departure is the **group's** responsibility — e.g. a remaining admin performs/receives the rotation, or the leaver's departure publishes `member_removed` and a remaining admin re-keys.
- Or allow the leaver to perform a scoped self-removal re-key without the general `rotateKeys` permission.
- Preserve the existing **last-admin** guard (a sole admin still can't leave; must dissolve).

## Next step
After the current reliability-sim validation finishes, run a graphify-driven multi-agent **debug + TDD fix plan** (workflow over `graphify-arch`) to: confirm intended behavior, adversarially verify the root cause, design the fix, and lay out a test-first implementation (host tests + the H01 device-real row as the end-to-end proof).
