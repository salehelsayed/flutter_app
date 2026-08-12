# 361 - GAP-N01 Direct Linked-Device Blob-Free Event Fanout

Status: POST_EXECUTION_AUDIT_CLOSED / CODE_COMPLETE / default-off authoring / not release-eligible
Type: Modification
Planning baseline: `d016f5449b4f1593317f76d720879762a813a5f6` (clean committed Plan 360 post-execution audit-hygiene closure; residual production repair `c3d2e434bd1dd7340c3dfd5a0e6ae40aaad7b55b`, source/Graphify closure HEAD `97af7e1fe4e68d77dfe1d6e684425f83e30927f0`)
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-18 and OQ-04; GAP-N01 / WP-01 in `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md`; immediate consumer of Plan 360's linked transport/roster authority and predecessor to Plan 362 media/voice/v111 fanout
Classification: DB-v113 blob-free direct-event fanout adopter only; no media/blob, activation, release, or GAP-N01 closure claim
Closure tier: host behavior + additive v113 migration + one exact unchanged-relay namespace sentinel + one availability-bounded Android SQLCipher upgrade/reopen proof; no per-plan Android pair, iOS, relay production/native, feature-family, or full-host campaign

## Planning Progress

| Time | Role | Evidence inspected | Decision / blocker | Disposition |
|---|---|---|---|---|
| 2026-08-11 | Evidence collector / planner | Graphify TDD context; Plan 360 active v112 authority; v108/v109/v111 schemas and helpers; send, receive, retry, drain, receipt, contact-delete and bootstrap owners | Plan 360 supplies stable physical transport plus authenticated contact-device authority, but its worktree and APIs are still changing. Current v108/v109 helpers still equate one transport recipient with the logical contact. | Plan the immediate adopter now, but block RED until Plan 360 is committed, audited, pinned and revalidated. |
| 2026-08-11 | Storage / lifecycle review | v108 and v109 keys, completion semantics, removed-parent reconstruction, generic custody verifier, Plan 344 ACK-or-expiry contract | Looping incumbent single-owner helpers is unsafe; a third outbox or accepted-row ledger is also unnecessary. Existing physical rows can remain the queue if v113 adds the logical-contact/parent facts they cannot recover and one message-owned fanout discriminator. | Add only nullable columns to the incumbent owners; retain exact local retirement on protected STORE acceptance. |
| 2026-08-11 | Trust / mixed-version review | Relay authenticated remote-peer binding, outer envelope sender checks, current handler equality checks, Plan 360 roster states and restricted runtime | A linked sender cannot impersonate its logical account at the transport layer. The outer sender and `ChatMessage.from` must remain the physical peer; the encrypted inner sender remains the logical account and is authorized through current v112 authority. | Reuse the wire and relay unchanged; add one shared physical-to-logical resolver and reauthorize inside durable apply. |
| 2026-08-11 | Counterexample / economy review | Partial A/B acceptance with roster drift to B/C; receipt-cleared wire bytes; all-target completion; later reaction/edit generations; message-only and contact deletion; flag rollback | Atomic all-target staging plus exact per-row retirement makes surviving rows the complete pending set. Survivor-first replay prevents A/C remint; after zero survivors, a durable current message generation ID or exact reaction event proves completion even when receipt settlement cleared the representative envelope. A target ledger/hash, representative bit, accepted state and ACK counter add no necessary decision. | Pin survivor-first/no-resolver replay and terminal no-remint in TC-361-01b/01c; stop if implementation cannot uphold that invariant. |
| 2026-08-11 | Test / gate review | Existing core/feature owners, DTR-18 pins, Plan 360 registrations, relay namespace tests, SQLCipher proof, PRD per-gap cadence | Four concurrent host commands containing six compact TC rows, four causal mutations, one exact Go sentinel, serial 1:1, one core c4 family and one existing Android SQLCipher path are sufficient. | Run concurrent multi-file tests whenever supported to reduce runtime; defer one real event+blob Android-pair composition and wave `host-all` to Plan 362. |
| 2026-08-11 | Final independent re-review | Completion-before-delete, reaction-generation progression, contact-delete interleaving after early cleanup, capability-reduced retry wrappers, canonical witness receipts, linked modality exclusions, and literal Go selector behavior | Preserve the scrubbed generation witness; defer physical contact-message deletion to one reaction-before-message final transaction; require persisted-contact requalification; prove the authored relay subtest's exact PASS line. No target hash/ledger, extra runtime, event device pair or broad gate is needed. | `PREREQUISITE_BLOCKED, CONTRACT_READY`; all storage, trust/receiver and gate reviewers returned READY after amendment. |
| 2026-08-11 | Final Plan-360 post-execution revalidation | Dirty Plan-360 candidate, production call graph, v112 resolver, contact deletion, P2P/startup/application lifecycle roots, and fresh Graphify review fingerprint `b3f410251f97cbbb` | Plan 360 has no clean closure SHA and its setup/QR and Move authorities are not shipping-callable. Its final APIs also require Plan-361 amendments: persisted-contact-qualified forward snapshots, a reverse transport resolver, one within-transaction contact purge body, and role filtering across cold/resume/pause runtime roots. | Keep Plan 361 blocked and change its review state to `REVALIDATION_FIXES_REQUIRED`; apply the bounded Plan-360 repair first, then amend/re-review these exact Plan-361 seams against the committed source. |
| 2026-08-11 | Plan-360 committed repair re-audit | HEAD `481a23d4e350ac5447819bf32279c9ba0418a445`; repair `395accca5`; current Graphify fingerprint `55f4851041c517b5`; setup/QR, Move, authority loading, P2P and blocked-contact transaction call paths | Setup/QR, both Move paths, expected-account loading and blocked-contact requalification are closed. One prerequisite defect remains: only node start translates transport->logical account, while the central post-start P2P network gate still forwards `_currentState.peerId` (the linked transport) to account authority. | Keep RED blocked until Plan 360 normalizes the central gate, proves one linked post-start operation, commits, and refreshes Graphify. The Plan-361 v113/forward/reverse/contact-delete/runtime contract otherwise remains unchanged. |
| 2026-08-11 | Final Plan-360 residual and unblock revalidation | Residual repair `c3d2e434bd1dd7340c3dfd5a0e6ae40aaad7b55b`; source/Graphify closure `97af7e1fe4e68d77dfe1d6e684425f83e30927f0`; audit-hygiene baseline `d016f5449b4f1593317f76d720879762a813a5f6`; current anchored Graphify fingerprint `6e0d3e61531b9292`; all Plan-361 owner/test paths and gate inventories | Central P2P normalization now covers explicit and running-state transport peers before every account-authority decision, while bridge/node identity stays physical. The forward snapshot, reverse resolver, final contact transaction and restricted cold/resume/pause filters remain correctly owned by Plan 361. No source overlap or new subsystem invalidates the reviewed contract. | Prerequisite satisfied. Mark `EXECUTION_READY`; pin the audit-hygiene SHA and retain the necessary-only concurrent cadence. |

## Execution Progress

