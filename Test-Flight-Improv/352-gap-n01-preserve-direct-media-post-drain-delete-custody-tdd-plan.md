# 352 - GAP-N01 Preserve Direct-Media Post-Drain Delete Custody

Status: **EXECUTION_READY / REVIEWED / NOT IMPLEMENTED** (2026-08-09)
Type: Bug
Baseline observed while planning: b4e7d490ae0a51e8b9eecd79d0d014e9a04ca016 (docs: carry the notification coverage assessment through Plan 351)
Spec: UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md requirements 1, 3, and 6 plus A-01/A-02/A-03/A-24/A-26; gap inventory UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md GAP-N01 / WP-01 / section 9.2
Classification: execution-ready; one same-schema completion-boundary correction; core bet confirmed by tdd-review
Closure tier: host real-SQLite transaction proof, affected curated lane and core family only; no schema, relay, native, mobile, or iOS claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-09 | Evidence Collector | PRD economy guardrails; GAP-N01/WP-01; Plan 351; v108 completion; v111 cleanup; media deletion classifier; existing real-DB tests and gate ownership | Confirmed a steady-state hole: exact v108 acceptance moves the final v111 proof to cleanup, physical cleanup removes it, and outgoing attachment fingerprints remain null, so a later delete falls back to the legacy lane. | Define the smallest point at which exact lineage can survive proof retirement. |
| 2026-08-09 | Planner | v108 exact manifest validation, current-parent projection, Plan 351 terminal deletion ordering and the existing fingerprint function/column | Stamp exact per-attachment lineage inside accepted v108 completion only while an intact ordinary outgoing parent and complete matching attachment projection still exist. Preserve deletion-first completion independently. | Write causal tests and proportional gates, then invoke tdd-review. |
| 2026-08-09 | Independent Reviewer | Full Plan 352 contract; completion-versus-stage authority; delivered fast path; early/late rollback boundaries; existing repository assertion; literal gate ownership | Core bet confirmed, with three plan fixes: prove rollback after post-stamp v111 failure, make delivered authorship independent of shouldAdvance, and run the exact repository accepted-difference sentinel. Targeted re-review found all three closed and no remaining delta. Final verdict: READY. | Hand the amended plan to the arbiter; do not implement in this session. |
| 2026-08-09 | Arbiter | Corrected five-row contract; causal RED order; preservation boundary; run/not-run cadence and scope stop | Completion-time conditional stamping is the smallest sufficient correction. Stage-time stamping would broaden unaccepted and classifier states. Host-only focused plus curated/core evidence is proportional. Final verdict: READY. | Append the execution-ready ledger marker for a separate implementation session. |

## Problem And Evidence

- Behavior to improve: after a strict ordinary direct-media or voice initial has been accepted by protected inbox custody and its v111 cleanup rows have physically drained, a later delete-for-everyone must still select Plan 351's durable v109 deletion owner, including while the node is stopped.
- User impact: the normal successful initial-custody path can silently erase the only proof Plan 351 uses to recognize strict outgoing media. A later delete then takes the legacy path and can again depend on a running node, even though the same message previously completed the strict custody contract.
- Confirmed completion boundary: dbCompleteAcceptedDirectInboxCustodyIfExact validates the exact v108 incarnation, bound complete outgoing-stored v111 generation, manifest and earliest expiry, then deletes v108 and moves v111 to outgoing-cleanup-pending in the same transaction. It currently writes no direct_media_blob_custody_fingerprint to outgoing attachments.
- Confirmed proof retirement: dbDeleteDirectMediaBlobCleanupPendingIfExact physically deletes each exact cleanup-pending v111 row. It intentionally does not alter the attachment.
- Confirmed Plan 351 selector: a media parent with no v111 and an exact fingerprint on every physical direct attachment selects strictMedia; the same parent with all-null fingerprints selects legacyMedia. Generic attachment saves already preserve a non-null fingerprint.
- Confirmed storage primitive: DB v111 already owns the nullable, shape-constrained fingerprint column, and computeDirectMediaBlobCommitmentFingerprint derives the exact one-row digest from attachment ID plus custody kind, contract, content hash, ciphertext size, transport MIME, and that row's blob expiry. No migration or new durable owner is missing.
- Placement decision: use exact accepted v108 completion, not initial v108 staging or per-row v111 cleanup. Completion is the last atomic transition that both proves the complete bound generation and removes the reconstructable authority; it also covers pre-352 v108 rows that have not completed yet. Per-row cleanup could expose a mixed null/fingerprint generation.
- Rejected broader alternative: stamping at initial v108 stage would mark unaccepted attempts, miss the existing-winner path unless widened, and expose an all-fingerprinted plus live manifest-v108 plus missing-v111 contradiction that Plan 351's current classifier does not order safely. Fixing those extra states would broaden this defect correction without improving the demonstrated post-success case.
- Deletion-first exception: Plan 351 may tombstone the parent and remove attachments before the retained initial v108 later completes. In that state the v109 tombstone already owns future deletion truth, so exact v108 completion must continue to retire its independent v108/v111 obligation without requiring or recreating attachment fingerprints.
- Unresolved finding before review: whether the conditional completion-time stamp has any current-parent or retry counterexample that requires moving authority earlier. tdd-review must specifically try to refute this core bet.

