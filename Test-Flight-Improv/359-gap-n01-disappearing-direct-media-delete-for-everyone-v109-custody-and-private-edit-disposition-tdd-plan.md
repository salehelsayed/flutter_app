# 359 - GAP-N01 Disappearing Direct-Media Delete-for-Everyone v109 Custody And Private-EDIT Disposition

Status: EXECUTION_COMPLETED / independently reviewed / default-off / not release-eligible
Type: Modification
Baseline: `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6` (clean, committed, post-execution-audited Plan 358 closure HEAD)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` sections 3.1 and 5, A-01/A-03/A-28; `Test-Flight-Improv/234-1to1-private-media-lifecycle-tdd-plan.md` D-234-01/D-234-02/D-234-05; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / section 9.2
Classification: bounded mutation adopter plus explicit unsupported-product disposition; Plan 358's final durable disappearing lineage prerequisite is satisfied and revalidated
Closure tier: behavioral host tests with current-schema SQLite, physical v108/v109/v111 rows, secure-key/temp-file cleanup and actual lifecycle locks; no schema, relay/native, device, activation, or release boundary

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-11 | Evidence Collector / Planner | Graphify TDD context; Plans 234/351/352/356/357/358; deletion lane/stage/completion; sender cleanup/settlement; current deletion receive; private EDIT send/receive; tests and gates | The existing physical owners are sufficient. Exact disappearing lineage may adopt the strict-media DFE transaction; proof-less rows stay legacy. Private EDIT is unsupported rather than a new adopter. Plan 358 is actively being implemented, so Plan 359 may be reviewed now but not executed against its transient tree. | Write a prerequisite-gated contract with existing tests only. |
| 2026-08-11 | Test/gate inventory | Host `1to1`, full `host-all`, exact Plan 351/353/356/358 sentinels and existing fixtures | Seven named causal rows in existing files are sufficient. Use concurrency 4 for the filtered proof, one curated `1to1`, then the once-only direct-private/disappearing wave `host-all`; do not repeat core/feature families. | Run `$tdd-review`, then keep execution blocked until Plan 358 closes. |
| 2026-08-11 | Independent `$tdd-review` | Review-profile Graphify context; sender/storage/cleanup; receiver/private-EDIT; literal commands, registrations and gate cadence | Initial verdict was `plan-fixes-required`, core bet confirmed. Bounded amendments closed mutable hidden/expired lifecycle admission, authenticated private-EDIT ordering and unsupported-policy handling, exact baseline verification, TC-359-03/04 economy, and index handoff. Three targeted re-reviews returned READY for the declared prerequisite-blocked state. | Await Plan 358's audited closure SHA, amend the literal baseline, then rerun the required targeted revalidation before execution. |
| 2026-08-11 | Plan 358 prerequisite audit and targeted unblock review | Clean closure HEAD `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6`; current Graphify review context; final Plan 358 lineage/policy, cleanup, deletion, EDIT and test anchors | Plan 358 is post-execution-audit closed with no executable defect. Its post-drain fingerprint and proof-less/no-v111 distinction match this plan. Revalidation found one bounded guard: the fingerprint does not encode attachment cardinality, so the deletion stage and TC-359-01a must independently require exactly one MIME/mediaType-coherent image or video. No new test row, file, owner or gate is needed. | Prerequisite satisfied; Plan 359 is execution-ready against the pinned baseline. |

## Problem And Evidence

- Behavior to improve: after Plan 358, a newly authored disappearing image/video can retain exact initial blob/envelope lineage, but Delete-for-Everyone still selects only ordinary strict media or Protected/View-Once private custody. A strict disappearing parent can therefore tombstone and destructively clean through the legacy route without first retaining the authenticated deletion event in v109.
- Current sender split: `delete_message_use_case.dart` derives private cleanup/transport ownership only from Protected/View-Once and invokes the DB deletion-lane classifier only for policy-v0 ordinary parents. Disappearing rows therefore never select the strict media v109 stage, even when Plan 358's fingerprint/v108/v111 authority is durable.
- Current cleanup split: `DirectPrivateMediaLifecycle._mustRetainLivePrivateBlobCustody` protects only outgoing Protected/View-Once. A disappearing tombstone that still has a live v108/bound v111 generation could otherwise lose the attachment, key or bytes that the independent initial owner still needs.
- Current completion split: the shared physical v109 completion admits exact ordinary mutations and Protected/View-Once deletion, but explicitly refuses disappearing. A retained disappearing event would therefore never settle.
- Current receive split: `dbApplyIncomingDirectMessageDeletion` already owns atomic target re-read, tombstone, exact marker retirement and v111 independence, but it admits only ordinary or Protected/View-Once parents. The handler's existing exclusive lifecycle lease, private cleanup, reaction retirement and post-release receipt ordering need no new owner once the DB predicate admits exact disappearing state.
- Private EDIT product decision already exists: D-234-01 and `PrivateMediaEligibility` forbid new private caption/text EDIT. Proof-bearing private EDIT fails strict parsing today, but proof-less v1 private EDIT can still write a hidden placeholder or reach the generic edit save; the sender also lets a caller-supplied ordinary policy override a persisted redacted parent. Plan 359 closes those bypasses explicitly and does not invent private caption semantics.
- Existing reusable authority: the Plan 351 media lane selector and atomic v111+tombstone+v109 transaction, Plan 352/358 post-drain fingerprint, physical v109 lifecycle/drain/retry, ordinary transport settlement, private lifecycle cleanup/lock, current incoming-deletion transaction and existing `ignoredEdit` live/recovered terminal mapping already exist on DB v111.
- Expected production surface after Plan 358 closes: `lib/core/database/helpers/media_attachments_db_helpers.dart`, `lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart`, `lib/core/database/helpers/messages_db_helpers.dart`, `lib/features/conversation/application/delete_message_use_case.dart`, `lib/features/conversation/application/direct_private_media_lifecycle.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, and `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`. Stop and re-review before changing any repository interface/implementation, bootstrap, retry, deletion-handler, schema, wire, relay/native or other production file.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: architecture fingerprint `88c2f3f763067ef2`; current at the audited Plan 358 closure HEAD.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 359 disappearing direct-media Delete-for-Everyone v109 custody after Plan 358 strict lineage and fail-closed private media EDIT; anchors dbClassifyOutgoingDirectDeletionLane dbStageOutgoingDirectMediaDeletionInboxCustody dbStageOutgoingDirectPrivateDeletionInboxCustody deleteMessageForEveryone handleIncomingChatMessage" --profile review --budget 900`.
- Anchors: `dbClassifyOutgoingDirectDeletionLane` and `dbStageOutgoingDirectMediaDeletionInboxCustody` -> `media_attachments_db_helpers.dart`; v109 completion -> `direct_reaction_inbox_custody_outbox_db_helpers.dart`; public authoring -> `delete_message_use_case.dart`; private edit receive -> `handle_incoming_chat_message_use_case.dart`.
- Surfaced proof/gate files: media/direct-reaction DB helpers, delete sender, private cleanup race, incoming deletion, send chat, incoming chat, strict presentation and host `1to1`.
- Revalidation rule: after Plan 358's audited closure commit, rerun the focused Graphify query and source anchors. If its post-drain fingerprint, exact disappearing policy predicate, cleanup topology, or named TC-358 lineage proof differs from this contract, stop and amend/re-review Plan 359 before authoring REDs.