| Time | Step | Evidence | Result / next action |
|---|---|---|---|
| 2026-08-11 | Planning and independent review | Graphify fingerprint `0c34708b5a8f68fa` was anchored but stale because Plan 360 is actively changing; all load-bearing claims were verified against current source | Plan is coherent for its declared blocked state. Pin a fresh Plan 360 closure SHA/fingerprint and re-review exact APIs before authoring RED. |
| 2026-08-11 | Unblock audit | Current `HEAD` remains `67eca670b72de69994be7e8bd5ffe4ace3f9d372`; the Plan-360 candidate and Plan-361 artifact are uncommitted; fresh dirty-tree graph fingerprint `b3f410251f97cbbb` | Block retained. The fingerprint is diagnostic only and cannot replace the committed-baseline placeholder. |
| 2026-08-11 | Committed repair re-audit | Four Plan-360 findings closed at `481a23d4e350ac5447819bf32279c9ba0418a445`; source review of every `_allowsAccountNetworkSideEffects` caller | One shared logical-account bypass remains; do not replace the baseline placeholder yet. |
| 2026-08-11 | Final unblock audit | Plan-360 audit-hygiene baseline `d016f5449b4f1593317f76d720879762a813a5f6`; source repair `c3d2e434bd1dd7340c3dfd5a0e6ae40aaad7b55b`; Graphify `6e0d3e61531b9292`; tracked tree clean before this Plan-361 artifact | `EXECUTION_READY`. Begin with the clean-tree/ancestry preflight, then author the four compact semantic RED bundles. |
| 2026-08-11 | Storage bundle (TC-361-01a/01b/01c) | Compile-clean semantic RED `+4 -17`; GREEN focused `+21`; whole storage files `+224`; migration-chain + account suites 654 green; v113 additive columns/indexes, plural survivor-first helpers, generation marker protection, serialized contact purge | GREEN. v108/v109 fanout siblings stage atomically against the re-read snapshot; historical rows keep NULL new columns. |
| 2026-08-11 | Sender bundle (TC-361-02a) | RED then GREEN `+12` focused; whole sender files `+314` | GREEN. One shared `DirectEventFanoutAuthoring` routes fresh text, EDIT, DFE and reaction ADD/REMOVE; survivor-first precedes resolver/crypto/capacity; selector-off and no-fanout shapes stay byte-identical incumbent. |
| 2026-08-11 | Receiver bundle (TC-361-03a) | RED then GREEN focused across the seven receive files; whole receiver files `+232` | GREEN. Outer envelope stays physical transport; the reverse resolver maps to at most one logical contact; every durable apply/settle re-runs authority in its own transaction; linked media modality terminally refused. |
| 2026-08-11 | Runtime bundle (TC-361-03b) | GREEN `+7` across the seven runtime files; whole files `+327 ~3`. Deviation: the runtime rows were authored after the wiring landed, so the bundle's semantic RED is carried by the reverted role-filter/generation mutations rather than a pre-implementation red | GREEN. Linked node start parks warm/discovery (primary contrast proven); router post-start skip and deferred `DirectBlobFreeLinkedServices` owner set locked at source; linked pause is a flush-parked local sweep; the exact v113 drain refuses historical/media/unclassifiable rows with the selector OFF; ConversationWired refuses media+voice on the linked gate. |
| 2026-08-11 | Go relay sentinel | `--- PASS: TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation/per_recipient_fanout_ack_isolation` verified by grep per the plan command | GREEN-only unchanged-relay premise: same logical event ID, different exact ciphertext per peer; ACK for A leaves B present and byte-identical. |
| 2026-08-11 | Four mutation re-reds, sequential, reverted | (1) first-target-only staging in all three stage loops -> TC-361-01[bc] `+1 -6`; (2) completion deletes all siblings -> `+3 -4`; (3) vacuous in-transaction reauth (4 sites) -> foundation TC-361-03a red (`Expected: unauthorized, Actual: inserted`); (4) settle ignores the generation marker -> exactly the generation-blind 01b row and the E1->E2->stale-E1 receipt 01c row red. Green restored after each revert | All four invariants are test-carried. |
| 2026-08-11 | Final focused proof | `+60` at concurrency 4 over the 33 listed paths with the plan's combined selector | GREEN once; whole files not rerun afterward. |
| 2026-08-11 | DTR preflight + frozen contracts | Both DTR-18 files `+7` after five digest repins with adjacent Plan-361 rationale (contact/message/reaction adapters, application_root, production bootstrap; message/bootstrap repinned once more after canonical formatting); TC-294-09 ConversationWired API fingerprint `27829d11 -> 5e80dc06` for two optional widget fields + five typedef params; delivered-status census 4 -> 5 for the receipt fanout settlement; runtime-root preservation anchor advanced to v113 | All frozen assertions unchanged; only pins moved, each with rationale. |
| 2026-08-11 | Gates | completeness 1440/1440 (113 test registered in both 1:1 inventories); serial host `1to1` PASS 123/123; `core-host-all --dart-only --batch-flutter --concurrency 4 --reporter failures-only` PASS 406 paths / `+3262`; both lanes rerun once more on the final formatted tree and PASS | GREEN on the settled tree. |
| 2026-08-11 | TC-361-04a Android SQLCipher | PASS on discovered target `emulator-5554`: v112 create -> historical v108/v109 seed -> v113 upgrade with NULL new columns -> idempotent migration + both generation indexes -> persisted fanout generation authority -> wrong-key refusal -> byte-identical reopen -> v113->v112 downgrade refusal -> unchanged reopen. Pixel 6 deliberately not used (`flutter test -d` destroys its stamped release install). Six stale `_userVersion == 112` asserts and the v109 historical-row equality in the shared proof file were repaired for v113 | Acceptance proof on a real Android SQLCipher boundary. |
| 2026-08-11 | Hygiene | Analyzer `No issues found`; 118 changed Dart files format-canonical; `git diff --check` x3 clean; one incremental Graphify refresh (71,897 nodes / 105,515 edges) | Ready to commit implementation + doc receipts. |
| 2026-08-12 | Post-execution audit and Plan-362 prerequisite revalidation | Implementation `be897336d60f94c742fa04cb9933d90886489265`; receipt closure `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`; current anchored Graphify review fingerprint `488091ffcb7bae21` (71,897 nodes / 105,515 links); direct inspection of v113 generation authority, deterministic persisted-contact target snapshots, reverse transport authority, serialized contact purge, restricted cold/resume/pause runtime, and plural retry/drain fail-closed guards | No executable defect or missing Plan-362 prerequisite API found. Historical receipts reconcile, the tracked tree at the receipt closure is clean, and no test gate needs repetition. Mark `POST_EXECUTION_AUDIT_CLOSED / CODE_COMPLETE` and release Plan 362 for its docs-only baseline pin. |

## Final Plan-360 Revalidation Delta

The reviewed v113/generation design remains the smallest viable event adopter.
Final Plan-360 source revalidation identified the following Plan-361-owned seams;
they are incorporated into the scope and tests below rather than left as blockers:

- Build the forward target snapshot from a persisted nonblocked contact and the
  complete active v112 binding facts, not a caller-provided legacy ML-KEM value.
  Re-read the same account key/state/fingerprint set inside the all-target stage
  transaction; missing contact or stale caller state is all-zero.
- Add one exact reverse resolver from authenticated transport peer to exactly one
  current logical contact/account key. Pending, rejected, revoked, ambiguous,
  blocked, contact-removed and key-drift states refuse, and receive/receipt apply
  rechecks that authority in its own transaction.
- Factor the contact helper into an unchanged public wrapper plus a
  `DatabaseExecutor` within-transaction body so the final Plan-361 owner can
  serialize v108/v109, reactions, messages, roster and contact without nesting a
  second transaction.
- The restricted-runtime proof must include `P2PServiceImpl`, `StartupRouter`,
  `ApplicationRoot`, resume and pause owners. The final Plan-360 source starts
  generic LAN/warm/inbox/discovery and other lifecycle work outside the narrow
  deferred-start callback; Plan 361 must filter cold, resume and pause paths to
  exact marked blob-free owners while preserving the primary path.
- Plan 360 now wires its default-off setup/QR route through production. Plan 361
  must not reimplement or broaden that setup surface; it starts from committed
  authority and remains an event adopter.

