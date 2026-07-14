# Plan 249 Session 02 — Direct-contact cell delivery, batch picker UX, and failed-cell retry

Status: accepted
Source: `Test-Flight-Improv/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown.md` Session 02
Run mode: implementation-committed gap-closure
Classification: host-only user-visible direct ordinary-send composition
Dependency: Plan 249 Session 01 is accepted and closed; Plan 234 Session 04 remains accepted and closed

## Planning Progress

| Time | Role / phase | Evidence or decision | Next action |
|---|---|---|---|
| 2026-07-11 | Evidence Collector | Read the accepted Session-01 plan, Plan-249 source and breakdown, and current direct source builder, ordinary share coordinator, generic picker, Shared Media action injection, ConversationWired route, contact authority, l10n, tests, and both 1:1 gate arrays. | Freeze Session 02 to one complete direct-only user-visible state machine. |
| 2026-07-11 | Graphify TDD grounding | Anchored current architecture context (`confidence=anchored`, `freshness=current`, fingerprint `34b8308146e152cb`) on `ConversationWired`, the direct Shared Media route, and the picker/delivery seams; current source verification supplied the load-bearing contracts below. | Own a dedicated direct batch coordinator and picker instead of adding a group-capable mode to the generic picker. |
| 2026-07-11 | Boundary decision | Session 01 already owns immutable exact-current source drafts, canonical order, independent captions/tokens, and dispatch revalidation. The ordinary share coordinator owns media preprocessing and independent direct sends, but its generic path may skip a vanished/oversized file and fall back to a stale contact. | Add one narrow opt-in Plan-249 strict seam while leaving generic `deliver` behavior unchanged. |
| 2026-07-11 | Session planner | The minimum complete endpoint is source-first preflight, current direct-contact qualification, source-major ordinary delivery, a truthful source/contact matrix, sparse failed-cell retry, a dedicated picker/preview, action injection, route wiring, and localized accessible state. | Record all eight new owner/test absences, author the four causal files and strict cases, then capture RED before any production edit. |
| 2026-07-11 | Independent plan reviewer | Counterexample review required and then accepted corrections for sole-media caption fallback, a second current-contact read, matrix/message cardinality, all-failed target freeze, typed pre-route source denial, RED ordering, zero-eligible-source calls, and retry-denial prior-state preservation. | `ACCEPTED`; execution may begin from a fresh post-Session-05 shared-tree baseline. |

## Execution Preflight

- **Historical pre-execution state:** this plan was execution-ready and had no `## Execution Result`, QA verdict, Graphify refresh, or closure audit. The accepted execution record below supersedes only that former status.
- At execution start, run `git status --short` and capture a fresh status/hash snapshot before any RED, production, l10n, gate, source-plan, or breakdown edit. The worktree is shared and intentionally dirty; never reset, stash, revert, overwrite, or attribute unrelated changes.
- **Planning-time scoped baseline:** at `2026-07-11 18:38 CEST`, HEAD was `84e8ead5d98928d60b1581bdb517b0f307503c35`; the aggregate SHA-256 over the 24 existing authority/owner/preservation/gate paths listed below was `f983c14bdb4243026a36d23d70f34674351b858bb382f5edb760e9c947b2ae12`.
- The four new production paths and four new causal-test paths named in `Exact Write Scope` were all absent. This Session-02 plan path was also absent historically before planning, but now exists by design. Reconfirm only the eight new owner/test absences at execution start; do not assert that this plan is absent. A newly present owner/test path is shared work and requires inspection rather than overwrite.
- Existing scoped paths to snapshot individually or with a deterministic aggregate:
  - `lib/features/conversation/application/build_direct_media_library_batch_forward.dart`
  - `lib/features/share/application/share_batch_delivery_coordinator.dart`
  - `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart`
  - `lib/features/conversation/presentation/screens/conversation_wired.dart`
  - `lib/l10n/app_en.arb`, `app_de.arb`, `app_ar.arb`
  - `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart`, `app_localizations_ar.dart`
  - `test/features/conversation/application/build_direct_media_library_batch_forward_test.dart`
  - `test/features/share/application/share_batch_delivery_coordinator_test.dart`
  - `test/features/share/presentation/share_target_picker_wired_test.dart`
  - `test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart`
  - `test/features/conversation/application/direct_media_library_boundary_test.dart`
  - `test/features/conversation/application/build_received_media_forward_test.dart`
  - `test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart`
  - `test/l10n/l10n_integrity_test.dart`
  - `scripts/run_test_gates.sh`, `scripts/run_host_test_gates.sh`, and `Test-Flight-Improv/test-gate-definitions.md`
  - the Plan-249 source plan and session breakdown.
- Capture the exact baseline output and SHA-256 of the baseline-safe scope command below immediately before RED. Later shared-tree movement is not automatically attributable; compare the owned-path hashes and inspect any scope-list delta.
- Session 01's accepted RED and production history are immutable evidence. Do not recreate its files, remint its contract, or turn its action-absence RED into Session-02 history.

## Session Objective

Expose the complete host-only direct Shared Media Batch Forward flow without changing its ordinary-send boundary:

1. Convert one Session-01 draft into a source-major Cartesian matrix with one truthful cell per source and selected direct contact; an outgoing message exists only when ordinary delivery reaches persistence.
2. Revalidate the whole attempted source set first, then re-read selected direct contacts, before the first ordinary delivery call.
3. Preserve one independently edited/cleared caption and one opaque operation token per source across contact fan-out and sparse in-route retry.
4. Record exactly one `sent`, `queued`, or `failed` cell for every attempted source/contact pair; never replay a settled cell.
5. Add a dedicated direct-only picker/preview and wire one injected Batch Forward action from Shared Media through `ConversationWired`.
6. Keep cancellation/denial selections intact, clear only fully settled sources, retain sources with failed cells, and present localized accessible progress/results.

Session 02 closes the user-visible implementation but does not accept overall Plan 249. Session 03 remains the independent aggregate mutation/closure owner.

## Contract Frozen For Execution

### Application vocabulary and one owner

Add `lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart` as the sole owner of the multi-source delivery state. Its API must provide typed equivalents of:

