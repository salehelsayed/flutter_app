# Review 08 — Invite/Join Reliability — TDD Implementation Plan

> **Branch:** `124-harness-refactor` · **Main:** `main`
> **Working-tree DB version:** `currentIdentityDatabaseVersion = 89` (`lib/core/database/app_database_version.dart:1`); highest migration on disk is `089_media_attachment_download_retry_column.dart`. **Next-free migration = `090`.**
> **Status of this document:** verify+refute pass complete (6 findings A–F, ~12-agent verify/refute). **Every review line number has been re-checked against current source and corrected below.** Where the original review or the recon brief disagreed with source, source wins and the divergence is called out inline.
>
> **Two recon premises were stale and are corrected here:**
> 1. Recon said `DB v88 / next-free 089`. **Reality: v89, next-free 090.** Migration `089` is already taken by finding-09 media-download work. Findings **C, E (fallback), and F** that the original assessments scoped against `089` must target **`090`** and re-check at landing.
> 2. The review's named receive-side gate `_shouldIgnoreStaleMetadataEvent in group_message_listener` **does not exist**; `group_message_listener.dart` has zero metadata logic. The real watermarks are `inviteMetadataIsCurrent` (`handle_incoming_group_invite_use_case.dart:962-972`) and `isStaleGroupMembershipEvent` (`group_membership_event_watermark.dart:48`). Finding D mirrors those.

---

## 1. Verification verdicts (what actually ships)

| # | Improvement | Review status | Verified verdict (after refute) | This plan |
|---|---|---|---|---|
| **A1** | Card-vs-proof TTL alignment (widen to 7d) | open | **ALREADY DONE** — `groupInviteMembershipFreshnessTtl == Duration(days: 7)` (`group_invite_payload.dart:19`); card expiry minted from same constant (`group_invite_auth.dart:129`); ceiling `hasSaneTtlWindow` also uses it (`:291-294`) | **DROP** (no work) |
| **A2** | Humanise genuine >7d expiry: dedicated `expiredFreshness` result + "ask resend" string | open | **CONFIRMED OPEN** — accept collapses `staleMembershipFreshness` → `invalidPayload` + misleading `INVALID_SIGNATURE` telemetry (`accept_…:169-182`) | **SLICE 1** (no migration, no wire) |
| **B1** | Schedule `deleteExpired{Pending,Revoked,Consumed}Invites` + tombstones at startup/resume | open | **CONFIRMED OPEN** — all 4 methods + DB helpers + ctor wiring exist; **zero production schedulers**; no `GROUP_INVITE_SWEEP_*` event | **SLICE 2** (no migration, no wire) |
| **B2** | Filter dead cards (`getPendingInvites` unfiltered) | open | **NARROWED** — card already disables expired Accept + keeps a working Decline (`pending_group_invite_card.dart:140`), so they are *degraded*, not *actionable-dead*. Only sound filter = "drop invites whose `groupId` is already a joined group" | **SLICE 2 (narrowed)** |
| **C** | Wire invite revocation into admin UI | open | **NARROWED (larger than review)** — send side genuinely unwired; receive side fully live. But **migration `090` MANDATORY** (CHECK constraint `067:10-16` + `invite_id` persistence for HOLE-4) — contradicts review's "no migration" twice | **SLICE 3** (migration `090`) |
| **D** | On-join authoritative-metadata resync (pull) | open | **CONFIRMED OPEN & BROADER** — pull surface absent; refute found there is **no receive-side metadata applier at all** (published actorEvent never verified/applied). New wire pair + first metadata applier | **SLICE 5** (new wire; flag-gated; no migration) |
| **E** | Mark "joining…" + bound half-materialized state | open | **NARROWED** — bounded-retry loop now exists (088 `group_rejoin_state`, telemetry-only bound); residual = stamp at failure site + derived badge + give-up UX (no auto-delete) | **SLICE 4** (preferred: **no migration**, derive from 088) |
| **F** | Decline acknowledgement to inviter | open | **CONFIRMED OPEN** — `declinePendingGroupInvite` is 100% local; no `declined` status / `markDeclined` / receive handler. **Migration `090` MANDATORY** (CHECK rebuild) | **SLICE 6** (migration `090`) |

**Build order (front-loading no-migration / no-wire quick wins, then migration-bearing, then new-wire last):**
`A2 → B → E → C → F → D`

Rationale for the swap vs the prompt's "A2→B→C→E→D→F": E is **Dart-only / no-migration** in its preferred form and is a pure quick win, so it precedes the migration-bearing C/F. D is the only finding with a **new wire protocol + a brand-new receive-side applier + a security-relevant authenticity gate**, so it ships last. **C and F both need migration `090`** — only one can take that number; the second-to-land bumps to `091` (see §4).

---

## 2. Corrected source anchors (current `file:line`)

> All verified against working tree on `124-harness-refactor`. ✎ = review/recon was stale.

### Shared / cross-finding
| Symbol | Anchor |
|---|---|
| DB version | `lib/core/database/app_database_version.dart:1` (`= 89`) ✎ recon said 88 |
| Highest migration | `lib/core/database/migrations/089_media_attachment_download_retry_column.dart` ✎ next-free = **090** |
| `sweepExpiredPosts` startup (mirror) | `lib/main.dart:3073` ✎ recon said 3066 |
| `sweepExpiredPosts` resume (mirror) | `lib/main.dart:4177` ✎ recon said 4171 |
| Retrier registration `.start()` block | `lib/main.dart:~2933-2938` (groupPendingKeyRepairBackoffTimer / pendingPostMediaUploadRetrier / keyExchangeRetrier) |
| `orbit_wired.dart` location | `lib/features/orbit/presentation/screens/orbit_wired.dart` ✎ recon/review used groups path |
| `getPendingInvites` (unfiltered) | `pending_group_invite_repository_impl.dart:160-162`; callers `orbit_wired.dart:582`, `group_list_wired.dart:200`, `feed_wired.dart:661` |
| GroupInviteListener routing seam | `group_invite_listener.dart:141` (`_onMessage`); revocation discriminator `:171-176`; fall-through `storeIncomingPendingGroupInvite` `:215` |
| GroupInviteListener ctor (no delivery repo) | `group_invite_listener.dart:46-63` — has `groupRepo/pendingInviteRepo/contactRepo/bridge`, **no `GroupInviteDeliveryAttemptRepository`** |

### Finding A2
| Symbol | Anchor |
|---|---|
| `enum AcceptPendingGroupInviteResult` (no `expiredFreshness`) | `accept_pending_group_invite_use_case.dart:25-36` |
| Collapse branch (`invalidSignature‖missingSignature‖staleMembershipFreshness` → `invalidPayload`) | `accept_…:169-182` (returns `invalidPayload` at `:181`) |
| Deferred freshness re-check | `accept_…:145` (`currentTimeValidationFailure(effectiveNow)`) |
| Parse with **no** validationTime | `accept_…:108-110` |
| `isSecurityFailure` alt path (lists stale) | `accept_…:111-121` |
| `staleMembershipFreshness` **sole producer** | `group_invite_payload.dart:853-854` (inside `_validateMembershipFreshnessAt :837-857`) |
| `isSecurityFailure` getter (lists stale) | `group_invite_payload.dart:47-50` |
| TTL constant (7d) | `group_invite_payload.dart:19` |
| `group_list_wired` `invalidPayload→group_invite_invalid` | `group_list_wired.dart:340-341` ✎ review said 337-338 |
| `orbit_wired` `invalidPayload→`hardcoded EN `'Invite is no longer valid'` | `orbit_wired.dart:1124-1125`; `bridgeError→'Failed to accept invite'` `:1131` (**entire switch hardcoded EN, no l10n**) |
| Retry wrappers (both gate on `bridgeError && group==null`) | `group_list_wired.dart:373` def / `:411-415` guard / count=5 `:90` / call `:294`; `orbit_wired.dart:1157` def / `:1199-1203` guard / count=5 `:191` / call `:1076` |
| ARB anchors | `lib/l10n/app_en.arb|app_ar.arb|app_de.arb`: `group_invite_expired` `:1192`, `group_invite_invalid` `:1197`; **`group_invite_expired_ask_resend` absent** |

### Finding B
| Symbol | Anchor |
|---|---|
| `deleteExpiredPendingInvites` impl | `pending_group_invite_repository_impl.dart:215` (siblings `:221`/`:227`/`:233`) |
| `deleteExpiredWelcomeKeyPackageTombstones` impl | `pending_group_invite_repository_impl.dart:233` |
| Iface decls | `pending_group_invite_repository.dart:33/35/37/39` |
| DB helper (deletes only expired) | `pending_group_invites_db_helpers.dart:148-164` (`where: 'expires_at <= ?'`) |
| Repo ctor closure wiring (all 4) | `lib/main.dart:1267-1274` |
| Card disabled-accept + expired label | `pending_group_invite_card.dart:27` (`isExpired`), `:28-33` (labels), `:91-99` (chip), `:140` (accept disabled) |
| `isExpiredAt` model | `pending_group_invite.dart:122`; `pendingGroupInviteTtl = Duration(days:7)` `:4` |
| Fake repo (harness ready) | `test/shared/fakes/in_memory_pending_group_invite_repository.dart:89/101/113` |

