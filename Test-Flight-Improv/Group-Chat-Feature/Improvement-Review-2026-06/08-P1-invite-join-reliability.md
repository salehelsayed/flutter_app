> Part of the **[Group Chat Improvement Review](./README.md)** · Priority **P1** · [Findings appendix](./appendix-findings.md)

---

# Make joining a group clean, current, and manageable

**Priority: P1**  ·  **Theme effort: Medium** (with two near-quick-wins)

---

## Why this matters (user experience)

A brand-new member's very first impression of a group is the join. Today that moment is fragile in ways the user can see but cannot understand or fix:

- **You join into a stale group.** If an admin renamed the group, changed its description, or swapped its avatar shortly before you accepted, you land in a group that shows the *old* name/description/image and silently diverges from everyone else. Convergence depends on a single fire-and-forget store-and-forward copy of the edit surviving long enough for a drain to succeed; if that copy expires first, the staleness can persist for a late joiner.
- **An invite that looks valid for a week silently dies after a day.** The pending-invite card advertises a ~7-day expiry and keeps the Accept button enabled, but the cryptographic freshness proof inside expires in 24h. Tap it on day 2 and you get a generic "Invite is no longer valid" with no reason and no path to a fresh invite.
- **Admins cannot take an invite back.** Revocation is fully implemented end to end — but no production screen ever calls it. An admin who invited the wrong person, or wants to cancel after a security concern, has no button to do so; the invitee can still join.
- **Dead cards pile up.** Expired invites linger as un-actionable "Expired" cards the user must dismiss one by one, and consumed/revoked tombstone rows are never swept.
- **A failed join can leave a half-materialized group.** A non-repairable bridge error (timeout, unknown code) persists the group, members, key, and avatar even though the topic was never joined — the group appears in the list but receives no live messages until a background rejoin happens to succeed.

Fixing these makes the join feel current (right metadata), honest (the card means what it says), and manageable (admins can revoke; dead cards self-clean).

---

## Current behaviour & evidence

### 1. No on-join authoritative-metadata resync (stale snapshot)
- The send path freezes the inviter's *current local* group state into the invite payload: `effectiveGroupConfig = currentFreshnessState.groupConfig` and it is embedded as `payload.groupConfig` (`send_group_invite_use_case.dart:158,250`).
- On accept, `materializeAcceptedGroupInvitePayload` rebuilds the entire `GroupModel` verbatim from that config — `name`, `description`, `avatarBlobId`/`avatarMime`, `metadataUpdatedAt` → `lastMetadataEventAt` — and saves it (`handle_incoming_group_invite_use_case.dart:841-872`), then downloads the snapshot avatar (`:900-908`).
- The only accept-time channel that can deliver a *newer* edit is the offline-inbox drain, which is fire-and-forget and fails on the same `bridgeError`.
- A repo-wide grep for `resync` / `requestGroupConfig` / `config:request` finds **no** on-join pull-based metadata-resync mechanism in `lib/`.
- `_isStaleAgainstLocalGroupState` returns `false` when `localGroup == null` (`accept_pending_group_invite_use_case.dart:528-530`), so a first join never rejects a stale snapshot.
- Mitigating context: `updateGroupMetadata` bumps `lastMetadataEventAt` and the receive-side watermark gate accepts strictly-newer events, so a *connected* member converges via live GossipSub. The genuine gap is the **late joiner** whose single store-and-forward copy of the edit expired before the drain succeeded.