## Problem And Source-Backed Evidence

- Plan 360 establishes a distinct installation transport, a device-local linked role, DB-v112 remote-contact bindings and an explicit trust decision. It deliberately does not change v108/v109 event custody or start normal linked messaging.
- v108 is physically keyed by `(recipient_peer_id, message_id)` and v109 by `(recipient_peer_id, event_id)`, so both tables can hold multiple device targets. Their helpers nevertheless enforce one global message owner, require `messages.contact_peer_id == recipient_peer_id`, load one owner, and settle against one recipient. v108 also has one globally unique incarnation per row; fanout therefore needs one deterministic incarnation per target.
- v108 may complete after the canonical parent is physically removed and reconstructs a hidden anti-resurrection tombstone. Using the delivery transport as `contact_peer_id` would create a false conversation owner. v109 deletion's clear outer envelope does not disclose its target message, so a new linked row must persist the logical parent ID at authoring time.
- Protected relay custody is already isolated by authenticated recipient peer. STORE, RETRIEVE and ACK use that peer's namespace, and the same logical message/event ID can carry independently encrypted bytes for different peers. The relay requires the outer `senderPeerId` to equal the authenticated STORE peer; no new outer field, action, kind, Redis key or Go/native bridge change is needed. One exact existing-test-file sentinel will pin that ACK for peer A leaves peer B's different exact ciphertext byte-identical.
- Current chat, reaction and deletion handlers require authenticated `message.from`, outer sender and decrypted sender to be identical. For linked traffic, the first two are the physical transport and the decrypted sender is the logical account. Current delivery-receipt handling likewise compares the outgoing logical contact directly with the raw receipt transport.
- `verifyInboxCustody` can re-store one canonical message envelope to `messages.contact_peer_id`, and failed/unacked/stuck rebuild paths assume one owner. Once a message generation is fanout-owned, those legacy fallbacks must never manufacture a single logical-account target after fanout rows transfer.
- Contact deletion currently removes reactions, messages, and then contact/roster authority through separate repository calls while no-FK v108/v109 rows may survive. A linked reaction/apply can interleave after the early reaction sweep, and a late completion can reconstruct an orphan logical tombstone unless reactions, messages, fanout rows, roster and contact converge in one final serialized DB decision.
- v111 binds one attachment to one recipient/incarnation. Every media/voice initial, caption edit, media deletion and Protected/View-Once/disappearing fanout remains Plan 362; Plan 361 must not stage a blob-bearing event whose first device completion could retire the sole blob authority.

Expected production surface after the Plan 360 closure revalidation:

- `app_database_version.dart`, `production_migration_registry.dart`, and one additive `113_direct_linked_device_event_fanout.dart` migration
- `direct_inbox_custody_outbox_db_helpers.dart`, `direct_reaction_inbox_custody_outbox_db_helpers.dart`, the exact message/reaction DB helpers they delegate to, and their existing repository models/interfaces/adapters
- the Plan 360 direct-contact device authority/helper, a persisted-contact-qualified forward snapshot, one exact transport-to-logical reverse resolver, and the incumbent contact-deletion owner factored for use inside the final serialized transaction
- `send_chat_message_use_case.dart`, `send_reaction_use_case.dart`, `remove_reaction_use_case.dart`, and `delete_message_use_case.dart`, preferably through one narrow blob-free target-batch coordinator rather than four independent fanout engines
- the two incumbent v108/v109 drains, pending/failed/unacked retry, `verify_inbox_custody_use_case.dart`, and delivery-receipt settlement
- incoming chat/reaction/deletion handlers and their recovered-listener disposition mapping
- Plan 360's role-aware deferred runtime owner plus `p2p_service_impl.dart`, `startup_router.dart`, production bootstrap, application-root cold/resume/pause wiring, the narrow resume/pause owners, and the smallest existing conversation capability gate
- one new direct-event authoring flag; never reuse the Plan 360 authority-creation flag or group multi-device flag as the event rollout switch

Stop and re-review before adding a third outbox/table, per-target accepted state, target-set hash, representative bit, ACK counter, scheduler, history/contact hydration, push/wake token, new wire/relay field or action, a new P2P protocol or native binding, v111/media behavior, group/announcement behavior, or an unlisted production authority. The explicitly listed Dart P2P linked-role filter remains in scope. One GREEN-only relay namespace subtest is evidence, not relay production scope. Also stop if final Plan 360 APIs no longer provide exact deterministic target resolution, queryable binding/account-key material from which Plan 361 can build the reverse authority, or the restricted-runtime seam assumed here.

## Graph Grounding Snapshot

- Post-execution audit: current anchored fingerprint `488091ffcb7bae21` (71,897 nodes / 105,515 links) over implementation `be897336d60f94c742fa04cb9933d90886489265` and receipt closure `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`; the focused review found no Plan-362 prerequisite defect.
- Graph: `graphify-arch`, current anchored fingerprint `6e0d3e61531b9292` (71,512 nodes / 104,942 links; overlay 1,565 files / 15,349 tests / 1,207 production targets / 1,485 registered), built at residual source commit `c3d2e434bd1dd7340c3dfd5a0e6ae40aaad7b55b` and carried by source/Graphify closure HEAD `97af7e1fe4e68d77dfe1d6e684425f83e30927f0`.
- Planning query: `python3 graphify-arch/tdd_context.py query "Plan 361 blob-free direct linked-device event fanout after Plan 360 direct device roster; direct_inbox_custody_outbox v108, direct_reaction_inbox_custody_outbox v109, send_chat_message_use_case, reactions, edit/delete, retry, ACK completion, receive account-to-transport authentication" --profile tdd --budget 700`.
- Review query: `python3 graphify-arch/tdd_context.py query "Review Plan 361 DB v113 extension of existing v108 v109 for blob-free linked-device fanout; counterexamples: removed parent/contact and roster, partial target completion, linked transport outer versus account inner, receipt mapping, revocation race, retry bypass, selector rollback, media v111 exclusion" --profile review --budget 800`.
- Confidence: anchored and current; load-bearing conclusions were verified in source.
- Final unblock completed: the review query was rerun with `--ensure-fresh`, every literal owner/test path was revalidated, and no load-bearing API or boundary changed beyond the already-incorporated forward/reverse/contact-delete/runtime seams.

## Scope Contract

### Prerequisite, product boundary, and selector

- Author RED only from `d016f5449b4f1593317f76d720879762a813a5f6` or a descendant containing Plan-361 planning/index/status/coverage docs and no production/test/platform/gate drift.
- Add `MKNOON_ENABLE_DIRECT_LINKED_EVENT_FANOUT`, default false, with an injectable host seam. It gates only NEW v113 blob-free authoring. It is separate from `MKNOON_ENABLE_DIRECT_LINKED_DEVICES` (authority creation) and `MKNOON_ENABLE_MULTI_DEVICE_SYNC` (unfinished group scope).
- Primary role + uninitialized contact roster keeps the incumbent single-target path byte-for-byte, regardless of the new selector. Primary + initialized roster requires the selector and uses v113; selector OFF refuses before target crypto/network and never demotes to the legacy target.
- Linked-origin blob-free authoring always requires the selector and v113, even when the target resolver currently yields only the dynamic legacy target. Selector OFF refuses before target crypto/network. This controlled-build rule is not an authenticated remote capability claim.
- Receiving, rejecting/quarantining unsupported linked input, and draining already-committed v113 rows are flag-independent. Flag rollback stops new fanout but cannot strand or reinterpret durable rows.
- v112 proves identity/trust, not that the remote device runs Plan 361. Therefore this plan remains default-off and code-closed only. Activation/general rollout requires an authenticated runtime capability and is an explicit later stop/replan, not a local-flag assumption.

