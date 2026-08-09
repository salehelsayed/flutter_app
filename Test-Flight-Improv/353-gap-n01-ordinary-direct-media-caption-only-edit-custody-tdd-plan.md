# 353 - GAP-N01 Ordinary Direct-Media Caption-Only EDIT Custody

Status: **IMPLEMENTED / DEFAULT-OFF CODE-CLOSED / PLAN-GREEN / HOST GATES GREEN / NOT STANDALONE RELEASE-ELIGIBLE** (2026-08-09)
Type: Modification
Baseline observed while planning: ac6eba539410f280cd7b37cfd81907be8ce1fa4f (feat: preserve direct-media delete custody past v111 drain)
Spec: UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md requirements 1, 3, and 6 plus A-01/A-02/A-03/A-24/A-26; gap inventory UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md GAP-N01 / WP-01 / section 9.2
Classification: execution-ready; bounded adoption of the existing v109 mutation owner and v111 lineage; core bet confirmed by tdd-review
Closure tier: host real-SQLite/application proof plus affected curated/core/feature families; no schema, relay, native, mobile, or iOS claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-09 | Evidence Collector | PRD economy guardrails; GAP-N01/WP-01; Plans 349/351/352; send/edit path; v109 stage/completion/drain/retry; v108/v111/fingerprint lineage; incoming strict-media stage and edit ordering; current tests/gate ownership | Confirmed the user-reachable ordinary direct-media caption EDIT still takes mutable legacy custody. It already has an authenticated event ID, while physical v109 and strict media lineage can represent the obligation without another table or wire kind. | Define the smallest exact attachment-preserving sender/receiver crossing. |
| 2026-08-09 | Planner | Outgoing live-v108 and post-drain states; UI-snapshot drift; edit-before-initial behavior; deletion precedence; event-aware receipts; mixed-version fallback | Reuse one raw-event v109 row, the existing media lifecycle lock, persisted attachment/v111 authority, and the retryable recovered-inbox disposition. Keep the proof-less media EDIT wire shape; do not reconstruct blob commitments, persist a second placeholder authority, or upload bytes. | Write the causal contract and proportional run/not-run gates, then invoke tdd-review. |
| 2026-08-09 | Independent Reviewer | Full draft; sender qualification/stage/completion; direct-delivery lineage; raw/secure key boundary; receiver classification/defer/receipt; literal tests and gates | Core bet confirmed but draft required bounded fixes: do not materialize an unprovable hidden caption; canonicalize persisted parent/media before caller gates; hydrate keys outside SQL; preserve normal direct-delivery lineage; reuse the Plan 352 helper; tighten receiver matrices; remove duplicate drain/retry testing. Verdict: PLAN-FIXES-REQUIRED. | Apply deltas and run targeted fresh re-review before handoff. |
| 2026-08-09 | Targeted Reviewers | Amended delivered-successor predicate; outgoing and incoming state matrices; exact v109 completion; failed/unacked bypass; edit-before-initial/tombstone ordering; mixed-version legacy row; literal gates | All required deltas are closed: full canonical delivery shape, direct fingerprint RED, exact incoming states, no-write nondeleted deferral, tombstone precedence, event-bearing legacy compatibility, and two narrow retry-owner sentinels. Duplicate retry commands were removed. Final verdict: READY. | Hand the reviewed plan to the arbiter; do not implement in this session. |
| 2026-08-09 | Arbiter | Final scope, six causal REDs, preservation set, run/not-run cadence, stop conditions, and user-requested anti-overengineering boundary | Existing v109/v108/v111 authority is sufficient. The eight-file production boundary and host-only affected-family cadence are proportional; no schema, wire, relay/native, new owner, device/iOS, or full-host leg is justified. Final verdict: READY. | Append the execution-ready ledger marker for a separate implementation session. |

## Problem And Evidence

- Behavior to improve: editing only the caption/text of an already-authored strict ordinary direct-media or voice message must acquire one exact event-scoped ACK-or-expiry obligation before LAN or relay transport, survive node-off/restart, and converge on the receiver without changing the media generation.
- User impact: the UI already permits media-message edits, and every edit already mints an authenticated outer/inner `eventId`; however, sender custody is restricted to attachment-free edits. A media caption EDIT therefore uses the mutable legacy message row and evictable/legacy inbox path, so a crash, node-off send, later edit, or deletion can replace the only retry bytes.
- Existing owner to reuse: physical DB-v109 is already an opaque `(recipient_peer_id,event_id)` exact-envelope outbox with shared capacity, fair drain, exact failure/completion CAS, lifecycle retries, account transfer, protected `direct_mutation_v109` relay/native custody, and event-aware delivery receipts. No new mutation owner, kind, drain, scheduler, protocol action, or flag is needed.
- Existing media authority to reuse: v108 proves a live manifest-bound initial; v111 owns each encrypted blob commitment; Plan 352 persists each accepted attachment's one-way exact commitment fingerprint through v111 cleanup. These states can qualify the immutable attachment generation but must never be republished as `blobCustody` on an EDIT.
- Sender exclusion: `sendChatMessage` defines `ownsDirectTextMutationInboxCustody` only when there are no attachments; a proof-less media EDIT falls through generic media staging, while a media EDIT carrying reconstructed `blobCustody` is rejected. `editChatMessage` also passes the caller/UI snapshot's media list rather than loading the persisted projection.
- DB exclusion: `dbStageOutgoingDirectTextMutationInboxCustody` atomically stages parent plus v109 but refuses a parent with physical direct attachments. Exact v109 mutation completion likewise rejects an EDIT when attachments still exist, even though the event owner itself is already type-neutral.
- Receiver exclusion: a proof-less media EDIT uses non-atomic generic parent/attachment saves. An edit that arrives before its initial creates a family-agnostic hidden parent that persists neither the media descriptors nor mutation event ID. That placeholder cannot prove caption-only authority and must not become a new strict-media owner.
- Direct-delivery lineage prerequisite: the live receipt path clears an exact initial's `wire_envelope` when it commits `delivered`. Later v108 acceptance still proves the complete bound v111 generation but Plan 352 currently skips fingerprint authorship because the parent no longer projects the initial envelope; normal cleanup can therefore leave an all-null/no-v111 parent that this plan would otherwise misclassify as historical legacy.
- Named PRD risk closed by this slice: a newly-authored strict ordinary direct-media caption EDIT gains authenticated, non-evictable, crash/restart custody independent of the live path. Its event receipt follows durable apply or durable supersession; a safe retryable missing-original deferral emits no receipt.
- Genuinely new durable authority: none. The only new seams are a narrow media-repository adapter over existing v109/v108/v111 rows, a same-schema incoming conditional apply, and a narrow safe-successor extension of Plan 352's existing completion-time lineage author.
- Shortest proof: one direct-delivery lineage RED, one outgoing SQLite state/rollback matrix, one sender network-before-authority test, one existing-v109 completion test, and one receiver apply/defer race matrix plus exact adjacent-lane sentinels.

