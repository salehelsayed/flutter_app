# Group Invite: "Ghost Notifications + Missing Invite" — Root-Cause Analysis

**Date:** 2026-06-04
**Branch:** `121-improvements`
**Method:** 13-agent code-investigation workflow (6 subsystems independently traced → each adversarially re-verified → synthesized). ~1.35M tokens, 448 tool calls.
**Confidence:** High on the mechanics and on both answers below. Medium on one server-side link (see [Confidence](#confidence--how-to-confirm-on-device)).

---

## TL;DR

user-b was invited but **the invite was almost certainly dropped at receive time and never written to a `pending_group_invites` row on her device.** Because no row was stored:

- it never materialized a local group → **the group does not appear in her app**, and
- it never appeared in the Orbit **Intros** list (which renders a 1:1 mirror of stored invite rows).

The notifications she keeps seeing are **not** produced by the group invite and **not** by the in-app (GossipSub) group-message listener — both are membership-gated and cannot fire for a non-member. They come from the **membership-blind remote FCM/relay push fallback**, which shows a generic *"New Message"* for any routable `group:<id>` payload with **zero** check on local group existence or membership. When she taps one, the route resolver finds no local group and no pending invite, returns `.missing()`, and the tap handler **silently returns with no navigation** — exactly "I tap the notification and find no messages."

Meanwhile user-a still lists her as a member because **the creator writes every invited contact into its own local roster at invite time, unconditionally**, and there is **no acceptance back-channel** that would ever remove her.

---

## The reported scenario

> user-a created a group and invited multiple users. Some accepted immediately; some did not. user-b (an invitee who did **not** accept) reports she receives notifications, but tapping them shows **no messages**. user-a sees user-b **among the invited members**. On user-b's phone the group is **not present**, and the invite is **not in the Intros tab** under Orbit.

Four observations to explain:
1. user-b gets notifications.
2. Tapping a notification shows no messages.
3. The group is absent from user-b's app.
4. The invite is absent from user-b's Intros tab — yet user-a still lists her as a member.

---

## Direct answers to the two questions

### Q1 — Do group intros/invites get deleted after a while if not accepted?

**No automatic *7-day* deletion runs in production — but a much shorter ~24-hour gate at receive time can permanently drop the invite before it is ever stored.** This is the nuance that matters for this bug.

- The pending-invite TTL constant is exactly `pendingGroupInviteTtl = Duration(days: 7)`
  (`lib/features/groups/domain/models/pending_group_invite.dart:4`). Stored `expires_at = min(receivedAt + 7d, invitePolicy.expiresAt)` (`pending_group_invite.dart:74-79`); the sender policy is also `now + 7d`, so it's ~7 days either way.
- A hard-delete sweep **exists** — `dbDeleteExpiredPendingGroupInvites` → `DELETE FROM pending_group_invites WHERE expires_at <= cutoff` (`pending_group_invites_db_helpers.dart:148-179`) — and is DI-wired in `main.dart:1003-1004`. **But the repo method that would trigger it (`deleteExpiredPendingInvites`) has ZERO production callers** anywhere in `lib/` (only the abstract decl, the impl, a fake, and one unit test). There is no Timer / startup / resume / lifecycle invocation. It is effectively **dead code.**
- The read path applies **no expiry filter** (`getPendingInvites` → `dbLoadPendingGroupInvites` has no `WHERE` clause). So a stored-but-expired invite would *still appear* in Intros, just rendered with an **"Expired"** label (`pending_group_invite_card.dart:27`). A *stored* unaccepted invite does **not** silently vanish after 7 days.

**The caveat that actually bites — a separate ~24-hour gate:**

- Every invite carries a `membershipFreshnessProof` with `expiresAt = issuedAt + 24h`
  (`groupInviteMembershipFreshnessTtl = Duration(hours: 24)`, `group_invite_payload.dart:19`; built at `group_invite_auth.dart:129`).
- On **receive**, `verifyGroupInviteAttestation(validationTime: effectiveReceivedAt)` calls `isMembershipFreshnessProofValid`, which returns false when `!proof.isFreshAt(validationTime)` (`group_invite_payload.dart:287-289`; check at `group_invite_auth.dart:55-61, 196`) → `invalidPayload` → **returns WITHOUT saving** (`handle_incoming_group_invite_use_case.dart:494, 498-499`).
- The same gate is re-checked at **accept** time → `staleMembershipFreshness` (`accept_pending_group_invite_use_case.dart:145, 172`).

**Net:** Invites are *not* garbage-collected by the 7-day timer. **But if user-b's device processes the relayed invite more than ~24h after it was issued** (offline, delayed store-and-forward relay, or clock skew), the invite is **silently dropped at receipt and never appears in Intros** — a genuine, time-based reason for the missing invite.

Other (non-time) reasons the receive path drops an invite without storing it: `unknownSender`, `decryptionFailed`, `invalidPolicy`, `revoked`, `alreadyUsed` (single-use), `stale-vs-existing`, `duplicateGroup` (`handle_incoming_group_invite_use_case.dart:497-608`). Stored invites are deleted only on explicit **accept / decline / incoming revocation**.

### Q2 — Do users receive notifications *before* they accept the group?

**Yes — but only via the remote FCM/relay push path, never via the in-app live group-message path, and never from the invite arrival itself.**

- **(a) In-app / live path cannot fire pre-accept.** `maybeShowNotification` (`group_message_listener.dart:835`) is nested inside `if (result != null)` (line 819). `handleIncomingGroupMessage` returns **null** for a non-member:
  - `GROUP_HANDLE_INCOMING_MSG_UNKNOWN_GROUP` when no local group row exists (`handle_incoming_group_message_use_case.dart:140-148`), and
  - `GROUP_HANDLE_INCOMING_MSG_LOCAL_MEMBERSHIP_MISSING` when self is not a current member for non-system messages (`:176-205`).

  Independently, an un-accepted user **never subscribes to the GossipSub topic** — subscription happens only via `callGroupJoinWithConfig` inside `materializeAcceptedGroupInvitePayload` (`handle_incoming_group_invite_use_case.dart:929`), reached only on accept — so GossipSub never delivers to her anyway. The precise precondition gating an in-app notification is: **local group row exists AND self is a current member AND `!group.isMuted` AND sender ≠ self.**

- **(b) The invite-arrival path fires no notification at all.** `group_invite_listener.dart` has no `NotificationService` and no `maybeShowNotification` call; it only stores the pending row and pushes to a UI stream.

- **(c) The remote FCM background path DOES show a notification with zero membership/group/decrypt checks.** `shouldShowBackgroundPushFallbackNotification` returns true whenever `message.notification == null` AND `NotificationRouteTarget.fromRemoteMessageData != null` (`background_push_notification_fallback.dart:21-32`), and `firebaseMessagingBackgroundHandler` calls `.show()` (`background_message_handler.dart:96-129`). For a `group_message`-typed payload that a non-member can't decrypt, the copy falls back to generic *"New Message" / "You have a new message"* (`background_push_notification_fallback.dart:6-7, 139-143`).

---

## Root cause

> user-b's invite was dropped at receive time (most plausibly by the 24h membership-freshness gate, given store-and-forward relay delay), so **no pending-invite row and no local group were ever created** on her device. The notifications are remote FCM/relay pushes for ongoing group messages, displayed **membership-blind** by the background fallback. Tapping them resolves to `.missing()` and **no-ops** with no navigation. user-a still sees her as a member because the creator's roster is written at invite time and is never reconciled against actual acceptance.

---

## What actually happened — step by step

1. **Creation.** user-a creates the group and invites contacts. `createGroupWithMembers` loops every invited contact → `addGroupMember` → `groupRepo.saveMember` (`create_group_with_members_use_case.dart:199-218`; `add_group_member_use_case.dart:311`), writing user-b into **user-a's local roster immediately** with `role=writer`, `joinedAt=now`, and **no acceptance flag.** → *This is why user-a will forever see user-b "among the invited members."*

2. **Invite send.** user-a sends the encrypted invite to user-b via **P2P inbox relay (store-and-forward)**, carrying a `membershipFreshnessProof` valid for only **24h** (`group_invite_auth.dart:129`) and an `invitePolicy` expiry of `now + 7d`.

3. **Invite NOT stored on user-b.** Her device receives the relayed invite, but `storeIncomingPendingGroupInvite` hits an early-return and never calls `savePendingInvite`. The single most scenario-consistent cause is the **24h freshness gate**: if she was offline / the relay delivered late / clock skew pushed processing >24h past issuance, `isMembershipFreshnessProofValid` returns false → `invalidPayload` → return without saving (`handle_incoming_group_invite_use_case.dart:498-499`). Equally plausible non-time causes: `unknownSender` (she never added user-a as a mutual contact / lacks his signing key), `decryptionFailed` (ML-KEM / device-binding mismatch), or a revocation user-a's app emitted during a re-invite or metadata edit.

4. **Group messages start flowing.** Accepted members chat. user-a's send path stores group messages in the relay inbox for offline/unreachable peers — **including user-b** — and the relay emits remote pushes typed `group_message` to her FCM token.

5. **Ghost notifications.** Her device shows these as generic *"New Message"* notifications via the **membership-blind background fallback** (`background_push_notification_fallback.dart:21-32`). She isn't subscribed to the topic and has no local group, so the in-app listener stays silent — these are purely remote-push artifacts.

6. **Tap → nothing.** She taps a notification. `main.dart:2741` calls `resolveGroupNotificationRouteTarget`, which finds no local group **and** no pending invite → `.missing()` (`resolve_group_notification_route_target_use_case.dart:36-79`). The handler at `main.dart:2748` sees `resolution.group == null`, emits `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING`, and because `hasPendingInvite` is false, **returns at line 2764 with no navigation.** → *"notifications but no messages."*

7. **Divergence persists.** There is no acceptance back-channel; nothing ever removes user-b from user-a's roster. user-a keeps seeing her as a member while her own device has neither the group nor the invite.

---

## Symptom → cause map

| Observed symptom | Mechanism |
|---|---|
| user-b gets notifications | Membership-blind remote FCM/relay push fallback shows generic "New Message" for any routable `group:<id>` payload (`background_push_notification_fallback.dart:21-32`, `background_message_handler.dart:96-129`) |
| Tapping shows no messages | Route resolver returns `.missing()` (no local group, no pending invite); tap handler no-ops with no navigation (`main.dart:2748-2764`, `resolve_group_notification_route_target_use_case.dart:36-79`) |
| Group absent from her app | Local group/members/key + topic-join are created **only** by `materializeAcceptedGroupInvitePayload`, reached only on accept (`handle_incoming_group_invite_use_case.dart:874,890,900,929`; `accept_pending_group_invite_use_case.dart:287`) — and she never accepted because the invite was never stored |
| Invite absent from Intros | Intros renders an unfiltered mirror of `pending_group_invites` rows (`orbit_wired.dart:574-575`); the row was never written (receive-path early-return, most likely 24h freshness drop) |
| user-a still sees her as a member | Creator writes every invitee to its roster at invite time with no "invited vs joined" distinction and no back-channel to remove non-acceptors (`create_group_with_members_use_case.dart:199-218`) |

---

## Contributing factors

1. **Two un-reconciled membership representations** — the creator's roster (written at invite time, unconditionally) vs the invitee's local join-state (created only on accept). No back-channel updates the creator when an invitee fails to accept.
2. **A short 24h `membershipFreshnessProof` TTL** (`group_invite_payload.dart:19`) silently drops the *entire* invite at receive time if processed late — far shorter than the visible 7-day invite TTL, and easy to trip given store-and-forward relay delivery.
3. **Many silent early-return branches** in `storeIncomingPendingGroupInvite` (`invalidPayload`, `unknownSender`, `decryptionFailed`, `invalidPolicy`, `revoked`, `alreadyUsed`, `stale`, `duplicateGroup`) drop the invite with **no user-visible artifact and no error shown.**
4. **The remote FCM background fallback displays notifications with zero membership/group-existence/pending-invite checks**, so a non-member receives ghost notifications.
5. **The tap handler treats `.missing()` as a silent no-op** (`main.dart:2764`): no toast, no error, no fallback navigation.
6. **Generic protected-preview copy** ("New Message") for undecryptable group pushes means the user can't tell the notification is for a group she isn't in.
7. **Inconsistent expiry story** — the 7-day sweep is dead code, yet the receive path enforces a hidden 24h gate. Stored invites never auto-expire; new ones can be silently dropped.
8. **Store-and-forward relay delivery** introduces arbitrary delay between `issuedAt` and `effectiveReceivedAt`, directly feeding the 24h-freshness drop.

---

## Recommendations (prioritized)

**P0 — Surface invite drops instead of silently discarding them.** The receive-path early-returns (`handle_incoming_group_invite_use_case.dart:497-608`) all return with no user-visible artifact. At minimum emit a distinct FLOW event per branch (several already do) **and** persist a lightweight "failed invite" record so the user/diagnostics can see an invite was received but rejected, and why. Directly addresses "user-a sees her invited but nothing landed."

**P0 — Re-evaluate the 24h `membershipFreshnessProof` TTL** (`group_invite_payload.dart:19`) against the real (store-and-forward, arbitrarily delayed) delivery channel. Options: (a) lengthen `groupInviteMembershipFreshnessTtl` to a realistic offline window; (b) allow re-issuance/refresh of the freshness proof on relay re-delivery; or (c) decouple anti-replay freshness from *storage eligibility* so a structurally-valid invite is still stored (as "needs re-verification") rather than dropped. This is the single most likely cause of the missing invite.

**P0 — Fix the membership-blind remote push → empty-tap UX.** Before showing a `group_message` fallback notification (`background_push_notification_fallback.dart:21-32`) OR at tap-time when resolution is `.missing()` (`main.dart:2748-2764`): either suppress the notification for groups the device has no local state for, or on `.missing()` navigate to a "this group is no longer available / you have a pending or expired invite" surface (or re-trigger an invite re-fetch). Today the tap is a silent no-op.

**P1 — Add an acceptance back-channel / two-state roster on the creator side.** The creator writes every invitee as a full member at invite time (`create_group_with_members_use_case.dart:199-218`) with no "invited vs joined" distinction. Add an explicit pending/accepted member state and update it from the existing `member_joined` timeline signal so user-a's UI can distinguish "invited (not yet joined)" from "active member."

**P1 — Make the invite-expiry story consistent.** Either actually invoke the existing 7-day sweep (wire `deleteExpiredPendingInvites` into a startup/periodic task; it's currently dead code despite being DI-wired at `main.dart:1003-1004`) AND filter expired rows out of `getPendingInvites`, **or** remove the dead sweep code. Right now stored invites never auto-expire while a hidden 24h gate drops new ones.

**P2 — On a relayed `group_message` push to a device with no local group, opportunistically request/re-drain the *pending invite*** (not just the message inbox), so a late-but-valid invite can still materialize the Intros entry instead of yielding ghost notifications.

**P2 — Capture the diagnosis with device logs.** The `GROUP_INVITE_STORE_PENDING_*`, `GROUP_HANDLE_INCOMING_MSG_*`, and `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING` flow events already exist; pulling user-b's logs will confirm which drop branch fired and pin the exact cause.

---

## Evidence map

| Point | Files |
|---|---|
| Q1: TTL = `Duration(days: 7)`; `expires_at = min(receivedAt+7d, policy)` | `pending_group_invite.dart:4,74-79`; `send_group_invite_use_case.dart:639` |
| Q1: hard-delete sweep exists but has **zero** production callers (DI-wired only) | `pending_group_invites_db_helpers.dart:148-179`; `pending_group_invite_repository_impl.dart:215-218`; `pending_group_invite_repository.dart:33`; `main.dart:1003-1004` |
| Q1: read path has no expiry filter; expired rows still render as "Expired" | `pending_group_invite_repository_impl.dart:160-163`; `pending_group_invites_db_helpers.dart:43-72`; `pending_group_invite_card.dart:27`; `orbit_wired.dart:574-575` |
| Q1 caveat: 24h freshness gate drops invite at receive (and re-checks at accept), no row stored | `group_invite_payload.dart:19,27,287-289`; `group_invite_auth.dart:55-61,129,196`; `handle_incoming_group_invite_use_case.dart:494,498-499`; `accept_pending_group_invite_use_case.dart:145,172` |
| Q1: silent early-return (no-store) branches | `handle_incoming_group_invite_use_case.dart:497-608` |
| Q2: in-app notification gated behind `result != null` + non-member returns null | `group_message_listener.dart:819,827,834-835`; `handle_incoming_group_message_use_case.dart:140-148,176-205` |
| Q2: invitee subscribes to GossipSub only on accept (materialize) | `handle_incoming_group_invite_use_case.dart:929`; `group_invite_listener.dart:215-244` |
| Q2: invite arrival fires no notification | `group_invite_listener.dart` (no `NotificationService` / no `maybeShowNotification`) |
| Q2: remote FCM fallback shows notification with no membership/group checks; generic copy | `background_push_notification_fallback.dart:6-7,21-32,139-143`; `background_message_handler.dart:96-129` |
| Tap → `.missing()` → silent no-op (no navigation); redirects to Intros only if `hasPendingInvite` | `main.dart:2741-2764`; `resolve_group_notification_route_target_use_case.dart:36-79` |
| Creator adds every invitee to roster at invite time; no back-channel removes them | `create_group_with_members_use_case.dart:199-218`; `add_group_member_use_case.dart:311` |
| Local group/members/key + topic-join created only via `materializeAcceptedGroupInvitePayload` (accept only) | `handle_incoming_group_invite_use_case.dart:774-991` (saveGroup:874, saveMember:890, saveKey:900, join:929); `accept_pending_group_invite_use_case.dart:287` |

---

## Confidence & how to confirm on device

**High** on the mechanics and on both Q1 and Q2 — independently re-verified by reading source (TTL constants, the dead-code sweep with zero callers, the 24h freshness gate at receive+accept, the membership-gated in-app notification, the membership-blind remote fallback, and the silent `.missing()` tap no-op at `main.dart:2764`).

**Medium** only on the single link that lives outside this repo: whether the **go-mknoon relay/server actually pushes** `group_message` FCM notifications to a roster-but-unaccepted invitee. The Dart client provably *will display* such a push membership-blind, but the server's recipient-selection logic is not in this codebase.

**To raise confidence to full:**
1. Pull user-b's device FLOW logs and look for which `GROUP_INVITE_STORE_PENDING_*` branch fired (especially `staleMembershipFreshness` vs `unknownSender` vs `decryptionFailed`), plus a `GROUP_NOTIFICATION_ROUTE_GROUP_MISSING` on tap.
2. Inspect `go-mknoon` server inbox/push recipient-selection to confirm it targets unaccepted invitees.
3. Compare the relative timing of invite issuance vs user-b's first online processing to confirm/exclude the 24h-freshness drop.

---

## Appendix — methodology

A deterministic 13-agent workflow:

- **Investigate (6 parallel `code-explorer` agents):** invite lifecycle/expiry · Intros-tab population · notification firing timing · notification-tap-to-nothing · membership & pubsub delivery · invite-delivery-vs-group-existence.
- **Verify (6 adversarial agents):** each dimension's claims independently re-traced with fresh file:line evidence and confirm/refute/uncertain verdicts. *(The verifier on the expiry dimension caught the **24h freshness gate** the investigator initially missed — the most scenario-relevant finding.)*
- **Synthesize (1 agent):** merged confirmed claims into the root-cause story and prioritized fixes above.
