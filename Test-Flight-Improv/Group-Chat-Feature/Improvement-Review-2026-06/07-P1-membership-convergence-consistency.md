> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · [Findings appendix](./appendix-findings.md)

---

# Make membership/role/metadata converge consistently

**Priority: P1** · Cluster: group membership-lifecycle convergence · Trust-damage: high, frequency: medium

> **One-liner:** Lock and stale-gate role updates, stop membership snapshots from regressing metadata, make metadata edits atomic with their broadcast, and break equal-timestamp ties deterministically.

---

## Why this matters (user experience)

When membership, roles, and metadata fail to converge, the group stops looking like a shared source of truth and starts looking broken:

- **Diverging admin views.** Two admins (or one admin on two devices) toggling roles concurrently can leave peers permanently disagreeing on who is an admin — one device shows a member as *admin*, another as *writer*. Because the role config can ship with an older `configVersion` than the receiver's watermark, the newer change is rejected or applied out of order, so the group never settles.
- **The name that flips back and forth.** Admin A renames the group; Admin B (who hasn't seen the rename) adds/removes a member or changes a role. B's membership event carries a *full* stale `GroupConfig` snapshot, and receivers that already applied A's new name silently revert to the old one. This reads as the group "fighting itself."
- **Silent metadata loss.** An admin edits the name/description/avatar while offline or with a flaky relay; the local copy commits but no one else ever receives it, with no rollback and no "not yet sent" indicator. The admin's group name permanently diverges from everyone else's.
- **Dropped same-instant edits.** Two membership changes in the same microsecond, or two admins with close/skewed clocks, collide on the watermark and the second legitimate change is discarded as "stale" on both sender and receivers — appearing to succeed for the actor but never landing for others.

These are lower-frequency than the P0 delivery clusters, but each one directly attacks trust in the group's correctness. The role-update lock+stale-gate in particular is a small, high-value fix that closes the most likely divergence path.

---

## Current behaviour & evidence

### 1. Role update skips the lock and the stale gate that add/remove use

`add_group_member_use_case.dart` and `remove_group_member_use_case.dart` both wrap their **entire** mutation body in `runGroupMembershipMutationLocked` and run `isStaleGroupMembershipEvent` before applying:

- `add_group_member_use_case.dart:156` — `runGroupMembershipMutationLocked<void>(groupId: groupId, action: ...)`, stale gate at `:268`.
- `remove_group_member_use_case.dart:77` — same lock wrapper, stale gate at `:109`.

`update_group_member_role_use_case.dart` has **neither**. It loads `group` and `members` unserialized (`:49`, `:123`), writes `groupRepo.updateMemberRole` (`:151`), then calls `callGroupUpdateConfig` with `configVersionOverride: normalizedEventAt` (`:158`–`:166`) and `recordGroupMembershipEventWatermark` (`:167`) — with no serialization against a concurrent add/remove/role mutation and no check that `normalizedEventAt` is newer than `group.lastMembershipEventAt`.

It does have a no-op short-circuit (`:108`–`:121`) and a try/catch revert (`:184`–`:200`), and `recordGroupMembershipEventWatermark` internally skips non-advancing writes (`group_membership_event_watermark.dart:62`) — but neither prevents concurrent interleaving of repo/validator/broadcast, and neither rejects a *stale-versioned* role change before it is sent. Receive-side ordering relies on the membership watermark, which an unguarded sender can violate by emitting a lower `configVersion`.

### 2. Membership/role snapshots overwrite metadata regardless of metadata version

> **Receive-side guard implemented in commit `74e8436c` (2026-06-03)** — the regression no longer sticks on the receive side. The send-side payload still carries full visible metadata, so the **strong variant** (trimming the snapshot at the source) remains open. See Improvement 2 below.

Membership and role events ship a **complete** `GroupConfig`:

- `remove_group_member_use_case.dart:207` — `buildGroupConfigPayload(...)`.
- `group_info_wired.dart:1183` — `_buildGroupConfig(group, members)` embedded in the `member_role_updated` system payload.
- `group_config_payload.dart:42`–`:47` — the payload still includes `name`, `description`, `avatarBlobId`, `avatarMime`, and `metadataUpdatedAt`.

On receive, the `member_role_updated` dispatch (`group_message_listener.dart:1934`–`1952`) and the `members_added` path gate **only** on `_shouldIgnoreStaleMembershipEvent` (the membership watermark), **not** on `_shouldIgnoreStaleMetadataEvent` (the metadata watermark, which is only applied to `group_metadata_updated` at `:1973`). `_handleMemberRoleUpdated` (`:3660`) calls `_applyAuthoritativeGroupConfigSnapshot` (`:3714`).

**As of `74e8436c`, `_applyAuthoritativeGroupConfigSnapshot` (`:4663`) no longer overwrites visible metadata unconditionally.** It now computes `currentMetadataWatermark = group.lastMetadataEventAt` (`:4778`) and an `appliesMetadataFields` gate (`:4779`–`:4782`) that is `true` only when the snapshot's `resolvedMetadataUpdatedAt` is **newer-or-equal** (`!resolvedMetadataUpdatedAt.isBefore(currentMetadataWatermark)`) to the receiver's watermark. The `updateGroup` call (`:4825`–`:4852`) gates `name`/`description`/`avatarBlobId`/`avatarMime`/`avatarPath`/`createdAt`/`createdBy` **and** `lastMetadataEventAt` behind that gate; avatar clear/path/delete bookkeeping (`:4804`–`:4821`, `:4855`) is gated too. A stale snapshot leaves visible metadata and the watermark untouched and emits `GROUP_MESSAGE_LISTENER_STALE_CONFIG_METADATA_FIELDS_IGNORED` (`:4783`–`:4793`). The **member-set and role deltas are still always applied** (`:4843`–`:4847`). So a stale snapshot no longer reverts the name on the receive side; the regression vector that remains is the send-side snapshot still carrying full visible metadata (the strong variant of Improvement 2).

### 3. Metadata edit commits locally before publish; failure leaves the admin diverged with no rollback

`update_group_metadata_use_case.dart:69`–`78` builds the updated group and persists `groupRepo.updateGroup(updated)` **inside** the use case — with no broadcast and no rollback hook beyond the optional `beforePersist` callback. The actual `callGroupPublish` (`group_info_wired.dart:1586`) and `callGroupInboxStore` (`:1633`) run **afterward, outside** the use case's commit. The surrounding `catch` (`group_info_wired.dart:1680`–`1701`) only emits `GROUP_INFO_FL_METADATA_UPDATE_ERROR`, shows a snackbar, and calls `_loadGroupInfo()` — it does **not** revert `groupRepo.updateGroup`.

Contrast with the membership flows, which restore prior state on publish failure:
- `update_group_member_role_use_case.dart:184`–`200` (re-applies prior role/`myRole`).
- `remove_group_member_use_case.dart:224`–`240` (re-saves the removed member, deletes the cutoff timeline message).

So a metadata publish/inbox failure permanently diverges the admin's local name from every other member, with no rollback and no pending-resend marker.

### 4. Microsecond-equal or clock-skewed membership events are dropped as stale

`group_membership_event_watermark.dart:38`–`44` — `isStaleGroupMembershipEvent` returns `true` for any `eventAt` **not strictly after** `lastMembershipEventAt`. The sender uses wall-clock microsecond timestamps as the version: `changedAt = DateTime.now().toUtc()` (`group_info_wired.dart:1118`) embedded as `microsecondsSinceEpoch` in the `sourceEventId` (`:1162`–`:1163`) and passed as `eventAt`. The receiver's `_shouldIgnoreStaleMembershipEvent` (`group_message_listener.dart:4245`) drops events where `!eventAt.isAfter(watermark)` (`:4258`). The role/dissolve dispatch (`:1934`, `:1953`) calls it **without** `allowEqualVersionReplay`, and only the add path has the `_membershipAddAdvancesLocalMember` escape hatch (`:4265`, `:4294`). There is no `(eventAt, sourceEventId)` tuple, no per-actor sequence number, and the sender never advances to `max(now, last + 1µs)`. Single-device microsecond collisions are improbable; the realistic trigger is **cross-admin clock skew** producing equal/inverted timestamps.

### 5. (Low) Receiver-side validator config-sync failures are logged but not reconciled in-session

`_syncGroupConfig` (`group_message_listener.dart:4942`–`5001`) tries once, retries once, returns `false`. It now takes an `emitFailureEvent` param (`:4945`) and, when set, emits `GROUP_MESSAGE_LISTENER_CONFIG_UPDATE_RETRY_FAILED` internally on double-failure (`:4991`); callers — `_handleMemberRoleUpdated` (`:3719`–`:3727`), the metadata-updated path (`:3794`–`:3802`), and the members-added paths (`:3097`/`:3105`, `:3482`/`:3490`) — pass `emitFailureEvent: true` and additionally `emitFlowEvent('CONFIG_SYNC_FAILED')` (`:3105`/`:3490`/`:3727`/`:3802`) and continue. The DB apply via `_applyAuthoritativeGroupConfigSnapshot` is already committed, so the DB reflects new membership while the Go validator still enforces the old config; the member can then send messages the rest of the group rejects. There is still no **durable** pending-config-resync marker anywhere in `lib/features/groups` (the new event is log-only), so the in-session gap stands.

**Scope note:** this is *not* permanent. `rejoin_group_topics_use_case.dart:131`–`139` rebuilds `groupConfig` from the (already-updated) DB and calls `callGroupJoinWithConfig` on app startup / watchdog / recovery, re-pushing the corrected config to the validator. The real gap is the lack of an **in-session** retry and any **user-visible** indication, which bounds the impact to the current session.

---

## Root cause(s)

| # | Root cause | Consequence |
|---|------------|-------------|
| A | Role update is the one membership mutation that was never wrapped in the shared lock + stale gate. | Concurrent role/add/remove interleave; stale-versioned role configs are emitted. |
| B | Membership/role events carry a full `GroupConfig` (including visible metadata). **Receivers now also gate visible metadata on the metadata watermark (`74e8436c`)**, but the send-side payload still embeds full visible metadata, so the regression vector persists at the source. | Receive-side regression fixed; remaining risk is the snapshot still carrying stale metadata on the wire (strong variant of Imp. 2). |
| C | Metadata commit and metadata broadcast live in two different layers (use case vs. wired screen) with no shared transaction/compensation. | Publish failure leaves local-only metadata with no rollback or resend. |
| D | The membership "version" is a raw wall clock with strict `isAfter` comparison and no tie-breaker. | Equal/skewed timestamps drop a legitimate distinct event on both ends. |
| E | DB snapshot apply and Go validator sync are independent; sync failure has no durable retry record and no UI surface. | In-session DB/validator drift until an unrelated rejoin re-syncs. |

The unifying root cause: **the four convergence-critical write paths do not share one ordering/serialization/atomicity discipline.** Add/remove already established the right pattern (lock + stale gate + compensating rollback). Role, metadata, and the watermark comparator each diverge from it in a different way.

---

## Proposed improvements

> Ordered by value-to-effort. Improvements 1–2 are the high-value, low/medium-effort core of this theme — **the receive-side half of Improvement 2 already shipped in `74e8436c` (2026-06-03); only its strong send-side variant remains**; 3 closes the metadata-atomicity gap; 4–5 are the larger ordering/observability hardening.

### 1. Lock and stale-gate the role update (small, high value)

In `update_group_member_role_use_case.dart`, wrap the whole body in `runGroupMembershipMutationLocked` exactly like add/remove, **reload group + members inside the lock**, and add a stale gate before applying.

```dart
await runGroupMembershipMutationLocked<void>(
  groupId: groupId,
  action: () async {
    final group = await groupRepo.getGroup(groupId);
    if (group == null) throw StateError('Group not found: $groupId');
    if (group.isDissolved) throw StateError(groupMembershipMutationDissolvedMessage);

    // ... existing admin / permission / target / no-op / last-admin checks,
    //     all now reading serialized state ...

    final normalizedEventAt = eventAt?.toUtc() ?? DateTime.now().toUtc();
    if (isStaleGroupMembershipEvent(
      eventAt: normalizedEventAt,
      lastMembershipEventAt: group.lastMembershipEventAt,
    )) {
      emitFlowEvent(layer: 'FL',
        event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_STALE_EVENT',
        details: {'groupId': _prefix(groupId), 'eventAt': normalizedEventAt.toIso8601String()});
      throw StateError(staleGroupMembershipEventMessage);
    }

    // ... existing updateMemberRole + callGroupUpdateConfig +
    //     recordGroupMembershipEventWatermark + try/catch revert ...
  },
);
```

Notes:
- Move the existing admin/last-admin checks **inside** the lock so the admin-count math runs on serialized state (currently it reads `members` at `:123` outside any lock).
- The existing revert block (`:184`–`:200`) stays inside the lock so a publish failure still restores both the target role and `myRole`.
- Reuse `staleGroupMembershipEventMessage` and `groupMembershipMutationDissolvedMessage` already defined for add/remove for consistent error surfacing.
- **No wire/DB/migration impact.** Pure use-case serialization change.

### 2. Don't let membership/role snapshots regress metadata (medium)

> **Receive-side guard: DONE — implemented in commit `74e8436c` (2026-06-03), after this review.** `_applyAuthoritativeGroupConfigSnapshot` (`group_message_listener.dart:4663`) now computes `currentMetadataWatermark = group.lastMetadataEventAt` (`:4778`) and an `appliesMetadataFields` gate (`:4779`–`:4782`, using `!resolvedMetadataUpdatedAt.isBefore(watermark)` — newer-or-equal) that conditions every visible-metadata field plus `lastMetadataEventAt` in the `updateGroup` call (`:4825`–`:4852`) and the avatar bookkeeping (`:4804`–`:4821`, `:4855`); member-set/role deltas remain always-applied (`:4843`–`:4847`), and a stale snapshot emits `GROUP_MESSAGE_LISTENER_STALE_CONFIG_METADATA_FIELDS_IGNORED` (`:4783`–`:4793`). The shipped guard uses `!isBefore` (newer-or-equal), which subsumes the equal-instant repair case below. **The stronger variant (trim visible metadata from the snapshot at the source) is still open** — see the end of this section.

The original proposal (now shipped on the receive side): `_applyAuthoritativeGroupConfigSnapshot` must only overwrite visible metadata when the snapshot's `metadataUpdatedAt` is *strictly newer* than the receiver's `lastMetadataEventAt` (or equal-and-repairing, mirroring `_metadataReplayRepairsVisibleFields` at `:4441`).

```dart
final snapshotMetaAt = resolvedMetadataUpdatedAt;            // already parsed at :4602
final localMetaAt = group.lastMetadataEventAt?.toUtc();
final metadataIsNewer = localMetaAt == null ||
    (snapshotMetaAt != null && snapshotMetaAt.isAfter(localMetaAt));
final metadataRepairsEqual = snapshotMetaAt != null &&
    localMetaAt != null &&
    snapshotMetaAt.isAtSameMomentAs(localMetaAt) &&
    _metadataReplayRepairsVisibleFields(group, parsed);
final applyVisibleMetadata = metadataIsNewer || metadataRepairsEqual;

await _groupRepo.updateGroup(group.copyWith(
  name: applyVisibleMetadata
      ? (normalizedGroupConfig['name'] as String? ?? group.name)
      : group.name,
  description: applyVisibleMetadata && normalizedGroupConfig.containsKey('description')
      ? normalizedGroupConfig['description'] as String?
      : group.description,
  avatarBlobId: applyVisibleMetadata ? resolvedAvatarBlobId : group.avatarBlobId,
  avatarMime:  applyVisibleMetadata ? resolvedAvatarMime  : group.avatarMime,
  avatarPath:  applyVisibleMetadata ? nextAvatarPath      : group.avatarPath,
  type: resolvedType,                 // member-set / role deltas always applied
  createdAt: resolvedCreatedAt,
  createdBy: normalizedGroupConfig['createdBy'] as String? ?? group.createdBy,
  myRole: ... ,                       // unchanged: role delta always applied
  lastMetadataEventAt: applyVisibleMetadata
      ? (snapshotMetaAt ?? group.lastMetadataEventAt)
      : group.lastMetadataEventAt,     // never regress the watermark
));
```

Key points (all satisfied by the shipped guard):
- The **member-set and role deltas are always applied** (that's what membership/role events are *for*); only the visible-metadata fields are conditionally preserved. (Shipped: `:4843`–`:4847`.)
- The avatar-changed / avatar-delete bookkeeping (`:4804`–`:4821`, `:4855`) is gated behind `appliesMetadataFields` too, so a stale snapshot doesn't delete the on-disk avatar.
- `lastMetadataEventAt` **never** moves backward (`:4848`).

**Stronger alternative — still open (recommended long-term):** exclude visible metadata fields entirely from membership/role snapshots in `buildGroupConfigPayload` (a `includeVisibleMetadata: false` mode), so name/description/avatar reconcile *only* through `group_metadata_updated` events. The send-side payload still carries full visible metadata (`group_config_payload.dart:42`–`:47`), so this regression vector still exists at the source even though the receive-side guard above neutralises it. Removing it at the source is a **wire-shape change** to the snapshot payload, so it must be rolled out behind the existing `schemaVersion`/state-hash machinery and kept backward-compatible with peers still sending full snapshots — which is why the receive-side guard (now shipped) was the safer first step.

### 3. Make the metadata edit atomic with its broadcast (medium)

Make metadata symmetric with the membership flows. Capture the pre-edit snapshot and, on publish/inbox failure, either revert or durably mark the edit as pending-resend.

Two-part change:

1. **Use case** (`update_group_metadata_use_case.dart`): return the *previous* group alongside the updated one, or accept an `onBroadcastFailed` compensation hook so the caller can revert through the same code path. Today the only escape valve is `beforePersist`; add an analogous post-persist contract.

2. **Wired flow** (`group_info_wired.dart:1586`–`1658`): wrap `callGroupPublish` + `callGroupInboxStore` in a try/catch. On failure:
   - **Minimum:** revert `groupRepo.updateGroup` to the captured pre-edit snapshot, delete the optimistic `metadataTimelineMessage` (`:1573`–`1581`), and surface a clear "changes not sent" error (not a generic snackbar).
   - **Preferred:** persist a per-group `pendingMetadataResend` marker (new nullable column, see below) holding the signed `sysText` + recipient set, surface a persistent "changes not yet sent to members — retrying" banner, and re-attempt on the next foreground / `rejoinGroupTopics` tick. This preserves the admin's edit while honestly reflecting that members haven't received it.

**DB/migration impact (preferred path only):** a new migration adding a nullable `pending_metadata_resend` blob column (or a small `pending_group_broadcasts` table keyed by `groupId`) under `lib/core/database/migrations/`. Follows the existing migration pattern (next version after current `005`). No wire change — the stored payload is the already-signed `sysText`.

### 4. Deterministic tie-breaker for equal/skewed membership versions (large)

Two complementary mechanisms in `group_membership_event_watermark.dart` + the role use case + the listener:

1. **Sender monotonicity.** When minting a membership/role event version under the mutation lock, advance to `max(DateTime.now().toUtc(), lastMembershipEventAt + 1µs)` so two rapid local mutations always produce strictly increasing versions. Implement as a helper, e.g.:
   ```dart
   DateTime nextMembershipEventAt(DateTime? lastMembershipEventAt) {
     final now = DateTime.now().toUtc();
     final last = lastMembershipEventAt?.toUtc();
     if (last != null && !now.isAfter(last)) {
       return last.add(const Duration(microseconds: 1));
     }
     return now;
   }
   ```
   Call this inside the now-locked role use case (Improvement 1) and at the add/remove mint sites.

2. **Tie-breaker on compare.** Extend the stale check to a `(eventAt, sourceEventId)` tuple so two *distinct* events at the same instant are ordered deterministically instead of conflated:
   ```dart
   bool isStaleGroupMembershipEvent({
     required DateTime eventAt,
     DateTime? lastMembershipEventAt,
     String? eventId,
     String? lastEventId,
   }) {
     final current = lastMembershipEventAt?.toUtc();
     if (current == null) return false;
     final at = eventAt.toUtc();
     if (at.isAfter(current)) return false;
     if (at.isBefore(current)) return true;
     // equal instant: deterministic tie-break by event id
     if (eventId != null && lastEventId != null) {
       return eventId.compareTo(lastEventId) <= 0;
     }
     return true; // no id available → preserve current strict-stale behaviour
   }
   ```
   The receiver's `_shouldIgnoreStaleMembershipEvent` (`group_message_listener.dart:4245`) and the watermark store must then persist the winning `sourceEventId` alongside `lastMembershipEventAt`.

**DB impact:** persisting the watermark's tie-break `sourceEventId` needs a nullable `last_membership_event_id` column (migration). **Wire impact:** none new — `sourceEventId` is already minted and shipped (`group_info_wired.dart:1162`–`:1163`); this change *consumes* it for ordering. Because this touches the watermark contract on both sender and receiver, it is the highest-risk item and should land last, after 1–3 stabilize.

### 5. (Low) In-session config-sync retry + user signal (medium)

On `_syncGroupConfig` (`group_message_listener.dart:4942`–`5001`) returning `false`, persist a per-group pending-config-resync marker (can reuse the `pending_group_broadcasts` table from Improvement 3) and re-attempt the validator update on the next listener tick / app foreground / `rejoinGroupTopics`, rather than only at the next app restart. (The current `GROUP_MESSAGE_LISTENER_CONFIG_UPDATE_RETRY_FAILED` emission at `:4991` is log-only and does **not** create a durable retry marker.) Optionally surface a transient "reconnecting group" indicator. This narrows the existing self-heal window (currently bounded by `rejoin_group_topics_use_case.dart:131`–`139`) from "next restart" to "next tick" and makes the drift visible.

---

## Affected files & components

| File | Change |
|------|--------|
| `lib/features/groups/application/update_group_member_role_use_case.dart` | Wrap in `runGroupMembershipMutationLocked`; reload inside lock; add `isStaleGroupMembershipEvent` gate; mint version via `nextMembershipEventAt` (Improvements 1, 4). |
| `lib/features/groups/application/group_message_listener.dart` | **Receive-side metadata watermark gate in `_applyAuthoritativeGroupConfigSnapshot` (`:4663`, gated `updateGroup` `:4825`–`:4852`) — DONE in `74e8436c`.** Remaining: tie-breaker in `_shouldIgnoreStaleMembershipEvent` (`:4245`); in-session config-sync retry at `_syncGroupConfig` callers (`:3097`, `:3482`, `:3719`, `:3794`) (Improvements 4, 5). |
| `lib/features/groups/application/group_config_payload.dart` | Optional `includeVisibleMetadata` mode for membership/role snapshots (Improvement 2, stronger variant). |
| `lib/features/groups/application/update_group_metadata_use_case.dart` | Return pre-edit snapshot / add post-persist compensation hook (Improvement 3). |
| `lib/features/groups/presentation/screens/group_info_wired.dart` | Wrap publish+inbox in try/catch with revert or pending-resend; mint role version via `nextMembershipEventAt` (`:1118`, `:1586`–`1701`) (Improvements 3, 4). |
| `lib/features/groups/application/group_membership_event_watermark.dart` | `nextMembershipEventAt` helper; `(eventAt, eventId)` tuple comparison (Improvement 4). |
| `lib/features/groups/application/add_group_member_use_case.dart`, `remove_group_member_use_case.dart` | Adopt `nextMembershipEventAt` at mint sites; persist tie-break event id (Improvement 4). |
| `lib/core/database/migrations/` + group repository | New nullable column(s): `pending_metadata_resend` / `pending_group_broadcasts` table, `last_membership_event_id` (Improvements 3, 4, 5). |
| `lib/features/groups/application/rejoin_group_topics_use_case.dart` | Drain pending-resend / pending-config-sync markers on rejoin (Improvements 3, 5). |

---

## Test & verification strategy

### Unit (each affected use case already has a sibling test file)

- `test/features/groups/application/update_group_member_role_use_case_test.dart` — add cases: (a) concurrent role + add/remove on the same `groupId` serialize (assert via an injected delay in the DB helper that the second mutation observes the first's committed state); (b) a stale `eventAt` (older than `lastMembershipEventAt`) throws `staleGroupMembershipEventMessage` and emits no `callGroupUpdateConfig`; (c) no-op short-circuit still works inside the lock.
- `test/features/groups/application/update_group_metadata_use_case_test.dart` + a `group_info_wired` widget/unit test — publish failure reverts local metadata (or writes a pending-resend marker) and the optimistic timeline message is removed.
- `test/features/groups/application/` (watermark) — new `group_membership_event_watermark_test.dart` cases: `nextMembershipEventAt` returns `last + 1µs` when `now <= last`; `isStaleGroupMembershipEvent` tie-breaks equal instants by `eventId` deterministically and symmetrically (winner on one side == loser on the other).
- `group_message_listener` receive tests — a `member_role_updated` snapshot carrying a *stale* `metadataUpdatedAt` does **not** change `name`/`description`/`avatar*` and does **not** regress `lastMetadataEventAt`, while the role delta **is** applied; a *newer* snapshot does apply metadata.

### Integration harness (`integration_test/`)

- `group_admin_metadata_convergence_simulator_test.dart` — extend with the "name flips back and forth" scenario: Admin A renames, Admin B (pre-rename) toggles a role; assert all peers converge on A's name **and** B's role change. This harness is the natural home for Improvement 2.
- `group_multi_device_real_harness.dart` / `group_multi_party_device_real_harness.dart` — concurrent role toggles from two admins; assert all devices converge on the same admin set (Improvement 1 + 4).
- `group_recovery_e2e_test.dart` — metadata edit during simulated relay outage; assert revert-or-pending behaviour and eventual delivery on reconnect (Improvement 3 + 5).

### Test-Flight-Improv matrices

- `Test-Flight-Improv/56-deterministic-remove-vs-send-boundary.md` — directly adjacent; extend its determinism gates to cover role-vs-role and role-vs-metadata boundaries.
- `Test-Flight-Improv/65-same-user-multi-device-group-convergence.md` — same-user two-device rapid role toggles (the realistic single-actor trigger for Improvement 4).
- `Test-Flight-Improv/59-post-creation-admin-role-management.md` and `60-post-creation-group-metadata-editing.md` — add convergence/rollback regression rows.
- Record device-matrix runs per `Test-Flight-Improv/test-gate-definitions.md`; the two-admin concurrent path needs a real two-device run (simulator clocks are too tightly synced to exercise the skew case — set deliberate clock offset or inject `eventAt` to force the equal/inverted-timestamp path).

### Device matrix

Use the documented devices (iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`). The two-admin concurrent role/metadata scenarios specifically need cross-device clock skew, which only the real-device matrix exercises faithfully.

---

## Risks, trade-offs & rollout

| Risk | Mitigation |
|------|------------|
| Adding the lock to role updates could surface ordering bugs masked today (e.g. UI assuming immediate apply). | The lock is already battle-tested by add/remove; reuse the identical pattern and keep the no-op short-circuit. Land behind the existing flow-event logging to watch for new `STALE_EVENT` emissions. |
| Stricter metadata gating (Imp. 2, shipped receive-side guard) could *suppress* a legitimate metadata change that legitimately rides a membership event. | Metadata is supposed to flow via `group_metadata_updated`; the membership snapshot is meant only to carry member/role deltas. The shipped guard uses **newer-or-equal** (`!isBefore`), so equal-instant repairs still land, subsuming the `_metadataReplayRepairsVisibleFields` repair path. Validated by the receive-side gate (`group_message_listener.dart:4778`–`:4793`); re-validate with the convergence harness. |
| Excluding visible metadata from snapshots (Imp. 2 strong variant) is a wire-shape change. | Gate behind `schemaVersion`; keep receivers tolerant of both full and trimmed snapshots; do not remove the receive-side guard until all peers ship trimmed snapshots. |
| Tie-breaker watermark change (Imp. 4) alters the ordering contract on both ends — a partial rollout could *invert* winner/loser between old and new clients. | Land sender monotonicity (`nextMembershipEventAt`) first (backward-compatible, only ever increases versions). Ship the tuple comparator with a null-safe fallback to today's strict-stale behaviour when `eventId` is absent, so mixed-version groups degrade to current behaviour rather than mis-order. |
| New DB columns/tables. | Standard nullable additions following the existing migration chain; idempotent; no secret-column constraints affected. |

**Rollout order:** (1) role lock + stale gate → ship and observe; (2) metadata regression guard — **receive-side guard already shipped in `74e8436c`; only the strong send-side variant remains**; (3) metadata atomicity/rollback; (4) tie-breaker (sender monotonicity first, then comparator); (5) in-session config-sync retry. Items 1–2 deliver most of the trust win at low risk and need no wire changes (the receive-side half of 2 is done).

---

## Effort estimate

| Improvement | Effort | Wire/DB/migration |
|-------------|--------|-------------------|
| 1. Role lock + stale gate | **Small** (~0.5 day) | None |
| 2. Stop membership snapshot metadata regression (receive guard) | **DONE** (`74e8436c`, 2026-06-03) — strong send-side variant still open | None (strong variant: wire-shape change) |
| 3. Atomic metadata edit + rollback/pending-resend | **Medium** (~1.5–2 days) | DB migration (pending-resend) for preferred path |
| 4. Deterministic equal-timestamp tie-breaker | **Large** (~2.5–3 days) | DB migration (`last_membership_event_id`); ordering-contract change |
| 5. In-session config-sync retry + UI signal | **Medium** (~1 day) | Reuses pending-broadcast table |

**Theme total:** ~6.5–8 days. The role lock+stale-gate (Improvement 1) is the small, high-value first cut and should land independently and immediately.
