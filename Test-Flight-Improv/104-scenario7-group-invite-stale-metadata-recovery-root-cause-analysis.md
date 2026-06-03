# Scenario 7 — Group Invite: Stale Metadata, Lingering Invite & "Recovery Catching Up" (Root-Cause Analysis)

- Type: bug root-cause analysis (no fix applied)
- Companion spec: `Test-Flight-Improv/103-group-invite-acceptance-stale-metadata-recovery.md`
- Companion regression harness: `Test-Flight-Improv/95-group-admin-permissions-message-reliability-four-users-plan.md` (already fails on four-user convergence in the simulator)
- Method: six parallel code-traces, each adversarially verified, plus an independent manual trace; findings reconciled. Confidence levels are stated per claim.
- Date: 2026-06-02

---

## Executive Summary

All three symptoms D experiences are **two defects wearing three faces.**

**Defect 1 — send-time frozen snapshot.** The invite D receives carries a point-in-time metadata snapshot of the group, captured at the instant C *sent* the invite (`send_group_invite_use_case.dart:158,250`). Because C updated the group to `test 3` **after** sending D's invite, that snapshot is `test 2` / `222` / old image. D's local group is materialized verbatim from that frozen snapshot (`handle_incoming_group_invite_use_case.dart:841-872`), and there is **no on-join resync** that re-requests the latest metadata.

**Defect 2 — partial commit coupled to a best-effort catch-up.** `acceptPendingGroupInvite` persists the group and announces the join **before** running the at-accept offline-inbox drain, then on any drain/join failure returns `bridgeError` **without** deleting the pending invite (`accept_pending_group_invite_use_case.dart:321-323` returns before the only `deletePendingInvite` caller at `:550`). That single failure produces the "recovery still catching up" copy fed the stale name (**BUG-1**), leaves the invite actionable so D keeps re-tapping (**BUG-2**), and — because the drain is the *only* accept-time channel that would have delivered C's `test 3` update — locks in the stale snapshot for that attempt (**BUG-3**).

Two clarifications the adversarial pass established and that are easy to get wrong:
- The metadata **watermark gate is not the blocker.** A strictly-newer `test 3` event *would* be applied if it were delivered (`group_message_listener.dart:4386`). The failure is **delivery-side**, not suppression.
- **BUG-3 is eventually-consistent, not strictly permanent.** A failed drain leaves C's `test 3` copy un-consumed (the inbox cursor does not advance — `drain_group_offline_inbox_use_case.dart:777-781`), and re-drains fire automatically on resume/startup/periodic/notification/repeat-Accept. So D typically converges on a later successful drain **without** C re-broadcasting — *provided the relay still holds the `test 3` copy.* The durable failure window is the accept attempt itself; whether the observed staleness lasts depends on **relay-side (Go) retention**, which is the chief remaining unknown.

Fixing Defect 2 makes BUG-1/BUG-2 truthful and self-healing; adding an on-join authoritative-config resync (Defect 1) makes BUG-3 converge deterministically rather than relying on relay retention.

---

## The Failing Sequence (Scenario 7, in code)

Ordering that matters: C (admin) **adds D**, then **updates metadata to `test 3`**, then **D taps Accept**.

1. **C adds D (before the `test 3` edit).** The add-then-invite ordering is real: `contact_picker_wired.dart:279-347` calls `addGroupMember(... syncBridgeConfig:false)`, then `buildGroupConfigPayload`, then `sendGroupInvitesInParallel`. D becomes a *member* of C's roster before the invite is sent (`add_group_member_use_case.dart:311`) — which is why C's later update targets D in its recipient list — but D has no local group/topic yet.

2. **C builds D's invite — snapshot frozen as `test 2`.** `sendGroupInvite` does **not** use a caller-passed config for the payload body; it re-reads C's *current* local state: `loadCurrentInviteMembershipFreshnessState` → `getGroup` + `getMembers` + `buildGroupConfigPayload(group, members)` (`group_invite_auth.dart:142-184`); `effectiveGroupConfig = currentFreshnessState.groupConfig` (`send_group_invite_use_case.dart:158`); embedded as `payload.groupConfig` (`:250`). `buildGroupConfigPayload` copies `name/description/avatarBlobId/avatarMime/metadataUpdatedAt(=lastMetadataEventAt)` (`group_config_payload.dart:41-54`). At this instant C is still `test 2`, so the snapshot is `test 2` / `222` / old image.