## Graph Grounding Snapshot

- Query/profile: python3 graphify-arch/tdd_context.py query "Plan 352 dbCompleteAcceptedDirectInboxCustodyIfExact dbClassifyOutgoingDirectDeletionLane direct_media_blob_custody_fingerprint v108 completion v111 cleanup post-drain delete strictMedia legacyMedia" --profile tdd --budget 700
- Result: confidence anchored; fingerprint e4f8093572ef32f5 at the planning baseline.
- Primary anchors: dbCompleteAcceptedDirectInboxCustodyIfExact and dbClassifyOutgoingDirectDeletionLane.
- Graph omissions verified from source: exact v111 physical cleanup, the reusable Plan 351 real-DB fixtures, and host-gate option ownership.
- Reuse rule: Graphify is a shortlist. Execution must verify the exact source and test names at its clean HEAD.

## Scope Contract And Guard

In scope:

- Change only the exact accepted v108 completion transaction for a manifest-bound strict blob generation.
- When strictBlobRows is nonempty and the current messages row satisfies ownsMessage, is ordinary, is not user-terminal (deleted_at and hidden_at are null), and still projects expectedWireEnvelope, load its physical direct attachment projection in the same transaction. This fingerprint predicate is status-independent and must include the common delivered fast-path even though delivered is intentionally excluded from shouldAdvance.
- Require one attachment for every strict v111 row and no extras: exact message ID, owner lane, attachment IDs, and content hashes. Each v111 row must remain the already-proven outgoing-stored row bound to expectedIncarnationId.
- Derive each fingerprint from that row's full exact public commitment: custody kind, custody contract, content hash, ciphertext size, transport MIME, and its own expiresAtMs. Never substitute the v108 manifest hash, relayExpiresAt, or the generation's earliest expiry.
- Accept only a null fingerprint or that exact derived fingerprint. Prevalidate the complete set before the first write; a crossed but valid 64-hex digest, missing/extra attachment, mismatched hash, invalid row, or ambiguous projection returns stale and changes nothing.
- CAS-stamp null to exact, leave exact pre-stamped input unchanged, then re-read and verify the complete projection before the existing message projection, exact v108 deletion, and v111 cleanup transitions. A second completion after v108 retirement remains stale as today.
- Keep every write in the existing dbWriteTransaction. A fingerprint update, message projection, exact v108 deletion, or any v111 transition failure must roll back all fingerprints and all existing completion changes.
- If the current parent is missing, hidden, deleted, no longer outgoing to that recipient, or already superseded by a different envelope, preserve the current completion outcome and do not make attachments/fingerprints a new prerequisite. This protects Plan 351 deletion-first convergence. Do not confuse transport status delivered with this user-terminal/superseded exception.
- Leave dbClassifyOutgoingDirectDeletionLane unchanged. The new persisted value satisfies its already-implemented fully-drained strictMedia row.
- Leave initial v108 stage, v111 publication/transition/cleanup helpers, repository APIs, lifecycle drain, message use cases, schemas, and wire contracts unchanged.

