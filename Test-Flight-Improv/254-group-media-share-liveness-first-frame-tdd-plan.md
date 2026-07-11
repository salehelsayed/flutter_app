# 254 - Group Media Share Liveness And First-Frame Media  (Bug)

Status: accepted — implementation, causal mutation proof, required family gates, analyzer comparison, and independent QA complete
Type: Bug
Spec: free-text intent (no formal spec) — sibling of Plan 253, deferred by its review (`Test-Flight-Improv/253-review-fixlist.md` §D)
Classification: implemented / accepted
Closure tier: host

## Planning Progress
| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-07-10 21:05 CEST | Evidence Collector (4-agent verify→refute workflow `wf_1529ebbd-2fd` + orchestrator source reads) | send/group use case, group repo impl + event class, group_conversation_wired, coordinator group lane, letter_card render, retry lanes, migrations 010/v96-v99, gate scripts, shared fakes | Liveness gap CONFIRMED (exhaustive subscription sweep; self-echo refuted at three layers). Blank-frame window CONFIRMED with NO fill-in trigger. NEW: failed media sends lose media PERMANENTLY (failure funnels never persist attachments → retry lane skips forever). In-app composer/voice masked by optimistic path; in-app group media FORWARD reproduces the gap (same coordinator lane). | Design F1/F2/F3 fix; hazard audit |
| 2026-07-10 21:20 CEST | Planner | Hazard + census + inventory agent outputs, tier-matrix, sufficiency checklist | F1 (repo `.inserted` event) / F2 (early stamped attachment persist) / F3 (targeted UI upsert) survived the hazard audit; polling and coordinator-only pre-persist KILLED; terminal-time unknown-id fallback KILLED (surfaces only at completion + races post-terminal media persist). Two load-bearing conditions: F3 post-await unknown-recheck; burst coalescing. No coordinator file is edited → no 236/253 overlap. | Emit matrix + plan |
| 2026-07-10 21:35 CEST | Reviewer (sufficiency) | This plan vs `references/sufficiency-checklist.md` | Zero empty matrix cells; every fix mutation-verified; one intentional re-red named; blind-spot sweep rowed or justified; host-only closure justified (pure Dart eventing/ordering — no OS boundary, crypto, relay, or schema change). | Arbiter |
| 2026-07-10 21:35 CEST | Arbiter | — | Structurally complete; TC-254-06 is a new-invariant guard (documented as not-RED-on-HEAD, red against naive F3). Hand off to execution after user accepts. | hand off |
| 2026-07-10 22:20 CEST | Reviewer (external audit, applied) | handle_incoming_group_message_use_case.dart:660-710, group_conversation_wired.dart:3390-3464, retry_failed_group_messages_use_case.dart:225-284, send_group_message_use_case.dart:768-782/:1096-1110, git HEAD | All 5 required findings VERIFIED and applied: (1) F1 narrowed to `status == 'sending'` (sibling self-delivery rows are `isIncoming:false, status:'sent'` saved BEFORE their media :692-699/:705 — an unnarrowed inserted event races media and duplicates the listener's update; sibling-echo benefit claim WITHDRAWN); (2) TC-254-02/06 upgraded to an operation-order spy / held-row-save construction (bridge gate cannot discriminate media-before-row from media-after-row-before-bridge — save :1096, bridge :1103); (3) F3 donor corrected to `_applyMessageUpdate`→`_enqueueGroupMessageUpdate(markAsRead:false)` (:3390-3451) — `_refreshMessageWithHydratedMedia` (:2910) bypasses the 159 coalescer; TC-254-07 completer-armed, TC-254-08 asserts one coalesced flush + zero mark-read; (4) NEW TC-254-09 + F3 replay guard for the stale `_loadMessages` overwrite (:1402-1423 unconditional replace erases a mid-load inserted upsert); (5) TC-254-04 discriminator re-anchored on the recorded bridge send for the retried messageId (RETRY_…_START fires pre-validation :236; GROUP_SEND_MSG_USE_CASE_BEGIN has no messageId :774-779). Tree-state wording refreshed (HEAD b1d043eb3, 236 COMMITTED, target files clean); orphan residue reworded cumulatively-unbounded + owner assigned. | hand off to execution |

## Execution Progress
| Time | Phase | Files touched | Command/evidence | Decision/blocker | Next |
|---|---|---|---|---|---|
| 2026-07-10 | RED/GREEN implementation | Group repository, send use case, wired conversation, shared fake, focused tests, and `GROUP_TESTS` registration | Seven catalog REDs failed causally; implementation committed in `f243b2788`; direct repository/send/retry/integration/wired/coordinator suites passed. | Proceed to managed closure. |
| 2026-07-11 | Acceptance hardening | `external_share_group_media_liveness_test.dart`, `group_conversation_wired_test.dart` | `de0aabfd5` makes TC-254-06 hold the parent-row save while proving attachment durability and makes TC-254-09 preserve a real image/thumbnail through the stale-load race. All nine final causal tests pass. | Run mutation, broad-gate, analyzer, and independent QA closure. |
| 2026-07-11 | Managed closure | No production changes | All 11 mapped mutation cycles produced the expected causal REDs (13 logs), followed by exact restoration and nine-test GREEN. `groups` passed 1,926 Flutter tests plus Go bridge/node; `feature-host-all` passed all 731 commands; analyzer improved from 1,628 to 1,627 issues and all seven scoped informational lints predate Plan 254; `git diff --check` passed. Independent QA: `accepted`. | Close Plan 254. |

## Source Of Truth
- Spec / intent: inline below (chained from 253 review §D deferral, user-directed 2026-07-10)
- Gate definitions: scripts/run_test_gates.sh (script wins over prose)
- Discovery/registration: scripts/check_reliability_simulation_discovery.sh
- Numbering / index: Test-Flight-Improv/00-INDEX.md

## Session Classification
implemented / accepted

## Exact Problem Statement

An external OS share (and an in-app group-media **Forward**, which rides the same coordinator lane) that targets a group whose conversation screen is currently open produces a message that **never appears on that screen while it stays mounted**. The pre-persist save of a brand-new outgoing row emits nothing; the terminal status event is dropped because the UI ignores unknown message ids; the only reload-triggering event (`rowsChanged`) fires solely from retry/recovery lanes. The user who shares a photo "into" the group they are looking at sees nothing happen.

Two adjacent defects share the same root: (1) if any reload *does* land during the media-free DB window (lifecycle resume, or a `rowsChanged` from ANY group's retry lane — it carries `groupId=null` and passes the guard), a captionless share renders as a **timestamp-only bubble** with no later fill-in trigger of any kind; and (2) if the send fails terminally, the failure funnels never persist the attachments at all, so the failed captionless share renders timestamp-only **permanently**, exposes **no retry affordance** (media actions need `messageMedia.isNotEmpty`; text retry needs non-empty text), and the background retry lane **permanently skips it** with reason `missing_media_attachments` — the media is silently lost despite a durable, already-uploaded artifact having existed at send time.

What must improve: a group-targeted media share surfaces live (with its thumbnail) in an already-open conversation; a mid-send fresh mount renders media on its first loaded frame; a terminally-failed media send retains its attachments and stays retryable.
What must stay unchanged (→ preserved-green sentinels): in-app optimistic composer/voice display; status-in-place updates with no page reload (GFR-003); cross-group event filtering; rowsChanged→reload; unmount cancellation; TC-159-11 media-resolve skip; all six "rejects … before persistence" validation pins; WU-3 pre-persist-before-bridge; stale-upload_pending reconciliation; 210b queuedOffline UX; coordinator group text-share contracts; incoming-emits-nothing and same-status-emits-nothing repo semantics.

## Root Cause (verify → refute confirmed)

Chain, each link verified in current source and survived adversarial refutation:

1. **New-row saves are silent.** `GroupMessageRepositoryImpl.saveMessage` (`group_message_repository_impl.dart:297-312`) → `_emitOutgoingStatusChangeIfNeeded` (`:153-166`) returns early when `previous == null`: the `sendGroupMessage` pre-persist (`send_group_message_use_case.dart:1096`) emits **nothing** on `outgoingLocalMessageChanges`.
2. **Terminal events are dropped for unknown ids.** Terminal funnels emit `.status` (saves `:1186`, `:1286`; `updateMessageStatus` emits at repo `:444-450`), but the sole consumer's handler (`group_conversation_wired.dart:1666-1685`) routes to `_updateLocalMessageStatus` (`:3721-3723`) which returns when `idx < 0`. `rowsChanged` (reload) fires only from 5 count-gated retry/recovery methods (repo `:257,:265,:274,:283,:292`).
3. **No other surface exists.** Exhaustive subscription sweep of the wired screen (initState `:508-570`; no `didChangeDependencies`, no RouteAware): media-upload progress (`:561-563`, counters only), `groupMessageStream` (`:1588-1622`, fed exclusively by `bridge.onGroupMessageReceived`, `main.dart:2476-2480`), group-removed, reactions, recorder, lifecycle observer. All `_loadMessages` call sites (`:565,:794,:848,:1464,:1676,:1702,:5428`) — none fires on share-picker pop. **Self-echo refuted at three layers**: recipient set excludes sender (`send_group_message_use_case.dart:122`); durable inbox recipients exclude sender by default (`:138-158`, `:743`); Go pubsub drops self-origin envelopes (`go-mknoon/node/pubsub.go:1676-1678`).
4. **The media-free window is structural.** `GroupMessage.media` is in-memory only (`group_message.dart:76-77,:119`; absent from `toMap`/`fromMap` `:128-190`); attachments are stamped with `resolvedMessageId` and persisted **only** in terminal funnels (`:1187-1194,:1287-1294,:1423-1430,:1502,:1567`). In-window `_loadMessages` (`:1402-1453` → `_loadResolvedMediaMap :2953-2975`) finds no rows; `buildGroupDisplayItems` does not filter empty-text messages (`group_conversation_screen.dart:1270-1329`); `LetterCard` renders the media grid only when media is non-empty and body text only when non-empty (`letter_card.dart:409,:437`) → timestamp-only bubble. **No fill-in exists**: the attachment repo has no change stream; `_shouldRecoverVisibleAttachment` (`:3360-3368`) never recovers a later-saved `'done'` row.
5. **Failure funnels never persist media.** `:1236-1256` and `:1262-1277` skip `_persistOutgoingMedia` entirely; `retry_failed_group_messages_use_case.dart:333-363` then skips the row with `missing_media_attachments` forever.

Refuted / do-NOT-re-introduce:
- **"Own message echoes back via the group message stream"** — refuted at three layers (link 3). Do not build the fix on incoming-stream delivery of own sends.
- **"Plan 236 / the dirty tree already fixes this"** — `deliverGroupMediaForward` routes into the same coordinator group lane; 236 adds source/destination gates, not surfacing. The in-app Forward overlay (`group_conversation_wired.dart:4885-4933` → picker → coordinator) **reproduces** the gap in-app.
- **"GroupMessage has no media field"** (earlier working assumption) — it HAS an in-memory `media` field (`group_message.dart:76-77`); only the DB row is media-free. F3 must populate **both** `message.media` and `_mediaMap` (the existing `_refreshMessageWithHydratedMedia` primitive already does exactly this, `group_conversation_wired.dart:2910-2926`).
- **Alternative fixes killed by the hazard audit**: UI polling (cost, still racy); coordinator-only pre-persist (leaves every other future caller broken; duplicates in-app logic); unknown-id fallback inside `_updateLocalMessageStatus` (surfaces only at send COMPLETION — seconds late, invisible for hung sends — and races the post-terminal media persist at `:1286→:1287-1294`).
- **`_refreshMessageWithHydratedMedia` as the F3 donor** (this plan's own first draft) — refuted by audit: it calls `setState`/`_upsertMessage` directly (`:2910-2926`) and bypasses the 159 coalescer; the correct donor is `_applyMessageUpdate` → `_enqueueGroupMessageUpdate` (`:3390-3451`).
- **"Sibling-device echoes of your own sends now surface live" as a free benefit** (this plan's own first draft) — WITHDRAWN: sibling self-delivery rows are saved BEFORE their media (`handle_incoming_group_message_use_case.dart:699` vs `:705`), so surfacing them from an inserted event would race media hydration and duplicate the listener's own update. The `status == 'sending'` gate excludes them by design; live sibling-echo surfacing needs its own designed slice.

## Real Scope

In scope (three edits, no coordinator/share file touched):
- **F1** — new `GroupOutgoingLocalMessageChange.inserted(groupId, messageId)` variant (`group_message_repository.dart:224-243`), emitted by `GroupMessageRepositoryImpl.saveMessage` when `previous == null && !message.isIncoming && message.status == 'sending'` (`group_message_repository_impl.dart:153-166,:297-312`); lockstep emit in the shared fake (`test/shared/fakes/in_memory_group_message_repository.dart:50-83`). The `'sending'` gate is load-bearing: sibling-device self-delivery rows arrive `isIncoming:false, status:'sent'` and are saved BEFORE their media (`handle_incoming_group_message_use_case.dart:692-693,:699,:705`), and system-publish retryable timeline rows are saved `status:'sent'` — an unnarrowed event would race their media persistence and duplicate the listener's own update path. Only the local pre-persist (`'sending'`) is eligible.
- **F2** — in `sendGroupMessage`, persist the stamped attachments (`groupMediaAttachments.map(copyWith(messageId: resolvedMessageId))` via the existing `_persistOutgoingMedia :534-574`) **immediately before** the pre-persist `saveMessage` at `:1096` — i.e. after ALL validation/auth/id-resolution (`:848,:935`, pinned by 8 existing tests). Terminal-funnel persists stay (verified idempotent merge-upsert; reconciliation `:548-566` cannot misfire at any of the 6 callers). Use the plain unguarded `saveAttachment` — `saveGroupAttachmentGuarded` refuses parentless saves by design (`media_attachments_db_helpers.dart:245-253`).
- **F3** — in `_handleOutgoingLocalMessageChange` (`group_conversation_wired.dart:1666-1685`): on an `inserted` event for this group whose id is NOT in `_messages`, run a dedicated inserted-hydrator modeled on `_applyMessageUpdate` (`:3390-3421`): pre-check unknown → fetch the row + resolve group-lane media → **post-await re-check the id is STILL unknown** (both in-app optimistic paths save the row BEFORE displaying — `:2168` vs `:2177`, `:4204` vs `:4233` — a late fetch would otherwise clobber optimistic absolute-path media with relative-path `upload_pending` DB rows) → `_enqueueGroupMessageUpdate(message, media: …, markAsRead: false)` (`:3427-3451`, the 159 per-frame coalesced flush). **Do NOT use `_refreshMessageWithHydratedMedia` (`:2910-2926`) — it calls `setState`/`_upsertMessage` directly and bypasses the coalescer.** No markAsRead (unread SQL is `is_incoming=1`-scoped, `group_messages_db_helpers.dart:569,:643-645`). Plus a **stale-load replay guard**: `_loadMessages` commits a snapshot fetched before its awaits and unconditionally replaces `_messages`/`_mediaMap` (`:1402-1423`) — an inserted upsert applied mid-load would be silently erased. Track a load generation; queue inserted ids that arrive while a load is in flight; after the load commits, re-run the hydrator for any queued id missing from the committed list.

Out of scope (owning work named):
- 1:1 external-share first frame + upload-progress UI → **Plan 253** (fix-list applied first).
- Group upload progress UI → 253 follow-up wave.
- External-share cancellation → 253's deferred follow-up.
- `deliverGroupMediaForward` source/destination gates → **Plan 236** (implemented; untouched here).
- Feed group text-reply non-optimism (text-only, pre-existing) → future feed work.

## Files To Inspect Next
Production: `lib/features/groups/domain/repositories/group_message_repository.dart` (:224-243), `group_message_repository_impl.dart` (:153-166, :297-312), `lib/features/groups/application/send_group_message_use_case.dart` (:534-574, :848, :935, :1074-1096, funnels :1170-1294/:1415-1430/:1490-1502/:1550-1567), `lib/features/groups/presentation/screens/group_conversation_wired.dart` (:1402-1453 stale-load window, :1648-1685 handler, :3390-3464 `_applyMessageUpdate`/`_enqueueGroupMessageUpdate` donor, :3721-3723).
Direct tests: `test/features/groups/domain/repositories/group_message_repository_impl_test.dart` (:334-521), `test/features/groups/application/send_group_message_use_case_test.dart` (:4235-4801, :6454-6520, :7267-7415), `test/features/groups/presentation/group_conversation_wired_test.dart` (:989-1108 harness, :2915-3359, :4577-4807), `test/features/groups/application/retry_failed_group_messages_use_case_test.dart`, `test/shared/fakes/in_memory_group_message_repository.dart` (:50-83).
Dependency-only context (read, do not edit): `share_batch_delivery_coordinator.dart` (:575-683), `share_target_picker_wired.dart`, `letter_card.dart` (:409,:437), `retry_failed_group_messages_use_case.dart` (:333-363), `media_attachments_db_helpers.dart` (:147-221,:245-253), `010_media_attachments.dart` (:17-31 — no FK).

## Existing Tests Covering This Area
- `send_group_message_use_case_test.dart` — WU-3 pre-persist-before-bridge (:6456), media payload/lane/persist-at-terminal (:4235-4500), six "rejects … before persistence" validation pins (:4541-4746), stale-placeholder reconciliation (:4751-4801), queuedOffline contract (:7267-7415). **Gap**: no attachment-vs-`:1096` ordering pin; no media persistence on the queuedOffline or failure funnels.
- `group_message_repository_impl_test.dart` (real ffi DB) — status-change emit (:335), updateMessageStatus emit (:368), incoming-emits-nothing (:397), same-status-emits-nothing (:427), count-only sweeps (:458-521). **Gap**: nobody subscribes before the FIRST save of a new outgoing row — the `previous==null` no-emit branch is unpinned in either direction.
- `group_conversation_wired_test.dart` — GFR-003 in-place status w/ no page reload (:4622), cross-group ignore (:4687), rowsChanged reload (:4734), unmount cancel (:4781), incoming-stream targeted upsert w/o reloads (:4577-4620), optimistic in-app media (:2915-3359), init hydration (:2512), TC-159-11 (:13641), 210b UX suite (:1121-1681). **Gap**: no test saves a brand-new OUTGOING row via the repo while mounted and asserts appearance.
- `share_batch_delivery_coordinator_test.dart` — real `_sendToGroup` is **text-only** (:368-533); every media-to-group case stubs `sendToGroupFn` (:125,:193,:1416) or uses the forward lane. **Gap**: the 254 symptom path is completely unpinned.
- No external-share-to-group integration test exists; 253's planned `external_share_media_ux_test.dart` does not exist yet (1:1-lane, net-new there).
Already in curated family arrays: impl test (`run_test_gates.sh:337`), use-case test (:375), retry-failed test (:376), wired test (:290), coordinator test (:373) — all in `GROUP_TESTS`.

## RED Test Catalog  (add BEFORE any production code — INV-RED-FIRST)

1. `test/features/groups/domain/repositories/group_message_repository_impl_test.dart::saveMessage emits one inserted event for a brand-new outgoing sending row`
   - Tier: repo host (sqflite_common_ffi, real DB — durability of the emit contract is the point)
   - Shape/setup: subscribe to `outgoingLocalMessageChanges` FIRST, then save a new outgoing `'sending'` row; companion asserts in the same test: a brand-new INCOMING save emits nothing; an identical re-save emits nothing further; **a brand-new OUTGOING row with `status: 'sent'` (the sibling-self-delivery / system-publish shape, `handle_incoming_group_message_use_case.dart:692` / system-publish retryable row) emits nothing**.
   - RED on HEAD because: `GroupOutgoingLocalMessageChange.inserted` does not exist (compile RED); once the variant exists but the impl still early-returns at `:157`, zero events observed.
   - GREEN after fix asserts: exactly one `inserted` with `groupId` + `messageId`, `reloadRequired == false`, `status == null`, for the `'sending'` row ONLY; all three negatives unchanged.
   - Mutations that re-red: restore `if (previous == null || saved.isIncoming) return;` unconditionally → zero events → red; drop the `status == 'sending'` condition → the `'sent'` negative control → red.
   - **Intentional re-red to update**: `'count-only sending sweeps emit one batch event only when rows changed'` (:458-521) — its subscribed brand-new outgoing save now ALSO sees one inserted event; update its expected count and assert the extra event is the `inserted` variant.

2. `test/features/groups/application/send_group_message_use_case_test.dart::persists stamped done attachments before the pre-persist row save and publish`
   - Tier: host application (operation-order spy + gated `FakeBridge`)
   - Shape/setup: media send with two attachments; a shared ordered operation log recorded by BOTH a spying `MediaAttachmentRepository` (`saveAttachment` entries) and a spying `GroupMessageRepository` (`saveMessage` entries); bridge publish additionally gated by a `Completer` for the idempotency leg.
   - RED on HEAD because: attachments persist only at terminal funnels → the log shows the first `saveMessage` BEFORE any `saveAttachment` (and zero attachments while the bridge gate is closed).
   - GREEN after fix asserts: **every `saveAttachment` entry precedes the FIRST `saveMessage` entry in the ordered log** (a bridge gate alone cannot discriminate this — the row save at `:1096` is followed by the bridge start at `:1103`, so save-row→persist-media→bridge would pass a gate-only test while retaining the media-free-row window); attachments carry `messageId == resolvedMessageId`, `owner == MediaOwnerLane.group`, `downloadStatus == 'done'`; after release, terminal re-persist leaves the same single set (idempotency).
   - Mutation that re-reds: move the early `_persistOutgoingMedia` anywhere at-or-below the `:1096` save (including between save and bridge) → order-spy assertion red.
   - Distinct-event discriminator: the ordered operation log (attachment-save indices < first message-save index), not completion-time state.

3. `test/features/groups/application/send_group_message_use_case_test.dart::terminal publish failure retains persisted done attachments`
   - Tier: host application
   - Shape/setup: bridge fails live publish AND inbox custody → terminal failure funnel (`:1236-1277`).
   - RED on HEAD because: failure branches never call `_persistOutgoingMedia` → zero attachment rows for the failed row.
   - GREEN: failed row exists with its stamped `'done'` attachments persisted.
   - Mutation that re-reds: revert F2 → red.

4. `test/features/groups/application/retry_failed_group_messages_use_case_test.dart::failed media send with persisted attachments is retried, not skipped as missing media`
   - Tier: host application (recording `FakeBridge`)
   - Shape/setup: produce the failed row **via the real use case** (same forced-failure path as #3 — not hand-seeded), then run `retryFailedGroupMessages` with a bridge that records send commands and succeeds.
   - RED on HEAD because: the failed row has no attachments → retry lane skips with reason `missing_media_attachments` (`retry_failed_group_messages_use_case.dart:333-363`) and the bridge records NO send for that id.
   - GREEN: **the recording bridge received the group send (reliable/publish) carrying the retried messageId**, the row's status transitioned OFF `'failed'`, exactly one candidate was retried, AND no `missing_media_attachments` skip event fired for that id.
   - Mutation that re-reds: revert F2 → red.
   - Distinct-event discriminator: the per-message bridge send command — NOT `RETRY_FAILED_GROUP_MESSAGES_START` (fires pre-validation at `:236-240`, vacuously satisfiable) and NOT `GROUP_SEND_MSG_USE_CASE_BEGIN` alone (carries no messageId, `send_group_message_use_case.dart:774-779`).

5. `test/features/groups/integration/external_share_group_media_liveness_test.dart::external image share to an open group conversation surfaces the message with its thumbnail while mounted`  **(NEW FILE — headline / PROD-CRITICAL leg)**
   - Tier: widget-integration host — real `DefaultShareBatchDeliveryCoordinator` constructed over the SAME in-memory repo instances as the mounted `GroupConversationWired` (fixture: clone wired harness setUp `:989-1029` + buildWidget `:1036-1108`; coordinator constructor pattern `share_batch_delivery_coordinator_test.dart:385-397`; group seeders `_seedGroupMembers :1575-1601` / `_saveLatestGroupKey :1561-1573`; precedents `group_media_forward_flow_test.dart:62-80`, `group_resume_recovery_test.dart:1120-1125`)
   - Shape/setup: mount the conversation; deliver a real tiny-PNG `ShareIntent` to the group via `coordinator.deliver`; pump.
   - RED on HEAD because: the liveness gap — the message never appears while mounted.
   - GREEN asserts: the bubble AND its media thumbnail appear; `getMessagesPageCalls` unchanged from the initial mount (targeted upsert, not a full reload).
   - Mutations that re-red: revert F1 (no inserted emit) → never appears; revert F3 (drop the inserted branch) → never appears; revert F2 (no early persist) → bubble may appear but thumbnail assertion fails.

6. same file::`a mid-send group media row renders its thumbnail on the first loaded frame`
   - Tier: widget-integration host
   - Shape/setup: gate the REPO's `saveMessage` (hold the first row-save future via a gating repo wrapper — NOT the bridge, which starts only after the save and cannot discriminate ordering); start `coordinator.deliver` unawaited; **while the row save is held, await until the attachment rows are durable and assert the message row is still absent** (the order proof); release the save; mount the screen; settle once.
   - RED on HEAD because: while the row save is held, the attachment rows NEVER appear (HEAD persists media only at terminal funnels, after save + dispatch) → the await times out → red for the causal reason.
   - GREEN: attachments durable before the row exists; thumbnail present on the first loaded frame after mount (post-save persistence CANNOT satisfy this construction).
   - Mutation that re-reds: revert F2 (or move the persist below the save) → red.

7. `test/features/groups/presentation/group_conversation_wired_test.dart::inserted event for an in-flight optimistic media send does not clobber optimistic media`
   - Tier: widget host (completer-armed — deterministic, not timing-dependent)
   - Shape/setup: in-app media send via the existing optimistic harness (`:2915` pattern); the fake repo emits `inserted` at the UI-side save (`:2168`) BEFORE `showOptimisticMessage` (`:2177`). **Arm with completers: gate the hydrator's row/media fetch so it PAUSES after observing the unknown id; let the optimistic upsert install its absolute-path media; then release the fetch** and pump.
   - RED on HEAD: **N/A — new-invariant guard** (F3 does not exist on HEAD). It is red against the naive F3 that lacks the post-await unknown-recheck; that is its documented failure mode.
   - GREEN: the rendered media remains the optimistic entries; no `upload_pending` relative-path clobber of `_mediaMap`.
   - Mutation that re-reds: remove F3's post-await "id still unknown" re-check → red (deterministically, because the completer forces the race ordering).

8. `test/features/groups/presentation/group_conversation_wired_test.dart::multiple inserted events surface targeted upserts without a full page reload`
   - Tier: widget host
   - Shape/setup: mounted screen; save three brand-new outgoing `'sending'` rows for this group via the (lockstep-updated) fake repo within one frame; pump.
   - RED on HEAD because: none of the three ever appears (liveness gap).
   - GREEN: all three appear; `getMessagesPageCalls` unchanged from initial mount; **the burst lands in ONE coalesced flush (one reorder frame, per the `_enqueueGroupMessageUpdate` contract `:3423-3451`) — not three direct setStates**; **zero `markConversationAsRead` calls** (fake repo call counter).
   - Mutations that re-red: implement F3's inserted branch as `_loadMessages()` → page-call count rises → red; apply upserts via direct setState per event (e.g. `_refreshMessageWithHydratedMedia`) → flush-count assert red; pass `markAsRead: true` → mark-read counter red.

9. `test/features/groups/presentation/group_conversation_wired_test.dart::an inserted message survives a concurrent stale page load`
   - Tier: widget host (completer-armed interleaving)
   - Shape/setup: mounted screen; gate the fake repo's `getMessagesPage` with a `Completer` and trigger a reload (emit `rowsChanged`); while the load is in flight (snapshot already taken), save a brand-new outgoing `'sending'` row (fires `inserted`); release the load; pump.
   - RED on HEAD: **N/A for the appearance itself (liveness gap makes it vacuous on HEAD)** — this row is the guard for F3's replay mechanism: red against a naive F3 without the stale-load replay, because `_loadMessages` unconditionally replaces `_messages`/`_mediaMap` from its pre-insert snapshot (`:1402-1423`) and erases the applied upsert.
   - GREEN: after the stale load commits, the inserted message (and its media) is still displayed — replayed after the load commit.
   - Mutation that re-reds: remove the load-generation/queued-ids replay from F3 → red.

## Test Coverage Matrix  (ZERO empty cells)

| Spec case | Behavior props | Tier | Test file::name | RED reason on HEAD | Mutation revert | Acceptance gate cmd | Harness registration |
|---|---|---|---|---|---|---|---|
| TC-254-01 repo inserted emit (`'sending'`-gated) | repo emit contract, real DB | repo host (ffi) | `group_message_repository_impl_test.dart::saveMessage emits one inserted event for a brand-new outgoing sending row` | `.inserted` absent (compile), then zero events (`:157` early return) | restore unconditional early return; drop the `'sending'` gate → `'sent'` negative control red | `flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart --plain-name 'saveMessage emits one inserted event for a brand-new outgoing sending row'` | AUTO (glob); file already in `GROUP_TESTS` (`run_test_gates.sh:337`) |
| TC-254-02 early media persist (order-spy) | ordering, use-case seam | host application | `send_group_message_use_case_test.dart::persists stamped done attachments before the pre-persist row save and publish` | ordered op-log shows first `saveMessage` before any `saveAttachment` (terminal-only persist `:1187-1294`) | move early persist anywhere at-or-below the `:1096` save | `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'persists stamped done attachments before the pre-persist row save and publish'` | AUTO; file in `GROUP_TESTS` (`:375`) |
| TC-254-03 failed-send media durability | failure funnel, durability | host application | `send_group_message_use_case_test.dart::terminal publish failure retains persisted done attachments` | failure branches `:1236-1277` never persist media | revert F2 | `flutter test test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'terminal publish failure retains persisted done attachments'` | AUTO; file in `GROUP_TESTS` (`:375`) |
| TC-254-04 retryability restored | retry lane handoff; per-id bridge-send discriminator | host application | `retry_failed_group_messages_use_case_test.dart::failed media send with persisted attachments is retried, not skipped as missing media` | no bridge send recorded for the id; skip with `missing_media_attachments` (`:333-363`) | revert F2 | `flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart --plain-name 'failed media send with persisted attachments is retried, not skipped as missing media'` | AUTO; file in `GROUP_TESTS` (`:376`) |
| TC-254-05 open-conversation liveness (headline) | end-to-end surface, real coordinator | widget-integration host | `external_share_group_media_liveness_test.dart::external image share to an open group conversation surfaces the message with its thumbnail while mounted` | liveness gap (root-cause links 1-3) | revert F1 / F3 / F2 (three distinct re-reds) | `flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart --plain-name 'external image share to an open group conversation surfaces the message with its thumbnail while mounted'` | AUTO `feature-host-all` (`run_host_test_gates.sh:256-258`) + **ADD to `GROUP_TESTS` array** (`run_test_gates.sh:274-382`) |
| TC-254-06 first-frame media, held-row-save order proof | render-during-window + ordering | widget-integration host | same file::`a mid-send group media row renders its thumbnail on the first loaded frame` | attachments never durable while the row save is held (terminal-only persist); timestamp-only frame (`letter_card.dart:409,:437`) | revert F2 / move persist below save | `flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart --plain-name 'a mid-send group media row renders its thumbnail on the first loaded frame'` | same file (AUTO + `GROUP_TESTS` add covers it) |
| TC-254-07 optimistic no-clobber | new-invariant guard, completer-armed race | widget host | `group_conversation_wired_test.dart::inserted event for an in-flight optimistic media send does not clobber optimistic media` | N/A on HEAD — red against naive F3 (no post-await recheck); documented | remove F3 post-await unknown-recheck | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'inserted event for an in-flight optimistic media send does not clobber optimistic media'` | AUTO; file in `GROUP_TESTS` (`:290`) |
| TC-254-08 burst: one coalesced flush, no reload, no mark-read | perf lock (159) + coalescer contract | widget host | `group_conversation_wired_test.dart::multiple inserted events surface targeted upserts without a full page reload` | rows never appear (liveness gap) | F3 branch → `_loadMessages()`; direct per-event setState; `markAsRead: true` — three distinct re-reds | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'multiple inserted events surface targeted upserts without a full page reload'` | AUTO; file in `GROUP_TESTS` (`:290`) |
| TC-254-09 inserted survives stale load | reload-race replay guard | widget host | `group_conversation_wired_test.dart::an inserted message survives a concurrent stale page load` | N/A on HEAD (liveness gap makes it vacuous) — red against F3 without the replay: stale `_loadMessages` snapshot erases the upsert (`:1402-1423`) | remove the load-generation/queued-ids replay | `flutter test test/features/groups/presentation/group_conversation_wired_test.dart --plain-name 'an inserted message survives a concurrent stale page load'` | AUTO; file in `GROUP_TESTS` (`:290`) |

## Blind-Spot Sweep
- **Lifecycle / derived-state durability**: TC-254-06 — a fresh mount mid-send reconstructs the media frame purely from durable rows (no in-memory derived state is added by this plan; message + attachment rows are the only state).
- **Sibling-surface consistency**: TC-254-05 exercises the coordinator lane shared by BOTH the OS share and the in-app group-media Forward (verified same funnel: wired `:4885-4933` → picker → coordinator `:628`). Announcement chats reuse this same screen and stream (single-consumer census) → inherit the fix. The 1:1 lane is deliberately asymmetric — owned by Plan 253 (its event-object mechanism differs because `ConversationMessage` events carry media inline). Feed text-reply non-optimism is text-only and pre-existing → named out-of-scope.
- **Destructive-action side-effects**: justified N/A — no delete/cleanup/cancel behavior changes. NEW accepted residue: a crash between F2's early persist and the `:1096` row save leaves orphan attachment rows (+ key + file) that no sweep touches and no library page shows (storage/library pages inner-join the parent — `media_library_db_helpers.dart:107,:224`); bounded, invisible, and strictly smaller than the HEAD failure window it replaces (failed rows whose media was never persisted at all → permanent loss). Recorded in Accepted Differences; a dedicated orphan-sweep is future work.
- **Invariant re-verification under new transitions**: the `inserted` event is a new transition into a mounted screen — TC-254-07/08/09 assert the full post-transition state (no page reload, no optimistic clobber, no markAsRead flip — unread SQL is `is_incoming=1`-scoped, `group_messages_db_helpers.dart:569,:643-645` — and survival across a concurrent stale reload, `:1402-1423`); the pre-existing pins GFR-003 (:4622), cross-group ignore (:4687), rowsChanged reload (:4734), unmount cancel (:4781), TC-159-11 (:13641) must stay green untouched.

## Invariants (locked by tests)
- INV-254-1: a brand-new outgoing **`'sending'`** row save emits exactly one `inserted`; incoming saves, same-status re-saves, and new outgoing NON-`'sending'` rows (sibling self-delivery `'sent'`, system-publish `'sent'`) emit nothing → TC-254-01.
- INV-254-2: stamped, group-lane, `'done'` attachments are durable BEFORE the first message-row save (order-spy: every attachment save precedes the first `saveMessage`) → TC-254-02/06.
- INV-254-3: terminal failure preserves attachments and retryability (per-id bridge send recorded on retry; no `missing_media_attachments` skip) → TC-254-03/04.
- INV-254-4: an externally-originated group media message surfaces live in a mounted conversation with its thumbnail, via targeted coalesced upsert (no full page reload, one flush per burst, zero mark-read) → TC-254-05/08.
- INV-254-5: fresh mount mid-send renders media on the first loaded frame → TC-254-06.
- INV-254-6: optimistic in-app display is never clobbered by the inserted-fetch → TC-254-07.
- INV-254-7: an inserted upsert survives a concurrent stale `_loadMessages` commit (queued-id replay after load) → TC-254-09.
- INV-RED-FIRST and INV-MUTATION-VERIFIED apply to every row above.

## Step-By-Step Implementation Plan
1. **Contract extraction**: `git status --short` snapshot; `flutter analyze` baseline count. Tree state at planning (2026-07-10 22:20): HEAD `b1d043eb3`, Plan 236 COMMITTED, and all five 254 target production/fake files are CLEAN — re-verify at execution; whatever unrelated dirt exists, 254 touches NO coordinator/share file (Stop-if any 254 edit would touch `share_batch_delivery_coordinator.dart` or `share_target_picker_*` → scope drift, replan).
2. **RED**: add TC-254-01..06 and 08 (TC-254-07/09 are authored with step 5 as its invariant guards); run the exact per-row commands; record each failure reason matches the documented RED. Stop-if TC-254-05's RED shows the message DOES appear on HEAD → the liveness grounding is stale; re-ground before any production edit.
3. **F1**: add the `inserted` variant to `GroupOutgoingLocalMessageChange` (`group_message_repository.dart:224-243`); emit in impl `saveMessage` when `previous == null && !message.isIncoming && message.status == 'sending'` (`:153-166` gains the branch; `:297-312` unchanged call). Update the shared fake in lockstep (`in_memory_group_message_repository.dart:50-83`). Update the one intentional re-red (`impl_test :458-521` count). GREEN: TC-254-01. Note: F1 alone is a UI no-op (an `inserted` event falls through the current handler's `status == null` return at `:1683`) — safe to land before F3.
4. **F2**: in `sendGroupMessage`, call `_persistOutgoingMedia(mediaAttachmentRepo, groupMediaAttachments.map(copyWith(messageId: resolvedMessageId)))` immediately BEFORE the `:1096` saveMessage — placement is pinned: after sanitation (`:848`), auth, and id-resolution (`:935`); the six "rejects … before persistence" tests and `:6768/:6797` must stay green. Keep all terminal persists. Stop-if any validation pin re-reds → placement is wrong; move the persist later, never weaken a pin. GREEN: TC-254-02/03/04/06 (TC-254-02's order-spy is the placement proof — a bridge gate alone cannot discriminate).
5. **F3**: extend `_handleOutgoingLocalMessageChange` with the inserted branch as a dedicated hydrator (donor: `_applyMessageUpdate` `:3390-3421`): group filter (existing `:1670-1673`) → known-id no-op → fetch row + resolve group-lane media → **post-await re-check** the id is still unknown → `_enqueueGroupMessageUpdate(message, media:, markAsRead: false)` (`:3427-3451`). NOT `_refreshMessageWithHydratedMedia` (direct setState, bypasses the coalescer). Add the **stale-load replay guard**: load-generation counter in `_loadMessages`; queue inserted ids arriving mid-load; after commit, re-hydrate queued ids missing from the committed list. Author TC-254-07 and TC-254-09 with this step. GREEN: TC-254-05/07/08/09.
6. **Registration + gates**: add `test/features/groups/integration/external_share_group_media_liveness_test.dart` to the `GROUP_TESTS` array (`run_test_gates.sh:274-382`); verify with the literal rg gate below (lesson from the 253 review: never trust a delegating dry-run). Run focused GREEN, preservation sentinels, `./scripts/run_test_gates.sh groups`, `./scripts/run_host_test_gates.sh feature-host-all`, analyzer, diff hygiene.

## Risks And Edge Cases
- Inserted-fetch races the optimistic upsert (UI-side save precedes display at `:2168→:2177`, `:4204→:4233`) → post-await unknown-recheck; pinned by TC-254-07 (completer-armed).
- Multi-device inbox-drain sibling self-echoes (`isIncoming:false, status:'sent'`, saved before their media — `handle_incoming_group_message_use_case.dart:692-699,:705`; root-repo writes `drain_group_offline_inbox_use_case.dart:863-877`) are **excluded by the `'sending'` gate** — they never emit `inserted`; pinned by TC-254-01's `'sent'` negative control. Live sibling-echo surfacing is NOT claimed by this plan.
- A stale `_loadMessages` commit (lifecycle resume, or a `rowsChanged` from ANY group's retry lane) erases a mid-load inserted upsert (`:1402-1423` unconditional replace) → load-generation + queued-id replay; pinned by TC-254-09.
- `inserted` also fires from the UI's own optimistic `'sending'` saves — F3's known-id no-op and post-await recheck cover it; system-publish retryable rows are saved `'sent'` (excluded by the gate) and timeline builders are `isIncoming:true` (`group_membership_timeline_message.dart:54-259`) so neither emits.
- F2 recovery-lane shift: a crash between `:1096` and a terminal funnel now leaves `'done'` attachments, moving recovery from `retryIncompleteGroupUploads` (upload_pending selector) to the stuck-sending sweep + `retryFailedGroupMessages` persisted-attachments lane (`:337-348`) → pinned by TC-254-04; `retryIncompleteGroupUploads` cannot double-handle (its selector is `upload_pending`-only).
- Reconciliation double-run (early + terminal): verified idempotent merge-upsert — wipe only fires for an `upload_pending` row whose id is OUTSIDE the passed set (`:548-566`); all 6 callers pass identical or fresh ids.
- Orphan attachment residue on crash → Accepted Differences (bounded, invisible; strictly better than HEAD's permanent-loss window).

## Device/Relay Proof Profile
**host-only for closure.** Every edited seam is pure in-process Dart (a broadcast-stream event variant, a DB-write ordering swap inside one use case, a widget-handler branch). No OS callback, no native code, no crypto/wire change, no relay custody change, no schema change (media rows and message rows keep their exact shapes — only WHEN they are written moves). The real coordinator (not a stub) drives the headline integration rows over shared in-memory repos, and the repo-emit contract is proven on a real ffi DB. Optional supporting confidence (NOT a gate): one physical share-sheet replay into an open group after 253's device replay wave.
Migration: **none** (no `DB v##`).
Closure scenario: n/a (no `/sims` row — no simulator/device scenario is registered by this plan).

## Acceptance Gates  (literal — copy/paste)
```bash
# Snapshot before execution; preserve unrelated/user-owned changes.
git status --short
flutter analyze   # record baseline count (dirty tree)

# RED (before production edits) — each must FAIL for its documented reason
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart \
  --plain-name 'saveMessage emits one inserted event for a brand-new outgoing sending row'
flutter test test/features/groups/application/send_group_message_use_case_test.dart \
  --plain-name 'persists stamped done attachments before the pre-persist row save and publish'
flutter test test/features/groups/application/send_group_message_use_case_test.dart \
  --plain-name 'terminal publish failure retains persisted done attachments'
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart \
  --plain-name 'failed media send with persisted attachments is retried, not skipped as missing media'
flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart \
  --plain-name 'external image share to an open group conversation surfaces the message with its thumbnail while mounted'
flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart \
  --plain-name 'a mid-send group media row renders its thumbnail on the first loaded frame'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'multiple inserted events surface targeted upserts without a full page reload'

# Direct GREEN (after each fix step; expect exit 0, zero failures)
flutter test test/features/groups/domain/repositories/group_message_repository_impl_test.dart
flutter test test/features/groups/application/send_group_message_use_case_test.dart
flutter test test/features/groups/application/retry_failed_group_messages_use_case_test.dart
flutter test test/features/groups/integration/external_share_group_media_liveness_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart

# Preservation sentinels (must stay green; expect exit 0)
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'GFR-003 open conversation applies outgoing local status update in place'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'local status event for another group is ignored'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'batch local rows-changed event reloads visible sending row status'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'local status stream is cancelled after unmount'
flutter test test/features/groups/presentation/group_conversation_wired_test.dart \
  --plain-name 'incoming message stream upserts without full message/media reloads'
flutter test test/features/groups/application/send_group_message_use_case_test.dart \
  --plain-name 'removes stale upload_pending placeholders before saving final attachments'
flutter test test/features/groups/application/send_group_message_use_case_test.dart \
  --plain-name 'is queued_offline (durably queued, not failed)'
flutter test test/features/share/application/share_batch_delivery_coordinator_test.dart   # group text-share + forward contracts

# Registration gate (literal source check — a delegating dry-run is NOT proof; 253-review lesson)
rg -n 'external_share_group_media_liveness_test.dart' scripts/run_test_gates.sh   # expect: 1 hit inside GROUP_TESTS

# Curated family + justified feature family; expect exit 0 and zero failures.
./scripts/run_test_gates.sh groups
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene
flutter analyze        # no NEW issues vs the step-1 baseline
git diff --check
```

## Known-Failure Interpretation
- Expected RED: the seven RED-catalog commands above, each for its documented reason; TC-254-01 first fails as a COMPILE error until the event variant exists.
- Intentional re-red to update: `group_message_repository_impl_test.dart::'count-only sending sweeps emit one batch event only when rows changed'` (:458-521) — expected-count update, part of step 3.
- Pre-existing dirty: at planning time (HEAD `b1d043eb3`) Plan 236 is COMMITTED and every 254 target production/fake file is CLEAN; residual dirt is docs/graph/index files only. Re-snapshot at execution; preserve whatever unrelated dirt exists — none of it is edited by 254.
- Environment blocker (NOT product): none — host-only, in-memory + ffi fixtures.
- Scope drift (BLOCKING): any edit to coordinator/share files, the 1:1 lane, drain Phase-1 transaction semantics, `deliverGroupMediaForward` gates, or a `group_messages` schema change → stop and replan.

## Done Criteria
- [x] RED added first; each failed for its documented reason (recorded in Execution Progress).
- [x] Mutation-verified: F1 (restore early return → TC-254-01 red; drop the `'sending'` gate → TC-254-01 `'sent'` negative red), F2 (move persist at-or-below the `:1096` save → TC-254-02 order-spy / TC-254-03/04/06 red), F3 (drop inserted branch → TC-254-05 red; drop post-await recheck → TC-254-07 red; full-reload / per-event setState / markAsRead:true → TC-254-08's three re-reds; the combined replay-guard mutation → TC-254-09 red).
- [x] Direct GREEN + all preservation sentinels + `groups` gate + `feature-host-all` pass.
- [x] The shared fake emits `inserted` in lockstep with the impl (TC-254-05/07/08 depend on it).
- [x] New integration file registered in `GROUP_TESTS`; the rg gate returns exactly 1 hit.
- [x] `flutter analyze` has no new issues vs baseline; `git diff --check` clean; Scope Guard respected.

## Scope Guard (hard "Do not")
- Do not edit `share_batch_delivery_coordinator.dart`, `share_target_picker_*`, or any 1:1-lane file — Plans 236/253 own them.
- Do not add a media column to `group_messages`, bump the DB, or touch SQLCipher migrations.
- Do not emit `inserted` for `isIncoming` rows or for new outgoing rows whose status is not `'sending'` (sibling self-echo / system-publish shapes), and do not convert it into a `reloadRequired` event (full-reload storms are exactly what the 159 locks forbid).
- Do not implement the F3 upsert via `_refreshMessageWithHydratedMedia` or any direct per-event `setState` — route through `_enqueueGroupMessageUpdate` (`:3427-3451`).
- Do not make `_updateLocalMessageStatus` fetch unknown ids (killed alternative — completion-latency + media-persist race).
- Do not use `saveGroupAttachmentGuarded` for F2 (refuses parentless saves by design).
- Do not touch drain Phase-1 root-repo write-through semantics, `deliverGroupMediaForward` source/destination gates, or retry-lane selectors.
- Do not add progress UI, cancellation, or ETA affordances (253 wave owns them).

## Accepted Differences / Intentionally Out Of Scope
- Crash between early persist and row save leaves orphan attachment rows (invisible — library pages inner-join the parent). **Per-send bounded but cumulatively UNBOUNDED**: no FK and no existing sweep ever reclaims them (rows + keychain keys + files). Accepted for this plan because the window is a process-kill race and each occurrence is small; the cleanup follow-up is owned by the **media storage-controls wave (229 follow-up: orphan-attachment sweep in `MediaStorageManager`)** and should land before any high-volume share usage. Still strictly better than the HEAD failure window it replaces (permanent media loss on terminal failure).
- Sibling-device self-echo rows do NOT surface live via `inserted` (excluded by the `'sending'` gate — their media persists after the row, `handle_incoming_group_message_use_case.dart:699,:705`); live sibling-echo surfacing needs its own designed slice with a media-ready signal.
- External shares surface with `'sending'` status and no byte-progress UI — progress belongs to the 253 wave.
- Feed group text replies remain non-optimistic (text-only, pre-existing) — future feed work.
- 1:1 external-share first frame — Plan 253 (fix-list applied first).

## Dependency Impact
- Plan 253 execution is unaffected: disjoint production files; both plans add tests to different curated arrays (`ONE_TO_ONE_TESTS` vs `GROUP_TESTS`). The 253-review's vacuous-dry-run lesson is already encoded in this plan's rg registration gate.
- Plan 236 (COMMITTED at `b1d043eb3`): untouched; its forward lane inherits the liveness fix automatically because the forward funnels into the same coordinator group lane whose surfacing 254 repairs.
- Future group progress/cancellation work builds on the `inserted` event (a natural anchor for "send started" UI).

## Reviewer Findings
Sufficiency self-check (references/sufficiency-checklist.md): all core conditions and gates pass. Matrix has zero empty cells in tier/mutation/gate/registration across 9 rows. TC-254-07 and TC-254-09 are new-invariant guards, documented as not-RED-on-HEAD with their red-against-naive-F3 failure modes and mutations. One intentional re-red is named with its exact update. PROD-CRITICAL leg = TC-254-05 (real coordinator end-to-end over shared repos); host-only closure justified — no OS-boundary/crypto/relay/multi-device/schema surface is edited. Blind-spot sweep: all four classes rowed or justified. Refuted findings recorded (self-echo, already-fixed-by-236, killed alternatives, wrong F3 donor, withdrawn sibling-echo benefit).
External audit (2026-07-10, applied in full — all 5 required findings source-verified): F1 `'sending'` gate; TC-254-02/06 order-spy / held-row-save constructions (bridge gate was order-blind); F3 donor corrected to `_applyMessageUpdate`→`_enqueueGroupMessageUpdate`; TC-254-09 stale-load replay guard added; TC-254-04 re-anchored on the per-id bridge send (START event is pre-validation; BEGIN carries no messageId). Non-blocking items applied: tree-state wording refreshed; orphan residue reworded cumulatively-unbounded with a named owner.

## Arbiter Decision
Structural blockers: none. Deferred details: exact fixture file layout for the new integration test (clone-and-trim of the wired harness — executor's discretion within the named precedents). Accepted differences: as listed. Hand off to execution.

## Final Execution Verdict
Verdict: accepted | Implementation: `f243b2788`; acceptance hardening: `de0aabfd5` | Tests: nine final causal GREEN tests, 11 mutation cycles / 13 expected RED logs, `groups` 1,926 plus Go, and `feature-host-all` 731/731 | Hygiene: analyzer 1,627 versus 1,628 baseline; scoped lints all pre-existing; `git diff --check` clean | QA verdict: accepted | Non-blocking follow-ups (owner): orphan-attachment sweep (media storage-controls wave, 229 follow-up in `MediaStorageManager`); live sibling-echo surfacing (own designed slice).

## Execution Result

- **Final verdict:** `accepted`
- **Execution mode:** `tdd-exec (local)`
- **Assurance mode:** managed mutation and independent-QA closure completed.
- **Independent QA:** `accepted` on 2026-07-11; no functional, scope, or evidence blocker remains.
- **Broad-gate result:** the complete current `feature-host-all` inventory passed all 731 commands.
- **Implemented:** outgoing `sending` insert notifications; early durable group-media persistence; targeted mounted-screen hydration with media, post-await identity/status protection, coalesced no-read upsert, and stale-load replay.
- **Tests added/updated:** repository insert contract; persistence order/failure/retry coverage; mounted burst, optimistic/status race, and stale-load widget coverage; new `external_share_group_media_liveness_test.dart`; one `GROUP_TESTS` registration.
- **RED evidence:** all seven catalog commands failed causally before production edits (missing insert event, missing early media durability, retry loss, and mounted/first-frame liveness gaps).
- **Direct GREEN on the latest observed tree:** repository `52/52`; send use case `151/151`; failed-message retry `27/27`; external-share integration `2/2`; wired conversation `191/191` on final rerun; share coordinator `18/18`.
- **Registration:** `rg -n 'external_share_group_media_liveness_test.dart' scripts/run_test_gates.sh` returned exactly one `GROUP_TESTS` hit.
- **Curated gate:** `./scripts/run_test_gates.sh groups` passed on the final observed tree: `1926` Flutter tests plus Go bridge/node packages.
- **Historical broad-gate attempt 1:** `feature-host-all` stopped on a concurrent dirty-tree compile mismatch in new media rollback work; its owner corrected that seam and the complete send suite then passed.
- **Historical broad-gate attempt 2:** progressed through the repaired seam, then item `#289` failed before test execution on a concurrent macOS native-assets `lipo` temp-file race. These attempts are superseded by the complete 731/731 rerun recorded above.
- **Hygiene completed:** initial analyzer baseline recorded `1628` pre-existing issues; final analyzer reports `1627`; all seven scoped informational lints blame to pre-254 commits; final `git diff --check` passed; implementation commit scope contains no banned share coordinator/picker, 1:1 wired screen, or migration file.
- **Graphify:** affected-impact query completed; `./graphify-arch/refresh_arch_graph.sh --incremental` succeeded (`46688` nodes, `72699` edges; TDD overlay `12161` named tests).
- **Managed closure:** complete. Eleven mapped mutation cycles generated all expected causal REDs (13 logs); exact restoration was followed by all nine final tests passing. The original isolated stale-replay mutation was superseded by the stricter combined replay-guard mutation, which causally re-reds TC-254-09.
- **Concurrency note:** while this execution was active, another session advanced HEAD through `21b6b54e2` to implementation commit `f243b2788` and edited overlapping group-media files. Plan 254 focused tests were rerun after those edits; no concurrent process or user-owned change was terminated or reverted.
- **Safety statement:** causal RED/GREEN, all direct suites, coordinator preservation, curated groups coverage, the complete feature family, analyzer comparison, mutation proof, scope checks, graph impact, and independent QA are green; Plan 254 is accepted.