- `DirectMediaBatchForwardCellKey`: complete source `DirectReceivedMediaActionIdentity` plus one nonblank direct contact peer ID; equality is the full pair and diagnostics are redacted.
- `DirectMediaBatchForwardCellStatus`: exactly `sent`, `queued`, or `failed`.
- `DirectMediaBatchForwardCellResult`: key plus status only, or a non-sensitive typed reason; it must not retain an ordinary coordinator's free-form detail string.
- `DirectMediaBatchForwardMatrix`: immutable source-major cells, counts, failed keys, fully settled source identities, and failed source identities. Its `toString`/diagnostics expose counts only.
- `DirectMediaBatchForwardAttemptResult`: either one whole-source preflight denial with zero newly attempted cells, or an updated matrix. A denial may retain the caller's prior settled matrix for display but cannot convert, clear, or replay it.
- `DirectMediaBatchForwardProgress`: counts/ordinals and `uploading`/`sending` phase only; source/contact IDs, usernames, captions, paths, tokens, keys, nonces, bytes, and exception text are forbidden from diagnostics.
- `DirectMediaBatchForwardCompletion`: the route-to-library result containing only fully settled and still-failed complete source identities, with a redacted representation. Cancellation or an initial zero-matrix in-route source denial settles none. A retry denial after a prior matrix adds no cells and cannot change that matrix; closing still returns truthful completion from the preserved prior cells.
- A typed library-launch result distinguishes `cancelled`, generic `sourceUnavailable`, and `completed`. It carries no builder denial enum, row detail, path, or source payload. `ConversationWired` maps a Session-01 build denial to `sourceUnavailable`, maps a null route result to `cancelled`, and maps a route completion to `completed`; the library never infers one state from another.
- `DirectMediaBatchForwardDeliveryCoordinator.deliverInitial(...)` and `retryFailed(...)`, or one equivalently typed API whose tests make initial Cartesian delivery and sparse retry impossible to confuse.

The coordinator may inject the Session-01 `BuildDirectMediaLibraryBatchForward` and a typed adapter around the opt-in Plan-249 strict ordinary-delivery seam defined below. It must not copy direct-private eligibility, message sending, media preprocessing, upload, encryption, persistence, or durable retry logic.

### Source-first dispatch boundary

- Initial delivery receives one current Session-01 draft, its direct source `contactPeerId`, and one ordered list of selected contact peer IDs.
- Reject an empty contact list, blank peer ID, or duplicate peer ID as a non-sensitive request denial with zero contact lookup and zero ordinary call. Do not silently trim, deduplicate, or invent a target.
- Before contact lookup, file processing, upload, encryption, message construction, or send, call `BuildDirectMediaLibraryBatchForward.revalidateForDispatch` for the complete set of sources that this attempt would dispatch.
- On initial delivery that set is the whole draft. On retry it is exactly the subset of sources owning at least one failed cell; constructing this sub-draft must preserve the original full identity, edited/cleared caption, and operation token.
- A source denial is atomic for the current attempt: zero ordinary calls and zero new cell settlement. Previously settled matrix cells, if this was a retry, remain settled and unchanged.
- Use the revalidated canonical source order. Never dispatch in tap order, path order, future-completion order, contact-major order, or prior matrix insertion order.
- Each revalidated source becomes exactly one existing `ShareIntent` with one current resolved path, that source's current edited/cleared caption, and that source's unchanged `ForwardProvenance.operationDedupKey`. No second token, contact-derived token, source ID, batch ID, provenance array, or album marker is allowed.

### Direct-contact authority and ordering

- The dedicated picker calls only `ContactRepository.getActiveContacts()`, then excludes any blocked/archived row. It owns no `GroupRepository`, announcement repository, group selection state, group callback, or generic target union.
- Immediately after successful source revalidation, the application coordinator calls `ContactRepository.getContact(peerId)` for every requested peer in the picker-provided display order before the first ordinary delivery call.
- A current row is eligible only when it exists, its exact `peerId` matches the requested value, and it is neither archived nor blocked. A missing/replaced/mismatched/archived/blocked row becomes a `failed` cell for every attempted source targeting it and is never passed to ordinary delivery.
- Contact invalidation does not abort valid contacts or weaken their ordinary contract. Missing required recipient encryption remains an ordinary failed result, not a fabricated active-contact success.
- Within each source, eligible contacts retain the picker-provided display order. The externally observable matrix is source-major: all cells for canonical source 1, then source 2, and so on.
- No group or announcement target can be represented at the direct coordinator boundary. If an adversarial ordinary result names a group, an unknown contact, a duplicate contact, or omits a requested contact, ignore the foreign result and fail closed for the affected requested cell; never report false settlement.

### Ordinary delivery and result truth

- For each source in canonical order that has at least one currently eligible pending contact, call the strict ordinary seam exactly once with that source's one-file `ShareIntent` and those eligible contacts. A source whose requested contacts all fail application contact preflight produces its required failed matrix cells and zero strict calls.
- Add one explicit opt-in Plan-249 method/mode in `share_batch_delivery_coordinator.dart` (for example `deliverDirectMediaBatchForwardStrict`, with equivalent exact naming allowed). Production Plan 249 uses it; existing `ShareBatchDeliveryCoordinator.deliver`, group Forward, external share, and every default caller retain their current behavior and signatures.
- The strict seam requires an input `ShareIntent` with exactly one file and, after ordinary preprocessing, exactly one processed media item before the first target send. A vanished, unreadable, oversized, or skipped source fails every requested target for that source with zero caption-only send, zero persistence, and zero upload/send continuation.
- The application coordinator's all-contact read is the first dispatch contact preflight. The strict seam performs a second current exact contact read immediately before each target's ordinary send and requires a non-null exact-peer, non-archived, non-blocked row. In strict mode `_sendToContact` may not use `current ?? stalePickerContact`; post-preflight removal, archive, block, or mismatch is a failed cell with zero send for that target. Other valid targets continue.
- The existing ordinary coordinator may preprocess the source once per source and must continue to create fresh ordinary recipient-scoped message/blob IDs, timestamp, key/nonce, ciphertext, persistence, and retry state per contact.
- A valid ordinary result maps only by the requested direct contact key. `sent` remains `sent`, `queued` remains `queued`, and `failed` remains `failed`; never collapse queued into success or picker failure.
- A thrown per-source ordinary call produces failed cells for that source's still-pending valid contacts and continues with the next canonical source. A thrown contact lookup fails only that contact's attempted cells. No exception text is rendered or logged.
- Every requested pair receives exactly one matrix cell. Duplicate, missing, foreign, or malformed ordinary results fail closed without aborting later sources and without creating additional cells.
- Two sources and two requested contacts always produce four matrix cells. Only an all-valid `2 x 2` fixture whose four ordinary outcomes reach persistence proves four outgoing media messages; missing files, invalid contacts, encryption failures, and other failed cells may correctly have no message row. Two attachments from one parent remain two sources. An all-valid source with an empty caption still produces its ordinary media message.