## Graph Grounding Snapshot

- Initial query/profile: `python3 graphify-arch/tdd_context.py query "Plan 353 ordinary direct-media caption-only EDIT custody: send_chat_message_use_case media edit v109 stage/completion, v108/v111 lineage fingerprint, receiver edit-before-initial and deletion race, retry and gate registration" --profile tdd --budget 700`
- Exact refinement: `python3 graphify-arch/tdd_context.py query "send_chat_message_use_case.dart ownsDirectMutationInboxCustody dbStageOutgoingDirectMutationInboxCustody applyIncomingOrdinaryTextMutation direct_reaction_inbox_custody_outbox_db_helpers.dart media attachments edit before initial" --profile tdd --budget 700`
- Result: confidence broad then anchored; architecture fingerprint `665c838645f43729` at the planning baseline.
- Primary anchors: `sendChatMessage`, `dbStageOutgoingDirectTextMutationInboxCustody`, `dbCompleteAcceptedDirectMutationInboxCustodyIfExact`, `dbStageIncomingDirectMediaBlobCustody`, and `handleIncomingChatMessage`.
- Graph omissions verified from source: the current hidden-edit persistence/defer path, post-Plan-352 lineage matrix, literal test names, and host-gate membership.
- Reuse rule: Graphify is a shortlist. Execution must verify exact symbols/test names at its clean HEAD and stop if the reviewed eight-file boundary no longer holds.

## Scope Contract And Guard

In scope:

- Only newly authored caption/text EDITs of an existing ordinary outgoing one-to-one parent whose complete physical direct attachment set is unchanged. Voice, image, video, file, GIF, marker-free and forwarded-to-contact parents use the same rule. Caller media deltas are never interpreted as attachment replacement: empty, missing, extra, reordered, or forged caller lists are ignored for a proven strict parent and the canonical DB projection is used.
- Add one narrow media-repository capability that, under `MediaAttachmentLifecycleLock.synchronizedAll`, classifies the repository-current parent before caller-derived `hasAttachments`/media gates. Its four outcomes are `notMedia` (continue Plan 349 text), `strictMedia`, `legacyMedia`, and `contradiction`; a missing capability for a persisted media candidate fails closed.
- Canonicalize the complete persisted parent contract for strict media: timestamp, createdAt, quote, dedup key, forwarding marker, policy, recipient, sender, and attachments. Non-identity caller drift is ignored; a caller target/sender mismatch refuses before key lookup, encryption, persistence, or network because the supplied recipient key cannot be safely retargeted.
- Load the physical attachment projection in deterministic `created_at ASC, id ASC` order. Hydrate its raw encryption keys under the existing lifecycle lock but outside the SQL transaction; missing/throwing/crossed hydration refuses. Convert the hydrated projection back to deterministic storage-reference expectations and recheck those rows in the staging transaction. Never access secure storage from inside SQLite.
- The exact proof-less EDIT wire descriptor is `id`, MIME, size, media type, width, height, duration, waveform, content hash, thumbnail hash, raw encryption key, nonce, and scheme. `ownerLane`, attachment timestamps, local path/status/retry/playback/bookmark fields, secure-store reference, and lineage fingerprint are local and never serialized. `blobCustody` remains absent.
- Narrowly extend exact v108 completion lineage authorship to the safe live-delivery successor: same ordinary outgoing parent/recipient, nonterminal, `status == delivered`, `wire_envelope == null`, `edited_at == null`, `relay_expires_at == null`, `custody_checked_at == null`, `transport == null || transport in {wifi, local, direct, reuse, relay, inbox}`, and the unchanged complete bound v111/incarnation/manifest proof. This is the full persisted delivered-settlement shape already accepted by the ordinary settlement CAS. Later edit/send/tombstone or malformed-settlement shapes remain excluded. Reuse one exposed transaction-body form of Plan 352's fingerprint helper rather than duplicating its proof logic.
- Define strict outgoing states precisely: (a) exact live manifest-v108 plus complete bound outgoing-stored v111 with all-null or all-exact fingerprints; (b) no v108 plus a complete cleanup-pending v111 generation with all-null or all-exact fingerprints; (c) no v108 plus a cleanup-pending subset only when every physical attachment already has its exact fingerprint; or (d) no v108/v111 and every physical attachment has its exact fingerprint. Complete all-null strict states are stamped; mixed null/exact state is contradiction.
- Keep `legacyMedia` only for the exact pre-353 all-null/no-v111 historical shape, with absent or exact unbound v108. Active unbound v111, manifest-v108 with missing/partial v111, crossed v108 recipient/incarnation/manifest/envelope, mixed/crossed fingerprints, partial attachments, private/terminal/foreign/ambiguous state, or any invalid secure key is `contradiction`.
- After full prevalidation and inside one SQLite transaction, commit the exact parent caption/monotonic editedAt/envelope plus the existing edit-attempt transport projection (`status = sending`, `transport = null`, `relay_expires_at = null`, `custody_checked_at = null`), any provable null-to-exact lineage stamps, and one raw-event-ID v109 row. Preserve every other parent field and every v108/v111/blob/attachment field. Write order inside the transaction is not prescribed; any late CAS/insert failure throws and rolls everything back.
- Exact event replay is checked before shared capacity and never reapplies an older parent. Edit A, edit B, and deletion coexist as independent v109 events; replaying A after B/deletion returns its exact owner without regressing the current parent. A different envelope under the same raw event ID refuses atomically.
- Tighten Plan 351's existing deletion classifier only for the new reachable impossible state: a manifest-bearing live v108 with no v111 remains contradiction even when attachments are fingerprinted. With valid transitions, v108 retirement and v111 cleanup are atomic, so no legitimate row uses that shape.
- Generalize sender mutation ownership checks from text-only to exact v109-owned mutation where needed: node-off staging, scheduled non-awaited inbox hedge, protected kind selection, local failure retention, accepted completion, and live-success behavior. Use the existing `DirectMutationInboxCustodyLifecycleRepository` for media completion/failure; do not couple this adopter to the text staging capability. A live ACK never cancels the staged hedge.
- Let exact v109 completion settle and retire an already-staged media EDIT whether physical attachments still exist or were later locally evicted. Stage-time authority is decisive; completion must not mutate or require v108/v111/attachment rows and must preserve a newer edit/deletion parent.
- On receive, route only a Plan-353 candidate—ordinary, nonempty proof-less media EDIT with exact v2 outer/inner event-ID parity—before the current generic missing/stale/deleted branches. Capability absence is fail-closed/retryable. Preserve v1/eventless legacy media EDIT behavior unchanged.
- For a live incoming parent, classify `strict` only when all attachment fingerprints are exact and extant incoming v111 rows are absent or an exact subset whose state is exactly `incomingCommitted` or `incomingAckPending`. An exact v2 event-bearing candidate over a live all-null/no-v111 legacy parent resumes the unchanged generic media-edit path and emits its existing event-aware receipt only after that durable apply. Mixed fingerprints, missing/extra/crossed v111 or attachment descriptors, every outgoing/wrong-direction state, wrong commitment, or ambiguous state refuses with no generic fallback.
- Under the media lifecycle lock, hydrate/compare actual persisted keys outside SQLite, then transactionally CAS the storage-reference attachment projection and current parent. Validate the ID-keyed immutable wire set plus parent timestamp/quote/dedup/forward/author/peer/ordinary policy before edit ordering. Update only text and editedAt; preserve status, transport, read/lifecycle fields, every attachment, and v111. Deletion may supersede without attachment availability; validated older/newer edits never regress the DB.
- Classify an exact author tombstone before hidden/missing handling: it is durable supersession and emits the exact event receipt. If a Plan-353 candidate observes an absent or hidden **nondeleted** original, bypass the family-agnostic placeholder save: make zero canonical DB/display/receipt changes, return `editMissingOriginal`, and retain the exact staged envelope through the existing retryable disposition. Strict initial staging stays unchanged. After initial commit, retained EDIT replay validates descriptors, applies once, and then emits its exact mutation receipt.
- Receipt matrix: applied, exact replay, validated older/newer supersession, or author-tombstone supersession emits the exact mutation-event receipt only after durable outcome. Missing original or refused/crossed authority emits none. Existing parent-conditional display staging and typed publication reload suppress a deletion winner; this plan claims durable DB ordering and deletion suppression, not a new cross-edit UI/notification ledger.
- Preserve the proof-less media EDIT envelope for old receiver compatibility. Plan-349-era current receivers already emit event-aware receipts on initial-first generic media edits; genuinely older receivers may emit only the legacy message-ID receipt, which the new sender ignores for event-bearing state until exact receipt or expiry.