3. **C updates to `test 3` (AFTER the invite was sent).** `updateGroupMetadata` mutates only local state and bumps `lastMetadataEventAt` (`update_group_metadata_use_case.dart:11-90`). Fan-out is at the call site (`group_info_wired.dart:1585-1657`): a fire-and-forget GossipSub publish (`callGroupPublish` at `:1585`), an offline-inbox store addressed to all members-minus-self **including D** (`recipientPeerIds` at `:1600-1638`), and direct-P2P sends. **D is not subscribed to the group topic and has no transport for this group**, so the live pubsub copy is missed; only the relay store-and-forward copy can reach D later.

4. **D persists the invite (card already shows `test 2`).** `PendingGroupInvite.fromPayload` copies the snapshot fields and stores `payloadJson` verbatim (`pending_group_invite.dart:63-98`). The pending-invite card renders `test 2` *before* D even taps Accept.

5. **D taps Accept → materialize from the frozen snapshot.** `acceptPendingGroupInvite` → `materializeAcceptedGroupInvitePayload` reads `config = payload.groupConfig` and builds the entire `GroupModel` from it: `name` (`handle_incoming_group_invite_use_case.dart:841`), `description` (`:843`), `avatarBlobId/avatarMime` (`:844-845`), `lastMetadataEventAt = metadataUpdatedAt` (`:869`), then `saveGroup` (`:872`). **D's settled local state is now `test 2`.** The avatar is downloaded from the snapshot's blob (`:900-908`).

6. **Join + drain run; one of them fails → `bridgeError`.** Two co-equal triggers:
   - `callGroupJoinWithConfig` throws / times out (documented 10s `BRIDGE_TIMEOUT`) → `(HandleGroupInviteResult.bridgeError, groupId)` on `BridgeCommandException`/`TimeoutException`/generic catch (`handle_incoming_group_invite_use_case.dart:943,955,962`) — *after* the group was already persisted at `:872`; the drain never runs.
   - On the success branch, the accept use case runs `_drainAcceptedGroupInboxBestEffort` (`accept_pending_group_invite_use_case.dart:295`), which returns **false on ANY thrown error** (`:611-635`); the drain rethrows on any error (`drain_group_offline_inbox_use_case.dart:250-262,371-385`).
   Transient relay errors self-heal first — `callGroupInboxRetrieveWithCursor` does 3 retries + relay reconnect + limit-halving (`bridge_group_helpers.dart:997-1041`) — so reaching `bridgeError` requires a **sustained** failure, which matches "D accepts immediately while the circuit relay is still converging."

7. **Partial commit — the three symptoms are minted here.** On `success` the use case persists the group, fetches the stale `test 2` row via `getGroup(acceptedId)` (`:307`), publishes the join timeline, then `if (!inboxDrained) return (bridgeError, group);` at `:321-323` — **before** `_commitAcceptedPendingInvite` (`:324`). The materialize-`bridgeError` branch (`:332-348`) returns the stale group identically. `_commitAcceptedPendingInvite` (`:531-551`) is the **only** caller of `deletePendingInvite` (`:550`). So the invite is never deleted (**BUG-2**), the UI shows the stale name (**BUG-1**), and the only accept-time channel that would have replayed `test 3` never completed (**BUG-3**).

> Where the failure stops, proven: even if the drain *did* begin applying `test 3`, the metadata handler writes `name`/`description`/`avatarBlobId` at `group_message_listener.dart:4591` **before** the avatar download at `:4619`. Since D shows a stale **name AND description AND image**, the `test 3` apply did **not** run at all — the throw occurred earlier (inbox fetch, or an earlier replay item), consistent with both `bridgeError` triggers above.

---

## Bug-1 — "Joined test 2, but recovery is still catching up"

**Symptom.** D accepts and sees a *success-flavored* error naming the **old** group.