Must preserve:

- Text-only v108 completion and every unbound/non-media custody row.
- Plan 351 live-v108 deletion coexistence, terminal-parent completion, exact v109 deletion stage, and historical all-null/no-v111 legacy lane.
- Plan 347 manifest, expiry, exact-envelope, cleanup, incoming fingerprint, source ACK/expiry, and retry semantics.
- Pre-352 generations whose v108 and v111 rows already drained remain legacy. There is no scan, backfill, lazy adoption, or historical promotion.
- Default-off client and relay admissions, mixed-version behavior, quota/capacity, account transfer, and platform behavior.

Hard do not:

- No DB v112, new column/table/index, repository capability, callback, queue, scanner, scheduler, migration, feature selector, receipt, relay/native/bridge change, or device harness.
- No stamping at initial stage, upload transition, generic v111 transition, per-row cleanup, generic attachment save, or Plan 351 classifier.
- No private/view-once/disappearing, group/announcement, media caption EDIT, linked-device fanout, artifact-erasure, activation, or release work.
- Stop for re-review if implementation needs more than the existing completion helper plus existing tests, or if it must change any public API or feature production file.

## Test Contract

| ID | Level / fixture | Arrange | Act | Assert | HEAD RED / mutation power |
|---|---|---|---|---|---|
| TC-352-01 | Core real SQLite; extend media_attachments_db_helpers_test.dart | Seed one exact delivered ordinary outgoing parent with two physical attachments and a bound outgoing-stored v111 generation whose rows have distinct expiry/commitment tuples plus one exact v108 owner. | Complete accepted v108, then physically delete every cleanup-pending v111 row and classify/stage deletion. | Completion returns messagePreserved, leaves the delivered parent/envelope unchanged, stamps the two independently derived exact fingerprints, retires v108, moves then fully drains v111, keeps the classifier strictMedia, and lets Plan 351 stage one tombstone plus one raw-event v109 row. | HEAD leaves both fingerprints null and classifies legacyMedia. Reusing shouldAdvance, one manifest, or one earliest/relay expiry stays red. |
| TC-352-02 | Core real SQLite with two test-only SQLite trigger faults; same existing file | Put crossed-valid-digest refusal first. Cover null and exact pre-stamped input plus missing/extra physical attachment, crossed physical attachment ID/hash, and a different valid 64-hex fingerprint. On a sending parent, one trigger aborts the second fingerprint update and a second scenario aborts the second v111 outgoing-stored to cleanup update after both fingerprints and message projection have run. | Attempt exact accepted completion for each matrix/fault row. | Null and exact pre-stamped input complete; every contradiction returns stale with message, fingerprints, v108 and v111 byte-for-byte unchanged; the first trigger proves partial stamping rolls back; the late v111 trigger proves message projection, all fingerprints, v108 deletion, and every v111 transition share one transaction. | HEAD fails the crossed-digest assertion before authorship. Splitting fingerprint writes into another transaction, removing prevalidation/CAS, overwriting crossed proof, or committing before the later v111 transition fails. |
| TC-352-03 | Feature application with existing MediaRepositoryRealDbFixture; extend delete_message_use_case_test.dart | Seed and complete one delivered strict outgoing media parent, assert completion preserves delivered status/envelope while authoring lineage, physically drain all cleanup v111 rows, retain its fingerprints, and stop the P2P node. | Delete the message for everyone. | The use case selects strictMedia, commits one tombstone and one exact v109 event before returning node-not-running, and performs zero network. | HEAD's fully drained row selects legacyMedia and returns before protected custody exists. |
| TC-352-04 | Core real SQLite GREEN preservation; existing media helper file | Seed a bound strict generation, then let a Plan 351 tombstone win and remove or partially remove its physical attachments before initial v108 acceptance completes. Also keep the existing text-only and historical matrices. | Complete the exact retained v108 and drain its v111 rows. | Completion preserves the tombstone, does not recreate or require fingerprints/attachments, retires the exact v108 once, and moves the independent v111 rows to cleanup. Text and historical behavior remain unchanged. | An unconditional fingerprint prerequisite strands Plan 351 deletion-first completion. |
| PRES-352-A | Feature repository accepted-difference sentinel; existing compound TC-345-02b/02c/02g in media_attachment_repository_impl_test.dart | Retain the raw exact-winner attachment snapshot taken before accepted completion and the stale generic save after completion. | Run exact completion and the stale save. | Every prior attachment field remains unchanged, the sole accepted difference is the exact newly authored fingerprint, the stale save cannot erase it, and the secure key remains the winner. | The current whole-row equality assertion must be narrowed deliberately; any unrelated row drift still fails. |