### Failed-cell-only retry

- `retryFailed` accepts the current edited draft plus the prior matrix and derives its work exclusively from `status == failed` cell keys. An empty failed set is a no-op: no source revalidation, contact read, processing, upload, encryption, or send.
- Never recompute a Cartesian product from the contacts/sources that happen to have any failure. If source A failed only for contact 2 and source B failed only for contact 1, retry exactly those two sparse cells.
- Before retry, source-revalidate the exact failed-source subset and contact-revalidate the exact failed-contact set. Preserve each item's complete identity, latest in-route edited/cleared caption, and original Session-01 operation token.
- Merge retry outcomes by complete cell key. Retried failures may become sent/queued or remain failed. Prior sent/queued cells are byte-for-byte/status-for-status unchanged and never supplied to ordinary delivery again.
- A queued cell is durable-retry-owned even when its live send returned an offline result. The picker must not retry it. Existing message/attachment repositories and direct retry use cases remain authoritative across restart/reopen.
- Closing and reopening after an unpersisted failure starts a new explicit Batch Forward action and a new Session-01 draft/token set; Session 02 adds no durable batch state.

### Dedicated picker, preview, and route

Add a dedicated direct flow, not a mode on the generic group-capable picker:

- `direct_media_batch_forward_picker_screen.dart`: pure bounded UI using `ListView.builder`/slivers for `1..10` source preview/editor rows and the active direct-contact list.
- `direct_media_batch_forward_picker_wired.dart`: owns contact loading, selection, per-source text controllers, wake-lock/send state, progress, accumulated matrix, exact sparse retry, and route completion.
- `direct_media_batch_forward_picker_route.dart`: constructs only the dedicated wired picker and returns `DirectMediaBatchForwardCompletion?`.
- Before the first attempt, captions and direct-contact selection are editable. Convert controllers back to immutable item copies by complete source identity; clearing one caption must not restore its parent caption or affect a sibling.
- After any matrix-producing attempt, freeze target selection for that in-route action, including an all-failed matrix with no sent/queued cell. An initial whole-source denial before any matrix creates zero cells and leaves target selection editable. A retry denial after a prior matrix creates zero new cells but preserves the prior matrix and its target freeze. The retry button acts only on stored failed cell keys; contact-level selection must never expand a sparse retry back into a Cartesian send.
- Show bounded source thumbnails without rendering a local path as text or semantics, source count, independent localized caption labels, active direct contacts, selection count, progress phase/count, localized cell statuses/summary, one generic source-preflight denial, and a localized retry-failed action.
- Acquire the existing upload wake lock immediately before application delivery and release it in `finally`. `PopScope`/controls prevent leaving during a live attempt. Do not advertise or implement mid-send cancellation.
- On zero-failure completion, close with the matrix completion. If failures remain, keep the route open for exact retry. A user close after an attempt returns the current completion; close/cancel before the first attempt returns null.
- Diagnostics and flow events contain only phase and counts. Do not pass `error.toString()`, source/contact IDs, usernames, captions, paths, tokens, keys, nonces, media payload, or ordinary result detail.

### Shared Media action and ConversationWired

- Add one nullable injected callback to `DirectSharedMediaLibraryScreen` for Batch Forward. The screen/controller remains transport-free and renders `shared-media-action-forward` only when the callback is non-null.
- On tap, pass the exact currently selected complete identities. Prevent re-entry while the callback/route is live.
- Cancel settles none, preserves the full selection, and shows no failure feedback. Generic `sourceUnavailable` also settles none and preserves the full selection, but shows only localized `direct_batch_forward_source_unavailable`; it must not reveal whether the cause was private, stale, terminal, corrupt, missing, or otherwise denied. A completion unselects only `fullySettledSourceIdentities`; any source with one or more failed cells remains selected. Existing Save/Share/Delete/Go-to-message actions and failed-only reconciliation remain unchanged.
- In `ConversationWired`, expose the callback only when the direct media repository and all required direct ordinary-delivery dependencies are present. First build the Session-01 draft for `_contact.peerId`; a build denial launches no picker, performs no contact lookup or ordinary file-processing/upload/delivery work, returns typed `sourceUnavailable`, and preserves library selection. The private/stale causal fixture must deny before path/file probing as well.
- Production then creates the existing ordinary coordinator, uses its opt-in strict Plan-249 seam through the new direct coordinator, and pushes only the dedicated route. A narrowly typed injected direct-batch launcher is permitted for widget proof, but it must receive the already-qualified draft and cannot authorize a denied build.
- The real route does not receive group/announcement repositories even when `ConversationWired` has them for one-source Forward.

### Localization, accessibility, and viewport contract

Add matching English, German, and Arabic ARB entries and regenerate all four Dart localization outputs. The minimum key family is:

- `shared_media_action_forward`
- `direct_batch_forward_title`
- `direct_batch_forward_item_count`
- `direct_batch_forward_source_label`
- `direct_batch_forward_caption_label`
- `direct_batch_forward_contacts_title`
- `direct_batch_forward_no_contacts`
- `direct_batch_forward_send`
- `direct_batch_forward_retry_failed`
- `direct_batch_forward_progress`
- `direct_batch_forward_source_unavailable`
- `direct_batch_forward_status_sent`
- `direct_batch_forward_status_queued`
- `direct_batch_forward_status_failed`
- `direct_batch_forward_summary`

Use declared placeholders consistently across locales. If ICU plural forms are used, all generated signatures and tests must agree.

- Every source editor has a unique semantic label using its 1-based ordinal and item count; never use message/attachment/path/token values as labels.
- Contact rows expose localized selected/unselected state, status rows expose the localized result, and progress/summary is a live region.
- The flow must render without overflow, clipped required controls, lost focus/scroll access, directionality exceptions, or unreachable send/retry controls at `320x568` logical pixels in English LTR and Arabic RTL with text scale `1.3`.
- Preview and contact lists stay lazily built; no `Column(children: allSources/allContacts)` regression is allowed.

## Exact Write Scope

### New production owners

- `lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart`
- `lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart`
- `lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart`
- `lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart`

### Existing production owners

- `lib/features/share/application/share_batch_delivery_coordinator.dart` — only the opt-in strict Plan-249 delivery seam and its narrowly shared internal plumbing; default generic/group/external-share behavior remains unchanged.
- `lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart` — injected action and selection reconciliation only.
- `lib/features/conversation/presentation/screens/conversation_wired.dart` — Session-01 build, dependency guard, dedicated route/coordinator wiring, and optional narrowly typed launcher seam only.
- `lib/l10n/app_en.arb`, `lib/l10n/app_de.arb`, `lib/l10n/app_ar.arb`
- generated `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_de.dart`, `app_localizations_ar.dart`

