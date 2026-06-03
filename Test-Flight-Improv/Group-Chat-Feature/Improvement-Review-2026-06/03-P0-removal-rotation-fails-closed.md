> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P0** · [Findings appendix](./appendix-findings.md)

---

# Make member removal durable and security-correct

**Priority: P0** — security boundary correctness (membership)

## Why this matters (user experience)

When an admin removes a member, the only thing that *must* happen, unconditionally, is that the removed member loses access to the live group key. Everything else — telling other members, re-keying offline devices, refreshing UI — is convergence work that can finish later. Today the code inverts this priority: it treats *full fan-out of the new key to every remaining device* as a precondition for the removal itself, and rolls the removal back if any single remaining member's device happens to lack a usable ML-KEM public key.

Concrete failure the admin sees:

- Admin taps "Remove" on member X.
- A *different* remaining member Y has a device with a missing/legacy ML-KEM key (common after restore, multi-device, or a member who joined before ML-KEM key exchange completed).
- The rotation aborts (`GROUP_ROTATE_KEY_UNDELIVERABLE_MEMBERS`), `rotateAndDistributeGroupKey` returns `null`, the UI throws, and `_rollbackFailedMemberRemoval` **re-adds X to local state and re-publishes a config that still includes X**.
- Result: the admin gets "Failed to rotate group key", and the removed member X is silently restored and **keeps the live key** — they can still read the group. The membership boundary is broken by an unrelated member's key gap.

The voluntary-leave path has the mirror-image defect: the leaver broadcasts `member_removed` to everyone *first*, then aborts on rotation failure, so the rest of the group thinks the member left while the leaver's own local state is not cleaned up — a split-brain where the member is "gone" to everyone but "still a member" to themselves and still receiving on the old key.

These are correctness/security failures, not cosmetic ones: an admin cannot reliably remove people, and a rollback can re-grant access to someone who was supposed to be excluded.

## Current behaviour & evidence

### Removal path (admin removes someone else)

`_onRemoveMember` in `group_info_wired.dart`:
- `group_info_wired.dart:851-861` — local removal is applied first (`removeGroupMember` updates DB + Go config), `localRemovalAccepted = true`.
- `group_info_wired.dart:936-1011` — `member_removed` is published on the topic, stored as offline replay, and sent direct to targets.
- `group_info_wired.dart:1014-1033` — `rotateAndDistributeGroupKey(...)`; if it returns `null`, `throw StateError(group_info_rotate_key_failed)`.
- `group_info_wired.dart:1039-1061` — the catch calls `_rollbackFailedMemberRemoval` which, at `group_info_wired.dart:782-805`, re-saves the removed member, restores the group row, deletes the removal timeline message, and **re-publishes a Go config that includes the removed member** (`callGroupUpdateConfig` with `restoredMembers`).

Inside the rotation use case (`rotate_and_distribute_group_key_use_case.dart`):
- `:150-168` computes `_undeliverableActiveMembers` and **returns `null` for the entire rotation** if that list is non-empty.
- `:736-744` `_undeliverableActiveMembers` = remaining members whose `_deliverableDevicesForRotation` is empty.
- `:746-758` `_deliverableDevicesForRotation` filters devices on `_hasUsableMlKemPublicKey`.
- `:757-758` `_hasUsableMlKemPublicKey` = "ML-KEM public key string is non-empty" — i.e. **key presence, not reachability**.
- Crucially, the undeliverable gate at `:150-168` runs *before* `distributionTargets` and the inbox fallback (`:170-181`, `:711-717`, `:760-828`). So an *offline-but-keyed* member is handled gracefully (direct send → inbox fallback), but a *missing-ML-KEM* member aborts the whole operation, including the security-critical re-key.

### Voluntary-leave path (member leaves)