## Scope Contract And Guard

Satisfied prerequisite and execution guard:

- Plan 358 is cleanly committed and post-execution-audit closed at `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6`; all reviewed receipts are current and no executable defect was found. The acceptance preflight pins this exact SHA and permits only this plan's documentation handoff above it before RED.
- Revalidation confirms that an exact completed disappearing initial retains the Plan 358 fingerprint after v108/v111 drain, while proof-less/no-v111 historical disappearing rows remain distinguishable as legacy. Because that fingerprint alone does not encode attachment cardinality or MIME/mediaType coherence, Plan 359 must re-prove the exact one-image/video projection when creating a new deletion v109. Existing-v109 replay remains attachment-independent after cleanup and is authorized only by the unique envelope owner plus exact persisted tombstone.
- The seven expected production files and existing test paths below remain sufficient. Any additional production boundary, schema/API change, or missing Plan 358 invariant returns this plan to review.

In scope:

- Separate three concepts currently conflated in `deleteMessageForEveryone`:
  1. P/VO deletion keeps the Plan 356 private v109 stage and private settlement.
  2. An exact persisted disappearing parent always uses private lifecycle cleanup, but its transport owner is selected from DB lineage.
  3. Only a disappearing parent classified `strictMedia` by physical fingerprint/v108/v111 authority owns the Plan 351 media v109 stage; `legacyMedia` stays on ordinary legacy transport and `contradiction` refuses before encryption, cleanup or network.