The strict seam may refactor shared private implementation only as needed to select strict versus default behavior. It must not change the abstract generic contract, default arguments, generic target results, group behavior, or external-share behavior.

### New causal tests

- `test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart`
- `test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart`
- `test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart`

### Existing causal test extension

- `test/features/share/application/share_batch_delivery_coordinator_test.dart` — add only opt-in strict-mode cases for exactly-one processed media, vanished/oversized source failure before send, second current active-contact read without stale fallback, and explicit default-mode preservation.
- **Execution-discovered causal preservation-sentinel expansion:** `test/features/conversation/application/received_media_action_transport_boundary_test.dart` — update only the frozen `ConversationWired` inventory from 17 to 18 `widget.p2pService` references, 27 to 29 `widget.bridge` references, and zero to one `DefaultShareBatchDeliveryCoordinator` construction, plus exact-one assertions for that coordinator and `DirectMediaBatchForwardDeliveryCoordinator`. The existing transport boundary test failed the curated lane after the real Plan-249 wiring landed; this bounded inventory correction is attributable Session-02 proof, not unrelated production scope.
- The existing coordinator suite proves the strict seam in isolation, and the new `direct_media_batch_forward_transport_boundary_test.dart` must repeat post-application-preflight missing file, oversized file, and contact invalidation through the composed Plan-249 path. Neither proof may be replaced by the other.

### Registration and session evidence

- `scripts/run_test_gates.sh`
- `scripts/run_host_test_gates.sh`
- `Test-Flight-Improv/test-gate-definitions.md`
- this Session-02 plan, the Plan-249 source plan, and the Plan-249 breakdown — execution/QA/closure evidence and Session-02 ledger transition only.

All other production and test files are read-only preservation authorities. In particular, do not edit the Session-01 builder or its test to make Session-02 REDs pass.

## Strict Non-goals And Scope Guard

- No schema, migration, database version, registry, table, column, durable batch record, or v101. Plan 238 retains sequential v101.
- No new encrypted-inner field, receiver codec, outer envelope, batch/album payload, shared caption, provenance array, receiver badge, legacy fallback, or transport command.
- No group, announcement, Plan 250/251, group picker, group repository, group publish, or announcement delivery behavior.
- No Go/libp2p/relay, native Android/iOS, SQLCipher, notification, device, actual PiP, or viewer change.
- No Plan-234 Session 05/06, Plan-247 Session 03/04, Plan-238, or excluded-plan work.
- No change to one-source Forward, external share, ordinary composer send, persisted direct retry, Shared Media paging/bookmark/viewer/Save/Share/Delete/Go-to-message, or private-media policy.
- No default behavior change in `ShareBatchDeliveryCoordinator.deliver`, group Forward, external share, or existing generic picker callers; Plan 249 must opt in explicitly to the strict seam.
- No full `host-all`, `core-host-all`, `feature-host-all`, performance family, device, SQLCipher, Go, relay, or native gate. Full `host-all` remains a Wave-1 batch/final-rollout obligation.

## RED-first Causal Test Contract

Create all four new test files and add the strict-mode cases to the existing ordinary-coordinator test before any new production file or existing production edit. The first focused command must fail because the new coordinator/picker/action/transport APIs and opt-in strict ordinary seam do not exist. Preserve the exact compiler failures and exit code in `## Execution Progress`. The Session-02 plan's own historical absence is not RED evidence and is never reasserted during execution.

| Case | Exact named behavior | Required proof / mutation |
|---|---|---|
| TC-249-S02-01 | `source denial precedes contact lookup and every ordinary delivery call` | Initial and retry source invalidation call Session-01 revalidation first, send zero cells, and retain prior settled state. Mutation: contact read or one source send before whole attempted-source success turns red. |
| TC-249-S02-02 | `two canonical sources by two active contacts produce four source-major ordinary cells` | Reverse-input draft revalidates to canonical source order; one ordinary call per source carries one file/caption/token and two contacts in picker order; matrix is source-major. Same-parent siblings remain separate. Mutation: contact-major iteration, coalescing, one multi-file intent, or one call per cell fails. |
| TC-249-S02-03 | `current direct contact qualification fails invalid cells and continues valid contacts` | Missing, peer-mismatched, archived, blocked, and throwing lookups never reach ordinary delivery; each yields failed cells while valid contacts continue. Blank/duplicate requested IDs deny before reads. Groups are unrepresentable. |
| TC-249-S02-04 | `ordinary sent queued failed and malformed results form one complete truthful matrix` | Every requested pair gets exactly one status. Queued stays queued; thrown source delivery, missing result, duplicate result, foreign contact, and adversarial group result fail closed without aborting later canonical sources. |
| TC-249-S02-05 | `failed-cell retry is sparse and preserves each source caption and token` | Crossed failures `(source1, contact2)` and `(source2, contact1)` retry only those two cells, with edited/cleared captions and original tokens. Prior sent/queued cells never enter revalidation targets or ordinary calls. Mutation: failed-source x failed-contact Cartesian retry, token remint, caption restoration, or queued replay fails. |
| TC-249-S02-06 | `all-valid ordinary transport persists four fresh encrypted media messages without source provenance` | An explicitly all-valid two-source/two-contact fixture through the new coordinator plus strict real ordinary coordinator produces four persisted ordinary outgoing media messages/attachments with fresh destination message/blob IDs, key/nonce/ciphertext and the expected per-source opaque token; no source message/attachment/conversation ID enters bridge payloads or persisted destination provenance. Other matrix fixtures make no message-row claim for failed cells. |
| TC-249-S02-07 | `dedicated picker loads active direct contacts only and edits captions independently` | Only `getActiveContacts`/current contact reads occur; blocked rows are filtered; no group section/repository/key exists. Ten lazily built source rows keep independent controllers and a cleared caption remains empty through send/retry. |
| TC-249-S02-08 | `picker reports progress matrix and retries failures without replaying settled cells` | A sent/queued/failed first attempt locks targets, displays localized truth, and invokes exact application retry. Success closes with completion; close after failure returns only fully settled versus failed sources; pre-send cancel or initial zero-matrix denial settles none. A retry denial preserves the prior completion. Wake lock releases on success, failure, denial, and throw. |
| TC-249-S02-09 | `batch forward action distinguishes cancel source-unavailable and completed selection outcomes` | Action is absent when callback is null and present under the stable key when injected. It passes exact full identities and blocks double tap. Cancel preserves selection with no failure feedback; typed source-unavailable preserves selection and shows only generic localized copy; completion clears all-settled sources and retains any partly failed source. Existing action keys remain. |
| TC-249-S02-10 | `ConversationWired builds current sources before launching the dedicated direct route` | Missing dependencies hide/unwire action; private/stale build denial returns only typed generic source-unavailable, preserves selection, and invokes no route/contact/path-file/delivery work; ready build launches the direct-only seam with canonical draft and source contact scope. Group picker dependencies are not passed. |
| TC-249-S02-11 | `batch picker is localized semantic lazy and safe in small LTR and RTL viewports` | EN/DE/AR keys and placeholders agree; source/contact/status/progress semantics contain no stable IDs/path/token; `320x568`, text scale `1.3`, LTR/RTL have no overflow or unreachable send/retry; builder calls remain viewport-bounded. |
| TC-249-S02-12 | `delivery matrix and diagnostics expose counts and outcomes only` | `toString`, flow events, denial, thrown-secret sentinel, matrix, and progress diagnostics omit source/contact IDs, usernames, captions, paths, tokens, keys, nonces, bytes, and ordinary detail/error text. |
| TC-249-S02-13 | `strict ordinary mode rejects post-preflight missing oversized media and invalid contacts before send` | Vanish the file or make it oversized after application preflight: strict processing returns failed cells with zero caption-only message, upload, or persistence. Remove/archive/block/mismatch a contact after the first read: the strict second read fails that cell without stale fallback while other contacts continue. The same fixtures prove default generic behavior is unchanged when strict mode is not selected. |
| TC-249-S02-14 | `all-failed matrix freezes targets while initial and retry source denials preserve their prior state` | A complete all-failed matrix locks contact toggles and retries only stored failed cells. An initial whole-source denial with no matrix leaves selection editable and settles nothing. A retry denial adds no cells, leaves the prior sent/queued/failed matrix byte-for-byte unchanged, keeps targets frozen, and returns truthful prior completion on close. Mutations that freeze the initial state, thaw after retry denial, or edit prior settlement turn red. |