**Root cause (CONFIRMED, high).** Accept returns `AcceptPendingGroupInviteResult.bridgeError` alongside the **already-persisted, stale-snapshot** `GroupModel`; the UI maps `bridgeError` + non-null group to `group_invite_joined_recovery(group.name)`, and `group.name` is the materialized `test 2`.

**Mechanism.**
1. Either the drain returns false (`accept_pending_group_invite_use_case.dart:321-323`) or `callGroupJoinWithConfig` throws/times out (`handle_incoming_group_invite_use_case.dart:943,955,962` → accept `:332-348`). Both converge on identical UI.
2. The group fetched at `:307` / `:334` is the row written at `handle_incoming_group_invite_use_case.dart:872` from the frozen `test 2` config.
3. `group_list_wired.dart:347-353` renders `group != null ? l10n.group_invite_joined_recovery(group.name) : l10n.group_invite_accepted_recovery`.
4. **"recovery" here is only a string label, not an active gate.** `GroupRecoveryGate` (`group_recovery_gate.dart:1-48`) is a depth counter checked by `updateGroupMetadata`/`addGroupMember`, but is **never referenced** by `acceptPendingGroupInvite` or `drainGroupOfflineInboxForGroup`. The copy implies an in-progress recovery that isn't actually running on D's path.

**Code evidence.** `accept_pending_group_invite_use_case.dart:321-323`; `group_list_wired.dart:347-353`; `app_en.arb:1180` (`group_invite_joined_recovery`), `:1188` (`group_invite_accepted_recovery`); `handle_incoming_group_invite_use_case.dart:841,869`.

**Localization divergence (secondary, CONFIRMED).** The Orbit accept UI hardcodes the English literal `'Joined ${group.name}, but recovery is still catching up'` (`orbit_wired.dart:1120-1126`) instead of the l10n key used by Group List (`group_list_wired.dart:347-353`). On a non-English locale, the same `bridgeError` shows English from Orbit but a localized string from Group List. Latent i18n bug on the same path, not a root cause.

**Why only the 4th member added right after a metadata change.** The success-flavored "Joined {name}" requires a non-null materialized group **plus** a `bridgeError`. B and C accepted before their relevant metadata changed and/or with a healthy drain, so they committed normally; D is the first member whose accept races a fresh metadata edit and a slow/failing relay drain.

---

## Bug-2 — Invitation persists / stays actionable after Accept

**Symptom.** After D taps Accept the pending-invite card stays present and Accept re-enables; D assumes it failed and keeps pressing.

**Root cause (CONFIRMED, high).** On any `bridgeError` exit the pending invite is **never deleted**, and the UI reloads invites unfiltered, so the card re-renders fully actionable once the in-flight lock clears.

**Mechanism.**
1. Both `bridgeError` exits (`accept_pending_group_invite_use_case.dart:321-323` and `:332-348`) return **before** `_commitAcceptedPendingInvite` (`:324`), the only path to `deletePendingInvite` (`:550`).
2. `getPendingInvites` maps every DB row with **zero** consumed/accepted/tombstone filtering (`pending_group_invite_repository_impl.dart:160-163`); the only removers are `deletePendingInvite` and expiry-cutoff sweeps (`:210-218`) — nothing clears a non-expired stuck invite.
3. The only concurrency guard is `_processingInviteIds`, set at `group_list_wired.dart:282` and cleared in `finally` (`:370-374`), so a *subsequent* tap is not blocked.
4. The card disables Accept only via `isProcessing || isExpired` (`pending_group_invite_card.dart:136-163`) — no disable on consumed/accepted state — so once `isProcessing` clears it is tappable again.
5. **Repeated taps re-fail without committing.** A second tap re-enters accept; materialize short-circuits to `duplicateGroup` (existing group, `handle_incoming_group_invite_use_case.dart:794-806`) → `_retryAcceptedMaterializedInvite` (`accept_…:349-365`). Because the metadata change was **key-neutral** (no rotation), `_compatibleAcceptedRetryGroup` passes (`:456-471`), so the retry re-joins + re-drains and re-hits `if (!inboxDrained) return (bridgeError, group)` at `:442-444` — again no commit/delete. As long as the relay fetch keeps failing, D can press Accept indefinitely and the invite never clears.

