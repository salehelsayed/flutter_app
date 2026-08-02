# 326 - Group Roster Convergence

Status: planning-draft — **Stage 1 execution-ready; Stage 2 blocked**
Type: Bug
Spec: free-text intent — deferral C returned to design by plan 323's `/tdd-review` (`wf_d8df3c95-e44`)
Classification: **prerequisite-blocked** — the headline fix cannot ship until a roster-reconciliation channel exists. Two independent defects on the same lines ARE shippable now (Stage 1).
Closure tier: host (Dart feature tier). No relay change, no deploy.

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-02 | Evidence Collector | processor, `group_info_wired.dart`, `apply_on_join_group_config_resync.dart`, `signed_group_transition_audit.dart` | Prune confirmed; no reconciliation exists (audit-rejection event has zero consumers) | Propose config:request reconciliation |
| 2026-08-02 | Planner (verify→refute `wf_9073b40c-853`, 3 agents) | `on_join_group_config_resync_use_case.dart`, `group_config_payload.dart`, `rotate_and_distribute_group_key_use_case.dart`, `group_member.dart`, migrations | **Proposed design REFUTED**; two new independent defects found; 4 candidate designs all partial | Split shippable defects from the blocked one |

## Problem And Evidence

### The headline defect (confirmed, NOT shippable yet)
- **Behavior:** `_applyAuthoritativeGroupConfigSnapshot` hard-deletes every local member absent from a snapshot (`group_message_listener_system_transition_processor.dart:3703-3708` → `removeMember` → `dbDeleteGroupMember`). `pruneOmittedMembers` defaults to `true` (`:3607`); three of six call sites take the default — `:2389` ban, `:2627` role-update, `:2706` metadata-update.
- **Trigger is routine:** a metadata edit builds `groupConfig` from the acting admin's OWN roster (`group_info_wired.dart:1934-1938`), so an admin merely missing a member prunes that member from every receiver. `isGroupConfigStateHashValid` (`group_config_payload.dart:421-433`) only checks self-consistency and cannot detect an omission.
- **Why it matters:** since plan 318 the local roster is the sole custody authority (`send_group_message_use_case.dart:96-125`), so a prune is a custody loss — the member silently stops receiving the group's messages.
- **Why it cannot simply be removed:** the blind prune is currently **the only self-healing path in the system**. A device that missed a `member_removed` re-converges today only because a later snapshot silently deletes the ghost. Remove it and that device is permanently hash-divergent: the roster is a signed-transition hash input (`signed_group_transition_audit.dart:439`, members serialized at `:479-481` via `group_member.dart:556-568`), every audited transition is dropped at `processor:404-410`, and the rejection emits `GROUP_MESSAGE_LISTENER_SIGNED_AUDIT_REJECTED` (`:1257`) which **nothing in `lib/` consumes**. The snapshot relaxation does not rescue it: `_canBootstrapSnapshotBackedSenderDevice` returns `false` whenever the sender's device is already known locally (`:1116-1129`) — it is a device-bootstrap escape, not a roster-divergence escape.
- **Net:** removing the prune trades a silent custody-loss bug for a silent group-freeze bug. Both are bad; the freeze is worse.

### Two independent defects on the same lines (confirmed, SHIPPABLE — Stage 1)
- **S1 — the metadata snapshot RESURRECTS explicitly-removed members.** `:2706` calls `_applyAuthoritativeGroupConfigSnapshot(groupId, groupConfig)` with **neither `eventAt` nor `msgRepo`**, so the member-removed recency guard at `:3660-3671` is inert on that path. A metadata edit from an admin whose roster still contains a removed member re-adds them locally — restoring their custody and their key eligibility. This is the exact mirror of the prune bug and is independent of it.
- **S2 — the truncated roster reaches the Go dial/discovery allow-list.** `:2707` syncs the **author's** config to Go via `_syncGroupConfig` → `callGroupUpdateConfig` (`:3922-3926`), feeding `pubsub.go:2164-2168` / `filterDiscoveredGroupMembers:1999-2007`. So even with the local prune stopped, the author's truncated roster still propagates. The fix already exists and is used exactly this way on the `member_removed` path: `_buildLocalGroupConfigSnapshot` (`:3828-3837`, applied at `:1956-1958`).