Preservation sentinels must also prove:

- Session-01 build/revalidation still owns exact-current atomic source qualification, canonical order, caption/token identity, and redaction.
- Plan-232 one-source Forward and its retry roundtrip retain their existing picker/dedup/encryption/persistence behavior.
- Plan-233 direct library paging, selection cap, Save/Share/Delete/Bookmark/viewer/Go-to-message, and failed-only reconciliation remain unchanged.
- Plan-234 private/terminal/unsupported/corrupt current rows remain denied before picker/delivery.
- Generic external/group-capable `ShareTargetPickerWired` and `ShareBatchDeliveryCoordinator` behavior remains unchanged.

## Implementation Sequence

1. Capture fresh shared-tree status, per-owned-file hashes, aggregate scoped hash, all eight new owner/test missing-file assertions, and the baseline-safe scope output/hash. Record the plan file as present and historical planning evidence only.
2. Add the four causal test files/imports and strict ordinary-coordinator cases before production. Run the combined focused command and preserve the missing-API RED.
3. Implement the typed direct coordinator plus the opt-in strict ordinary seam and reach application GREEN, including exactly-one processed media, second current contact read, malformed ordinary results, exception isolation, source-first ordering, and sparse retry. Prove default generic behavior unchanged.
4. Implement the pure dedicated picker, wired state, and route; reach picker GREEN before wiring Shared Media.
5. Add the nullable Shared Media callback/action and selection reconciliation; then wire Session-01 build plus the dedicated route in `ConversationWired`.
6. Add EN/DE/AR source strings, run `flutter gen-l10n`, and reach localization/accessibility/small/RTL GREEN.
7. Reach the real ordinary transport-boundary GREEN. Do not weaken it into a mock-only assertion if fixture work is required.
8. Register all four new suites in `ONE_TO_ONE_TESTS`, `ONE_TO_ONE_HOST_TESTS`, and `test-gate-definitions.md`.
9. Run every literal focused, preservation, l10n, curated, inventory, completeness, static, diff, and scope gate below on the final Executor candidate.
10. Run final Graphify `affected` over all seven attributable production owners plus generated l10n outputs.
11. Obtain fresh independent QA. Apply at most two bounded fix passes. After a fix, rerun the causal batch, its exact preservation sentinel(s), l10n when touched, curated `1to1`, formatter/analyzer/diff/scope, and final `affected`.
12. Only after final QA accepts, run exactly one incremental architecture refresh.
13. Persist `## Execution Result`; then run a separate closure review and synchronize only Session-02 source/breakdown status. Unblock Session 03; do not mark Plan 249 accepted.

## Literal Acceptance Gates

Run every command from the repository root and record exact exit status and test counts/output in `## Execution Result`.