Outgoing state matrix:

| Persisted ordinary direct-media state | Caption EDIT decision | Required result |
|---|---|---|
| No physical direct media/v111 authority | notMedia | Continue the unchanged Plan 349 text classifier/stage |
| Exact live manifest v108 + complete bound stored v111; fingerprints all-null or all-exact | strictMedia | Stamp all-null lineage in the same transaction, then caption+v109; v108/v111 unchanged |
| No v108 + complete cleanup-pending v111; fingerprints all-null or all-exact | strictMedia | Stamp all-null lineage, then caption+v109; v111 unchanged |
| No v108 + cleanup-pending subset and all physical fingerprints exact | strictMedia | Caption+v109 only; extant v111 unchanged |
| v108/v111 absent after cleanup and all physical fingerprints exact | strictMedia | Caption+v109 only |
| All fingerprints null, no v111, and absent or exact unbound historical v108 | legacyMedia | Preserve exact legacy EDIT; no v109 promotion/backfill |
| Every mixed, partial, crossed, active-unbound, manifest-v108-without-complete-v111, key-invalid, foreign, terminal, or ambiguous shape | contradiction | Fail before encryption/network and change nothing |

Must preserve:

- Plan 349 ordinary direct-text EDIT/delete ownership, raw event IDs, one fair v109 drain, event-aware receipts, historical exact fallback, and concurrent receiver convergence.
- Plans 347/352 exact initial/blob ownership, v108 completion, per-attachment fingerprint authorship, source ACK/expiry, cleanup, retry, and post-drain delete lineage.
- Plan 351 strict media delete-for-everyone classification/staging/completion, deletion dominance, display/download resurrection guards, and node-off behavior.
- Existing legacy media EDIT behavior for exact historical all-null/no-v111 rows and v1/eventless receive compatibility; ownerless pre-353 event-bearing media edits remain indistinguishable and keep exact legacy retry with the existing pre-egress owner recheck. No retry-time promotion or provenance marker is added.
- Private/protected/view-once/disappearing, group/announcement, incoming/outgoing ownership boundaries, default-off client/relay admissions, mixed-version shadows, capacity, and account transfer.

Hard do not:

- No DB v112, table/column/index, new outbox, event kind, custody kind, drain, scheduler, retry queue, receipt ledger, protocol field, blob commitment reconstruction, expiry extension, re-encryption, upload/download, or new rollout flag.
- No media add/remove/replace/reorder semantics: the caption API ignores caller attachment deltas and always uses the proven persisted set. No caption history, per-edit blob lifetime, local artifact cleanup, historical scan/backfill/promotion, private media, group/announcement, linked-device fanout, activation, quota/UX, or notification-outcome redesign.
- Do not broaden `dbStageOutgoingDirectTextMutationInboxCustody`; retain its text-only contract. Add one bounded media-owned stage and reuse the physical v109 helpers/lifecycle.
- Do not use the UI `ConversationMessage.media` or other caller snapshot fields as authority, add a persisted media-edit proof, or serialize local fingerprints/paths/status into the wire envelope.
- Do not add a listener mutex, process queue, generic mutation framework, new hidden-placeholder model, or strict-initial materialization rule. Reuse the existing SQLite lifecycle lock, retryable disposition, conditional transactions, and typed publication result.
- Stop for re-review if implementation needs a migration, relay/native/bridge edit, new durable owner, public wire change, additional scheduler, or production files outside the reviewed bounded seam without a demonstrated correctness dependency.

Expected production boundary:

1. `lib/features/conversation/application/send_chat_message_use_case.dart`
2. `lib/features/conversation/domain/repositories/media_attachment_repository.dart`
3. `lib/features/conversation/data/repositories/media_attachment_repository_impl.dart`
4. `lib/core/database/helpers/media_attachments_db_helpers.dart`
5. `lib/core/database/helpers/direct_inbox_custody_outbox_db_helpers.dart`
6. `lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart`
7. `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
8. `lib/app/bootstrap/production_application_bootstrap.dart`

## Test Contract

| ID | Level / fixture | Arrange | Act | Assert | HEAD RED / mutation power |
|---|---|---|---|---|---|
| TC-353-01a | Core real SQLite; extend `direct_inbox_custody_outbox_db_helpers_test.dart` | Seed an exact strict ordinary initial with two distinct bound v111 commitments. Let a direct receipt CAS the parent to delivered and clear its envelope before protected v108 acceptance. Include later edit, tombstone, crossed recipient, and separate malformed successor mutations for nonnull `relay_expires_at`, nonnull `custody_checked_at`, and unsupported `transport`; retain every supported/null transport row. | Complete the exact accepted v108, inspect both attachment fingerprints directly, physically drain v111, and optionally run the already-existing Plan 351 delete classifier. Do not call the new caption classifier in this test. | Only the full canonical delivered-settlement shape receives both exact fingerprints in the existing completion transaction; parent remains delivered/envelope-null with its valid settlement fields; v108 retires, v111 cleans up, and the fingerprints survive physical drain (so the existing delete classifier remains strict). Later edit/tombstone/crossed/malformed shapes skip authorship and preserve their current completion outcome. | HEAD directly exposes null fingerprints after completion, independently of any new caption API. Keeping the old `stillProjectsOwnedAttempt`-only predicate or accepting a malformed delivered projection re-reds. |
| TC-353-01b | Core real SQLite; extend `media_attachments_db_helpers_test.dart` | Parameterize not-media, exact live-bound-v108, complete cleanup-pending all-null/all-exact, exact-fingerprinted cleanup subset, fully drained fingerprinted, historical all-null/unbound-v108, and every contradiction. Use two attachments with distinct commitments, tied `created_at`, edits A/B, raw-ID collision/capacity, secure storage expectations, v108-completion/deletion barriers, and a late v109-insert abort. | Qualify and stage caption EDITs A/B, exact-replay A after B, and crossed cases. | Strict rows use deterministic canonical attachments, prevalidate completely, and atomically commit only exact edit attempt fields, provable lineage, and one v109 each; v108/v111/blob fields remain byte-identical. Exact replay never regresses B/deletion. Historical stays legacy; text stays Plan 349; every contradiction/fault is all-or-zero. Manifest-v108 without v111 remains contradiction even after fingerprints exist. | HEAD has no media-caption stage. Partial validation, split transaction, duplicate fingerprint logic, parent replay regression, destructive v111 change, or legacy/text promotion stays red. |
| TC-353-02 | Feature application/repository; extend `media_attachment_repository_impl_test.dart` and `send_chat_message_use_case_test.dart` | Persist one exact strict marker-free parent and one forwarded-to-contact parent with canonical two-attachment sets. Supply null/empty/extra/reordered/wrong-ID/key/hash caller media, forged timestamp/createdAt/quote/dedup/forward/policy, and separate sender/recipient drift. Cover missing/throwing/key-drift secure store, node stopped, LAN/relay observation barriers, live ACK, admission-disabled/full/non-proof store, capability absence, historical/private, and stage refusal. | Edit blank and nonblank captions through the production authoring path. | Non-identity caller drift is ignored in favor of DB parent/hydrated media; identity drift/key failure refuses before crypto/network. The proof-less envelope has the exact deterministic wire fields and no `blobCustody`; v109 exists before LAN/relay; no blob transport runs; node-off and failed/disabled custody retain; live ACK keeps the hedge; no strict-to-legacy fallback occurs. | HEAD derives `hasAttachments` and wire media from the caller and cannot own v109. Caller-trust, secure-reference leakage, network-before-stage, hedge cancellation, or fallback mutations re-red. |
| TC-353-03 | Core v109 completion plus two narrow retry preservation sentinels | Seed an already-authorized media caption v109 event with an exact current parent, then with physical attachments present/locally absent, a newer edit/deletion/absent parent, and accepted/duplicate/full/non-proof outcomes. In the existing failed and unacked retry test files, seed the same exact event-bearing media parent/envelope and make its v109 owner exist at the initial check or win at the pre-egress barrier. Run TC-349-04 unchanged. | Complete/fail/retry the one existing event owner. | Protected acceptance settles only the exact current parent and retires only that v109 row; newer/deleted/absent parent converges without regression; attachment/v108/v111 state is irrelevant and unchanged; non-proof/full retains. In failed and unacked paths, either owner observation blocks legacy store/send/blob upload and retains or drains only the exact event as the caller mode permits. | HEAD completion rejects a current media EDIT. The two new retry tests are green-on-arrival preservation proofs over existing generic checks; attachment-dependent completion, missing initial/pre-egress check, or row-delete-before-parent settlement re-reds. No duplicate fair-drain/retry matrix is added. |
| TC-353-04 | Repository + core real SQLite + handler fixture | Seed incoming strict parents with two hydrated attachments and all-exact fingerprints plus absent or exact-subset v111 in `incomingCommitted` and `incomingAckPending`. Parameterize a live all-null/no-v111 legacy parent receiving an exact v2 event-bearing candidate; legacy v1/eventless; mixed fingerprints; duplicate/missing/extra/permuted/trailing-crossed descriptors; every outgoing/wrong-direction v111 state; wrong commitment; changed/missing/throwing/key-drift secure store; exact/stale/newer captions; both edit/delete commit orders; and deletion after edit commit before marker/publication. | Route each candidate through the production receive path. | Strict accepts exactly absent/`incomingCommitted`/`incomingAckPending` authority, applies only text+editedAt, preserves every parent transport/lifecycle and attachment/v111 field, and receipts applied/exact/validated superseded outcomes. The exact event-bearing live legacy row follows the unchanged generic media-edit apply and emits its event receipt; v1/eventless compatibility stays unchanged. Tombstone wins and receipts without attachment availability. Missing/refused sends no receipt and never falls through generic save; every outgoing/wrong-direction state refuses. Deletion suppresses display/publication. | HEAD performs generic non-atomic parent/attachment saves. Weak key/set/state proof, loss of the event-bearing legacy path, secure-store access inside SQL, strict downgrade, precommit receipt, or attachment rewrite re-reds. |
| TC-353-05 | Real-SQLite two-connection + handler/recovered-inbox fixture | Deliver edits A/B as exact Plan-353 candidates before an absent initial, repeat them before initial, cross an initial commit between qualification/apply, then replay after the strict initial; also cross an exact author deletion whose tombstone is hidden. Preserve one eventless legacy-edit placeholder sentinel. | Process edit-before-initial, initial-first, defer-then-initial, retained A/B replays, and deletion winner in both DB orders. | Plan-353 absent or hidden nondeleted original writes no parent/attachment/v111/marker and emits no receipt; repeated result remains `editMissingOriginal`/retryable. An exact author tombstone is classified first as durable supersession and emits the exact event receipt. Strict initial stages unchanged. Retained edits then validate, newest caption wins, each safely applied/superseded event receives its own exact receipt, and deletion dominates. Eventless legacy placeholder behavior remains. | HEAD creates a family-agnostic hidden placeholder. Any hidden-before-deleted branch, placeholder/materialization, sequential-only race proof, premature receipt, or lost retained edit re-reds. |
| PRES-353-A | Exact existing sentinels | Run TC-349-01/04 and generic mutation retry barriers, TC-351-02/04, TC-352-01/02/03, TC-342-03c unchanged, `editMissingOriginal -> retryable`, strict initial/blob ACK, and bootstrap closure. | Execute after TC-353 GREEN. | Text/reaction/delete/private/group/historical lanes, one fair v109 order, v108/v111 state, event receipts, and default-off wiring remain unchanged. No old exclusion assertion is weakened unless implementation proves a literal accepted difference. | Prevents caption adoption from widening adjacent mutation/blob authority or hiding compatibility drift. |

## Test Notes

- Record TC-353-01a, TC-353-01b, and TC-353-02 through TC-353-05 as six independent causal REDs before production edits. Parameterize internal rows rather than creating one test per media type or transport.
- Use physical attachment rows and real SQLite for both outgoing and incoming authority. `ConversationMessage.media`, recording fakes, or a mocked classifier alone are not causal proof.
- TC-353-01a is not historical backfill: it extends the same exact acceptance transaction only for the direct-delivery successor that was CAS-derived from the owned initial. It must not stamp a later edit/tombstone or a generic delivered row.
- TC-353-01b must force the live-v108 race both ways. SQLite transaction serialization means no internal write order is prescribed; the proof is full prevalidation, one transaction, and all-or-zero outcome.
- TC-353-02 must observe LAN and relay only after v109 staging but must not duplicate Plan 347's ciphertext/blob campaign. Caption EDIT performs no blob transport.
- TC-353-03 extends only completion causality and adds one narrow green-on-arrival owner-bypass sentinel to each existing failed/unacked retry file. Each sentinel parameterizes owner-present-at-entry and owner-winning-at-pre-egress; it does not replay the general retry matrix. The existing drain sees the same opaque outer edit kind, so TC-349-04 remains an unchanged preservation proof rather than a second fairness matrix.
- TC-353-04 compares every actual `MediaAttachment.toJson()` field by attachment ID. Hydrated raw key equality is repository proof; SQLite receives only deterministic storage-reference expectations and performs no secure-store I/O.
- TC-353-05 deliberately creates no current-event placeholder. The exact local inbox/relay row is the retry owner until an initial makes validation possible; the existing bounded quarantine remains visible rather than silently deleting the event.
- Existing ownerless pre-353 media edits are a documented compatibility ambiguity. Do not add provenance merely to distinguish a corrupt lost Plan-353 owner from one historical row.

## Implementation Steps

1. Require a clean tree at the Plan 353 execution HEAD, confirm STATUS ends with Plan 353 EXECUTION_READY and not EXECUTION_COMPLETED, and preserve unrelated user work. Record the six exact causal REDs before any production edit.
2. Expose a narrowly named within-transaction form of Plan 352's exact-lineage helper in `direct_inbox_custody_outbox_db_helpers.dart`; keep its existing caller. Extend exact v108 completion only for the fully qualified delivered/envelope-cleared/no-edit successor, and keep every terminal/superseded/crossed row on the current path.
3. Add one outgoing four-way media-caption qualification/stage and one incoming conditional-apply contract to `media_attachment_repository.dart`; wire only those closures through `MediaAttachmentRepositoryImpl` and production bootstrap. Keep existing text/deletion interfaces and physical owner names stable.
4. In the media repository, hold the existing lifecycle lock around qualification and each atomic stage/apply call, but never across envelope encryption or network. Hydrate canonical keys outside SQL, fail on missing/crossed/drifted keys, derive storage-reference expectations, and pass only those expectations into the DB transaction.
5. In `media_attachments_db_helpers.dart`, implement the reviewed outgoing/incoming state matrices and deterministic canonical attachment projection. Reuse the exposed lineage helper plus the existing shared v109 replay/capacity/insert semantics. Prevalidate before any write, commit in one transaction, re-read all changed authority, and tighten only the manifest-v108-without-v111 deletion contradiction exposed by live fingerprinting.
6. In `sendChatMessage`, consult repository-current media authority before caller-derived attachment gates, canonicalize non-identity parent/media fields, refuse identity drift, and generalize a combined `ownsDirectMutationInboxCustody` across every current text-only ownership branch. Use `DirectMutationInboxCustodyLifecycleRepository` for media completion/failure; leave text staging unchanged.
7. In exact v109 completion, remove only the media-EDIT attachment exclusion made safe by atomic stage. Preserve parent-envelope CAS, deletion handling, later-winner convergence, and attachment-independent event retirement; never inspect or mutate blob state there. Retry/drain production remains unchanged unless a causal test proves otherwise.
8. Route the exact Plan-353 incoming candidate before generic missing/stale/deleted media branches. Classify an exact author tombstone first as durable supersession with an event receipt; an absent or hidden nondeleted original returns no-write `editMissingOriginal`; strict current rows use the atomic media apply; an exact event-bearing candidate over a live legacy parent resumes the current generic media-edit path, while v1/eventless rows also keep current behavior; contradiction/capability absence fails closed. Use existing display/publication and exact event receipt only after durable disposition. Do not modify strict initial staging.
9. Run the focused TC-353 batch plus exact preservation sentinels, host `1to1` once, and only the justified dart-only core/feature family sweeps. Run analyzer, exact changed-Dart formatting, diff hygiene, and one incremental Graphify refresh. The implementation session updates Plan 353/index/coverage receipts and appends EXECUTION_COMPLETED only after every required gate passes.

## Risks And Blind Spots

- Direct delivery can clear the parent envelope before Plan 352 authors lineage -> safe delivered-successor completion proof in TC-353-01a.
- UI snapshot or stale parent can rewrite attachment identity -> four-way persisted qualification, canonical parent/media and identity-drift refusal in TC-353-01b/02.
- Secure references can compare equal while raw keys differ -> hydrated equality and prepare-to-stage key-drift barriers in TC-353-02/04.
- EDIT can race v108 completion -> shared transaction serialization, exact lineage helper reuse, and two-order proof in TC-353-01b.
- A valid but crossed fingerprint/descriptor can masquerade as strict lineage -> full-set prevalidation and trailing contradiction mutation in TC-353-01b/04.
- Media stage can mutate or cancel the still-live blob owner -> byte-for-byte v108/v111/attachment assertions in TC-353-01b.
- Shared completion can settle the wrong/newer parent or strand after local cache eviction -> exact envelope CAS plus present/absent attachment cases in TC-353-03.
- Failed/unacked retry can re-upload blobs or legacy-store after owner races -> initial and pre-egress v109 barriers in TC-353-03.
- Edit-first can create an unprovable family-agnostic placeholder or receipt before validation -> zero-write retryable deferral and two-connection replay proof in TC-353-05.
- Independent edit/delete streams can publish stale caption after tombstone -> SQLite winner and existing typed publication suppression in TC-353-04/05.
- Proof-less EDIT wire can be mistaken for permission to replace media -> caller media ignored on send, exact immutable descriptor comparison on receive, and no attachment writes in TC-353-02/04.
- Mixed old receiver sends only a target receipt -> event-bearing sender ignores it and retains v109; this accepted compatibility difference is explicit.
- Overengineering pressure -> unchanged DB v111, physical v109, wire kind, drain, retries, relay/native, and device profile; stop if another owner is proposed.

## Gate Cadence

Run for this plan:

- Six exact causal RED commands before production edits.
- One focused `--plain-name 'TC-353-'` GREEN over changed core/repository/sender/receiver test paths, then only the named preservation sentinels. Do not run those whole files twice unless production changes after the batch.
- Host curated `1to1` once. Do not pass batch flags; this wrapper owns the affected sender/receiver/v109 files and rejects batch mode for `1to1`.
- `core-host-all` once with batch Flutter, concurrency 2, and `--dart-only` because shared DB helpers change and no Android manifest/platform boundary changes.
- Serial dart-only `feature-host-all` once because sender, receiver, repository interfaces/fakes, and bootstrap production surfaces change.
- Analyzer, exact changed-Dart format, diff check, and one incremental Graphify refresh.

Do not run for this plan:

- No completeness-check: every test extends an existing registered/AUTO path and no gate registration changes.
- No full `host-all`: the next GAP-N01 dependency-wave checkpoint owns it; WP-07/final rollout owns the final release rerun.
- No non-host `./scripts/run_test_gates.sh 1to1`, Go/relay/node/bridge/binding, rollout shell, Redis/process, schema/migration/account-transfer, SQLCipher/device, Android emulator/phone, iPhone/iOS, performance, feed, groups, or posts gate. This plan changes none of those boundaries.
- Do not repeat Plan 347's media ciphertext upload/download campaign, Plan 349's fair-drain matrix, or Plans 351/352's full deletion/fingerprint matrices beyond named sentinels.

## Device / Relay Proof Profile

- Profile: host-only.
- Boundary being proven: same-process SQLite atomicity over existing message/media/v108/v109/v111 rows, production sender/receiver routing, and existing lifecycle/retry composition.
- Live device availability check: N/A. No schema migration, native binding, provider, OS lifecycle, media filesystem, or device-specific behavior changes.
- Relay proof: reuse unchanged `direct_mutation_v109` protected kind, mixed-version shadow, admission flag, capacity and metrics from Plans 344/349. Focused Dart proves the adopter; unchanged Go contracts remain wave-level sentinels.
- Two-peer default: N/A; no mobile-runtime or presentation claim is made.
- Deferred evidence: aggregate Android and consolidated availability-bounded iOS remain GAP-N01/WP-07 closure work, not a Plan 353 exit condition.

## Acceptance Gates

```bash
# Baseline; implementation must start clean and from the reviewed handoff.
git status --short
git rev-parse HEAD