### Candidate designs — all four evaluated, none sufficient alone
| Design | Verdict | Killed by |
|---|---|---|
| **D1** — trigger `config:request` on hash mismatch, apply the admin-signed response's roster | **REFUTED** | The response roster is the *same artifact* as the defective snapshot: `on_join_group_config_resync_use_case.dart:90` calls `groupRepo.getMembers(...)` → `buildGroupConfigPayload` (`:112`) — identical to `group_info_wired.dart:1934-1938`. Same function, same omission. Worse: `normalizeGroupConfigMembers` silently drops members failing `hasDeliverableGroupMemberIdentity` (`group_config_payload.dart:77`, `:153-161`), so a responder holding a keyless partial record omits M without ever having lost M. Also: one hard-coded target (the inviter, `:24-46`, sole caller `orbit_wired.dart:1867`), responder must be admin (`:103-110`), and the applier discards anything not strictly newer (`apply_on_join_group_config_resync.dart:134-143`). |
| **D2** — per-member removal guard (compare snapshot `eventAt` to member `joinedAt`) | **REFUTED** | No discriminator exists on the wire. `buildGroupConfigPayload` emits only `metadataUpdatedAt` and `configVersion` (`group_config_payload.dart:41-54`), and a metadata edit sets `lastMetadataEventAt = now` (`group_info_wired.dart:1932`), so `configVersion` always postdates `M.joinedAt` and the rule removes M anyway. Nothing in `member.toConfigJson()` (`group_member.dart:556-568`), the payload, or `group_members` (`migrations/017_groups_tables.dart:34-43`) distinguishes "author removed M" from "author never learned M". |
| **D3** — corroboration / soft-delete (suspected-removed tri-state) | **Sound intent, defeated** | `buildGroupTransitionStateHash` forces a **binary** answer at exactly the moment D3 wants to defer. Include suspects → hash stays divergent → freeze during the corroboration window, which is the window D3 needs to be long. Exclude them → you have performed the prune while pretending not to. Cost anyway: **DB v106** (`app_database_version.dart:23` — next free is 106, not 105) and a tri-state across **66 `getMembers` call sites in 38 files**. |
| **D4** — explicit-removal-only + key gating | **Strongest; right about the write, silent about repair** | Already half-shipped: `member_removed` does explicit removal at `:1936` then `pruneOmittedMembers: snapshotHasNoActiveMembers` (`:1954`); `member_banned` is the same shape at `:2385` with the flag inconsistently omitted at `:2389`. But D4 alone still removes the only self-healing path (see headline). |