**Code evidence.** `accept_pending_group_invite_use_case.dart:321-330`; `pending_group_invite_repository_impl.dart:160-163`; `pending_group_invite_card.dart:136-163`.

**This is currently codified as intended behavior (two tests).**
- Widget test: `test/features/groups/presentation/group_list_wired_test.dart:777-818` ("bridgeError accept keeps the joined group and shows recovery warning") injects `group:join → {ok:false}` (`:781-784`) and asserts the pending invite is still non-null (`:798-801`), the card still renders (`:803-806`), the group exists (`:802`), and the snackbar reads "Joined Book Club, but recovery is still catching up" (`:808-811`).
- Use-case test `GCA-004`: `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:502-538` injects `inboxRetrieveCursor → {ok:false, RELAY_UNAVAILABLE}` and asserts `result == bridgeError`, `group isNotNull`, `getPendingInvite(...) isNotNull`, `getConsumedInvite(...) isNull`.

These pin both `bridgeError` sub-paths to the same "keep visible; catch-up will reconcile" intent. Scenario 7 is the case where catch-up does **not** reconcile within the user's patience, so a fix is a deliberate behavior change that must update these tests.

**Side effect (CONFIRMED).** `_publishAcceptedJoinTimelineBestEffort` runs **before** the `bridgeError` early-return on *every* attempt (`accept_…:308,335`), saving a `member_joined` row and re-publishing + re-storing a replay envelope. Because BUG-2 lets D re-tap repeatedly, each tap fans **duplicate join notifications** to A/B/C.

---

## Bug-3 — D settles on stale `test 2` / `222` / old image

**Symptom.** Under "All", D's group shows the OLD name, description and image — not C's `test 3`/`333`/new image.

**Root cause (CONFIRMED mechanism; severity corrected to eventually-consistent).** D's local group is materialized verbatim from the **send-time frozen snapshot** (`handle_incoming_group_invite_use_case.dart:841-872`), and the only accept-time channel that would converge `test 3` — the offline-inbox drain — failed with the same `bridgeError` driving BUG-1/BUG-2. The **watermark gate is NOT the blocker**; the failure is delivery-side.

**Mechanism.**
1. **Frozen snapshot** (see Failing Sequence §2,§5): the invite config is C's state at send time (`send_group_invite_use_case.dart:158,250`), i.e. `test 2`.
2. **No first-join staleness guard.** `_isStaleAgainstLocalGroupState` returns false when `localGroup == null` (`accept_pending_group_invite_use_case.dart:490-529`), so D's first accept treats the stale snapshot as authoritative instead of short-circuiting.
3. **Live pubsub missed D.** C's `test 3` `callGroupPublish` (`group_info_wired.dart:1585`) is fire-and-forget; D was not subscribed and GossipSub has no late-joiner replay.
4. **The watermark gate would PASS the event.** `_shouldIgnoreStaleMetadataEvent` ignores only events whose `eventAt` is **not** after the watermark (`group_message_listener.dart:4384-4388`). `test 3` eventAt > `test 2` watermark, so it would apply via `_applyAuthoritativeGroupConfigSnapshot` (`:4452-4633`, overwriting name/description/avatar and updating `lastMetadataEventAt` at `:4609-4610`). Convergence fails on **delivery**, not suppression.
5. **The only accept-time catch-up channel failed.** The drain feeds `__sys: group_metadata_updated` replays through `groupMessageListener.handleReplayEnvelope(..., rethrowOnError:true)` (`drain_group_offline_inbox_use_case.dart:586-606`) → `_applyAuthoritativeGroupConfigSnapshot`. The pre-join skip gate would **not** drop `test 3`: `shouldSkipPreJoinReplay` skips only when `relayTimestamp.isBefore(selfJoinedAt)` (`:477-480`), and C's edit is *after* D's `joinedAt` (C added D first). A *successful* drain would converge — but the drain threw.
6. **No re-broadcast on join.** `_handleMemberJoined` only writes a timeline row (`group_message_listener.dart:2734-2773`); nothing makes C re-publish current metadata to D, and the accept/join flow never re-requests current group metadata from inviter or relay.