### Additive DB v113; no new queue

- Advance the DB from v112 to v113 with nullable additive columns only:
  - `messages.direct_event_fanout_generation_id TEXT NULL`, containing the message ID for a fanout initial or the exact current edit/deletion event ID; legacy/historical messages remain null;
  - `direct_inbox_custody_outbox.contact_account_peer_id TEXT NULL`;
  - `direct_reaction_inbox_custody_outbox.contact_account_peer_id TEXT NULL`;
  - `direct_reaction_inbox_custody_outbox.parent_message_id TEXT NULL`.
- Historical rows are not promoted or guessed. Null logical-contact fields retain their incumbent single-target meaning (`recipient_peer_id`), and a historical v109 deletion may keep null `parent_message_id` even after its parent/contact is gone. Every newly authored fanout row requires exact nonblank logical contact; every new v109 fanout row also requires exact nonblank parent.
- Each added TEXT column enforces `NULL` or nonblank with a column-local CHECK. New fanout helpers enforce the cross-column generation shape; historical null rows remain valid. Preserve current PKs, the v108 per-row unique incarnation, fair indexes, retry columns, no-FK lifetime, v110/v111 bytes, and relay kinds. Add only generation-first lookup indexes on v108 `message_id` and v109 `event_id`; do not rebuild either table merely to add a cross-column CHECK that the application/helper boundary can enforce on new rows.
- The message generation ID persists through receipt settlement and hidden-tombstone reconstruction, and is atomically replaced by a genuinely later edit/deletion generation. Generic message custody verifier, failed/unacked/stuck rebuild and cached-envelope paths must skip/refuse a current nonnull fanout generation; they may never re-store its canonical envelope to the logical contact.
- Reactions need no second marker column: their canonical row ID is the exact reaction event/tombstone generation, and no generic message verifier owns them. Exact canonical event + zero surviving v109 rows is terminal/idempotent, never authority to resolve a new roster and remint the event.

### Atomic all-target stage and sparse pending-set invariant

- Resolve a deterministic current target snapshot from Plan 360 authority: dynamic legacy target first when active, then active linked bindings in stable device order. Require the persisted nonblocked contact row before crypto, then re-read it with the target snapshot in the stage transaction; require current contact account key, transport peer/public-key binding, ML-KEM key, state and immutable binding fingerprint to be exact. A stale caller-supplied legacy target, removed contact or zero targets fails closed rather than being reinterpreted as an uninitialized legacy contact.
- Build one authenticated logical inner event ID/body. Encrypt it independently for each target ML-KEM key. Every outer envelope uses the local installation's actual authenticated transport peer; on a primary this equals the account, while on a linked secondary it does not.
- Do not hold a SQL transaction across bridge crypto. After all candidates exist, one SQLCipher transaction re-reads and exactly compares the full current target peer/key/fingerprint snapshot, checks capacity for the whole batch, validates canonical policy/event shape, and commits the canonical transition/current generation ID plus every v108/v109 sibling. v108 mints one stable 32-character incarnation per `(message,target)`.
- The canonical message stores one deterministic representative generation witness in `wire_envelope` (active legacy target first, otherwise the first stable linked target) because the other target ciphertexts live only in their rows. That witness is retained after all local siblings transfer solely for logical event-ID/receipt/CAS correlation; it is never a retry or network authority. Nonrepresentative completion compares clear kind/message/event identity plus the persisted generation ID, never ciphertext equality with that witness.
- Zero/crossed target authority, key/fingerprint drift, missing candidate, duplicate transport, partial envelope set, total-capacity shortage, conflicting existing bytes or an injected insert failure leaves canonical message/reaction, every v108/v109 row and network counters byte-identical.
- A byte-exact complete stage replay wins before capacity. More importantly, ANY surviving row for the same logical event is authoritative evidence that the atomic batch already existed: exact replay returns/drains only those survivors before consulting current roster/capacity and never appends a joined target or recreates an accepted/revoked target.
- When no sibling survives, an exact matching `direct_event_fanout_generation_id` or exact canonical reaction event is terminal/idempotent and cannot be reminted, including after a delivery receipt cleared `wire_envelope`. A genuinely new edit/delete/reaction event has a new event ID and may snapshot the then-current roster; an older generation is superseded.
- This survivor-first invariant deliberately replaces a full-target hash/ledger. If implementation needs to infer whether a missing sibling was accepted versus never staged, the all-or-zero stage/only-exact-retirement invariant was broken and the plan must stop rather than add a shadow state machine silently.

### Transport, completion, retry, deletion, and receipts

- After durable all-target commit, feed the exact rows through the incumbent per-row live/protected-STORE owner and fair drains. Do not add a queue/scheduler or hold sibling work in memory. Network begins only after all rows exist; one live ACK or protected STORE acceptance never cancels another row.
- Protected `stored|duplicate` with exact `ackOrExpiryAccepted` is terminal LOCAL handoff for that target and deletes only its exact v108/v109 row. The relay then owns that recipient's ciphertext until its device ACK or fixed expiry. Do not retain a local `accepted` row or wait for delivery receipts to retire outbox rows.
- For a v108/mutation generation, only the final surviving sibling's accepted handoff may project canonical `inboxed`, and only while the canonical generation ID still matches. An authenticated receipt may clear the representative witness only when its mutation event ID matches the exact current generation and may project the stronger contact-level `delivered`; stale/prior/future event receipts refuse. Later sibling completion still retires its exact row but must not downgrade or remint. A genuinely later edit/deletion atomically replaces generation ID + witness. Hidden tombstone reconstruction preserves the generation ID but scrubs the witness. Reaction completion has no receipt and no message-status projection.
- Retry/restart loads every surviving physical row and replays its exact immutable transport peer/envelope without roster lookup, re-encryption or incarnation rotation. Partially completed batches remain partial across restart. Generic single-owner loaders either become explicit plural/fanout-aware owners or fail closed on marked generations; they may not select an arbitrary sibling.
- Any v108 sibling can reconstruct the same scrubbed hidden tombstone after MESSAGE-only removal, using `contact_account_peer_id`, never the delivery transport. Target ciphertext/key material is not copied into the tombstone.
- The central single-message delete owner must not physically erase the only no-remint fact for an outgoing row with nonnull `direct_event_fanout_generation_id`. In one transaction it first removes reactions for that message, then scrubs/hides the message while preserving ID, logical contact and generation ID. Delete-before-completion still allows one exact sibling to reconstruct the same scrubbed tombstone; completion-before-delete followed by exact same-generation replay produces zero resolver, crypto, rows and network. Bulk contact deletion remains a physical purge.
- Contact deletion may remove files/keys/attachments/introductions and perform an early best-effort reaction cleanup before the final DB decision, but it must NOT physically purge messages first. The exact final DB owner must still see those parents and, in one serialized transaction, delete v108/v109 rows whose logical contact is the removed account (`COALESCE(contact_account_peer_id, recipient_peer_id)` for historical compatibility), delete `message_reactions` through the still-live contact message IDs, delete those messages, then delete Plan 360 roster metadata/bindings and the contact. Existing message/contact deletion triggers own direct-notification cleanup; the application/repository layer reconciles its message/reaction caches and removal publication from that committed purge. Completion/apply/reaction-first is swept; delete-first makes later completion/apply/reaction absent or unauthorized. No row or canonical reaction may recreate an orphan conversation.
- Revoke-before-stage excludes a target. Stage-before-revoke keeps the immutable local/relay obligation; retry never consults current roster. A revoked recipient that later retrieves is durably rejected/quarantined and ACKed without apply/receipt/notification. Hard purge of already-relayed ciphertext would require a new authenticated relay delete protocol and is out of scope.
- Receipts remain plaintext v1 unchanged for fresh text plus v109 EDIT/DFE only; reaction ADD/REMOVE retain their incumbent no-receipt/no-message-status contract. Send a receipt to the raw authenticated origin transport (`message.from`), not the logical account. On receipt ingress, reverse-authorize the raw transport to the logical contact and settle only an exact current canonical generation; never retire/cancel sibling v108/v109 rows because their local handoff already completed independently. Current active transport->logical authority is an account-level delivery assertion, not historical per-target membership proof after a child transferred. Unknown/revoked/key-drift/cross-account transports and stale event IDs are zero-effect. If product later requires per-target receipt attestation, stop/replan for retained target evidence rather than smuggling in an accepted ledger.