- **Key-gating detail (D4's second half, for the blocked stage):** `rotate_and_distribute_group_key_use_case.dart:296` iterates `getMembers`, and the predicate `_deliverableDevicesForRotation` (`:1173-1185`) is **pure roster presence + key material — no recency, no evidence**. A stronger predicate would have to land at **three** sites (`:322`, `:663`/`:688`, `:758`/`:790`) behind the shared mirror `deliverableGroupKeyDevices` (`:1170`, consumed by `group_pending_key_distribution_service.dart:64,71`), or it forks into the "second, drifting definition" the comment at `:1165-1169` warns against.
- **Blast-radius note:** with key gating in place, a ghost's residual leak is a 7-day relay copy and a push wake of **ciphertext under an epoch it does not hold** — metadata, not plaintext. Materially less bad than the inverse failure (a pruned real member gets no custody at all, and the message is invisible to them forever).
- **Existing coverage:** none. `grep -rn pruneOmittedMembers test/` returns nothing. `group_admin_metadata_convergence_test.dart:3502-3606` proves a creator *learns* a member added by a promoted admin; `:3420-3460` exercises a stale **superset** member list. Neither exercises an **omitted** member.
- **Unresolved findings:** **U1 — there is no sound reconciliation channel.** D1 was the obvious candidate and is refuted. Until one is designed, the prune cannot be removed. This is what makes the plan prerequisite-blocked.
- **Affected files:** `group_message_listener_system_transition_processor.dart`; `group_admin_metadata_convergence_test.dart`, `group_message_listener_test.dart`.

## Graph Grounding Snapshot
- Graph fingerprint / freshness: arch graph refreshed 2026-08-02 (`REFRESH_EXIT=0`).
- Query / profile: grounding carried from plan 323's pass plus a dedicated 3-agent verify→refute (`wf_9073b40c-853`).
- Anchors: `_applyAuthoritativeGroupConfigSnapshot`, `buildGroupTransitionStateHash`, `buildGroupConfigPayload`, `_deliverableDevicesForRotation`.
- Surfaced proof/gate files: `group_admin_metadata_convergence_test.dart`, `group_message_listener_test.dart`.
- Graph gaps that required raw source search: the six-site prune census, the Go dial allow-list path, and the state-hash membership serialization.
- Reuse rule: anchors are search starting points; every conclusion is re-verified in current source.

## Scope Contract And Guard

In scope — **Stage 1 only**:
- **S1** pass `eventAt:` and `msgRepo:` at `:2706` so the existing removal guard (`:3660-3671`) stops the metadata path resurrecting explicitly-removed members.
- **S2** route `:2707`'s config sync through `_buildLocalGroupConfigSnapshot` (`:3828-3837`), mirroring `:1956-1958`, so the author's truncated roster stops reaching Go.

Must preserve:
- **The prune stays exactly as it is in Stage 1.** It is the only self-healing path; removing it is Stage 2 and is blocked → TC-326-04 GREEN sentinel.
- The dissolve prune (`:1949`, `pruneOmittedMembers: snapshotHasNoActiveMembers`) → TC-326-05 sentinel.
- Ban and removal still delete their own targets explicitly (`:2385`, `:1936`) → TC-326-06 sentinel.

Hard `Do not`:
- **Do not set `pruneOmittedMembers: false` at any site in Stage 1.** That is the blocked change.
- Do not gate the prune on `appliesMetadataFields` — refuted by plan 323's review (suppresses `:1949` dissolve and `:2389` ban prunes on equal-version events, and is a clock category error: metadata watermark vs `membershipVersion.eventAt`).
- Do not build D1, D2, or D3 as specified (all refuted/defeated above).
- Do not touch the key-rotation predicate in Stage 1 — it belongs with Stage 2's blast-radius reduction.

Deferred / accepted difference:
- **Stage 2 (the headline fix) is deferred pending U1.** Any successor must supply a reconciliation channel that does NOT re-derive the roster from a single peer's `getMembers`, and must keep the state hash stable while it runs.
- Stage 3 (key gating at the three rotation sites) reduces a ghost's blast radius but does not fix custody; deferred with Stage 2.

Dependencies:
- Descends from plan 323 deferral C. No ordering constraint against 322/324/325.

## Test Contract
Zero empty cells. **Stage 1 rows only** — Stage 2/3 have no runnable contract until U1 resolves.

| Case | Behavior | Named test/proof | Tier / fixture | HEAD state → GREEN | Mutation that re-reds | Gate / registration |
|---|---|---|---|---|---|---|
| TC-326-01 | A metadata update does not resurrect an explicitly-removed member | `group_message_listener_test.dart::326 group_metadata_updated does not re-add a member removed by a later member_removed` | unit / fakes + `msgRepo` seeded with a `member_removed` system event newer than the snapshot's `eventAt` | causal RED (HEAD re-adds them: `:2706` passes no `eventAt`/`msgRepo`, so the guard at `:3660-3671` never runs) → member absent after the event; metadata fields still applied | revert `:2706` to the two-argument call → TC-326-01 red | `flutter test test/features/groups/application/group_message_listener_test.dart`; AUTO (`GROUP_TESTS` `:566`) |
| TC-326-02 | The Go config sync carries the LOCAL roster, not the author's truncated one | `group_message_listener_test.dart::326 metadata update syncs the local group config snapshot to the bridge` | unit / fakes + recording bridge | causal RED (HEAD forwards the author's `groupConfig` at `:2707`) → the bridge receives the locally-built snapshot including a member the author omitted | revert `:2707` to the author's config → TC-326-02 red | same as TC-326-01 |
| TC-326-03 | The resurrection guard is relationship-correct, not merely present | `group_message_listener_test.dart::326 an older member_removed does not block a legitimate later re-add` | unit / fakes; removal event OLDER than the snapshot | GREEN sentinel (a genuine re-add must still work) → member present | invert the guard's comparison at `:3667-3669` → TC-326-03 red | same as TC-326-01 |
| TC-326-04 | The blind prune is unchanged in Stage 1 (scope lock) | `group_message_listener_test.dart::326 metadata update still prunes an omitted member (Stage 1 scope lock)` | unit / fakes; snapshot omits a local member | GREEN sentinel (documents today's behaviour so Stage 2 has an explicit RED to flip) → omitted member still removed | set `pruneOmittedMembers: false` at `:2706` → TC-326-04 red, which is the signal that Stage 2 work has begun | same as TC-326-01 |
| TC-326-05 | The dissolve prune still works | `group_message_listener_test.dart::(existing GM-032 sentinel, `:7602`)` | unit / fakes; `members: []` | GREEN sentinel → roster cleared as today | force `pruneOmittedMembers: false` at `:1949` → GM-032 reds | same as TC-326-01 |
| TC-326-06 | Ban and removal still delete their own targets | `group_message_listener_test.dart::(existing ban/removal tests)` | unit / fakes | GREEN sentinel → target removed on both paths | delete `removeMember` at `:2385` → the existing ban test reds | same as TC-326-01 |

### Test Notes
- **TC-326-04 is deliberately a sentinel that documents a bug.** It exists so Stage 2 has a single, named, pre-agreed RED to flip when a reconciliation channel lands — rather than discovering mid-execution that the prune's removal is unpinned. Its cell says plainly that flipping it *is* the Stage 2 signal.
- TC-326-01 must assert the metadata fields still applied, or a fix that skips the whole snapshot would pass for the wrong reason.
- TC-326-02 asserts the *relationship* (the bridge receives a snapshot containing a member the author's config omitted), not merely that some config was sent.
- Fixture reachability: these tests reach `_applyAuthoritativeGroupConfigSnapshot` through the relaxed path, because unit fixtures compute the signed pre-hash from the same fake repo. That is honest for Stage 1 (which does not depend on which path fired) but would NOT be sufficient for Stage 2, whose whole risk is the strict-path freeze.

## Implementation Steps
1. Snapshot `git status --short`. Add TC-326-01..04; confirm 01/02 red for the documented reasons and 03/04 green.
2. **S1** — pass `eventAt: eventAt` and `msgRepo: msgRepo` at `:2706`. Both are already in `_handleGroupMetadataUpdated`'s signature (`:2680-2687`). Stop-if: passing them changes any behaviour beyond the removal guard → stop and re-scope.
3. **S2** — build the local snapshot before syncing at `:2707`, mirroring `:1956-1958`.
4. **Do not touch `pruneOmittedMembers`.**
5. Run focused GREEN → sentinels → graph-affected → the `groups` lane.

## Risks And Blind Spots
- **The headline defect remains open after Stage 1.** State this in the index row; do not let Stage 1's green gates read as "roster convergence fixed".
- S1 activates a previously-inert guard, so a genuine later re-add must still work → TC-326-03.
- Lifecycle / derived-state durability: no persisted schema change in Stage 1; the guard reads existing system-event history.
- Sibling-surface consistency: `:2389` and `:2627` also take the prune default and are **knowingly left alone** in Stage 1 — recorded, not silently skipped.
- Destructive-action side effects: S1 *reduces* a destructive action (stops an unintended re-add); S2 changes what is broadcast to Go, not what is deleted.
- Invariant re-verification under new transitions: the state hash is unchanged by Stage 1 (S1 prevents an addition; S2 changes only what is sent to Go).
- Construction/call-site census: `grep -n '_applyAuthoritativeGroupConfigSnapshot\|pruneOmittedMembers'` → 6 call sites + declaration + use; re-derive at execution, never inherit.
- Build-artifact provenance: N/A — no native artifact.
- Permission/ACL verb symmetry: N/A in Stage 1; Stage 2/3 touch key distribution and must revisit it.

## Rollback
- Stage 1 is client-only, no schema, no wire change: revert = `git revert`. Old and new builds interoperate — S1 only suppresses a local re-add, S2 only changes which config this device sends to its own Go node.

## Gate Cadence
- Per-plan closure (Stage 1): TC-326-01..04 focused + TC-326-05/06 sentinels + the `groups` curated lane.
- Graph-affected first: after the edits, run `tdd_context.py affected lib/features/groups/application/group_message_listener_system_transition_processor.dart --budget 600` and run the named files directly.
- Full `host-all` is **not** a per-plan gate; owned by the notification-reliability wave closure and final rollout.
- Shared tests outside the feature/core globs: N/A.

## Acceptance Gates  (literal — copy/paste, Stage 1 only)
```bash
git status --short

# Causal RED (before edits) — must FAIL for the documented reason
flutter test test/features/groups/application/group_message_listener_test.dart \
  --plain-name '326 group_metadata_updated does not re-add a member removed by a later member_removed'

# Focused GREEN (after the fix)
flutter test test/features/groups/application/group_message_listener_test.dart

# Preservation sentinels
flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart

# Graph-affected dependents BEFORE the lane
python3 graphify-arch/tdd_context.py affected \
  lib/features/groups/application/group_message_listener_system_transition_processor.dart --budget 600

# Curated lane
./scripts/run_test_gates.sh groups

# Registration is grep-verified, never run-verified
grep -c 'test/features/groups/application/group_message_listener_test.dart' scripts/run_test_gates.sh  # expect: 1
./scripts/run_test_gates.sh completeness-check   # expect: PASS, 0 unmatched

# Hygiene
flutter analyze
git diff --check
```

## Execution Interpretation And Done Criteria
- Expected RED: TC-326-01 (metadata update re-adds a removed member), TC-326-02 (the author's truncated config reaches Go).
- GREEN sentinel: TC-326-03 (legitimate re-add still works), TC-326-04 (prune unchanged — Stage 1 scope lock), TC-326-05, TC-326-06.
- Pre-existing dirty tree / known failure: the three user-owned claude-docker files — never staged.
- Environment blocker (NOT a product blocker): none — host-only.
- Scope drift (BLOCKING): any change to `pruneOmittedMembers`; any key-rotation predicate change; any attempt at D1/D2/D3.

- [ ] Every Stage 1 behavior has a named test.
- [ ] Causal RED, focused GREEN, and mutation re-red are recorded.
- [ ] Preservation sentinels and named gates pass with semantic outcomes.
- [ ] Harness registration is implemented AND verified.
- [ ] `flutter analyze` clean; `git diff --check` clean.
- [ ] The index row states plainly that the headline defect remains OPEN after Stage 1.

## Handoff
- First causal RED command: `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name '326 group_metadata_updated does not re-add a member removed by a later member_removed'`.
- Preservation command: `flutter test test/features/groups/integration/group_admin_metadata_convergence_test.dart`.
- Manual registration: none — the touched test files are already in `GROUP_TESTS`.
- Migration: none in Stage 1. (D3, if ever revived, would need **DB v106**.)
- Boundary closure: host-only for Stage 1.
- **Unresolved evidence: U1 — no sound roster-reconciliation channel exists, and D1 (the obvious candidate) is refuted. Stage 2 stays blocked until one is designed.**

## Execution Progress
| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | - | Stage 1 awaiting go-ahead; Stage 2 blocked on U1 | user decision |

## Correction — the broadcast IS the source of truth (user challenge, 2026-08-02, source-verified)

The user challenged the framing above, and the challenge is **correct**. Verified:

- **Voluntary leave broadcasts durably to every remaining member.** `broadcast_voluntary_leave_use_case.dart:209-211` builds `recipientPeerIds` from the remaining roster and `:418-422` calls `callGroupInboxStore(... recipientPeerIds: recipients)` — so offline members get it from the relay inbox, not just live pubsub. Transition type `member_removed` (`:222`, `:234`).
- **Admin removal broadcasts the same event** — `change_group_member_role_and_broadcast_use_case.dart:533` (`eventType: 'member_removed'`).

So roster convergence **does** have a designed primary mechanism, and it is the removal broadcast. The blind snapshot prune is a **backstop**, not the primary path. The earlier framing ("the prune is the only convergence path") was **overstated** and is corrected here.

### The actual gap is narrow and bounded
The broadcast fails to reach a member in exactly two cases, both relay-retention limits (`go-relay-server/inbox.go:30-34`):
1. **Offline longer than 7 days** — `groupMessageTTL = 7 * 24h` expires the event before the member drains it.
2. **More than 500 group messages accumulate after the event** — `maxMessagesPerGroup = 500`, and eviction is oldest-first (`backend_redis.go:672-678`, cap eviction takes from the front), so the leave notice is dropped before newer traffic.

### What this changes about the plan
- **The freeze risk is much smaller than stated.** A diverged device normally re-converges from the next `member_removed` broadcast. The permanent-freeze scenario requires the device to have *also* missed that broadcast — i.e. it must already be in one of the two edge cases above.
- **The prune's problem is its TRIGGER, not its existence.** A backstop for "I missed a removal while offline >7d" is legitimate. What is wrong is that it fires on *every* metadata edit, role change and ban — using a roster that carries no membership authority — rather than only when reconciliation is actually warranted.
- **U1 is therefore narrower than recorded above.** The open question is no longer "design a reconciliation channel from scratch" (one exists: the removal broadcast). It is: *what should the backstop do for a member who was offline past the relay's retention window?* Candidates now worth weighing: bound the prune to genuine membership events; or detect the >7d/>500 condition explicitly and reconcile only then; or accept the gap and let such a device re-derive on rejoin.
- **Stage 1 is unaffected** — S1 (resurrection) and S2 (Go allow-list truncation) remain correct and shippable exactly as written.