### 2. Freshness TTL (24h) vs invite TTL (7d) mismatch → silent reject
- `PendingGroupInvite.expiresAt = min(policyExpiry, receivedAt + ttl)`, where `pendingGroupInviteTtl = Duration(days: 7)` (`pending_group_invite.dart:4,75-79`) and the policy expiry is also `now + pendingGroupInviteTtl` (`_deriveInvitePolicy`, `send_group_invite_use_case.dart`). Both are ~7 days.
- The card uses `invite.isExpiredAt` / `invite.expiresAt` for its label and to enable Accept (`pending_group_invite_card.dart:27,91-99,140`) — so it stays actionable for ~7 days.
- But on accept, `payload.currentTimeValidationFailure(effectiveNow)` (`accept_pending_group_invite_use_case.dart:143`) ultimately checks `proof.isFreshAt`, where `expiresAt = issuedAt + groupInviteMembershipFreshnessTtl = 24h` (`group_invite_auth.dart:129`; `group_invite_payload.dart:19,287-289`).
- A stale proof yields `staleMembershipFreshness`, which accept maps to `deletePendingInvite` + `invalidPayload` (`accept_pending_group_invite_use_case.dart:167-180`), surfacing the generic `group_invite_invalid` snackbar (`group_list_wired.dart:341-342`).
- Note: the 24h proof TTL is intentional design (a separate freshness window). The defect is purely UX: the card advertises 7 days and the failure is a generic "invalid" with no "expired, ask the admin to resend" guidance.

### 3. Revocation implemented but never invoked from production UI
- `revokePendingGroupInvite` (`revoke_pending_group_invite_use_case.dart:20`) and `sendGroupInviteRevocation` (`:68`) are fully built — local tombstone + signed encrypted envelope with direct-send then inbox-fallback (`:223-257`).
- A scoped grep of `lib/` finds **no caller** of either outside tests / the integration harness.
- By contrast, `resendGroupInvite` *is* wired into production UI at `group_info_wired.dart:1738`.
- The receive side (`handleIncomingGroupInviteRevocation`, `handle_incoming_group_invite_use_case.dart:385-451`) and the verification/attestation path are complete. Only the **admin-facing trigger** and the inviter→invitee revocation **send** are missing.

### 4. No expiry/tombstone sweep → lingering dead cards
- `deleteExpiredPendingInvites` / `deleteExpiredRevokedInvites` / `deleteExpiredConsumedInvites` are implemented (`pending_group_invite_repository_impl.dart:215-229`) and declared on the interface, but a grep of `lib/` finds **no caller**.
- `getPendingInvites()` returns all rows unfiltered (`pending_group_invite_repository_impl.dart:160-163`); the only delete invoked anywhere is the explicit `deletePendingInvite` on accept/decline/revoke of a specific group.
- `main.dart` wires `sweepExpiredPosts` (`:2164,3113`) and the `PendingMessageRetrier` (`:1923`) but **no invite sweep**.
- The card still renders expired invites (Accept disabled, card persists; `pending_group_invite_card.dart:27,91-99,140`).
- Severity is **low**: tombstone rows are bounded by their own ~7-day `expiresAt`, so growth is not truly unbounded; the visible symptom is mainly stale "Expired" cards needing manual dismissal.

### 5. Non-repairable bridge join failure persists a half-materialized group
- In `materializeAcceptedGroupInvitePayload`, `_rollbackMaterializedInviteState` runs **only** when `_isRepairableJoinMaterialError` matches a fixed allowlist of key/welcome/decrypt codes (`handle_incoming_group_invite_use_case.dart:920-937,1000-1024`).
- `TimeoutException` (`:944-955`) and the generic `catch` (`:956-963`) return `(bridgeError, groupId)` with the group, members (`:877-889`), key (`:891-898`), and avatar (`:900-908`) left fully persisted — feeding the scenario-7 "joined recovery" snackbar (`group_list_wired.dart:347-352`).
- Mitigating context: `rejoinGroupTopics` idempotently re-joins every non-dissolved persisted group with a stored key on startup/watchdog/recovery, so the half-materialized group *is* eligible and will be re-joined automatically. The residual gap is only that there is **no needs-join flag/UI indicator** and **no bounded give-up + rollback** if the join never succeeds.