`broadcastVoluntaryLeaveAndRotateKey` in `broadcast_voluntary_leave_use_case.dart`:
- `:135-152` — saves the leave timeline message and publishes `member_removed` on the topic.
- `:154-182` — stores the offline replay envelope for remaining members.
- `:184-201` — *then* calls `rotateAndDistributeGroupKey`; if it returns `null`, `throw StateError(voluntaryLeaveRotationFailedMessage)` at `:198-200`.

The caller `_onLeave` (`group_info_wired.dart:336-377`):
- `:343` runs `_broadcastSelfRemovalIfNeeded()` (which includes the rotation).
- `:345-352` proceeds to `leaveGroup` + local cleanup **only on success**.
- `:363-368` the catch only rolls back when `_isNativeLeaveFailure(e)` is true, and `_isNativeLeaveFailure` (`:692-693`) requires `BridgeCommandException` with command `'group:leave'`. A rotation `StateError` does **not** qualify, so: removal is already broadcast and inbox-stored, the leave timeline message is not deleted, and `leaveGroup` cleanup never runs. Split-brain confirmed.

## Root cause(s)

1. **Durability is gated on full fan-out success.** The security-critical outcome (kicked member loses the key) is coupled to a non-critical outcome (every remaining device gets the new key now). Rotation is all-or-nothing and "nothing" means *the removed member keeps access*.
2. **The gate keys on ML-KEM key presence, not reachability.** `_undeliverableActiveMembers` rejects members with a missing key string even though the system already has a graceful offline path (inbox fallback) and a *receiver-driven repair* subsystem (`group_pending_key_repairs`, migration `063`, `GroupPendingKeyRepairRunner`). A missing key is a *deferred-repair* condition, not an *abort* condition.
3. **The rollback is unsafe by design.** Re-adding the removed member to local state + Go config on rotation failure actively re-grants the live key to someone being removed. Rollback should never restore a removed member after the removal was already published to the group.
4. **Leave ordering is wrong.** The irreversible removal broadcast happens before the (failable) rotation, and the failure mode (`StateError`) isn't recognized as recoverable, so local cleanup is skipped while the network already believes the member left.

## Proposed improvements

The unifying principle: **separate "exclude the target" (must succeed, durable) from "re-key everyone reachable" (best-effort, retryable) from "repair unreachable/keyless members" (deferred).**

### 1. Make rotation tolerate keyless remaining members instead of aborting

In `rotate_and_distribute_group_key_use_case.dart`, **remove the hard abort** at `:155-168`. Instead, partition remaining members into:

- **distributable** — at least one device with a usable ML-KEM key (current `_deliverableDevicesForRotation`);
- **deferred-repair** — the current `_undeliverableActiveMembers` set (no usable ML-KEM key on any device).

Then:
- Still generate + promote the new epoch and persist it locally (steps 3–4 unchanged at `:336-365`). This is what actually revokes the removed member.
- Distribute to all distributable device targets best-effort (the existing loop at `:282-315` and `_distributeRotatedKeyToDeviceWithRetry`).
- For each deferred-repair member, **enqueue a sender-side pending key distribution** keyed by `(groupId, peerId, newEpoch)` so it is retried when that member's ML-KEM key becomes available, rather than blocking the rotation.

Reuse the existing repair infrastructure rather than inventing a new one. Today `group_pending_key_repairs` (`migration 063`, `GroupPendingKeyRepairRunner` in `group_pending_key_repair_service.dart:380-548`) is *receiver-driven* (a member who can't decrypt requests a repair). Add a **sender-driven deferred-distribution** record for the symmetric case (the rotator knows it couldn't deliver). Minimal options:

- **Preferred (reuse table):** add rows to `group_pending_key_repairs` with a new `status = 'pending_distribution'` and `payload_type = 'group_key_update'`, storing the target `peerId`/`transport_peer_id` and `key_epoch = newEpoch`. The runner's retry path (`retryPendingRepairsForKey`, `:408`) gains a branch that, for `pending_distribution` rows, re-attempts `_distributeRotatedKeyToDevice` once the member has a usable ML-KEM key. No migration needed (the columns already exist; `status` is free-form `TEXT`).
- **Alternative (new helper):** a dedicated `group_pending_key_distributions` table if mixing sender/receiver semantics in one table is undesirable. This requires a new migration (next free number) + DB helpers + repository, so it is more code; prefer the reuse option unless the status overload proves confusing.