## Test Notes

- Record TC-352-01, TC-352-02, and TC-352-03 as independent causal REDs before production edits. TC-352-04 is a GREEN preservation guard and need not be forced red.
- Reuse seedBoundStrictParent and the Plan 351 real-DB fixture. Extend existing test files; do not create a new harness or registration row.
- TC-352-01 must use two distinct full commitments so a generation-level hash or one shared expiry cannot satisfy the test accidentally.
- TC-352-01 and TC-352-03 must pin status delivered. Fingerprint authorship follows exact owned lineage independently of shouldAdvance; accepted completion preserves the already-stronger delivered projection.
- TC-352-02 must put the crossed-valid-digest refusal first, then snapshot messages, media_attachments, direct_inbox_custody_outbox, and direct_media_blob_custody before each refused/faulted attempt. Retain both the second-fingerprint trigger and the later second-v111-transition trigger.
- TC-352-03 is the application-level proof that the new core lineage actually closes the node-off user path; do not replace it with a mocked classifier.
- PRES-352-A is a known accepted difference, not permission to weaken raw-row checks generally: compare all old fields exactly and assert the one computed fingerprint separately.
- Existing TC-347-04, TC-351-02, TC-351-03, and direct-text completion tests are exact preservation sentinels, not new duplicated matrices.

## Implementation Steps

1. First checkpoint the reviewed Plan 352, index, and append-only STATUS artifacts together (or begin after their owner does so). Then require a clean tree, record that execution HEAD, confirm STATUS contains Plan 351 EXECUTION_COMPLETED and Plan 352 EXECUTION_READY but no Plan 352 completion marker, and preserve unrelated work.
2. Add TC-352-01, TC-352-02, and TC-352-03 in the existing files. Run each exact plain-name command and retain non-zero causal evidence before production edits. Add TC-352-04 as a preservation guard and narrow only the known compound repository assertion for PRES-352-A.
3. In dbCompleteAcceptedDirectInboxCustodyIfExact, after exact strict v108/v111 proof and current-parent load but before any completion mutation, qualify fingerprint authorship with ownsMessage, not userTerminal, stillProjectsOwnedAttempt, and the ordinary policy. Keep it independent of shouldAdvance so delivered is included, then load the complete physical direct attachment projection.
4. Precompute the exact per-row fingerprints, reject every crossed/partial projection, CAS null values, accept exact pre-stamped input, and re-read the complete projection. Use no production failpoint; both rollback triggers remain test-only.
5. Leave terminal/missing/superseded parent completion on its current path without fingerprint authorship. Preserve the exact v108 delete and v111 transition ordering inside the same transaction.
6. Run the focused causal and preservation batch once after GREEN. Run host 1to1 once and only core-host-all with dart-only because the sole production change is a shared core DB helper.
7. Run analyzer, exact changed-Dart formatting, diff hygiene, and one incremental architecture refresh. Update Plan 352/index/coverage receipts only in the implementation session, and append EXECUTION_COMPLETED only after required evidence passes.

## Risks And Blind Spots

