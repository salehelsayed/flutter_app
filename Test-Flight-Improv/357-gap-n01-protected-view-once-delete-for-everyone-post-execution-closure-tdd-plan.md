# 357 - GAP-N01 Protected/View-Once Delete-for-Everyone Post-Execution Closure

Status: execution-ready / reviewed / not implemented
Type: Bug / modification
Baseline observed while planning: `ca5f2174c9bd4cbdbc54d02a92a70610a111f150` (`feat(356): adopt physical v109 custody for private delete-for-everyone`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` sections 3.1 and 5, A-01/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / section 9.2
Classification: bounded post-execution repair of Plan 356's existing Protected/View-Once deletion adopter; no new modality or durable authority
Closure tier: behavioral host tests with real current-schema SQLite and the actual private lifecycle/contact owners; no schema, relay/native, device, iOS, activation, or release boundary

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-10 | Post-execution auditors | Plan 356 contract/receipts; physical v109 private stage; sender cleanup; incoming deletion handler; contact deletion; retry and lifecycle race tests | Three executable defects and three weaker-than-reviewed proofs invalidate Plan 356's code-closure claim. Historical receipts remain real but insufficient. | Repair the incumbent owners before adopting disappearing media. |
| 2026-08-10 | Planner | Graphify review/TDD context plus exact source, tests and gate registrations | One bounded production repair is coherent: require an already-persisted exact tombstone on v109 replay, reauthorize contact under the existing lease, and isolate reaction cleanup failure. Retry/lock corrections are evidence-only. | Write four causal rows and one bounded evidence-repair set, then invoke `$tdd-review`. |
| 2026-08-10 | Independent `$tdd-review` | Full plan, exact storage/sender, receiver/concurrency, gate registrations and literal commands | Initial `plan-fixes-required`: reject ambiguous envelope projection, fully define exact tombstone shape, make NULL-row/contact/receipt/lock proofs causal, count four mutations, and remove the redundant 404-path core family. All deltas were applied. | Run targeted re-review. |
| 2026-08-10 | Targeted re-review / arbiter | Amended plan and all review counterexamples | Three independent reviewers returned READY. Core bet confirmed; no schema/new owner and no core/feature/full/device/Go family is justified. | Mark execution-ready; implementation remains a separate session. |

## Problem And Evidence

- Behavior to repair: a Plan-356 Protected/View-Once deletion may use its retained v109 event only when the local parent has converged to the exact authorized tombstone; an incoming deletion may not recreate a conversation after contact deletion; and a non-authoritative reaction cleanup failure may not interrupt already-durable deletion settlement or delivery.
- Existing-v109 counterexample: `dbStageOutgoingDirectPrivateDeletionInboxCustody` checks the exact `(recipient,event,envelope)` winner before capacity, then returns `idempotent` with whatever row currently occupies the message ID. `MessageRepositoryImpl` and `deleteMessageForEveryone` treat that result as transport/cleanup authority. A live or crossed local parent can therefore send the deletion without a durable local tombstone.
- Contact-removal counterexample: `handleIncomingMessageDeletion` authenticates the contact before acquiring `DirectPrivateMediaCleanupRuntime.directPrivateMediaLifecycleLock.synchronizedAll`. `deleteContactAndMessages` holds that same lease while deleting messages and finally the contact. If contact deletion wins after the handler's first read, the handler enters later, the absent-target branch inserts a tombstone, and an exact receipt is sent for an orphan row.
- Cleanup counterexample: `_privateTerminalCleanupBestEffort` awaits `reactionRepo.deleteReactionsForMessage` outside its catch. A reaction-store error occurs after atomic tombstone+v109 commit but escapes before node-off settlement, hedge scheduling/live transport, and the incumbent file/key/attachment cleanup.
- Evidence gaps: TC-356-03a/03b use a map-backed owner rather than physical v109 and do not prove the later owner check; TC-356-04c's deletion-first competitor uses a different target; TC-356-02 uses 20 ms sleeps rather than deterministic competing-start proof. The committed `1to1` selector contains 120 unique paths, so Plan 356's historical `121 paths` receipt is unverified.
- Existing owners to reuse: the incumbent private-tombstone shape and exact-row predicates, physical v109 and its generic lifecycle repository, the existing repository-wide private lifecycle lock, local contact repository, private lifecycle cleanup engine, and existing retry owner checks. The live-parent tombstone body remains the new-event path; replay never invokes it. No durable type or new lock is required.
- Expected production surface: exactly `lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart`, `lib/core/database/helpers/messages_db_helpers.dart` only to expose/reuse the incumbent exact private-tombstone row predicate, `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`, and `lib/features/conversation/application/delete_message_use_case.dart`. `delete_contact_use_case.dart`, retry production, repositories/interfaces, bootstrap, and private lifecycle code are preservation-only unless a causal RED disproves reuse.

## Graph Grounding Snapshot

- Query/profile: `python3 graphify-arch/tdd_context.py query "Plan 357 Plan 356 closure repair dbStageOutgoingDirectPrivateDeletionInboxCustody exact replay tombstone handleIncomingMessageDeletion contact deleteContactAndMessages lifecycle lock reaction cleanup retry failed unacked physical v109 tests" --profile tdd --budget 700`.
- Graph fingerprint/freshness: architecture fingerprint `9e09c2c544ed38f9`; the graph reports only the already-known stale marker on `direct_private_media_lifecycle_repository.dart`, not a missing repair anchor.
- Anchors: `dbStageOutgoingDirectPrivateDeletionInboxCustody`, `handleIncomingMessageDeletion`, and `deleteContactAndMessages`.
- Affected-query proof candidates: direct-v109 helper, delete-message, incoming-deletion, private-cleanup race, protected-thumbnail, retry-failed, retry-unacked, messages-helper, recovered-disposition and SQLCipher proof paths.
- Source verification narrowed the production delta to the four files above. Existing tests are extended in place; no new path or registration is expected.

## Scope Contract And Guard

In scope:

- In the exact existing-v109 branch, remain before capacity but authorize only when the persisted parent is already the unique exact supplied private deletion tombstone. Query the completion-style outgoing envelope projection by exact recipient/contact plus `wire_envelope`, with limit two; require exactly one row and require its ID equal the supplied message ID before applying the pure exact-row predicate. Do not invoke the mutating live-parent tombstone body. The deletion outer envelope intentionally hides the target message ID, so a pre-existing v109 row cannot prove which live parent its encrypted inner payload names. Missing, live, crossed, duplicate-envelope, wrong-policy, or wrong-author/contact parent therefore refuses while retaining the pre-existing v109 row unchanged. Return only the exact persisted tombstone row.
- Define "exact persisted tombstone" rather than inheriting the current incomplete local closure: row ID, contact/sender, outgoing direction, immutable `timestamp`/`created_at`/quote/dedup/forward projection, deletion time/author, exact wire envelope, empty caption, v1 Protected/View-Once policy with NULL duration, `sending` status, and NULL attempt-owned transport/relay/custody fields must match the supplied tombstone. Only `read_at`, `hidden_at`, and incumbent private lifecycle state/clock fields may drift. A malformed duration/status or another immutable-field drift refuses; no parser-unsupported row can authorize cleanup or transport.
- Preserve the meaning of `idempotent`: the custody event and exact persisted tombstone already existed. Do not add an outcome or trust caller-supplied expected/tombstone rows to invent the missing encrypted target binding. Exact tombstone replay still wins before shared capacity; a crossed envelope or non-tombstoned parent refuses before cleanup/transport.
- In `deleteMessageForEveryone`, require an authorized private stage to return both exact custody and a non-null committed transaction row. Remove the fallback to the in-memory tombstone candidate. Refusal performs zero private cleanup, node/live/store work, or new hedge scheduling; the already-existing v109 owner remains available to its independent drain.
- Inside the existing current-event private lifecycle lease, re-read the local contact immediately before `applyIncomingDirectMessageDeletion`. A stale-positive first read followed by an in-lease miss returns the existing terminal `unauthorized` result, which recovered replay maps to rejected/non-retryable, with zero DB apply, marker/presentation cleanup, reaction cleanup, or receipt. Preserve the initial first-read `unknownSender` result for a sender that was never locally authorized. The lookup is the local repository reauthorization required by the race; crypto, network, and receipt remain outside the lease.
- Preserve valid deletion-before-initial behavior while the contact exists. Do not change `dbApplyIncomingDirectMessageDeletion` absent-target semantics globally. If the incoming deletion owns the lease first, it may commit and receipt; later contact deletion intentionally removes that row. If contact deletion owns first, no row may be reinserted afterward.
- Make outgoing reaction retirement independently best-effort: catch and record its failure, then always run the incumbent private lifecycle cleanup catch and continue into node settlement/hedge/live logic. Do not catch or downgrade atomic stage failures, private lifecycle authorization failures, or transport failures.
- Repair evidence without changing retry/lock production: make TC-356-03a/03b execute through a lifecycle-only wrapper over real SQLite/physical v109 and cover the loaded owner plus the applicable later owner-before-egress check; make TC-356-04c compete on the same target and assert terminal supersession/receipt-only; replace TC-356-02's wall-clock sleeps with explicit contender-attempt/entered/release completers and durable zero-effect assertions.
- Correct the prior retry overclaim explicitly: an ownerless current deletion fails closed at its first lookup, so a private deletion cannot legitimately continue to a later legacy-egress checkpoint. The later-check case is exercised with the existing compatible current EDIT route; the private-deletion row proves physical ownership at the first lookup. Do not weaken ownerless-deletion fail-closed behavior to manufacture a pre-egress test.

Must preserve:

- New Plan-356 authoring remains atomic tombstone+v109 before cleanup/network; exact completion, node-off/live hedge, v111 independence, event identity, and pause/reopen behavior do not change.
- Ordinary text/media/reaction v109 exact-winner and fair-drain semantics remain unchanged; the stricter replay validation is exact v1 Protected/View-Once deletion only.
- A physically removed parent does not get recreated by outgoing replay. Its pre-existing v109 row remains independently drainable/completable.
- Current incoming deletion still transactionally dominates initial/media state and receipts only after durable apply and lease release when the contact still exists.
- Pre-356 eventless private DFE, proof-less receive, private EDIT, disappearing, Delete-for-Me, groups/announcements, historical promotion and linked-device fanout keep their existing lanes.
- `commitPrivateDeleteForEveryoneTombstone` remains deferred dead-boundary hygiene. Removing its interface/implementation/bootstrap/fixture wiring would touch frozen owners and is unrelated to these defects; the within-transaction body remains live, and this repair reuses only its factored exact-tombstone predicate.

Hard do not:

- No DB v112, table/column/index, new outbox/kind/outcome/queue/drain/scheduler/lock, receipt ledger, contact-message cross-repository transaction, scanner/backfill, or general mutation framework.
- No retry production edit, contact-deletion production edit, repository/interface/bootstrap edit, relay/native/Go/wire/binding change, selector/admission change, device harness, or activation work.
- No disappearing initial/deletion, private EDIT, group/announcement, historical/no-intent, fanout, quota/UX, mixed-version rollout, GAP-N01 closure, or release claim.
- No source-string test as causal proof, clock sleeps, new test file, gate registration change, completeness run, per-plan full `host-all`, or duplicated whole-file ad-hoc campaign.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-357-01 | An exact pre-existing private deletion v109 winner authorizes transport only when the persisted parent is the unique exact supplied tombstone. Exact tombstone + capacity zero stays `idempotent`; live, absent, crossed, duplicate-envelope, wrong-duration/status, or immutable-drift parent refuses with v109 retained and every parent/attachment/v108/v111 row unchanged. A same event/envelope presented for a different live message ID or two outgoing exact tombstones projecting the same envelope must refuse because deletion's outer envelope has no target binding. Independently, an authorized repository result with exact custody but a NULL committed row is refused by the application with zero cleanup/network. | `test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart::TC-357-01a exact private deletion v109 replay authorizes only the persisted tombstone`; `test/features/conversation/application/delete_message_use_case_test.dart::TC-357-01b private deletion replay without a committed tombstone cannot clean or transmit` | real current-schema SQLite; capacity zero; ordered full-table inventory; lifecycle-capable real-SQLite wrapper returning authorized exact custody plus NULL message; application cleanup/network counters | HEAD returns `idempotent` with the live/crossed/ambiguous row; independently, the application substitutes its in-memory candidate for an authorized NULL row | restore the blind exact-winner return, omit the unique envelope projection, or admit/rewrite a live parent -> 01a RED; restore the in-memory fallback -> 01b RED; revert both | causal RED/GREEN; existing core AUTO/host `1to1` paths |
| TC-357-02 | Contact deletion and incoming current deletion converge in both actual lease orders. A stale first contact read followed by real `deleteContactAndMessages` winning the shared lease yields terminal `unauthorized`/rejected replay, no orphan tombstone, cleanup, marker, or receipt. Handler-first starts from an absent target while the contact exists, durably applies deletion-before-initial, and emits exactly one target+event receipt only after the lease is inactive; contact deletion waits, then removes the row/contact, leaving no resurrection. | `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart::TC-357-02 contact deletion winner prevents current deletion tombstone resurrection and receipt` | real SQLite message/media repository, mutable barrier contact repository, receipt-eligible staged entry/relay event, real receipt callback, actual contact-delete use case, actual shared lock; completers only | HEAD contact-first inserts and receipts the absent-target tombstone and leaves recovered replay retryable | remove the in-lease contact reauthorization or map its miss to retryable `unknownSender` -> TC-357-02 RED; revert | causal RED/GREEN; existing host `1to1` path |
| TC-357-03 | A throwing reaction repository after durable private tombstone+v109 stage cannot escape or suppress private lifecycle cleanup and node settlement. Protected/View-Once node-off returns normally, leaves the exact v109 retryable, projects failed/no transport, runs exact artifact/key/attachment cleanup, and performs zero network. | `test/features/conversation/application/delete_message_use_case_test.dart::TC-357-03 reaction retirement failure after private stage cannot suppress cleanup or settlement` | real SQLite/temp artifacts/secure-key fake; throwing reaction repo; stopped P2P service | HEAD throws before lifecycle cleanup and node settlement | move reaction retirement outside its independent catch -> TC-357-03 RED; revert | causal RED/GREEN; existing host `1to1` path |
| PRES-357-A | Replace Plan 356's weak proof shapes without widening production: TC-356-03a/03b use physical v109 and prove private owner-at-load plus compatible EDIT owner-before-egress; TC-356-04c uses the same target and returns durable supersession with receipt-only; TC-356-02 uses deterministic contender completers and both actual lock orders. Existing DB/handler Plan-356 causal rows remain green. | Existing exact names: `TC-356-03a failed private deletion with lifecycle-only v109 owner blocks legacy replay`; `TC-356-03b unacked private deletion with lifecycle-only v109 owner blocks legacy replay`; `TC-356-04c current private deletion and strict presentation serialize in both lifecycle lock orders`; `TC-356-02 private initial and deletion custody converge in both lifecycle lock orders`; plus TC-356-01b/04a/04b | real SQLite/physical v109; existing real lifecycle/contact fixtures; no sleeps/source scans | Supporting proof correction; may be GREEN on current production after fixture repair | casting back to the text-stage capability, removing an applicable later owner check, using a different target, or removing the lifecycle lease must red its existing row | exact filtered proof only; files are existing host/AUTO paths; no registry edit |

## Test Notes And Non-Vacuity

- TC-357-01a must preseed the current physical v109 directly using existing SQL/helper authority before invoking the current stage API; it may not create the winner through a new Plan-357 symbol. Inventory includes `messages`, physical v109, v108, every v111 row and attachments. Exact tombstone replay is checked from the returned row and a fresh DB query; live/cross-message, two exact outgoing tombstones sharing one envelope, non-NULL duration, non-`sending` status, and immutable-field drift cases must remain unchanged and refused.
- TC-357-01b must use a narrow lifecycle-capable wrapper over the real SQLite/physical-v109 delegate that deliberately returns an otherwise authorized exact custody result with `message: null`. A live/crossed case refused by TC-357-01a cannot prove removal of the application fallback because it never reaches that branch.
- TC-357-02 must configure a receipt-eligible current event with nonblank staged-entry ID/relay transport and the real mutation-receipt callback. It captures the first contact object, starts the competing future outside the incumbent lock owner's Zone, lets the real contact-delete use case finish under the shared lease, then releases the stale first read. Assert zero receipts and a rejected/non-retryable recovered disposition. The reverse order starts from an absent target with a valid contact, pauses the handler inside the actual lease, signals that real contact deletion has attempted entry, proves it cannot purge until release, then asserts exactly one target+event receipt after the lock reports inactive and final absence after both finish. Merely deleting the contact before calling the handler, acquiring the lock directly, launching the competitor inside the reentrant Zone, or using zero-yield loops is not causal. No timers.
- TC-357-03 must prove lifecycle cleanup continues after reaction failure, not merely that the public future is caught by the test. Atomic stage errors remain observable/refused.
- For TC-356-03a/03b, a current private deletion with no physical owner must still fail closed on its first lookup. The later-owner case uses the compatible event-bearing EDIT path and inserts a physical v109 row at a deterministic existing callback/fixture boundary before egress; do not add a production test hook.
- Repaired TC-356-04c uses the same target and the injected actual lifecycle lock's contender-attempt/entered/release signals. Create the competitor future outside the owner's Zone so Zone-reentrancy cannot bypass the queue; assert exact `durablySuperseded`, one receipt, and no presentation effects. Repaired TC-356-02 uses the same pattern and contains no sleep or polling loop.
- Four mutation re-reds are required and sufficient: blind existing-v109 winner, restored application nullable-row fallback, missing in-lease contact recheck, and escaping reaction retirement. Do not add a mutation framework or repeat Plan 356's four already-recorded mutations.

## Implementation Steps

1. Start from clean baseline `ca5f2174c`; retain Plan 356's historical receipts and its appended post-execution-incomplete marker. Author TC-357-01/02/03 against existing methods so the first RED is behavioral, not a missing-symbol/compiler failure.
2. Factor/reuse the incumbent pure exact-private-tombstone row predicate. In the existing-v109 transaction branch, load at most two outgoing rows for the exact contact+envelope, require one unique matching message ID and the exact row predicate, refuse every ambiguous/non-tombstoned/absent/crossed parent without touching custody, and preserve replay-before-capacity. Tighten the application result guard to require that row. Never rewrite a live parent from an opaque deletion envelope.
3. Reauthorize local contact existence inside the incumbent lifecycle lease immediately before current deletion apply. Map a stale-positive/in-lease miss to terminal `unauthorized` (recovered rejected/non-retryable), preserve first-read `unknownSender`, and keep receipt outside the lease. Correct the nearby handler comment: contact reauthorization is inside the lease; receipt/network remain outside.
4. Isolate reaction retirement in its own best-effort catch; always proceed to the incumbent private lifecycle cleanup and the already-selected settlement/transport flow. Change no durable reaction contract.
5. Repair the three Plan-356 proof shapes in place: physical-v109 retry cases, same-target strict replay, and deterministic lock contenders. Make no retry/lock production edit unless an amended test exposes a separate defect; stop and re-review if it does.
6. Run the four mutations, one combined concurrency-4 focused/preservation proof, and host `1to1` once. Run analyzer, changed-Dart format/diff hygiene, and one incremental architecture-graph refresh. Reconcile Plans 356/357, `STATUS.md`, index and coverage to repaired/executed only after every receipt passes.

## Risk And Reversibility

| Risk | Detection | Reversible response |
|---|---|---|
| Replay validation accepts or mutates an unrelated/current parent | TC-357-01 live/cross-message/duplicate-envelope/absent/policy/identity/full inventory matrix | Fail closed unless one unique outgoing envelope projection is the supplied exact tombstone; existing v109 remains durable, no schema rollback |
| Contact recheck enlarges the lifecycle critical section or changes valid deletion-before-initial | TC-357-02 both actual orders + TC-356-04a/04b/04c | Keep only one local lookup immediately before apply; stop for review rather than adding a cross-repository transaction |
| Cleanup catch hides stage/settlement failures | TC-357-03 injected reaction failure plus existing stage-refusal tests | Catch only reaction retirement; retain existing lifecycle catch and transport error semantics |
| Evidence repair drives retry/lock refactor | Diff boundary and PRES-357-A | Stop and re-review; no retry/lock production edit is authorized |
| Gate runtime expands again | selected-name receipt and once-only curated ledger | Remove duplicate invocations; do not add core/feature/full/device/Go families without the explicit scope trigger |

Rollback has no migration or external operation. Runtime effects remain the already-authorized private tombstone, reaction best-effort cleanup, terminal artifacts, and independent v109/v111 obligations. Reverting Plan 357 restores the audited Plan-356 behavior without data conversion; all selectors/admissions remain default-off.

## Gate Cadence

- Inner loop: only the active exact TC-357 plain name while editing.
- First combined RED: one Flutter invocation over the three causal files with concurrency 4. All rows must compile at baseline and fail on current behavior.
- Final proof: one filtered Flutter invocation at concurrency 4 over the eight existing files below. It contains all TC-357 rows and only the load-bearing corrected Plan-356 sentinels; do not rerun them separately.
- Curated regression: host-only `1to1` once. This selector does not accept Flutter batch/concurrency flags. Record the live unique-path count; baseline dry-run is 120, not the historical 121.
- Family: omit both `core-host-all` and `feature-host-all`. Host `1to1` already runs the complete changed core helper suites and both changed feature use-case suites; the final filtered invocation covers the two evidence-only paths outside that lane. Adding 404 core paths supplies no new load-bearing boundary. Stop for targeted re-review if implementation expands into a shared repository/interface/bootstrap/common retry path.
- No DTR preflight: none of the four intended production files is content-hash pinned. No completeness: no test path or registry changes.
- Hygiene: full analyzer once, changed-Dart format covering committed/staged/unstaged/untracked execution modes, diff checks, then one incremental Graphify refresh after coherent production changes.
- Wave/final only: no full `host-all` in this repair.

## Acceptance Gates

First behavioral REDs, one invocation:

```bash
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  --name 'TC-357-01|TC-357-02|TC-357-03'
```

Final focused plus exact preservation proof, one invocation:

```bash
flutter test --concurrency=4 \
  --dart-define=MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED=true \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  --name 'TC-357-|TC-356-01b|TC-356-02 private initial and deletion custody|TC-356-03a|TC-356-03b|TC-356-04a|TC-356-04b|TC-356-04c'
```

Affected curated lane and hygiene, each once:

```bash
plan357_base_ref=ca5f2174c9bd4cbdbc54d02a92a70610a111f150
./scripts/run_host_test_gates.sh 1to1
flutter analyze

plan357_dart_list="$(mktemp)"
trap 'rm -f "$plan357_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan357_base_ref"...HEAD -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan357_dart_list"
test ! -s "$plan357_dart_list" || xargs dart format --output=none --set-exit-if-changed < "$plan357_dart_list"
rm -f "$plan357_dart_list"
trap - EXIT

git diff --check "$plan357_base_ref"...HEAD
git diff --cached --check
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan357_base_ref"...HEAD
git diff --cached --check
git diff --check
git status --short
```

Explicitly NOT RUN per plan:

- `./scripts/run_test_gates.sh 1to1`, `core-host-all`, `feature-host-all`, full `host-all`, completeness, DTR hash preflights, ad-hoc whole-file reruns, or separate repeats of the filtered sentinels.
- No dedicated Go relay/node/bridge/mixed-version/process, custody shell, gomobile binding, migration/account-transfer/SQLCipher, groups/feed/posts/performance/baseline, physical/native device, Android/iOS, deployment, activation, or release campaign.
- If implementation touches schema, wire, relay/native, a repository/interface/bootstrap/common retry branch, creates a test path, or needs a new lock/outcome/owner, stop and re-review rather than silently adding a large gate campaign.

## Done Criteria

- [ ] Exact existing-v109 replay returns only one uniquely envelope-projecting, already-persisted exact private tombstone or refuses while preserving the owner; it never rewrites a live/cross-message/ambiguous parent from an opaque envelope, and no uncommitted in-memory fallback may clean or transmit.
- [ ] Contact deletion winning the actual shared lease cannot be followed by an orphan tombstone, cleanup, marker or receipt; handler-first still converges and final contact purge leaves no row.
- [ ] Reaction retirement failure after durable private stage is contained without suppressing lifecycle cleanup, node settlement, retained v109, or the already-selected transport path.
- [ ] TC-356-03a/03b use physical v109 and honestly distinguish private deletion's first-lookup fail-closed rule from compatible EDIT's later owner check.
- [ ] TC-356-04c uses the same target, and TC-356-02 contains no clock sleep; both prove the actual incumbent lifecycle order.
- [ ] Four representative mutations independently red their causal rows and are reverted.
- [ ] One combined focused/preservation invocation, host `1to1`, analyzer/format/diff and one Graphify refresh pass on the same final tree; live `1to1` count is recorded rather than copied.
- [ ] Plans 356/357, `STATUS.md`, index and coverage retain historical receipts but are changed to repaired/executed only after all evidence passes.
- [ ] No schema, new durable owner, retry/contact-delete production expansion, modality adoption, activation, device/iOS, per-plan full host-all, GAP-N01 closure, or release claim is made.

## Handoff

- First RED: the single three-file `TC-357-01|02|03` command above; no missing symbol or source-string failure counts.
- Final proof: the one eight-file filtered concurrency-4 command; verify selected names in the receipt and do not repeat them ad hoc.
- Registration/completeness: none expected; every test stays in an existing path. Record a live host `1to1` inventory (baseline 120 unique paths).
- Migration/protocol/platform: none; DB stays v111 and physical v109 is byte-compatible.
- Rollout: all existing client/relay admissions remain default-off.
- Deferred next N01 work: only after Plan 357 executes and its post-execution audit passes, plan disappearing direct-media initial custody as Plan 358; keep disappearing Delete-for-Everyone separate unless review proves one lifetime/owner.

## Reviewer Findings

Initial verdict: **plan-fixes-required; core bet confirmed**.

Required fixes were applied:

- Exact replay now requires one unique outgoing contact+envelope projection, the supplied message ID, and a complete persisted tombstone predicate. Duplicate-envelope, duration/status, immutable-projection and absent/live/crossed cases are causal refusals.
- TC-357-01b independently reaches the application guard with authorized physical custody plus a NULL committed row, so restoring the in-memory fallback re-reds it.
- A stale-positive contact that disappears before the in-lease reauthorization returns terminal `unauthorized`/rejected, while the initial unknown sender remains `unknownSender`; both lock orders use real contender signals outside the reentrant Zone and exact receipt assertions.
- Four independent mutation re-reds replace the inconsistent count of three.
- The redundant 404-path `core-host-all` was removed. One concurrency-4 filtered proof plus one existing host `1to1` lane covers every load-bearing path; no feature/full/device/Go family is added.
- Literal production-file, DTR, reconciliation and temporary-file hygiene wording was corrected.

Targeted storage/sender, receiver/concurrency, and gate re-reviews all returned **READY**, with no remaining required delta.

## Arbiter Decision

**READY / EXECUTION_READY. Core bet confirmed.** Plan 357 is the smallest sufficient repair of Plan 356: four production files, the existing physical v109/private lifecycle/contact owners, three new behavioral rows, repaired existing evidence, and four mutation re-reds. It adds no schema, outcome, lock, queue, protocol, modality, activation, or release boundary.

Disposition: execute separately from baseline `ca5f2174c`; do not treat Plan 356 as repaired until the final filtered proof, live host `1to1`, analyzer/hygiene and Graphify receipt all pass on one final tree. The expensive core and feature families are intentionally omitted because the curated lane already runs every changed full suite.