### 6. Decline never notifies the inviter
- `declinePendingGroupInvite` writes only a local consumption tombstone and deletes the local pending invite (`decline_pending_group_invite_use_case.dart:32-37`); it sends **nothing** to the inviter.
- (Accept-side convergence already works: a joiner's `member_joined` reaches the inviter's `group_message_listener._handleMemberJoined` → `markJoined` → `GroupInviteDeliveryStatus.joined`, `group_message_listener.dart:2756`. So the only gap here is the **decline** half — the admin's delivery view never reflects an explicit decline and cannot drop a never-joined member.)

---

## Root cause(s)

| # | Root cause |
|---|-----------|
| 1 | The invite is a **frozen snapshot** with no pull-based "give me your current config" step on join; freshness convergence is delegated entirely to a best-effort store-and-forward drain. |
| 2 | **Two independent lifetimes** (7-day invite TTL vs 24h freshness-proof TTL) are not reconciled in the UI, and the accept-time freshness failure is folded into the catch-all `invalidPayload` result. |
| 3 | Revoke is **feature-complete but unwired** — an asymmetry vs. the wired resend. |
| 4 | Expiry/tombstone sweep functions exist but are **never scheduled**, and `getPendingInvites()` does no filtering. |
| 5 | Rollback is gated on a **narrow repairable-error allowlist**; everything else persists state with no "not actually joined" marker or bounded give-up. |
| 6 | Decline is a **purely local** operation with no signalling channel back to the inviter. |

---

## Proposed improvements

> Ordered to front-load the near-quick-wins (#2 card alignment, #4 sweep) that immediately remove misleading/dead cards, then the medium-effort correctness/management items.

### Improvement A — Align invite freshness/expiry and humanise the failure *(quick win, #2)*

**A1. Make the card tell the truth.** Compute the card's effective expiry as the minimum of the policy/local expiry and the freshness-proof expiry, so the card correctly flips to "Expired" at ~24h and disables Accept.

- In `PendingGroupInvite.fromPayload` (`pending_group_invite.dart:63-79`), fold the proof window into `expiresAt`:
  ```dart
  final proofExpiry = payload.membershipFreshnessProof?.expiresAt.toUtc();
  var expiresAt = policyExpiry.isBefore(localExpiry) ? policyExpiry : localExpiry;
  if (proofExpiry != null && proofExpiry.isBefore(expiresAt)) {
    expiresAt = proofExpiry; // card now expires when the proof does
  }
  ```
  This needs no schema change — `expires_at` is already persisted — but **existing rows** will keep the old (7-day) value until re-received; acceptable since accept-time validation is unchanged. (Alternatively, recompute effective expiry in the card from `payloadJson` to also fix rows in flight.)

**A2. Distinguish the expired-freshness failure.** Rather than collapsing `staleMembershipFreshness` into `invalidPayload`, return a dedicated result so the UI can say "this invite expired — ask the admin to resend."

- Add `expiredFreshness` (or reuse `expired`) to `AcceptPendingGroupInviteResult` (`accept_pending_group_invite_use_case.dart:25-36`) and branch `staleMembershipFreshness` to it at `:167-180` (keep the `deletePendingInvite` so the dead card is removed).
- Handle it in `group_list_wired.dart:341` with a new ARB string, e.g. `group_invite_expired_ask_resend` ("This invite has expired. Ask the group admin to send a new one."), threaded through all locales (`app_en.arb`, `app_ar.arb`, `app_de.arb`, `app_localizations*.dart`).

*Alternative (config decision, not code):* extend `groupInviteMembershipFreshnessTtl` to match the 7-day invite lifetime — simpler, but weakens the freshness guarantee the PREREQ-INVITER-FRESHNESS plan intended. **Recommend A1+A2 over widening the TTL.**

### Improvement B — Sweep expired invites & tombstones; filter dead cards *(quick win, #4)*

**B1. Schedule the existing sweep functions.** Add an invite sweep alongside the existing `sweepExpiredPosts`/`PendingMessageRetrier` wiring:
- At startup (next to `sweepExpiredPosts(...)`, `main.dart:2163-2175`) and on resume (`main.dart:3113`), call `deleteExpiredPendingInvites(now)`, `deleteExpiredRevokedInvites(now)`, `deleteExpiredConsumedInvites(now)` (and the already-present `deleteExpiredWelcomeKeyPackageTombstones`) on the `PendingGroupInviteRepository`, each wrapped in `unawaited(...).catchError(...)` with a `GROUP_INVITE_SWEEP_*` flow event.
- Optionally fold the same calls into the `PendingMessageRetrier`'s periodic tick for steady-state cleanup.

**B2. Stop rendering dead cards.** Either filter at the source — have `getPendingInvites()` (`pending_group_invite_repository_impl.dart:160-163`) drop rows whose `expiresAt < now` *and* whose group is already materialized — or filter in `group_list_wired` before building cards. Keeping a short grace window (show "Expired" briefly, then sweep) is fine; the key is they don't accumulate.

*No new wire/DB/migration impact.*

### Improvement C — Wire invite revocation into the admin UI *(medium, #3)*

Add a **"Revoke invite"** action to the member/delivery-status row in `group_info_wired.dart`, mirroring the existing `_onResendInvite` (`:1726-1789`), shown only for members whose invite is still outstanding (status `sent`/`queued`/`needsResend`) and for whom the current user is an admin.

On tap:
1. `revokePendingGroupInvite(pendingInviteRepo, groupId, revokedBy: ownPeerId)` — tombstones locally.
2. `sendGroupInviteRevocation(...)` (`revoke_pending_group_invite_use_case.dart:68`) — direct-send then relay-inbox fallback (already built).
3. Update the delivery-status row to a new **`revoked`** state and reload group info.

- Add `revoked` to `GroupInviteDeliveryStatus` (`group_invite_delivery_attempt.dart:1-44`) — extend `toValue`/`fromValue` and the presentation mapper in `group_invite_status_presentation.dart`; add a `markRevoked` to the delivery-attempt repo (sibling of `markJoined`). This is an enum value addition: persisted as the string `"revoked"`, so **no DB migration** (the column already stores free-form status strings).
- New ARB strings: action label `group_info_revoke_invite`, confirmation dialog, and result snackbars.

### Improvement D — On-join authoritative-metadata resync *(medium–large, #1)*

Close the late-joiner staleness gap with a pull-based resync that does **not** depend on retention of a single store-and-forward copy.

**Recommended (pull):** After a successful `materializeAcceptedGroupInvitePayload` / join, the new member sends a lightweight signed `group:config:request` to the inviter (and/or the group's other reachable members). Reuse the existing encrypted-envelope + inbox-fallback transport already used by `sendGroupInviteRevocation`. The responder replies with the current authoritative `groupConfig` (name/description/avatar blob + `metadataUpdatedAt`). The new member feeds that through the **existing receive-side watermark gate** (which already accepts strictly-newer `lastMetadataEventAt`), so a stale snapshot is corrected and the newer avatar downloaded.

- Send trigger: end of the success branch of `materializeAcceptedGroupInvitePayload` (`handle_incoming_group_invite_use_case.dart:965-974`) and/or `acceptPendingGroupInvite` after a `success` result.
- Wire format: a new envelope `type` (e.g. `group:config:request` / `group:config:response`), versioned per the v1/v2 envelope convention. Document in the wire-format reference and `Test-Flight-Improv` matrices.
- Reuse `updateGroupMetadata` on the response path so the watermark/avatar logic is shared with live GossipSub edits (no duplicate convergence code).

**Lighter alternative (push):** Have `updateGroupMetadata` (admin side) re-broadcast the latest authoritative snapshot to any member whose `joinedAt > lastMetadataEventAt` (a late joiner). Smaller surface, but only helps if the admin edits again or stays online; the pull is the robust late-joiner fix. **Recommend the pull; the push is a complementary nicety.**

*Scope note:* this is the only item with new wire-protocol surface; everything else is local.

### Improvement E — Mark "joining…" and bound the half-materialized state *(medium, #5)*

Make "durably joined" distinguishable from "persisted but not joined":

1. Add a `joinState` (e.g. `joined` / `joining` / `needsJoin`) marker on `GroupModel`. Persisting this is a **DB migration** (new nullable column on the `groups` table, default `joined` for existing rows) — keep it minimal.
2. On `TimeoutException` / generic `catch` in `materializeAcceptedGroupInvitePayload` (`:944-963`), set `needsJoin`/`joining` instead of leaving it ambiguous.
3. Surface it in the UI as "Joining…" on the group row/list, and have `rejoinGroupTopics` clear it to `joined` on the next successful idempotent join (it already retries these groups since the key is persisted).
4. Add a **bounded give-up**: after N failed rejoin cycles or T elapsed, run `_rollbackMaterializedInviteState` (`:1026-1033`) and inform the user, rather than leaving a silent dead group indefinitely.

*This is the lowest-priority item in the theme (the existing `rejoinGroupTopics` already auto-recovers most cases); ship after A–D unless device testing shows frequent stuck joins.*

### Improvement F — Decline acknowledgement to the inviter *(low, #6)*

Send a lightweight signed **decline ack** (reuse the revocation-style envelope + inbox fallback) from `declinePendingGroupInvite` (`decline_pending_group_invite_use_case.dart`) so the admin's delivery view can show **`declined`** and optionally drop a never-joined member from the roster.

- Add a `declined` value to `GroupInviteDeliveryStatus` and a `markDeclined` repo method (same shape as the `revoked` work in C).
- New wire `type` `group:invite:decline-ack`; receive-side handler in `group_message_listener` calls `markDeclined`.
- Privacy trade-off: a decline ack reveals the user declined. Make it best-effort and consider gating behind a setting; **not blocking** for the theme.

---

## Affected files & components

| Area | Files |
|------|-------|
| Card freshness/expiry (A1) | `lib/features/groups/domain/models/pending_group_invite.dart`, `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` |
| Accept result + snackbar (A2) | `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/presentation/screens/group_list_wired.dart`, `lib/l10n/app_en.arb` (+ `_ar`, `_de`, `app_localizations*.dart`) |
| Sweep scheduling (B) | `lib/main.dart`, `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` (filter `getPendingInvites`) |
| Revoke wiring (C) | `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/revoke_pending_group_invite_use_case.dart` (caller), `lib/features/groups/domain/models/group_invite_delivery_attempt.dart`, `lib/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl.dart`, `lib/features/groups/presentation/group_invite_status_presentation.dart` |
| Metadata resync (D) | `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `lib/features/groups/application/accept_pending_group_invite_use_case.dart`, `lib/features/groups/application/send_group_invite_use_case.dart`, new `group:config:request/response` envelope + handler in `lib/features/groups/application/group_message_listener.dart` (or a dedicated use case), Go bridge transport (already reusable) |
| Join-state marker (E) | `lib/features/groups/domain/models/group_model.dart`, a new DB migration in `lib/core/database/migrations/`, `lib/features/groups/application/handle_incoming_group_invite_use_case.dart`, `rejoin_group_topics_use_case.dart`, group list/row UI |
| Decline ack (F) | `lib/features/groups/application/decline_pending_group_invite_use_case.dart`, `lib/features/groups/application/group_message_listener.dart`, `lib/features/groups/application/record_group_invite_delivery_attempts.dart`, delivery-status enum/presentation |

---

## Test & verification strategy

### Unit tests
- **A1** `PendingGroupInvite.fromPayload`: effective `expiresAt = min(policy, local, proofExpiry)`; card `isExpiredAt` flips at the proof boundary (~24h).
- **A2** `acceptPendingGroupInvite`: a payload past the 24h freshness window returns the new `expiredFreshness` result (not `invalidPayload`) and still deletes the pending invite; `group_list_wired` maps it to the ask-resend string.
- **B** repository: `deleteExpiredPendingInvites/Revoked/Consumed` remove only rows with `expiresAt < now`; `getPendingInvites` filters expired+materialized rows.
- **C** revoke: tapping revoke calls `revokePendingGroupInvite` + `sendGroupInviteRevocation` and transitions the attempt to `revoked`; `GroupInviteDeliveryStatus.fromValue('revoked')` round-trips.
- **D** resync: a config-request emitted on successful join; a strictly-newer config response updates `name/description/avatar`+`lastMetadataEventAt` (and a stale/older one is rejected by the watermark gate).
- **E** materialize: `TimeoutException`/generic error sets `needsJoin` (not ambiguous); `rejoinGroupTopics` clears it on success; bounded give-up triggers rollback after the threshold.
- **F** decline emits a signed ack; receiver's listener marks `declined`.

### Integration harnesses (`integration_test/`)
- Extend `group_invite_status_matrix_harness.dart` for the new `revoked`/`declined` delivery states and the "expired-after-24h ⇒ ask-resend" path.
- Extend `group_recovery_e2e_test.dart` (or a sibling) for the **late-joiner resync**: admin edits name/avatar, invitee accepts after the store-and-forward copy would have expired, assert convergence to the latest metadata via the new config-request.
- Use `group_multi_device_real_harness.dart` / `group_multi_party_device_real_harness.dart` for revoke-then-attempt-accept (invitee must be blocked) and join-state "Joining…" surfacing.
- `FakeGroupPubSubNetwork` + `GroupTestUser` for the resync request/response round-trip without real transport.

### Test-Flight-Improv matrices & gates
- Add rows to `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and `test-gate-definitions.md` for: card-vs-proof expiry alignment, revoke flow, late-joiner metadata convergence, expired-card sweep, and the half-join "Joining…" indicator.
- Fold the resync and revoke journeys into `52-notification-journey-test-matrix.md` where they affect roster/notification state.

### Device matrix
- Two-device (iPhone13 + Pixel6 per project device IDs) real-stack run for the relay-inbox-dependent paths: revoke delivery via inbox fallback, and late-joiner resync where the original edit's store-and-forward copy is allowed to expire first. These need the real two-device harness because cross-device `/tmp` and ML-KEM-random-per-restore make single-process simulation unreliable.

---

## Risks, trade-offs & rollout

| Item | Risk / trade-off | Mitigation |
|------|------------------|-----------|
| A1/A2 | Tightening the visible expiry to 24h means some invites that "would have worked" now show Expired sooner — but they would have failed on accept anyway. Honest > optimistic. | Pair with the clear "ask admin to resend" message and the wired resend (already present). |
| B | Filtering/sweeping could hide an invite a user wanted to act on. | Use `expiresAt`-based cutoff only; keep a short grace window; never sweep non-expired rows. |
| C | New `revoked` enum value: an older client decoding it via `fromValue` throws on the `default` branch. | Map unknown status strings to `unknown` instead of throwing (small hardening of `fromValue`), and/or gate the feature behind a min-version. Reveals admin intent — acceptable for an admin action. |
| D | **New wire protocol surface**; a config request leaks "I just joined"; a malicious responder could push bad metadata. | Sign the request/response; reuse the existing inviter-authorization/watermark gates so only strictly-newer, admin-authorized config is accepted; rate-limit. Roll out behind a flag. |
| E | DB migration (new column) + a give-up that rolls back a group the user thinks they joined. | Default existing rows to `joined`; make give-up generous (T ≫ typical relay reconnection) and inform the user before rollback. |
| F | Decline ack is a privacy disclosure. | Best-effort, optionally setting-gated, non-blocking. |

**Rollout order:** A → B (quick wins, no protocol/DB change, immediately remove misleading/dead cards) → C (admin completeness, enum-only) → D (the real correctness fix, behind a flag, device-validated) → E → F. Each is independently shippable.

---

## Effort estimate

| Improvement | Effort | Notes |
|-------------|--------|-------|
| A — freshness/expiry alignment + humane failure | **S–M** (near quick-win) | Local model/UI + one accept result + ARB strings. |
| B — schedule sweeps + filter cards | **S** (quick win) | Functions already exist; just wire + filter. No schema/protocol change. |
| C — wire revoke into admin UI | **M** | UI action + enum value + repo `markRevoked` + presentation; logic already built. |
| D — on-join metadata resync | **M–L** | Only item with new wire-protocol surface; reuses watermark gate + envelope transport; device-validated. |
| E — join-state marker + bounded give-up | **M** | DB migration + UI indicator; partly mitigated by existing `rejoinGroupTopics`. |
| F — decline ack | **L→M** | New ack type + enum + listener; privacy-gated, low priority. |

**Theme total:** medium. A and B are near-quick-wins that deliver visible cleanup almost immediately; D is the central correctness investment; E and F are optional polish that can follow.
