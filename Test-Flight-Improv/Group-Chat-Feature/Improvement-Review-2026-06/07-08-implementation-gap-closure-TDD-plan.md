# 07 + 08 — Implementation/Test Gap-Closure TDD Plan

> Generated 2026-06-17 on branch `124-harness-refactor`. Source: a 6-agent source-level verification of
> [07-P1 membership-convergence](./07-P1-membership-convergence-consistency-TDD-plan.md) and
> [08-P1 invite-join-reliability](./08-P1-invite-join-reliability-TDD-plan.md) against the working tree,
> plus three direct grep confirmations. **Both plans are substantially implemented and host-green.** This doc
> covers only the residuals: genuine gaps (close), hygiene items (close or decide), test gaps (host-only,
> cheap), accepted residuals (leave), and device-gated items (leave).

---

## 0. Verdict snapshot (what actually shipped)

| Plan / Slice | Verdict | Notes |
|---|---|---|
| 07 S1 role lock + stale gate + `nextMembershipEventAt` | ✅ IMPLEMENTED | tests pass, no skips |
| 07 S1b members-added `CONFIG_SYNC_FAILED` emit | ✅ IMPLEMENTED | both sites + listener test |
| 07 S2a metadata revert + soft-fail false-success fix | ✅ IMPLEMENTED | **avatar file-restore = documented residual (G7)** |
| 07 S2b durable `pending_group_broadcasts` (mig **086**) | ✅ IMPLEMENTED | metadata only; gaps **G3/G4/G8** |
| 07 S3 tuple comparator + `last_membership_event_id` (mig **083**) | ✅ IMPLEMENTED | gap **G5**; device test device-gated (D1) |
| 08 A2 `expiredFreshness` + ask-resend | ✅ IMPLEMENTED | orbit got real l10n; residual G9 (out of scope) |
| 08 B sweep + materialized filter | ✅ IMPLEMENTED | startup + resume + 3 loaders |
| 08 E "joining…" badge from 088 | ⚠️ PARTIAL | enrollment+badge done; **give-up UX missing (G2)** |
| 08 C revoke UI (mig **090**) | ✅ IMPLEMENTED | **HOLE-4 closed** (invite_id col+capture+use) |
| 08 F decline-ack (mig **090**, folded) | ⚠️ PARTIAL | **non-contact inviter unreachable (G1)**; no crypto verify (G6) |
| 08 D on-join metadata resync pull (flag **ON**) | ✅ IMPLEMENTED | L2 built + authenticity-gated; L1 deferred (documented); test gaps T1/T2 |

Migration reality: 07 took **083** (last_membership_event_id) + **086** (pending_group_broadcasts); 08 took **090**
(revoked+declined CHECK + invite_id). `currentIdentityDatabaseVersion = 90`. All in `full_migration_chain_test.dart`.

**Harness/build-time:** 08's real-crypto sim proof (`group_invite_reliability_proof_test.dart`) and the two-device
relay run (`MD004_SCENARIO=invite_reliability`) already fold C+F+D into **shared entrypoints → one device build**.
Every fix below is **host-test-only** — none requires a new device build.

---

## 1. GENUINE GAPS — close these

### G1 — [08-F] Decline-ack never reaches a non-contact inviter *(HIGH)*

**Confirmed:** `PendingGroupInvite` has no `mlKemPublicKey` field; `decline_pending_group_invite_use_case.dart:102`
resolves the inviter key via `contactRepo.getContact(invite.senderPeerId)?.mlKemPublicKey`. Group invites routinely
come from non-contacts → `inviterContact == null` → `DECLINE_ACK_ENCRYPTION_SKIPPED`. **F's entire purpose (tell the
inviter you declined) silently no-ops for the common case.** Plan §8 item 7 explicitly required persisting the
inviter ML-KEM key on the invite; it was not done.

**RED**
- `decline_pending_group_invite_use_case_test.dart`: inviter is **not** a contact, but the stored invite carries the
  inviter ML-KEM key → assert a `group_invite_decline_ack` envelope **is** sent (not `DECLINE_ACK_ENCRYPTION_SKIPPED`).
- `pending_group_invite_test.dart`: `toMap`/`fromMap` round-trips the new `mlKemPublicKey` (nullable; null-safe for
  legacy rows).
- store path test: `storeIncomingPendingGroupInvite` persists the inviter ML-KEM key from the incoming invite payload.

**GREEN**
- Add nullable `mlKemPublicKey` to `PendingGroupInvite` (+ `toMap`/`fromMap`). **Migration:** the `pending_group_invites`
  table needs a nullable `inviter_mlkem_public_key TEXT` column → next-free migration (re-check `ls migrations/`; 090 is
  taken, so **091**). Bump `currentIdentityDatabaseVersion` + `full_migration_chain_test.dart`.