- One generation-level value could be copied to every attachment -> two distinct commitments in TC-352-01.
- A well-formed but crossed digest could be treated as lineage -> exact per-row recomputation and refusal in TC-352-02.
- Partial fingerprint writes or a split transaction could survive a later completion failure -> second-fingerprint and post-stamp v111-transition trigger aborts plus four-table snapshots in TC-352-02.
- Reusing shouldAdvance could skip the common delivered parent -> delivered messagePreserved assertions in TC-352-01/03.
- The existing repository raw-row sentinel could hide or reject the intended one-column delta -> exact accepted-difference PRES-352-A.
- Completion could strand a deletion-first terminal parent -> conditional skip and TC-352-04.
- A helper-only test could miss the real node-off delete selection -> real application fixture in TC-352-03.
- Stamping too early could expand accepted authority -> explicit completion-only boundary and no stage/classifier edits.
- Historical rows could be silently promoted -> all-null already-drained preservation and no backfill.
- Overengineering pressure -> one production helper, existing schema/function/fixtures, no public API, no feature production, no device proof.

## Gate Cadence

Run for this plan:

- Three exact causal RED commands before production edits.
- One combined focused GREEN over the two core helper files and delete-message use-case file.
- One exact accepted-difference repository sentinel because that existing feature file is outside both host 1to1 and core-host-all.
- Host curated 1to1 once. The delete use-case and direct-inbox helper are already registered; do not add batch flags because the wrapper rejects them for 1to1.
- Core-host-all once with batch Flutter, concurrency 2, and dart-only because one shared core DB helper changes and no Android manifest/platform boundary changes.
- Flutter analyzer, exact changed-Dart formatter check, git diff check, and one Graphify incremental refresh.

Do not run for this plan:

- No completeness-check: there is no new/moved test path or gate registration. If execution adds one, stop and re-review the scope before changing this disposition.
- No feature-host-all: no feature production surface changes; delete-message is executed directly and through host 1to1, while the affected repository assertion is run by one exact plain-name command.
- No full host-all: the GAP-N01/WP-01 dependency wave owns its aggregate run, and WP-07/final rollout owns the release run.
- No run_test_gates.sh 1to1: its Go/relay/toolchain tails are unchanged.
- No non-dart Android manifest contracts; dart-only intentionally excludes them.
- No migration, SQLCipher-device, Go, relay, native, binding, performance, feed, groups, posts, Android device/emulator, iPhone, or iOS simulator campaign.

## Acceptance Gates

~~~bash
# Clean implementation handoff.
git status --short
git rev-parse HEAD

# Causal RED 1: exact accepted completion must create durable per-row lineage.
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-352-01 exact accepted v108 completion pins per-attachment lineage through full v111 drain'

# Causal RED 2: crossed proof plus early and late transaction faults remain all-or-zero.
flutter test test/core/database/helpers/media_attachments_db_helpers_test.dart \
  --plain-name 'TC-352-02 outgoing lineage fingerprint CAS and v108 completion are all-or-zero'

# Causal RED 3: the fully drained application state still needs protected delete custody.
flutter test test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'TC-352-03 post-drain strict-media delete retains v109 while node stopped'

# One final focused causal/preservation batch.
flutter test --concurrency=1 \
  test/core/database/helpers/media_attachments_db_helpers_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart

# Exact accepted-difference sentinel outside host 1to1/core-host-all.
flutter test \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'TC-345-02b crossed saves preserve one owner through exact completion; TC-345-02c generic media staging cannot overwrite a consumed v108 winner; TC-345-02g completion-before-stale-save stays settled'

# Affected curated lane and sole justified family.
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all \
  --batch-flutter --concurrency 2 --dart-only

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
~~~

Explicit exclusions from the acceptance command block: completeness-check, feature-host-all, full host-all, run_test_gates.sh 1to1, Android manifest contracts, Go/relay/native/binding suites, migration/SQLCipher/device tests, performance families, Android/iOS device work.

## Execution Interpretation And Done Criteria