# Causal RED 1a: direct-first delivery currently loses lineage at v108 completion.
flutter test test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  --plain-name 'TC-353-01a direct-delivered strict media keeps lineage through v108 completion'

# Causal RED 1b: no atomic strict media-caption + raw-event v109 stage exists.
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-353-01b strict media caption edit stages lineage parent and raw-event v109 atomically'

# Causal RED 2: media EDIT currently trusts caller media/keys and cannot own v109.
flutter test \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'TC-353-02'

# Causal RED 3: exact v109 completion currently rejects media EDIT parents.
flutter test test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  --plain-name 'TC-353-03 media caption edit reuses one exact v109 lifecycle'

# Causal RED 4: incoming strict caption apply/key proof is generic/non-atomic.
flutter test \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'TC-353-04'

# Causal RED 5: current event-bearing media edit writes an unprovable hidden placeholder.
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'TC-353-05 media edit before initial writes nothing then converges on replay'

# One focused GREEN: only Plan 353 tests in existing AUTO-classified paths.
flutter test --concurrency=1 \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  --plain-name 'TC-353-'

# Exact preservation sentinels outside the focused-name batch.
flutter test test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  --plain-name 'TC-349-01 ordinary text mutations stage atomically in shared v109'
flutter test test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  --plain-name 'TC-349-04 one fair batch routes reaction edit and deletion kinds'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'TC-342-03c media private edit delete and existing attempts remain outside new custody'
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-351-02 v108 and v111 state matrix preserves the independent initial and blob owners'
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-352-01 exact accepted v108 completion pins per-attachment lineage through full v111 drain'
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-352-02 outgoing lineage fingerprint CAS and v108 completion are all-or-zero'
flutter test test/core/database/helpers/messages_db_helpers_test.dart \
  --plain-name 'TC-351-04 strict media initial and current deletion converge without resurrection'