**Severity correction — eventually-consistent, not permanent.** A failed drain does **not** consume C's stored `test 3` copy: the inbox cursor only advances after a page is processed, and a failure leaves it un-advanced (`drain_group_offline_inbox_use_case.dart:777-781`). Re-drains fire automatically on app resume (`handle_app_resumed.dart:180`), startup (`startup_router.dart:587`, `main.dart:1769`), periodically via `PendingMessageRetrier` (`main.dart:1949`), on notification open, and on every repeated Accept (the `duplicateGroup` retry re-runs the drain). So D **typically converges to `test 3` on a later successful drain without C re-broadcasting.** The durable failure window is the accept attempt; whether the user's observed staleness *persists* depends on **relay-side (Go) retention/redelivery** of C's stored `test 3` copy — the chief remaining unknown (see Open Questions). The user-reported "stuck on test 2" is consistent with either a still-failing relay window or expiry of the stored copy before a drain succeeded.

**Avatar stickiness (CONFIRMED).** The old image is slightly stickier than name/desc: `_applyAuthoritativeGroupConfigSnapshot` re-downloads the avatar only when `avatarChanged`/`nextAvatarPath == null` (`group_message_listener.dart:4614-4624`), so the settled avatar path can persist until a strictly-newer metadata event with a different `avatarBlobId` is applied.

**Confidence.** High on mechanism (snapshot freeze, delivery gap, watermark non-suppression); the permanence framing was corrected from "permanent" to eventually-consistent during adversarial review.

**Why only the 4th member added right after a metadata change.** BUG-3 is strictly an ordering bug: it requires `add D` → `update to test 3` → `D accepts`. Had C updated *before* inviting D, the snapshot would carry `test 3`. Earlier members joined before the relevant edits, so their snapshots were already current.

---

## Shared Root Cause(s)

1. **Partial commit coupled to a best-effort catch-up drain (highest leverage).** Accept persists the group + announces the join, then treats a drain/join failure as a hard `bridgeError` and returns **before** consuming the invite (`accept_pending_group_invite_use_case.dart:321-323`, `:332-348` vs the only `deletePendingInvite` at `:550`). One failure → BUG-1 (copy) + BUG-2 (un-consumed invite) + BUG-3 (the un-run drain was the only accept-time catch-up channel).
2. **Send-time frozen metadata snapshot with no on-join resync.** D materializes from `payload.groupConfig` captured at invite-send time (`send_group_invite_use_case.dart:158,250` → `handle_incoming_group_invite_use_case.dart:841-872`), and nothing re-requests the latest authoritative config when a member joins after a metadata change. Even with a perfect drain this is fragile; combined with Defect 1 it is durable.

---

## Contributing / Secondary Factors

- **Two `bridgeError` triggers, drain-independent.** The `callGroupJoinWithConfig` timeout path (`handle_incoming_group_invite_use_case.dart:943,955,962` → accept `:332-348`) fires **before** the drain runs and is at least as likely as the drain-throw path; both produce identical UI. (CONFIRMED.)
- **First-join staleness guard is inert.** `_isStaleAgainstLocalGroupState` returns false for `localGroup == null` (`accept_…:496-497`), so D's first accept never rejects the stale snapshot. (CONFIRMED.)
- **Watermark seeded from the stale snapshot, but recoverable.** `lastMetadataEventAt = metadataUpdatedAt` from `test 2` (`handle_incoming_group_invite_use_case.dart:869`) — yet `test 3` eventAt is strictly newer, so the gate still passes it (`group_message_listener.dart:4384-4388`). (CONFIRMED.)
- **All-or-nothing page cursor.** A mid-page throw leaves the cursor un-advanced (`drain_…:777-781,844-860`), so an immediate retry re-fetches and re-fails the identical page — which is why re-tapping Accept never helps even though a *later* (better-conditioned) background drain can. (CONFIRMED.)
- **Repeated-Accept amplification.** Each re-tap re-publishes a `member_joined` timeline + replay envelope (`accept_…:308,335`), fanning duplicate join notifications. (CONFIRMED.)
- **Transient relay errors self-heal first.** 3 retries + reconnect + limit-halving (`bridge_group_helpers.dart:997-1041`); only a sustained 10s-per-attempt timeout or persistent non-transient errorCode reaches the drain wrapper, so the bug needs a **sustained** relay failure. (CONFIRMED.)
- **Orbit vs Group-List i18n divergence** on the BUG-1 string (`orbit_wired.dart:1120-1126` hardcoded English vs `group_list_wired.dart:347-353` localized). (CONFIRMED.)
- **Clock-skew fragility (UNCERTAIN).** Convergence on a successful drain hinges on C's edit `changedAt` > D's snapshot `joinedAt` watermark (`drain_…:477-480`); skew between C's add-member and edit could flip the skip gate and silently drop `test 3`. Favorable in Scenario 7, but a real latent fragility.

