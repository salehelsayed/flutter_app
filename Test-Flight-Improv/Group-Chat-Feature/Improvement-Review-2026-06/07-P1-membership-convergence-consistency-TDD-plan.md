> TDD implementation plan for **[07-P1 Make membership/role/metadata converge consistently](./07-P1-membership-convergence-consistency.md)** · Priority **P1**
> Generated 2026-06-16 against branch `124-harness-refactor` (working tree, DB **v80**). 13-agent graph-first verify+refute pass — every claim re-confirmed against live source; the review doc's line numbers are uniformly stale and are corrected below.

---

# 07-P1 Membership Convergence — TDD Plan

## 0. Verification verdicts (what actually ships)

| # | Improvement | Review status | **Verified verdict** | This plan |
|---|-------------|---------------|----------------------|-----------|
| 1 | Lock + stale-gate the role update | open, small/high-value | **CONFIRMED_OPEN** — role use case has neither lock nor stale gate; Dart-only, no migration | **S1** (with monotonicity) |
| 2-recv | Receive-side metadata-regression guard | DONE (`74e8436c`) | **ALREADY_DONE** — present, correct, locked by 2 tests | **DROP** |
| 2-send | Trim visible metadata from snapshots at source | open (strong variant) | **CONFIRMED_OPEN but fix unsound as scoped** — flat trim breaks new-joiner metadata + join handshake; marginal value over shipped guard | **DEFER** (§6) |
| 3 | Atomic metadata edit + rollback / pending-resend | open | **CONFIRMED_OPEN + wider** — also a *false-success* on soft publish failure the review missed | **S2** |
| 4 | Deterministic equal/skew tie-breaker | open, large | **CONFIRMED_OPEN but partly mis-scoped** — `eventId` ≡ `eventAt` µs (no same-sender tie-break); synthesized fallback id non-deterministic | **S3** |
| 5 | In-session config-sync retry + signal | open, low | **CONFIRMED_OPEN, overstated** — self-heal already runs on resume/watchdog; members-added path fully silent | **DEFER** + tiny S1b slice (§6) |

**Landing order:** `S1` → `S2` → `S3`. Each ships and is observed before the next. `S1` is the small high-value first cut; `S3` (the watermark ordering-contract change + migration) is highest-risk and lands last, exactly as the review recommends.

---

## 1. Corrected source anchors (review doc lines are stale)

All paths are working-tree-verified. `group_info_wired.dart` lives under `presentation/screens/` (the doc drops `/screens/`).

**`lib/features/groups/application/group_membership_event_watermark.dart`** (69 lines)
- `_groupMembershipMutationLocks` map :5 · `runGroupMembershipMutationLocked<T>` :7-36 · `isStaleGroupMembershipEvent({eventAt, lastMembershipEventAt})` :38-44 (stale iff `!eventAt.isAfter(current)` → **equal = stale**) · `recordGroupMembershipEventWatermark` :46-69 (persists **only** `lastMembershipEventAt`, monotonic-down guard :60-68). **No `nextMembershipEventAt` exists anywhere.**

**`update_group_member_role_use_case.dart`** (201 lines) — *no lock, no stale gate*
- recovery check :38-47 · `getGroup` :49 · self `getMember` :54 · `canApplyGroupMemberRoleUpdate` :87-106 · no-op short-circuit :108-121 · `getMembers` (last-admin math, **outside any lock**) :123 · last-admin throw :142 · `normalizedEventAt = eventAt?.toUtc() ?? now` :149 · `updateMemberRole` :151 · `myRole` update :152-154 · `try {` :156 · `callGroupUpdateConfig(... configVersionOverride: normalizedEventAt)` :158-166 · `recordGroupMembershipEventWatermark` :167-171 · `catch` revert :184-200 (rethrows :199).

**`add_group_member_use_case.dart`** — lock :157 · stale gate :269 · throw :282 · watermark :357 · mint `eventAt = memberToAdd.joinedAt` :268.
**`remove_group_member_use_case.dart`** — lock :77 · `isDissolved` throw :85-87 · stale gate :109 · throw :124 · `buildGroupConfigPayload` :207 · `callGroupUpdateConfig` :214-218 · watermark :219-223 · `catch` revert :224-240 (`saveMember` :225, `deleteMessage` :226-228).
- ⚠ **`staleGroupMembershipEventMessage` and `groupMembershipMutationDissolvedMessage` are each declared TWICE** — add :26/:28 and remove :18/:20 — with no canonical home. Harnesses already `import ... hide staleGroupMembershipEventMessage` to dodge the ambiguous export (`group_multi_party_device_real_harness.dart:23`).