### Finding C
| Symbol | Anchor |
|---|---|
| `revokePendingGroupInvite` (unwired) | `revoke_pending_group_invite_use_case.dart:20` (0 prod callers) |
| `sendGroupInviteRevocation` (unwired) | `revoke_pending_group_invite_use_case.dart:68`; direct `:224` → inbox `:242` |
| `GroupInviteDeliveryStatus` (no `revoked`) | `group_invite_delivery_attempt.dart:1-7` (sent/queued/needsResend/cannotSend/joined/unknown); `toValue` `:9-24`, `fromValue` `:26-44` (**`default:` throws `:42`**) |
| DB CHECK constraint | `067_group_invite_delivery_attempts.dart:10-16` (sent/queued/needs_resend/cannot_send/joined ONLY) ✎ refute confirmed: **needs rebuild migration** |
| `markJoined` (mirror for `markRevoked`) | `group_invite_delivery_attempt_repository_impl.dart:131-162`; iface `:29-34` |
| `_onResendInvite` (mirror) | `group_info_wired.dart:2016-2081` ✎ review said 1736/1748 |
| resend button wired | `group_info_wired.dart:2143-2145` |
| resend gate (**only `==needsResend`**) | `group_info_screen.dart:551-560` ✎ review assumed sent/queued/needsResend |
| resend TextButton render | `group_member_row.dart:99-110` (key `group-member-resend-invite-<peerId>`) |
| presentation mapper (no `revoked`) | `group_invite_status_presentation.dart:8-21` |
| receiver-side revocation handler (live) | `handle_incoming_group_invite_use_case.dart:405-438` |
| `GroupInviteDeliveryAttempt` fields (**no `inviteId`** — HOLE-4) | `group_invite_delivery_attempt.dart:48-54` |
| pending-invite repo instance | `main.dart:1242` |