---

## Affected Files (map)

- `lib/features/groups/application/accept_pending_group_invite_use_case.dart` — partial-commit logic; `bridgeError` early-returns `:321-323`/`:332-348`; sole `deletePendingInvite` via `_commitAcceptedPendingInvite` `:531-551`; retry path `:349-365`/`:430-444`; inert first-join staleness guard `:490-529`; best-effort drain wrapper `:611-635`. **Root of BUG-1 + BUG-2; the failure that locks BUG-3.**
- `lib/features/groups/application/handle_incoming_group_invite_use_case.dart` — materialize from frozen snapshot `:841-872`; avatar download `:900-908`; join-timeout `bridgeError` `:943,955,962`; duplicate short-circuit `:794-806`. **Root of BUG-3's stale state + second BUG-1 trigger.**
- `lib/features/groups/application/send_group_invite_use_case.dart` — re-reads C's current state at send time `:144-158`; embeds as `payload.groupConfig` `:250`. **Why the snapshot is `test 2`.**
- `lib/features/groups/application/group_invite_auth.dart` — `loadCurrentInviteMembershipFreshnessState` single point-in-time read `:142-184`.
- `lib/features/groups/application/group_config_payload.dart` — copies name/desc/avatar/metadataUpdatedAt into the snapshot `:41-54`.
- `lib/features/groups/application/add_group_member_use_case.dart` — D becomes a local member at step 20 (`:311`) → D is a targeted replay recipient at step 21.
- `lib/features/groups/application/update_group_metadata_use_case.dart` — local metadata write + `lastMetadataEventAt` watermark `:11-90`; admin/recovery gates `:32-55`.
- `lib/features/groups/presentation/screens/group_info_wired.dart` — metadata-update fan-out (pubsub `:1585` + inbox-store to members incl. D `:1600-1638` + direct) `:1585-1657`.
- `lib/features/groups/application/group_message_listener.dart` — convergence handler `_applyAuthoritativeGroupConfigSnapshot` `:4452-4633`; name/desc written before avatar download `:4591` vs `:4619`; non-suppressing watermark gate `:4384-4388`; avatar re-download condition `:4614-4624`; `_handleMemberJoined` (no re-broadcast) `:2734-2773`. **The receive path that would converge `test 3` if delivered.**
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart` — rethrow-on-error → false `:250-262`; `rethrowOnError:true` replay routing `:586-606`; pre-join skip gate `:477-480`; cursor-un-advanced-on-failure `:777-781,844-860`. **The catch-up channel that fails.**
- `lib/features/groups/domain/repositories/pending_group_invite_repository_impl.dart` — unfiltered `getPendingInvites` `:160-163`; deleters `:210-218`. **Why the invite re-renders (BUG-2).**
- `lib/features/groups/domain/models/pending_group_invite.dart` — `fromPayload` freezes snapshot fields `:63-98`. **Card shows `test 2` pre-accept.**
- `lib/features/groups/presentation/screens/group_list_wired.dart` — `bridgeError` snackbar `:347-353`; unfiltered reload `:191-197`; transient lock `:282,370-374`.
- `lib/features/orbit/presentation/screens/orbit_wired.dart` — hardcoded-English `bridgeError` copy `:1120-1126`; same un-consumed reload (`:1086`).
- `lib/features/groups/presentation/widgets/pending_group_invite_card.dart` — Accept disabled only by `isProcessing||isExpired` `:136-163`.
- `lib/features/groups/application/group_recovery_gate.dart` — depth-counter only; **not** on the accept path `:1-48` (rules out an active gate behind the BUG-1 copy).
- `lib/l10n/app_en.arb` — `group_invite_joined_recovery` `:1180`, `group_invite_accepted_recovery` `:1188`.
- Tests pinning current behavior: `test/features/groups/presentation/group_list_wired_test.dart:777-818`; `test/features/groups/application/accept_pending_group_invite_use_case_test.dart:502-538` (GCA-004).

---

## Recommended Fix Directions (analysis-level, not prescriptive code)

- **Shared / highest leverage:** decouple invite-consumption from catch-up success. Consume (or tombstone) the pending invite once the group is **durably materialized + joined**, and demote the inbox drain to a genuinely background/retryable step that does not return a hard `bridgeError` to the UI. This collapses BUG-1 and BUG-2 and stops the repeated-Accept publish amplification.
- **BUG-1:** stop surfacing a success-name "Joined {name}" when the result is a failure; render a neutral, non-actionable status and rely on idempotent background retry rather than a user-driven loop. Route the Orbit copy through the l10n key to fix the i18n divergence.
- **BUG-2:** delete/tombstone the invite on the durable-join boundary regardless of drain outcome; if the design must keep it on failure, filter accepted/materialized invites out of `getPendingInvites` so the card cannot re-render as a fresh action.
- **BUG-3:** add a **post-join authoritative-metadata resync** — on materialize/join, have the new member request the inviter's (or relay's) *current* groupConfig, or have the inviter push the latest authoritative snapshot to a member who joined after the last metadata edit. The watermark already accepts a newer event; the missing piece is delivery to a late joiner that doesn't depend on relay retention of a one-shot store-and-forward copy.

These are directions only; each needs the four-user regression in `Test-Flight-Improv/95-*` (which already fails on convergence) plus a direct accept-path test asserting that, on a drain/join failure, the invite is consumed, the group converges to the latest metadata, and the user is not shown an actionable stale invite. Updating `group_list_wired_test.dart:777-818` and `accept_pending_group_invite_use_case_test.dart:502-538` (GCA-004) is part of the fix, since they currently lock in the buggy behavior.

---

## Open Questions / Needs Device or Go Confirmation

1. **Relay-side retention/redelivery (UNCERTAIN — Go, the key unknown).** The Dart receive path is confirmed capable of converging `test 3` on a later successful drain. Whether C's stored relay-inbox `test 3` copy is actually **retained and re-served** to D after the first failed drain is relay-side (Go), outside the traced Dart files — and it determines whether the user's observed staleness is temporary or effectively permanent.
2. **Dominant `bridgeError` trigger (UNCERTAIN ranking).** Join-with-config timeout vs inbox-drain throw both produce identical symptoms; which dominates in the field needs a device log capture of the `bridgeError` origin (`GROUP_INVITE_HANDLE_BRIDGE_TIMEOUT` vs `PENDING_GROUP_INVITE_ACCEPT_INBOX_DRAIN_WARNING`).
3. **Live-pubsub timing (UNCERTAIN — device).** Static trace confirms D was not subscribed when C published `test 3` and GossipSub has no late-joiner replay, but the exact subscribe-vs-publish ordering on real circuit-relay timing is not statically provable.
4. **Eventual convergence in practice (UNCERTAIN).** Code shows automatic re-drains re-fetch the un-consumed copy with cursor un-advanced; whether D *actually* converges in a real run depends on (1) and was not device-confirmed.
5. **Clock-skew skip-gate flip (UNCERTAIN).** If C's edit timestamp ever precedes D's snapshot `joinedAt` watermark (`drain_…:477-480`), `test 3` would be silently skipped even on a successful drain. Favorable in Scenario 7; needs a skew-injection check to rule out as a latent permanent-staleness path.