- Reuse Plan 358's exact durable disappearing policy: outgoing v1 `disappearing`, duration in `{3600, 86400, 604800}`, state `available`, no sender-side received/expires/reveal/terminal/high-water clock, no edit/deletion predecessor, consumed v110 intent, and only lineage that Plan 358 could have authored. Before a new deletion v109 is inserted, independently require exactly one persisted direct-owned attachment whose MIME and `mediaType` coherently identify an image or video; a fingerprinted multi-attachment or crossed-media projection refuses. Do not impose that attachment check on an exact existing-v109 replay after cleanup. Never select on the caller's media list, selector state, or private policy snapshot.
- Capability-qualify the selected strict disappearing media stage, generic v109 lifecycle, private lifecycle/cleanup and ordinary settlement owners before encryption. A default-off/rollback build must still safely drain/delete a physical strict generation; the client selector is not deletion authority.
- For strict disappearing, mint one deletion event ID and encrypted inner/outer identity only after the DB lane selects `strictMedia`. Under the existing repository-wide private lifecycle lease, atomically transition only the exact eligible v111 rows, commit the tombstone and insert the exact raw-event v109 row, then run incumbent private terminal cleanup. Release the lease before node/live/inbox network work.
- Preserve live initial custody during terminal cleanup. Extend only the outgoing live-blob retention predicate from P/VO to exact disappearing, so a live v108/bound `outgoingPrepared|outgoingStored` generation retains its attachment/key/artifacts. Once v108/v111 have converged and only the Plan 358 fingerprint remains, the deletion may clean the exact private artifacts. Incoming deletion remains destructive while no-FK v111 converges independently, matching Plans 354/355.
- Keep proof-less/no-v111 disappearing on its legacy transport with no event ID or v109. It still uses the incumbent private lifecycle cleanup under the same lease rather than generic attachment deletion, so secure keys, thumbnails and lifecycle-owned files are not leaked or deleted outside their authority. Do not backfill or promote it.
- Keep disappearing transport settlement on the existing ordinary settlement owner, which already preserves v1 disappearing lifecycle columns. Do not widen the P/VO private retry/settlement boundary or add a repository capability.
- Widen `dbStageOutgoingDirectMediaDeletionInboxCustody` only from exact strict ordinary media to exact strict ordinary OR exact strict disappearing media. Keep the lane requalification, v111 transition set, v108 preservation, transaction and capacity unchanged.
- Harden that shared media stage's existing-v109 replay before admitting the new modality: query the completion-style outgoing `contact_peer_id + is_incoming=0 + wire_envelope` projection with `limit 2`, require exactly one owner whose ID is the supplied message ID, and require an exact persisted deletion tombstone for its policy. Exact replay wins before capacity; live, absent, crossed, malformed or ambiguous parents refuse with the existing v109 and all other rows byte-identical. Do not resurrect or converge a live parent from event bytes.
- At accepted v109 completion, admit the exact disappearing deletion tombstone only in the deletion branch: valid duration, state `available`, null sender clocks, exact deletion author/envelope and allowed settlement statuses. Local read/hidden drift remains independent. Completion remains attachment/v108/v111-independent after staging, including when cleanup or contact deletion removed the parent. Private EDIT remains stale/refused.
- On receive, extend only `dbApplyIncomingDirectMessageDeletion` to accept an exact persisted incoming v1 disappearing parent with an allowed duration, no v110 intent and the already-proven sender/contact identity. Authenticated author deletion must not be vetoed by mutable receiver-local lifecycle state: admit visible active, expired, and locally hidden rows, and preserve every clock/state byte rather than re-validating it as deletion authority. The real hide owner deliberately leaves state `available` while setting terminal/high-water. Invalid policy/duration, crossed author/direction or a remaining v110 intent refuse before writes.
- The incoming transaction preserves duration, received/expires/reveal/terminal/high-water/state/hidden columns and every v111 byte; it changes only the incumbent tombstone projection and exact target-scoped display retirement. Existing handler orchestration continues to serialize DB apply, exact private file/key/attachment cleanup and reaction retirement under the same lifecycle lease, then emits the exact event receipt after release. No handler production change is expected.
- Make private EDIT explicitly unsupported at both authority boundaries:
  - Sender: after loading the durable target and before recipient crypto/envelope construction, staging or network, reject any EDIT whose persisted target policy requires redaction, even if the caller supplies ordinary policy or stale media. The recipient key is already an argument here, so the causal contract does not claim a separately observable key lookup.
  - Receiver: preserve clear/inner identity validation first. A malformed strict non-EDIT keeps its current immediate refusal; only an invalid EDIT defers that decision. Authenticate sender/contact, then read the durable target once for the EDIT before Plan-353 caption, duplicate, missing-original or generic routing. A crossed parent author/contact remains `unauthorized`; otherwise an EDIT whose normalized wire policy or same-author durable target `requiresRedaction` returns `ignoredEdit`, including a persisted unknown-version `unsupported` checkpoint. Any remaining non-redacted invalid EDIT then keeps strict refusal. The ignored mutation writes no placeholder, parent, attachment, key or marker; publishes nothing; and sends no application mutation receipt. Existing live transport confirmation and recovered-inbox `ignoredEdit -> rejected` disposition terminally drain it without a new enum/outcome. D-234-01's action-specific private-EDIT prohibition controls; D-234-07's unsupported persistence applies to received media items, not an unsupported mutation that grants edit semantics.
- Keep ordinary text EDIT and Plan 353 ordinary caption-only EDIT behavior byte-identical. P/VO/disappearing private EDIT never gains v109, caption mutation or future compatibility inference in this plan.

Must preserve:

- Ordinary strict media DFE keeps its current media stage, replay, completion, cleanup and retry semantics, aside from the shared replay validation becoming stricter for impossible/crossed local state.
- Protected/View-Once DFE stays on the Plan 356 private v109 owner and private settlement; its completion and terminal cleanup remain unchanged.
- Plan 358 initial send/receive/download/expiry and its exact post-drain fingerprint remain unchanged. Deletion never resets a receiver deadline, treats v111 expiry as content expiry, or revives an expired card.
- Legacy disappearing rows remain proof-less and node-dependent, and selector-off does not suppress safe handling of already-physical strict lineage.
- Generic v109 failed/unacked replay, fair drain, ACK-or-expiry settlement and event identity need no production edit; their policy-neutral physical owner handles the new staged row.
- Group/announcement, linked-device fanout, historical/no-intent backfill, crash-complete general erasure and activation remain open.

Hard `Do not`:

- Do not add DB v112, a table/column/index, custody kind, second v109 owner, outbox, queue, drain, scheduler, lock, cleanup scanner, receipt type, feature flag, wire field or network caller.
- Do not modify repository interfaces/implementations, bootstrap, retry use cases, incoming deletion handler, relay/Go/native/bridge/bindings or platform code. Such a need is a stop/re-review signal, not implementation discretion.
- Do not widen on `policyVersion == 1`, caller media, selector state or the mere presence of an attachment. Outgoing selection/completion requires exact mode, duration, sender-clock shape and Plan 358/physical lineage; incoming authenticated deletion uses immutable policy/author authority and preserves rather than judges mutable receiver clocks.
- Do not support private caption EDIT, private media replacement, disappearing GIF authoring, group/device custody, historical promotion or production activation.
- Do not add a test file, gate registration, completeness campaign, sleeps, source-substring causal proof, separate core/feature sweep, dedicated device/relay/native campaign, or repeat whole files outside the once-only curated/wave gates.

Deferred / accepted difference:

- Pre-358 and already-drained rows without a Plan 358 fingerprint stay legacy permanently; no scan/backfill is added.
- A legacy eventless incoming disappearing deletion retains its incumbent compatibility branch and generic cleanup. Plan 359 changes only authenticated event-bearing receive authority; revisiting unowned legacy cleanup would require a separate compatibility decision and is not hidden inside this v109 adopter.
- Private EDIT is deliberately discarded as an unsupported product action, not retained for possible future replay. A future decision to support private caption edits requires a new adopter plan and cannot weaken this guard silently.
- Plan 359 closes the direct-private/disappearing code wave only. GAP-N01, group/announcement, per-device fanout, historical/no-intent disposition, activation, quota/UX and release evidence remain open.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-359-01a | For a new stage, exact Plan-358 disappearing lineage plus exactly one persisted MIME/mediaType-coherent image or video atomically commits the exact v111 transition+tombstone+v109; insert failure is all-zero, while fingerprinted multi-attachment, crossed-media and proof-less/partial projections refuse. Separately, attachment-independent exact persisted-tombstone replay wins before capacity after cleanup, while live/absent/crossed/ambiguous/malformed replay refuses byte-identically. Include an ordinary strict control. | `TC-359-01a disappearing media deletion stages only exact lineage and revalidates an existing v109 tombstone` | Core, real current-schema SQLite; direct SQL seeds physical lineage and capacity | Current stage is ordinary-only and its existing-event branch trusts a same-ID parent without exact tombstone/unique-envelope proof. | Restore ordinary-only admission, omit new-stage attachment-shape requalification, or restore blind same-ID replay; the compact matrix reds. | Existing `media_attachments_db_helpers_test.dart`; core AUTO, exact filtered run and wave host-all. |
| TC-359-01b | Exact disappearing deletion completion settles status/transport, preserves duration/state/all clocks, and retires only v109 even after artifacts/parent disappear. Crossed/malformed disappearing and every private EDIT remain stale; exact P/VO control stays green. | `TC-359-01b disappearing deletion completion is exact and private EDIT remains refused` | Core, real SQLite physical v109 | Current completion explicitly excludes disappearing. | Broad `policyVersion==1` admission makes P/VO/disappearing EDIT or bad duration pass and reds. | Existing `direct_reaction_inbox_custody_outbox_db_helpers_test.dart`; already in `1to1`. |
| TC-359-02a | Public DFE ignores caller media, selects exact persisted disappearing lineage, stages v109 before cleanup/network, and on node-off retains one event with zero network plus ordinary failed settlement. Proof-less historical disappearing keeps legacy/no-v109 transport but uses private cleanup; capability absence or contradiction is all-zero. | `TC-359-02a disappearing DFE uses physical lineage and ordinary settlement without promoting legacy rows` | Feature/application fakes backed by the real lane/stage or delegated real-DB repository | Current application never selects disappearing and uses generic cleanup/no v109. | Bypass the DB lane or mint identity before strict selection; the order/inventory assertions red. | Existing `delete_message_use_case_test.dart`; already in `1to1`. |
| TC-359-02b | Actual lifecycle contenders prove both orders. A live v108/bound v111 generation retains exact key/attachment/files through deletion; post-drain fingerprint-only lineage cleans them. No contender/network enters between selected stage and private cleanup. | `TC-359-02b disappearing DFE serializes stage to cleanup and retains live initial custody` | Feature host, real lifecycle lock, temp files/secure-key fake, external-Zone completers; no sleeps | Current retention predicate is P/VO-only and media stage+generic cleanup do not share the private lease. | Remove disappearing retention or the outer lease; the blocked-start/inventory assertions red. | Existing `private_media_cleanup_race_test.dart`; already in `1to1`. |
| TC-359-03a | One compact event-bearing DFE row covers visible-active, real-hide-generated, and real-expiry-generated disappearing parents. Each tombstones, preserves every receiver clock/state and v111 byte, retires exact markers/reactions, performs private file/key/row cleanup, then receipts only after lease release. Bad duration/policy/direction/author refuses with zero receipt/effects. | `TC-359-03a incoming disappearing deletion preserves lifecycle and v111 before exact receipt` | Feature host, real DB/shared lock, temp files and secure-key fixture | Current DB apply refuses disappearing before the incumbent handler owner can act. | Restore disappearing refusal or route cleanup generic; the durable/cleanup/receipt assertions red. | Existing `handle_incoming_message_deletion_use_case_test.dart`; already in `1to1`. |
| TC-359-04a | An outgoing EDIT targeting a persisted P/VO/disappearing parent refuses before crypto/envelope construction, staging or network even when caller policy is forged ordinary. Ordinary edit controls remain eligible. | `TC-359-04a persisted private target defeats caller policy drift before EDIT effects` | Feature/application owner test with effect counters | Current effective policy may trust the caller override instead of persisted redacted authority. | Remove the persisted-target guard; forged ordinary reaches crypto/stage and reds. | Existing `send_chat_message_use_case_test.dart`; already in `1to1`. |
| TC-359-04b | Three causal authenticated shapes—proof-less redacted absent target, proof-bearing redacted EDIT, and forged-ordinary same-author durable `unsupported(sourceVersion: 9)` target—return `ignoredEdit`, write no placeholder/parent/attachment/key/marker, publish nothing and emit no application receipt. A crossed-author target remains `unauthorized`; malformed strict non-EDIT, ordinary text and Plan-353 caption controls retain their existing order/outcomes. | `TC-359-04b private EDIT is terminally ignored before strict caption missing or generic edit branches` | Feature handler test; repository snapshots and effect counters | Proof-bearing strict private is retryably refused today, while proof-less private edit can write a placeholder or generic edit. | Remove the post-auth redaction guard; one or more causal shapes reach the wrong owner and red. | Existing `handle_incoming_chat_message_use_case_test.dart`; already in `1to1`. |