### Receive authentication and narrow linked runtime

- Preserve two identities explicitly: `ChatMessage.from` and the outer envelope `senderPeerId` must equal the authenticated PHYSICAL transport; the decrypted payload sender must equal the resolved LOGICAL contact account. Never emit outer logical account from a linked transport—the relay correctly rejects that impersonation.
- Add one shared reverse authority over a persisted nonblocked contact. A linked transport requires initialized roster metadata plus exactly one active v112 binding whose verified account key still equals the current contact key; a legacy transport requires the current dynamic legacy authorization. A transport claimed simultaneously by legacy and linked authority is ambiguous and refuses. Pending/rejected/revoked, duplicate/ambiguous transport, key drift, removed/unknown account and outer/inner mismatch also refuse.
- Resolve logical contact and apply the incumbent per-kind blocked policy before decrypt whenever the existing behavior permits. Re-read and reauthorize transport/account/key inside the same SQL transaction as message/reaction/deletion/receipt apply, so revoke-first has zero durable effect and apply-first commits exactly once. Do not add a global lock when SQLite writer serialization owns the race.
- Current legacy transport==logical behavior remains byte-identical. Old receivers reject linked outer!=inner traffic; old senders reach only the legacy target. This is fail-closed mixed-version behavior, not backward-compatible linked delivery.
- Extend Plan 360's restricted linked runtime with one `startDirectBlobFreeLinkedServices` path: exact P2P inbox router/stage/replay+ACK, chat/reaction/deletion/receipt listeners, and existing-conversation blob-free text/edit/delete/reaction authoring only. Its drain/retry loaders must select exact nonnull v113 fanout generations with blob-free event shape; they must not invoke broad historical/null/media/private v108/v109 loaders. Already-committed exact v113 rows drain even with authoring selector OFF. Do not call generic `startLiveServices`.
- Keep provider registration, contact request/key exchange, contact/history hydration, group/post/feed, media/voice/private authoring/download, and generic push/wake owners stopped. Unsupported linked-role media/private input is durably rejected/quarantined and ACKed with zero apply, application receipt, publication or notification.

### Exact adopter and exclusion matrix

In scope:

- fresh v0 ordinary direct TEXT v108, including already-supported quote/forward metadata;
- ordinary direct text EDIT and Delete-for-Everyone v109;
- direct reaction ADD and REMOVE v109 over an incumbent eligible direct parent;
- linked physical-to-logical receive authentication, with plaintext delivery receipts for fresh text and text EDIT/DFE only;
- primary and restricted linked-origin authoring under the default-off selector.

Out of scope and preserved:

- every media/voice initial, caption edit, media deletion, Protected/View-Once/disappearing event fanout, v110/v111/blob transfer or private lifecycle;
- private EDIT (remains the Plan 359 terminal refusal), automatic historical promotion/backfill, contact/history sync, contact requests, cross-device read/notification clearing;
- group/announcement event or blob fanout, provider/wake tokens, relay/Redis/Go/native/bindings production changes or broad gates, activation/cohort/telemetry, hard remote purge, GAP-N01 closure and release eligibility.

## Test Contract - Necessary Tests Only

