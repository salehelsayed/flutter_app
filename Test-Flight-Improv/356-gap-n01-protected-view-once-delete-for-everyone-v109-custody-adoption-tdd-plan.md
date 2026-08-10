# 356 - GAP-N01 Protected/View-Once Delete-for-Everyone v109 Custody Adoption

Status: execution-ready
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` sections 3.1 and 5, A-01/A-03; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01 / WP-01 / section 9.2
Classification: implementation-ready
Closure tier: host (real SQLite and file-backed restart where persistence is causal); no schema, relay/native, device, iOS, activation, or release boundary

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-10 | Evidence Collector | Plans 349, 351, 354, 355; `delete_message_use_case.dart`; private tombstone/message helpers; physical v109 helper; retry, receipt, incoming-deletion, lifecycle and gate owners | Newly authored Protected/View-Once Delete-for-Everyone still mints no event ID and commits only an update-only tombstone. Physical v109, one fair mutation drain, event-aware receipts and private lifecycle cleanup already exist. | Plan one owner-aligned adopter; add no durable type. |
| 2026-08-10 | Planner | Graphify architecture graph plus current source/tests and gate registrations | The smallest coherent slice is one atomic P/VO tombstone+v109 stage, its existing lifecycle/drain/retry adoption, and the narrow current-deletion receiver qualification the new event requires. The enabled pause flush may make a compatibility deposit but must not complete or delete v109. | Write causal contracts and economical gates, then run `$tdd-review`. |
| 2026-08-10 | Reviewers | Fresh source/counterexample audit plus literal path, name, option and gate dry-run review | Required deltas closed: causal existing-method completion RED; raw outer/inner identity; generic-lifecycle retry seeding; shared incoming lifecycle lease; private cleanup plus separate reactions; correct peer+target display retirement; outgoing/incoming v111 distinction; truly overlapping lock barriers; DTR preflight; staged/committed hygiene; consolidated concurrency-4 proof. | Final verdict READY; no correctness, sufficiency, cadence or overengineering blocker. |
| 2026-08-10 | Arbiter | Amended four-bundle contract, four mutation re-reds, exact preservation regex, host-only cadence and stop conditions | Reuse physical v109 plus incumbent private lifecycle authority. No schema, owner, drain, protocol, feature-family, device or release expansion is justified. | Append readiness ledgers and hand off to a separate implementation session. |

## Problem And Evidence

- Behavior to improve: a newly authored outgoing v1 Protected or View-Once Delete-for-Everyone must retain its authenticated deletion event in the existing physical v109 outbox before private artifact cleanup or any live/relay call, then converge only through exact device receipt and ACK-or-expiry custody semantics.
- User impact: today private deletion commits a visible tombstone, removes private artifacts, and then depends on the legacy node/store path. A stopped process, crash, or failed legacy deposit can therefore leave the recipient without the deletion even though the sender has irreversibly cleaned the private item.
- Confirmed sender root cause: `deleteMessageForEveryone` in `lib/features/conversation/application/delete_message_use_case.dart` excludes `requiresPrivateTerminalCleanup` from both v109 ownership booleans, mints no mutation event ID for that lane, and calls only `commitPrivateDeleteForEveryoneTombstone`. Merely widening `ownsDirectMutationInboxCustody` is invalid: `stagedMutationCustody` remains null and the stopped-node branch dereferences the ordinary transport repository.
- Confirmed storage root cause: `dbCommitOutgoingDirectPrivateDeleteForEveryoneTombstone` in `lib/core/database/helpers/messages_db_helpers.dart` is an update-only private tombstone transaction with no v109 insert. `dbStageOutgoingDirectTextMutationInboxCustody` and `dbCompleteAcceptedDirectMutationInboxCustodyIfExact` in `lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart` reuse physical v109 but admit only strict ordinary policy.
- Confirmed receive root cause: `dbApplyIncomingDirectMessageDeletion` in `messages_db_helpers.dart` re-reads the target transactionally but explicitly refuses policy-v1 Protected/View-Once rows. The event-bearing handler consequently returns unauthorized. Its generic cleanup also bypasses the private lifecycle file/key owner: it can delete the attachment row without exact secure-key/private-artifact cleanup or the incumbent terminal rules, while the no-FK v111 obligation itself must survive independently to ACK or expiry.
- Existing reusable authority: physical DB v109 keyed by raw event ID, `direct_mutation_v109`, one fair reaction/mutation drain, `DirectMutationInboxCustodyLifecycleRepository`, exact failed/unacked owner checks, event-aware deletion payload and receipts, the update-only private tombstone/settlement owner, `DirectPrivateMediaLifecycle`, and the shared private lifecycle lock.
- Existing coverage: Plans 349/351 prove atomic ordinary mutation custody, fair drain, exact completion and receipts; Plans 354/355 prove P/VO initial v108/v111 ownership, lifecycle retention, terminal cleanup, anti-resurrection and presentation convergence. None proves a P/VO deletion owns v109.
- Missing coverage: atomic private tombstone+v109 refusal/rollback, P/VO completion without admitting private EDIT, node-off/live hedge ordering, owner-only failed/unacked/restart behavior, and event-bearing P/VO receiver convergence.
- Refuted finding: a new outbox, schema column, relay kind, scheduler or private drain is required. The private deletion event has the same authenticated identity and ACK-or-expiry lifetime as existing v109 deletion; only its parent transition and cleanup authority differ.
- Unresolved findings: none after independent review and targeted re-review.
- Expected production surface: `lib/core/database/helpers/messages_db_helpers.dart`; `lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart`; `lib/features/conversation/domain/repositories/direct_private_media_lifecycle_repository.dart`; `lib/features/conversation/domain/repositories/message_repository.dart` only if shared result/lifecycle wording must be clarified; `lib/features/conversation/data/repositories/message_repository_impl.dart`; `lib/features/conversation/application/delete_message_use_case.dart`; `lib/features/conversation/application/retry_failed_messages_use_case.dart`; `lib/features/conversation/application/retry_unacked_messages_use_case.dart`; `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart`; and `lib/app/bootstrap/production_application_bootstrap.dart`. Reuse `DirectPrivateMediaLifecycle`; do not change it unless a causal test disproves the existing retention contract.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `2aa68bd8cc79121a`; current at planning query.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 356 Protected View-Once delete-for-everyone v109 custody: deleteMessageForEveryone commitPrivateDeleteForEveryoneTombstone dbStageDirectMutationInboxCustody dbCompleteAcceptedDirectMutationInboxCustody retry_failed_messages_use_case tests gate registration" --profile tdd --budget 700`.
- Anchors: `commitPrivateDeleteForEveryoneTombstone` -> `direct_private_media_lifecycle_repository.dart`; `deleteMessageForEveryone` -> conversation deletion application path; physical v109 stage/completion -> `direct_reaction_inbox_custody_outbox_db_helpers.dart`.
- Surfaced proof/gate files: delete application tests, v109 DB helper tests, retry tests, private cached-envelope race, and host `1to1` registration.
- Graph gaps requiring source search: current receiver policy predicate, private cleanup/key ownership, enabled pause-flush behavior, exact literal sentinel names and bootstrap delegate wiring; each was verified in current source.
- Reuse rule: these anchors may be handed to execution/review, but source and literal command evidence remain authoritative.