## Test Notes

- Author every `TC-359-*` row only after the Plan 358 prerequisite is accepted. The first RED must compile against existing APIs and fail behaviorally; seed physical Plan 358 lineage directly instead of calling a new Plan 359 symbol.
- TC-359-01a uses the exact post-drain fingerprint case as the primary new-stage seed, then representative live v108/bound v111 and malformed rows. Its compact new-stage attachment matrix includes one valid image/video representative plus fingerprinted multi-attachment and MIME/mediaType-crossed negatives. The existing-v109 replay subcase deliberately has no surviving attachment. Test all three allowed durations compactly but do not cross-product duration, media type and lifecycle state.
- TC-359-01a's existing-v109 matrix must include an ordinary strict control, one exact disappearing tombstone at capacity zero, and live/absent/duplicate-envelope/crossed-policy negatives. Final-state-only or same-ID-only assertions are insufficient.
- TC-359-02b competitors are created outside the current lock owner's Zone and expose attempted/entered/release completers. Sleeps or two sequential end states do not prove exclusion.
- TC-359-03a reuses the real current-deletion handler owner rather than adding a duplicate DB-only disappearing suite. Its one named row creates all three promised projections through their real owners: visible active, hide-generated `available + terminal/high-water`, and expiry-generated `expired`. Do not add another contact-race, reaction-failure or lock-order matrix already proved by Plans 356/357.
- Rework the two existing private-edit tests that currently expect generic `chatMessage` acceptance. Preserve their lifecycle anti-resurrection assertions while changing the disposition to zero-effect `ignoredEdit`; use only the three causal authenticated shapes plus the crossed-author control, and do not leave contradictory old expectations or add a mode/state/proof cross-product.
- Extend/narrow exact accepted differences rather than weakening them: TC-356-01b's disappearing-completion negative moves to TC-359 positive, while its private-EDIT and P/VO controls remain; the existing proof-less disappearing DFE test remains legacy/no-v109 but now expects private-owner cleanup.
- Retry production is unchanged. Do not add a new failed/unacked matrix; physical policy-neutral retry remains covered by existing Plan 356 and the final wave gate.

## Implementation Steps

1. Preserve the accepted Plan 358 closure SHA, current Graphify fingerprint and targeted unblock review recorded above. The preflight must fail on any intervening production/test/platform/gate drift before authoring tests.
2. Snapshot `git status --short`. Add the seven causal tests in existing files and run the single `TC-359-` concurrency-4 RED. Record every semantic failure; missing-symbol or skipped tests do not count.
3. In `media_attachments_db_helpers.dart`, admit only the exact Plan 358 disappearing policy plus exactly one persisted MIME/mediaType-coherent image/video attachment when creating a new media deletion v109. Harden existing-v109 replay separately to one unique outgoing envelope owner plus exact persisted tombstone without requiring an attachment that cleanup may already have removed. Keep capacity order, transaction and ordinary behavior.
4. In `direct_reaction_inbox_custody_outbox_db_helpers.dart`, admit exact disappearing deletion completion only. Preserve attachment-independent settlement, removed-parent convergence and private-EDIT refusal.
5. In `delete_message_use_case.dart`, separate cleanup policy from transport owner. Classify persisted disappearing lineage before encryption; run strict media stage or legacy ordinary stage plus private cleanup under the incumbent lifecycle lease; retain ordinary settlement and release before network.
6. In `direct_private_media_lifecycle.dart`, extend only outgoing live-v111 retention to exact disappearing. Keep incoming deletion destructive and cleanup-pending/post-drain convergence unchanged.
7. In `messages_db_helpers.dart`, admit exact-policy incoming disappearing rows to the existing current-deletion transaction without making mutable receiver clocks/state a deletion precondition; preserve every lifecycle/v111 field.
8. In `send_chat_message_use_case.dart` and `handle_incoming_chat_message_use_case.dart`, add the persisted/wire private-EDIT guards before effects. On receive, keep malformed strict non-EDIT refusal exactly where it is, but defer invalid EDIT handling through authenticated sender/contact plus one durable target read; retain crossed-author `unauthorized`, use `requiresRedaction` for wire and durable targets, and broaden the existing `ignoredEdit` documentation with the D-234 unsupported-mutation arbitration. No repository/listener/recovered-disposition change is authorized.
9. Run the single final filtered proof at concurrency 4, then host `1to1` once. Execute the once-only direct-private/disappearing wave `host-all` at concurrency 4; this subsumes core/feature families, so do not run either separately.
10. Run analyzer, changed-Dart format, baseline/staged/unstaged diff hygiene and one incremental Graphify refresh. Update Plan 359/index/status/coverage receipts without rewriting historical Plan 358 evidence.

Stop/re-review if Plan 358 is not post-audit clean, its lineage/policy contract changed, or implementation requires any new schema, interface/repository/bootstrap/retry/handler owner, DTR re-pin, wire/network/platform change, test path/registration, private EDIT custody, or production file outside the expected seven.

## Risks And Blind Spots