| ID | Behavior proved | Exact owner / test path | RED -> GREEN | Counterexample / mutation discriminator |
|---|---|---|---|---|
| TC-361-01a | Fresh v113 and v112->v113 preserve every v108-v112 row, v110/v111 and roster byte-for-byte; add only the four nullable columns plus two generation lookup indexes; retain a parentless/contactless historical v109 deletion; run twice/reopen; one-way downgrade; no backfill/FK | new `test/core/database/migrations/113_direct_linked_device_event_fanout_test.dart`; extend existing `integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart::TC-361-04a` for the real Android engine | v112/current registry lacks v113 -> exact additive host migration and one encrypted upgrade/reopen pass | Backfill/guess parent, table rebuild loss, schema/index omission, wrong order/version or downgrade acceptance -> red |
| TC-361-01b | v108 all-target stage is atomic; exact survivor-first replay precedes resolver/capacity; A accepted while B survives, roster A/B -> B/C drift still retries B only; representative/nonrepresentative completion in both last-sibling orders; receipt-cleared wire and later generation cannot remint/downgrade. Delete-before-completion reconstructs the logical tombstone, while all-complete -> delete-for-me preserves a scrubbed generation witness and exact replay stays zero-effect. Both contact-delete transaction orders leave no message/reaction/outbox/orphan and reconcile cached/removal state. With zero siblings and a nonnull marker, verifier/send/failed/unacked wrappers lacking the plural capability still refuse before legacy network. | `test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart` (rename incumbent `TC-345-09b` to `TC-361-01b`, retain its legacy/uninitialized one-owner subcase, and add the exact authorized fanout positive); `messages_db_helpers_test.dart`; `contacts_db_helpers_test.dart`; `delete_contact_use_case_test.dart`; `pending_message_retrier_direct_inbox_custody_test.dart`; both drains/verifier and exact failed/unacked retry rows | HEAD rejects sibling owner and hard-deletes the canonical witness -> one canonical plus N exact transport rows, scrubbed no-remint authority, all-zero target/key/capacity/insert failures and both completion/deletion orders | Stage only first/partial batch, re-resolve after a survivor, event-wide delete, hard-delete the completed generation, make marker protection depend on an optional plural capability, arbitrary single-owner load, lose/ignore generation ID, compare nonrepresentative ciphertext to canonical, or legacy verifier fallback -> red |
| TC-361-01c | v109 atomically stages reaction ADD/REMOVE and ordinary text EDIT/DFE target batches; persists logical contact + parent ID for new rows; partial completion/restart replays survivors only. After all A/B mutation rows transfer, a real exact receipt clears the representative witness but same-event replay stages zero rows; stale/future receipts refuse; new E2 may stage and overlapping E1 completion retires itself without projecting E2. Reaction sequence R1 ADD complete -> exact R1 replay zero -> R2 REMOVE stages -> stale R1 zero -> R3 later ADD stages; an old survivor cannot mutate the newer canonical row. In the contact race, pause after the incumbent early reaction cleanup but before final DB deletion, stage a reaction, then prove the final transaction removes reaction/message/outbox/contact; inverse delete-first refuses. Single-message delete performs its reaction sweep before scrub/hide, and later staging refuses the hidden/deleted parent. Reactions remain no-receipt. | `test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart`; `messages_db_helpers_test.dart`; `contacts_db_helpers_test.dart`; `delete_contact_use_case_test.dart`; `drain_direct_reaction_inbox_custody_outbox_use_case_test.dart`; exact failed/unacked retry rows | HEAD binds parent contact to one recipient, accepts reactions against a merely matching live ID, and purges messages before its final contact writer -> plural exact target rows, durable generation ID, one final reaction-before-message purge, hidden/deleted-parent refusal and independent exact retirement | Roster re-resolution after partial, event-wide retirement, missing parent/generation identity, early physical message purge, stale receipt acceptance, same-event remint after receipt, sticky reaction terminal that suppresses R2/R3, stale R1 projection over newer canonical, reaction stage after delete, reaction receipt minting, or delivered->inboxed downgrade -> red |
| TC-361-02a | Default-off/version-skew and production sender adapters: primary+uninitialized stays exact legacy; OFF+initialized or OFF+linked refuses pre-crypto/network; ON requires a persisted nonblocked contact both before crypto and in the transaction, encrypts one logical blob-free event independently per target, and commits every row before any network; fresh text, EDIT, DFE, reaction ADD/REMOVE use the shared owner; one partial network outcome cannot cancel siblings. An existing survivor is discovered BEFORE resolver/bridge crypto, so B/C roster drift returns B only with resolver/crypto/network counters zero and a same-event conflicting canonical candidate refuses. Revoke-first excludes that target; stage-first retains its immutable sibling, and retry performs zero resolver/crypto while replaying the stored bytes. Removed-contact plus stale caller target refuses rather than falling back to uninitialized legacy. One representative attachment-bearing ordinary-media draft is never routed to v113. | `test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart`; exact adapter subrows in `message_repository_impl_test.dart`, `reaction_repository_impl_test.dart`, `send_chat_message_use_case_test.dart`, `send_reaction_use_case_test.dart`, `remove_reaction_use_case_test.dart`, and `delete_message_use_case_test.dart` | HEAD has no event selector/batch owner -> compact parameterized production-adapter matrix green | Single-target loop, caller roster trust, resolver/crypto/network before contact/survivor check or full stage, append C after partial transfer, drop a stage-first sibling after revoke, consult the resolver/crypto on retry, treat removed contact as uninitialized legacy, accept crossed canonical bytes, linked fallback, media promotion, live-ACK sibling cancellation or per-kind bespoke owner -> red |
| TC-361-03a | Shared physical->logical ingress accepts legacy and exact active linked text/edit/delete/reaction, keeps outer/raw physical + inner logical, preserves incumbent blocked semantics, and reauthorizes within durable apply; revoke-first is zero-effect, apply-first exactly once. Contact-delete-first leaves zero ingress effect, while apply-first is removed by the final contact sweep. Authenticated linked ordinary-media and P/VO/disappearing/private payloads are terminally rejected/quarantined with zero v111/private lifecycle/apply/receipt/publication/notification. Exact text/mutation receipt goes to origin transport and settles only the logical current generation while siblings remain; reactions mint none. | `direct_linked_device_addressing_foundation_test.dart`; exact handler/listener/receipt subrows in incoming chat/reaction/deletion, chat/reaction listener and delivery-receipt suites | HEAD equality checks reject valid linked traffic and receipt correlation -> authenticated mapped apply/receipt plus exact excluded-modality dispositions | Compare raw transport to inner account, authorize before but not inside transaction, accept revoked/key-drift/cross-account, lose either contact-delete/apply order, admit media/private, decrypt blocked input, mint reaction receipt, send receipt to account, accept stale event, or clear sibling rows -> red |
| TC-361-03b | Cold start, resume and pause start only the exact direct blob-free linked router/listeners/replay and exact v113 blob-free drains even when authoring selector is OFF; a mixed table proves historical/null/media/private v108/v109 rows stay byte-identical. P2P startup and `StartupRouter` do not start generic LAN/warm/proactive-discovery/push/group owners for the linked role. Primary cold/resume/pause stays unchanged; generic push/contact/group/post/media/voice owners remain zero; UI refuses excluded modalities. | `test/core/services/p2p_service_impl_test.dart`; `test/features/identity/presentation/screens/startup_router_test.dart`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart`; `test/core/lifecycle/main_deferred_startup_wiring_test.dart`; smallest exact rows in `handle_app_resumed_upload_ordering_test.dart` and `handle_app_paused_test.dart`; smallest exact `conversation_wired_test.dart` policy row only if Plan 360 has not already provided an injectable modality gate | HEAD linked foundation starts no event owners through the deferred callback but surrounding cold/resume/pause roots still start broad owners -> exact role-filtered lifecycle | Bypass the role filter at P2P/router/application cold/resume/pause, call generic runtime/broad shared-table drain, or admit media/private/voice -> red |

Preservation in the same final filtered run only:

- `TC-360-03a direct-device trust owns exact admission revocation and legacy resolution` (name revalidated at the committed Plan 360 baseline);
- `TC-342-02 atomic immutable direct-text custody mutations fail closed` and `TC-343-02 atomic direct-reaction custody preserves every transition` after their intentional plural-owner narrowing;
- `TC-343-05 retrier lifecycle drains text and reaction custody without sibling starvation`;
- `TC-359-01b disappearing deletion completion is exact and private EDIT stays refused`;
- `TC-345-06 prepared voice delegates uploaded audio to exact v108 media custody` as the one Plan-362 boundary sentinel.

Author one GREEN-only unchanged-relay boundary subtest in existing `go-relay-server/ack_custody_retrieval_test.go::TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation/per_recipient_fanout_ack_isolation`: store the same logical event ID with different exact ciphertext for peers A/B, ACK A, and assert B's protected row and bytes remain. Its command must verify the exact subtest PASS line so an absent subtest cannot false-green. It is not a relay production RED or permission for a package sweep.

Do not create a mode x event x device cross-product. Use one legacy target plus two linked targets in host matrices, representative capacity/key/roster failures, and the same shared physical-to-logical authorization table across event kinds. Existing whole suites and the curated lane own broad ordinary/PVO/disappearing/group preservation.

All revoke/contact-delete/apply/stage ordering rows use explicit transaction-entry and release barriers against real SQLite writers; no sleeps, zero-yield loops or source-order assertions count as race evidence.

Four mutation re-reds only:

1. stage only the first target or allow partial batch insert -> TC-361-01b/01c red;
2. re-resolve roster after one sibling transfers, or delete all siblings on one acceptance -> TC-361-01b/01c red;
3. bypass physical-to-logical in-transaction reauthorization -> TC-361-03a red;
4. clear/ignore `direct_event_fanout_generation_id` on receipt or treat every nonnull marker as terminal across later generations -> the receipt-cleared E1 -> E2 -> stale-E1 sequence in TC-361-01c red.

## Implementation Steps

1. **Satisfied.** Plan 360 is post-execution-audit closed; pin `d016f5449b4f1593317f76d720879762a813a5f6`, retain Graphify `6e0d3e61531b9292`, and run the literal clean-tree/ancestry/no-drift preflight before RED.
2. Add the default-off direct-event authoring selector and compile-only inert types/ports required to make every owning RED compile. Missing symbols are not a behavioral RED receipt.
3. Author TC-361-01a through 03b as compact per-owner semantic REDs. Register only the genuinely new v113 migration path in both 1:1 arrays; rename TC-345-09b to TC-361-01b, retain its legacy/uninitialized one-owner subcase, and add the authorized plural case rather than duplicating it.
4. Add the additive v113 migration/version/registry and nullable model mappings. Preserve historical null semantics and update current-version pins deliberately.
5. Add exact plural v108/v109 stage/load/complete operations, message fanout marker handling, survivor-first replay, final-sibling projection, logical tombstone reconstruction, fanout-marked single-message scrub/hide, and atomic reaction/message/outbox/contact purge. Defer physical contact-message deletion to that final transaction and reconcile repository cache/removal publication afterward. Keep existing legacy helpers byte-compatible.
6. Add one shared target-batch qualification/encryption handoff and wire the five blob-free sender actions. Requalify the exact v112 snapshot inside the stage transaction and begin network only after commit.
7. Make drains/retry/verifier plural-aware and exact-row-only. Preserve local handoff on protected STORE acceptance and relay-owned ACK/expiry.
8. Add shared reverse transport authority and apply-time reauthorization to chat/reaction/deletion/receipt paths, including exact recovered dispositions and physical receipt routing.
9. Start only the narrow linked blob-free services and gate excluded UI/actions. Preserve primary startup and all Plan-362 modalities.
10. Author and run the exact GREEN-only Go namespace sentinel with an exact PASS-line assertion; then run four mutation re-reds, one final concurrency-4 filtered host proof, DTR preflight if affected, completeness, serial host 1:1, one core c4 family, and one availability-bounded Android SQLCipher proof. Do not run a relay package sweep or separate Android pair.
11. Run analyzer, changed-Dart format/diff hygiene and one incremental Graphify refresh; update plan/index/status/coverage receipts without claiming activation, Plan-362 behavior or GAP-N01 closure.

## Gate Cadence - Necessary Tests Only

- **Run tests concurrently whenever the runner supports it to reduce execution time.** Every multi-file Flutter RED/GREEN, the two-file DTR preflight, and the final focused proof use `--concurrency=4`. Mutation edits are sequential because they share one worktree, host `1to1` is serial by script contract, and the single-device SQLCipher proof owns one target.
- Inner loop: one compile-clean semantic RED/GREEN per storage, sender, receiver and runtime bundle; never repeat whole owning files after the final GREEN.
- Final focused: one name-filtered concurrency-4 invocation over exact owners and preservation sentinels.
- DTR-18: if contact/message/reaction repository implementations or production bootstrap/application root change, run the two exact DTR contract files once before core. Repin only actually changed digests with adjacent Plan-361 reasons; assertions remain unchanged.
- Registration: add only `test/core/database/migrations/113_direct_linked_device_event_fanout_test.dart` to both 1:1 arrays. The committed Plan-360 baseline measures host 1:1=122, core=405, feature=842 and host-all=1341; the one new registered core migration path yields expected 123/406/842/1342, which execution must recount rather than assume.
- Curated: host `1to1` exactly once; do not pass unsupported batch/concurrency flags.
- Family: one dart-only `core-host-all` at concurrency 4 because DB version/registry and shared outbox helpers change. Omit feature family because the focused proof plus curated lane cover changed feature owners.
- Device: reuse the existing `direct_inbox_custody_outbox_sqlcipher_proof_test.dart` on one explicitly discovered available Android for v112->v113 encryption/reopen/run-twice/downgrade only. If no Android is available, record `N/A (target unavailable by project policy)`. Do not add a Plan-361 pair scenario; Plan 362's wave proof composes real event + blob delivery once.
- Relay/Go: run only the exact GREEN namespace/ACK-isolation subtest above. Wire grammar, custody kind and production are unchanged, so omit relay/node/bridge packages and every broad Go gate. Also omit non-host 1:1, feature/full `host-all`, native/bindings, iOS, performance, group and duplicate SQLCipher files. The 360-362 dependency wave runs full `host-all` and one real event+blob Android pair after Plan 362.

## Acceptance Commands

These commands are authorized from the pinned clean baseline.

```bash
# Final prerequisite preflight. A committed Plan-361 docs/index/status update may sit above the base.
PLAN361_ACCEPTED_BASE='d016f5449b4f1593317f76d720879762a813a5f6'
test -z "$(git status --porcelain)"
git rev-parse --verify "${PLAN361_ACCEPTED_BASE}^{commit}"
git merge-base --is-ancestor "$PLAN361_ACCEPTED_BASE" HEAD
test -z "$(git diff --name-only "$PLAN361_ACCEPTED_BASE"...HEAD | grep -Ev '^(Test-Flight-Improv/361-gap-n01-direct-linked-device-blob-free-event-fanout-tdd-plan.md|Test-Flight-Improv/00-INDEX.md|STATUS.md|UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md)$' || true)"