- Populate it where the incoming invite is stored (the invite payload already carries the sender's ML-KEM key used for
  the join handshake — thread it into `storeIncomingPendingGroupInvite`).
- In the decline path prefer `invite.mlKemPublicKey ?? contactRepo.getContact(...)?.mlKemPublicKey`. Keep the
  best-effort `ENCRYPTION_SKIPPED` only when both are null.

**Gate:** use-case + model + migration-chain tests green; `flutter analyze` 0 new. *(If a migration is unwanted, the
fallback is to leave F as contacts-only and **downgrade the plan's claim** — but that abandons the stated goal.)*

---

### G2 — [08-E] "Couldn't join — retry" badge has no retry/leave action *(MEDIUM)*

**Confirmed:** no `clearGroupRejoinState` / `next_eligible_at` reset anywhere in `lib/features/.../presentation`.
`group_list_screen.dart:249-251` and `orbit/.../group_row.dart:31-33` render static text only;
`GROUP_REJOIN_PERMANENTLY_STUCK` is emitted but never consumed in UI. Plan §6 item 4 required a manual **"Retry now"**
(force `next_eligible_at = now`) + **"Leave"** affordance. The load-bearing safety property (no auto-delete) **is**
satisfied; the user-facing dead-end is the gap.

**RED**
- `group_list_wired_test.dart` / `orbit_wired_test.dart`: a group with a stuck rejoin row (attempt ≥ 10) renders a
  tappable "Retry now" affordance; tapping it resets the row's `next_eligible_at` to now (or clears it) and triggers a
  rejoin pass — assert via a spy on the rejoin/clear call. A non-stuck (attempt < 10) group shows the passive
  "Joining…" text with **no** action (negative guard).
- assert a "Leave" affordance is reachable directly from the stuck row (not only after entering the group).

**GREEN**
- Add a repository method to force-eligible a rejoin row (`dbRecordGroupRejoinFailure` with `nextEligibleAt: now`, or a
  small `forceGroupRejoinEligible(groupId)` helper) and expose a wired callback from the stuck-badge widget that calls
  it then triggers the existing rejoin trigger.
- Surface the existing leave path on the stuck row. **Do NOT auto-delete** — the row holds the key + drained inbox.

**Gate:** 2 widget tests + repo test green; analyze 0 new. No migration.

---

### G3 — [07-S2b] Durable resend does not cover member add/remove *(MEDIUM)*

**Confirmed:** `enqueueGroupPendingBroadcast` has exactly one producer (`group_info_wired.dart:1931`, the metadata edit).
`add_group_member_use_case.dart` / `remove_group_member_use_case.dart` publish paths have no durable-resend enqueue — a
soft `callGroupPublish` failure on an add/remove is still a silent false-success (the exact class of bug S2a/S2b were
built to kill, fixed for metadata only). Plan §6 listed this as a REMAINING item.

**RED**
- add/remove wired (or use-case) tests: on a soft publish failure (`{ok:false}`/timeout), a `pending_group_broadcasts`
  row is enqueued holding the already-signed membership sysText + recipients + original `eventAt`, and the local commit
  is kept; on next drain it re-pushes and clears. Monotonicity: drain re-uses the original `eventAt`, never re-stamps.

**GREEN**
- Reuse the existing `enqueueGroupPendingBroadcast` sink + `GroupPendingBroadcastRunner` (already drained on resume).
  Add the enqueue at the add/remove publish call sites, mirroring the metadata producer (`group_info_wired.dart:1924-1944`).

**Gate:** add/remove tests green; runner/drain already covered. No migration (086 table reused).

---

## 2. HYGIENE / LATENT — close or explicitly decide

### G4 — [07-S2b] Dead per-group drain trigger *(LOW, cheap)*
`triggerGroupPendingBroadcastDrainForGroup` (`group_pending_broadcast_sink.dart:43`) is **never called**; only
`triggerGroupPendingBroadcastDrainAll()` (`main.dart:4102`, resume) runs. Plan §4.2 specified
"rejoinGroupTopics + app-resume."
- **Close:** wire the per-group trigger into `rejoinGroupTopics` (faster convergence on the path that just reconnected),
  **or**
- **Decide:** delete the unused function (resume `drainAll` is functionally sufficient). Either way, no dead code should
  remain. RED = a `rejoin_group_topics_use_case_test.dart` assertion that a rejoin triggers a drain (if wiring) — else
  just remove + grep-clean.

### G5 — [07-S3] Remove send-path discards the canonical `(eventAt, eventId)` pair *(LOW, latent)*
`remove_group_member_use_case` returns the minted pair, but `group_info_wired.dart:971` discards it and re-derives
`sourceEventId`/`eventAt` from raw `removedAt`. **Non-functional today** (member_removed never tie-breaks by eventId on
send or receive), but a latent footgun if remove is ever folded into the tuple gate, and a deviation from the plan's
"canonical pair end-to-end."
- **Close:** consume `minted.eventAt`/`minted.eventId` from the use-case return at the wired remove site (mirror the role
  site at `group_info_wired.dart:1320/1333/1354`). **or**
- **Decide:** add a one-line comment at `:971` documenting the intentional divergence + a regression-guard test pinning
  "remove never tie-breaks by eventId" so a future change can't silently break it.

### G6 — [08-F] Decline-ack is not cryptographically verified *(LOW–MED, security posture)*
`handle_incoming_group_invite_decline_ack.dart` has **no** `callVerify`/`verify*Attestation` — only structural
validation (`_validateSignature` checks algorithm + canonical-payload match). The revocation handler it claims to mirror
**does** call `verifyGroupInviteRevocationAttestation`. Authenticity currently rests on ML-KEM-encryption-to-inviter +
the double `==message.from` spoof guard (defensible: a forger can't encrypt to the inviter's key nor spoof
`message.from`).
- **Decision required:** either add the Ed25519 `callVerify` to match the revocation path (RED: a structurally-valid but
  signature-forged ack is rejected), **or** record in the plan why the encryption+from-guard is sufficient and downgrade
  the "verify the inner signed payload" wording. Recommend adding the verify — it's cheap and matches the sibling path.

---

## 3. TEST GAPS — host-only, no device build

### T1 — [08-D] Responder `handleIncomingGroupConfigRequest` has no host test
Plan §9 specified a `config:request` **routing-discrimination** test (routes to the responder, NOT to
`storeIncomingPendingGroupInvite`/revocation) and a **stale-inviter echo no-op** test. Both absent at host level (only
exercised in the two-device harness). **RED:** in `group_invite_listener_test.dart`, a `config:request` reaches the
responder; a non-member requester is rejected; a non-admin responder declines to answer; and a stale-echo response
applies nothing.

### T2 — [08-D] `sendOnJoinGroupConfigRequest` transport-fallback has no host test
The offline `sendMessage:false → storeInInbox` fallback (`on_join_group_config_resync_use_case.dart:257-265`) is only
covered end-to-end. **RED:** direct unit test — direct send fails → inbox fallback used; node-not-running → best-effort
no-throw.

### T3 — [07-S3] No equal-instant `group_dissolved` *convergence* test *(LOW)*
Plan §5.1 listed both role and dissolve equal-instant convergence; only role has the explicit cross-sender pair test.
Low value (dissolve is terminal, never tie-breaks by eventId) — add only if cheap.

---

## 4. ACCEPTED RESIDUALS — leave as-is (plan-sanctioned), no action

- **G7 [07-S2a] avatar on-disk file not restored on metadata-edit broadcast failure** — only `GroupModel` fields revert;
  the committed avatar file is reconciled on next successful sync. Documented at `group_info_wired.dart:1947-1950`;
  plan §4.1 permitted "document as accepted residual." Close only if field evidence shows a stale-avatar problem.
- **G8 [07-S2b] no persistent "changes not yet sent" banner** — surfaced as a transient SnackBar; the `count` sink is
  wired (`main.dart:2544`) but unconsumed. Cosmetic; build only if product wants a persistent indicator.
- **07-S1 constants not moved to a canonical home** — role use-case imports from `remove_…` (single source, no
  ambiguity); the harness `hide staleGroupMembershipEventMessage` directive remains. Plan's explicitly-permitted
  "minimal alternative."
- **G9 [08-A2] orbit `invalidPayload`/`bridgeError` cases still hardcoded EN** — the `expiredFreshness` case got real
  l10n; the broader orbit-switch localization was flagged "opportunistic," out of A2 scope.

## 5. DEVICE-GATED — leave (cannot run on host)

- **D1 [07-S3] two-admin concurrent role toggle with deliberate clock skew** (iPhone13 `00008110-…`,
  Pixel6 `21071FDF600CSC`). Simulator clocks are too synced; host coverage substitutes by injecting
  `eventAt`/`sourceEventId` directly (proves the comparator). The real cross-device-skew run stays device-gated — matches
  the known remaining item for 07.

---

## 6. Recommended order (all host-only)

1. **G1** (08-F non-contact reachability — highest user impact; needs migration **091**).
2. **G2** (08-E retry/leave UX — user-facing dead-end; no migration).
3. **G3** (07-S2b add/remove durable resend — closes the remaining false-success class; no migration).
4. **G4 + G5 + G6** (hygiene/decisions — cheap; bundle).
5. **T1 + T2** (08-D responder/send host tests — pure coverage; no device build).
6. T3 optional.

Leave G7/G8/G9/D1 as documented residuals unless field evidence promotes them.
