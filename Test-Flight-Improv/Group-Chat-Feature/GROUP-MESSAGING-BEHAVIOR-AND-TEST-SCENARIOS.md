# Group Messaging — Behavior & Test-Scenario Reference

> **Purpose.** A single place that says *what SHOULD happen* for every group-messaging sub-feature, across every dimension (chat window, settings page, encryption, notifications, per-role), so you can (a) reference expected behavior when you test, and (b) know what *should* happen when you debug. It also catalogs the test scenarios — existing and proposed — that exercise each behavior and catch each known bug class.
>
> **How this was built.** Graph-first recon over the architecture graph (`graphify-arch/`), one agent per sub-feature, each mapping verified against real source with `file:line` evidence, then an adversarial verify pass, then a cross-reference of the field-reported bug scenarios (S1–S7) to root causes. Authored 2026-06-14 against branch `121-improvements`. Many fixes (111/112/113/117/118/119/120/121) are landed-but-uncommitted on this branch — see [Part 3](#part-3--known-bug-cross-reference) for what is fixed vs build-skew vs open.
>
> **Caveat on `file:line`.** Files on this branch are actively edited; line numbers drift. Trust the **symbol names** and **file paths**; treat line numbers as approximate. Where the verify pass found drift, the symbol is still correct.

---

## How to read this doc

**Actor convention** (matches the reported field scenarios):

| Label | Role |
|-------|------|
| **user-a** | Creator / admin — the actor performing most admin actions |
| **user-b** | An existing member (sometimes promoted to admin) |
| **user-c** | The target / newly-added member |
| **user-d** | A late joiner (accepts after metadata changed) |

**The five dimensions** every lifecycle event is described against:

1. **Chat window** — system/timeline cards and banners that appear in the group conversation stream.
2. **Settings page** — the Group Info screen: roster, admin badges, name/description/photo, which action buttons appear/enable.
3. **Encryption** — key epoch / rekey / sender-binding behavior; any key-epoch banner.
4. **Notifications** — which local/push notifications fire, to whom, mute/debounce.
5. **Per-role** — what each of {admin-actor, other members, the target/new member, a removed/external party} observes.

---

## Core concepts (read this first — it explains most bugs)

These five "laws" cut across every sub-feature. Almost every reported field bug is an instance of one of them.

### 1. Delivery is connectivity-bound, not friendship-bound — and has two legs

A group send/event reaches a member through **up to three channels**, and *being friends is irrelevant* to all of them:

- **Live GossipSub (`floodPublish`)** — Go publishes to **every peer that is BOTH (a) connected to the sender over a libp2p circuit-relay AND (b) subscribed to the group topic** (`topic.ListPeers()`). `topic.Publish()` returning `nil` does **NOT** mean anyone received it; publishing to zero peers still "succeeds." (`go-mknoon/node/pubsub.go`, `WithFloodPublish(true)`)
- **Relay inbox custody (store-and-forward)** — the message/event is also stored on the relay for `recipientPeerIds`, so offline/unmeshed members catch up on their next drain. **`recipientPeerIds` is computed from the *sender's local roster*** — if the sender's roster is stale/incomplete, a member is silently omitted from *both* the live and the stored copy.
- **Direct P2P** — membership/role/metadata events are *also* fire-and-forget sent directly to each member device.

> **This is the entire "C's message reaches A but not B" bug class.** If C has a circuit to A but not to B, only A gets it live; B must catch up via relay custody — and only if B is in C's `recipientPeerIds`. (See [§12 Send text](#12-sending-a-text-message) and [Bug class B](#part-3--known-bug-cross-reference).)

### 2. Authorization is evaluated against the LOCAL roster, on both ends

Every mutating action (edit metadata, add/remove member, change role, dissolve) is authorized **from the actor's own local `group.myRole` / `selfMember.permissions`**, and every *receiver* re-checks the sender's **current role in the receiver's local roster** before applying.

> **Consequence:** if a promotion/demotion event was never *applied* on a device, that device acts on stale role. A demoted admin who never applied the demotion can still edit/add (S5); a promoted admin whose promotion hasn't applied locally can't add yet (S1-bug2). And a receiver whose roster lags can transiently *reject* a legitimate transition from a just-promoted admin. (See [Bug class C](#part-3--known-bug-cross-reference).)

### 3. Convergence is per-receiver verification, gated by a signed transition audit

Membership/role/metadata/dissolve events are **v3 signed system payloads** (`{"__sys": ...}`). Each receiver independently runs:

1. **stale-event gate** (`_shouldIgnoreStaleMembershipEvent` / `_shouldIgnoreStaleMetadataEvent` vs a watermark — drops older-than-known events),
2. **authorized-sender gate** (`_isAuthorizedMembershipEventSender` — sender must currently be admin in the receiver's roster),
3. **signed transition audit** (`verifyGroupTransitionAudit` — Ed25519 over a canonical payload binding actor peerId/device/transport/key-package + a pre-transition state hash),

and **drops the event silently** (FLOW telemetry only) on any failure. A common failure is **`device_mismatch`/`transport_mismatch`**: the signer omitted its device/transport binding, or the receiver's roster doesn't yet know the sender's device. This was the root cause of the historical dissolve bug (121 B4) and is the same family behind metadata-not-converging (S1/S3). (See [§Convergence accept-gate](#the-convergence-accept-gate) in Part 2.)

### 4. One shared group key per epoch — rotated on *removal/leave*, not on add/promote/demote/metadata

Group E2EE is a **single shared AES-256-GCM key**, versioned by an integer **`keyEpoch`** (a.k.a. `keyGeneration`). There are **no Signal-style per-sender ratchets**; each message is encrypted once with the current group key and authenticated by the sender's Ed25519 signature over `groupId|epoch|ciphertext`.

- **Created** at epoch 1.
- **Rotated (epoch+1)** only on **member removal** and **voluntary leave** — the admin/leaver generates the next key, distributes it 1:1 (ML-KEM-encrypted) to **remaining members only**, then promotes it. This is the forward-secrecy event.
- **NOT rotated** on add, promote, demote, name/description/photo edit, or reaction.
- A removed member is excluded from the new epoch → cryptographically locked out.
- **30-second grace window** keeps the previous key so in-flight stragglers still decrypt; messages past grace under an old/unknown epoch are silently dropped at the validator.

### 5. System/membership events never notify; metadata propagates by snapshot (photo is two-stage)

- **No notification** fires for any group system event (member added/removed, role change, metadata edit, dissolve). They update local state + render a timeline card only. (Intentional "calm" policy.)
- **Metadata** (name/description/photo) propagates as a **full signed `groupConfig` snapshot** over the three channels **plus** a refresh of still-pending invites (so a late joiner's invite carries fresh metadata).
- **Photo lags worst** because it is **two-stage**: the wire payload carries only `avatarBlobId`/`avatarMime`, *not the bytes*. Each receiver must separately download+decrypt the blob from the relay and only then set `avatarPath`. Text fields converge with the snapshot; the photo appears later (or never, if the blob fetch fails). (See [Bug class A](#part-3--known-bug-cross-reference).)

---

# Part 1 — Lifecycle behavior spec

Each section: trigger/preconditions → the five dimensions → known fragilities → tests that lock it.

---

## 1. Creating a group

**Trigger.** user-a taps create-group in Orbit, picks a `GroupType` (chat / announcement / qa), selects ≥1 contact (the "Start group" panel only appears once a contact is selected — **no solo group via UI**), optionally types a name, taps Start.
**Preconditions.** Identity loaded with peerId + publicKey + ML-KEM public key (else `ArgumentError`); P2P node initialized; total members ≤ 50.

- **Chat window.** No window exists until create completes; on success the picker `pushReplacement`-navigates straight into the new group conversation. The creator's stream shows a `members_added` system card. No `group_created` chat card (that event lives only in the group event log).
- **Settings page.** Group Info reflects the new `GroupModel`: resolved name (auto-generated `"<u1>, <u2>"` / `"<u1>, <u2> +N"` if blank), **no description and no photo** — *the create UI never collects them* (they can only be set later via Edit details). Roster shows user-a with an **admin** badge and each invited contact as a **writer**.
- **Encryption.** Key epoch **1**, random AES group key minted in Go. The key is handed to invitees **inside** each per-recipient encrypted invite (keyed to their ML-KEM public key). A contact with no ML-KEM key still gets a roster row but is recorded as missing-key / encryption-skipped.
- **Notifications.** None to the creator. Invitees get a P2P group invite (drives their invite card). The live `members_added` GossipSub publish typically reaches **zero** peers at create time (invitees not yet subscribed) — convergence relies on the per-recipient invites, not this publish.
- **Per-role.** **user-a:** sole admin (`myRole=admin`, `createdBy=self`). **user-b/user-c (invitees):** saved as `writer`, *not yet joined on their side* — they hold a pending invite.

**Known fragilities.** Create collects no description/photo (low); `topicName` is client-derived (Go doesn't return it); a config-sync rollback after create succeeds leaves a **created-but-creator-only** group (`membershipSyncRolledBack=true`) rather than fully aborting; `members_added` publish failure is non-fatal (no local "added" card if it throws).
**Tests.** `create_group_use_case_test.dart`, `create_group_with_members_use_case_test.dart`, `create_group_picker_wired_test.dart`, plus the device harnesses. **Coverage: strong.**

---

## 2. Adding a member (invite send)

**Trigger.** Admin → Group Info → Add member → ContactPicker → select → confirm.
**Preconditions.** P2P node started; actor has `inviteMembers` permission; group not dissolved; **group recovery NOT in progress**; target has a deliverable identity + ML-KEM key; supplied key matches the latest local key (TOCTOU re-check at send time); membership limit not exceeded.

- **Chat window.** On a *successful* `members_added` publish, a `sys-members_added` card ("**user-a added user-c**") renders for user-a and existing members. **The local card is written only if publish did not fail** — if the publish/relay/direct block throws, no "added" card appears even though the member was added (silent gap).
- **Settings page.** The new member appears in user-a's roster **immediately as a writer** — committed locally *before* any delivery confirmation. A per-member delivery indicator + **Resend Invite** affordance is backed by the inviter-tracker. Existing members see the new member after they apply the `members_added` snapshot.
- **Encryption.** **No key rotation on add.** The invite carries the **current** group key inline at the current epoch (the new member can decrypt current-epoch traffic; addition is not a forward-secrecy event). Each invite is individually ML-KEM-encrypted to the recipient *device's* key and ML-DSA-signed by the inviter; it embeds the **full `groupConfig` snapshot** (name/desc/avatar + all members + their key material).
- **Notifications.** None fired by the send side directly. The admin sees a SnackBar ("N members invited" / "N added, but <issues>"). The invitee's notification happens when *their* device processes the invite.
- **Per-role.** **user-a:** authorizes, saves member locally, pushes merged config to Go validator (rolled back on failure — *also restores the avatar and deletes invite-attempt rows*), broadcasts `members_added`, fans individual signed+encrypted invites to **every registered device** of the recipient, persists per-peer delivery status. **user-b:** not contacted by the fan-out; learns via `members_added` (live + relay replay + direct). **user-c:** receives one encrypted invite per device; still pending until they accept. **Removed/external:** can't be picked (picker lists contacts not already in the group).

**Known fragilities.** Member is committed to the roster *before* delivery — if all invites fail, the roster shows a member who never got the key (only the tracker marks it pending; no auto-removal). Per-peer tracker collapses multi-device outcomes (one device delivered + one failed shows last-writer). Add does not advance the epoch (current-epoch readability of a just-added member is by design).
**Tests.** `send_group_invite_use_case_test.dart`, `add_group_member_use_case_test.dart`, `resend_group_invite_use_case_test.dart`, `invite_round_trip_test.dart`, `contact_picker_wired_test.dart`. **Coverage: strong.**

---

## 3. Accepting an invitation (joiner side)

**Trigger.** Invited user taps **Accept** on a `PendingGroupInviteCard`.
**Preconditions.** A pending invite exists and is not expired; identity loads.

- **Chat window.** No persistent banner for accepting; a transient **"Joined {name}"** snackbar fires and the group conversation **auto-opens** (B1 fix). A local `member_joined` timeline card is saved, and a `member_joined` system message is published to existing members. Drained inbox history (catch-up) materializes into the conversation.
- **Settings page.** The joiner's roster is built **entirely from the invite's frozen `groupConfig` snapshot** (`myRole=member`, name/description/avatarBlobId, every member + their key material) — a **full overwrite, no merge** against live state. The avatar is downloaded best-effort and only adopted if the invite metadata isn't stale vs a refreshed group.
- **Encryption.** Joiner persists `GroupKeyInfo(keyGeneration: payload.keyEpoch)` and calls the Go bridge to subscribe to the topic. The invite is verified before materialization (signature, recipient-device binding, single-use welcome-key-package tombstone, attestation). The joiner does **not** re-mint the key — it adopts the invite's epoch.
- **Notifications.** None to the joiner for their own accept (snackbar + auto-open only). Existing members *may* get the `member_joined` event, best-effort.
- **Per-role.** **user-c (joiner):** card spinner during processing; on success the invite is deleted and the group auto-opens. **user-a/user-b:** receive `member_joined` (live or relay replay) — best-effort; their roster gains user-c when their listener materializes the join. **Removed user-c re-accepting:** the retained read-only shell is re-materialized (B3 re-join), not rejected as duplicate. **Wrong-identity recipient:** rejected ("Invite is for another identity").

**Known fragilities.** The orphaned **"recovery still catching up"** strings exist in all locales but have **zero call sites** (the intended "still catching up" UX does not exist on HEAD — see S7-bug1). A `bridgeError` that returns a *non-null* group is **not** retried → shows "Failed to accept invite" while a usable group row exists *and the invite card is already deleted* (sharp inconsistency). Roster reconciliation is a full overwrite from a possibly-stale frozen snapshot (the scenario-7 stale-metadata class — S7-bug3). The `member_joined` broadcast carries **name only**, not the joiner's key material, and frequently reaches zero peers at publish time.
**Tests.** `accept_pending_group_invite_use_case_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `group_invite_accept_spinner_simulator_test.dart`, `group_new_member_onboarding_test.dart`. **Coverage: strong.**

---

## 4. Removing a member (admin kicks)

**Trigger.** Admin → Group Info → per-member Remove → confirm dialog. **Admin-only on both the UI and the receiver side.**
**Preconditions.** Group exists, not dissolved; actor has `removeMembers` permission; **recovery NOT in progress**; not removing the last admin; a removed-member-snapshot repo is present.

- **Chat window.** Remaining members and the removed member both get a "**user-a removed user-c**" system card. Content messages at/after the removal cutoff are deleted on both sides.
- **Settings page.** Admin's roster drops user-c after success (or restores it on any failure → full rollback). Remaining members apply the authoritative snapshot and drop user-c.
- **Encryption.** **Key re-mint (forward secrecy).** `rotateAndDistributeGroupKey` generates epoch+1, distributes it 1:1 (ML-KEM-encrypted, signed) to **remaining members' deliverable devices only**, promotes the admin's own key **last**, then broadcasts a `key_rotated` card. The removed member is excluded (no longer in `getMembers`) and its local keys are wiped.
- **Notifications.** None (membership change is silent). The removed member gets a soft `groupRemovedStream` signal to refresh UI.
- **Per-role.** **user-a:** full pipeline; on publish-OR-rotation failure the **entire removal rolls back** (member restored). **user-b (remaining):** verifies the signed `member_removed` (sender must be admin), drops the member, applies snapshot, renders the card, advances watermark, prunes post-cutoff content; separately receives the new key. **user-c (removed):** group is **retained as a read-only shell** (NOT hard-deleted) — "Admin removed you" card, composer auto-gates read-only; can read retained history, cannot send or decrypt future traffic. **External/non-admin forging a removal:** rejected.

**Known fragilities (this is a fragile path).**
- **Key re-mint is removal-blocking & all-or-nothing:** if any remaining member has *no ML-KEM-capable device at all* it hard-blocks; a merely-offline member is retried (5×) + relay-inbox fallback before counting as failed. A genuinely undeliverable member makes the kick impossible until they're reachable, and the whole removal rolls back.
- **Partial-commit window:** the `member_removed` broadcast + relay store + direct sends run **before** the key rotation; if rotation then fails, the admin rolls back *local* state only — peers that already applied the removal diverge until the next event.
- **Authorization asymmetry (latent, not UI-reachable):** the *use case* honors a non-admin's explicit `removeMembers` grant, but every *receiver* accepts `member_removed` only from an admin — so such a removal would never converge. (Through the UI, remove is admin-only on both ends, so this is latent.)
**Tests.** `remove_group_member_use_case_test.dart`, `member_removal_integration_test.dart`, `rotate_and_distribute_group_key_use_case_test.dart`, `group_membership_smoke_test.dart`. **Coverage: strong.**

---

## 5. Re-adding a previously-removed member

**Trigger.** Admin re-invites someone previously removed (who retains a read-only "keyless shell" locally).
**Distinguishing signal everywhere:** `getGroup(id) != null && getMember(id, ownPeerId) == null` ⇒ retained-removed (vs a *voluntarily-left* member, who hard-deleted the group, so `getGroup == null`).

- **Chat window.** On user-c: the read-only shell becomes writable again after re-materialize; pre-removal history is preserved (post-removal content was purged at removal). On user-b/user-a: user-c reappears; a `member_joined` card renders at most once per (group, peer).
- **Settings page.** user-c reappears as active member on all rosters. On user-c's device the roster is rebuilt from the new signed config; **`myRole` is reset to `member`** (a previously-admin re-add loses admin unless the new config restores it).
- **Encryption.** The re-add invite carries the **current** group key+epoch. Because the *removal* already rotated the key (admin-removal flow rotates), the re-add carries a **post-removal** epoch the removed member never had — forward secrecy across the removal window holds **via the removal-time rotation** (not via re-add itself).
- **Notifications.** None re-add-specific (FLOW telemetry only).
- **Per-role.** **user-a:** re-add runs as a fresh add (target is locally a non-member). **user-b:** sees `member_joined` once (idempotent across live + replay). **user-c:** retained shell is re-joined — invite stored as pending (not `duplicateGroup`), accept re-materializes, composer re-opens. **Voluntarily-left member:** treated as a brand-new join (no retained shell).

**Known fragilities.** Re-join does **not** prune stale shell members (a member who left during the absence can linger). Classification depends on a non-empty `ownPeerId` — if null/empty, a legit re-add is mis-classified as `duplicateGroup` and silently dropped. A late `member_removed` arriving after re-add is handled by a best-effort repair that only fires when `removedAt` is known. A re-join carrying an **older** config snapshot can regress the visible name/description (avatar is watermark-guarded, name/desc is not). This is also where **122-plan B3** (re-add dropped at `storeIncomingPendingGroupInvite` + false-joined roster) lives — PLAN ONLY.
**Tests.** `store_pending_group_invite_use_case_test.dart`, `handle_incoming_group_invite_use_case_test.dart`, `member_removal_integration_test.dart`, `group_real_crypto_onboarding_test.dart` (old key cannot decrypt). **Coverage: strong.**

---

## 6. A member leaves the group (voluntary self-leave)

**Trigger.** Group Info → **Leave Group** (rendered for every member when not dissolved). **No confirmation dialog** (unlike Dissolve/Delete/Remove).
**Preconditions.** Identity loads; the leaver is currently a member. **Last/sole admin is BLOCKED** from leaving (must Dissolve instead). Key rotation requires every remaining member be deliverable (ML-KEM-capable device).

- **Chat window.** Leaver: a "user-c left the group" row is saved then the entire conversation is wiped (hard-delete) and the screen pops to the list. Remaining members: a "**user-c left the group**" card (text chosen by username equality actor==subject), and the leaver's at/after-removal content is pruned.
- **Settings page.** Leaver: Group Info popped; group no longer exists locally. Remaining members: roster drops the leaver.
- **Encryption.** Leaver **rotates the key to epoch+1**, distributing it to remaining members **before** local cleanup, then wipes its own keys. Remaining members adopt the rotated epoch. *(The rotated key reaches remaining members via the separate 1:1 distribution + `key_rotated` message — NOT via the `member_removed` handler.)* Self-leave is symmetric (signs its own binding), so it does **not** hit the dissolve binding-asymmetry.
- **Notifications.** None — leaves are silent (system payload returns before the notify block).
- **Per-role.** **Sole/last admin:** blocked ("You can't leave this group because you're the only admin"). **Other admin / member:** normal leave. **Remaining members:** drop the leaver, render the card, advance epoch, silently. **Leaver (most destructive outcome):** full hard-delete of group + members + keys + messages locally (contrast: admin-removal *retains* a read-only shell).

**Known fragilities.** Leave is **hard-blocked** if any remaining member is undeliverable → user can be *trapped*. **No confirmation** + irreversible local hard-delete on a single mis-tap. Order-dependent partial-failure: broadcast+rotation run *before* the native `group:leave`; if leave then fails, peers already rotated past the still-present leaver (rollback is local-only). A leave **does** carry a metadata snapshot, so it can reconcile name/desc/photo on remaining members.
**Tests.** `leave_group_use_case_test.dart`, `member_removal_integration_test.dart`, `group_info_wired_test.dart`. **Coverage: partial** — **GAP: no multi-device test asserts remaining peers' rosters drop a *voluntary* leaver** (admin-removal is covered; voluntary-leave fan-out is not). See GS-H01.

---

## 7. Promoting a member to admin

**Trigger.** Admin → member's popup → "Make Admin" → confirm. (Promotion *to admin* requires the actor be `MemberRole.admin`; a writer-with-`manageRoles`-override cannot promote to admin.)
**Preconditions.** Group exists, not in recovery; target exists; target not already admin.

- **Chat window.** "**user-a made user-c an admin**" system card for everyone (deterministic id, deduped). The raw `__sys` payload is never rendered as a bubble.
- **Settings page.** user-c's role badge flips writer→**admin**; the per-member menu item now reads "Remove Admin". The actor sees a SnackBar. **On user-c's own device,** the incoming role event sets `myRole=admin`, **unlocking the full admin management surface** (edit details, dissolve, add/remove, role toggles).
- **Encryption.** **No rotation / no rekey.** Integrity is the signed transition audit (binds actor device/transport/key-package + pre-transition state hash); the relay/offline copy rides the current key epoch.
- **Notifications.** **None** (system payload). Promotee learns of it only via the in-chat card + UI unlock on next view.
- **Per-role.** **user-a:** authorizes, mutates role, syncs Go config, publishes the signed audit over 3 channels; on bridge failure rolls the role back. **user-b:** verifies + applies; sees the badge change. **user-c:** verifies the audit + receive-side anti-escalation, sets own `myRole=admin`. *(In a normal chat group this does NOT change send ability — they could already write; what they gain is management actions.)* **Removed/external:** rejected.

**Known fragilities.** **The "Make Admin" toggle is binary admin↔writer** — a former `reader` becomes `writer`, not `reader` (no UI sets `reader`). Receive-side authorization recomputes from the receiver's *current local roster*, so a stale receiver can **transiently reject** a legitimate promotion (mitigated by the stale-event guard + later replay). The receiver also applies the **full embedded config snapshot** (so metadata/roster ride along — and can even change the receiver's own role). Promotion does **not** suffer the dissolve binding-asymmetry (it signs a real device/transport binding).
**Tests.** `update_group_member_role_use_case_test.dart`, `group_membership_smoke_test.dart`, `group_admin_metadata_convergence_test.dart`. **Coverage: strong.**

---

## 8. Demoting an admin

**Trigger.** Admin → admin member's popup → "Remove Admin" → confirm. **Hard-coded admin→writer** (never reader).
**Preconditions.** Recovery not in progress; not demoting the last admin (would drop admin count to 0).

- **Chat window.** "**user-a removed admin from user-c**" system card (system payload, no notification, no key-epoch banner).
- **Settings page.** user-c's badge flips admin→**writer** for all viewers. **On user-c's own device,** `myRole=member` ⇒ every admin control (edit/add/remove/dissolve/role) disappears.
- **Encryption.** **No key rotation on demotion.** The demoted device keeps the current group key — demotion is **policy/UI + receive-side authorization only, not cryptographically enforced**.
- **Notifications.** None.
- **Per-role.** **user-a:** runs the role update, publishes the signed audit; rolls back on bridge failure. **user-b:** applies, sees the badge change. **user-c (demoted):** loses admin controls; **in a normal/chat group can STILL send messages** (the write gate only blocks non-admins in *announcement* groups). They learn of demotion only via the in-chat card or the missing controls.

> **Important for testing demote:** *Demote does not make a user read-only in a chat group.* The confirmation copy itself says "They will lose admin-only **actions**," not write access. Read-only-on-demote happens only in **announcement** groups.

**Known fragilities.** Receive-side authority is from local state (eventual-consistency race). Receiver timeline text uses the *receiver's* local `previousRole`, so different members can see different text for the same event. A malformed/missing `newRole` defaults to `writer` (silent demote of an intended promotion; a non-empty *invalid* role throws instead). **This is the S5 cluster:** if the demotion event never *applies* on user-b, user-b keeps `myRole=admin` locally and can still edit/add (see [Bug class C](#part-3--known-bug-cross-reference)).
**Tests.** `update_group_member_role_use_case_test.dart`, `group_message_listener_test.dart`, `group_admin_metadata_convergence_test.dart` (rejects demoted-admin metadata). **Coverage: partial** — **GAP: no multi-device test asserting a demoted admin loses authority across ALL peer devices in real time.** See GS-C05.

---

## 9. Admin vs member permission matrix

Management actions are gated at **four layers**: (1) **UI** — non-admins simply don't see the controls (no greyed buttons); (2) **use case** — each operation re-checks authorization before mutating; (3) **receiver** — each event is dropped unless the sender is currently authorized *and* the signed audit verifies; (4) **Go transport validator** — rejects publishes from non-members (`non_member`) and, in announcement groups, non-admins (`unauthorized_writer`).

| Action | Who can | Enforced where | Rotates key? | Notes |
|--------|---------|----------------|--------------|-------|
| Send text/media | any member (chat/qa); admin only (announcement) | `_canWriteForGroup` + Go `isAllowedWriter` | no | `reader` role is **not** enforced read-only in chat/qa |
| React | any member (incl. announcement non-admins) | `_canMutateReactions` | no | deliberate carve-out |
| Edit name/desc/photo | admin only | `updateGroupMetadata` (checks `myRole==admin` **only** — ignores fine-grained `editMetadata` permission) | no | one "Edit details" path for all three |
| Add member | admin (or `inviteMembers` override) | `addGroupMember` | no | |
| Remove member | admin (or `removeMembers` override*) | `removeGroupMember` | **yes** | *receiver accepts only from admin → override won't converge |
| Promote/demote | admin (`manageRoles`); promote-to-admin needs actor be admin | `updateGroupMemberRole` | no | blocks last-admin removal |
| Dissolve | admin only | `dissolveGroup` | no | |

**Known fragilities.** `MemberRole.reader` is defined + shown as a badge but **not enforced** as read-only for chat/qa groups (read-only only via announcement type). No UI assigns `reader`. `updateGroupMetadata` ignores the fine-grained permission model (admin-binary only). Removed member can briefly still publish until the config update propagates (no rotation = no immediate cut-off; rotation in the wired layer closes it). Receiver re-checks from possibly-stale local roster.
**Tests.** the `update/remove/role/metadata/add` use-case tests + `pubsub_test.go`/`pubsub_authorization_forward_test.go`. **Coverage: strong** (override convergence is unit-only — GAP, see GS-C07).

---

## 10. Editing group name & description

**Trigger.** Admin → Group Info → Edit details → change name and/or description → Save (`_applyMetadataEdit`).
**Preconditions.** **Recovery NOT in progress**; `myRole==admin`; trimmed name non-empty; signing succeeds.

- **Chat window.** A single "**user-a updated the group details**" card renders for everyone (a normal LetterCard, right-accent for the actor, left-accent for receivers). **The text never says WHAT changed** (name vs description vs photo are identical). On receiving any `sys-group_metadata_updated`, the open conversation refreshes the app-bar title/description live.
- **Settings page.** Group Info shows the new name; description shows only if non-empty. Actor reloads + SnackBar "details updated." Receivers reflect the new values once the snapshot applies.
- **Encryption.** **No rekey.** Integrity = a `groupConfigStateHash` + a signed actor-event envelope (verified against the sender member's trusted public key) + a signed transition audit binding actor device/transport.
- **Notifications.** **None** (system payload). The pending-invite refresh can itself re-notify not-yet-joined targets via the invite path.
- **Per-role.** **user-a:** persists locally first, then signs + publishes the snapshot over **four channels** — live GossipSub, relay inbox (offline members), direct P2P, **and `refreshPendingGroupInvitesForMetadataChange`** (re-snapshots still-pending invites so late joiners get fresh metadata). **user-b:** receives → stale-watermark gate → actor-signature verify → applies name/desc/avatar/members → app-bar refresh. **user-c (late joiner):** does **not** get the live event; converges via the invite snapshot (and the pending-invite refresh, if delivered before accept). **Removed/external:** pruned from / can't pass the verify.

**Known fragilities.** Card text is field-agnostic. **Actor-signature verify keys off the sender's *existing* member public key** — if the metadata event arrives before the receiver knows the sender (e.g. just-promoted admin not yet converged, or empty publicKey), the **entire update is silently dropped** (FLOW-only). **This is the S1/S3 metadata-not-received root** (Bug class A). Stale-gating is microsecond-timestamp LWW with no vector reconciliation — concurrent edits can silently drop one. Member reconciliation runs even when the metadata watermark blocks the field apply (a stale event can still mutate the roster). A snapshot can change the *receiver's own* `myRole`. A member with invalid key material aborts the **whole** snapshot apply (fail-closed).
**Tests.** `update_group_metadata_use_case_test.dart`, `group_admin_metadata_convergence_test.dart` (+ simulator), `group_message_listener_test.dart`. **Coverage: strong.**

---

## 11. Changing the group photo

**Trigger.** Admin → Group Info editor → pick/remove photo → Save (flows through the same `updateGroupMetadata` path as name/desc).
**Preconditions.** As §10, plus avatar ops are **double-gated on recovery**; for replace, the relay upload must succeed (else "upload photo failed").

- **Chat window.** Same generic "updated the group details" card — does **not** distinguish a photo change. No separate card when the bytes finish downloading.
- **Settings page.** Editor toggles "Add photo"/"Change photo"; a "Remove photo" button shows when an avatar exists. **On a receiver during the lag, the avatar tile shows initials** (`GroupAvatar` fallback) until `avatarPath` resolves; name/description already reflect the new values.
- **Encryption.** Avatar blob encrypted as standard group media (per-blob key, ACL = active member peerIds **at upload time**). The **wire payload carries only `avatarBlobId`/`avatarMime` — NOT the bytes.** No rekey.
- **Notifications.** None photo-specific.
- **Per-role.** **user-a:** sees the new photo immediately (local commit), then uploads + publishes over the same 4 channels as §10. **user-b/user-c:** apply name/desc/blobId synchronously, then **asynchronously download+decrypt the blob** before `avatarPath` is set — *this second stage is why the photo lags name/desc, and why it silently stays as initials if the fetch fails*. **Late joiner:** materializes blobId from the invite snapshot then downloads (watermark-guarded). **Removed/external:** excluded from the blob ACL → cannot decrypt the new photo.

> **This is the recurring "photo not updating" bug (S1-bug4 / S2-bug1 / S3-bug3).** Photo propagation is **two-stage**: text via snapshot, bytes via a separate per-receiver relay fetch. A failed/slow blob fetch, a stale-snapshot blobId for a late joiner, or an ACL that excludes a concurrently-joining member all leave the photo as initials while name/description are correct.

**Known fragilities.** Two-stage lag (structural). Silent blob-download failure → initials fallback, retry only opportunistically on a duplicate metadata event. Upload ACL is point-in-time (no per-photo re-key for late joiners). The equal-watermark replay-repair path re-applies name/description but **ignores the avatar** (avatar has its own separate retry seam).
**Tests.** `group_admin_metadata_convergence_test.dart` (asserts avatar **bytes** converge + late-invitee catch-up), `group_avatar_storage_test.dart`, `group_new_member_onboarding_test.dart`. **Coverage: strong.**

---

## 12. Sending a text message

**Trigger.** An allowed-writer taps Send.
**Preconditions.** Group joined + not dissolved; passes `isAllowedWriter`; key material present (else `bootstrap_pending`); sender is in config membership (else `unauthorized`).

- **Chat window.** Outgoing row appears at **'sending'** immediately, then resolves to **'sent'** (check), **'pending'/'inboxed'** (clock), or **'failed'** (error + tap-to-retry). Incoming messages show no status indicator.
- **Settings page.** Unchanged by sending.
- **Encryption.** Envelope encrypted+signed in Go with the group key at the **current stored epoch**. **No epoch change.** (A *stale local epoch* — e.g. post-rotation before resync — silently encrypts at the old generation → undecryptable for recipients on the new epoch; see GS-J03.)
- **Notifications.** Sender gets none (just the status indicator); recipient notifications are produced by receive-side listeners (§17).
- **Per-role / who actually receives.** Go runs `SendGroupMessageReliable`: concurrently (1) **relay inbox custody** for every active recipient and (2) **`floodPublish`** to connected+subscribed topic peers. Dart then decides the stored status from `expectedRecipientCount`, inbox custody (`inboxOk`), and **effective topic peers** (post-publish recount, GAP-2). **A member not connected+subscribed at publish time receives nothing live and depends entirely on relay inbox custody.**
  - **user-a (admin/creator):** inviter-tracker device — excludes genuine not-yet-joined invitees from the recipient set (INV-106) but **always keeps the creator**.
  - **user-b/user-c as recipients:** live only if dial-connected + topic-subscribed; otherwise via relay drain.
  - **just-joined user-c as sender:** a joiner device includes the creator + all incumbents (REG-119 fix), avoiding the old vacuous `expectedRecipientCount:0`.

> **This is the "C reaches A but not B" bug (S1-bug3 / S2-bug2 / S3-bug2).** Two legs each create subset delivery: (1) live mesh asymmetry (C↔A circuit but not C↔B), and (2) relay custody scoped to `recipientPeerIds` from the **sender's local roster** — a stale roster omits a member from *both* legs. **Group fanout does not depend on friendship.** (Bug class B.)

**Known fragilities.** `expectedRecipientCount<=0` ⇒ a **vacuous 'sent'** regardless of delivery (REG-119 fixed the joiner-excludes-creator cause; the 0-recipient short-circuit remains a truthfulness hazard). Pre- vs post-publish peer-count skew (GAP-2 recount mitigates; build skew can read a real delivery as 'pending'). Legacy plain-publish fallback marks 'sent' optimistically. Retrier **confirm-before-republish** ordering (GAP-3a) is load-bearing for dup avoidance.
**Tests.** `send_group_message_use_case_test.dart`, `send_group_message_recipient_eligibility_test.dart`, `group_messaging_smoke_test.dart`, `pending_message_retrier_test.dart`, `pubsub_delivery_test.go`. **Coverage: strong.**

---

## 13. Sending a media message

**Trigger.** Member attaches ≥1 image/video/voice and sends.
**Preconditions.** Durable repos present; allowed mime (jpeg/png/gif/webp/heic, mp4/quicktime video, mp4/aac/mpeg/ogg audio); passes magic-byte signature sniff; within size budgets.

- **Chat window.** Sender: optimistic card; durable path shows the local copy immediately. Receiver: spinner → decoded image / video-frame-with-play-overlay once downloaded+decrypted+verified; a **quarantined/failed blob shows "Media unavailable"** with a retry button. A video whose *thumbnail* fails to decode shows a benign placeholder (the video stays playable) — not "unavailable" (117 fix).
- **Settings page.** Unchanged.
- **Encryption.** **Each blob encrypted unconditionally** with a **fresh random per-blob AES-256-GCM key** (not derived from the group key). `contentHash` = SHA-256 of the **ciphertext**. Upload is **fail-closed** (no plaintext fallback). Key/nonce/scheme/hash travel inside the v3 group envelope. Receiver verifies relay-mime → ciphertext-hash (before decrypt) → GCM decrypt; any failure quarantines.
- **Notifications.** Standard group-message notification (§17) with a "Photo"/"Video"/"Voice message" placeholder body.
- **Per-role.** **Sender:** encrypt-once + ACL-from-current-roster + fanout. **user-b (present at upload):** in the ACL, downloads + verifies + renders. **user-c (joins after upload):** **NOT in the blob ACL → cannot fetch pre-join media (no backfill)**; but a brand-new member *can send* media to existing members. **Removed/external:** excluded by ACL + fail-closed verify; a removed-after-cutoff or unknown sender's whole message is dropped at the receiver.

**Known fragilities.** **No late-joiner media backfill** (point-in-time ACL). Group blobs are **never acked-for-deletion** on the relay (durability for slow members) → after TTL expiry an offline member's fetch fails/quarantines. Whole-message **fail-closed** on a single bad descriptor (drops text + all attachments). Divergent-id duplicate can survive id-only dedup (the double-card class). Video thumbnails are never transmitted (regenerated locally per receiver). A receiver **stale-epoch** rejection (`keyEpoch < latest`) drops the whole media message.
**Tests.** `group_media_fanout_test.dart`, `group_media_*_policy_test.dart`, `group_new_member_media_simulator_proof_test.dart`, `upload_media_use_case_test.dart`. **Coverage: strong.**

---

## 14. Dissolving a group

**Trigger.** Admin → Group Info → red Dissolve → confirm.
**Preconditions.** `myRole==admin`; not already dissolved. Receiver applies only if the sender is currently admin in its roster + the signed audit verifies.

- **Chat window.** Everyone gets one "**user-a dissolved the group**" card. Afterward the composer is read-only ("This group has been dissolved"). Further non-dissolve inbound events for the group are dropped.
- **Settings page.** A dissolved badge + a red "Group dissolved / read-only" status card; **all** management actions hidden; only **Delete locally** remains. **Dissolve does NOT delete locally** — the group/members/keys/history are retained read-only until the user taps Delete-locally.
- **Encryption.** **No key rotation.** Just a signed v3 terminal transition over the existing epoch; keys removed only on Delete-locally.
- **Notifications.** **None** (no production push handler consumes a dissolve; calm policy).
- **Per-role.** **user-a:** signs the audit **with its device/transport binding** (the B4 fix), publishes + relay-replays, marks `isDissolved` locally, leaves the topic. **user-b/user-c:** verify the audit, **relax the pre-transition state-hash check** (terminal event), set `isDissolved`, render the card, leave the topic → read-only everywhere; can only Delete-locally. **Removed/external:** not a recipient; a forged dissolve from a non-admin is rejected.

> **Friends & 1:1 DMs are never touched** by dissolve or Delete-locally — only group tables.

**Known fragilities.** **Binding-asymmetry (historical B4, fixed on this branch):** if a future call site reverts to null `actorDeviceId`/`actorTransportPeerId`, every receiver rejects with `device_mismatch`/`transport_mismatch` and the group stays live for everyone but the dissolver. The terminal pre-transition-hash relaxation weakens chain verification for dissolve specifically. **Offline-member loss:** if the relay inbox store fails for an offline member, they may never receive the dissolve and silently stay in a "live" group (admin sees only a "recovery" snackbar). No notification.
**Tests.** `dissolve_group_use_case_test.dart`, `group_delete_preserves_friends_and_dms_test.dart`, `group_message_listener_test.dart`, `group_recovery_e2e_test.dart`. **Coverage: strong** — **GAP: no fully-online multi-device test that a live dissolve flips every connected peer to read-only in real time.** See GS-I01.

---

## 15. Encryption & key epochs

**Model.** One shared AES-256-GCM key per group, versioned by integer `keyEpoch`/`keyGeneration`. **No per-sender ratchets.** Each message: encrypt once with the group key + Ed25519 signature over `groupId|epoch|ciphertext`. Wire = v3 `GroupEnvelope`.

**Lifecycle.** Minted at **epoch 1** on create. **Rotated (epoch+1)** only on **member removal** and **voluntary leave** (admin/leaver generates next key → distributes 1:1 ML-KEM-encrypted to remaining members → promotes own key **last** → broadcasts informational `key_rotated`). **Anti-rollback** in Go (`UpdateGroupKey` no-ops for epoch ≤ current; rotation refused during a 30s grace). **30s grace window** keeps the previous key so in-flight stragglers still decrypt.

- **Chat window.** A recipient that lacks the epoch's key (or is past grace via the subscription path) gets a placeholder **"Waiting for a newer group key to decrypt this message."**, replaced by the real message if repair succeeds, or finalized as **"Message could not be decrypted."** if it permanently fails. A message under an unknown/out-of-grace epoch on the *live gossip* path is **silently dropped at the validator** (no placeholder).
- **Settings page (Group Info "Security" card — NOT a chat banner).** Shows **"Encrypted — key epoch {N}"**; a **red open-lock "No group key on this device"** when the device has no key; and, for **any epoch > 1**, a **standing amber "Key change visible / Group key changed to epoch {N}"** warning.
- **Encryption.** As above.
- **Notifications.** None. `key_rotated` is logged only (does **not** apply the key).
- **Per-role.** **user-a (only rotator):** requires `rotateKeys` + `createdBy==self`; promote-own-key-last; aborts (no advance) if any device delivery fails. **user-b:** receives the new key via a **direct `group_key_update` envelope** (the actual self-heal), applies via anti-rollback. **user-c (new):** seeded the current key at **join**, not via rotation. **Removed:** excluded from new-epoch distribution (forward secrecy).

> **The "Encrypted — key epoch 1" flash near the bar (S2-bug4)** is the compact security chip showing during the brief *pending→encrypted* settle (`shouldShowCompactStatus` true while `!hasCurrentKey`). At epoch 1 it's purely the transition flash; there is no debounce/calm steady state, so users misread a benign indicator as an error. No data is lost. Any rotated group (epoch>1) shows the amber line *permanently*.

**Known fragilities.** Security-card UX reads as a warning/error even when healthy (epoch>1 amber is permanent; no-key is red). **`key_rotated` triggers no self-heal** — a member that missed the direct envelope stays on placeholders until a separate repair supplies the key. Out-of-grace stragglers are silently dropped on the live path. Per-message signature binds only `groupId|epoch|ciphertext` (device binding is enforced separately, not in the signature).
**Tests.** `pubsub_key_rotation_grace_test.go`, `pubsub_decryption_failure_test.go`, `rotate_and_distribute_group_key_use_case_test.dart`, `group_key_update_listener_test.dart`, `group_pending_key_repair_service_test.dart`. **Coverage: strong.**

---

## 16. Group recovery / resync

**What it is (answers the S6 "what does resync mean" question directly).** After the Go relay watchdog forces a node restart, Go raises a **sticky `needsGroupRecovery`** flag. On startup, app-resume, and the periodic retrier sweep, Flutter **rejoins all group pubsub topics + drains the offline inbox**, wrapped in a **process-global `GroupRecoveryGate`** counter. **While that counter is > 0, admin *mutations* are hard-blocked** with `StateError("Group recovery is in progress. Try again after resync completes.")`. "Resync/recovery" = *re-subscribing to group GossipSub topics and replaying the store-and-forward inbox*; it blocks edits to avoid mutating a possibly-stale roster mid-resync. The window is normally seconds; retry after it closes succeeds.

**What is blocked vs not:** add member, remove member, promote/demote, **edit name/description/photo**, and **announcement-group sends** all throw `groupRecoveryPendingError`. **Regular (non-announcement) chat sends are NOT blocked.** The **accept-invite / re-join path is NOT recovery-gated.**

- **Chat window.** Regular sends unaffected. No recovery banner in the conversation screen itself.
- **Settings page.** The **metadata editor sheet** shows an inline **"Please wait while this device catches up."** banner + a **"Waiting {N}s"** counter while the gate is active; a Save that races the gate maps the error to that friendly SnackBar. **The add-member picker does NOT special-case it** → shows the generic, misleading **"Failed to invite members."**
- **Encryption.** No rekey; rejoin re-subscribes with the **existing** stored key/epoch. Recovery does **no** roster/metadata reconciliation (pure transport re-subscribe + inbox drain).
- **Notifications.** None (internal FLOW telemetry only).
- **Per-role.** **user-a (admin):** transiently blocked on all admin writes. **user-b:** unaffected for regular sends; does its own silent rejoin. **user-c:** the membership event user-a tried to send is simply not produced until user-a retries.

> **This is the S6 cluster.** UX defects, all real and confirmed: (a) the message **reads like a failure**, not a transient state; (b) the gate is **process-global**, so a routine resume rejoin blocks admin edits on *unrelated* groups even when nothing failed; (c) **no auto-retry/queue** — the user must manually retry; (d) avatar can be **committed locally before the gate throws** → "image changed only locally"; (e) **no timeout** on the gate (a stalled drain blocks indefinitely with an ever-growing "Waiting Ns"); (f) a single **keyless group** prevents the Go ack from clearing, so recovery re-triggers every resume.

**Known fragilities.** All of (a)–(f) above. The orphaned "recovery still catching up" invite strings are dead code (S7-bug1 was build-skew, now fixed on HEAD).
**Tests.** `group_resume_recovery_test.dart`, `handle_app_resumed_group_recovery_test.dart`, `group_startup_rejoin_smoke_test.dart`, `rejoin_group_topics_use_case_test.dart`, `relay_session_test.go`, `watchdog_failover_test.go`. **Coverage: strong** (mechanics) — gaps are UX-shaped (see GS-D02/D03/D05/D07).

---

## 17. Group notifications

**Live (foreground) path.** For an incoming group **user** message, after persist + emit, a local notification fires **only if**: `senderId != self`, services wired, **group not muted**, not currently viewing that group, and no recent FCM for the same messageId. Title = group name, body = "**sender: text**" (or a media placeholder). A shared **`NotificationToneTracker`** allows **one audible tone per group per 30s** — the first sounds (high channel), subsequent in-window updates the same notification **silently**.

**FCM (background/foreground-fallback) path.** A data-only group push shows **only to a current member** (suppressed for pending-invitee / known-non-member / unknown group); uses **generic copy** ("New Message") so ciphertext never leaks; deduped per-message.

- **Chat window.** No special behavior; the message renders as a normal card regardless of notification outcome.
- **Settings page.** A **mute toggle** in Group Info persists `isMuted`.
- **Encryption.** Live body embeds the already-decrypted plaintext; FCM body is forced generic.
- **Notifications.** As above. **System/membership events (add/remove/role/metadata/dissolve) NEVER notify** on any path.
- **Per-role.** **Sender:** no self-notify. **user-b:** notified for user messages subject to mute/viewing/dedup/30s tone. **user-c while pending-invitee:** FCM group push **suppressed** (`pending_invite`); the invite shows via its card. **Removed/external:** FCM suppressed (`local_member_missing`/`group_missing`).

**Known fragilities.** **Mute is enforced only on the live path** — the FCM background/foreground fallback **never reads `isMuted`**, so a muted group can still notify via FCM (Bug). The tone debounce is in-memory/foreground-only → background bursts each sound. System events are silent by design. Live local notification body previews decrypted plaintext on lock screen (FCM is protected). *(Note: every persisted incoming message also triggers a key-epoch repair check if its epoch is ahead of local — adjacent to the notify block.)*
**Tests.** `group_notification_dedupe_integration_test.dart`, `notification_tone_tracker_test.dart`, `show_notification_use_case_test.dart`, `background_push_notification_fallback_test.dart`, `resolve_group_notification_route_target_use_case_test.dart`, `foreground_group_push_drain_test.dart`. **Coverage: partial** — GAPs: notification **stacking** + **tap-routing** to the correct group; group-scoped tone in the background isolate.

---

## 18. Reactions & read state

**Reactions.** Any active member (**including a non-admin in an announcement group** — text is blocked there but reactions are not) can react. Optimistic insert → `sendGroupReaction` (validates membership/device/target) → live publish (v3 `group_reaction` envelope) → relay-inbox replay for offline members → local upsert (`UNIQUE(message_id, sender_peer_id)` — one reaction per sender per message). Receivers verify device/transport binding + re-bind payload sender to transport sender, then upsert/remove. **Reactions fire NO notifications.** Reactions ride the **current key epoch** and go through the same grace-window machinery as messages.

**Read/delivery state.** A `group_message_receipts` table (delivered/read) exists but is a **non-user-facing sync substrate** — **there is no per-message read/delivered checkmark in the group UI.** Receipts are populated only during offline inbox drain (`delivered` locally-derived; `read` only from a trusted-sender payload). Sent messages carry `recipientReceiptClaimed: false`.

- **Chat window.** Reaction chips render under the target; tapping a chip opens a reactor list. No read indicators.
- **Settings page.** No reaction/receipt settings.
- **Encryption.** v3 encrypted+signed; full key-epoch + grace handling (a reaction after key removal fails).
- **Notifications.** None.
- **Per-role.** **Any member** reacts; **announcement non-admins** can react though they can't post. **Late joiner** gets offline reactions via inbox replay. **Removed/external:** rejected.

**Known fragilities.** Dual id scheme (deterministic add id vs random remove id). Optimistic add **rolled back on a false `publishFailed`** while receivers already got it → divergence until reload. One reaction per sender per message is structural (no multi-emoji-per-user). **Receipts never fan out / never render** — read state is sync-only. Live reactions are **blocked during account migration** (network gate).
**Tests.** `group_reaction_roundtrip_test.dart`, `send/handle/remove_group_reaction_use_case_test.dart`, `group_sync_receipts_db_helpers_test.dart`. **Coverage: reactions strong; receipts weak end-to-end** (GAP: no test that a read receipt travels to + renders on other devices; no media-message reaction convergence test).

---

# Part 2 — Cross-cutting systems

Two mechanisms drive most of the confusing behavior. Understand these and the field bugs become obvious.

## "Who actually receives a message/event?" — the delivery decision

For **any** group message or system event, ask three independent questions in order:

```
1. Is the recipient connected to the sender over a libp2p circuit-relay
   AND subscribed to the group topic, AT PUBLISH TIME?
        YES → floodPublish delivers it LIVE.
        NO  → no live copy (topic.Publish "succeeding" means nothing).

2. Is the recipient in the sender's recipientPeerIds (derived from the
   SENDER's LOCAL roster)?
        YES → relay inbox custody stores it; recipient catches up on next drain.
        NO  → recipient gets NOTHING via custody either (silent omission).

3. (events only) Direct P2P is also attempted to each member device,
   fire-and-forget.
```

Then, *separately from delivery*, the receiver must **accept** the event (next section). **Friendship is never a factor.** This is why a message can reach A but not B (mesh asymmetry, or B missing from a stale sender roster), and why a "delivered/sent" status can be vacuously true.

## The convergence accept-gate (the engine behind bug classes A & C)

A delivered system event (membership/role/metadata/dissolve) is only **applied** if it survives, in order:

1. **Serialization** — runs inside `_enqueueGroupConfigWork(groupId)` (ordered per group).
2. **Stale-event gate** — dropped if older than the local watermark (`lastMembershipEventAt` / `lastMetadataEventAt`). *Microsecond LWW, no vector reconciliation.*
3. **Authorized-sender gate** (`_isAuthorizedMembershipEventSender`) — the sender must **currently be admin in the receiver's local roster** (self-removal is the one exception for `member_removed`). A receiver whose roster lags the sender's promotion **rejects** a legitimate event here.
4. **Signed transition audit** (`verifyGroupTransitionAudit`) — Ed25519 over a canonical payload binding actor `peerId/username/signingKey/deviceId/transportPeerId/keyPackageId` + `preTransitionStateHash`. Fails as `device_mismatch` / `transport_mismatch` (signer omitted the binding, or receiver doesn't yet know the sender's device) or `previous_transition_hash_mismatch`. `group_dissolved` **relaxes** the pre-transition-hash check (terminal).
5. **Metadata only:** an actor-signature envelope verified against the sender's **existing member public key** — if the sender isn't yet a known member-with-key, the **whole metadata update is silently dropped**.

> Failure at any gate = **silent drop** (FLOW telemetry only). This is precisely why metadata/role events "don't arrive" on a device whose roster is stale or whose copy of the sender's device binding is unreconciled — even though the event was *delivered*. Convergence then depends on a later replay re-delivering it after the roster reconciles.

## Why the security/key-epoch indicator can look like an error

The Group Info **Security card** (and a compact chip near the composer) is computed from `GroupSecurityStatusViewState`:
- `!hasCurrentKey` → **red** open-lock "No group key on this device" (shown transiently while a key is settling, or persistently if a member is stuck without a key).
- `keyEpoch > 1` → **permanent amber** "Key change visible / Group key changed to epoch N" (any group that ever rotated).
- During the brief pending→encrypted settle on group entry, the compact "Encrypted — key epoch {N}" chip flashes then vanishes (S2-bug4).

There is **no calm steady state / no debounce** — a healthy rotated group reads as a standing amber warning, and a settling key reads as a red error.

---

# Part 3 — Known-bug cross-reference

The field-reported scenarios (S1–S7) all reduce to **six recurring bug classes**. Status reflects branch `121-improvements` (many fixes uncommitted; some field reports are **build skew** against an older build).

## Bug classes

| # | Class | One-line pattern |
|---|-------|------------------|
| **A** | **Metadata/photo non-convergence** | Signed `group_metadata_updated` is *delivered* but **dropped at the receiver's accept-gate** (device-binding / unknown-sender-key) → name/desc/role don't converge. **Photo lags worst** — two-stage (blobId on wire, bytes fetched separately); late joiners get a **frozen invite snapshot**. |
| **B** | **Partial message fanout** | Two delivery legs each create subset delivery: **live mesh asymmetry** + **relay custody scoped to the sender's local `recipientPeerIds`** (stale roster omits a member from both). Not friendship-related. |
| **C** | **Local-roster authority for permissions** | All mutation authz is from **local** `myRole`/permissions. A role event that never *applied* leaves stale role → demoted user still edits/adds; promoted user can't add yet; receiver transiently rejects a just-promoted admin. |
| **D** | **Global recovery gate blocks admin writes** | A process-wide `GroupRecoveryGate` held during resume rejoin+drain hard-throws a **failure-styled** "recovery in progress" with **no auto-retry**; partial avatar local-commit; over-blocks unrelated groups. |
| **E** | **Invite lifecycle** | Card removed only by a post-accept reload (lingers on non-success/race → re-pressed); re-add can be dropped at `storeIncomingPendingGroupInvite`; **late joiner materialized from a stale frozen snapshot**. |
| **F** | **Security/status UI reads like an error** | Transient "Encrypted — key epoch N" chip flash + permanent epoch>1 amber + no-key red, with no calm steady state. Cosmetic; no data loss. |

## Reported bug → class → root cause → status

| Reported | Class | Root cause (confirmed in source) | Status |
|----------|-------|----------------------------------|--------|
| **S1-bug1 / S3-bug1** name+desc not received | **A** | Receiver accept-gate (`_verifyGroupMetadataActorEvent` + device-binding + `verifyGroupTransitionAudit`) drops the signed transition when the sender's device row is unknown/unreconciled. Same binding-asymmetry family as 121-B4. | implemented-uncommitted (+ likely build-skew on field devices) |
| **S1-bug4 / S2-bug1 / S3-bug3 / S6 image** photo not seen | **A** | Two-stage avatar: wire carries only `avatarBlobId`/`avatarMime`; each receiver must separately download+decrypt the blob. Failed/late fetch (or rejected metadata event, or stale-snapshot blobId for a late joiner) → text updates, photo stays initials. | implemented-uncommitted (structural lag remains) |
| **S2-bug1 photo / S7-bug3** late joiner sees stale name/desc/photo | **A + E** | `handle_incoming_group_invite` materializes the whole group from the **frozen `payload.groupConfig`** at invite-send time; no post-accept reconciliation. (`refreshPendingGroupInvitesForMetadataChange` only helps if the invite is re-delivered before accept.) | open (doc-104 stale-snapshot) |
| **S1-bug3 / S2-bug2 / S3-bug2 / S5-bug2-partial** C reaches some not all | **B** | (1) live floodPublish only reaches peers with a circuit to the sender; (2) relay custody only covers `recipientPeerIds` from the **sender's local roster** — stale roster omits a member from both legs. | open (114/115 send-truthfulness custody hardening plan-only) |
| **S5-bug1/2/3** demote not reported; demoted still edits/adds | **C** | Authz is local (`updateGroupMetadata` checks `myRole==admin`; `addGroupMember` checks local permissions). If the `member_role_updated` demotion never *applied* on user-b (rejected at the binding gate or undelivered), user-b keeps `myRole=admin` locally. "Not reported in chat" = the same event failed to apply/render. | open |
| **S6-bug1/2/4 + add-member** "Group recovery in progress" then works | **D** | Global `GroupRecoveryGate` held during resume rejoin+drain → every admin mutation throws `groupRecoveryPendingError`. Avatar committed locally before the throw = "image changed only locally." No auto-retry; error-styled wording. | open (UX) |
| **S7-bug1** "joined…but recovery still catching up" | **D** | **Build skew.** That string was emitted in build 104; on HEAD both accept handlers show plain "Joined {name}" and the recovery l10n strings are orphaned (zero call sites). | **fixed** (ship a release) |
| **S7-bug2** invite card persists after accept | **E** | Card removed only by a post-accept reload (`_loadPendingGroupInvites`), guarded by `_processingPendingInviteIds`; on a non-success/recovery path or a reload race it lingers. Deeper: 122-plan re-add drop + false-joined roster. | planned (122) |
| **S2-bug4** "Encrypted — key epoch 1" flashes | **F** | Compact security chip shows while `!hasCurrentKey` during the pending→encrypted settle; no debounce/calm state. Benign. | open (UX) |
| **S1-bug2 / S5-bug3** promoted can't add / demoted still adds | **C** | Same local-roster-authority + role-convergence root: the role event hadn't applied locally (or the recovery gate was active for S1-bug2). | open |

> **Practical implication.** Bugs A, B, C are **the same underlying engine** (delivery + per-receiver accept-gate + local-roster authority). The highest-leverage fixes are: (1) make signed transitions converge even when the receiver's roster lags the sender's device/role (snapshot-bootstrap the sender, or carry sender key material in the event); (2) reconcile a late joiner against live state post-accept instead of trusting the frozen snapshot; (3) make recovery a per-group, auto-retrying, non-error-styled state.

---

# Part 4 — Test scenario catalog

A systematic set spanning the combinatorial space: lifecycle event × actor role × ordering/timing × party count × network condition. **91 scenarios** — 42 already covered (regression-locks worth formalizing as named cases), **49 NEW** targeting the documented gaps and the field bugs whose root causes are confirmed-in-source but not yet locked by a test.

**Legend.** P0 = data-loss / convergence-breaking field bug · P1 = ordering-dependent divergence / silent-loss edge · P2 = UX, by-design, or scale completeness. `EXISTS:file` = assertion already locked (formalize/extend). `NEW` = write it. Read each alongside the matching Part 1 / Part 2 section for mechanics.

> **⚠️ Two test layers — read [Part 5](#part-5--reliability-simulator-matrix-integration) before writing any of these.** The `EXISTS:file` references below mostly point at the **`flutter test` unit/integration suite** (`test/**`). There is a **second layer** — the **reliability-simulator matrix** (174 group check rows, real Go crypto across simulators, tracked by `group-sim-feature-test-files.md`). Several scenarios marked `NEW`/GAP here are **already covered in the simulator matrix** (e.g. demote convergence, membership-cap churn, concurrent admin edits, the S7 stale-metadata case). **Do not write a parallel test** — Part 5 maps every GS-row to its simulator host and tells you whether to extend an existing `private_*` scenario or add a new one.

## 4.1 Existing coverage by sub-feature

| Sub-feature | Coverage | Notable gap |
|-------------|----------|-------------|
| create, add-member, accept-invite, remove, re-add | **strong** | — |
| promote, edit-name/desc, change-photo, send-text, send-media, dissolve, encryption-key-epochs, recovery-resync, admin-permissions | **strong** | dissolve/override convergence are use-case/UI-level, not fully-online multi-device |
| self-leave (voluntary) | **partial** | no multi-device test that remaining peers drop a *voluntary* leaver |
| demote-admin | **partial** | no multi-device test that a demoted admin loses authority on ALL peers |
| notifications-group | **partial** | no stacking / tap-routing / background-isolate tone tests |
| reactions / **receipts** | reactions strong; **receipts weak** | no end-to-end read/delivered receipt fanout; no media-reaction convergence |

## 4.2 Known gaps (what no test currently locks)

Annotated with reliability-simulator-matrix status (see Part 5). "GENUINE gap" = absent from **both** layers; "sim-only" = covered in the simulator matrix but not the `flutter test` suite.

1. Read/delivered **receipt fanout** end-to-end (`recipientReceiptClaimed:false`; receipts are sync-only). — **GENUINE gap** (neither layer).
2. **Voluntary-leave** convergence across peers' rosters. — **GENUINE gap**; closest sim scenarios are `private_late_leave_readd` / `private_peer_disconnect_not_removal` (neither asserts "remaining peers drop a clean voluntary leaver"). Add `private_voluntary_leave_convergence`.
3. **Demote-admin** multi-device authority revocation. — **COVERED in sim** as `private_admin_demotion_enforcement` (+ `regression_group_admin_permissions_and_message_reliability_four_users`); the gap is only at the `flutter test` layer.
4. **Permission-override** convergence (override-empowered writer's mutation propagating). — **GENUINE gap**. Add `private_override_removal_nonconvergence`.
5. **Live online dissolve** convergence (all connected peers → read-only in real time). — **GENUINE gap** in the multi-party harness (only `group_recovery_e2e_test` covers *offline-recovered* dissolved cleanup). Add `private_online_dissolve_convergence`.
6. Notification **grouping/stacking + tap-routing**; group-scoped background tone debounce. — **GENUINE gap**; add rows to the notification sims (`notification_open_ui_smoke_test`, `run_notification_sound_smoke`, `run_ios_notification_tap_ui_smoke`).
7. **Reactions on media** messages converging across devices. — **GENUINE gap**; `private_reaction_roundtrip` is text-only. Extend it / add a media variant.
8. **Concurrent metadata edit** conflict resolution (two admins rename at once). — **PARTIALLY covered in sim** as `private_concurrent_admin_membership_edits` (membership); the same-microsecond *name-rename* LWW collision is not asserted — extend.
9. **Membership-cap (50)** runtime fanout + (cap+1) rejection through the real add path. — **COVERED in sim** as `private_max_group_size_churn`; the gap is only at the `flutter test` layer.
10. Read-receipt privacy/setting (may not exist; unspecified). — **GENUINE gap** (product decision first).

## 4.3 Scenarios by bug class / category

### A — Metadata & photo propagation

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-A01 | P0 | NEW | Admin name+desc edit to an online member whose roster hasn't reconciled the **sender's device row** → does the accept-gate drop it (`device/transport_mismatch`)? Re-deliver after reconcile must converge. (S1/S3 root) |
| GS-A02 | P0 | EXISTS:`group_admin_metadata_convergence_test` | Photo change converges last/never while name+desc converge — inject blob-download failure; verify initials fallback + avatar-recovery retry on replay. |
| GS-A03 | P0 | NEW | Late joiner accepts **after** a metadata change → materialized from a **stale frozen invite snapshot**; sees old name/desc/photo under "All". (S2/S7) |
| GS-A04 | P1 | EXISTS:`group_admin_metadata_convergence_test` | `refreshPendingGroupInvitesForMetadataChange` re-snapshots a still-pending invite → later acceptor gets **current** metadata (contrast GS-A03). |
| GS-A05 | P1 | NEW | Metadata edit from a **just-promoted admin** whose membership/key hasn't converged on receivers → `_verifyGroupMetadataActorEvent` drops it (unknown publicKey); must self-heal after role converges. |
| GS-A06 | P1 | NEW | Two admins rename at the **same microsecond** → LWW collision; assert deterministic convergence, no permanent divergence. |
| GS-A07 | P2 | EXISTS:`update_group_metadata_use_case_test` | Description **cleared** converges and is not resurrected by a stale replay; late joiner sees empty. |
| GS-A08 | P2 | NEW | Avatar ACL excludes a **concurrently-joining** member → late joiner can't decrypt the new photo blob (no per-photo re-key). |
| GS-S01 | P2 | NEW | Edit metadata **immediately after** promoting a member → serialized `_enqueueGroupConfigWork`; both apply in order, no lost update. |
| GS-S02 | P2 | NEW | Snapshot apply **fails closed** if any member entry lacks valid key material → name/desc/photo + roster all rejected. |

### B — Message fanout, delivery truthfulness, double-card

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-B01 | P0 | EXISTS:`group_messaging_smoke_test` | C→subset via **mesh asymmetry** (C↔A circuit, not C↔B): A live, B via relay drain; sender status truthful. (S1-bug3/S3-bug2) |
| GS-B02 | P0 | NEW | C→subset via **stale sender roster**: B's device row missing from C → omitted from *both* live and relay custody; B gets nothing, C may falsely show "sent". (S2-bug2) |
| GS-B03 | P0 | EXISTS:`send_group_message_use_case_test` | `expectedRecipientCount:0` **vacuous "sent"** — offline send shown delivered but lost. |
| GS-B04 | P1 | NEW | Pre- vs post-publish topic-peer skew (GAP-2): peer subscribing during the settle window is delivered to but uncounted; legacy binary reads a real delivery as "pending". |
| GS-B05 | P1 | EXISTS:`group_resume_recovery_test` | Relay-only (no mesh): all offline at send, catch up purely via inbox drain; exactly-once; media never relay-deleted. |
| GS-B06 | P2 | EXISTS:`send_group_message_recipient_eligibility_test` | Membership cutoff excludes a member whose `joinedAt` is after a back-dated/retry send. |
| GS-B07 | P2 | NEW | Legacy plain-publish fallback marks "sent" with zero delivery (build-skew optimism). |
| GS-B08 | P1 | EXISTS:`group_resume_recovery_test` | Retrier **confirm-before-republish** (GAP-3a): "pending" with resolved custody promoted to "sent" without re-send; mutate the order → duplicate. |
| GS-M01 | P1 | NEW | **Double/stacked card**: send timeout re-mints messageId → divergent-id duplicate survives id-only dedup → two cards. |
| GS-R01 | P2 | EXISTS:`group_edge_cases_smoke_test` | 4-party high-fanout text+media reaches all exactly once; `topicPeers`/`expectedRecipientCount` honest. |
| GS-T01 | P2 | EXISTS:`group_multi_device_convergence_test` | Sibling-device: own publish stored as sent on both; no id-collision; mute/unread stay device-local. |

### C — Permission leak / role convergence

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-C01 | P0 | NEW | Demoted admin **still edits name/desc** because the demotion never applied locally → edit accepted by some peers, rejected by others → divergence. (S5-bug2) |
| GS-C02 | P0 | NEW | Demoted admin **still adds a member** using stale local admin role → receivers should reject `members_added` from a non-admin → roster divergence. (S5-bug3) |
| GS-C03 | P0 | NEW | Promoted admin **can't add** because promotion not yet applied locally → "Only admins…" (distinguish from the recovery-gate error). (S1-bug2) |
| GS-C04 | P1 | EXISTS:`group_membership_smoke_test` | Receiver **transiently rejects** a legit transition from a just-promoted admin (stale receiver roster) → must self-heal via stale-gate/replay. |
| GS-C05 | P1 | EXISTS:`group_info_wired_test` (extend to multi-device) | Demotion applies on **all** peers in real time + revokes admin UI/authority. **(GAP: full multi-device.)** |
| GS-C06 | P2 | EXISTS:`announcement_happy_path_test` | Demoted admin in an **announcement** group → message read-only but can still **react** (carve-out). |
| GS-C07 | P1 | NEW | Non-admin writer with `removeMembers` **override** removes → applies locally but **every receiver rejects** (admin-only receive gate) → divergence. |
| GS-C08 | P2 | NEW | `reader` role is **not** enforced read-only in a chat/qa group → reader can send (documents the gap). |

### D — Recovery / resync gate

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-D01 | P0 | EXISTS:`group_info_wired_test` | Resume-gate blocks a metadata edit with a failure-styled error + "Waiting Ns" banner; succeeds on retry. (S6-bug2/4) |
| GS-D02 | P0 | NEW | Add-member blocked by the gate shows the **generic "Failed to invite members"** (no friendly recovery copy). (S6) |
| GS-D03 | P0 | NEW | Avatar **partial local-commit** before the gate throws → "image changed only locally", nothing on others. (S6-bug2) |
| GS-D04 | P1 | NEW | Promote blocked by the gate first try, works on retry; check the raw error wording. (S6-bug1) |
| GS-D05 | P1 | NEW | Gate is **process-global**: a rejoin for group X blocks an admin edit on **unrelated group Y**. |
| GS-D06 | P1 | EXISTS:`group_startup_rejoin_smoke_test` | A **keyless group** blocks the Go recovery ack → repeated transient admin-write blocks each resume. |
| GS-D07 | P1 | NEW | Gate has **no timeout**: a stalled inbox drain blocks all admin writes indefinitely (unbounded "Waiting Ns"). |
| GS-D08 | P2 | NEW | Regular chat send is **not** gated while announcement send **is** — documents the boundary. |
| GS-Q01 | P2 | EXISTS:`rejoin_group_topics_use_case_test` | Recovery does **no** roster/metadata reconciliation and no rekey — pure transport re-subscribe + drain. |
| GS-Q02 | P2 | NEW | Re-subscribing does **not** establish mesh connectivity → resumed member gets messages via inbox replay, not live, until a circuit forms. |

### E — Invite lifecycle

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-E01 | P0 | EXISTS:`group_invite_accept_spinner_simulator_test` | Pending-invite card **persists after accept** (reload race / non-success path), re-pressable → assert idempotency (one join, one card). (S7-bug2) |
| GS-E02 | P0 | EXISTS:`invite_round_trip_test` | **Re-add dropped** at `storeIncomingPendingGroupInvite` / false-joined roster → verify retained-removed shell detection + clean re-materialize. (122-B3, S7-bug2 deeper) |
| GS-E03 | P1 | NEW | Re-add with **null/empty ownPeerId** mis-classified as `duplicateGroup` → re-add silently fails. |
| GS-E04 | P1 | NEW | Accept returns `bridgeError` **with a non-null group** → "Failed to accept" shown despite a usable group **and the card already deleted**. |
| GS-E05 | P2 | EXISTS:`handle_incoming_group_invite_use_case_test` | Re-accept of a duplicate-but-**compatible** group → retry-into-**success**, not a flat failure (incompatible key → duplicate). |
| GS-E06 | P1 | NEW | Accept under recovery shows plain "Joined {name}" — **regression-lock** against re-introducing the orphaned "recovery still catching up" string. (S7-bug1) |
| GS-E07 | P1 | NEW | `member_joined` broadcast fails on **both** GossipSub (0 peers) and relay-replay → existing members never learn of the join. |
| GS-E08 | P2 | EXISTS:`revoke_pending_group_invite_use_case_test` | Revoked invite stays rejected even if a delayed duplicate arrives after revocation. |

### F — Security / key-epoch banner

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-F01 | P1 | NEW | "Encrypted — key epoch 1" chip **flashes** near the composer during the pending→encrypted settle (reads as error); no debounce. (S2-bug4) |
| GS-F02 | P2 | NEW | Post-rotation amber "Key change visible / epoch N" is a **standing** warning for any rotated group; no-key device shows **red**. |

### Encryption & key epochs

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-J01 | P1 | NEW | Out-of-grace straggler (old epoch, >30s after rotation) **silently dropped** at the validator (no placeholder); in-grace decrypts via PrevKey. |
| GS-J02 | P1 | EXISTS:`group_key_update_listener_test` | `key_rotated` topic broadcast triggers **no** self-heal; member that missed the direct `group_key_update` stays on placeholders until it arrives. |
| GS-J03 | P1 | NEW | **Stale local epoch send** (post-rotation, pre-resync) → recipients on the new epoch can't decrypt; repair queued. |
| GS-J04 | P2 | EXISTS:`group_resume_recovery_test` | Subscribed member with **no key at all** → `decryption_failed` + placeholder (third failure branch); repairs on key delivery. |
| GS-J05 | P2 | EXISTS:`rotate_and_distribute_group_key_use_case_test` | Anti-rollback: `UpdateGroupKey` no-ops for epoch ≤ current; back-to-back rotation refused inside the 30s grace; epoch monotonic. |

### Membership — remove / leave / promote-demote edges

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-G01 | P1 | EXISTS:`member_removal_integration_test` | Removed member's brief **publish window** before config propagates + before rotation closes it; then cut off at the epoch check. |
| GS-G02 | P1 | EXISTS:`group_membership_smoke_test` | Removal **blocked** because a remaining member is undeliverable → re-mint returns null → whole kick rolled back. |
| GS-G03 | P1 | NEW | Partial-failure removal: peers process `member_removed` **before** rotation fails on the admin → roster divergence until next event. |
| GS-G04 | P2 | NEW | `member_removed` that empties the group **closes/dissolves** it on receivers (`snapshotHasNoActiveMembers`). |
| GS-G05 | P2 | NEW | Removal-cutoff timeline message saved 3× with the same deterministic id must collapse to **one** card; mutate eventAt → stacked dups. |
| GS-H01 | P1 | NEW | **Voluntary leave** converges on remaining peers' rosters in real time; leaver hard-deletes locally; silent. **(GAP.)** |
| GS-H02 | P1 | EXISTS:`leave_group_use_case_test` | Leave **hard-blocked** when a remaining member is undeliverable → user trapped. |
| GS-H03 | P1 | EXISTS:`leave_group_use_case_test` | Leave partial-failure: sys-message+rotation published then native `group:leave` fails → peers rotated past the still-present leaver. |
| GS-H04 | P2 | NEW | A voluntary leave **carries a metadata snapshot** that can reconcile name/desc/photo on remaining members. |
| GS-P01 | P2 | EXISTS:`group_membership_smoke_test` | Promotion applies on the promoted member's **own** device + unlocks admin UI; no rekey, no notification. |
| GS-P02 | P2 | NEW | A role/metadata snapshot can **change the receiver's own `myRole`** (gain/lose admin UI). |
| GS-P03 | P2 | NEW | Receiver timeline text uses **local `previousRole`** → different members see different text for the same role event. |
| GS-P04 | P2 | NEW | Malformed role event with missing `newRole` defaults to **writer** → silently demotes an intended promotion. |

### Dissolve

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-I01 | P1 | EXISTS:`dissolve_group_use_case_test` (extend to online multi-device) | Live online dissolve flips **every** connected peer to read-only in real time (B4 binding correct). **(GAP: full-online.)** |
| GS-I02 | P1 | EXISTS:`dissolve_group_use_case_test` | Dissolve call site reverts to **null device binding** → every receiver rejects (`device/transport_mismatch`), group stays live (B4 regression-lock). |
| GS-I03 | P1 | NEW | Dissolve with an **offline** recipient whose inbox-store fails → recovery snackbar to admin, but member stays in a live group. |
| GS-I04 | P2 | EXISTS:`group_delete_preserves_friends_and_dms_test` | Delete-locally removes only group tables; **friends + DMs + other groups preserved** (no FK guard → regression-prone). |

### Media

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-M02 | P2 | EXISTS:`group_media_fanout_test` | One bad attachment descriptor **drops the whole incoming message** (text + all attachments). |
| GS-M03 | P2 | EXISTS:`group_new_member_onboarding_test` | Late joiner cannot fetch **pre-join media** (point-in-time ACL, no backfill); post-join media fine. |
| GS-M04 | P2 | EXISTS:`group_media_fanout_test` | Media blob **TTL expiry**: long-offline member's later download fails → quarantines; in-TTL fetch succeeds. |

### Notifications

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-K01 | P1 | NEW | **Muted group still raises an FCM background notification** (mute enforced only on the live path). |
| GS-K02 | P1 | EXISTS:`group_message_listener_test` | First message sounds; subsequent within 30s update the same notification silently; **background bursts NOT tone-debounced** (cross-isolate gap). |
| GS-K03 | P2 | EXISTS:`group_notification_dedupe_integration_test` | System events (add/remove/role/metadata/dissolve) raise **no** notification on any path. |
| GS-K04 | P2 | NEW | Tapping a group notification routes to the **correct** group conversation; stacked notifications don't misroute. **(GAP.)** |
| GS-K05 | P2 | EXISTS:`foreground_group_push_drain_test` | FCM group push **suppressed** for pending-invitee / non-member / unknown group; protected/generic body. |

### Reactions & receipts

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-L01 | P2 | NEW | Reaction on a **media** message converges + renders for all members. **(GAP.)** |
| GS-L02 | P2 | NEW | Optimistic reaction **rolled back on a false `publishFailed`** while receivers already got it → divergence until reload. |
| GS-L03 | P2 | NEW | Live reactions **blocked during account migration** (network gate); resume after. |
| GS-L04 | P2 | EXISTS:`group_sync_receipts_db_helpers_test` | Read/delivered **receipts do not fan out / render** — assert there's no per-message read indicator (sync-only substrate). **(GAP.)** |

### Creation & add-member edges

| ID | P | Status | Scenario → what it catches |
|----|----|--------|----------------------------|
| GS-N01 | P2 | EXISTS:`create_group_with_members_use_case_test` | Auto-name + zero-member UI guard + epoch-1 invariant; no description/photo on create. |
| GS-N02 | P2 | EXISTS:`create_group_with_members_use_case_test` | Config-sync rollback after create succeeds leaves a **created-but-empty** group. |
| GS-O01 | P1 | EXISTS:`add_group_member_use_case_test` | Invitee committed to roster **before** delivery; all invites fail → roster shows a member who never got the key. |
| GS-O02 | P2 | NEW | `members_added` card **not written** on the admin when the publish/relay/direct block throws (silent UX gap). |
| GS-O03 | P2 | NEW | Multi-device invitee: per-peer tracker **collapses** partial-device delivery (one delivered + one failed → last-writer). |
| GS-O04 | P2 | NEW | Add config-sync rollback **restores the avatar AND deletes invite-attempt rows** (broader than member removal). |
| GS-O05 | P2 | EXISTS:`send_group_invite_use_case_test` | Invite **TOCTOU**: key rotation between picker-read and send → `invalidPayload` (stale-key guard); `keyEpoch<=0` guard. |
| GS-R02 | P2 | NEW | **Membership cap (50)**: 50th add succeeds + delivers; 51st rejected through the real add path. **(GAP.)** |

---

# Part 5 — Reliability-simulator matrix integration

> **Why this part exists.** `Test-Flight-Improv/group-sim-feature-test-files.md` tracks a **second test layer** that Part 4 only partially acknowledged. Future group tests must **extend this matrix**, not fork a parallel suite. This part defines the two layers, the exact mechanism for adding a check row, and a GS-row → simulator-host mapping so every new scenario lands in the right place.

## 5.1 The two test layers

| | **A. `flutter test` unit/integration** | **B. Reliability-simulator matrix** |
|---|---|---|
| Lives in | `test/**` (+ a few headless `integration_test/*_test.dart`) | `integration_test/**` + `scripts/*` discovered by `check_reliability_simulation_discovery.sh` |
| Runs on | Dart VM, fakes / `FakeGroupPubSubNetwork`, fake bridge | iOS simulators / Android emulators with **real Go crypto + real relay** |
| Discovery | `flutter test` paths | `run-flutter-reliability-sims group --list` → **174 group check rows** across 24 entries (12 sim files + 12 runners) |
| What most Part 4 `EXISTS:` points at | ✅ this layer | the `_simulator_test` / runner rows |
| Best for | use-case logic, widget gates, fail-closed branches, error mapping | **multi-device convergence, fanout reach, key rotation across peers, recovery, "works on a real device"** |

**Rule of thumb.** A scenario whose failure mode is *logic* (e.g. "vacuous 'sent' when `expectedRecipientCount==0`", "demoted role gate", "recovery-gate error mapping", "banner flash") belongs in **layer A**. A scenario whose failure mode is *convergence/delivery across devices* (e.g. "C reaches A but not B", "demote applies on all peers", "stale invite → stale metadata", "cap churn") belongs in **layer B** — and several already exist there.

## 5.2 Anatomy of a check row — and how to add one

The discovery script (`scripts/check_reliability_simulation_discovery.sh`) classifies each candidate file (`classify_path`) then **expands** it into check rows (`expand_record_to_checks`). A **group check row** is one of:

1. A **`test()` / `testWidgets()` declaration** inside a **classified** group sim file (e.g. `group_recovery_e2e_test.dart` → 8 rows, `foreground_group_push_drain_test.dart` → 6 rows). *Parsed by name.*
2. A **target `_test.dart`** referenced by a classified **runner** (the runner's tests are expanded).
3. A **scenario id** in a special harness:
   - `run_group_multi_party_device_real.dart` → `dart … --scenario all --list-scenarios` → **103 ids** (`private_*` + coded `gm*/ge*/de*/ir*/pl*`). **This is the largest slice and the primary home for multi-device convergence/fanout/recovery scenarios.**
   - `run_routing_smoke_e2e.dart` → `G1..G8` from `routing_smoke_group_criteria.dart` (2-party send/receive/rotation reliability).
   - `smoke_test_push_decrypt_simulator.sh` → `S-*` group push-decrypt rows; `run_notification_sound_smoke.dart`, `run_notification_open_ui_smoke.dart`, `run_ios_notification_tap_ui_smoke.sh` → notification rows; `run_media_*_smoke.dart` → media rows.

**To add a new reliability check (no script change needed):**
- **Multi-device convergence / fanout / recovery** → add a `private_<name>` scenario to `group_multi_party_device_real_harness.dart` and register it (the criteria + `--list-scenarios` output) so `run_group_multi_party_device_real.dart --list-scenarios` prints it. It auto-joins the matrix.
- **2-party send/rotation reliability** → add a `G9` criterion to `routing_smoke_group_criteria.dart` + the routing harness.
- **A new assertion on an existing flow** → add a `test()`/`testWidgets()` to the already-classified sim file (e.g. another case in `group_recovery_e2e_test.dart` or `foreground_group_push_drain_test.dart`).
- **Notifications/media** → add to the relevant notification/media sim file.

**To add a brand-new sim FILE (script change required):** add a `classify_path` rule for it in `check_reliability_simulation_discovery.sh` **or discovery FAILS** with `FAIL: N candidate(s) are unclassified`. Then re-run the refresh commands and update `group-sim-feature-test-files.md`.

**Always after touching the matrix:**
```bash
./scripts/check_reliability_simulation_discovery.sh --checks-tsv | awk -F '\t' '$1=="group"{print}' | wc -l   # expect 174 + N
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
```
and update the row count + file list in `group-sim-feature-test-files.md`.

> ### ⚠️ When you implement these gaps: classification > naming
>
> A clear name helps humans, but **naming is cosmetic — classification is what actually makes a test run in the group reliability gate.** A future group simulator test is caught **only if BOTH** are true:
>
> **1. It lives in a *discovered* location** (`discover_candidates`, `check_reliability_simulation_discovery.sh`):
> - direct simulator test → `integration_test/*_test.dart`
> - Dart runner/orchestrator → `integration_test/scripts/…`
> - shell runner → `scripts/*simulator*.sh`, `*e2e*.sh`, `*smoke*.sh`, `*emulator*.sh`
>
> **2. It is *explicitly classified* as `group`** in `classify_path()` → `scripts/check_reliability_simulation_discovery.sh:71`. A discovered-but-unclassified file fails CI (`FAIL: N candidate(s) are unclassified`); a file classified under another category (or as `support`/`ignored`) simply **won't appear in the group matrix** even if its name screams "group".
>
> **Conventions to follow (name clearly, then classify):**
> - New **direct simulator test** → name it `integration_test/group_<feature>_simulator_test.dart`, then add it to the **group `test` case** in `classify_path` (the `record "group" "$path" "test" "group simulator/E2E test"` block, ~line 268).
> - New **runner/orchestrator** → name it `integration_test/scripts/run_group_<feature>_simulator_smoke.dart` or `…/run_group_<feature>_e2e.dart`, then add it to the **group `runner` case** (the `record "group" … "runner"` block, ~line 208).
>
> **Host tests are a different gate — don't confuse the two.** Tests under `test/features/groups/…` are **host tests** (layer A), caught by **`$run-flutter-host-gates`**, *not* by **`$run-flutter-reliability-sims`**. `discover_candidates` never scans `test/**`, so a host test will **never** join the group sim matrix no matter how it's named. Put cross-device convergence in a simulator test (layer B); put logic in a host test (layer A).
>
> **Verify before trusting it:**
> ```bash
> # 1. Is it discovered AND classified as group?
> ./scripts/check_reliability_simulation_discovery.sh --records-tsv | awk -F '\t' '$1 == "group" {print}'
> # 2. Does it appear in the runnable group gate?
> "${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" group --list
> ```
> **If it does not appear in `group --list`, it will not run in the group reliability-sim gate** — regardless of its name or that it passes locally.

## 5.3 GS-scenario → simulator-matrix host

**`run_group_multi_party_device_real.dart` (`private_*` — multi-device convergence/fanout/recovery):**

| GS | Matrix scenario (existing) | Status |
|----|----------------------------|--------|
| GS-A02 photo converge | `private_admin_metadata_intro_photo_convergence` | covered (also sim test `group_admin_metadata_convergence_simulator_test`) |
| GS-A03 / GS-E02 stale invite snapshot (S7) | `scenario7_group_invite_stale_metadata_recovery`, `private_stale_invite_readd` | covered |
| GS-A05 just-promoted-admin metadata | `private_admin_role_transfer_delivery` + metadata convergence | extend (assert publicKey-not-yet-converged drop→heal) |
| GS-A06 / GS-S01 concurrent admin edits | `private_concurrent_admin_membership_edits` | partial — extend for same-µs name LWW |
| GS-B01 mesh subset (C→A not B) | `private_full_mesh_online`, `private_partition_readd_heal` | extend (explicit asymmetric-mesh + relay catch-up) |
| GS-B02 stale-roster omission | — | **NEW** `private_stale_roster_recipient_omission` |
| GS-B05 relay-only delivery | `private_relay_only_delivery` | covered |
| GS-B (friendship irrelevant) | `private_non_friend_member_delivery` | covered |
| GS-C01/C02 demoted still edits/adds | `private_admin_demotion_enforcement` | covered — verify it asserts the *leak direction*, else extend |
| GS-C05 demote converge on all peers | `private_admin_demotion_enforcement` | covered (sim layer) |
| GS-C07 override removal non-converge | — | **NEW** `private_override_removal_nonconvergence` |
| GS-E02/E03 re-add cluster | `private_offline_readd`, `private_readd_current`, `private_readd_active_members`, `private_rapid_readd`, `private_readd_cycles`, `private_late_leave_readd`, `private_rotated_device_readd`, `private_same_user_multi_device_readd` | covered (rich) |
| GS-G02 undeliverable blocks kick | `private_partial_key_distribution` | related — extend for kick rollback |
| GS-J01/J03 epoch churn / stale-epoch send | `private_long_offline_epoch_churn` | covered |
| GS-J05 anti-rollback / same-epoch conflict | `private_stale_lower_key_update`, `private_same_epoch_key_conflict` | covered |
| GS-R02 membership cap churn | `private_max_group_size_churn` | covered (sim layer) |
| GS-L01 media reactions | `private_reaction_roundtrip` (text only) | extend / **NEW** `private_media_reaction_roundtrip` |
| GS-H01 voluntary-leave converge | — | **NEW** `private_voluntary_leave_convergence` |
| GS-I01 live online dissolve converge | — | **NEW** `private_online_dissolve_convergence` |
| S5/S6 4-user admin+reliability | `regression_group_admin_permissions_and_message_reliability_four_users` | covered |
| recovery delivery (resume/process-death) | `private_relay_reconnect_group_recovery`, `private_background_resume_group_delivery`, `private_process_death_matrix` | covered |
| GS-B (truthfulness / history) | `private_timeline_truth`, `private_history_retention` | covered |
| removed-member notification privacy | `private_removed_notification_privacy` | covered |

> Coded ids `gm*` (messaging/membership), `ge*` (edge cases), `ir*` (invite round-trip), `pl*` (media fanout — PL-005/006/007/011/013), `de*` are the **device-real counterparts of the `flutter test` integration families** of the same name; list exact assertions via `--checks-tsv`.

**Other group sim hosts:**

| Host file (rows) | Covers GS | Add new rows here for |
|---|---|---|
| `run_routing_smoke_e2e.dart` G1–G8 (8) | GS-B basic fanout (G2=5/5), recovered receipt (G4), 9-msg bidi reliability (G5), rotation pre/post receipts (G7) | 2-party send/rotation reliability (add `G9…`) |
| `group_recovery_e2e_test.dart` (8) | GS-B08 status truthfulness, missed-drain, dissolved local cleanup, watchdog rejoin | resume/recovery + dissolved-cleanup assertions |
| `foreground_group_push_drain_test.dart` (6) | GS-K push drain/dedup, GS-M02 tampered/oversized | **GS-K01 muted-FCM-leak**, more push edge cases |
| `notification_open_ui_smoke_test` / `run_notification_open_ui_smoke` (8) | notification-open routing | **GS-K04 tap-routing** to correct group |
| `run_notification_sound_smoke.dart` (2) | tone behavior | GS-K02 group tone/30s window |
| `smoke_test_push_decrypt_simulator.sh` (12) | GS-K05 eligibility, push-decrypt | FCM eligibility/suppression rows |
| `run_media_stable_id_smoke` / `media_stable_id_smoke_test` (6) | GS-M01 double-card / stable-id | id-dedup / re-mint rows |
| `run_media_delivery_ui_smoke` (3), `group_new_member_media_simulator_proof_test` (1) | GS-M03 late-joiner media | media render/play/backfill |
| `group_admin_metadata_convergence_simulator_test` (2) | GS-A01/A02/A04 | metadata/avatar convergence |
| `group_invite_accept_spinner_simulator_test` (1) | GS-E01 spinner/idempotency | accept-card lifecycle |
| `group_delete_preserves_friends_simulator_test` (1) | GS-I04 | delete-locally preservation |
| `group_real_crypto_onboarding_test` (1) | GS-E02 real-crypto re-add (old key can't decrypt) | crypto-onboarding boundaries |
| `multi_relay_failover_test` (4) | GS-B5 / recovery infra | relay failover |

**Layer-A-only (NOT reliability-sim — keep in `test/features/groups/**`):** GS-D01–D08 (recovery-gate UX/error mapping), GS-F01/F02 (security-chip flash), GS-B03 (vacuous-sent logic), GS-C03 (promoted-can't-add logic), GS-E04 (bridgeError-with-group accept), GS-G05 (deterministic-id dedup), GS-N02/O02/O03/O04/O05 (create/add rollback + tracker), GS-P02/P03/P04 (role-snapshot edges). These are use-case/widget logic; lock them cheaply in layer A, and *only* add a layer-B `private_*` mirror if the convergence behavior also needs device proof.

## 5.4 Corrections to Part 4's gap claims

The following Part 4 entries said "GAP: no … test" relative to the **`flutter test`** layer. They are **already covered in the reliability-sim matrix** — extend the named scenario instead of writing anything new:

- **GS-C05 / demote multi-device convergence** → `private_admin_demotion_enforcement`.
- **GS-R02 / membership-cap churn** → `private_max_group_size_churn`.
- **GS-A06 + GS-S01 / concurrent admin edits** → `private_concurrent_admin_membership_edits` (extend for the same-µs rename collision).
- **GS-A03 / GS-E02 / S7 stale metadata** → `scenario7_group_invite_stale_metadata_recovery` + `private_stale_invite_readd`.
- **GS-A02 / photo convergence** → `private_admin_metadata_intro_photo_convergence` + `group_admin_metadata_convergence_simulator_test`.

## 5.5 The genuinely-new reliability rows to add (the real backlog)

Absent from **both** layers — these are the true additions, each with its host:

1. `private_stale_roster_recipient_omission` (GS-B02) — sender's stale roster omits a member from live + custody.
2. `private_voluntary_leave_convergence` (GS-H01) — remaining peers drop a clean voluntary leaver.
3. `private_online_dissolve_convergence` (GS-I01) — live dissolve flips all connected peers read-only.
4. `private_override_removal_nonconvergence` (GS-C07) — override-empowered writer's removal rejected by receivers.
5. `private_media_reaction_roundtrip` (GS-L01) — reaction on image/video/voice converges.
6. Muted-group FCM-leak row in `foreground_group_push_drain_test.dart` (GS-K01).
7. Group-notification tap-routing row in `notification_open_ui_smoke_test.dart` (GS-K04).
8. Read/delivered **receipt fanout** (GS-L04) — needs the product decision first (receipts are currently a sync-only substrate).

## 5.6 Rule for future implementation

1. **Check the matrix first.** Before writing any group test, run `run-flutter-reliability-sims group --list` (or the `--checks-tsv` refresh) and search for an existing `private_*`/`G*`/`gm*` row. Most convergence/fanout/recovery behavior already has a home.
2. **Extend, don't fork.** Add an assertion to the existing scenario, or a sibling `private_*` next to it — so it inherits the harness, fixtures, and reporting.
3. **Pick the layer by failure mode** (§5.1 rule of thumb): logic → `test/**`; cross-device convergence → the `private_*` matrix.
4. **A new sim file means a `classify_path` rule** + a discovery refresh + a `group-sim-feature-test-files.md` update, or CI discovery fails.
5. **Keep the three docs in sync:** this behavior spec (Part 1/3), the GS catalog (Part 4), and `group-sim-feature-test-files.md` (the matrix inventory).

---

## Maintenance

- When you fix a bug or change a behavior, update the matching **Part 1** section, the **Part 3** status, and flip the relevant **Part 4** row from NEW → `EXISTS:<file>` once a test locks it — at the **correct layer** ([Part 5](#part-5--reliability-simulator-matrix-integration)).
- After touching the simulator matrix, re-run the refresh commands and update the row count + file list in `group-sim-feature-test-files.md` (it currently reads 24 entries / **174** group rows).
- The structured source data for Parts 1–4 was generated by the `group-messaging-behavior-spec` workflow; re-run it to refresh after major changes.
- **Highest-value next tests (P0/P1, mirroring field bugs), routed to their layer:**
  - *Layer B (reliability-sim):* GS-A01 (`group_admin_metadata_convergence_simulator_test`), GS-A03/E02 (`scenario7_…` — verify), GS-B02 (**new** `private_stale_roster_recipient_omission`), GS-C01/C02 (`private_admin_demotion_enforcement` — verify leak direction), GS-H01 (**new** `private_voluntary_leave_convergence`), GS-I01 (**new** `private_online_dissolve_convergence`), GS-K01 (muted-FCM row).
  - *Layer A (`flutter test`):* GS-B03 (vacuous-sent), GS-C03 (promoted-can't-add), GS-D02/D03 (recovery-gate UX), GS-E04 (bridgeError accept), GS-F01 (banner flash).