```bash
# Fresh shared-tree and missing-owner baseline before RED.
git status --short
test ! -e lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart
test ! -e lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart
test ! -e lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart
test ! -e lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart
test ! -e test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart
test ! -e test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart
test ! -e test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart
test ! -e test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart

# Causal RED first, including the opt-in strict ordinary seam; rerun this exact
# batch as the primary final GREEN.
flutter test test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart

# Session-01 and Plan-234 exact-current source preservation.
flutter test test/features/conversation/application/build_direct_media_library_batch_forward_test.dart test/features/conversation/application/private_media_action_eligibility_test.dart test/features/conversation/application/direct_private_media_boundary_test.dart test/features/conversation/application/received_media_action_controller_test.dart

# Plan-232 one-source Forward and durable retry preservation.
flutter test test/features/conversation/application/build_received_media_forward_test.dart test/features/conversation/integration/forwarded_media_retry_roundtrip_test.dart

# Plan-233 direct Shared Media boundary/action preservation.
flutter test test/features/conversation/application/direct_media_library_batch_actions_test.dart test/features/conversation/application/direct_media_library_boundary_test.dart test/features/conversation/presentation/screens/conversation_shared_media_library_test.dart

# Existing generic picker preservation; the ordinary coordinator's complete
# default/strict suite is already in the primary causal batch above.
flutter test test/features/share/presentation/share_target_picker_wired_test.dart

# Localization source/generated integrity.
flutter gen-l10n
flutter test test/l10n/l10n_integrity_test.dart test/core/l10n/app_localizations_signal_test.dart

# Affected curated lane and registration/completeness truth.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh 1to1 --list
./scripts/run_test_gates.sh completeness-check

# Every new proof file must appear in both arrays and the definition doc.
rg -n 'direct_media_batch_forward_delivery_coordinator_test\.dart|direct_media_batch_forward_picker_wired_test\.dart|conversation_shared_media_batch_forward_test\.dart|direct_media_batch_forward_transport_boundary_test\.dart' scripts/run_test_gates.sh scripts/run_host_test_gates.sh Test-Flight-Improv/test-gate-definitions.md

# Scoped formatting and analysis.
dart format --output=none --set-exit-if-changed lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart
dart analyze lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart test/features/share/application/direct_media_batch_forward_delivery_coordinator_test.dart test/features/share/application/share_batch_delivery_coordinator_test.dart test/features/share/presentation/direct_media_batch_forward_picker_wired_test.dart test/features/conversation/presentation/screens/conversation_shared_media_batch_forward_test.dart test/features/conversation/application/direct_media_batch_forward_transport_boundary_test.dart

git diff --check

# Baseline-safe whole-tree scope view. Capture its output and SHA-256 before
# RED and compare after GREEN. It removes only the exact Session-02 allowlist;
# every printed path is shared/pre-existing or forbidden for this session.
session_02_forbidden_scope() {
  git status --porcelain=v1 --untracked-files=all | awk '
    {
      path = substr($0, 4)
      allowed = path ~ /^(Test-Flight-Improv\/249-1to1-shared-media-batch-forwarding-tdd-plan\.md|Test-Flight-Improv\/249-1to1-shared-media-batch-forwarding-tdd-plan-session-breakdown\.md|Test-Flight-Improv\/249-1to1-shared-media-batch-forwarding-tdd-plan-session-02-plan\.md|Test-Flight-Improv\/test-gate-definitions\.md|scripts\/run_(host_)?test_gates\.sh|lib\/features\/share\/application\/(direct_media_batch_forward_delivery_coordinator|share_batch_delivery_coordinator)\.dart|lib\/features\/share\/presentation\/screens\/direct_media_batch_forward_picker_(screen|wired)\.dart|lib\/features\/share\/presentation\/navigation\/direct_media_batch_forward_picker_route\.dart|lib\/features\/conversation\/presentation\/screens\/(direct_shared_media_library_screen|conversation_wired)\.dart|lib\/l10n\/app_(en|de|ar)\.arb|lib\/l10n\/app_localizations(_(en|de|ar))?\.dart|test\/features\/share\/application\/(direct_media_batch_forward_delivery_coordinator_test|share_batch_delivery_coordinator_test)\.dart|test\/features\/share\/presentation\/direct_media_batch_forward_picker_wired_test\.dart|test\/features\/conversation\/presentation\/screens\/conversation_shared_media_batch_forward_test\.dart|test\/features\/conversation\/application\/(direct_media_batch_forward_transport_boundary_test|received_media_action_transport_boundary_test)\.dart)$/
      if (!allowed) print $0
    }
  ' | LC_ALL=C sort
}
session_02_forbidden_scope
session_02_forbidden_scope | sha256sum

# Final attributable production impact, after all fixes and before final QA.
python3 graphify-arch/tdd_context.py affected lib/features/share/application/direct_media_batch_forward_delivery_coordinator.dart lib/features/share/application/share_batch_delivery_coordinator.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_screen.dart lib/features/share/presentation/screens/direct_media_batch_forward_picker_wired.dart lib/features/share/presentation/navigation/direct_media_batch_forward_picker_route.dart lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart lib/features/conversation/presentation/screens/conversation_wired.dart lib/l10n/app_localizations.dart lib/l10n/app_localizations_en.dart lib/l10n/app_localizations_de.dart lib/l10n/app_localizations_ar.dart --budget 600
```

The execution-discovered inventory sentinel was already dirty and present in
the original forbidden output. Consequently the original `afd4d0...` hash
proves only that the **status path list** did not grow; it cannot prove that an
already-listed file's contents stayed unchanged. After adding the sentinel to
the attributable allowlist, the corresponding adjusted baseline path-list hash
is `67a1017857c45d59fa44cc4dedb1ea8185aed25cbb0082058860ece44592dec9`.
Its exact Plan-249 hunks are reviewed and tested separately above.

The eight `test ! -e` production/test commands are pre-RED evidence only and are not rerun after intentional creation. The plan-file absence is planning evidence, not an execution gate because this document now exists. `flutter gen-l10n` must leave no unreviewed generated drift. Full `host-all` is explicitly not a Session-02 gate.

## Independent QA And Refresh Contract

- QA must be fresh and independent of the Executor and must review the complete attributable production/test/l10n/gate diff, literal gate evidence, baseline-safe scope comparison, and Graphify `affected` output.
- Required counterexamples: source denial after preview; source order reversal; same-parent siblings; cleared versus edited captions; token remint/contact derivation; empty/duplicate contacts; current missing/mismatched/blocked/archived contacts at first and strict second read; one invalid plus one valid contact; all contacts invalid for one source; post-preflight missing/oversized media; caption-only fallback; stale-contact fallback; per-source throw; missing/duplicate/foreign/group ordinary result; crossed sparse failures; sent replay; queued replay; retry source denial with prior settlement; all-failed matrix target editing; initial zero-matrix denial editability; retry-denial target freeze/prior completion; action double tap; cancel versus generic source-unavailable feedback/selection; partial-source failure selection; generic group picker leakage; path/token/source identity semantics or logs; wake-lock throw; ten-item lazy list; small LTR/RTL overflow.
- QA must confirm exactly one strict ordinary delivery call per canonical source with at least one eligible pending cell, zero strict calls for a source whose contacts all fail application preflight, and one matrix cell per requested source/contact pair. Only the all-valid `2 x 2` real transport fixture must prove four persisted outgoing media messages with fresh recipient-scoped identity/encryption; failed cells must not be reported as messages.
- Acceptance requires no unresolved blocking finding and no unsupported schema/wire/group/native/device claim.
- `fix_passes` starts at zero and must be recorded. At most two bounded fix passes are authorized inside this exact scope. A finding requiring schema, receiver/wire, group/announcement, Go/relay, native/device, Session-03 closure, or another Plan-249 source policy blocks and re-plans.
- Only after final QA accepts, run exactly once:

```bash
./graphify-arch/refresh_arch_graph.sh --incremental
```

- Do not refresh before QA acceptance and do not run a second refresh for closure-document edits.

## Done Criteria