Change the return contract so callers can distinguish "rotation done, fully distributed" from "rotation done, some members deferred":

```dart
class RotateGroupKeyOutcome {
  final GroupKeyInfo? key;          // null only on true failure (no new epoch promoted)
  final int distributedDeviceCount;
  final List<String> deferredPeerIds; // keyless/unreachable members queued for repair
  bool get rotated => key != null;
  bool get fullyDistributed => deferredPeerIds.isEmpty;
}
```

Return `key == null` **only** when the new epoch could not be promoted locally (steps 1–3 genuinely failed) — i.e. when the removed member would *not* actually lose access. A keyless remaining member must no longer produce `key == null`.

> Note: the partial-distribution case (`failedDistributionCount > 0` at `:317-332`) should follow the same philosophy — once the epoch is promoted and the removed member is excluded, undelivered remaining-member targets become deferred-repair entries instead of a `null` return. Keep promotion (`:336-350`) gated only on "the new key exists and is persisted", not on fan-out completeness.

### 2. Make the removal path treat partial distribution as a warning, not a rollback

In `group_info_wired.dart` `_onRemoveMember`:

- Replace the `rotatedKey == null` throw at `:1029-1033` with a check on the new outcome:
  - `outcome.rotated == false` → genuine failure (epoch not promoted, removed member not excluded). This *is* a fatal case; but see the rollback fix below.
  - `outcome.rotated == true && !outcome.fullyDistributed` → success with deferred members. Do **not** throw. Surface a non-fatal SnackBar (new l10n string, e.g. `group_info_remove_member_partial_distribution`) and continue.
- **Make rollback safe.** `_rollbackFailedMemberRemoval` (`:773-819`) must **never re-add a member whose `member_removed` was already published**. Since the publish at `:936-959` happens before rotation, by the time rotation could fail the removal is already on the wire. Guard rollback so it only fires for failures *before* the broadcast (e.g. local DB write / Go config update failed and nothing was published). After the broadcast, removal is committed; on a later failure, prefer **retry of rotation/distribution**, not restoration of the member. Track a `removalBroadcast` flag analogous to `localRemovalAccepted` and gate `_rollbackFailedMemberRemoval` on `!removalBroadcast`.

### 3. Fix voluntary-leave ordering and failure handling

Two complementary changes in `broadcast_voluntary_leave_use_case.dart`:

- **Reorder so the irreversible broadcast is last where feasible.** Attempt `rotateAndDistributeGroupKey` *before* publishing `member_removed` and storing the offline replay envelope (`:139-182`). If rotation cannot even promote a new epoch (`outcome.rotated == false`), abort **before** anything is broadcast and before the leave timeline message is committed — the leaver is cleanly still-a-member, no split-brain. (The leave-specific subtlety: the leaver removing *themselves* doesn't need to exclude another member, so rotation here is purely forward-secrecy hygiene; if it can't promote, leaving without rotating is acceptable — see best-effort fallback.)
- **Best-effort after broadcast.** If the design must keep broadcast-first (e.g. to ensure remaining members converge even if the leaver's rotation flakes), then **do not throw** on rotation failure at `:198-200`. Return `VoluntaryLeaveBroadcastResult(didBroadcast: true, rotatedKey: null, ...)` plus a `deferredRotation` flag and an emitted flow event, so `_onLeave` proceeds to `leaveGroup` cleanup. Remaining members can re-key on the next admin action.
- In `_onLeave` (`group_info_wired.dart:336-377`): once `broadcastResult.didBroadcast == true`, **always complete `leaveGroup` + cleanup**, regardless of rotation outcome. Restrict `_rollbackFailedVoluntaryLeave` (`:363-368`) to the pre-broadcast failure window only (native `group:leave` failure already qualifies; a post-broadcast rotation `StateError` must now lead to *forward* cleanup, not rollback).

### 4. Surface deferred state and drive it to convergence

- Emit explicit flow events for the new states: `GROUP_ROTATE_KEY_DEFERRED_REPAIR_QUEUED` (per deferred peer) and `GROUP_ROTATE_KEY_PARTIAL_DISTRIBUTION` (summary), replacing the abort event `GROUP_ROTATE_KEY_UNDELIVERABLE_MEMBERS` at `:156-166`.
- Wire the deferred-distribution rows into the existing repair runner so they retry on the same triggers that already drive `group_pending_key_repairs` (app resume, key-repair request, periodic). Reuse `GroupPendingKeyRepairRunner.retryPendingRepairsForKey` (`:408`) with the new status branch.

### Wire / DB / migration impact

| Change | Impact |
|---|---|
| Sender-side deferred distribution via existing `group_pending_key_repairs` (status `pending_distribution`) | **No migration** — columns already exist; status is free-form TEXT. Runner gains a branch. Preferred. |
| Alternative dedicated table | New migration (next free number after `072`) + DB helpers + repository + DI threading in `main.dart`. More code. |
| Wire format | **None.** `group_key_update` v2 envelope unchanged; the deferred path re-sends the same envelope later. |
| `rotateAndDistributeGroupKey` return type | `GroupKeyInfo?` → `RotateGroupKeyOutcome`. Update both call sites (`group_info_wired.dart:1014`, `broadcast_voluntary_leave_use_case.dart:186`) and tests. |

## Affected files & components

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart` — remove abort gate (`:150-168`); partition members; promote-then-defer; new return type; enqueue deferred distributions.
- `lib/features/groups/presentation/screens/group_info_wired.dart` — `_onRemoveMember` (`:821-1076`): no-throw on partial distribution, guard `_rollbackFailedMemberRemoval` (`:773-819`) so it never restores a removed member post-broadcast; `_onLeave` (`:336-377`) forward-cleanup on post-broadcast rotation failure.
- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart` — reorder rotation before broadcast and/or make post-broadcast rotation failure non-fatal (`:139-201`).
- `lib/features/groups/application/group_pending_key_repair_service.dart` — add `pending_distribution` branch to `GroupPendingKeyRepairRunner.retryPendingRepairsForKey` / `_retryOne`.
- `lib/features/groups/domain/repositories/group_pending_key_repair_repository_impl.dart` + `lib/core/database/helpers/group_pending_key_repairs_db_helpers.dart` — enqueue/query sender-side rows.
- `lib/l10n/app_en.arb` (+ `ar`/`de` + generated `app_localizations*.dart`) — new non-fatal partial-distribution string; possibly retire/repurpose `group_info_rotate_key_failed`.
- DI: `lib/main.dart` only if the alternative dedicated-table option is chosen.

## Test & verification strategy

### Unit (existing suites to extend)

- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` — add cases:
  - remaining member with **empty ML-KEM key** → rotation still promotes the new epoch, returns `rotated == true`, that peer appears in `deferredPeerIds`, removed member is **not** in the new-epoch recipient set.
  - mixed: one keyed-online, one keyed-offline (inbox fallback), one keyless (deferred) → epoch promoted, online direct, offline inbox, keyless deferred.
  - genuine failure (Go `generateNextKey` fails / promote fails) → `rotated == false`, no epoch advance.
- `test/features/groups/application/remove_group_member_use_case_test.dart` and `member_removal_integration_test.dart` — assert that after a keyless-remaining-member rotation, the removed member is **gone from local state and Go config** (no rollback re-add), and a partial-distribution warning path is taken rather than a throw.
- New/extended test for `broadcastVoluntaryLeaveAndRotateKey` — rotation-failure-after-broadcast no longer throws; `_onLeave` completes `leaveGroup` cleanup; no split-brain (leaver removed locally, timeline message kept consistent).
- `GroupPendingKeyRepairRunner` — `pending_distribution` rows retried and finalized once the target gains a usable ML-KEM key.

### Integration harnesses (this repo)

- `test/features/groups/integration/group_membership_smoke_test.dart` — add a "remove with a keyless bystander" scenario asserting durable removal.
- `integration_test/group_recovery_e2e_test.dart` / `group_recovery_cli_e2e_test.dart` — extend so a recovered (ML-KEM-regenerated) member acts as the keyless bystander while a third member is removed; assert removal durability + later repair convergence.
- `integration_test/group_multi_party_device_real_harness.dart` — multi-party real-stack: admin removes X while Y has a legacy/missing key on one device; assert X loses the live epoch and Y converges via deferred repair.

### Device matrix & gates (Test-Flight-Improv)

- Add a row to `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and a gate in `Test-Flight-Improv/test-gate-definitions.md` for "member removal is durable under a keyless remaining member" and "voluntary leave does not split-brain on rotation failure".
- Cross-reference `Test-Flight-Improv/52-notification-journey-test-matrix.md` for the removed-member-stops-receiving check (the removed member must no longer decrypt new-epoch traffic) and `20-group-discussion-reliability-closure-reference.md` for convergence closure.
- Two-device manual: iPhone13 + Pixel6 — admin removes one device's owner while the other device has a stripped ML-KEM key; confirm removal sticks and the bystander recovers after the repair runner fires.

### Negative / security assertions (must-haves)

1. After removal of X (regardless of bystander key state), X **cannot decrypt** a message published at the new epoch.
2. `_rollbackFailedMemberRemoval` **never** re-adds X once `member_removed` has been published.
3. New epoch is monotonic; deferred repair never resurrects an old epoch for the removed member.

## Risks, trade-offs & rollout

- **Trade-off: weaker fan-out atomicity.** We accept that some remaining members may briefly be on the old epoch (deferred repair) in exchange for guaranteed exclusion of the removed member. This is the correct security posture — forward secrecy for the *boundary* matters more than synchronous convergence for *insiders*. Deferred members are already insiders; they keep reading old-epoch traffic until repaired, which is acceptable.
- **Risk: deferred-repair backlog never drains** if a member's ML-KEM key never arrives. Mitigate with attempt/`trigger_count` caps (already present in the `063` schema: `attempts`, `last_error`, `finalized_at`) and a flow-event surface so it's observable; optionally a UI affordance prompting that member to refresh keys.
- **Risk: return-type change ripples.** `RotateGroupKeyOutcome` touches two call sites and several tests; contained and compiler-enforced.
- **Risk: leave reorder changes timing.** Putting rotation before broadcast slightly delays the visible "left" event; acceptable and strictly safer. Keep the broadcast-first variant behind the best-effort path if convergence-first is preferred.
- **Rollout:** ship behind the existing migration infrastructure (no new migration if reusing `group_pending_key_repairs`). Land use-case + tests first (no UI behavior change visible until the wired call sites switch), then flip `group_info_wired` to the non-fatal/no-rollback behavior, then the leave path. Each step is independently testable.

## Effort estimate

**Large.** The rotation use-case rewrite (partition + promote-then-defer + new return contract), the sender-side deferred-distribution reuse of the repair runner, the two UI call-site behavior changes (no-throw + safe-rollback + leave forward-cleanup), and the multi-party/recovery integration coverage together span ~6 files of core logic plus tests and Test-Flight gate updates. The diagnostics, l10n, and DI surface are small; the correctness-critical logic and the new test matrix dominate the cost. Estimate ~3–5 focused days, with the integration/device proofs being the long pole given this repo's device-harness constraints.