# Storage/migration semantic RED, then its inner GREEN. Use inert scaffolding first if APIs are absent.
flutter test --concurrency=4 \
  test/core/database/migrations/113_direct_linked_device_event_fanout_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/core/database/helpers/contacts_db_helpers_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/features/contacts/application/delete_contact_use_case_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/application/verify_inbox_custody_use_case_test.dart \
  --name 'TC-361-01'

# Sender semantic RED/GREEN, concurrently across independent files.
flutter test --concurrency=4 \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/domain/repositories/reaction_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_reaction_use_case_test.dart \
  test/features/conversation/application/remove_reaction_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  --plain-name 'TC-361-02a linked blob-free event authoring stages the exact target batch before transport'

# Receive/auth semantic RED/GREEN, concurrently across independent files.
flutter test --concurrency=4 \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/conversation/application/reaction_listener_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  --plain-name 'TC-361-03a linked physical transport maps to one logical event authority'

# Restricted-runtime semantic RED/GREEN.
flutter test --concurrency=4 \
  test/core/services/p2p_service_impl_test.dart \
  test/core/lifecycle/main_deferred_startup_wiring_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_paused_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  --plain-name 'TC-361-03b linked runtime starts only direct blob-free event owners'

# One final focused proof. Do not rerun these whole files afterward.
flutter test --concurrency=4 \
  test/core/database/migrations/113_direct_linked_device_event_fanout_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/core/database/helpers/contacts_db_helpers_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/lifecycle/main_deferred_startup_wiring_test.dart \
  test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart \
  test/core/lifecycle/handle_app_paused_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart \
  test/features/contacts/integration/direct_linked_device_addressing_foundation_test.dart \
  test/features/contacts/application/delete_contact_use_case_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/domain/repositories/reaction_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/send_reaction_use_case_test.dart \
  test/features/conversation/application/remove_reaction_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/application/verify_inbox_custody_use_case_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_reaction_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/conversation/application/reaction_listener_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/identity/presentation/screens/startup_router_test.dart \
  --name 'TC-361-|TC-360-03a|TC-342-02|TC-343-02|TC-343-05|TC-359-01b|TC-345-06 prepared voice delegates'

# Four mutations run one at a time; rerun only their causal TC selector, then revert immediately.

# One unchanged-relay premise, exact selector only; prove the authored subtest ran.
plan361_go_log="$(mktemp)"
trap 'rm -f "$plan361_go_log"' EXIT
if ! (set -o pipefail; \
  (cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
    -run '^TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation$/^per_recipient_fanout_ack_isolation$' \
    -count=1 -v) | tee "$plan361_go_log"); then
  exit 1
fi
if ! grep -Fq -- '--- PASS: TestRelayNotificationClosure_AckCustodyRetrievalAndAckIsolation/per_recipient_fanout_ack_isolation' "$plan361_go_log"; then
  rm -f "$plan361_go_log"
  trap - EXIT
  exit 1
fi
rm -f "$plan361_go_log"
trap - EXIT

# DTR preflight only because the reviewed adapters/bootstrap are expected to move.
flutter test --concurrency=4 \
  test/unit/dtr18_placement_closure_contract_test.dart \
  test/unit/dtr18_layering_relocation_contract_test.dart

# New-path accounting and affected gates exactly once.
./scripts/run_test_gates.sh completeness-check
./scripts/run_host_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all \
  --dart-only --batch-flutter --concurrency 4 --reporter failures-only

# One real-SQLCipher schema proof on one explicitly discovered Android target.
flutter devices --machine
adb devices -l
PLAN361_ANDROID_ID='<AVAILABLE_ANDROID_ID>'
test "$PLAN361_ANDROID_ID" != '<AVAILABLE_ANDROID_ID>'
flutter test integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart \
  -d "$PLAN361_ANDROID_ID" \
  --plain-name 'TC-361-04a Android SQLCipher v112-to-v113 linked event fanout custody survives reopen'