### Finding D
| Symbol | Anchor |
|---|---|
| `materializeAcceptedGroupInvitePayload` | `handle_incoming_group_invite_use_case.dart:802-803`; persists `lastMetadataEventAt` `:924`; success `:1043` ✎ review stale |
| `inviteMetadataIsCurrent` watermark | `handle_incoming_group_invite_use_case.dart:962-972` ✎ review said 982-990 |
| `metadataUpdatedAt` parse | `handle_incoming_group_invite_use_case.dart:901,905-907` |
| send-invite `effectiveGroupConfig` snapshot | `send_group_invite_use_case.dart:144` (re-snapshot), `:158` (build), `:245/:250` (consume) |
| accept success returns (resync hook) | `accept_pending_group_invite_use_case.dart:367,:445,:567,:606` ✎ review's `:701-702` is the `_isStaleAgainstLocalGroupState` helper, not a success site |
| revocation transport (mirror) | `revoke_pending_group_invite_use_case.dart:68/124/162/193/207/224/242` |
| admin metadata send + publish | `update_group_metadata_use_case.dart:11` (local persist; **admin-only, throws for non-admins `:48-56`, throws under recovery `:33`**); `group_info_wired.dart:1676` call, `:1720-1721` signed `actorEvent`, `:1803` `callGroupPublish` |
| signed-actorEvent build/verify | `group_config_payload.dart:466` (`buildSignedGroupMetadataActorEventEnvelope`) / `:479` (`extractGroupMetadataActorEventVerificationData` — **defined but never consumed in lib/**) / `:491` |

### Finding E
| Symbol | Anchor |
|---|---|
| `materializeAcceptedGroupInvitePayload` join try | `handle_incoming_group_invite_use_case.dart:981-988` |
| repairable-only rollback | `handle_incoming_group_invite_use_case.dart:990-1006` (`_rollbackMaterializedInviteState :991` → `invalidPayload :1005`) |
| **non-repairable BridgeCommandException → bridgeError, no rollback** | `handle_incoming_group_invite_use_case.dart:1007-1012` |
| **TimeoutException → bridgeError, no rollback** (the leak) | `handle_incoming_group_invite_use_case.dart:1013-1024` ✎ review said 902-908 |
| **generic catch → bridgeError, no rollback** | `handle_incoming_group_invite_use_case.dart:1025-1032` |
| `_isRepairableJoinMaterialError` allowlist | `handle_incoming_group_invite_use_case.dart:1074-1098` |
| `_rollbackMaterializedInviteState` (inner) | `handle_incoming_group_invite_use_case.dart:1100-1107` |
| GroupModel (no `joinState`) | `group_model.dart:49`; `isDissolved :87`; `lastMetadataEventAt :109`; `copyWith :217` (sentinel `:237/:279`) |
| accept materialize call | `accept_pending_group_invite_use_case.dart:287`; bridgeError case `:368-449`; conditional rollback `:411-419` (gate `welcomeKeyPackage!=null :413`); verdict `:443-449` |
| `rejoinGroupTopics` | `rejoin_group_topics_use_case.dart:95`; success clears row `:213-218`; backoff defer skip `:183-198`; no-key skip `:152`; dissolved skip `:123`; `_maxRejoinAttempts=10 :71`; `_rejoinBackoffDelay :73`; **`GROUP_REJOIN_PERMANENTLY_STUCK` telemetry-only `:250-261`** |
| 088 table (NOT a column) | `088_group_rejoin_state.dart:26-32` (`group_rejoin_state(group_id PK, rejoin_attempt_count, next_eligible_at)`) |
| rejoin-state helpers | `group_rejoin_state_db_helpers.dart:10` (`dbLoadGroupRejoinStates`), `:19` (`dbRecordGroupRejoinFailure`), `:34` (`dbClearGroupRejoinState`) |
| rejoin trigger fan-out | `startup_router.dart:664`; `handle_app_resumed.dart:219 & :335` (gated `enableResumeGroupRecovery :26`); pending retrier `main.dart:2701-2733`; `hydrate_groups_from_peers_use_case.dart:47` |

### Finding F
| Symbol | Anchor |
|---|---|
| `declinePendingGroupInvite` (local-only) | `decline_pending_group_invite_use_case.dart:8-52`; tombstone helper `:54-71`; **imports no p2p/bridge** |
| call sites | `orbit_wired.dart:1255` (`_onDeclinePendingInvite`); `group_list_wired.dart:466` |
| inviter-side `markJoined` (the only delivery advance) | `group_message_listener.dart:3363,:3386` |
| status enum / CHECK | enum `group_invite_delivery_attempt.dart:1-7`; CHECK `067:10-16` (no `declined`) |
| exhaustive switches (RED leverage on enum add) | `group_invite_status_presentation.dart:8-21`; `group_member_row.dart:228-248` |
| delivery repo wiring | instantiated `main.dart:1277`; passed to message listener `main.dart:2390/2784/2796`; **NOT to GroupInviteListener** (constructed `main.dart:2561`) |
| `PendingGroupInvite` (no inviter ML-KEM) | `pending_group_invite.dart:7-17` (`senderPeerId/senderUsername` + `payloadJson`, no `mlKemPublicKey`) |
| revocation `revokedByPeerId==message.from` guard (mirror for spoof) | `handle_incoming_group_invite_use_case.dart:~316`; member-binding `group_invite_auth.dart:339` |

---

## 3. Migration & sequencing strategy

**Only findings C, E (fallback path only), and F can touch migrations. The preferred E path needs NO migration.**

| Finding | Migration? | Number | Notes |
|---|---|---|---|
| A2 | **No** | — | enum + branch + ARB + UI mapping only |
| B | **No** | — | all 4 side tables + `expires_at` + delete helpers already exist |
| **E (preferred)** | **No** | — | derive "joining…" badge from existing 088 `group_rejoin_state`; stamp `dbRecordGroupRejoinFailure` at failure site |
| E (fallback only) | If a literal `groups.join_state` column is *mandated* | **`090`** | strongly discouraged (drift risk vs 088 table); write only from the two paths that mutate `group_rejoin_state` |
| **C** | **Yes (mandatory)** | **`090`** | (a) rebuild `group_invite_delivery_attempts` CHECK to include `revoked`; (b) add `invite_id` column to feed `sendGroupInviteRevocation`'s required `inviteId` (HOLE-4) |
| **F** | **Yes (mandatory)** | **`090`** | rebuild same table's CHECK to include `declined` |

**Collision resolution (C, E-fallback, F all want `090`):**
- If **C lands first**: its `090` migration should rebuild the CHECK to include **both `revoked` and `declined`** in one table-rebuild (cheaper, one rebuild) and add `invite_id`. Then F reuses the already-expanded CHECK and needs **no further migration** (only the enum value + `markDeclined`). This is the recommended sequencing — fold C+F's CHECK changes into one `090`.
- If **F lands first**: F's `090` adds `declined`; C then needs `091` for `revoked` + `invite_id` (two rebuilds — worse).
- **Recommendation:** land C and F's table changes together in a single `090` rebuild (`CHECK(status IN ('sent','queued','needs_resend','cannot_send','joined','revoked','declined'))` + `invite_id` column), even if the UI/transport for each ships in separate PRs.

> **⚠ Re-check-at-landing (concurrent churn):** the groups migration band is hot — 078–080 were contended (03/09/self-heal), 081/082 reserved by 07-S2/S3, 088 took rejoin-state, **089 is already media-download**. Before writing `090`, run `ls lib/core/database/migrations/ | sort | tail` and confirm `090` is still free; bump to the next free number and update `currentIdentityDatabaseVersion` + `full_migration_chain_test.dart` accordingly.

---

## 4. SLICE 1 — A2: Humanise the genuine >7d expiry

**No migration, no wire, no Go.** Pure Dart client-side accept-time decision. Inviter need not be online.

### RED tests
**`test/features/groups/application/accept_pending_group_invite_use_case_test.dart`**
1. `'returns expiredFreshness (not invalidPayload) for a correctly-signed invite whose membership freshness proof is >7d old'` — arrange via existing `signedInvite(makeInvite(...))` + `_makeFreshnessProof` (test file `:38`) with `expiresAt` override (param `:73`) = `issuedAt + 7d + 1s` (structurally valid + sane-TTL + timestamp-compatible but `!isFreshAt`). Drive `now = issuedAt + 7d + 1s`. Assert `result == AcceptPendingGroupInviteResult.expiredFreshness` **AND** `pendingInviteRepo.getPendingInvite(groupId) == null` (delete still runs). RED: enum member absent → won't compile; once added, current `:181` returns `invalidPayload`.
2. NEGATIVE guard `'a tampered proof (structural mismatch / missing inviteSignature) still returns invalidPayload, NOT expiredFreshness'` — reuse the "malformed signed payload" arrange (tampered `groupKey`, test `:2863-2879`) + a missing-signature variant; assert `invalidPayload`. Locks that branching stale leaks no forgeries.
3. TELEMETRY RED — assert the new path emits a **distinct** flow event `PENDING_GROUP_INVITE_ACCEPT_EXPIRED_FRESHNESS` and **NOT** `PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE`, via the test's `emitFlowEvent` capture seam.
4. RETRY-ISOLATION — accept yielding `(expiredFreshness, null)` must not enter `_acceptPendingInviteWithRecoveryRetry`'s loop (no extra `attempt()/drain` calls). GREEN-by-construction given `:411-415`, but lock it.

**`test/features/groups/presentation/screens/group_list_wired_test.dart`** — pump accept yielding `(expiredFreshness, null)`; assert SnackBar shows `l10n.group_invite_expired_ask_resend`, **not** `group_invite_invalid`.

**`test/features/orbit/presentation/screens/orbit_wired_test.dart`** — same `expiredFreshness` → assert the new resend-prompt string appears, not `'Invite is no longer valid'`. **Catches HOLE-2.**

**l10n presence** (analyzer/codegen gate or test) — assert `AppLocalizations` exposes `group_invite_expired_ask_resend` for en/ar/de.

### GREEN implementation
1. **Enum** — add `expiredFreshness` to `AcceptPendingGroupInviteResult` at `accept_…:25-36` (place next to `expired`).
2. **Split the branch at `accept_…:169-182`** — keep `invalidSignature ‖ missingSignature → deletePendingInvite + emit PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE + return invalidPayload`; add a **separate preceding** `if (currentTimeFailure == GroupInvitePayloadParseFailure.staleMembershipFreshness) { await pendingInviteRepo.deletePendingInvite(groupId); emitFlowEvent(layer:'FL', event:'PENDING_GROUP_INVITE_ACCEPT_EXPIRED_FRESHNESS', details:{...prefix}); return (AcceptPendingGroupInviteResult.expiredFreshness, null); }`. Keeping `deletePendingInvite` is correct (a >7d proof can never become fresh again).
3. **Defensive (HOLE-3)** — at `accept_…:111-121`, special-case `parsedPayload.failure == staleMembershipFreshness` inside the `isSecurityFailure` block to **also** return `expiredFreshness`, so the mapping survives if any caller ever passes a `validationTime` to `parseJsonDetailed` (today it does not — `:108`). *Alternative:* drop `staleMembershipFreshness` from `isSecurityFailure` (`group_invite_payload.dart:47-50`) and let the deferred `:145` check own it. Cheap insurance.
4. **ARB triple-write** — add `group_invite_expired_ask_resend` to `app_en.arb`/`app_ar.arb`/`app_de.arb` near line 1192 (mirror `group_invite_expired`). EN suggestion: *"This invite has expired. Ask the group admin to send a fresh one."* Provide ar/de. Regenerate `app_localizations*.dart`.
5. **`group_list_wired.dart`** — add `case AcceptPendingGroupInviteResult.expiredFreshness: _showSnackBar(l10n.group_invite_expired_ask_resend);` in the switch (`:314-347`), between `:326` `expired` and `:341` `invalidPayload`.
6. **`orbit_wired.dart`** (`lib/features/orbit/...`) — add the `expiredFreshness` case in the switch `:1100-1131`. Its switch is **100% hardcoded EN**; preferred fix is to **wire `l10n` into orbit_wired** and use `l10n.group_invite_expired_ask_resend` (and opportunistically migrate `invalidPayload`/`bridgeError` to l10n to close the recon-noted localization gap). Minimum: add a parallel hardcoded EN string.
7. **No retry-wrapper change** — `:411-415` (group_list) and `:1199-1203` (orbit) already gate on `bridgeError && group==null`, so `expiredFreshness` terminates immediately.

### Gotchas / invariants
- **HOLE-2 is compile-time-enforced**: adding the enum member makes both exhaustive switches non-exhaustive → analyzer flags both call sites. Verify `flutter analyze` lights up `orbit_wired` too.
- **HOLE-1 (telemetry)**: stale must get its own event or the new path emits the misleading `INVALID_SIGNATURE`. Any dashboard counting `PENDING_GROUP_INVITE_ACCEPT_INVALID_SIGNATURE` must tolerate stale moving.
- **No false-success**: `deletePendingInvite` retained (dead row); does NOT auto-trigger resync (the "ask resend" string is a user prompt only — no inviter-online dependency).
- A2 humanises the failure but does **not** remove the stale row pre-tap (that's B's sweep + filter).

### Gates
`flutter analyze` (0 new; exhaustive-switch confirms both UI sites) · new use-case tests + both widget mapping tests + l10n presence · no migration, no Go rebuild.

---

## 5. SLICE 2 — B: Sweep expired invites & tombstones; filter dead cards

**No migration, no wire.** B1 = scheduler (load-bearing). B2 = **narrowed** to materialized-only render filter.

### RED tests
**`test/features/groups/application/sweep_expired_group_invites_use_case_test.dart` (NEW)**
1. Seed in-memory repo with 1 expired + 1 valid pending, 1 expired + 1 valid revocation, 1 expired consumed, 1 expired welcome-tombstone. `sweepExpiredGroupInvites(now)` deletes **only the 4 expired rows** and returns per-table counts; valid rows survive. RED (use-case absent). Harness: `in_memory_pending_group_invite_repository.dart:89/101/113` already implements `deleteExpired*`.
2. Assert `GROUP_INVITE_SWEEP_START` / `GROUP_INVITE_SWEEP_SUCCESS` emitted with `deletedCounts`. RED (no such event).

**`test/main_startup` wiring-lock** (mirror 120-style source-text tests) — assert `lib/main.dart` contains a **startup unawaited** `sweepExpiredGroupInvites(...).catchError(...)` **and** a **resume await**, adjacent to the `sweepExpiredPosts` calls (`main.dart:3073` / `:4177`). RED.

**`test/features/groups/presentation/screens/group_list_screen_test.dart`** (or widget on `group_list_wired`)
3. Given `pendingInvites` containing one invite whose `groupId` is already in the joined-groups list, assert that card is **NOT** rendered (B2 materialized filter). RED — screen renders all invites today.
4. NEGATIVE guard — an **expired-but-not-materialized** invite **STILL** renders (as the expired chip with Decline enabled). RED if implementer over-filters. **Mandatory** — locks that B2 does not strip the dismiss affordance.

**`feed_wired` badge consistency** — badge count equals the number of rendered (post-filter) invites, not raw `getPendingInvites().length` (`:661`). RED if badge keeps raw length.

### GREEN implementation
**B1 — new use-case `lib/features/groups/application/sweep_expired_group_invites_use_case.dart`** (mirror `sweep_expired_posts_use_case.dart`):
```dart
Future<GroupInviteSweepResult> sweepExpiredGroupInvites({
  required PendingGroupInviteRepository repo,
  DateTime Function()? now,
}) async {
  final t = (now ?? () => DateTime.now().toUtc())();
  emitFlowEvent(layer:'FL', event:'GROUP_INVITE_SWEEP_START',
                details:{'cutoff': t.toUtc().toIso8601String()});
  try {
    final pending    = await repo.deleteExpiredPendingInvites(t);
    final revoked    = await repo.deleteExpiredRevokedInvites(t);
    final consumed   = await repo.deleteExpiredConsumedInvites(t);
    final tombstones = await repo.deleteExpiredWelcomeKeyPackageTombstones(t);
    emitFlowEvent(layer:'FL', event:'GROUP_INVITE_SWEEP_SUCCESS',
      details:{'pending':pending,'revoked':revoked,'consumed':consumed,'tombstones':tombstones});
    return GroupInviteSweepResult(pending,revoked,consumed,tombstones);
  } catch (e) {
    emitFlowEvent(layer:'FL', event:'GROUP_INVITE_SWEEP_ERROR', details:{'error':e.toString()});
    rethrow;
  }
}
```
**Wiring in `lib/main.dart`:**
- **Startup** — directly after the `sweepExpiredPosts` unawaited block (after `main.dart:3073`):
  `unawaited(sweepExpiredGroupInvites(repo: <pendingInviteRepo handle from :1242/:1267>).catchError((e,st){ emitFlowEvent(layer:'FL', event:'GROUP_INVITE_SWEEP_STARTUP_ERROR', details:{'error':e.toString()}); return GroupInviteSweepResult.empty; }));` Capture the `PendingGroupInviteRepositoryImpl` instance constructed at `:1267-1274` in a local and reuse it (already passed to the invite listener).
- **Resume** — after the existing `sweepExpiredPosts` await at `main.dart:4177`, add `await sweepExpiredGroupInvites(repo: widget.<pendingInviteRepo>);` inside the same try, **placed LAST** in `_onResumed` (before the finally) so it never races accept-recovery/drain.

**B2 — filter in the 3 UI loaders** (keep repo dependency-free):
- `group_list_wired.dart:195-201` `_loadPendingInvites`: after `getPendingInvites()`, drop invites whose `groupId` is in the already-loaded joined groups (`_groups`): `invites.where((i) => !_joinedGroupIds.contains(i.groupId)).toList()`. **Do NOT drop expired-unaccepted** (leave the expired chip).
- `orbit_wired.dart:570-593` `_loadPendingGroupInvites`: same filter against `_activeGroups`.
- `feed_wired.dart:661`: compute the badge from the **same** filtered list.

### Gotchas / invariants
- **Resume ordering**: sweep MUST run after accept-recovery retriers + inbox drains (7-day TTL vs seconds-scale recovery; place last). Do NOT couple to drain.
- **B2 must filter on materialization, not expiry** — filtering on expiry would silently vanish expired chips and **remove the user's explicit Decline/dismiss affordance** (`card:140/:28-33`). The negative guard test (#4) enforces this.
- B1 already deletes expired rows at the data layer → the card disappears on next reload, so B1 substantially covers the "expired invite lingers" symptom without B2 needing an expiry filter.
- **B2's materialized-orphan target is rare**: the primary `bridgeError` accept path calls `_rollbackIncompleteAcceptedInviteState` (un-materializes the group) then retains the invite (`accept_…:339-345`); success consumes the row (`_commitAcceptedPendingInvite`). A live group with a surviving invite row is a partial-accept corner. B2 is low-value once B1 lands — but cheap and the negative guard protects against regressions.
- **Badge drift**: badge + render projection must use the identical filtered list.
- **Sweep all 4 tables in one use-case** — revoked/consumed/welcome-tombstone tables have **no other GC** and grow unbounded; this is their only reaper.
- B touches no membership-freshness gate, no `group_message_listener`, no watermark, no peer transport — fully independent of C/D/E/F.

### Gates
new use-case test (RED-listed) · `main.dart` wiring-lock test · screen widget test (materialized hidden / expired-non-materialized still renders) · feed badge consistency · `flutter analyze` 0 new · no migration.

---

## 6. SLICE 3 — E: Mark "joining…" + bound the half-materialized state

**Preferred path: NO migration** — derive the badge from the existing 088 `group_rejoin_state` table; stamp `dbRecordGroupRejoinFailure` at the failure site. Dart-only.

> Recon's "next-free 089" is moot here — the preferred path adds no migration. If a literal `groups.join_state` column is *mandated* against advice, it is **`090`** (not 089), and must be written only from the two paths that mutate `group_rejoin_state`.

### What is already done (do NOT rebuild)
- The bounded-retry loop itself (088 `group_rejoin_state` + `rejoin_group_topics_use_case.dart`: skip dissolved/no-key, exponential backoff base 30s ×2 cap 30min, `GROUP_REJOIN_PERMANENTLY_STUCK` at attempt≥10).
- The accept-layer `bridgeError` verdict (`8ba68cd7`).
- **Live delivery recovery already works**: a half-materialized group has a key (persisted `:953` before the join call), is non-dissolved, has no rejoin row → it falls through all three skip-guards and **is attempted every rejoin pass**. So the open part is purely the *marker/UI/give-up-UX*, **not lost delivery**.

### Open residual
The three non-rollback catch branches return `bridgeError` **without enrolling the group in the bounded retrier** — grep-confirmed neither `handle_incoming` nor `accept_pending` calls `recordGroupRejoinFailure`. So the half-materialized group is only swept up incidentally on the next independent rejoin pass. Stamping it at the failure site is the load-bearing work.

### RED tests
**`test/features/groups/application/handle_incoming_group_invite_use_case_test.dart`**
1. materialize; on join `callGroupJoinWithConfig` throws a **non-repairable** `BridgeCommandException` (errorCode e.g. `'TOPIC_SUBSCRIBE_FAILED'`, not in allowlist) → assert group still exists (`getGroup != null`) **AND** a `group_rejoin_state` row is queued (`dbRecordGroupRejoinFailure` called). RED: persists with no enrollment.
2. materialize; `TimeoutException` → returns `bridgeError` **AND** group enrolled in rejoin state. RED.
3. materialize; generic `Exception` → enrolled. RED.
4. **REGRESSION GUARD (stays GREEN)** — a repairable error (`STALE_JOIN_MATERIAL`) still **fully rolls back** (`getGroup == null`, `removeAllKeys/removeAllMembers` called) and returns `invalidPayload`. **Mandatory** — proves the enrollment path does not swallow the existing repairable rollback (`:990-1006`).

**`test/features/groups/application/rejoin_group_topics_use_case_test.dart`**
5. an enrolled/half-materialized group whose rejoin **succeeds** clears the row to joined (extends existing `clearGroupRejoinState :216` coverage).
6. an enrolled group with **no key** is skipped (`skippedNoKey`) and the row is **NOT** falsely cleared (guards against false "joined"). *(Note: this case is rare for the join-failure path — key is persisted before the join call — but locks the skip semantics.)*
7. at attempt≥`_maxRejoinAttempts` the group is reported `PERMANENTLY_STUCK` and (per give-up policy) surfaced as "couldn't join" but **NOT hard-deleted** — assert `getGroup != null` **and key still present** after give-up. **Guards HOLE-3.**

**Widget `group_list_wired_test.dart` / `orbit_wired_test.dart`**
8. a group with a `group_rejoin_state` row renders a "Joining…" (attempt<10) or "Couldn't join — retry" (attempt≥10) affordance, distinct from a normal joined group and from a dissolved group. RED — no such UI.

### GREEN implementation (preferred — no migration)
1. **`handle_incoming_group_invite_use_case.dart` catch branches** — at `:1013` (TimeoutException), `:1025` (generic), and the **transient subset** of `:1007` (non-repairable BridgeCommandException): before returning `(bridgeError, groupId)`, call `groupRepo.recordGroupRejoinFailure(groupId, nextEligibleAt: now + base)` (same upsert `rejoinGroupTopics` uses at `:245`). Reuses the existing bound (attempt 10 → `PERMANENTLY_STUCK`), **zero new schema**. Keep the repairable-allowlist rollback (`:990-1006`) exactly as-is.
   - **Policy on the truly-fatal `:1007` case (HOLE-5):** if a non-repairable, non-timeout BridgeCommandException is provably fatal/malformed-config, prefer **rollback** (mirror `:991`) over enrollment — retrying a permanent error 10× then sitting stuck forever is wrong. Only timeout + transient → enroll.
2. **Derived badge (no `GroupModel` field):** in `group_list_wired`/`orbit_wired`, after loading groups also load `groupRepo.loadGroupRejoinStates()` (already exposed, used at `rejoin_…:116`) and badge any group whose id is in that map: "Joining…" (attempt < cap) / "Couldn't join — retry" (attempt ≥ `_maxRejoinAttempts`). l10n keys mirror existing `group_invite_accept_failed`.
3. **Auto-resolve:** `rejoinGroupTopics` already clears the row on success (`:216`) and skips no-key/dissolved without clearing → the derived badge resolves to joined the moment a rejoin succeeds; a no-key group correctly stays badged.
4. **Give-up UX:** consume the existing `GROUP_REJOIN_PERMANENTLY_STUCK` (`:250`) — surface a manual "Retry now" (force `next_eligible_at=now`) + an explicit "Leave group" (existing leave path). **Do NOT auto-delete** (HOLE-3 — the row holds the key + drained inbox; the member is legitimately in the group server-side).
5. **accept wrapper:** leave existing rollback gates (`:339-346`, `:411-419`) untouched; ensure that when it keeps a half-materialized group and returns `bridgeError` (`:446`), a rejoin-state row exists (it will, if step 1 stamped it in materialize) so the badge + retrier engage.

**Fallback (only if a literal column is mandated):** migration **`090`** adds nullable `groups.join_state` default `'joined'`; write it **only** from the two paths that mutate `group_rejoin_state`; `GroupModel` adds `joinState` via the `_sentinel` copyWith idiom (`:237/:279`); update `GroupRepository`/Impl/`in_memory_group_repository` fake + `full_migration_chain_test`. Strictly more code + drift risk for no behavioral gain — discouraged.

### Gotchas / invariants
- **HOLE-1 (drift):** a second source of truth (a `join_state` column) will drift from the sparse 088 table. Deriving from `group_rejoin_state` is the canonical signal — do NOT add a parallel column.
- **HOLE-3 (auto-delete hazard):** never hard-delete at give-up; keep the key + drained inbox; offer manual retry/leave only.
- **HOLE-5 (transient vs fatal):** split transient→enroll from fatal→rollback; don't collapse all three catch branches into one bucket.
- **No-key skip (`:152`)** must distinguish "skipped (still pending key)" from "joined" so a key-less group isn't falsely cleared.
- **Self-heal needs no inviter** — `rejoinGroupTopics` rebuilds config from stored members (`:200-202`) and calls `callGroupJoinWithConfig` locally; recovery is purely local/relay-pubsub.
- Badge must not conflate with the unfiltered `getPendingInvites` surfaces already showing stale invites on the same lists (handled by Slice 2 B2 filter); attempt-count drives "Joining…" vs "Couldn't join".
- `isDissolved` is independent — no collision.

### Gates
4 use-case tests + 3 rejoin tests + 2 widget tests · regression guard (#4) green · `flutter analyze` 0 new · **no migration** (preferred path).

---

## 7. SLICE 4 — C: Wire invite revocation into the admin UI

**Migration `090` MANDATORY** (refute corrected the review's "no migration" on two grounds). Receiver path already live; send side genuinely unwired.

> **HOLE-4 (FATAL if shipped without it):** the receiver deletes the live pending invite **only when `pending.inviteId == payload.inviteId`** (`handle_incoming_…:435`). `sendGroupInvite` mints a fresh `uuid.v4` per call (`send_group_invite_use_case.dart:207`), persisted **nowhere per-peer**; `resendGroupInvite` mints anew. `GroupInviteDeliveryAttempt` carries **no `inviteId`** (`:48-54`). Without persisting `invite_id` on the attempt row, revocation saves the receiver tombstone but **never deletes the live invite → false "revoked" + recipient can still accept (silent auth hole)**.

### RED tests
**`test/features/groups/domain/models/group_invite_delivery_attempt_test.dart`**
1. `expect(GroupInviteDeliveryStatus.revoked.toValue(),'revoked')` and `fromValue('revoked')==revoked`. RED.
2. `expect(fromValue('some_future_value'), unknown)`. RED today (`default:` throws `:42`) — locks the hardening.

**`test/features/groups/domain/repositories/group_invite_delivery_attempt_repository_impl_test.dart`**
3. `markRevoked` then `getAttempt().status==revoked` + `lastError` cleared. RED.
4. persisting `'revoked'` does **not** throw the 067 CHECK constraint. **Forces migration `090`.**

**`test/core/database/integration/full_migration_chain_test.dart`** — v90 chain runs; `group_invite_delivery_attempts` accepts a `revoked` row + an `invite_id` value.

**`test/features/groups/presentation/group_info_screen_test.dart`**
5. admin + member status `sent`/`queued`/`needsResend` → key `group-member-revoke-invite-<peerId>` present + tappable; negative for `joined`/`unknown`/non-admins. RED.

**`test/features/groups/presentation/group_info_wired_test.dart`**
6. spy `P2PService.sendMessage`+`storeInInbox` + fake attempt repo; tap revoke → assert revocation envelope sent (direct OR inbox) **AND** `markRevoked` called **AND** `_loadGroupInfo` reload **AND** revoke snackbar. RED.
7. assert the `inviteId` passed to `sendGroupInviteRevocation` is non-empty/correct — **forces HOLE-4 surfacing**.

**`test/features/groups/presentation/group_invite_status_presentation_test.dart`** — `groupInviteStatusLabel(l10n, revoked)` returns a localized label, no switch crash. RED (exhaustive switch fails to compile until added).

### GREEN implementation
1. **Migration `090`** (`lib/core/database/migrations/090_group_invite_delivery_attempts_revoked_declined.dart`) — rebuild `group_invite_delivery_attempts`: `CHECK(status IN ('sent','queued','needs_resend','cannot_send','joined','revoked','declined'))` **+ add `invite_id TEXT`** column (copy rows, swap table, recreate the two indexes from `067:24-32`). Bump `currentIdentityDatabaseVersion = 90`. *(Fold F's `declined` into this same rebuild — see §3.)*
2. **Plumb `invite_id` capture** into the send/resend recording path (`record_group_invite_delivery_attempts` + `sendGroupInvite`/`resend`) so the attempt row carries the `inviteId` the receiver matches on.
3. **Enum** (`group_invite_delivery_attempt.dart`) — add `revoked` after `joined` (`:6`); `toValue` case → `'revoked'`; `fromValue` case `'revoked'→revoked`; **change `default: throw` to `default: return unknown`** (`:42`).
4. **Repo** — add `markRevoked({required groupId, required peerId, DateTime? revokedAt})` to iface (`:29` area) + impl mirroring `markJoined` (`:131-162`): load existing, `copyWith(status: revoked, updatedAt, clearLastError:true)` via `saveAttempt`.
5. **Mapper** — `case revoked → l10n.invite_status_revoked` (`group_invite_status_presentation.dart:8-21`) + ARB.
6. **Callback plumbing** — add `onRevokeInvite` to `GroupInfoScreen` and `GroupMemberRow` (parallel to `onResendInvite`), rendering `TextButton` key `group-member-revoke-invite-<peerId>` beside resend (`:99-110`); **gate in screen** (gate must be authored fresh — resend gates only on `==needsResend`, `:551-560`) on `!isDissolved && isAdmin && !isSelf && onRevokeInvite!=null && status in {sent,queued,needsResend}`.
7. **`_onRevokeInvite` handler** in `group_info_wired.dart` mirroring `_onResendInvite` (`:2016-2081`): new `Set _revokingInvitePeerIds` guard; load identity; recipient via `member.mlKemPublicKey` (`:83`) + `member.peerId`; groupConfig via `_buildGroupConfig(_group,_members)` (`:2150-2155`); call `sendGroupInviteRevocation(p2pService:..., bridge:..., inviteId: <persisted invite_id>, groupId:_group.id, recipientPeerId: member.peerId, recipientMlKemPublicKey: member.mlKemPublicKey, senderPeerId:_ownPeerId, senderPublicKey:..., senderPrivateKey:..., groupConfig:...)`; on success `widget.inviteDeliveryAttemptRepo!.markRevoked(...)`; `await _loadGroupInfo()`; revoke snackbar.
8. **`build()`** (`:2143` area) — `onRevokeInvite: canManageGroup && widget.inviteDeliveryAttemptRepo != null ? _onRevokeInvite : null`.
9. **DROP** the review's `revokePendingGroupInvite` local-tombstone call for the sender — it operates on the **receiver's** invite store (keyed by `groupId`, written only via `storeIncomingPendingGroupInvite`); for an admin who *sent*, it's `notFound` or wrongly tombstones the admin's own received invite. Dropping it also avoids 7-site `PendingGroupInviteRepository` threading.

### Gotchas / invariants
- **HOLE-4** is non-negotiable: without persisted `invite_id`, revocation is a false-success auth hole. Migration column + capture plumbing are part of the floor.
- **`fromValue` default throws (`:42`)** and `getAttemptsForGroup` maps **every** row (`impl:80-81`) — a `revoked` row written by a newer build and read by an older enum **crashes the group-info load**. Enum + migration + read must land atomically (or default-to-unknown hardening ships first / write gated behind a build floor).
- **Admin gate mandatory** — without it non-admins emit sends the receiver rejects (`isRevokerAuthorizedBySignedSnapshot`) wastefully, and the local row may flip `revoked` while the receiver ignores it.
- **Best-effort honesty**: a malicious responder that never deletes its pending invite is undetectable by the sender (no revoke-ack) — same caveat as resend; document it. Offline recipient is covered (`storeInInbox` fallback `:242`).
- **Interaction with B**: `getPendingInvites` is unfiltered — a `revoked` status surfaced there could re-surface a revoked invite. Verify B-vs-C interaction before shipping.
- Send inputs already reachable in `group_info_wired` (`member.mlKemPublicKey`, identity keys, `_buildGroupConfig`, `p2pService`, `bridge`) — mirrors `resend_group_invite_use_case.dart:88-102`.

### Gates
enum + repo + mapper + screen + wired tests · `full_migration_chain_test` v90 · `flutter analyze` 0 new (exhaustive switches force both mapper + member-row) · **migration `090`** (re-check free at landing).

---

## 8. SLICE 5 — F: Decline acknowledgement to the inviter

**Migration `090` MANDATORY** (CHECK rebuild — fold into C's `090` if C lands first; else F's `090` adds `declined` and C bumps to `091`). Pure Dart + SQL; no Go.

### RED tests
**`test/features/groups/application/decline_pending_group_invite_use_case_test.dart`**
1. given injected `p2pService`/`bridge` + inviter mlkem, `declinePendingGroupInvite` sends a `group_invite_decline_ack` envelope to `invite.senderPeerId` (direct OR inbox) **AND** still records tombstone + `deletePendingInvite` (no regression). Mirror revocation send-then-inbox-fallback.
2. when inviter ML-KEM key is null/unavailable → decline still **succeeds locally** and does **not throw** (best-effort no-send), emitting `DECLINE_ACK_ENCRYPTION_SKIPPED`.

**`test/features/groups/application/handle_incoming_group_invite_decline_ack_test.dart` (NEW)**
3. a valid signed decline-ack from member X for group G calls `deliveryRepo.markDeclined(groupId:G, peerId:X)`; a **spoofed** ack where `message.from != signed declining peer` is **REJECTED** (no `markDeclined`). **Mirrors revocation `revokedByPeerId==message.from` guard.**

**`group_invite_listener` routing** — a `group_invite_decline_ack` message reaches the decline-ack branch (mirror the `isRevocation` branch); a non-ack invite still flows to `storeIncomingPendingGroupInvite`.

**`group_invite_delivery_attempt_repository_test.dart`** — `markDeclined` upserts `status='declined'`; `fromValue('declined')==declined`; persisting `'declined'` does **not** throw the 067 CHECK. **Forces migration.**

**`full_migration_chain_test.dart`** — v90 chain accepts a `declined` row.

**presentation** — `groupInviteStatusLabel(declined)==l10n.invite_status_declined`; `group_member_row` `_color(declined)` defined (compile-forced by exhaustive switch).

### GREEN implementation
1. **Migration** — if C has not landed, add `declined` to the CHECK in `090` (rebuild table); if C's `090` already expanded the CHECK to include `declined`, **no migration here** (only enum + `markDeclined`). See §3.
2. **Enum** — add `declined` to `GroupInviteDeliveryStatus` + `toValue`/`fromValue` (`:9-44`); (default-to-unknown already done by C, else do it here).
3. **Repo** — `markDeclined({groupId, peerId, declinedAt})` iface + impl mirroring `markJoined` (`:131-162`), `status=declined`, `clearLastError:true`, keyed on `(groupId, declining peerId)`.
4. **Send** — new `GroupInviteDeclineAckPayload` (mirror `group_invite_revocation_payload.dart`: canonical signed payload + `buildEncryptedEnvelope` type `'group_invite_decline_ack'`) + `sendGroupInviteDeclineAck` mirroring `sendGroupInviteRevocation` (`:68-265`): sign (`callSignPayload`), encrypt to inviter mlkem (`callEncryptMessage`), `p2pService.sendMessage:224` → `storeInInbox:242` fallback. Call **best-effort from `declinePendingGroupInvite` AFTER the local tombstone/delete (`:37`)**, guarded by `mlkem != null`, never throwing. Thread `p2pService`/`bridge`/own keys/inviter mlkem into the use case + both call sites (`orbit_wired.dart:1255`, `group_list_wired.dart:466`).
5. **Route** — add `case 'group_invite_decline_ack'` in `incoming_message_router.dart` (after the revocation case) → `_groupInviteController`.
6. **Receive** — in `group_invite_listener.dart._onMessage` (after the `isRevocation` block `:176-205`) add an `isDeclineAck` branch: parse, verify signature + `message.from == signed declining peer`, then `deliveryRepo.markDeclined(groupId, peerId:message.from)`. **Thread `GroupInviteDeliveryAttemptRepository` into the `GroupInviteListener` ctor (`:46-63`) and wire at `main.dart:2561` from `groupInviteDeliveryAttemptRepository` (`main.dart:1277`)** — the ctor currently has no delivery repo (verified).
7. **Inviter-mlkem capture** — persist the inviter ML-KEM public key when storing the incoming invite (`storeIncomingPendingGroupInvite` / `pending_group_invite` payload) so **non-contact** inviters are reachable (invites can come from non-contacts; `contactRepo.getContact(senderPeerId)?.mlKemPublicKey` may be null).
8. **Presentation** — add `invite_status_declined` l10n + cases in `group_invite_status_presentation.dart:8-21` and `group_member_row.dart:228-248`.

### Gotchas / invariants
- **Privacy**: a decline-ack reveals the user declined. Send MUST be fire-and-forget, never block the local tombstone/delete, and **should be gated behind a privacy setting** (preserve review's privacy note). *(If product wants this off-by-default, the setting gate is part of the slice — see Deferred §9.)*
- **Spoof guard mandatory** — without `message.from == signed declining peer`, any peer can mark another member declined.
- **`markDeclined` vs `joined` race** (decline-then-rejoin) — define precedence (**joined wins / monotonic**) or the inviter view regresses. The review did not specify; this plan mandates joined-wins.
- **Forward-compat**: older inviter builds receiving `group_invite_decline_ack` must hit the router default/unknown branch as a graceful no-op (no worse than today's stale "sent"). Cross-version: if older senders omit inviter mlkem, decliners on new builds degrade to `DECLINE_ACK_ENCRYPTION_SKIPPED`, never block.
- The decliner is a **pending invitee, not a roster member** — it can never emit the GossipSub member-event the inviter's `markJoined` consumes; a direct 1:1 envelope is the only viable channel (structurally independent of reviews 07/10/12).

### Gates
use-case + receive + routing + repo + presentation tests · `full_migration_chain_test` v90 · `flutter analyze` 0 new · migration coordinated with C.

---

## 9. SLICE 6 — D: On-join authoritative-metadata resync (pull)

**New wire pair (the only finding with new wire surface). Flag-gated. NO migration** (reuses `lastMetadataEventAt`). Ships **last** — security-relevant authenticity gate + the first receive-side metadata applier.

> **Refute escalation (read first):** the verify verdict's premise *"live (already-joined) members DO converge"* is **unverified-to-FALSE in source**: `extractGroupMetadataActorEventVerificationData` (`group_config_payload.dart:479`) is **defined but never consumed** anywhere in lib/; `handleIncomingGroupMessage` parses `__sys` only as a guard and **never applies** `groupConfig` name/avatar/`lastMetadataEventAt`; the only receive reaction (`group_conversation_wired.dart:1361 → _refreshVisibleGroup()`) re-reads a DB row that was never updated. **There is no receive-side metadata applier at all.** So the defect is two-layered: (L1) no member converges name/desc/avatar on the live publish; (L2) the late joiner additionally has no point-in-time-independent way to obtain current metadata.
>
> **This plan scopes D to L2 (the join-time pull) and explicitly flags L1 as a separate decision** (see Deferred §10). Mis-scoping — assuming live convergence works and only adding the joiner pull — is the top risk: members would *still* show stale name/avatar after any admin edit.

### RED tests
**`test/features/groups/application/on_join_metadata_resync_test.dart` (NEW)**
1. member materialized with `metadataUpdatedAt=T1` (stale name/avatar); a **signed** `config:response` with `metadataUpdatedAt=T2>T1` (new name + new avatarBlobId) is applied → `groupRepo.getGroup` returns new name + `lastMetadataEventAt==T2` and `downloadGroupAvatarFn` invoked for the new blob. RED (no applier).
2. **strictly-newer idempotency** — local `lastMetadataEventAt=T2`; a `config:response` with `T1<T2` (or `==T2`) arrives → name/avatar/`lastMetadataEventAt` UNCHANGED, `downloadGroupAvatar` NOT re-called (mirror `inviteMetadataIsCurrent` `:965-968`).
3. **authenticity reject** — a `config:response` whose embedded actorEvent is **not validly admin-signed** (forged name/avatar from a non-admin member) → REJECTED, local metadata unchanged (verify via `extractGroupMetadataActorEventVerificationData` before apply).

**`test/features/groups/application/group_invite_listener_test.dart`** — a `config:request` envelope routes to the request handler (NOT `storeIncomingPendingGroupInvite`, NOT revocation); a `config:response` routes to the apply handler; no false-positive against existing invite + revocation envelopes (parse priority).

**`test/features/groups/application/accept_pending_group_invite_use_case_test.dart`** — accept returns success (`group != null`) → a `config:request` send is triggered **exactly once** (spy on transport), best-effort (does NOT fail accept if send fails / node not started).

**transport best-effort + offline** — `config:request` falls back to `storeInInbox` when direct `sendMessage` returns false; accept still returns success when undeliverable.

**stale-inviter echo no-op** — inviter responds with config no newer than the invite snapshot → requester applies nothing (documents the convergence-only-if-fresher limitation).

**flag gate** — flag OFF → no `config:request` emitted on accept; behavior identical to today.

### GREEN implementation
**No migration; DB stays v89.**

**WIRE** — define `const String groupConfigRequestType` / `groupConfigResponseType`; both ride the existing v2 encrypted envelope (reuse `GroupInviteRevocationPayload.buildEncryptedEnvelope` pattern `:207`, same sign+encrypt `:162/:193`). The `config:response` **inner body embeds the admin-signed metadata actorEvent** built by `buildSignedGroupMetadataActorEventEnvelope` (`group_config_payload.dart:466`).

**REQUEST** (new use case `sendGroupConfigRequest`) — mirror `sendGroupInviteRevocation` structure: sign canonical request, encrypt to inviter mlkem, `buildEncryptedEnvelope`, `sendMessage(inviterPeerId, env)` → `storeInInbox` fallback. Fire from `accept_pending_group_invite_use_case.dart` at each `group!=null` success return (`:367/:445/:567/:606`), **unawaited + try/catch best-effort, behind the new flag**, idempotent (once per accept).

**RESPONDER** (new handler from `group_invite_listener.dart:_onMessage`) — parse `config:request` → **verify requester is a current member** → load own authoritative group via `groupRepo.getGroup` + `buildGroupConfigPayload(group, members)` (same builder as `group_info_wired.dart:987/:1687`) → embed admin-signed actorEvent → reply via revocation-style transport. **Strongly recommend the responder source config from its OWN current authoritative state and stamp its `lastMetadataEventAt`** (prefer admin as responder, or weight by role) — a stale non-admin inviter echoing stale config is a silent no-op.

**APPLY** (new receive-side applier — **do NOT call `updateGroupMetadata`**, it throws for non-admins `:48-56` and under recovery `:33`) — parse `config:response` → verify embedded actorEvent via `extractGroupMetadataActorEventVerificationData` (`:479`) → read `response.metadataUpdatedAt` → fetch local group → apply **only if** `responseMetadataAt != null && (local.lastMetadataEventAt == null || responseMetadataAt.isAfter(local.lastMetadataEventAt))` (mirror strictly-newer at `:965-968`) → `group.copyWith(name, description, avatarBlobId, avatarMime, lastMetadataEventAt: responseMetadataAt)` → `groupRepo.updateGroup` → if avatar changed, `await (downloadGroupAvatarFn ?? downloadGroupAvatar)(...)` then persist `avatarPath` (reuse `:955-977`, keeping the `inviteMetadataIsCurrent` re-check to avoid clobbering concurrently-fresher local state).

**ROUTING** — in `group_invite_listener.dart:_onMessage` (`:141`), add the two discriminators **most-specific-first** (before the revocation check `:171`), then fall through to revocation, then `storeIncomingPendingGroupInvite` (`:215`). Keep parse priority deterministic.

**WIRING** — construct/thread the new request+response handlers where `GroupInviteListener` is built (`main.dart:2561`); thread `p2pService`, `bridge`, key getters (already on the listener: `getOwnMlKemSecretKey`/`getOwnPeerId`/`getOwnMlKemPublicKey`). **Flag** — no existing flag infra in `lib/features/groups/`; introduce a minimal `const` flag.

### Gotchas / invariants
- **Authenticity is security-relevant**: `config:response` is a metadata-mutation vector; `extractGroupMetadataActorEventVerificationData` is currently dead code — the applier MUST verify the admin-signed actorEvent **before** applying or any member spoofs name/avatar.
- **Best-effort only**: needs responder online + reachable + non-stale + admin-signed. Document that convergence happens only when *some reachable peer holds fresher metadata*. Add the stale-echo no-op test.
- **Members cannot reuse `updateGroupMetadata`** — a new member-side applier is mandatory; routing members through it crashes.
- **Strictly-newer apply preserves the `:962-972` avatar-download watermark invariant** (`lastMetadataEventAt` only moves forward).
- **Shared listener seam + transport with F** — coordinate the discriminator additions at `group_invite_listener.dart:171` to keep parse priority deterministic and avoid merge conflicts (D and F both add envelope types + both reuse the revocation transport).
- **Rate-limit/idempotency** — fire once per accept; no per-retry amplification.
- No collision with E's `group_rejoin_state` (088) — D touches no join state.

### Gates
applier + routing + accept-fire + authenticity + stale-echo + flag tests · `flutter analyze` 0 new · **no migration** · coordinate listener seam with F.

---

## 10. Deferred / dropped items

| Item | Disposition | Rationale |
|---|---|---|
| **A1** — TTL alignment to 7d | **DROP (already done)** | `groupInviteMembershipFreshnessTtl == Duration(days: 7)` (`group_invite_payload.dart:19`); card minted from same constant (`group_invite_auth.dart:129`); ceiling uses it (`:291-294`). git log: `invite_payload.dart`/`group_invite_auth.dart` untouched since `8ba68cd7` (106). No work. |
| **B2** — render-filter expired-but-unmaterialized invites | **DEFER / decline** | The card already disables expired Accept and keeps a working Decline (`pending_group_invite_card.dart:140`). Render-filtering them removes the user's dismiss affordance and leaves orphan DB rows; B1's sweep deletes them at the data layer so they vanish on next reload. Ship only the materialized-group filter. |
| **C** — local `revokePendingGroupInvite` tombstone for the sender | **DROP** | Operates on the **receiver's** invite store (keyed by `groupId`); for an admin who *sent* it is `notFound` or wrongly tombstones the admin's own received invite. `markRevoked` on the per-peer attempt row is the correct state. Dropping it avoids 7-site `PendingGroupInviteRepository` threading. |
| **D — L1** (verified live metadata applier on the GossipSub publish) | **DEFER (explicit decision required)** | The published actorEvent is built/broadcast but never verified/applied — *no member converges on the live publish*. This is a broader receive-path gap than the join-time pull. Scope D to **L2** (join-time pull) here; track L1 as a follow-up (add a verified applier in `handleIncomingGroupMessage`). The pull alone does not fix the general staleness. |
| **D** — push-notification alternative to the pull | **DROP (not in scope)** | The pull (request/response) is the chosen mechanism; a push-on-edit broadcast is L1's concern, deferred above. |
| **F** — decline-ack privacy setting default | **DEFER product decision** | Whether the ack is on/off by default is a product call (decline reveals the user declined). Implement the setting gate; default value to be confirmed. The send is fire-and-forget regardless. |
| **E** — literal `groups.join_state` column | **DROP (prefer derived)** | Drifts vs the 088 `group_rejoin_state` sparse table for no behavioral gain; derive the badge instead. Only revisit if a single-table query is a hard requirement (then `090`, not 089). |
| Reviews/commits claimed to "already fix" these | **Refuted** | `8ba68cd7` (106) touches Go bridge/node + docs + 9 lines of `accept_…` only — does not fix A2 collapse, B scheduler, C/F send, D pull, or E marker. `b63c19d5` (self-heal) is undecryptable-recovery. Reviews 07/04/10/12 touch convergence/notifications/reactions/multi-device — none wires invite GC, revoke UI, decline-ack, or metadata pull. No collisions. |

---

## 11. Cross-cutting invariants

1. **Invite authorization unchanged** — revoke (`buildGroupInviteRevokerAuthorizationSnapshot` + `isRevokerAuthorizedBySignedSnapshot`, `:124-189`) and the freshness proof remain the auth source of truth. UI buttons (C) add no bypass; admin-only gates mandatory.
2. **Watermark gate reuse, never weakened** — every metadata apply (D) and stale-invite decision (A2) moves `lastMetadataEventAt` **strictly forward** (`:965-968`); membership events keep `isStaleGroupMembershipEvent` (`group_membership_event_watermark.dart:48`). No path lowers a watermark.
3. **No false-success** — C without persisted `invite_id` is a false-revoke auth hole (HOLE-4); D applies only verified-admin-signed, strictly-newer config; E never reports `success` for a half-materialized group without enrolling it in the bounded retrier; F's ack is best-effort and the inviter view stays honest (joined-wins precedence).
4. **`fromValue` unknown-tolerance** — adding `revoked`/`declined` MUST change `fromValue` `default:` from `throw` to `return unknown` (`group_invite_delivery_attempt.dart:42`); a newer-written status read by an older enum must not crash the group-info load (`getAttemptsForGroup` maps every row, `impl:80-81`).
5. **No key re-grant / no destructive give-up** — E never hard-deletes a half-materialized group at give-up (it holds the decryption key + drained inbox; the member is legitimately in the group server-side). Repairable-error rollback (`:990-1006`) stays intact; transient → enroll, fatal → rollback.
6. **Spoof resistance** — D's `config:response` and F's `decline_ack` both verify the inner signature **and** `message.from == signed peer` (mirror revocation `:316`).
7. **Forward-compat** — new wire types (D request/response, F decline-ack) must hit older builds' router default/unknown branch as graceful no-ops; cross-version key gaps degrade to skip-events (`DECLINE_ACK_ENCRYPTION_SKIPPED`), never block local actions.
8. **Two-surface consistency** — A2/C/E badges must update BOTH `group_list_wired` and `orbit_wired` (relocated to `lib/features/orbit/...`); orbit's switch is hardcoded EN and its exhaustive switch flags missed cases at compile time.

---

## 12. Test & device matrix

### Unit / widget (host)
| Harness | Findings | Key new files |
|---|---|---|
| `accept_pending_group_invite_use_case_test.dart` | A2, D, E | expiredFreshness + telemetry + retry-isolation; config-request fire; half-materialized enrollment |
| `handle_incoming_group_invite_use_case_test.dart` | E | enrollment at 3 catch branches + repairable-rollback regression guard |
| `handle_incoming_group_invite_decline_ack_test.dart` (NEW) | F | signed ack + spoof reject |
| `on_join_metadata_resync_test.dart` (NEW) | D | apply / strictly-newer idempotency / authenticity reject |
| `sweep_expired_group_invites_use_case_test.dart` (NEW) | B | 4-table sweep + flow events |
| `rejoin_group_topics_use_case_test.dart` | E | clear-on-success / no-key-skip / give-up-no-delete |
| `group_invite_listener_test.dart` | D, F | routing discrimination (request/response/decline-ack vs invite/revocation) |
| `group_invite_delivery_attempt_test.dart` + `..._repository_impl_test.dart` | C, F | enum `revoked`/`declined`, `fromValue` unknown-tolerance, `markRevoked`/`markDeclined`, CHECK |
| `group_invite_status_presentation_test.dart` | C, F | mapper `revoked`/`declined` |
| `group_info_screen_test.dart` / `group_info_wired_test.dart` | C | revoke button gate + send + markRevoked + inviteId-non-empty (HOLE-4) |
| `group_list_wired_test.dart` / `orbit_wired_test.dart` / `group_list_screen_test.dart` | A2, B2, E | expiredFreshness mapping (both surfaces); materialized-filter + expired-still-renders; "Joining…" badge |
| `feed_wired` badge | B2 | filtered count parity |
| `full_migration_chain_test.dart` | C, F | v90 chain accepts `revoked`/`declined` + `invite_id` |
| `main.dart` source-text wiring-lock (120-style) | B, F | startup unawaited + resume await sweep; delivery-repo threaded into `GroupInviteListener` |

### Integration / device (two-device, relay-inbox-dependent)
The relay-transport paths (C revoke, D pull, F decline-ack) all use direct send → `storeInInbox` fallback and must be exercised on the **iPhone13 + Pixel6** real two-device rig (local relay setup per MEMORY `reference_local_relay_and_android_emulator_setup`):
- **C revoke:** admin (iPhone13) revokes an unaccepted invite while the invitee (Pixel6) is **offline** → invitee comes online, drains inbox, the live pending invite is deleted (HOLE-4 — confirm `invite_id` match) and can no longer be accepted; admin's member row reads `revoked`. Repeat with invitee **online** (direct send).
- **D pull:** invitee (Pixel6) accepts an invite minted with **stale** metadata; admin (iPhone13) had since changed name/avatar → after accept, the invitee pulls and converges to the new name/avatar; verify a **forged** response from a non-admin device is rejected. Confirm best-effort no-op when the responder is offline.
- **F decline-ack:** invitee (Pixel6) declines → admin (iPhone13) member row flips to `declined` (direct + offline-inbox paths); a decline-then-rejoin shows `joined` wins (no regression to `declined`).
- **E:** force a join-bridge failure (e.g. topic-subscribe failure) on Pixel6 → group shows "Joining…", self-heals to joined on next rejoin pass; at attempt-10 shows "Couldn't join — retry" and is **not** deleted (key retained).

---

## 13. Risk & rollout

| Slice | Risk | Mitigation |
|---|---|---|
| A2 | HOLE-2 (orbit surface missed) | exhaustive switch is compile-RED at both sites; widget test on orbit |
| A2 | HOLE-3 (dual parse path) | defensive special-case at `accept_…:111-121` or drop stale from `isSecurityFailure` |
| A2 | telemetry dashboards counting `INVALID_SIGNATURE` | stale moves to `EXPIRED_FRESHNESS`; document |
| B | resume race (just-expired row swept before recovery) | place sweep **last** in `_onResumed`; 7d TTL vs seconds recovery |
| B2 | over-filter expired → lose dismiss | negative guard test mandatory; filter on materialization only |
| C/F | **migration `090` collision** (E-fallback / cross-slice) | re-check free at landing; fold C+F CHECK into one `090`; second-to-land bumps |
| C | **HOLE-4 false-revoke (FATAL)** | `invite_id` column + capture plumbing are part of the floor; HOLE-4 RED test |
| C/F | older enum crash on newer status | `fromValue → unknown`; land enum+migration+read atomically or gate write behind build floor |
| C/F | spoofed revoke/decline | admin gate (C) + `message.from==signed peer` (F) |
| F | privacy leak (decline visible) | fire-and-forget; setting gate; never block local delete |
| E | auto-delete hazard at give-up | never hard-delete; manual retry/leave; HOLE-3 guard test |
| E | transient/fatal conflation | split transient→enroll vs fatal→rollback |
| **D** | **"live convergence works" false premise** | scope to L2 join-pull; defer L1 explicitly; do not claim general staleness fixed |
| D | metadata-spoof via response | verify admin-signed actorEvent before apply (the dead `extractGroupMetadataActorEventVerificationData`) |
| D/F | listener-seam merge conflict | coordinate discriminator priority (most-specific first) |

**Rollout order & floors:** A2 → B → E (no-migration quick wins, independent, shippable in parallel). Then C (migration `090` + HOLE-4 floor) → F (reuses C's `090` CHECK). Then D last (new wire + authenticity + flag; ship behind the flag OFF, enable after two-device verification). **Receiver-first not required** (all paths degrade gracefully on older builds), but D and C/F benefit from a build-floor before enabling so older readers don't see new statuses/wire types — D's flag and C/F's `fromValue→unknown` hardening cover this.

---

## 14. Effort

| Slice | Migration | Wire | New use-case/handler | UI surfaces | l10n | Est. |
|---|---|---|---|---|---|---|
| **A2** | — | — | branch split | 2 (group_list + orbit) | 1 key ×3 | **S** |
| **B** | — | — | 1 (sweep) + main wiring | 3 loaders + badge | badge reuse | **S–M** |
| **E** (derived) | — | — | failure-site stamp + badge derive + give-up UX | 2 badges | mirror existing | **M** |
| **C** | `090` (CHECK + `invite_id`) | — | `markRevoked` + handler + invite_id capture | screen+row+wired | 1 key ×3 | **M–L** |
| **F** | `090` (CHECK; shared w/ C) | new type | `markDeclined` + send + receive + key capture + ctor thread | row+mapper | 1 key ×3 | **M–L** |
| **D** | — | new pair | request + responder + applier + flag + ctor thread | none | none | **L** |

---

**Provenance:** Synthesized from the review-08 verify+refute workflow (6 findings A–F, RECON brief + per-finding verify and refute agents, all graph-confirmed-in-source via graphify-arch then verified in real files). **All review/recon line numbers were independently re-checked against the working tree on `124-harness-refactor` before inclusion; the two stale recon premises (DB v88→**actually v89, next-free 090**; nonexistent `_shouldIgnoreStaleMetadataEvent` gate) are corrected throughout.** Confirmed live in source during synthesis: `currentIdentityDatabaseVersion = 89` + `089_media_attachment_download_retry_column.dart` (→ next-free 090); `accept_…:169-182` collapse branch; `staleMembershipFreshness` sole producer `group_invite_payload.dart:854`; `067:10-16` CHECK (C/F migration mandatory); `088_group_rejoin_state` separate table; `GroupInviteListener` ctor lacks delivery repo; `sweepExpiredPosts` mirror at `main.dart:3073/4177`; `orbit_wired.dart` at `lib/features/orbit/presentation/screens/`; zero non-repo callers of the four `deleteExpired*` methods; config-pull surface absent.