flutter test test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'TC-352-03 post-drain strict-media delete retains v109 while node stopped'
flutter test test/features/conversation/application/recovered_inbox_chat_disposition_test.dart \
  --plain-name '172 TC-02: editMissingOriginal maps to retryable (original may arrive later)'

# Affected curated lane and only justified families.
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2 --dart-only
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1 --dart-only

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

- Expected RED 1a: a direct-delivered/envelope-cleared parent skips Plan 352 fingerprint authorship and becomes legacy after cleanup.
- Expected RED 1b: no DB helper can qualify strict media lineage and atomically stage caption+v109 while retaining v108/v111.
- Expected RED 2: sender excludes attachments from mutation ownership and uses the caller media snapshot/generic media stage.
- Expected RED 3: exact mutation completion returns stale when physical direct attachments exist.
- Expected RED 4: receiver saves the parent and attachment projection through separate generic operations and can race deletion/publication.
- Expected RED 5: current event-bearing media EDIT with no original saves a family-agnostic hidden placeholder instead of making zero writes and remaining exact-envelope retryable.
- Green sentinel: text/reaction/delete/private/group/historical behavior, raw v109 ordering, v108/v111 bytes and default-off controls remain unchanged.
- Pre-existing dirty tree / known failure: none at planning baseline. No baseline failure is accepted.
- Environment blocker: none. Host real SQLite/application tests prove every changed boundary; unavailable device/iOS targets are N/A by project policy.
- Scope drift: any migration, wire/protocol/native change, new owner/drain/scheduler/flag, media replacement/upload, private/group adoption, device requirement, or full per-plan `host-all` stops execution for re-review.

- [ ] Direct-delivery successor and ordinary accepted completion preserve exact post-drain lineage without stamping later edit/tombstone/crossed parents. -> TC-353-01a.
- [ ] Repository-current strict media lineage, caption-only parent CAS and raw-event v109 commit atomically before network; every refusal changes none. -> TC-353-01b/02.
- [ ] Live v108 completion and EDIT converge in either order; caption EDIT never rewrites/transitions v108/v111/blob bytes and post-drain lineage remains exact. -> TC-353-01a/01b.
- [ ] Node-off/live/restart/protected acceptance/failed/unacked paths retain and retire only the exact caption event with no owned-event legacy fallback or blob re-upload. -> TC-353-02/03.
- [ ] Receiver applies only an exact immutable media descriptor set, changes parent caption metadata only, and deletion/newer edit wins without stale display or premature receipt. -> TC-353-04.
- [ ] Current edit-before-initial writes no placeholder, remains exact-envelope retryable, strict initial stays unchanged, and retained edit replay applies/settles only after descriptor validation. -> TC-353-05.
- [ ] Plans 349/351/352, historical compatibility, private/group lanes, schema v111, physical v109, default-off rollout controls, and gate ownership remain unchanged. -> PRES-353-A.
- [ ] Six causal REDs, at least two representative mutation re-reds (network-before-stage and attachment/v111 write prohibition), focused GREEN, exact sentinels, host `1to1`, core/feature families, analyzer, format, diff, and one Graphify refresh are recorded.
- [ ] No activation, GAP-N01 closure, device/iOS, per-plan full `host-all`, or release claim is made.

## Handoff

- First causal REDs: the six exact commands above (01a, 01b, and 02 through 05).
- Preservation: run the focused-name batch and exact sentinels above. Keep TC-342-03c unchanged unless implementation proves a literal accepted difference; its current edit arm has no strict media authority.
- Manual registration: none; extend existing registered/AUTO test files only.
- Migration: none; DB remains v111 and physical v109/v111 layouts stay byte-compatible.
- Rollout: no new flag. Existing protected inbox admission remains default-off; an already-strict local parent must not downgrade merely because admission is off.
- Boundary closure: host application plus real SQLite. No Go/native/relay/device/iOS leg.
- Deferred owner: media replacement/re-upload is not caption EDIT; private/disappearing, groups/announcements, historical promotion, linked-device fanout, activation/operations/quota and release evidence remain later GAP-N01/WP-07 work.
- Implementation session must update this plan, `00-INDEX.md`, GAP-N01 coverage receipts, and append `- Plan 353 — EXECUTION_COMPLETED` only after all required evidence is green.

## Reviewer Findings