# Final static/hygiene checks.
set -euo pipefail
plan361_base_ref="$PLAN361_ACCEPTED_BASE"
flutter analyze
plan361_dart_list="$(mktemp)"
trap 'rm -f "$plan361_dart_list"' EXIT
{
  git diff --name-only --diff-filter=ACMR "$plan361_base_ref"...HEAD -- '*.dart'
  git diff --name-only --diff-filter=ACMR -- '*.dart'
  git diff --cached --name-only --diff-filter=ACMR -- '*.dart'
  git ls-files --others --exclude-standard -- '*.dart'
} | sort -u > "$plan361_dart_list"
test ! -s "$plan361_dart_list" || \
  xargs dart format --output=none --set-exit-if-changed < "$plan361_dart_list"
rm -f "$plan361_dart_list"
trap - EXIT
git diff --check "$plan361_base_ref"...HEAD
git diff --check
git diff --cached --check
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check "$plan361_base_ref"...HEAD
git diff --check
git diff --cached --check
git status --short
```

If no Android target is available, record the SQLCipher leg exactly as `N/A (target unavailable by project policy)` and do not substitute iOS or require another model/API band. The later Plan-362 wave Android-pair scenario is separate and must not be pulled into this per-plan cadence.

## Risks, Stops, And Reversibility

- Partial fanout: all-N stage is atomic and only exact accepted handoff deletes a row. A surviving subset is the retry set, not permission to resolve a new roster. Breaking this invariant requires re-review.
- Identity laundering: linked outer sender is physical, inner sender is logical. Writing outer=account, trusting caller-supplied logical identity, or accepting a stale/revoked binding is a correctness/security failure.
- Contact deletion: no FK or roster lookup may be needed after the final delete transaction. Both DB writer orders must converge without an orphan tombstone.
- Revocation: it stops new targeting and durable receive apply; it cannot recall already-stored relay ciphertext. A hard purge promise requires a new relay protocol and is excluded.
- Mixed version: new authoring remains default-off. Old receivers reject linked traffic; old senders reach only the legacy target; DB v113 downgrade fails closed. No activation or compatibility percentage is claimed.
- Rollback: selector OFF stops new fanout but drains durable rows. Before v113 open, code rollback is normal; after open, older DB binaries fail closed. Removing v113 columns/markers or reinterpreting them is not rollback.
- Scope: any need for media/voice/v111, provider wake, contact/history hydration, group fanout, new relay/wire/native behavior, a third outbox or full target ledger moves work to Plan 362/later or triggers a new reviewed repair.

## Done Criteria

- [x] Plan 360 is committed and post-execution audited; baseline `d016f5449b4f1593317f76d720879762a813a5f6` and Graphify `6e0d3e61531b9292` are pinned, exact APIs/paths are revalidated, and plan/index/status move to `EXECUTION_READY` before RED.
- [x] DB v113 is additive, one-way, no-FK and preserves historical v108-v112/v110/v111/roster data without promotion or guessed v109 parents.
- [x] Four concurrent host commands containing six compact TC rows receive compile-clean behavioral REDs and final GREEN; TC-361-04a is an acceptance proof, not a fabricated host RED.
- [x] Atomic all-target stage, survivor-first retry, exact per-row completion, final-sibling projection and no-remint terminal convergence pass for v108/v109.
- [x] Physical-outer/logical-inner receive authority, in-transaction revoke race, receipt routing and invalid terminal disposition pass without sibling cancellation.
- [x] Default-off selector, narrow linked runtime and media/private/voice exclusion pass; primary/uninitialized behavior is byte-identical.
- [x] Four representative mutations re-red independently and are reverted.
- [x] One final concurrency-4 focused proof, one exact Go ACK-isolation sentinel, conditional DTR c4, completeness, serial host 1:1, core c4, analyzer/format/diff and one Graphify refresh pass once.
- [x] One available-Android SQLCipher v112->v113 proof passes or is recorded N/A under project policy; no per-plan pair/iOS substitute is required.
- [x] No new table/outbox/accepted ledger/hash/separate representative row, bit or state/ACK counter/scheduler, wire/relay/native change, historical promotion, full/feature host family, activation, GAP-N01 or release claim is introduced; the deterministic canonical `wire_envelope` witness is the only representative projection.

## Reviewer Findings

### Lens 1 - Claims and boundaries

- Tightened. Plan 361 adopts only blob-free direct events and explicitly leaves all v111/media/voice/private/group behavior to Plan 362 or later.
- The runtime capability gap is explicit: a trusted v112 binding is identity authority, not version negotiation. Default-off controlled builds are sufficient for code closure only.

### Lens 2 - Test completeness

- Four concurrent host commands contain six compact TC rows over the independently changing migration/storage, sender, receiver and runtime boundaries. Adapter variants are parameterized rather than multiplied into a modality x device matrix.
- The partial-acceptance + roster-drift counterexample, both contact-delete orders, in-transaction revoke race, generic retry bypass and outer/inner identity split are causal rather than source-order assertions.

### Lens 3 - Alternate production paths

- Closed. Failed/unacked/stuck/verifier paths, both drains, contact deletion, receipts and restricted bootstrap are named. Existing rows drain flag-independent and no single-owner fallback may reinterpret them.
- `TC-345-09b` is intentionally renamed to `TC-361-01b`, not silently weakened: its legacy/uninitialized subcase remains single-target while exact authorized v113 fanout permits multiple physical owners for one canonical event.

### Lens 4 - Gates and evidence

- Lean and concurrent. Multi-file tests and DTR use concurrency 4 wherever supported; only the script-owned 1:1 and one-device SQLCipher legs are serial.
- One core schema family and one exact unchanged-relay sentinel are justified. Feature/full host, per-plan device pair, broad Go/relay/native, iOS and performance campaigns are omitted; Plan 362 owns the aggregate pair and wave full-host proof.

### Lens 5 - Operability and reversibility

- New authoring has a dedicated default-off switch; persisted receive/drain authority is not switched off. Relay admission rollback retains local retry and remote retrieve/ACK behavior.
- The DB floor and already-relayed ciphertext cannot be rolled back destructively. Contact deletion/revocation semantics are honest about what local code can and cannot recall.

## Arbiter Decision

`POST_EXECUTION_AUDIT_CLOSED / CODE_COMPLETE.` The core v113 bet is
sound: no third queue, accepted-row ledger, target-set hash, representative bit,
new relay protocol, event-specific scheduler or per-plan device pair is
justified. The committed v113 implementation supplies the persisted-contact
forward snapshot, exact reverse authority, final contact transaction and
cold/resume/pause role filtering that Plan 362 consumes. Post-execution source,
receipt and Graphify review found no executable defect and requires no gate
repeat. This is default-off event-fanout code closure, not activation, GAP-N01 or
release closure.

## Handoff

- Current state: `POST_EXECUTION_AUDIT_CLOSED / CODE_COMPLETE`; implementation
  `be897336d60f94c742fa04cb9933d90886489265`, receipt closure
  `94e6e2d74a2a7ab8da768c0b61f65975e52a8637`, current anchored Graphify
  `488091ffcb7bae21`.
- Audit outcome: no executable defect or missing successor API; Plan 361's
  focused, mutation, curated, core, SQLCipher and hygiene receipts remain
  accepted without repetition.
- Successor: Plan 362 may pin this audit-hygiene closure and execute its reviewed
  media/voice/v111 fanout contract, aggregate Android event+blob proof and
  dependency-wave full `host-all`. Activation, GAP-N01 and release remain open.