**`update_group_metadata_use_case.dart`** (90 lines) — `BeforePersistGroupMetadataUpdate` typedef :8-9 · `group` loaded :43 · build `updated` :69-76 · `beforePersist?.call` :77 · `groupRepo.updateGroup(updated)` :78 · `return updated` :89. **No publish, no try/catch, no revert, no lock, no watermark.**

**`group_info_wired.dart` (presentation/screens/)** — `_applyMetadataEdit` :1490 · `hasMetadataChanges` 1498-1506 · `changedAt = now` :1508 · `updateGroupMetadata(...)` 1575-1667 (beforePersist closure 1584-1666; avatar commit/delete 1647-1662) · optimistic `metadataTimelineMessage` built 1674-1679 (declared **inside** try) · `msgRepo.saveMessage` :1682 · `callGroupPublish` 1687-1700 (**return discarded**) · recipients gate :1706 · `buildGroupOfflineReplayEnvelope` :1719 · `callGroupInboxStore` 1734-1740 · `sendGroupMembershipUpdateDirect` (unawaited) :1746 · success snackbar 1774-1780 · `catch` 1781-1802 (emit `GROUP_INFO_FL_METADATA_UPDATE_ERROR` 1782-1791, snackbar 1797-1800, `_loadGroupInfo()` :1801). `_loadGroupInfo` 129-160 (`getGroup` :135, `setState _group` :156).
- Role mint: `changedAt = now` :1219 · `sourceEventId = 'member_role_updated:$gid:$peerId:${changedAt.microsecondsSinceEpoch}'` 1263-1264 · `eventAt: changedAt` :1271 · sign :1265 · publish :1303. `_buildGroupConfig` 1968-1973 → `buildGroupConfigPayload(group, members)` :1972.

**`group_config_payload.dart`** — `buildGroupConfigPayload` 31-62 (visible metadata `name/groupType/description/avatarBlobId/avatarMime/metadataUpdatedAt` :42-47, `configVersion` :48, `members` :49-51, `stateHash` 55-61) · `buildGroupConfigStateHash` 410-419 · `_canonicalGroupConfigForHash` (**fixed field set incl. all visible metadata**) 578-606 · `isGroupConfigStateHashValid` (tolerant of absent hash :426; recompute-and-compare else) 421-434 · `_groupConfigVersion` 565-576. **No `schemaVersion` field on the config payload** (only `configVersion` ISO ts + `stateHash`).

**`group_message_listener.dart`** (working-tree dirty: one unrelated F8-dedup hunk at :924, disjoint from everything here)
- `_applyAuthoritativeGroupConfigSnapshot` :4896 · member loop (**always applied**) 4938-4991 · `currentMetadataWatermark` :5011 · `appliesMetadataFields = ...|| !resolvedMetadataUpdatedAt.isBefore(watermark)` 5012-5015 · `STALE_CONFIG_METADATA_FIELDS_IGNORED` emit 5016-5026 · gated `updateGroup` 5058-5085 · avatar gating 5037-5056/5088-5092.
- `_shouldIgnoreStaleMembershipEvent` 4478-4525 (`return false` if after watermark :4491; `_membershipAddAdvancesLocalMember` escape 4495-4506; `allowEqualVersionReplay` escape 4508-4512) · `_membershipAddAdvancesLocalMember` :4527 · `_resolveIncomingMembershipVersion` → `({eventAt, hasConfigVersion})` 4383-4398 (**no eventId**) · `_resolveMembershipEventWatermark` 4753-4780.
- Dispatch: `member_added` :1926 (`allowEqualVersionReplay:true`) · `members_added` 1972/1974 (`allowEqualVersionReplay:true`) · `member_role_updated` 2078/2080 (**no** allowEqual) · dissolve 2106-2114/2109 (gate before stale check) · `group_metadata_updated` 2125/2127 (uses `_shouldIgnoreStaleMetadataEvent`).
- `transitionSourceEventId` 1747-1751 (⚠ **falls back to** `system:$gid:$sender:$type:$ts:${jsonEncode(parsed)}` when audit id absent — non-canonical/device-local).
- `_syncGroupConfig(groupId, groupConfig, {emitFailureEvent=false})` 5175-5234 (`callGroupUpdateConfig` :5202, retry :5214, `CONFIG_UPDATE_RETRY_FAILED` 5221-5229, `return false` :5231). Sync sites: `_handleMemberAdded` :2903 **(silent)** · `_handleMembersAdded` :3040 **(silent)** · `_handleMemberJoined` :3285 · `_handleMemberRemoved` :3715 · `_handleMemberRoleUpdated` :3952 · `_handleGroupMetadataUpdated` :4027.