- Broad v1 widening -> exact duration/state/null-clock and physical-lineage matrices plus P/VO/private-EDIT controls fail closed.
- Caller snapshot becomes authority -> TC-359-02a forges media/policy while DB lineage alone selects the owner.
- Existing event authorizes wrong parent -> unique envelope projection plus exact persisted tombstone is tested before capacity.
- Cleanup strands live initial custody -> TC-359-02b pins v108/v111/key/file retention and both actual lock orders.
- Deletion resets or vetoes receiver lifecycle -> TC-359-03a snapshots every clock/state and v111 around visible, expired and real-hide-owned projections.
- Private EDIT sneaks through another branch -> send and receive causal rows cover caller-policy drift, proof-less missing/live and proof-bearing controls before effects.
- Retry test explosion -> no retry production changes and no new retry matrix; use the wave gate for policy-neutral owner preservation.
- Wave gate duplication -> run full `host-all` once here, then omit core/feature and do not run another full host sweep until final rollout/release closure.
- Concurrent Plan 358 implementation -> the explicit accepted-baseline prerequisite prevents tests or predicates from being authored against a transient contract.

## Gate Cadence

- Inner loop: individual plain-name tests only while implementing; do not record or repeat every diagnostic run.
- First RED: one selector-on concurrency-4 invocation over the seven existing causal paths with `--name 'TC-359-'`.
- Final focused proof: one concurrency-4 invocation over the same paths plus only the load-bearing out-of-lane sentinels. The Plan 358 define is enabled for its lineage sentinel; Plan 359 itself must also pass in the default-off curated/wave runs.
- Curated closure: `./scripts/run_host_test_gates.sh 1to1` exactly once. It accepts no batch/concurrency option and currently resolves 120 unique paths; record the live count.
- Wave closure: because Plan 358 explicitly deferred the direct-private/disappearing dependency-wave full sweep to Plan 359, run `host-all` once with one Flutter batch at concurrency 4 plus its normal non-Dart tails. This is a wave exception, not a new per-plan default. Do not also run `core-host-all` or `feature-host-all`.
- No dedicated migration/SQLCipher/account-transfer, relay/Go/native/bridge/bindings, device/Android/iOS, groups/feed/posts/performance/baseline, non-host `run_test_gates.sh 1to1`, completeness, registration, or ad-hoc whole-file campaign. The one wave `host-all` supplies its incumbent tails; no separate platform campaign is launched.
- Expected DTR impact: none. If a frozen repository/bootstrap file must change, stop and re-review rather than automatically re-pin.

## Acceptance Gates

Run only after the prerequisite is satisfied and `PLAN359_ACCEPTED_BASE` is the exact audited Plan 358 closure SHA.

