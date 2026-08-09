# 351 - GAP-N01 Ordinary Direct-Media Delete-for-Everyone Custody

Status: **EXECUTION_READY / REVIEWED / NOT IMPLEMENTED** (2026-08-09)
Type: Modification
Baseline observed while planning: `e0a559aef53243f0126958be9800b2c092403a84` (`docs: carry the notification coverage assessment through Plan 350`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` requirements 1, 3, and 6 plus A-01/A-02/A-03/A-24/A-26; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / §9.2
Classification: execution-ready after the documented clean checkpoint handoff; bounded adoption of the existing v109 mutation and v111 blob owners; core bet confirmed by `$tdd-review`
Closure tier: host real-SQLite/filesystem concurrency and restart proof, affected curated/family gates; no relay/native/schema/mobile/iOS claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-09 | Evidence Collector | PRD economy/finish-line rules; GAP-N01/WP-01; Plans 345/347/349/350; delete authoring; v108/v109/v111 helpers; media repository/lifecycle lock; incoming chat/deletion/download paths; retry/bootstrap/gates | Confirmed one bounded gap: strict ordinary direct-media delete-for-everyone can terminalize v111 before its text-only v109 stage refuses physical attachments, while receiver delete/strict-initial/download races can resurrect media after a durable tombstone. | Define one atomic outgoing crossing and one transactional incoming winner without new durable infrastructure. |
| 2026-08-09 | Planner | Exact v108 completion; v111 terminalization/cleanup; v109 completion; physical attachment fingerprint; receiver publication/generic-save guards | Reuse DB v111 and physical v109 unchanged. An exact live v108 owner must coexist with the deletion and retain v111; only unbound v111 may transition to cleanup in the deletion transaction. The incoming tombstone is durable precedence, not a new artifact-purge journal. | Write the causal contract, run the sufficiency checklist, then invoke `$tdd-review`. |
| 2026-08-09 | Independent Reviewer | Full Plan 351 contract; outgoing v108/v109/v111 state matrix; incoming strict-initial/deletion/display/download races; literal test files and gate registrations | Required four bounded corrections: parent-conditional display custody with deletion-side marker retirement, exact historical unbound-v108 preservation, recomputed v111-to-attachment fingerprint parity, and a nonthrowing post-stage supersession result that still emits the initial receipt. All are incorporated and causally named. Final verdict: READY. | Hand the corrected plan to the arbiter; do not implement in this session. |
| 2026-08-09 | Arbiter | Corrected scope, six-row test contract, focused RED/GREEN commands, family cadence and explicit exclusions | Core bet confirmed. One same-schema strict-media deletion crossing plus narrow incoming resurrection guards is coherent and sufficient. Crash-complete artifact erasure, caption edit, private/group adoption and activation remain correctly deferred. Final verdict: READY after the separate checkpoint session leaves a clean tree. | Append the execution-ready ledger marker; implementation begins only from the later clean handoff. |

## Problem And Evidence

- Behavior to improve: deleting an already-sent strict ordinary direct-media or voice message for everyone must durably stage the authenticated deletion event before any network request, retain that exact event through node stop/restart/live success, and converge with the receiver's strict-media initial/download path without resurrecting the deleted card or local media.
- User impact: the current sender may cancel blob authority and then fail to retain the deletion envelope, so the original can remain visible remotely while the sender shows a tombstone. On receive, independently scheduled initial/delete/download work can overwrite a durable delete or leave a post-delete plaintext artifact.
- Confirmed outgoing split-commit defect: `deleteMessageForEveryone` calls `_authorizeOutgoingDirectMediaBlobParentDeletion` before staging the tombstone (`lib/features/conversation/application/delete_message_use_case.dart:437-449`). That helper terminalizes v111 and marks pending attachments failed under the media lifecycle lock (`:1005-1052`). The later Plan 349 v109 stage is text-only and refuses any physical direct attachment (`lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart:101-116`). A crash/refusal can therefore change v111 without committing either the tombstone or its v109 event.
- Confirmed selector defect: `MessageRepositoryImpl.getMessage` hydrates only the `messages` row (`lib/features/conversation/data/repositories/message_repository_impl.dart:552-555`), so `currentMessage.media.isEmpty` is not physical-media authority. After v108 staging, `direct_media_custody_intent_id` is intentionally cleared (`lib/core/database/helpers/media_attachments_db_helpers.dart:2162-2175`). The durable strict-media discriminator is the complete direct attachment projection with nonblank `direct_media_blob_custody_fingerprint`, not a UI snapshot or the consumed v110 intent.
- Confirmed reusable mutation owner: physical v109 already stores `(recipient_peer_id,event_id)` plus exact opaque envelope and retry/CAS fields, and Plan 349's single fair drain already classifies deletion as `direct_mutation_v109`. No relay kind, parser, native binding, table, column, index, migration, flag, queue, or scheduler is missing for a media-parent deletion.
- Confirmed v108 coexistence requirement: a live/device ACK does not retire v108. Exact v108 completion deliberately preserves an already-deleted parent, retires only its own incarnation, and transitions its complete bound v111 generation to cleanup in the same transaction (`lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart:348-442`). Refusing deletion whenever v108 exists would strand normal delivered media.
- Confirmed v111 independence: DB v111 has no parent/attachment foreign key and explicitly preserves outgoing cleanup and incoming ACK/expiry obligations after parent deletion (`lib/core/database/migrations/111_direct_media_blob_custody.dart:208-213`). The deletion must not delete, rewrite, or falsely ACK these rows.
- Confirmed completion gap: `dbCompleteAcceptedDirectMutationInboxCustodyIfExact` requires the text policy and refuses every direct attachment (`lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart:459-561`). Protected acceptance of an exactly staged media deletion would therefore retain the v109 row forever unless deletion completion permits its staged media lineage while keeping media EDIT excluded.
- Confirmed incoming race: chat and deletion arrive on independent async streams. A current deletion whose target was absent at the handler's first read enters the ordinary-text path (`lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart:217-286`); if strict media stages before its transaction, the text helper refuses physical attachments and the recovered inbox classifies the event as terminally rejected. Conversely, strict stage currently treats an exact author tombstone as generic refusal (`lib/core/database/helpers/media_attachments_db_helpers.dart:6055-6280`) instead of durable supersession.
- Confirmed post-delete producers: strict local-path commit does not reject a deleted/hidden parent (`lib/core/database/helpers/media_attachments_db_helpers.dart:6319-6338`); the download owner writes the canonical plaintext before that commit and leaves it when the commit returns false (`lib/features/conversation/application/strict_direct_media_blob_download_ack_owner.dart:242-279`); generic direct attachment save permits incoming tombstones (`lib/core/database/helpers/media_attachments_db_helpers.dart:4395-4480`); bootstrap retries `incoming_committed` for any incoming parent (`lib/app/bootstrap/production_application_bootstrap.dart:3967-3984`); and publication reloads without an `isDeleted` guard (`lib/features/conversation/data/repositories/message_repository_impl.dart:497-518`).
- Confirmed cleanup boundary: duplicate incoming deletions send another receipt without re-driving best-effort artifact cleanup (`lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart:348-355`). Re-driving that existing idempotent cleanup is sufficient for this custody slice. A crash between row/key/file cleanup steps can still leave inaccessible local residue; the PRD does not make crash-complete local erasure part of inbox ACK, so a new cleanup journal/scanner is not justified here.
- Existing coverage to reuse: Plan 347 owns exact v111 bytes, strict receive/download/source-pinned ACK and cleanup; Plan 349 owns deletion event identity, raw v109 keys, protected relay kind, retry egress guards, event-aware receipts and text receiver convergence. This plan adds only the media-parent crossing and resurrection guards.
- Unresolved finding: none in the bounded contract. Caption EDIT requires a different persisted commitment-lifetime decision and is explicitly not bundled.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `daebefba78899021`; current at planning baseline `e0a559aef53243f0126958be9800b2c092403a84`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 351 Ordinary Direct-Media Delete-for-Everyone Custody deleteMessageForEveryone dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact dbStageOutgoingDirectTextMutationInboxCustody dbCompleteAcceptedDirectMutationInboxCustodyIfExact stageIncomingDirectMediaBlobCustody commitIncomingDirectMediaBlobLocalPath" --profile tdd --budget 700`.
- Anchors: `dbStageOutgoingDirectTextMutationInboxCustody`, `dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact`, and `stageIncomingDirectMediaBlobCustody`.
- Surfaced proof candidates: the existing v109 helper test and core/host `1to1` registration; direct source search supplied the cross-owner v108/v111 state matrix, handler race, filesystem failure and gate details that the compact graph did not connect.
- Reuse rule: implementation and review must verify current source at execution HEAD; the graph is a shortlist, not authority.

## Scope Contract And Guard

In scope:

- Start only after the separate GAP-N01 checkpoint session has finished and left a clean handoff. Record the actual clean HEAD and preserve any later checkpoint commit; do not reset back to the planning baseline or rerun its wave-level `host-all` as a Plan 351 gate.
- Adopt only newly authored delete-for-everyone for an outgoing, ordinary, one-to-one media/voice parent whose persisted direct attachment set proves strict lineage. Keep caption EDIT, attachment replacement and every non-delete mutation out.
- Select the lane from current DB state, never `ConversationMessage.media` alone. One narrow existing-repository selector/stager may distinguish: no direct attachments (Plan 349 text path), complete strict direct attachments (Plan 351), complete historical/no-fingerprint direct attachments with no v111 and either no v108 or one exact unbound v108 (existing legacy media path), and contradictory/mixed state (refuse). Selection is advisory only; the staging transaction repeats every predicate.
- Preserve historical ordinary media without promoting it. A proven all-null-fingerprint/no-v111 media parent may atomically stage its existing legacy tombstone and keep legacy transport when v108 is absent or exactly one historical unbound initial row exists with null blob manifest/expiry. Preserve that v108 unchanged. Mixed fingerprints, a manifest-bearing or ambiguous v108 without v111, partial/cross-owner rows, or any strict owner contradiction fail closed; there is no fallback after strict selection.
- Mint one deletion UUID and reuse Plan 349's existing outer/inner identity only after the strict lane is selected. The exact encrypted deletion envelope and raw event ID enter physical v109 unchanged. Do not change `MessageDeletionPayload`, receipts, `direct_mutation_v109`, relay dedupe, ACK proof, or mixed-version policy.
- Add one narrow media-owned deletion staging capability under the existing message-wide media lifecycle lock. It composes current-parent/physical-attachment qualification, the v108/v111 state transition, `dbStageOutgoingOrdinaryAttemptWithinTransaction`, and exact v109 insert in one `dbWriteTransaction`. Factor/reuse transaction bodies; never nest the current public transaction wrappers or copy their CAS logic.
- Keep Plan 349's shared v109 lifecycle owner. A tiny shared load/failure/completion interface may be extracted from the text-stage capability so both text and media deletion use the same drain; do not mass-rename v109 files/table/migration or build a generic event framework.
- Apply this exact outgoing strict-media state matrix inside the stage transaction:

| Current authority | Atomic Plan 351 result |
|---|---|
| One exact v108 media incarnation plus a complete bound v111 `outgoing_stored` generation matching its manifest/earliest expiry | Stage tombstone + exact v109; preserve v108 and every v111 row. |
| No v108 plus one complete unbound active v111 generation in its permitted prepared/stored states | Transition the complete generation to `outgoing_cleanup_pending` and stage tombstone + exact v109. |
| No v108 plus only cleanup-pending rows for that one generation, including a subset left after physical cleanup | Stage tombstone + exact v109; preserve remaining v111 cleanup rows. |
| No v108 and v111 fully absent, with one or more remaining physical direct attachments whose every row retains a valid strict commitment fingerprint | Stage tombstone + exact v109. |
| All physical direct attachments have null fingerprints, v111 is absent, and v108 is absent or one exact historical unbound row with null blob manifest/expiry | Atomically stage the unchanged legacy tombstone; preserve v108 if present; create no v109 and retain legacy transport. |
| Bound v111 without its exact v108; non-media/ambiguous v108; incomplete/crossed generation; active mixed with cleanup; incoming rows; mismatched incarnation/manifest/expiry; mixed/missing strict fingerprints | Refuse atomically: no parent, v109, v111, attachment status, cleanup, reaction, key/file, or network mutation. |

- Whenever v111 rows exist, recompute each row's exact commitment fingerprint and require it to match the corresponding physical attachment; a different but well-formed 64-hex fingerprint is a contradiction. When v111 is fully absent, the persisted nonblank fingerprint is only the bounded strict-lineage marker needed to choose deletion custody; this plan does not reconstruct expired blob proof from it.
- Check exact replay before shared v109 capacity. Exact same `(recipient,eventId,envelope)` is idempotent without replaying an older parent projection; a changed-envelope collision, capacity refusal, injected insert fault or parent drift changes neither the tombstone nor v111.
- Move only this lane's node-not-running decision after encryption and atomic stage. Once stage authorizes, attempt the same best-effort reaction/attachment/file/key cleanup even when the node was stopped, then return with v109 retained and zero network. Schedule the existing non-throwing mutation hedge beside the current running-node live race. A live ACK must not cancel v109, and protected acceptance must not wait for or rewrite v108/v111.
- Generalize mutation completion for an exact deletion envelope: attachment presence/absence cannot invalidate terminal deletion settlement, because exact v109 stage already owns the event and cleanup may run before protected acceptance. Settle at most one exact current tombstone to existing visible `inboxed` semantics and retire the exact v109 row atomically. Media EDIT remains refused; a newer/delivered/removed parent is preserved exactly as Plan 349 defines. Do not invent an unpersisted claim that completion can distinguish a text-staged deletion from a media-staged deletion.
- Keep failed/unacked and lifecycle retry on the existing v109 owner. Both load-time and pre-egress checks must suppress rebuild, re-encryption, media re-upload and legacy inbox fallback for a retained Plan 351 event. The composite drain keeps v108 before the single fair v109 batch when both initial and deletion obligations coexist.
- Add one no-schema incoming current-deletion transaction beside `MessageRepository`. After existing event/sender/contact authentication, it re-reads the target and physical media inside SQLite: absent target creates the ordinary tombstone; matching ordinary text or strict-media target becomes the tombstone; exact replay or an already-newer deletion is durable supersession; an older event never replaces a newer tombstone; outgoing/private/cross-sender/ambiguous state refuses. Current event-bearing text deletion may reuse it; legacy payloads retain their current Plan 349 paths.
- Extend strict incoming media stage with one typed durable-supersession outcome. If an exact ordinary incoming author tombstone already won, stage no attachments/v111, publish no message/media/notification, and send the initial message receipt. If initial staging wins first, deletion tombstones the parent while retaining incoming v111 for source ACK or expiry. Both commit orders converge after restart.
- Close the existing direct-display marker race through its current owner, not a new notification pipeline: message-marker staging must transactionally refuse/no-op when the exact parent is already tombstoned, while the incoming deletion transaction reuses the existing message-scoped display deletion body to retire pre-existing direct display entries for that target. Missing marker after a crossed promotion load/CAS is durable retirement, not an exception. The handler must treat either tombstone winner as durable supersession and return no stale hydrated initial/stream event. This is an N01 deletion-order guard only; it does not implement GAP-N03 outcome acknowledgement, presentation policy or OS-notification cancellation.
- Treat the tombstone as durable deletion/cleanup authority. Mutation receipt is sent only after the tombstone transaction is durable; exact replay may re-mint it. Duplicate deletion re-drives existing best-effort reaction/attachment/file/key cleanup before/alongside receipt, but cleanup failure does not revoke durable deletion or block its receipt.
- Block post-delete media resurrection: strict local-path commit and generic incoming attachment save refuse an exact tombstone; a download that has already promoted plaintext deletes only its just-written canonical file when DB commit loses; bootstrap does not redownload `incoming_committed` under a deleted parent; `incoming_ack_pending` can still source-ACK without attachment rows; expiry still removes either incoming state; strict message publication and notification-display custody re-read/suppress a tombstone that wins after strict DB stage but before either callback.
- Use existing lifecycle locks and DB transactions only. Do not add a listener mutex, event ledger, deletion journal, cleanup queue, startup scanner or new phase.

Must preserve:

- Plan 349 ordinary direct-text EDIT/delete staging, relay kind, receipt correlation, retry behavior and receiver concurrency.
- Plan 342/345/347/348/350 initial v108/v110/v111 custody, including historical unbound v108 rows, exact artifact/manifest/expiry identity, fresh/external/internal-forward adopters and default-off selectors.
- Direct reaction ADD/REMOVE capacity, fair ordering and completion in the same physical v109 table.
- Exact live-v108 completion after a user tombstone: it retires only its initial incarnation, leaves the tombstone, and moves bound v111 to cleanup.
- Legacy/no-fingerprint direct-media delete behavior without historical promotion; private/protected/view-once/disappearing, group/announcement and local delete-for-me remain on their current owners.
- Existing source-pinned incoming ACK and expiry semantics; a deletion receipt is not a blob ACK and never deletes v111.

Hard `Do not`:

- Do not add DB v112, a table, column, index, foreign key, persistent media-delete kind, second outbox, filtered drain, scheduler, isolate, WorkManager job, flag, metric family or protocol action.
- Do not change Go relay/node/bridge, Dart custody kind, encrypted deletion wire, receipt wire, provider payload, Android bindings or iOS/platform code.
- Do not combine caption EDIT, media replacement/re-upload, private/disappearing deletion, groups/announcements, linked-device fanout, historical backfill, production activation, quota/UX, GAP-N02/N03 outcome work or release work. The bounded existing direct-display marker guard above is not authorization to expand notification behavior.
- Do not terminalize/delete v111 before the tombstone+v109 commit, delete a live exact v108, treat message delivery receipt as blob ACK, or perform file/key/reaction/attachment cleanup before stage authorization.
- Do not claim crash-complete local artifact erasure. A residual inaccessible file/key after a crash within existing best-effort cleanup remains explicit storage-hygiene follow-up; adding durable cleanup infrastructure requires a separate authority/lifetime case.
- Do not run per-plan full `host-all`, a device campaign, SQLCipher migration proof, Go/relay packages, gomobile binding build or iOS harness. No boundary in this plan justifies them.

## Test Contract

| ID | Behavior / invariant | First RED and fixture | GREEN oracle | Mutation / false-positive guard | Registration / tier |
|---|---|---|---|---|---|
| TC-351-01 | Strict ordinary direct-media delete atomically stages exact tombstone + raw-event v109 before network | Add real-SQLite cases to `media_attachments_db_helpers_test.dart` and `media_attachment_repository_impl_test.dart`; current split terminalizes v111 then text v109 refuses physical media. Include missing/throwing selector/stager capability, lane drift between selection and commit, injected failure immediately before v109 insert and post-commit publication fault. | Complete fingerprinted parent/attachments and exact envelope produce one tombstone + one v109 or no change; no network/cleanup observes pre-authority; idempotent replay preserves winner; commit survives publication error. | Reorder terminalization before transaction, trust the UI snapshot, accept partial fingerprint, fall back after strict selection, or call live/legacy store before v109 -> RED. | Exact focused; helper AUTO core, repository AUTO feature/non-host 1:1; no new file/registration. |
| TC-351-02 | v108/v111 state matrix preserves the independent initial/blob owner and refuses contradictions | Extend `media_attachments_db_helpers_test.dart`, `direct_reaction_inbox_custody_outbox_db_helpers_test.dart`, `direct_inbox_custody_outbox_db_helpers_test.dart`, and the existing `DirectMediaBlobCustodyDrain` cases in `media_attachment_repository_impl_test.dart` with every matrix row, capacity/collision and a v108-before-v109 lifecycle ordering sentinel. Include a well-formed 64-hex attachment fingerprint crossed with another extant v111 commitment. | Exact live v108 preserves bound v111; absent-v108 active generation becomes cleanup atomically; cleanup subset/fully-drained fingerprint lineage stages; proven historical unbound v108 stays legacy; every crossed state changes nothing. Later v108 completion preserves tombstone and transitions v111 once. | Unconditionally reject/promo a historical v108, cancel exact v108, terminalize bound v111, trust fingerprint shape without recomputing extant v111, accept bound-without-v108/mixed active-cleanup, or split parent/v111/v109 commits -> RED. | Existing helper/repository files; v108/v109 helpers are in both 1:1 inventories; AUTO core/feature covers shared changes. |
| TC-351-03 | Authoring, protected completion and retry retain one media deletion event without fallback | Extend `delete_message_use_case_test.dart`, `message_repository_impl_test.dart`, `drain_direct_reaction_inbox_custody_outbox_use_case_test.dart`, `retry_failed_messages_use_case_test.dart` and `retry_unacked_messages_use_case_test.dart`. Cover node-off, live ACK, full/rejected/nonproof store, accepted completion with attachment rows present/absent, and owner winning between initial lookup and egress. | Node-off leaves exact v109, attempts cleanup only after stage, and performs zero network; live result never cancels custody; only stored/duplicate proof retires it; completion settles exact tombstone atomically; failed/unacked never rebuild, upload or legacy-store an owned event; media EDIT stays excluded. | Skip cleanup on handled node-off, clean before stage, delete hedge on live ACK, allow legacy fallback, use mutable parent bytes, reject completion merely because attachments exist, or broaden to caption edit -> RED. | Delete/drain/unacked are host/non-host 1:1; retry-failed and repository run focused + AUTO feature. |
| TC-351-04 | Current incoming deletion and strict initial converge to one durable tombstone in both commit orders and after reopen | Add barrier-backed real-SQLite cases to `messages_db_helpers_test.dart`, `handle_incoming_message_deletion_use_case_test.dart` and `handle_incoming_chat_message_use_case_test.dart` using the existing real DB fixture. Add the exact direct-display DB/owner cases to `107_direct_notification_durability_test.dart` and `direct_notification_display_outbox_wiring_test.dart`. Force strict DB commit -> deletion commit -> display stage/publication, marker stage -> deletion commit, and deletion between marker promotion load/CAS in addition to the two initial/delete transaction orders. | Deletion-first creates tombstone; later strict initial returns durable supersession, sends its receipt, and creates no attachment/v111/UI/notification. When deletion wins after the strict DB commit but before display/publication, publication returns a typed suppressed/durable-supersession disposition (or equivalent non-throwing result), no stale marker/stream/hydrated initial is produced, and the handler still sends exactly one initial-message receipt. Initial-first stages exact incoming v111; deletion commits tombstone, sends event-aware receipt and retains v111. Display-after-delete cannot insert/promote a marker; delete-after-marker retires it before readiness; a crossed promotion observes durable retirement without throwing. Reopen preserves tombstone and neither order resurrects it. Capability absence/throw fails closed for current events. | Keep pre-read text/media routing, generic save fallback, send receipt before commit, let publication throw after durable supersession and thereby suppress the initial receipt, treat deletion-first as rejected, leave/recreate a direct display marker, throw on crossed marker retirement, publish/return a stale initial, or serialize only listeners -> RED. | Messages/chat/deletion files already in both 1:1 inventories; display helper/owner run exactly and remain AUTO core/feature/non-host 1:1; no new file. |
| TC-351-05 | Download/save/cleanup work cannot recreate media after the tombstone while v111 independently ACKs or expires | Adapt TC-347 download barriers in `download_media_use_case_test.dart`; extend media helper/repository and bootstrap phase tests. Include duplicate deletion, canonical-file promotion followed by losing DB commit, generic-save secure-key compensation, deleted-parent startup retry, incoming-ACK-pending without attachment and expiry. | Deleted/hidden parent rejects local-path commit and generic attachment save; losing download removes only its candidate canonical file; no preview/notification publishes; duplicate deletion re-drives cleanup; `incoming_committed` is not redownloaded under tombstone; ACK-pending and expiry converge from v111 alone. | Return false while leaving canonical file, allow incoming generic save, skip duplicate cleanup, block source ACK because attachment vanished, or delete v111 with the deletion receipt -> RED. | Download is in both 1:1 inventories; helper/repository/bootstrap run exact + AUTO core/feature. No device. |
| TC-351-06 | Adjacent and excluded lanes remain unchanged | Run existing Plan 349 text mutation/receipt/race tests; Plan 347 strict receive/ACK/expiry and v108 completion tests; reaction fair-drain; all-null-fingerprint historical media with absent and exact unbound v108; private/disappearing; group and delete-for-me sentinels. | DB stays v111, physical v109 unchanged, historical v108 remains exact and unpromoted, selector/admissions remain off, and every excluded lane retains its prior owner/behavior. | Add schema/wire/flag, promote or strand history, cancel v108/v111, alter reaction order, or route private/group/caption edit into the new stage -> sentinel RED. | Existing curated/AUTO files and completeness check; no new manual registration. |

### Test Notes

- TC-351-01/02 use physical direct attachment rows and fingerprints. An in-memory `ConversationMessage.media` assertion is not causal evidence for this plan.
- TC-351-02 treats a partially drained cleanup generation as the remaining subset all in `outgoing_cleanup_pending`; it does not authorize a partial active generation or mixed active/cleanup state.
- TC-351-02's historical row is compatibility-only: an exact unbound v108 continues its original lifecycle while the deletion remains on legacy transport. It is never relabeled strict or copied into v109.
- TC-351-03 reuses the exact Plan 349 deletion envelope and protected kind. No Go/relay test is repeated because the wire/backend boundary is unchanged.
- TC-351-04 must force both SQLite commit orders. A sequential handler-only test or a listener mutex cannot prove the independent-stream race.
- TC-351-05 accepts that existing best-effort cleanup may leave inaccessible crash residue. Its causal obligation is no durable-state/file-producing resurrection after the tombstone and continued v111 ACK/expiry, not a new erasure subsystem.

## Implementation Steps

1. After the other checkpoint session finishes, snapshot `git status --short` and `git rev-parse HEAD`; require a clean tree but accept its newer documented checkpoint commit. Record the outgoing TC-351-01, both receiver/display TC-351-04, and filesystem TC-351-05 causal REDs before production edits.
2. Add the narrow DB-authoritative ordinary-deletion lane selection needed to distinguish text, strict media, proven legacy media and contradiction. Repeat selection in the staging transaction; never authorize from the transient parent media list or consumed v110 intent.
3. Factor transaction-body forms of the existing v111 terminalization and v109 insertion/CAS only as needed. Add one media-owned deletion stage under `MediaAttachmentLifecycleLock.synchronizedAll` that implements the exact state matrix and commits v111 transition + tombstone + v109 together. Keep the proven legacy-media branch exact and unpromoted.
4. Add the smallest repository capability/result needed to expose the committed tombstone and v109 entry with best-effort publication. Reuse Plan 349's load/failure/completion owner; extract only a tiny shared mutation-lifecycle interface if the current text-stage type would otherwise leak into media code.
5. Route only qualified strict ordinary direct-media delete-for-everyone through the new stage. Mint the existing authenticated deletion event once, move node-off after stage and post-authority cleanup, start the existing mutation hedge beside running-node live delivery, and run no reaction/media cleanup before authority. Preserve text, historical media, private and delete-for-me branches.
6. Generalize exact mutation completion for deletion rows staged from strict media, regardless of whether best-effort cleanup has already removed attachment rows. Preserve exact parent/envelope CAS and keep media edits refused. Verify failed/unacked/lifecycle paths need no new retry owner; add only the shared-interface/winner guards required by tests.
7. Add one transactional incoming current-deletion capability and typed strict-initial supersession result. Route authenticated current deletion through it, keep legacy payloads on current paths, and use committed disposition for receipts/publication. In that transaction, retire the existing direct message display marker for the target.
8. Reuse the direct-display DB owner to make message-marker staging conditional on the exact non-tombstoned parent. Make strict publication return a typed suppressed/durable-supersession disposition (or equivalent non-throwing outcome) when the tombstone wins, so the handler suppresses stale UI/notification but still emits the initial receipt. Add tombstone checks to strict local-path commit, generic incoming attachment save and startup retry. When canonical plaintext promotion loses the DB commit, delete that exact candidate. Re-drive existing best-effort cleanup on duplicate deletion without turning cleanup success into receipt authority.
9. Extend only existing tests/fixtures and current production bootstrap delegates. Add no new test harness or manual gate row. Keep schema/migration/protocol/account-transfer tests unchanged as sentinels.
10. Run the focused, preservation, completeness, host `1to1`, justified core/feature families and hygiene commands below. Refresh Graphify once after coherent implementation changes. Update Plan 351/index/coverage receipts and append `EXECUTION_COMPLETED` only in the implementation session after every required gate passes.

## Risks And Blind Spots

- UI snapshots omit or stale media authority -> DB selection plus repeated transaction qualification in TC-351-01/02.
- A normal delivered media initial still owns v108 -> explicit coexistence row and later v108-completion proof in TC-351-02.
- Split v111 terminalization and v109 insert could lose deletion -> injected rollback and no-precommit cleanup/network in TC-351-01/02.
- Shared v109 completion could stay text-only or accidentally admit caption edit -> attachment-present/absent deletion completion plus media-edit refusal in TC-351-03.
- Retry may rebuild from the mutable tombstone after owner lookup -> load and pre-egress winner barriers in TC-351-03.
- Independent initial/delete streams can cross stale reads -> two-order SQLite barriers and restart in TC-351-04, not a process lock.
- Direct display staging sits between strict commit and publication -> conditional marker stage plus deletion-side marker retirement in both barrier orders in TC-351-04.
- Download or generic save can recreate a path/key after delete -> promotion/commit barrier, candidate deletion and secure-key compensation in TC-351-05.
- Cleanup failure could be confused with deletion durability -> receipt is gated on tombstone only; duplicate cleanup re-drive and explicit residual storage gap in TC-351-04/05.
- Sibling-surface consistency -> exact text/reaction/private/group/legacy/v108/v111 sentinels in TC-351-06.
- Overengineering pressure -> no schema, protocol, new owner/drain/scheduler, cleanup journal/scanner, device harness or per-plan full `host-all`.

## Gate Cadence

- Per-plan closure: four causal RED commands; focused DB/repository/use-case/retry/receiver/download/bootstrap/direct-display tests; exact preservation sentinels; completeness; host `1to1`; `core-host-all` because shared DB/display helpers change; serial `feature-host-all` because deletion/retry/receiver/download/display-owner production changes; analyzer, changed-Dart format, diff hygiene and one Graphify refresh.
- Use `./scripts/run_host_test_gates.sh 1to1`. Do not run `./scripts/run_test_gates.sh 1to1`, because Plan 351 changes no Go/relay/native boundary and exact focused commands cover feature files not in host 1to1.
- Do not run full `host-all`. The separate checkpoint session owns the current wave-level run; WP-07/final closure owns the next full release run.
- Extend existing files only. Current delete/chat/deletion/download/messages/v109/drain/unacked tests retain both host/non-host 1to1 registration; media helper/repository/message repository/retry-failed/bootstrap remain covered by exact commands and AUTO core/feature classification. No new manual row is needed.

## Device / Relay Proof Profile

- Profile: host-only.
- Boundary being proven: same-process SQL atomicity over existing v108/v109/v111 tables, exact parent/media lifecycle transitions, file-backed restart and delete-vs-download convergence.
- Live availability check: N/A. No schema migration, platform API, native binding, relay parser/backend, provider, OS lifecycle or device-specific behavior changes.
- Required setup: host Flutter/Dart and existing SQLCipher/SQLite temp-file fixtures.
- Two-peer default: N/A; this is not a mobile-runtime claim.
- Closure role: required code-boundary evidence for this default-off sender/receiver slice; not production activation, notification-presentation outcome or release evidence.
- Deferred device work: the GAP-N01 dependency wave/final rollout owns aggregate Android evidence; GAP-N12/WP-07 owns the availability-bounded consolidated iOS phase.

## Acceptance Gates

```bash
# Baseline after the separate checkpoint session; tree must be clean.
git status --short
git rev-parse HEAD

# First outgoing causal RED: current code changes v111, then its text-only v109
# stage refuses the physical media parent. Expect non-zero before production edits.
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-351-01 direct-media deletion stages blob transition tombstone and v109 atomically'

# Independent receiver-order RED: expect non-zero because the absent-target
# deletion path can race strict media staging and be terminally refused.
flutter test test/core/database/helpers/messages_db_helpers_test.dart \
  --plain-name 'TC-351-04 strict media initial and current deletion converge without resurrection'

# Display-order RED: expect non-zero because message-marker staging does not
# currently qualify the parent and deletion does not retire the marker atomically.
flutter test test/core/database/migrations/107_direct_notification_durability_test.dart \
  --plain-name 'TC-351-04 tombstone and direct message display marker cannot coexist'

# Independent filesystem RED: expect non-zero because a losing post-promotion
# strict download currently leaves its canonical plaintext.
flutter test test/features/conversation/application/download_media_use_case_test.dart \
  --plain-name 'TC-351-05 delete during strict download cannot resurrect canonical media'

# Focused DB/repository/stage/completion/lifecycle GREEN.
flutter test --concurrency=1 \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart

# Focused receiver/download/bootstrap/restart GREEN.
flutter test --concurrency=1 \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/message_deletion_listener_test.dart \
  test/features/conversation/application/download_media_use_case_test.dart \
  test/core/database/migrations/107_direct_notification_durability_test.dart \
  test/features/conversation/application/direct_notification_display_outbox_wiring_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart

# Discovery, affected curated lane, justified families.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1

# Hygiene and one implementation-time architecture refresh.
flutter analyze
dart format --output=none --set-exit-if-changed $(
  {
    git diff --name-only --diff-filter=ACMR -- '*.dart'
    git ls-files --others --exclude-standard -- '*.dart'
  } | sort -u
)
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
```

## Execution Interpretation And Done Criteria

- Expected outgoing RED: v111 state changes or is consulted, but no atomic media tombstone+v109 owner can commit while direct attachments exist.
- Expected receiver RED: crossed strict-initial/deletion commits can return unauthorized/refused or let stale media publication/path state survive the deletion winner.
- Expected display RED: a message marker can stage after the tombstone or survive a later deletion and become ready for stale presentation.
- Expected filesystem RED: canonical plaintext exists after the DB local-path commit loses to a tombstone.
- Green sentinel: Plan 349 text/reaction/receipt/retry behavior, Plan 347 initial/blob/ACK/expiry behavior, exact v108 completion, historical media, private/disappearing/group and delete-for-me remain unchanged.
- Pre-existing dirty tree / known failure: none at planning baseline. The separate checkpoint session may create a newer clean documentation/evidence commit; that is an expected dependency, not Plan 351 scope. No baseline test failure is accepted.
- Environment blocker: none. Host real SQLite/filesystem barriers prove every changed boundary; unavailable mobile/iOS hardware is N/A by project policy.
- Scope drift: any schema/protocol/native/platform change, cleanup journal/scanner, caption edit/private/group adoption, new retry/drain/flag, device requirement or per-plan full `host-all` stops execution for re-review.

- [ ] Strict media deletion commits the exact v111 state transition, tombstone and v109 event atomically before network; every refusal changes none. -> TC-351-01/02.
- [ ] An exact live v108 and bound v111 survive deletion and later complete independently without resurrecting the parent. -> TC-351-02.
- [ ] Node-off/live/restart/protected acceptance/failed/unacked paths retain and retire only the exact media deletion event with no legacy fallback. -> TC-351-03.
- [ ] Strict initial and current deletion converge to one tombstone in both SQLite commit orders and after reopen; a post-stage deletion suppresses stale publication without throwing and still produces exactly one initial receipt. -> TC-351-04.
- [ ] Local-path commit, generic save, startup retry and publication cannot recreate media after delete; incoming v111 still ACKs or expires. -> TC-351-05.
- [ ] Adjacent lanes, schema v111, physical v109, default-off controls and gate ownership remain unchanged. -> TC-351-06.
- [ ] Causal REDs, focused GREEN, at least one representative stage-order mutation re-red, completeness, host `1to1`, core/feature families, analyzer, format, diff and one Graphify refresh are recorded.
- [ ] No activation, GAP-N01 closure, crash-complete erasure, device/iOS, per-plan full `host-all` or release claim is made.

## Handoff

- First causal RED commands: the four exact outgoing, receiver-order, display-order and filesystem commands above.
- Preservation command: the focused batches plus host `1to1`; retain exact Plan 349/347 tests in their existing files instead of creating a duplicate matrix.
- Manual registration: none; implementation should extend existing registered/AUTO files.
- Migration: none; DB remains v111 and physical v109/v111 schemas remain byte-compatible.
- Boundary closure: host application + real SQLite/temp filesystem. No Go/native/relay/device/iOS leg.
- Deferred owner: existing best-effort local deletion cleanup owns ordinary artifact removal; crash-complete inaccessible residue is explicit storage-hygiene follow-up, not Plan 351 custody acceptance.
- Dependency: the other session's GAP-N01 checkpoint/full-host evidence must finish first; Plan 351 does not repeat it.

## Reviewer Findings

`$tdd-review` initially returned `REQUEST_CHANGES` for three concrete blind spots: notification-display custody could outlive a deletion winner; an upgraded all-null-fingerprint media row with an exact unbound v108 had no explicit compatibility outcome; and a merely well-formed fingerprint could be crossed with a different v111 commitment. The plan now makes display staging parent-conditional, retires an existing message marker in the deletion transaction, preserves the exact historical v108 on the legacy path, and requires recomputed v111/physical-attachment fingerprint equality with a crossed-valid-fingerprint mutation.

Targeted re-review found one final receipt-order counterexample: throwing from strict publication after a deletion superseded a committed initial could prevent the initial receipt. TC-351-04 and Step 8 now require a typed nonthrowing durable-supersession outcome (or equivalent), no stale marker/UI publication, and exactly one initial receipt. The independent final verdict is `READY`; no tests were run because this is a planning/review session.

## Arbiter Decision

`READY / EXECUTION_READY`. The core bet is confirmed: reuse unchanged physical v109/v111 with one atomic outgoing strict-media deletion transaction, then close only the incoming tombstone/display/download resurrection boundaries exposed by that adoption. The plan is sufficient without a schema, protocol, native binding, cleanup journal, scheduler, new drain, device campaign, iOS harness or per-plan full `host-all`. Execute only after the concurrent GAP-N01 checkpoint session has finished and left the documented clean handoff; do not implement in this planning session.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-09 | execution not started | planning artifacts only | `$tdd-plan` + fresh `$tdd-review`: READY | Source-grounded six-row causal contract, four causal REDs, proportional gates, independent review and final arbitration complete; no implementation or tests run | implementation must wait for the separate checkpoint session's clean handoff | execute the reviewed plan in a different session, then append `EXECUTION_COMPLETED` only after its required evidence passes |