**`signed_group_transition_audit.dart`** — `requiresSignedGroupTransitionAudit` (covers member_added/members_added/member_removed/member_role_updated/group_dissolved/group_metadata_updated) 55-66 · `sourceEventId` in signed payload :130 and container :161 · `signedGroupTransitionAuditSourceEventId` 274-284 · `buildGroupSystemTransitionSubject` 305-372 (`groupConfigHash` via `_groupConfigHash` :342-344) · `_groupConfigHash` (reads embedded `stateHash`) 507-516 · `buildGroupTransitionStateHash` (preTransitionStateHash; includes `group.name` from **local DB**, not payload; no description/avatar) 412-446.

**Self-heal / drain wiring** — `rejoin_group_topics_use_case.dart`: `getMembers` :129, `buildGroupConfigPayload` :131, `callGroupJoinWithConfig` 133-139. Triggered from `handle_app_resumed.dart` :212/:300 (resume) and `main.dart:2446` (recovery watchdog) — **not restart-only**.

---

## 2. Migration & sequencing strategy

- Working-tree DB version = **80**; migrations `078_group_pending_key_distributions` / `079_message_dedup_key` / `080_group_pending_key_repairs_status_index` are **all taken** by concurrent in-flight work. **Next free = 081.**
- This plan owns **two** migrations, assigned within the plan:
  - **`081_group_pending_broadcasts`** — S2 preferred path (durable metadata-resend; also the table S5 would reuse if it were in-scope).
  - **`082_groups_last_membership_event_id`** — S3 tie-break id column.
- ⚠ **At landing, re-check `app_database_version.dart` and `ls migrations/`.** Other uncommitted clusters (self-heal, 03 removal-rotation, F8 dedup) share this tree; if any bumps past 080 first, shift 081/082 up and update `main.dart` migration wiring + `full_migration_chain_test.dart` (imports 048 @ :47, 080 @ :77) accordingly.
- S1 is **Dart-only, zero migration** (`last_membership_event_at` col already exists, migration 048).

---

## 3. Slice 1 — Role lock + stale gate + sender monotonicity *(small, high value, no migration)*

Combines review **Imp 1** with the **sender-monotonicity half of Imp 4**. They are bundled deliberately: adding a stale gate to the role path *without* monotonic minting introduces a **self-block** — a legitimate local role toggle whose `DateTime.now()` is `≤` a watermark previously advanced by a clock-skewed remote event would throw `staleGroupMembershipEventMessage` and silently fail. Minting `eventAt` via `nextMembershipEventAt(reloadedWatermark)` inside the lock closes that window.

### 3.1 RED — write these first
New cases in `test/features/groups/application/update_group_member_role_use_case_test.dart` (mirror existing precedents; the file uses `FakeBridge` + `InMemoryGroupRepository`):
1. **Stale role event rejected before any write/send** — seed `group.lastMembershipEventAt` to a future instant, call with an older/equal `eventAt`; assert `throwsA(isStateError w/ staleGroupMembershipEventMessage)`, `bridge.commandLog` contains **no** `group:updateConfig`, and target role unchanged. (Mirror remove `G3-006` @ remove_test:427 / add `G3-006` @ add_test:968.)
2. **Concurrent role + add/remove serialize** — mirror add `G3-007` @ add_test:1005: inject a delay in a repo helper, fire role + remove on the same `groupId`, assert the second observes the first's committed state (no lost update on the admin-count math).
3. **No-op short-circuit still returns early *inside* the lock** — `targetMember.role == role` returns before any send (currently :108-121).
4. **Monotonic mint** — when `now ≤ lastMembershipEventAt`, the recorded watermark and the `configVersionOverride`/`sourceEventId` are `lastMembershipEventAt + 1µs`, and the call still sends (not stale against itself).

New `test/features/groups/application/group_membership_event_watermark_test.dart` (**file does not exist yet**):
5. `nextMembershipEventAt(last)` returns `now` when `now > last`; returns `last + 1µs` when `now == last` and when `now < last`; returns `now` when `last == null`.