```bash
# Snapshot and fail fast unless execution descends from the exact clean,
# audited Plan-358 closure SHA recorded during prerequisite unblocking.
PLAN359_ACCEPTED_BASE=4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6
test -z "$(git status --porcelain)"
git rev-parse --verify "${PLAN359_ACCEPTED_BASE}^{commit}"
grep -F "Baseline: \`$PLAN359_ACCEPTED_BASE\`" \
  Test-Flight-Improv/359-gap-n01-disappearing-direct-media-delete-for-everyone-v109-custody-and-private-edit-disposition-tdd-plan.md
git merge-base --is-ancestor "$PLAN359_ACCEPTED_BASE" HEAD
test -z "$(git diff --name-only "$PLAN359_ACCEPTED_BASE"...HEAD | \
  grep -E '^(lib|test|integration_test|android|ios|go-[^/]+|scripts)/' || true)"

# One behavioral RED before Plan-359 production edits. Every selected row must
# compile, execute and fail for its documented current boundary.
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --name 'TC-359-'

# One final causal + preservation proof. Verify every selected name ran.
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  --name 'TC-359-|TC-358-01c accepted disappearing custody preserves strict lineage through v111 drain|TC-356-01b private deletion v109 stage and completion preserve independent lifecycle authority|TC-356-04b event-bearing protected and view-once deletion use private cleanup reactions and exact receipt|TC-356-04c current private deletion and strict presentation|TC-353-04 strict caption edit routes before the generic branches'

# Default-off curated lane once; no batch/concurrency flags.
./scripts/run_host_test_gates.sh 1to1

# Once-only direct-private/disappearing dependency-wave closure. This already
# contains core, feature and the incumbent non-Dart tails; do not duplicate them.
./scripts/run_host_test_gates.sh host-all \
  --batch-flutter --concurrency 4 --reporter failures-only

# Static/hygiene checks on the final tree.
set -euo pipefail
plan359_base_ref="$PLAN359_ACCEPTED_BASE"
flutter analyze

plan359_dart_list="$(mktemp)"
trap 'rm -f "$plan359_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR \
    "$plan359_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan359_dart_list"
test ! -s "$plan359_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan359_dart_list"
rm -f "$plan359_dart_list"
trap - EXIT

git diff --check "$plan359_base_ref"...HEAD
git diff --check
git diff --cached --check

./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan359_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

## Execution Interpretation And Done Criteria

- Expected RED: seven named rows fail behaviorally because disappearing DFE is not admitted/retained/completed/received and proof-less private EDIT still reaches generic behavior; no missing symbol, skip or source-string failure counts.
- Green preservation: ordinary strict DFE, P/VO DFE, Plan 358 lineage/expiry, ordinary caption EDIT, default-off legacy disappearing and generic v109 drain remain unchanged.
- Representative mutation re-reds: five independent mutations are required and reverted—restore ordinary-only disappearing stage or bypass its exact lineage; remove the stage-to-cleanup lease/retention; restore incoming disappearing refusal; remove the persisted-target sender EDIT guard; remove the early receiver private-EDIT guard.
- Accepted baseline: Plan 358's transient worktree is not an execution checkpoint. Execution begins from a clean descendant of the exact audited SHA, with only the reviewed Plan-359 documentation handoff above it before RED.
- Scope drift: any schema/interface/repository/bootstrap/retry/new owner/test-path/platform expansion returns the plan to review.

- [x] Plan 358 has a clean committed GREEN, post-execution audit and recorded accepted SHA.
- [x] Every behavior has a named causal test or exact preservation control; all seven causal rows are real behavior tests.
- [x] One combined RED (`+0 -7`), one combined final proof (`+12`) and five representative mutation re-reds (plus two extra storage sub-mutations) are recorded.
- [x] Exact disappearing DFE retains v109 before private cleanup/network; proof-less rows never promote.
- [x] Live initial v108/v111 authority retains its exact attachment/key/artifacts; post-drain lineage cleans safely.
- [x] Completion and incoming deletion preserve all disappearing lifecycle columns and independent v111 authority.
- [x] Private EDIT is rejected/ignored before effects on both sender and receiver, while ordinary EDIT remains unchanged.
- [x] Host `1to1` (120/120 paths) and the once-only wave `host-all` ran once each; core/feature were not rerun separately. The wave's Flutter batch was `+13904 ~11 -9` over 1339 paths and its 8 non-Flutter tails passed; the 9 failures are the pre-existing `test/integration/**` notification/relay-degradation set, reproduced identically at the accepted baseline in a clean worktree.
- [x] No new test path/registration/completeness, schema, DTR re-pin, device or dedicated relay/native campaign is added.
- [x] Analyzer, changed-Dart format, baseline/staged/unstaged diff hygiene and incremental Graphify (`7a7dc08f28bf4b4d`) are clean.
- [x] Plan/index/status/coverage receipts remain append-only and make no activation, GAP-N01 or release claim.

## Handoff

- Execution state: EXECUTED against accepted Plan 358 closure `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6`. The literal preflight passed with documentation-only drift above the base, and every gate in the cadence ran exactly as authorized.
- Recorded receipts: RED `+0 -7`; TC-359 rows `+7`; the seven owning files in full `+400`; the single nine-file filtered proof `+12`; 5/5 documented mutation re-reds plus two extra storage sub-mutations; host `1to1` PASS at 120/120 paths; the once-only wave `host-all` Flutter batch `+13904 ~11 -9` over 1339 paths with its 8 non-Flutter tails 8/8 PASS.
- Attributed pre-existing failures: the 9 wave reds are `android_picture_in_picture_interruption_ownership`, `chat_notification_dedupe_integration`, `ios_notification_provider_adapter_contract`, `live_direct_notification_integration` (x2), `live_direct_notification_simulation` (x2) and `relay_down_degradation_integration` (x2). All reproduce identically at the accepted baseline in a clean detached worktree and are outside this plan's surface. Because the script aborts before its tails on a red batch, the 8 Go/non-Dart tails were executed separately and all passed.
- Contract correction during execution: TC-359-02b originally proved only the deletion-first lock order. Its contract requires BOTH, so Order B was rewritten as a genuine reverse order (incumbent contender holds the lease first) while keeping the live-custody retention assertions, and the in-flight first `1to1` run was stopped rather than allowed to certify a stale tree. `1to1` therefore still ran exactly once to completion.
- Second accepted-difference restatement: `messages_db_helpers_test.dart` is an eighth EXISTING test path touched only to narrow TC-356-04a's disappearing negative to the malformed no-duration shape and add the exact positive. No test file, path or registration was created.
- Manual registration/migration: none; every test extends an existing path and DB remains v111.
- Runtime defaults: the client selector and relay admissions remain default-off; physical custody remains drainable/deletable after rollback.
- Deferred: group/announcement event and blob custody, linked-device fanout, historical/no-intent disposition, crash-complete general erasure, activation/operations/quota UX, device/iOS evidence, final release evidence and legacy retirement. GAP-N01 remains open and no PRD control score moves.

## Reviewer Findings

Initial verdict: **plan-fixes-required; core bet confirmed**.

Required fixes were applied:

- Incoming disappearing deletion now gates on immutable policy/duration/direction/author/no-v110 authority and preserves mutable receiver lifecycle bytes. TC-359-03a uses the real owners to cover visible-active, hide-generated `available + terminal/high-water`, and expiry-generated `expired` projections without another race matrix.
- Private EDIT ordering is explicit: non-EDIT strict-invalid refusal stays in place; EDIT proceeds through authenticated sender/contact and one durable target read; crossed author is unauthorized; wire or target `requiresRedaction` yields terminal `ignoredEdit` before strict/caption/missing/generic routing. This includes unknown-version unsupported targets while preserving transport confirmation and suppressing only the application mutation receipt.
- TC-359-04b is limited to three causal authenticated shapes plus one crossed-author control. Existing listener/recovered mapping and Plan 353 ordinary caption behavior remain preservation evidence rather than duplicated matrices.
- The execution preflight now requires a clean tree, a valid accepted commit matching the literal Baseline recorded in this plan, ancestry, and no intervening production/test/platform/gate drift. It permits only the reviewed Plan-359 documentation handoff above the eventual Plan-358 base.
- The index and append-only status ledger now record the execution-ready handoff after Plan 358's audit closed.
- Final-source revalidation additionally requires one persisted coherent image/video attachment before a new deletion v109 is created because the post-drain fingerprint alone does not encode cardinality. Exact existing-v109 replay stays attachment-independent after cleanup. Both are covered inside TC-359-01a without a new row or gate.

Targeted storage/sender, receiver/private-EDIT and gate/economy re-reviews returned **READY**, and the final Plan 358 source/baseline audit confirmed the same owners after the bounded attachment-shape tightening. No tests were rerun during this read-only unblock review.

## Arbiter Decision

**EXECUTION_READY. Core bet confirmed.** Plan 359 is one bounded mutation slice: strict disappearing DFE reuses the existing media v109 transaction and private cleanup authority, legacy disappearing never promotes, and private EDIT is explicitly discarded through existing outcomes rather than gaining custody.

The proof is intentionally lean: seven causal rows in existing files, one concurrency-4 RED, one concurrency-4 final filtered proof, host `1to1` once, and the once-only direct-private/disappearing wave `host-all` at concurrency 4. That wave gate subsumes core/feature; no separate family, device, relay/native, completeness or registration campaign is authorized.

The prerequisite is satisfied at the pinned clean Plan 358 closure SHA. Current Graphify/source anchors and the exact lineage/legacy distinction were revalidated; execution may begin after the literal clean-tree/no-code-drift preflight passes.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-11 | planned | plan artifact only | No tests run; read-only planning against an active Plan 358 worktree | Existing owners and tests mapped; Plan 358 still in implementation | Prerequisite blocked | Await clean audited Plan 358 baseline, then author causal REDs. |
| 2026-08-11 | prerequisite unblocked | Plan 358/359 artifacts, index, status and coverage | Clean closure HEAD `4e24d7451c30d2a6f6f609dfcc3b0880d2ac70f6`; Graphify review fingerprint `88c2f3f763067ef2`; targeted source/gate reviews | Plan 358 audit closed with no executable defect; Plan 359 owners and tests remain sufficient; TC-359-01a now independently proves one coherent image/video projection | Execution-ready | Run the literal preflight, then author the seven behavioral RED rows. |
| 2026-08-11 | RED | Seven existing causal test paths plus the two accepted-difference restatements | Preflight clean at the pinned baseline with documentation-only drift; one concurrency-4 selector-on `--name 'TC-359-'` invocation over the seven paths returned `+0 -7` | Every row failed behaviorally at its documented current boundary: the stage never reaches its transaction for disappearing, completion is `stale`, DFE returns no tombstone, the retention predicate is P/VO-only, incoming apply is `unauthorized`, the sender reaches the caption-edit branch, and the receiver returns `editMissingOriginal` | No missing symbol, skip or source-string failure | Implement the seven owners. |
| 2026-08-11 | GREEN | `media_attachments_db_helpers.dart`, `direct_reaction_inbox_custody_outbox_db_helpers.dart`, `messages_db_helpers.dart`, `delete_message_use_case.dart`, `direct_private_media_lifecycle.dart`, `send_chat_message_use_case.dart`, `handle_incoming_chat_message_use_case.dart` | TC-359 rows `+7`; the seven owning files in full `+400`; the single nine-file filtered proof `+12` (7 rows + 5 out-of-lane sentinels) | Exactly the reviewed seven-file surface; no schema, interface, bootstrap, retry, handler owner, DTR re-pin, new test path or registration | Executed as reviewed | Run the mutation re-reds, then the gates. |
| 2026-08-11 | mutations | Production owners only, each reverted immediately | 5/5 documented re-reds plus two extra storage sub-mutations, all `-1` and reverted: ordinary-only stage; omitted attachment requalification; restored blind same-ID replay; removed disappearing live retention; removed the stage-to-cleanup lease; restored incoming disappearing refusal; removed the sender persisted-target guard; removed the receiver private-EDIT guard | Every guard is load-bearing | Tree restored clean before any lane | Run host `1to1`, then the wave `host-all`. |
| 2026-08-11 | contract correction | `private_media_cleanup_race_test.dart` | TC-359-02b Order B rewritten as a genuine reverse lock order (incumbent contender holds the lease first, deletion blocked behind it) while keeping the live-custody retention assertions; the in-flight first `1to1` run was stopped rather than allowed to certify a stale tree | The row now proves BOTH orders as its contract requires; the lease mutation re-reds it | Both orders proven with no sleeps | Rerun the filtered proof, then the lanes once each. |
| 2026-08-11 | gates | Whole tree | Final filtered proof `+12`; host `./scripts/run_host_test_gates.sh 1to1` **PASS**, 120/120 paths measured live, zero FAIL; wave `host-all --batch-flutter --concurrency 4 --reporter failures-only` Flutter batch `+13904 ~11 -9` over 1339 paths, then its 8 non-Flutter Go tails run separately (the red batch aborts before them) — 8/8 PASS | The 9 batch failures are all `test/integration/**` notification/relay-degradation rows and reproduce IDENTICALLY at the accepted baseline `4e24d7451` in a clean detached worktree, so they are pre-existing and outside this plan's surface | Wave closure accepted with the pre-existing set explicitly attributed | Run hygiene, Graphify and receipts. |
| 2026-08-11 | hygiene | Whole tree | `flutter analyze` clean; changed-Dart `dart format --set-exit-if-changed` clean over the full baseline/unstaged/staged/untracked set (three test files needed formatting and were reformatted and rerun `+263`); all three `git diff --check` variants clean; one incremental Graphify refresh (15 changed / 3,136 unchanged; 71,046 nodes / 104,386 edges; fingerprint `7a7dc08f28bf4b4d`) | Clean | Executed | Record plan/index/status/coverage receipts. |