## Scope Contract And Guard

In scope:

- Newly authored outgoing ordinary 1:1 v1 `protected` and `view_once` Delete-for-Everyone only. Mint one raw authenticated event ID, bind outer/inner identity, and reuse the unchanged physical v109 row and `direct_mutation_v109` relay custody kind.
- One narrow optional private-deletion stage capability on the incumbent private delete repository boundary. It returns the exact transaction result/custody row; it is not a new durable owner. Keep the existing generic v109 load/failure/completion lifecycle independent of the staging modality.
- Factor the existing update-only private tombstone body into a within-transaction form and call it from one v109 transaction. Exact replay is checked before capacity. Parent removal, capacity, event collision, policy/identity drift, or injected insert failure leaves parent, v108, v111, attachments, reactions, keys and files unchanged.
- Acquire the existing repository-wide private media lifecycle lock for private stage plus terminal cleanup, then release it before network/receipt work. If an initial v108/v111 handoff owns the lock first it finishes unchanged; if deletion owns it first, the later handoff observes the tombstone and refuses before new network work.
- Extend existing v109 completion only for the deletion branch: exact outgoing v1 P/VO tombstones may settle/retire; private EDIT and disappearing remain refused. Completion is attachment/v108/v111-independent and preserves hidden/private lifecycle state.
- Node-off stages first, performs incumbent private cleanup, settles the still-present private tombstone to failed without an ordinary-repository dereference, performs zero network, and retains v109. A running node launches the existing scheduled/non-awaited v109 hedge beside the live race; live success never cancels the hedge.
- Failed and unacked retry discover the exact owner through `DirectMutationInboxCustodyLifecycleRepository`, both initially and immediately before legacy egress. Owned rows drain/retry only v109; an event-bearing private deletion with no owner fails closed. No retry-time event minting or adoption.
- Current event-bearing incoming deletion acquires the same repository-wide exclusive private lifecycle lease used by strict private stage-through-presentation before current-event selection/apply. It reuses `dbApplyIncomingDirectMessageDeletion`, transactionally preserves P/VO lifecycle/hidden fields, retires the incumbent exact peer+target message-scoped display entries (message and reaction while preserving every other peer/message), keeps v111 independent, and returns the same durable outcomes/receipt contract. Post-commit P/VO cleanup uses the incumbent private lifecycle engine rather than generic attachment deletion; reaction records are retired separately and best-effort. The lease spans the marker/presentation-sensitive cleanup seam, then receipt/contact work begins only after release. Absent-target deletion-first keeps the existing tombstone placeholder and strict initial replay remains superseded.

Must preserve:

- Ordinary text/media/caption mutation behavior, raw-ID collision refusal and one fair drain -> `TC-349-01`, `TC-349-04`, `TC-351-03`, and `TC-353-03` sentinels.
- Private initial v108/v111 ownership and cleanup retention -> Plan 354/355 behavior plus TC-356 lock-order/byte-identity assertions.
- Pre-356 eventless/ownerless private DFE exact cached/rebuilt retry remains legacy and receives no event ID or v109 row -> `legacy failed private DFE inbox transport reacquires deletion custody`.
- Legacy proof-less incoming Protected deletion remains readable and uses its existing lifecycle -> `authorized incoming protected deletion cleans attachments and local artifacts`.
- Exact event receipt pairing remains required; target-only, blank or wrong event maps cannot settle the current tombstone -> `TC-349-06`.
- Delete-for-Me remains local-only; private EDIT/caption replacement, disappearing, groups/announcements and linked-device fanout remain unchanged.
- Enabled pause flush is not a second custody owner. It may preserve its existing compatibility deposit, but it must leave the exact v109 row and event envelope intact; resume's shared drain remains authoritative. No pause framework change is authorized unless this preservation assertion fails.

Hard `Do not`:

- Do not add DB v112, a new table/column/kind key, subtype-prefixed local event IDs, a second outbox/drain/queue/scheduler/flag/lock, a receipt ledger, or a historical scanner/backfill.
- Do not change relay/native/Go protocol, gomobile bindings, ciphertext/wire shape, event namespace, capacity, retry cadence, selector/admission defaults, or notification payloads.
- Do not put v108/v111 transition or artifact erasure inside the v109 transaction. Those remain independent lifecycle owners; only the private tombstone and v109 row are atomic.
- Do not widen the outgoing-only live-v111 artifact-retention predicate to incoming media. An incoming private terminal winner may remove its exact attachment/key/files through the incumbent private lifecycle while the no-FK v111 row survives byte-identically for its own ACK/expiry owner.
- Do not admit private EDIT, disappearing deletion, group/announcement deletion, historical eventless rows, or per-device fanout by generalizing a broad policy predicate.
- Do not add a receiver pipeline, listener sequencer, cleanup journal/scanner, production file hierarchy or generic mutation framework.

Deferred / accepted differences:

- Pre-356 eventless private tombstones remain legacy forever; there is no reliable provenance for safe v109 promotion.
- A new sender talking to an older receiver may get only a target-message receipt. The sender ignores it for an event-bearing deletion and retains v109 until an event-aware receipt and/or protected ACK-or-expiry convergence. Admission/cohort and downgrade policy remain WP-07.
- Enabled pause flush can create the incumbent compatibility copy while v109 remains authoritative; deduplicated retirement still belongs to exact v109 acceptance/expiry. A universal pause-flush redesign is outside this slice.
- Crash-complete removal of inaccessible local artifact residue remains storage hygiene. Plan 356 owns durable deletion truth and preservation of live v111, not a new erasure journal.
- Disappearing initial/deletion custody, private EDIT, group/announcement, historical promotion, linked-device fanout, activation, aggregate quota/UX, wave-level full `host-all`, consolidated iOS and GAP-N01/release closure remain later work.

Dependencies:

- Requires implemented Plans 349, 351, 354 and 355. Reuses DB v109/v111 without migration and keeps all direct-inbox/media selectors and relay admissions default-off.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-356-01 | P/VO authoring atomically commits one update-only tombstone plus one exact raw-event v109 row before cleanup/network. One nonblank ID must be byte-equal in the v109 key, clear outer envelope and decrypted inner deletion payload, with the same sender and target. Protected and View-Once, delivered/inboxed and an already-hidden/private-lifecycle successor are accepted; exact replay wins before capacity. Full/collision, disappearing/wrong duration, identity/envelope drift, parent removal and an injected v109-insert abort preserve all rows/files/keys. The repository returns committed custody even if a post-commit publication reload loses the parent. Existing completion accepts exact private deletion with live or absent attachments/v111, hidden/terminal or removed parent, but refuses private EDIT, disappearing, crossed and ambiguous parents. | `test/features/conversation/application/delete_message_use_case_test.dart::TC-356-01a private deletion atomically stages tombstone and v109 before cleanup or network`; `test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart::TC-356-01b private deletion v109 stage and completion preserve independent lifecycle authority`; `test/features/conversation/domain/repositories/message_repository_impl_test.dart::TC-356-01c repository returns exact private deletion custody after atomic commit`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::TC-356-01d production wires private deletion stage to physical v109` | real current-schema SQLite; passthrough crypto bridge; use-case network/cleanup counters; test trigger; repository post-commit barrier; 01d analyzer-AST constructor/delegate wiring contract | HEAD 01a runs but commits no v109 and misses the insert fault. Independently, 01b seeds the current physical v109 plus an exact P/VO tombstone using existing SQL/APIs, invokes the existing completion method, and observes its current v0-only refusal. Neither causal RED may depend on a missing new symbol; 01c/01d are supporting GREEN/wiring proof. | split the two writes, omit/change encrypted-inner identity, move capacity before exact replay, retain the v0-only completion gate, require attachments/hidden-null at completion, or discard committed custody on reload -> 01a/01b/01c RED; revert | exact RED/GREEN; helper/bootstrap AUTO core, delete host `1to1`, repository AUTO feature; no new path |
| TC-356-02 | The existing exclusive private lifecycle owner serializes initial handoff versus deletion. Node-off stages then cleans, uses private settlement, performs zero network and retains v109; live-v111 keeps attachment/key/artifact/v108/v111 byte-identical while no-live-v111 permits incumbent cleanup. Live ACK returns without awaiting/canceling the scheduled hedge; accepted protected custody settles the exact tombstone, while refusal/capability absence causes zero cleanup/transport. | `test/features/conversation/application/delete_message_use_case_test.dart::TC-356-02 protected and view-once delete retain v109 across lifecycle node-off and live ACK`; `test/features/conversation/application/private_media_cleanup_race_test.dart::TC-356-02 private initial and deletion custody converge in both lifecycle lock orders` | real SQLite + temp files/secure-key fake + actual lifecycle lock + completer barriers; no sleeps | HEAD node-off rejects before authority, private stage is outside v109, and no hedge exists -> staged/serialized exact owner with zero pre-authority effects | restore pre-stage node check, omit the outer private lifecycle lease, terminalize live v111, or await/cancel hedge on live ACK -> TC-356-02 RED; revert | exact RED/GREEN; both existing host `1to1`/AUTO feature paths |
| TC-356-03 | Failed, unacked, restart and enabled-pause paths cannot escape exact ownership. A lifecycle-only repository (no text-stage capability) finds P/VO v109 initially and at the pre-egress barrier; accepted drain completes it without rebuild/direct/generic store/blob work, retained failure leaves it retryable, and an ownerless current event fails closed. File-backed reopen preserves the same bytes/event. The enabled pause compatibility deposit never removes or completes v109. | `test/features/conversation/application/retry_failed_messages_use_case_test.dart::TC-356-03a failed private deletion with lifecycle-only v109 owner blocks legacy replay`; `test/features/conversation/application/retry_unacked_messages_use_case_test.dart::TC-356-03b unacked private deletion with lifecycle-only v109 owner blocks legacy replay`; `test/features/conversation/integration/private_cached_envelope_retry_delete_race_test.dart::TC-356-03c private deletion v109 survives reopen and pause compatibility deposit` | application fakes with initial/pre-egress barriers plus real file-backed SQLite reopen; exact owner row | HEAD retry casts ownership through the text-stage capability and eventless legacy private rows have no v109 -> generic path/owner miss; GREEN uses the generic lifecycle capability and exact row only | restore text-stage cast, remove pre-egress recheck, rebuild/mint on retry, delete v109 on failed store, or treat pause deposit as completion -> TC-356-03 RED; revert | exact RED/GREEN; unacked/integration host `1to1`; failed exact-run because it is outside curated lane; AUTO feature |
| TC-356-04 | Current event-bearing incoming P/VO deletion is one transactional winner against absent/strict-initial/current/terminal parent. The same exclusive lease serializes it against strict private stage-through-thumbnail/marker/publication/ready in both orders. It preserves hidden/private lifecycle fields, retires the incumbent exact peer+target message-scoped display entries while preserving other peers/messages, never deletes v111, uses the private lifecycle owner for exact file/key/attachment cleanup, separately retires reaction records best-effort, re-drives exact duplicate cleanup, and sends one exact mutation receipt only after durable apply and lease release. Incoming v111 remains independent even when its now-terminal private attachment/key are removed. Deletion-first strict initial is superseded; initial-first deletion publishes then terminalizes without resurrection. Disappearing, wrong sender/policy/duration and crossed event identity refuse. Exact sender receipt settles only the matching private tombstone and does not retire v109. | `test/core/database/helpers/messages_db_helpers_test.dart::TC-356-04a current private deletion and strict initial converge without lifecycle regression`; `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart::TC-356-04b event-bearing protected and view-once deletion use private cleanup reactions and exact receipt`; `test/features/conversation/application/receive_protected_photo_thumbnail_test.dart::TC-356-04c current private deletion and strict presentation serialize in both lifecycle lock orders`; `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart::TC-356-04d exact private deletion receipt settles only the matching event` | real SQLite for ordering/display rows/v111; handler and strict-receive completer barriers using the actual shared lifecycle lock; receipt/reaction/presentation counters | HEAD transactional owner refuses v1 and handler does not share strict presentation's lease -> narrow P/VO deletion apply/private cleanup and one existing-owner serialization. Receipt is GREEN preservation unless implementation crosses it | restore v0-only policy, clear hidden/lifecycle fields, use generic attachment cleanup, leave reaction records, remove the receiver lease, delete v111/other-message display rows, receipt before durable apply, or accept wrong event -> TC-356-04 RED; revert | exact RED/GREEN; messages helper AUTO core; handler/receipt host `1to1`; thumbnail path exact/AUTO feature; no new path |
| PRES-356-A | Ordinary mutations/fairness, ordinary-media node-off deletion, legacy private DFE, legacy protected receive, exact receipt correlation and deletion payload compatibility remain unchanged. | exact sentinels under Acceptance Gates | existing fixtures | GREEN -> GREEN | any broad policy/retry/wire change -> sentinel RED | exact commands only; do not rerun whole files |

### Test Notes

- TC-356-01a is the first causal RED and must use the existing public delete path, not call a new helper that fails only because its symbol is absent. With a passthrough bridge, decrypt/capture the actual staged envelope and prove one event ID plus sender/target parity across physical v109, clear outer and encrypted inner payload. The v109 insert trigger must fire after the private parent update and prove transaction rollback. Independently, 01b must be HEAD-compilable: seed physical v109 and the P/VO tombstone with existing fixture SQL/APIs, invoke the already-existing completion method, and fail on its current policy-v0 gate. 01c/01d then pin the new storage publication/wiring boundaries; 01d uses analyzer AST/constructor-argument assertions, not brittle literal source ordering.
- TC-356-01b must compare ordered snapshots of `messages`, v109, v108, every v111 row and every attachment. Completion cases with no matching parent or a direct receipt-cleared envelope retire only the exact event; ambiguity/crossed envelope retains it. Hidden P/VO is valid for deletion completion; hidden private EDIT remains impossible.
- TC-356-02 must use completers, not sleeps, and prove real overlap rather than two sequential end states. Pause deletion after it enters the actual repository-wide `synchronizedAll` span, start the real private initial handoff, and assert zero initial DB stage/v111/network progress until deletion releases; reverse the order by pausing the real initial handoff inside its incumbent lifecycle span, starting deletion, and asserting zero tombstone/cleanup/receipt/network progress until release. Then assert superseded/terminal convergence and byte inventories. Observe the database and network at the first cleanup/live callback. The exclusive lease ends before any network await. A v111 prepared/stored generation is never transitioned by v109 staging or private cleanup; its incumbent drain/expiry owns convergence.
- TC-356-03a/03b must seed the current physical v109 row directly with existing fixture SQL/APIs, then wrap a real delegated repository so it exposes `DirectMutationInboxCustodyLifecycleRepository` but deliberately does not expose the text-stage capability. Creation through the new private-stage capability is forbidden in these tests. Test both owner-present-at-first-read and owner-wins-at-pre-egress so each RED reaches the current bad cast rather than failing on a missing new symbol. Do not add another fair-drain matrix; run TC-349-04 unchanged.
- TC-356-03c must distinguish a pre-356 eventless private tombstone (legacy, no promotion) from a Plan-356 event-bearing row (exact owner). The pause case may deposit compatibility bytes but v109 count/envelope/event ID must be byte-identical afterward.
- TC-356-04a must force both DB commit orders with real SQLite and retain live `incomingCommitted`/`incomingAckPending` v111 rows. The P/VO update preserves hidden and every lifecycle clock/state column; an author tombstone remains presentation-terminal. Seed exact peer+target message and reaction display rows plus other-message/other-peer rows: the incumbent message-scoped delete removes the former pair only. 04b must invoke the private lifecycle engine, never the generic `deleteAttachmentsForMessage` path, assert exact key/file/attachment cleanup while v111 survives, and assert reaction records are retired without making their failure revoke the durable deletion. If optional private cleanup capabilities are unavailable after durable apply, the handler records bounded cleanup failure and still receipts the tombstone; it must not fall back to generic destructive cleanup.
- TC-356-04c must reuse the actual strict-private receive/presentation path and completers from Plan 355 and prove blocked competing starts, not sequential extremes. Pause deletion inside its actual `synchronizedAll` span, start the real strict initial path, and assert zero strict DB/v111/thumbnail/marker/publication/network progress until release. Reverse the order by pausing strict receive inside the incumbent lifecycle span after its DB stage but before presentation, start deletion, and assert zero tombstone/cleanup/receipt progress until strict receive releases. Then deletion-first returns the strict initial as superseded with no presentation, while receive-first completes presentation before deletion enters and later leaves no marker/thumbnail. No sleeps, detached work, or direct lock-only proxy.
- Required mutation re-reds: (1) split parent/v109 writes or skip the insert; (2) restore node check before stage or remove the outgoing lifecycle lock; (3) cast retry ownership through the text-stage capability/omit pre-egress recheck; (4) restore the receiver's v0-only predicate/generic cleanup or remove its shared presentation lease. Execute and revert one representative mutation for each bundle; do not create a mutation framework.

## Implementation Steps

1. Snapshot `git status --short` and record `418f92e7f2d7de8b77c7e982f05c89c72df1a01d` as the accepted Plan-356 baseline. Add TC-356-01a/01b, TC-356-02, TC-356-03a/03b and TC-356-04a/04b/04c before production edits and record their causal HEAD failures. Supporting new-symbol and wiring rows may be added after the narrow contract exists, but cannot replace behavioral RED evidence.
2. Factor the incumbent update-only P/VO tombstone transaction body in `messages_db_helpers.dart` so the unchanged legacy commit and one new v109 stage can call the same predicate. Preserve hidden/private lifecycle columns and physical-removal authority. Stop if this requires a schema or insertion-capable parent save.
3. In the physical v109 helper, add exactly one P/VO deletion stage: authenticate raw event/envelope/recipient/sender, check exact winner before capacity, apply the private tombstone within the same transaction, insert v109, and return the committed row/custody projection. Widen completion only for exact private deletion. Do not generalize the ordinary edit/stage predicate.
4. Add one narrow optional private deletion custody capability/result at the incumbent repository boundary, implement it in `MessageRepositoryImpl`, and wire its DB delegate in production and the real DB fixture. Reuse `DirectMutationInboxCustodyLifecycleRepository`; keep its historical method/table names and do not create a new lifecycle interface.
5. In `deleteMessageForEveryone`, qualify private capability before encryption, mint one event ID, build the event-bearing envelope, and hold the existing exclusive private lifecycle lease across atomic stage plus incumbent terminal cleanup. Release it before node/live/protected-store work. Fix node-off to use private settlement and retain v109; schedule the existing hedge beside live transport without waiting on live ACK.
6. Change failed/unacked ownership checks to depend on the generic mutation lifecycle capability rather than the text-stage capability, preserving both initial and pre-egress barriers. Event-bearing ownerless deletion remains fail-closed; pre-356 eventless private DFE retains exact legacy cached/rebuild behavior.
7. Extend `dbApplyIncomingDirectMessageDeletion` with a deletion-only P/VO policy branch that preserves hidden/lifecycle state and v111. In the shared handler, acquire the media repository's incumbent `synchronizedAll` lease before current-event selection/apply and keep it through P/VO lifecycle cleanup plus all marker/presentation-sensitive work; this makes live listener and recovered replay use the same seam. Retire reactions separately best-effort, release the lease, then mint the event-aware receipt. Never fall through to generic attachment cleanup. Preserve absent-target, exact duplicate and marker retirement behavior.
8. Run the four representative mutation re-reds, the one combined filtered TC-356/preservation proof, host `1to1`, dart-only core family, analyzer/changed-Dart format/diff, and one Graphify refresh. Add feature-host-all only if implementation broadens common repository save/load/publication semantics or another shared feature surface beyond these narrow methods.
9. After all GREEN evidence, update this plan, index and coverage receipt, append `- Plan 356 — EXECUTION_COMPLETED`, and keep activation/GAP-N01/release claims open.

## Risks And Blind Spots

- Split commit or racy publication -> TC-356-01 trigger, capacity/collision and post-commit removal cases.
- Initial upload/delete/cleanup lock inversion -> TC-356-02 both lock orders; use the existing repository-wide exclusive lease, never exact-ID-to-exclusive upgrade, and keep network outside it.
- Private edit/disappearing admitted by a broad predicate -> TC-356-01 completion negatives and TC-356-04 receiver negatives.
- Failed/unacked owner exists but a narrow type cast or second lookup misses it -> TC-356-03 lifecycle-only wrapper and pre-egress winner.
- Receiver durable tombstone races strict presentation, uses generic cleanup, leaks key/private artifacts or reactions, deletes v111, clears hidden state, or receipts before commit/lease release -> TC-356-04 real SQLite/lifecycle/receipt assertions.
- Lifecycle / derived-state durability -> TC-356-03 file-backed reopen reconstructs ownership only from v109 plus persisted parent; no process token or attachment is required.
- Sibling-surface consistency -> ordinary text/media/caption, legacy private, Delete-for-Me and disappearing are exact sentinels or explicit exclusions.
- Destructive-action side effects -> TC-356-01 refusal snapshots and TC-356-02/04 artifact/key/v108/v111 inventories prove both authorized deletion and required preservation.
- Invariant re-verification under new transitions -> completion and both retry barriers re-read exact envelope/event/recipient; receiver re-reads target in SQLite.
- Mixed-version activation -> default-off and exact payload/receipt/legacy sentinels; rollout remains WP-07.

Rollback needs no migration or data conversion: DB remains v111, physical v109 is unchanged, and every selector/admission remains default-off. Reverting Plan 356 restores the pre-356 legacy private-deletion route. Tombstones, exact peer+target display retirement, reaction retirement, and incumbent private artifact/key cleanup already authorized by a successfully applied deletion remain valid and are intentionally not reconstructed after code rollback; refusal paths are all-zero and live outgoing v108/v111 remain owned by their existing lifecycle.

## Gate Cadence

- Inner loop: run only the exact active TC-356 row. Do not run whole files after each edit.
- Final focused/preservation proof: one concurrency-4 multi-path invocation with a precise name-regex selecting every `TC-356-` row plus the named preservation sentinels. The files use isolated SQLite/temp fixtures, so four workers are safe here; this compiles each path once before the curated/family gates and avoids eight separate Flutter startups.
- Curated regression: host `1to1` once. It already includes delete, unacked retry, incoming deletion/receipt, messages/v109 helpers, private lifecycle tests and the cached-envelope race.
- Family: dart-only `core-host-all` at concurrency 4 because shared messages/v109 DB helpers and core invariants change. This repository has already proved the batch at four workers; fall back to 2 only for a reproduced resource-contention failure, not a product-test failure. `retry_failed_messages_use_case_test.dart`, repository implementation, pause preservation and payload compatibility are run in the combined exact proof because they are not all in the curated/core sets.
- Frozen-content preflight: Plan 356 necessarily changes `MessageRepositoryImpl` and production bootstrap, whose reviewed bodies are pinned by two DTR-18 hashes. After final formatting and before the expensive core family, run only those two exact contracts. If and only if each mismatch is explained by reviewed Plan-356 edits, re-pin the digest with an adjacent Plan-356 reason; never relax/remove the contract. Then run the preflight green before the one core sweep.
- Omit `feature-host-all` by default: the focused rows plus host `1to1` cover every changed feature owner. Add the 9k-test family only if execution broadens common `MessageRepositoryImpl` save/load/publication behavior or another shared feature production surface.
- No completeness check unless a test path is created/moved or a gate registry changes; this plan expects only existing files/AUTO globs.
- Hygiene: one analyzer, format the union of baseline-to-HEAD, staged, unstaged and untracked Dart files, check each corresponding diff domain, then one incremental Graphify refresh.
- Do not run full `host-all` for this plan. Run it once after the direct-private/disappearing GAP-N01 dependency wave is complete and once at final WP-07 rollout/release closure.

## Acceptance Gates

Snapshot:

```bash
git status --short
```

Causal REDs before production edits; each must select its named test and exit non-zero for the documented behavior:

```bash
flutter test --concurrency=1 \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  --plain-name 'TC-356-01'