- [x] Fresh dirty-tree, scoped hash, eight new owner/test missing-file assertions, the already-present plan record, and forbidden-scope baseline are recorded without altering shared work.
- [x] All four causal files exist before new production and the first combined command records the intended missing-API RED.
- [x] The new application coordinator revalidates the whole attempted source set before contact or ordinary work.
- [x] Current active direct contacts only are eligible; invalid contacts become failed cells while valid contacts continue.
- [x] Canonical source-major delivery calls the opt-in strict ordinary seam exactly once per source with at least one eligible pending cell, zero times when all of that source's contacts fail preflight, and produces one truthful matrix cell per requested source/contact pair.
- [x] Strict mode requires exactly one processed media item before send and a second exact active-contact read without stale fallback; post-preflight missing/oversized media and invalid contacts produce no false message.
- [x] Default generic, group, and external-share coordinator behavior remains unchanged without explicit Plan-249 opt-in.
- [x] Same-parent sources remain separate; independent edited/cleared captions and per-source tokens survive fan-out and retry.
- [x] Matrix handling fails closed for throws, missing/duplicate/foreign/group results and never fabricates settlement.
- [x] Retry is exactly sparse failed-cell-only; no sent/queued cell is revalidated for dispatch or replayed.
- [x] The dedicated picker never loads/renders group or announcement targets and owns bounded preview/editor/contact/progress/result state.
- [x] Wake lock, leave protection, progress, cancel, initial zero-matrix-denial editability, all-failed selection freeze, retry-denial prior-matrix/target-freeze preservation, success, partial failure, retry, and route-close outcomes are causal-tested.
- [x] Shared Media action injection and ConversationWired source-build/dedicated-route wiring distinguish cancel, generic source-unavailable, and completion while preserving selection truth and all existing actions.
- [x] EN/DE/AR strings, generated localization output, semantics, lazy lists, and small LTR/RTL viewports pass.
- [x] The all-valid `2 x 2` real ordinary transport proof confirms four persisted media messages, fresh destination identity/encryption, and no source provenance leak; no failed-cell fixture overclaims a message.
- [x] All four suites are registered in both 1:1 arrays and the gate-definition document.
- [x] Every literal focused, preservation, l10n, curated, inventory, completeness, formatter, analyzer, diff, and scope gate passes.
- [x] Final Graphify `affected` covers every attributable production owner.
- [x] Fresh independent QA accepts with the explicitly reviewed `fix_passes=3` bounded exception in the same picker/test scope.
- [x] Exactly one incremental Graphify refresh runs after QA acceptance.
- [x] `## Execution Result` and closure audit truthfully close Session 02, leave Session 03 runnable, and keep overall Plan 249 implementation-in-progress.

## Closure-document Update Contract

Only after accepted execution, final QA, and the one post-QA refresh:

- Set this session plan to `Status: accepted`, check only truthful Done Criteria, append `## Execution Result`, and add a stable `## Closure Audit`.
- Update the Plan-249 source plan with exact Session-02 RED/GREEN/gate/QA/refresh evidence. Mark Session 02 accepted, Session 03 pending/runnable, and keep the overall source status `implementation-in-progress` / verdict `still_open`.
- Update only the Plan-249 breakdown ledger/progress needed to close Session 02 and unblock Session 03. Do not rewrite D-249-01..07 or mark the whole feature accepted.
- Leave `Test-Flight-Improv/00-INDEX.md` and `19-1to1-message-reliability-closure-reference.md` to Session 03, which exclusively owns final Plan-249 acceptance and stable closure synchronization.
- Run a separate closure review for evidence fidelity, retry/queued truth, residuals, scope, and dependency correctness. Reopen Session 02 only for a causal regression in its direct delivery/picker/action/wiring boundary.

## Execution Progress