### 3.2 GREEN — implementation
In `group_membership_event_watermark.dart`, add:
```dart
DateTime nextMembershipEventAt(DateTime? lastMembershipEventAt, {DateTime? now}) {
  final candidate = (now ?? DateTime.now()).toUtc();
  final last = lastMembershipEventAt?.toUtc();
  if (last != null && !candidate.isAfter(last)) {
    return last.add(const Duration(microseconds: 1));
  }
  return candidate;
}
```
(Inject `now` so test #5 is deterministic — there is no clock seam otherwise.)

Rewrite `updateGroupMemberRole` body to mirror add/remove:
```dart
await runGroupMembershipMutationLocked<void>(
  groupId: groupId,
  action: () async {
    final group = await groupRepo.getGroup(groupId);            // reload INSIDE lock
    if (group == null) throw StateError('Group not found: $groupId');
    if (group.isDissolved) throw StateError(groupMembershipMutationDissolvedMessage); // see note
    // self/target getMember, canApplyGroupMemberRoleUpdate, no-op short-circuit,
    // getMembers + last-admin math — ALL moved inside the lock (serialized reads)
    final eventAt = nextMembershipEventAt(group.lastMembershipEventAt, now: providedEventAt?.toUtc());
    if (isStaleGroupMembershipEvent(eventAt: eventAt, lastMembershipEventAt: group.lastMembershipEventAt)) {
      emitFlowEvent(layer: 'FL', event: 'GROUP_UPDATE_MEMBER_ROLE_USE_CASE_STALE_EVENT', details: {...});
      throw StateError(staleGroupMembershipEventMessage);
    }
    await groupRepo.updateMemberRole(...);                       // existing optimistic write
    try {
      await callGroupUpdateConfig(... configVersionOverride: eventAt);
      await recordGroupMembershipEventWatermark(groupRepo: groupRepo, groupId: groupId, eventAt: eventAt);
    } catch (e) { /* existing revert :184-200, now INSIDE the lock */ rethrow; }
  },
);
```
- Leave `isGroupRecoveryInProgress()` (:38-47) **outside** the lock — matches add :146-155 / remove :63-75.
- Constant import: reference `staleGroupMembershipEventMessage` + `groupMembershipMutationDissolvedMessage`. **REFACTOR step (recommended):** move both constants to their natural home, `group_membership_event_watermark.dart`, re-export from add/remove for compat, and drop the `hide staleGroupMembershipEventMessage` directives in the two device harnesses (`group_multi_party_device_real_harness.dart:23` and sibling). Minimal alternative if you want zero harness churn: import from `remove_group_member_use_case.dart` only (single source, no ambiguity).

### 3.3 Notes / invariants
- **Gate semantics must match remove exactly** (`isStaleGroupMembershipEvent`, equal = stale, thrown *before* the bridge send) so `ML-020` (test:682-733, two strictly-ascending `eventAt`s) and the `group:updateConfig`-asserting happy-path tests (:134-163) stay green **unmodified**. Verified: no existing role test seeds a non-null `lastMembershipEventAt`, so none flips RED.
- `BB-013` (test:165-187, timeout-rolls-back) stays green only if the revert stays **inside** the locked action body.
- **isDissolved guard** is not part of review Imp 1, but the role path lacks one that add/remove have; reloading inside the lock makes it a free, correct addition. Include it (scoped + tested) — flag in the PR.
- **Scope honesty:** `updateGroupMemberRole` has exactly one production caller (`group_info_wired.dart:1234`, local admin UI). Incoming *remote* role deltas converge via `_applyAuthoritativeGroupConfigSnapshot` + the listener's own membership watermark, **not** this use case. S1 governs the local **send** path only; cross-device convergence on concurrent toggles needs S3. Do not oversell S1 as a convergence fix.

### 3.4 Gates
`flutter analyze` 0 new · role use-case suite green · `group_membership_event_watermark_test.dart` green · full groups/application suite green (`-j 1` if the shared-gate flake bites). No device run required (in-memory serialization + existing column).

---

## 4. Slice 2 — Atomic metadata edit (rollback + false-success fix + durable resend)

Review **Imp 3**, expanded. The adversarial pass found a **second, worse failure mode the review missed**: `callGroupPublish` (`bridge_group_helpers.dart:374-401`) does **not** throw on a soft failure — on timeout it returns `{'ok':false,'errorCode':'BRIDGE_TIMEOUT'}` — and `group_info_wired.dart:1687-1700` **discards the return value**. So a publish timeout never reaches the `catch`; the flow shows the **success** snackbar (`group_info_details_updated` :1774-1780) while peers received nothing. The review's "revert in the catch" fixes only the hard-throw path (inbox-store throw / `bridge.send` throw).

Two distinct divergences to close:
- **Hard throw** (`callGroupInboxStore` ok≠true / send throw) → error snackbar + local DB stuck applied.
- **Soft fail** (`callGroupPublish` ok:false / timeout) → **false success** + local DB stuck applied.

### 4.1 S2a — revert + honest failure *(no migration; the floor)*

**RED** (`test/features/groups/presentation/group_info_wired_test.dart`; reuse `_openGroupDetailsEditor` :419 / `_tapGroupEditSave` :432 / `_groupEditNameField` :349; FakeBridge seeds `group:publish:{ok:true}` @ :735-737):
1. **Hard-throw revert** — make `group:inboxStore` throw; assert `getGroup` retains the **old** name/description/avatar, `msgRepo` has **no** `group_metadata_updated` timeline card, error snackbar shown.
2. **Soft-fail false-success** — seed `group:publish:{ok:false}` (or `BRIDGE_TIMEOUT`); assert it does **not** show the success snackbar and reverts. (This test is RED today — current code false-succeeds.)
3. **Monotonic-revert guard** — if a newer remote `group_metadata_updated` (higher `lastMetadataEventAt`) landed between persist and failure, the revert must **not** clobber it (revert only if the persisted value still equals what we wrote).

**GREEN** — in `_applyMetadataEdit`:
- Capture `preEditGroup = _group` **before** `updateGroupMetadata`. Hoist the `metadataTimelineMessage` id to an outer nullable (it's currently declared inside the try at :1674, invisible to the catch).
- Check `callGroupPublish` `ok`: treat `ok:false`/timeout as failure (route into the same path as a throw).
- On failure: revert `groupRepo.updateGroup(preEditGroup)` **iff** still-equal (monotonicity guard), `msgRepo.deleteMessage(metadataTimelineMessage.id)` (precedent: remove_use_case:226-228), restore the avatar file/blob committed in `beforePersist` (commit/delete @ 1647-1662 — see residual), and show an explicit **"changes not sent"** error (not the generic snackbar).

⚠ **Avatar residual:** `beforePersist` commits the avatar to disk + uploads the blob before publish. A GroupModel-only revert leaves the avatar file diverged. S2a must snapshot the prior avatar path/blob and restore it, or the scope must explicitly document the avatar-file divergence as an accepted residual. Prefer restore.

### 4.2 S2b — durable pending-resend *(migration 081, preferred)*

**RED** — new repo/helper test + a drain test in `rejoin_group_topics_use_case_test.dart`: on broadcast failure a `pending_group_broadcasts` row is written holding the **already-signed** `sysText` + recipient set + original `eventAt`; the row is drained on the next rejoin/foreground, re-pushes via the bridge, clears on success, and is retained (idempotent, no duplicate push) on repeat failure. Banner state ("changes not yet sent — retrying") is set while a row exists.

**GREEN**
- **Migration `081_group_pending_broadcasts`** — clone the `072_group_pending_membership_messages` idiom: `CREATE TABLE IF NOT EXISTS pending_group_broadcasts(id PK, group_id, kind TEXT, payload_json TEXT NOT NULL, recipient_peer_ids TEXT, event_at, created_at, updated_at)` + UNIQUE partial index for dedup + `emitFlowEvent` START/SUCCESS/ERROR. A **table** (not a GroupModel column) — row-per-broadcast, reuses the dedup idiom, avoids `GroupModel.copyWith/fromMap/toMap` churn. Bump `currentIdentityDatabaseVersion` 80→81; register in `main.dart`; add the import to `full_migration_chain_test.dart`.
- DB-helpers → repository → drain runner. **Wire drain via a process-wide sink** (mirror `GroupPendingKeyDistributionRunner` / `setDeferredGroupKeyDistributionSink` from the 03 work) hooked into `rejoinGroupTopics` + app-resume — **do not** thread DI through the wired widget.
- **Drain rebuilds from the stored signed payload but must respect `lastMetadataEventAt` monotonicity** (re-use the original `eventAt`, never re-stamp `now`) so a retry can't resurrect stale metadata the receive-side guard (74e8436c) suppresses, and can't fight a newer remote state.

### 4.3 Gotchas / invariants
- `update_group_metadata_use_case` currently bypasses both the mutation lock and the watermark. If S2b adds a drain, consider serializing the metadata mutation under `runGroupMembershipMutationLocked` to avoid lost-update races with concurrent membership mutations on the same Group row (verify no starvation — the lock is per-group).
- Existing use-case test `'updates name, description, avatar metadata, and watermark'` (:39) asserts forward persistence only — stays green; add the failure-path test alongside (a new RED) only if you move publish into the use case via a callback. The wired-only S2a keeps the use-case signature unchanged (smaller blast radius — recommended).
- `group_test_user.updateMetadata` (convergence harness, ~:395-476) and `FakeGroupPubSubNetwork.publish` never throw today (silent drop) — they cannot exercise the throw path, so integration convergence tests need a **failure-injection** path added before they can cover S2; they will **not** need expectation inversions for S2a.

### 4.4 Gates
`flutter analyze` 0 new · `update_group_metadata_use_case_test` + `group_info_wired_test` green · `081` migration test + `full_migration_chain_test` green · groups integration green · device: metadata edit during simulated relay outage on `group_recovery_e2e_test.dart` asserting revert-or-pending + eventual delivery on reconnect.

---

## 5. Slice 3 — Deterministic tie-breaker *(migration 082, highest risk, lands last)*

Review **Imp 4 Part 2** (Part 1 already shipped in S1's `nextMembershipEventAt`, scoped to role; S3 extends it to add/remove mints). Two adversarial corrections shape the design:

- **`eventId` ≡ `eventAt` microseconds.** Every mint builds `sourceEventId = '<type>:<gid>:<peerId>:${eventAt.microsecondsSinceEpoch}'` (group_info_wired :927/:1264/:1614/:1686, contact_picker :387, create :291, dissolve :89). So for two events from the **same sender at the same instant**, the id is **identical** — the tuple does **not** break that tie. The tuple only disambiguates **different senders / different types**. Same-sender same-instant collisions are fixed by **Part 1 monotonicity (S1)**, not the tuple. State this honestly; don't claim the tuple solves equal-version collisions universally.
- **Synthesized fallback id is non-deterministic.** `transitionSourceEventId` (listener :1747-1751) falls back to `system:...:${jsonEncode(parsed)}` when the audit's `sourceEventId` is absent — device-local, JSON-key-order-dependent. The comparator must tie-break **only on the audit-borne `signedGroupTransitionAuditSourceEventId`** (already parsed at :1748), and fall back to `eventAt`-only when it's absent. Never persist/compare the synthesized fallback.

### 5.1 RED
- `group_membership_event_watermark_test.dart`: tuple comparator — equal `eventAt` + higher `eventId` ⇒ **not** stale; equal `eventAt` + lower/equal `eventId` ⇒ stale; **absent eventId ⇒ falls back to today's strict `!isAfter`** (mixed-version safety); symmetric (winner-on-one-side = loser-on-other).
- `group_message_listener_test.dart`: equal-instant **cross-sender** `member_role_updated` and `group_dissolved` now **converge deterministically** (today dropped at :2080/:2109); and a **terminal `group_dissolved` still wins** regardless of eventId even when `lastMembershipEventAt` is ahead (123/T4 invariant — `reconcile_missed_group_dissolves_use_case_test.dart:418-443`).
- Migration: `082` migration test; `full_migration_chain_test.dart` updated (new import + final-version assertion); `app_database_version.dart` 81→82.

### 5.2 GREEN
- Extend `isStaleGroupMembershipEvent` to `({eventAt, lastMembershipEventAt, String? eventId, String? lastEventId})` — strict `isAfter`/`isBefore` first; on **equal instant**, tie-break by `eventId.compareTo(lastEventId)` **only when both present**, else preserve strict-stale.
- **Migration `082_groups_last_membership_event_id`** — nullable `last_membership_event_id` on `groups`. Add `GroupModel.lastMembershipEventId` using the `_sentinel` triple-state copyWith pattern (group_model.dart:295); update `toMap`/`fromMap`. `recordGroupMembershipEventWatermark` gains an `eventId` param **and** must allow an equal-instant update when the new id out-tiebreaks the stored one (else the winning id never persists on an equal-timestamp upgrade).
- Thread the **audit** `sourceEventId` from `signedGroupTransitionAuditSourceEventId(parsed)` (listener :1748) into `_resolveIncomingMembershipVersion` (extend its record to carry `eventId`), `_shouldIgnoreStaleMembershipEvent`, and `_resolveMembershipEventWatermark`.
- Adopt `nextMembershipEventAt` at add/remove mint sites with **one canonical `(eventAt, eventId)` pair end-to-end** — resolve the add-path mismatch (wire `publishedAt` @ contact_picker:385 vs watermark `joinedAt` @ add_use_case:268) so the persisted `last_membership_event_id` corresponds to the persisted `last_membership_event_at`.

### 5.3 Invariants / out-of-scope
- **Backward-compat (highest risk):** S1 monotonicity is purely additive (only ever increases versions); the tuple comparator degrades to today's behavior when `eventId` is absent. Mixed-version groups thus get current behavior, never mis-ordering. This is why S3 lands last, after S1/S2 stabilize.
- **Preserve terminal dissolve.** The dissolve dispatch checks `alreadyDissolved` **before** the stale gate (:2106-2114); the comparator change must not let an eventId tie-break override a not-yet-applied terminal `group_dissolved`.
- **Metadata is a separate gate/column** (`_shouldIgnoreStaleMetadataEvent` / `last_metadata_event_at`). S3 is membership-only; **do not** extend the tuple to metadata (would need a parallel `last_metadata_event_id`). Metadata convergence is owned by S2 + the shipped 74e8436c guard.
- **RED-lock watch:** `dissolve_group_use_case_test` exact-value `lastMembershipEventAt` asserts (:88/:95, :384/:393), listener role-rollback `:10480-:10534` and `:9968`, and rotate `NW-013` `:704` (reused `eventAt` across retry) all pin `eventAt` values — verify monotonicity adoption at mints doesn't perturb them (most pass an explicit future timestamp with no prior watermark, so they stay green; any that prime a prior watermark go RED and must expect `max(now, last+1µs)`).

### 5.4 Gates
`flutter analyze` 0 new · watermark + listener suites green · `082` + chain tests green · device: two-admin **concurrent role toggle with deliberate clock skew** on `group_multi_party_device_real_harness.dart` (iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`) — simulator clocks are too synced; inject `eventAt` or set a real offset (per `test-gate-definitions.md`).

---

## 6. Deferred (documented, not built this round)

- **Imp 2 send-side trim (`includeVisibleMetadata:false`) — DEFER.** A flat trim at all `buildGroupConfigPayload` sites would **break new-joiner metadata** (the `member_added`/`members_added` snapshot is the *sole* channel of name/description/avatar to a member who joined after the last `group_metadata_updated`; no metadata replay-to-new-joiner exists — locked by `group_admin_metadata_convergence_test.dart` photo-snapshot tests ~:1979 and ~:3691) and **break the join handshake** (`join_group_use_case.dart:96-109` validates name/createdBy/createdAt + stateHash; `group_invite_auth.dart:205` validates stateHash). It would have to be **narrowed to `member_role_updated` + `member_removed` only**, requires **adding a `schemaVersion` to the config payload** (none exists) plus a versioned `_canonicalGroupConfigForHash`, and demands a **multi-release receiver-first rollout** (peers must tolerate both shapes). Given the receive-side guard (74e8436c) already neutralizes the regression, net value is marginal. Revisit only if field evidence shows the wire-borne stale metadata still causes harm on guard-equipped clients. *(The review's "signed-audit folding" blocker is a non-issue — the subject is re-derived from the received payload, so signatures stay self-consistent under trimming.)*
- **Imp 2 equal-instant avatar residual — DEFER.** `_metadataReplayRepairsVisibleFields` (:4847-4865) compares only name+description; an equal-microsecond `group_metadata_updated` that changes *only* the avatar blob (name/desc unchanged, local `avatarPath` present) is dropped. Pathological (equal-µs timestamps); the snapshot path doesn't have it. Defer unless field evidence.
- **Imp 5 durable config-resync marker — DEFER (behind S2's table).** Self-heal already fires on resume (`handle_app_resumed.dart:212/:300`) and the recovery watchdog (`main.dart:2446`), not just cold start — the residual is only "app stays foregrounded one session" + no user signal → genuinely low. The durable half would reuse S2b's `pending_group_broadcasts` (so it can't land standalone), must rebuild config from DB at drain time (not replay a frozen snapshot — else it fights the 74e8436c guard), and must keep the existing `CONFIG_SYNC_FAILED` emission (5 test files depend on the string) while adding the marker (extend `group_message_listener_test.dart:7350`, don't suppress).
  - **S1b (cheap, zero-migration, optional — land anytime):** the two **members-added** sync sites (`_handleMemberAdded` :2903, `_handleMembersAdded` :3040) are **fully silent** (no `emitFailureEvent`, return discarded) — the review wrongly attributed the emit pattern to them. Add `emitFailureEvent:true` + capture + `CONFIG_SYNC_FAILED` so the weakest path is at least observable. Add a sibling to the removed-path test (:7350). No table, no migration.

---

## 7. Cross-cutting invariants (must hold across all slices)

1. **Member-set / role deltas always apply**; only *visible metadata* is ever conditionally preserved (already true on receive — 74e8436c).
2. **Watermarks never regress** (`lastMembershipEventAt`, `lastMetadataEventAt`) — except the deliberate equal-instant tuple upgrade in S3.
3. **Terminal `group_dissolved` always wins** when not-yet-dissolved (123/T4) — unaffected by S1/S2/S3 comparator changes.
4. **Mixed-version safety:** every comparator/mint change degrades to current behavior when the new signal (`eventId`) is absent. No wire-shape change in S1–S3 except S2b's stored payload (local-only) — `sourceEventId` already rides the signed audit.
5. **Reverts are monotonicity-guarded** — never clobber a concurrently-arrived newer remote state.
6. **No new permission-prompt / no secret-column-constraint** impact from migrations 081/082 (standard nullable additions).

---

## 8. Test & device matrix

**Unit** — `update_group_member_role_use_case_test.dart` (S1: stale, serialize, no-op-in-lock, monotonic) · new `group_membership_event_watermark_test.dart` (S1: `nextMembershipEventAt`; S3: tuple) · `update_group_metadata_use_case_test.dart` + `group_info_wired_test.dart` (S2: hard-throw revert, soft-fail false-success, monotonic revert) · `group_message_listener_test.dart` (S3: equal-instant cross-sender convergence + terminal-dissolve preservation; S1b: members-added emit) · migration tests `081_*`, `082_*`, `full_migration_chain_test.dart`.

**Integration (`integration_test/`)** — `group_admin_metadata_convergence_simulator_test.dart`: extend with the "name flips back and forth" scenario (Admin A renames; Admin B pre-rename toggles a role) → converge on A's name **and** B's role (note: the 74e8436c guard already neutralizes this; the scenario proves convergence, not the send-trim). `group_recovery_e2e_test.dart`: S2 relay-outage revert/pending + reconnect delivery.

**Device matrix** (iPhone13 `00008110-…`, Pixel6 `21071FDF600CSC`) — the **two-admin concurrent role/metadata** path (S3) needs **cross-device clock skew**; simulator clocks are too synced. Set a deliberate offset or inject `eventAt` to force the equal/inverted-timestamp path. Record per `Test-Flight-Improv/test-gate-definitions.md`. Adjacent matrices to extend: `56-deterministic-remove-vs-send-boundary.md` (role-vs-role, role-vs-metadata), `65-same-user-multi-device-group-convergence.md` (single-actor rapid toggles), `59`/`60` (rollback regression rows).

---

## 9. Risk & rollout

| Risk | Mitigation |
|------|------------|
| S1 role lock surfaces a UI "assume immediate apply" bug | Lock is battle-tested by add/remove; keep no-op short-circuit; watch new `*_STALE_EVENT` flow emissions. |
| **S1 self-block** (stale gate rejects a valid local toggle) | Bundled `nextMembershipEventAt` mint inside the lock — minted version is always strictly > reloaded watermark. |
| S2 catch-only revert leaves soft publish-fail as false-success | Check `callGroupPublish` `ok`; route soft-fail into the same revert/error path. |
| S2 revert clobbers concurrent newer remote metadata / leaves avatar file diverged | Monotonicity-guarded revert; restore avatar file/blob (or document residual). |
| S3 tuple inverts winner/loser across mixed-version cohorts | Land S1 monotonicity first (additive); tuple null-safe-falls-back to strict `!isAfter` when `eventId` absent. |
| S3 tie-break on non-deterministic synthesized id | Tie-break **only** on audit-borne `sourceEventId`; never the `jsonEncode` fallback. |
| Migration collisions (078/079/080 taken) | Claim 081 (S2b) / 082 (S3); re-check next-free at landing; update `main.dart` + chain test. |

**Rollout:** S1 (ship + observe `STALE_EVENT` emissions) → S2a (revert + false-success fix) → S2b (durable resend, 081) → S3 (tuple + 082, device-skew verify). S1 delivers most of the trust win at low risk with no wire/DB change.

---

## 10. Effort

| Slice | Scope | Effort | Migration |
|-------|-------|--------|-----------|
| S1 | Role lock + stale gate + `nextMembershipEventAt` (role mint) + S1b emit | **Small** ~0.5–1 day | None |
| S2a | Metadata revert + soft-fail false-success fix + avatar restore | **Medium** ~1 day | None |
| S2b | Durable `pending_group_broadcasts` + drain + banner | **Medium** ~1–1.5 days | **081** |
| S3 | Tuple comparator + `last_membership_event_id` + add/remove monotonic mints + device skew | **Large** ~2.5–3 days | **082** |

**Total ~5–6.5 days.** Deferred (Imp 2-send-trim, Imp 5 durable, equal-instant avatar) excluded.

---

### Provenance
13-agent verify+refute workflow (1 infra recon → 6 graphify-explorer verifies → 6 adversarial refutes), all claims re-confirmed against the `124-harness-refactor` working tree on 2026-06-16. Corrections to the source review: Imp 2-recv DROP (done); Imp 2-send fix unsound-as-scoped → DEFER; Imp 3 widened to cover the `callGroupPublish` false-success; Imp 4 `eventId`≡`eventAt`-µs and non-deterministic-fallback findings; Imp 5 members-added-silent + self-heal-already-on-resume.