- Expected TC-352-01 RED: accepted v108 and v111 cleanup complete, but outgoing attachment fingerprints remain null and the drained deletion lane is legacyMedia.
- Expected TC-352-02 RED: current completion has no fingerprint CAS or rollback behavior to satisfy the matrix.
- Expected TC-352-03 RED: stopped-node delete returns through the legacy lane without a retained v109 event.
- Green preservation: terminal deletion-first completion, text-only completion, historical all-null media, incoming-authored fingerprints, exact v108/v111 cleanup, and Plan 351 state classification remain unchanged.
- Pre-existing dirty tree / known failure: none at planning baseline. No baseline failure is accepted.
- Environment blocker: none. Existing host SQLite fixtures prove the changed boundary; device availability is irrelevant because no platform boundary changes.
- Scope drift: any schema/public API/feature/native change, completion backfill/scanner, stage/classifier edit, new test path, device requirement, or second production file stops execution for re-review.

- [ ] Exact accepted v108 completion conditionally persists each exact attachment lineage before v108/v111 proof retirement. -> TC-352-01.
- [ ] Crossed/partial/faulted completion is all-or-zero, including a failure after fingerprints and message projection, and exact pre-stamped input is idempotent. -> TC-352-02.
- [ ] A fully drained strict media parent still stages one protected delete event while offline. -> TC-352-03.
- [ ] Deletion-first terminal completion and adjacent historical/text/incoming paths remain unchanged. -> TC-352-04 and named preservation tests.
- [ ] The existing repository winner remains byte-stable except for the one exact lineage fingerprint, which stale saves cannot erase. -> PRES-352-A.
- [ ] Focused GREEN, host 1to1, core-host-all dart-only, analyzer, format, diff, and one Graphify refresh are recorded.
- [ ] No activation, GAP-N01 closure, device/iOS, full host-all, or release claim is made.

## Handoff

- First RED: TC-352-01.
- Second independent RED: TC-352-02.
- User-path RED: TC-352-03.
- Manual registration: none.
- Migration: none; DB stays v111.
- Production edit expectation: direct_inbox_custody_outbox_db_helpers.dart only.
- Clean handoff: this planning session leaves only Plan 352, index, and STATUS changes uncommitted; checkpoint those planning artifacts before the first causal RED or production edit.
- Full-host owners: GAP-N01/WP-01 dependency-wave closure and WP-07/final rollout.
- Deferred: pre-352 already-drained generations remain legacy; caption EDIT and other GAP-N01 lanes remain separate.
- Do not implement in this planning/review session.

## Reviewer Findings

Fresh tdd-review first returned plan-fixes-required while confirming the completion-time core bet. It found three source-backed gaps in the draft:

1. A second-fingerprint trigger proved only early rollback and could not detect fingerprints committed separately before a later v111 failure.
2. The word nonterminal could let an executor reuse shouldAdvance and skip the common delivered parent even though delivered completion returns messagePreserved.
3. The existing compound TC-345-02b/02c/02g repository test compares the raw pre-completion attachment row and would reject the intentional fingerprint delta, yet neither host 1to1 nor core-host-all owns that feature file.

The amended plan adds an independent late second-v111-transition abort after fingerprint writes and sending-parent projection, pins delivered/messagePreserved in the core and application tests, and runs the exact repository accepted-difference sentinel while preserving every prior column. Targeted re-review returned READY with no remaining required delta. No tests were run because this was a planning/review session.

## Arbiter Decision

READY / EXECUTION_READY. The core bet is confirmed: exact accepted v108 completion is the atomic point that both proves the complete bound v111 generation and retires its reconstructable authority. Conditional per-attachment lineage stamping there closes Plan 351's steady-state post-drain delete hole without marking unaccepted attempts or widening classifier states. Terminal/deletion-first completion stays independent, already-drained pre-352 rows stay legacy, and no schema, public API, feature production, relay/native, device/iOS, backfill, new owner, or full-host gate is justified.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-09 | planning/review | planning artifacts only | tdd-plan plus fresh tdd-review and targeted re-review: READY | Source-grounded five-row contract, three causal REDs, early/late rollback mutations, delivered fast-path proof, exact repository sentinel, and proportional run/not-run gates | no plan-content blocker; implementation intentionally not started | execute in a separate session, then append EXECUTION_COMPLETED only after every required receipt passes |