| Time | Phase | Evidence | Result / next |
|---|---|---|---|
| 2026-07-11 18:38 CEST | planning baseline | Shared dirty-tree status; HEAD `84e8ead5d98928d60b1581bdb517b0f307503c35`; 24-path aggregate `f983c14bdb4243026a36d23d70f34674351b858bb382f5edb760e9c947b2ae12`; all eight proposed production/test owners and this plan were absent at that historical instant | Baseline captured read-only; at execution reassert only the eight owner/test absences because this plan now exists. |
| 2026-07-11 | plan authored | Accepted Session-01/source/breakdown contract; anchored current Graphify TDD context; current builder/delivery/picker/library/wiring/contact/l10n/test/gate source | Execution-ready; obtain independent plan review before causal RED. |
| 2026-07-11 | independent plan review | Two bounded documentation-correction passes covering strict ordinary delivery, contact/media races, cell/message truth, target freeze, denial feedback, RED ordering, and retry-denial state | `ACCEPTED`; no production/test/gate command or Graphify refresh ran. Executor must refresh the baseline after Session 05 finishes because shared wiring/l10n/gate files are moving. |
| 2026-07-11 | independent plan-review corrections | Authorized only a default-off strict ordinary seam, duplicated its post-preflight file/contact race proofs at seam and composed transport boundaries, corrected cell/message cardinality, froze all matrix-producing attempts, and typed cancel versus generic pre-route source denial | Execution-ready for independent re-review; no implementation evidence exists yet. |
| 2026-07-11 | Executor fresh post-Session-05 baseline | Full shared `git status --short`; SHA-256 of 17 existing owned paths; all eight planned production/test absences; exact baseline-safe forbidden-scope output/hash; current Graphify TDD query | Shared dirty tree preserved. All eight new owners/tests are absent. Existing-owned aggregate `663b50772dd69571e5ab713e8d61e40d004a5d7b4cddcf018e57fd8cf0bf3419`; forbidden-scope baseline `afd4d0f510030cacd6c8fbe2eea09c41710ff878544debf32eda0fa9a45a2197`. Graphify is current/anchored on the builder, ordinary coordinator, and Shared Media screen. This plan is present historical planning evidence, not an absence assertion. Next: add every causal test and strict-mode case before production, then capture the intended missing-API RED. |
| 2026-07-11 | Causal RED | Added all four new causal suites and four strict/default cases to the existing ordinary-coordinator suite before any production/l10n/gate edit. Ran the literal five-file combined command; first run also exposed three test-intake errors (`SemanticsFlag` import, a non-const identity fixture, and a nonexistent message-field assertion), which were corrected without production. The fresh complete rerun exited 1. | Authoritative RED is the intended absent contract: missing `direct_media_batch_forward_delivery_coordinator.dart`, missing picker/wired production, missing `launchBatchForward` screen parameter/type, and missing concrete `deliverDirectMediaBatchForwardStrict`. Every test file existed and was invoked. No production, l10n, gate, or unrelated file changed. Next: implement the typed application coordinator and strict ordinary seam, then reach application/transport GREEN before UI/wiring. |
| 2026-07-11 | GREEN implementation | Added the direct application coordinator, default-off strict ordinary seam, dedicated direct picker/route, Shared Media action/result reconciliation, `ConversationWired` source-first wiring, and EN/DE/AR generated localization. Updated the frozen transport inventory only after the real wiring changed its exact coordinator count. | Primary causal batch reached `42/42` before QA; exact preservation passed: Plan-234/current-row `27/27`, Plan-232 Forward/retry `3/3`, Plan-233 library/action `13/13`, generic picker `16/16`, l10n `3/3`, and expanded wiring inventory `1/1`. |
| 2026-07-11 | initial acceptance gates | Literal curated lane, host inventory, completeness, formatter/analyzer, script syntax, diff hygiene, registration, scope guard, and final Graphify `affected` over eleven production/generated owners. | Curated rerun reached `1,959/1,959`; host inventory `87`; completeness `1,174/1,174`; scoped formatter changed zero files and analyzer reported no issues. Exact forbidden-scope status hash initially matched baseline `afd4d0f510030cacd6c8fbe2eea09c41710ff878544debf32eda0fa9a45a2197`. |
| 2026-07-11 | independent QA pass 1 | Full contract/counterexample review plus bounded reruns. | `REJECT`: B1 missing behavioral `ConversationWired` proof, B2 incomplete 2x2 attachment/encryption evidence, and B3 missing failed-result Retry proof at compact EN/AR viewport. No production behavior defect was otherwise found. |
| 2026-07-11 | QA fixes 1-2 | Added real wired dependency/denial/order/result tests, fresh blob/key/nonce/scheme/envelope assertions, and compact failed-matrix Retry proof. The unchanged Arabic 320x568/1.3x test exposed a 5px production overflow; the preview rail was compacted while status is present. | Repaired suites passed `17/17`; the literal primary batch became `45/45`. The repair retained the original viewport/text-scale contract rather than weakening it. |
| 2026-07-11 | bounded exception pass 3 | Re-QA identified the untested retained-matrix plus live-retry-progress state. An explicit third-pass exception stayed within the same picker production/test scope: the screen now renders one live region (`progress` > source unavailable > settled matrix) while wired state retains the prior matrix; the compact test gates retry mid-flight and verifies summary restoration. | Exact compact proof `1/1`, full picker `8/8`, primary `45/45`, wiring sentinel `1/1`, and final curated `1,962/1,962`. Fresh independent QA `ACCEPTED` the explicit `fix_passes=3` exception with no residual finding. |
| 2026-07-11 | final proportional gates and scope | Host `1to1 --list`; completeness; 13-file formatter/analyzer; `bash -n`; `git diff --check`; registrations; final Graphify `affected`. Concurrent shared Plan-255/256 work added `00-INDEX`, two new plan paths, and two audio-test/fake status lines while QA ran. | Host inventory `87`; completeness `1,174/1,174`; format/analyze/diff/syntax clean. The original raw path-list hash was `d2af7c...`; removing only the five timestamped concurrent shared lines reproduced `afd4d0...`. With the execution-discovered inventory sentinel correctly added to the allowlist, the adjusted clean baseline is `67a101...`. Hashes prove path-list attribution only; the exact sentinel content hunk is independently reviewed and green `1/1`. |
| 2026-07-11 | post-QA architecture refresh | Exactly one `./graphify-arch/refresh_arch_graph.sh --incremental`, after final QA acceptance. | Exit `0`; 18 changed / 2,477 unchanged code files; graph 47,958 nodes / 74,471 edges; overlay 1,267 files / 12,393 named tests / 958 production targets. No second Session-02 refresh is authorized. |

## Execution Result

`accepted`

- RED-first history is preserved: all four new causal files plus strict ordinary cases existed before the first production API, and the authoritative combined run failed on those missing APIs.
- Final causal and preservation evidence is green: primary `45/45`, expanded wiring inventory `1/1`, Plan-234/current-row `27/27`, Plan-232 `3/3`, Plan-233 `13/13`, generic picker `16/16`, and l10n `3/3`.
- Final proportional gates pass: curated `1to1` `1,962/1,962`, host inventory `87`, completeness `1,174/1,174`, registration in both arrays and the definition doc, clean scoped format/analyze/script/diff checks, path-list scope attribution, and separate exact review/test of the already-dirty inventory sentinel's attributable content hunk.
- Fresh independent QA accepted the complete candidate with an explicit bounded `fix_passes=3` exception. The exception remained inside the picker/test scope and closed the live retry-progress compact-state defect without schema, wire, group, announcement, Go/relay, native, or device expansion.
- Final Graphify `affected` covered eleven attributable Dart/generated-localization owners, followed by exactly one successful post-QA incremental refresh. The three ARB localization sources were covered by `flutter gen-l10n` plus the `3/3` localization integrity/signal batch rather than passed as Graphify inputs.
- Session 02 is accepted and closed. Session 03 is pending/runnable and exclusively owns combined mutation audit and stable Plan-249 closure synchronization; overall Plan 249 remains `implementation-in-progress` / `still_open`.

## Closure Audit

- **Evidence fidelity:** RED, GREEN, preservation, curated, inventory, completeness, static, scope, QA, and refresh evidence is recorded without claiming full `host-all` or device/native/relay proof.
- **Behavioral boundary:** the user-visible flow remains direct-only ordinary-send composition. Source qualification precedes contact/file/picker delivery work; strict delivery re-reads contact/media state; matrices stay source-major and truthful; retry remains failed-cell-only.
- **Compact/accessibility boundary:** EN/AR 320x568 at 1.3x proves Send, failed summary, live retry progress, Retry, and restored prior summary without overflow; DE/EN/AR localization integrity remains green.
- **Shared-worktree safety:** no reset, stash, revert, or overwrite occurred. Concurrent Plan-255/256 index/plan/audio changes were preserved and explicitly excluded from Plan-249 attribution.
- **Dependencies:** Session 03 is now runnable. Plans 250/251 remain the separate group/announcement batch owners; overall Plan 249 remains open.
- **Reopen rule:** reopen Session 02 only for concrete regression evidence in its direct source/contact delivery matrix, strict ordinary seam, picker, Shared Media action, or `ConversationWired` route boundary.
- **Separate Closure Reviewer:** `ACCEPTED` after one documentation-fidelity correction bundle. The reviewer verified the execution-discovered inventory-sentinel scope, path-list-only hash semantics, adjusted `67a101...` baseline, eleven Graphify Dart/generated inputs plus separately gated ARBs, exact counts, bounded `fix_passes=3` exception, sole post-QA refresh, Session-03 runnable state, and still-open overall verdict. No residual closure blocker remains.