flutter test --concurrency=1 \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  --plain-name 'TC-356-02'

flutter test --concurrency=1 \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --plain-name 'TC-356-03'

flutter test --concurrency=1 \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  --plain-name 'TC-356-04'
```

Final focused GREEN plus exact preservation sentinels in one Flutter invocation; expect exit 0, a selected-name receipt containing every `TC-356-` row and each named sentinel (including both named `TC-349-03` payload rows), and zero failures:

```bash
flutter test --concurrency=4 \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/private_media_cleanup_race_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/integration/private_cached_envelope_retry_delete_race_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/receive_protected_photo_thumbnail_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/domain/models/message_deletion_payload_test.dart \
  --name 'TC-356-|TC-349-01 ordinary text mutations stage atomically in shared v109|TC-351-03 node-off media deletion retains one exact v109 event, cleans up only after stage, and performs zero network|TC-349-04 one fair batch routes reaction edit and deletion kinds|TC-353-03 failed media caption edit with a v109 owner blocks legacy send|cached current edit replays exact bytes with one stable event id|authorized incoming protected deletion cleans attachments and local artifacts|TC-349-06 stale edit receipt cannot settle current deletion and exact event receipt can|legacy failed private DFE inbox transport reacquires deletion custody|TC-349-03 current deletion round-trips outer and inner event identity|TC-349-03 legacy deletion remains readable'