Fresh `$tdd-review` confirmed the core reuse bet but returned `PLAN-FIXES-REQUIRED`. Three independent audits found the same high-severity receiver issue: the existing hidden placeholder contains neither media descriptors nor event identity, so strict-initial materialization could make a crossed caption visible before exact replay rejects it. The amended plan instead makes current event-bearing missing-original media EDIT a zero-write retryable outcome and leaves strict initial unchanged.

The review also made caller independence and secure-key proof non-vacuous, added a four-way persisted sender classifier, exact parent and wire-field canonicalization, all-null cleanup recovery, A/B replay/collision behavior, attachment-independent v109 completion, exact receiver fingerprint/v111/key matrices, and the explicit event-receipt decision table. It removed a duplicate fair-drain campaign and keeps TC-342-03c unchanged.

A sender audit exposed one necessary adoption prerequisite not in the first draft: direct receipt clears the initial envelope before a later protected v108 acceptance, so Plan 352 skips lineage on a common successful path. TC-353-01a now requires the existing completion transaction to recognize only that safe delivered successor, reuse the same fingerprint helper, and retain strict lineage through cleanup. This adds one existing core helper file, not a new owner or phase.

Targeted re-review then tightened three last boundaries: the direct-delivery prerequisite now matches the full canonical delivered settlement and has a fingerprint-direct causal RED; a live exact event-bearing legacy parent retains its current generic apply and event receipt; and failed/unacked paths each gain one narrow owner-at-entry/pre-egress sentinel. The final sender, receiver, and independent sufficiency reviews all returned READY. No tests were run because this remains a planning/review session.

## Arbiter Decision

READY / EXECUTION_READY. The core bet is confirmed: a caption-only EDIT needs no new durable authority. It can atomically reuse the physical raw-event v109 owner while v108/v111 plus the existing per-attachment lineage prove that the persisted media generation is immutable. The narrowly extended delivered-successor completion closes the common direct-ACK lineage hole; zero-write missing-original deferral avoids inventing a second placeholder owner; and exact legacy/mixed-version behavior remains intact. The reviewed eight-file boundary, six causal REDs, two small retry sentinels, affected host `1to1` plus dart-only core/feature sweeps, and explicit exclusions are sufficient. No migration, new outbox/kind/drain/scheduler/flag, relay/native change, media upload/replacement, device/iOS leg, per-plan full `host-all`, activation, GAP-N01 closure, or release claim is justified.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-09 | planning/review | Plan 353, index, append-only STATUS marker | `$tdd-plan` plus independent and targeted `$tdd-review`: READY | Source-grounded sender/storage/receiver contract, six causal REDs, two narrow retry-owner sentinels, exact preservation commands, and proportional run/not-run gates | no plan-content blocker; implementation intentionally not started | execute in a separate session, then append EXECUTION_COMPLETED only after every required receipt passes |
| 2026-08-09 | execution | The exact reviewed eight production files plus seven test files, the shared real-DB media fixture, and two frozen-digest/census guards | Six causal REDs recorded, focused GREEN 11/11, preservation sentinels 9/9, two mutation re-reds, host `1to1` 120 paths, `core-host-all` 404 paths / 3,221 tests, `feature-host-all` 841 paths / 9,014 tests / 7 skips, analyzer/format/diff clean, one incremental Graphify refresh | Three execution corrections were required and are recorded below; no scope drift, no new owner, no migration | append EXECUTION_COMPLETED and hand the remaining GAP-N01 lanes to their own plans |

## Execution Receipts

- Causal REDs (recorded before any production edit): TC-353-01a failed on null post-completion fingerprints for a direct-delivered parent; TC-353-01b, TC-353-02 and TC-353-04 failed because no caption-edit owner, sender lane or incoming conditional-apply existed; TC-353-03 returned `stale` whenever physical direct attachments existed; TC-353-05 wrote a family-agnostic hidden placeholder.
- Focused GREEN: `--plain-name 'TC-353-'` over the nine reviewed paths, 11/11.
- Preservation sentinels, each green unmodified: TC-349-01, TC-349-04, TC-342-03c, TC-351-02, TC-351-04, TC-352-01, TC-352-02, TC-352-03, and `editMissingOriginal -> retryable`.
- Mutation re-reds: (a) routing the caption EDIT back through generic media staging (no exact v109 before LAN/relay) reds TC-353-02; (b) transitioning v111 inside the caption stage reds TC-353-01b.
- Gates: host `1to1` 120 paths; `core-host-all --batch-flutter --dart-only` 404 paths / 3,221 tests; `feature-host-all --batch-flutter --dart-only` 841 paths / 9,014 tests / 7 skips; `flutter analyze lib test` clean; exact changed-Dart format clean; `git diff --check` clean; one incremental Graphify refresh (70,615 nodes / 103,797 edges).
- Concurrency note: both family sweeps were run with `--concurrency 4` rather than the planned 2/1. That is an execution-speed choice only; both scopes are the same planned path sets and both passed.

## Execution Corrections

1. The repository needed one seam the plan did not name: SQLite can only ever compare deterministic storage references, and two attachments can share a reference while their raw keys differ. A hydrated raw-key barrier now runs under the media lifecycle lock, outside the SQL transaction, before any expectation row is derived. It deliberately treats an EMPTY persisted projection as "not drifted" so the transactional owner keeps sole authority to distinguish an absent/hidden original (retryable deferral) from a genuinely crossed generation (refusal).
2. Two frozen content digests (`dtr18_layering_relocation_contract_test.dart` over production bootstrap, `dtr18_placement_closure_contract_test.dart` over the media adapter) and one census guard (`delivered_status_minting_sites_test.dart`) are path-string contracts invisible to import-level analysis and to every focused gate; all three were re-pinned with a reviewed justification rather than weakened. The census entry rises 5 -> 6 for the incoming caption candidate, whose status is never persisted at all.
3. TC-353-01b's planned "late v109-insert abort" arm cannot insert through the same connection from inside the transaction (sqflite serializes writes and would deadlock). The barrier now throws after the parent projection and the lineage stamps, which proves the same all-or-zero rollback property.