```

Format the complete accepted change set before regression gates:

```bash
plan356_base_ref=418f92e7f2d7de8b77c7e982f05c89c72df1a01d
{
  git diff --name-only --diff-filter=ACMR "$plan356_base_ref"...HEAD -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u | while IFS= read -r path; do
  [ -z "$path" ] || dart format --output=none --set-exit-if-changed "$path"
done
```

Run the two frozen-content contracts before the expensive core family. A digest-only failure may be re-pinned only when its changed body is already justified by Plan 356, with an adjacent Plan-356 reason and no weakened assertion; rerun this exact command green before continuing:

```bash
flutter test --concurrency=2 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart \
  --name 'DTR-18 relocates all three Conversation adapters|DTR-18 relocates resume orchestration to app without a core shim'
```

Affected regression and final hygiene:

```bash
plan356_base_ref=418f92e7f2d7de8b77c7e982f05c89c72df1a01d
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 4 --dart-only
flutter analyze

git diff --check "$plan356_base_ref"...HEAD
git diff --cached --check
git diff --check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan356_base_ref"...HEAD
git diff --cached --check
git diff --check
git status --short
```

The union above is mandatory whether execution remains uncommitted, stages files, or commits mid-run; do not replace it with a worktree-only discovery.

Explicitly NOT RUN per plan:

- `./scripts/run_test_gates.sh 1to1`, `feature-host-all` by default, full `host-all`, ad-hoc whole-file reruns beyond the once-only curated/family gates, or completeness without a path/registry change.
- No dedicated Go relay/node/bridge/mixed-version/process, custody-shell, gomobile-binding, migration/account-transfer/SQLCipher, physical/native device, Android/iOS, groups/feed/posts/performance/baseline, deployment, admission-activation, or release campaign. `core-host-all` may incidentally include Dart host contracts under `test/core`/`test/unit`; that does not authorize their platform/native harnesses.
- If implementation touches relay/native/wire/schema, creates a test path, or broadens shared repository behavior, stop and re-review rather than silently adding a large gate campaign.

## Execution Interpretation And Done Criteria

- Expected RED: TC-356-01a observes a private tombstone with zero v109; TC-356-02 observes node-off refusal/no owner or missing lock ordering; TC-356-03 lifecycle-only wrappers escape to legacy; TC-356-04 sees the v1 receiver transaction refuse.
- Green sentinel: exact Plan 349/351/353, legacy-private receive/retry, event receipt and payload commands stay green.
- Pre-existing dirty tree / known failure: none at planning snapshot (`418f92e7f` clean). Execution must record new unrelated changes rather than absorb them.
- Environment blocker: none. Host SQLite/file tests prove this existing Dart/DB owner adoption. No schema, native, relay or OS/device claim exists.
- Scope drift: a new schema/type/drain/flag, relay/native edit, private EDIT/disappearing admission, broad repository behavior change, or feature-family-only failure requiring architecture expansion blocks completion and triggers review.

- [ ] Every P/VO delete stages one exact v109 with its tombstone before cleanup/network, or refuses all-zero.
- [ ] v108/v111 and private lifecycle ownership remain independent in both lock orders.
- [ ] Exact protected acceptance completes P/VO deletion without admitting private EDIT/disappearing or requiring attachments.
- [ ] Node-off/live ACK/failed/unacked/restart/pause behavior retains the exact owner and never uses legacy as authoritative completion.
- [ ] Event-bearing incoming P/VO deletion converges transactionally, uses private cleanup, preserves v111/lifecycle, and receipts only exact durable apply.
- [ ] Pre-356 eventless private DFE and legacy proof-less receive remain unchanged with no v109 promotion.
- [ ] Four causal RED bundles, focused GREEN and four representative mutation re-reds are recorded and reverted.
- [ ] Exact sentinels, host `1to1`, dart-only core family, analyzer/format/diff and Graphify pass; feature family remains omitted unless its condition triggers.
- [ ] Both exact DTR-18 frozen-content preflights pass on the formatted tree; any necessary digest change is reasoned and re-pinned rather than weakened before the single core-family run.
- [ ] No harness registration, migration, device/relay proof, activation, GAP-N01 closure or release claim is added.

## Handoff

- First causal RED command: the combined TC-356-01a/01b command above; both failures must be behavioral and HEAD-compilable.
- Preservation command: the combined focused/preservation name-regex above; verify its selected-name receipt rather than rerunning files separately.
- Manual registration: none expected. Every path already exists and is either AUTO-globbed or explicitly registered as recorded in the Test Contract; the combined proof covers the few paths outside host `1to1`.
- Migration: none; DB remains v111 and physical v109 is byte-compatible.
- Boundary closure: host-only real current-schema SQLite plus file-backed restart. No relay/native/wire/device boundary changes.
- Test-economy decision: no per-plan feature-host-all, non-host Go-tailed `1to1`, full host-all, completeness, device or iOS leg. Add the feature family only on the explicit shared-surface trigger.
- Unresolved evidence: none; independent `$tdd-review` verdict is READY.

## Reviewer Findings

Fresh `$tdd-review` audited sender/storage, receiver/lifecycle and literal gate economy against current source. The first pass returned bounded plan fixes rather than an architectural replan: make exact P/VO completion a HEAD-compilable causal RED; prove one raw event ID across physical v109, outer and decrypted inner payload; seed retry ownership through the existing generic lifecycle interface; run incoming current-event deletion under the same exclusive private lifecycle lease as strict presentation; use exact private cleanup plus separate best-effort reaction retirement; preserve the incumbent peer+target display scope; and distinguish outgoing live-v111 retention from incoming terminal cleanup with independent no-FK v111 survival.

The review also removed vacuous/redundant evidence. It dropped a new payload duplicate in favor of the two existing TC-349-03 rows, required real competing-start barriers inside the actual lifecycle spans, consolidated all final Plan-356 rows and preservation sentinels into one concurrency-4 invocation, omitted the 9,000-test feature family absent a shared-surface trigger, added exact DTR-18 preflights before core, and made format/diff hygiene cover committed, staged, unstaged and untracked Dart. Literal paths, test names, regexes, baseline, options and the concurrency-4 404-path core dry-run resolve. Final independent verdicts are **READY** with no remaining correctness, sufficiency, cadence or overengineering delta.

## Arbiter Decision

**READY / EXECUTION_READY. Core bet confirmed.** Plan 356 is one bounded adopter over the existing physical v109 event owner and incumbent private lifecycle authority. Four causal RED bundles plus four representative mutation re-reds cover the load-bearing atomicity, completion, lifecycle, retry and receiver races. A schema, new outbox/drain/queue/lock/flag, protocol/native change, feature-wide sweep, full `host-all`, or device/iOS leg would be overengineering for this host-only slice.

Disposition: execute from clean baseline `418f92e7f2d7de8b77c7e982f05c89c72df1a01d`. Stop and re-review if implementation needs a schema/wire/native change, new durable authority, broad repository behavior, private EDIT/disappearing admission, or a new test path. Do not claim activation, GAP-N01 closure or release eligibility when this plan completes.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-10 | planning | Plan 356 draft, current source/tests/gates | `$tdd-plan` + Graphify TDD context | Four existing-owner bundles; no schema/protocol/platform work | independent review required | run `$tdd-review` |
| 2026-08-10 | review | Plan 356 plus current source and literal commands | two independent review passes plus targeted re-review; core gate dry-run 404 paths at concurrency 4 | all required deltas incorporated; final verdict READY | none | execute separately from accepted baseline |
