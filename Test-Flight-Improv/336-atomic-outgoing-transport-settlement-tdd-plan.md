# 336 - Atomic Outgoing Transport Settlement

Status: implemented / plan-green / Android SQLCipher device-verified (2026-08-05)
Type: Bug
Spec: UI-14-Conn-Type/go-libp2p-transport-assessment-review.md, R1
Classification: implementation-complete
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-05 00:15 CEST | Evidence Collector | R1 assessment; message repository, DB helpers, send, receipt, retry, pause, delete, UI/feed writers, tests, gates | Confirmed stale full-row and unconditional status writers; no schema change is needed | Build the complete writer and preservation census |
| 2026-08-05 00:40 CEST | Evidence Collector | Share/debug callers, edit and delete round trips, private settlement precedent, live device matrix | Generated-ID sends and edits require narrow pre-race staging; ordinary delete tombstones need their own settlement predicate | Define the smallest coherent persistence contract |
| 2026-08-05 00:55 CEST | Planner | Gate arrays, SQLCipher device patterns, 42 focused baseline tests | One optional typed capability avoids changing 25 unrelated MessageRepository fakes; one Android SQLCipher proof closes the real persistence boundary | Write causal RED rows and literal gates |
| 2026-08-05 01:35 CEST | Independent Reviewers | Current send/edit/media/delete/retry/receipt paths, repository projections, SQLCipher and gate registration | Core settlement direction confirmed; plan fixes required for tombstone staging, strict attempt identity, media pre-staging, receipt authority wording, unsafe-legacy quarantine, and literal gate proof | Apply only source-confirmed corrections |
| 2026-08-05 01:42 CEST | Arbiter | Reviewer findings rechecked against source and preservation tests | Corrections integrated without adding schema, wire protocol, queue, coordinator, or new ACK semantics; receipt `sending` predecessor request rejected as unsafe R2 scope | Execute the reviewed Test Contract |
| 2026-08-05 01:45 CEST | Independent Re-auditor | Corrected scope, all 16 Test Contract rows, implementation order, and gates | READY; prior tombstone, edit-custody, preassigned-ID, media split-brain, fail-closed, projection, receipt, and census blockers are closed | Hand off Plan 336 for TDD execution |

## Problem And Evidence

- Behavior to improve: competing ordinary 1:1 send, inbox, receipt, retry, pause, and UI callbacks can persist stale delivery state after a stronger result has already committed.
- Impact: a recipient-confirmed message can regress to inboxed, sent, or failed; a receipt can set delivered and clear the envelope in separate writes; a stale full-row save can restore old transport/content state or a removed row.
- Confirmed root causes:
  - MessageRepositoryImpl.updateMessageStatus at lib/features/conversation/data/repositories/message_repository_impl.dart:358-368 delegates to an unconditional status update.
  - dbConditionalTransitionStatus at lib/core/database/helpers/messages_db_helpers.dart:927-972 checks only id and status; it does not atomically own transport, envelope, relay expiry, peer identity, or visibility.
  - handleDeliveryReceipt at lib/features/conversation/application/handle_delivery_receipt_use_case.dart:135-178 performs up to three status CAS calls, reloads, then performs a stale full-row save to clear wire_envelope.
  - _persistOutgoingTransportState at lib/features/conversation/application/send_chat_message_use_case.dart:2215-2256 performs a full save for ordinary terminal results.
  - retryUnackedMessages, retryFailedMessages, pause-flush custody, delete-tombstone completion, retry-upload envelope invalidation, and selected UI/feed callbacks retain equivalent stale or unconditional writers.
- Confirmed prerequisite gaps:
  - sendChatMessage generates an ID at :497, but pre-race envelope persistence at :618-651 runs only when a caller supplied messageId. The production share path at lib/features/share/application/share_batch_delivery_coordinator.dart:1306-1319 supplies no ID, so an update-only settlement would have no row.
  - lib/core/debug/android_voice_message_e2e.dart:209-222 supplies a host-minted fresh message ID without pre-inserting its parent. Treating every supplied ID as an existing row would break that production debug/device proof; treating every missing supplied ID as fresh would resurrect removed rows. Freshness therefore needs explicit caller authority plus insert-only collision refusal.
  - Media-bearing generated-ID sends normalize attachment ownership at send_chat_message_use_case.dart:507-522 but currently persist attachment rows only after terminal parent persistence at :2237-2245. Moving only the parent before transport would leave a crash-replay row without its attachment projection, while retaining the post-settlement loop could write orphan attachments after a concurrent parent removal.
  - editChatMessage reuses a previously delivered row at send_chat_message_use_case.dart:1528-1573. Existing round trips require a failed edit to retain its new text, editedAt, and envelope; the transport predecessor table must not be weakened to permit an arbitrary delivered -> failed transition.
  - An edit can start from an inboxed row. Unless staging clears the prior transport, relay expiry, and custody check, status-only recovery can later mistake the edited envelope for already-proven inbox custody.
  - ordinary delete tombstones are deliberately deleted_at != NULL and become hidden only when delivered. Their initial ordinary path currently uses insert-capable saveMessage, and rebuilt ordinary retry envelopes are not staged before transport; both need update-only tombstone staging as well as narrow final settlement.
- Existing coverage:
  - The 2026-08-05 baseline command covering receipt, live-before-inbox, verified custody loss, and private writer guards passed 42 tests.
  - dbSettleOutgoingDirectPrivateTransport at messages_db_helpers.dart:1726-1933 proves the repository already accepts a column-only, expected-envelope, predecessor-guarded pattern for protected/view-once rows.
  - verifyInboxCustody retains the separate authoritative inboxed -> sent custody-loss transition at verify_inbox_custody_use_case.dart:126-140.
- Missing coverage: no real ordinary-row transition table, no first-delivery field freeze, no atomic receipt-and-envelope-clear assertion, no generated/preassigned-ID parent-and-media staging barrier, no ordinary tombstone stage race, and no exhaustive ordinary writer guard.
- Refuted findings:
  - A universal status ranking is unnecessary and unsafe; the status set is not a total order.
  - A schema migration, route-history table, new queue/coordinator, new ACK level, or protocol hash field is not required for this persistence repair.
- Unresolved but explicitly deferred: a delivery receipt contains a message ID and peer identity, not an edit-attempt generation or envelope hash. R1 can prevent stale local writes but cannot prove whether a late same-ID receipt belongs to the pre-edit or edited envelope.
- Principal affected production files:
  - lib/core/database/helpers/messages_db_helpers.dart
  - lib/core/database/helpers/media_attachments_db_helpers.dart
  - lib/features/conversation/domain/repositories/message_repository.dart
  - lib/features/conversation/domain/repositories/media_attachment_repository.dart
  - lib/features/conversation/data/repositories/message_repository_impl.dart
  - lib/features/conversation/data/repositories/media_attachment_repository_impl.dart
  - lib/app/bootstrap/production_application_bootstrap.dart
  - lib/features/conversation/application/send_chat_message_use_case.dart
  - lib/features/conversation/application/send_voice_message_use_case.dart
  - lib/features/conversation/application/handle_delivery_receipt_use_case.dart
  - lib/features/conversation/application/retry_unacked_messages_use_case.dart
  - lib/features/conversation/application/retry_failed_messages_use_case.dart
  - lib/features/conversation/application/retry_incomplete_uploads_use_case.dart
  - lib/features/conversation/application/delete_message_use_case.dart
  - lib/core/lifecycle/handle_app_paused.dart
  - lib/features/conversation/presentation/screens/conversation_wired.dart
  - lib/features/feed/presentation/screens/feed_wired.dart
  - lib/core/debug/android_voice_message_e2e.dart
- Principal test/gate files: the named Test Contract files, scripts/run_host_test_gates.sh, scripts/run_test_gates.sh, and scripts/check_reliability_simulation_discovery.sh.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: 2bcd04d868b7429e; topology reported stale only for ios/Flutter/flutter_export_environment.sh, which is unrelated to R1.
- Query / profile: python3 graphify-arch/tdd_context.py query "Atomic ordinary outgoing message transport settlement for status transport wire_envelope relay_expires_at; updateMessageStatus updateMessageTransport saveMessage settleOutgoingDirectPrivateTransportState handleDeliveryReceipt verifyInboxCustody sendChatMessage retryUnacked messages_db_helpers.dart message_repository_impl.dart" --profile tdd --budget 700
- Independent review query / profile: python3 graphify-arch/tdd_context.py query "handleDeliveryReceipt _persistOutgoingTransportState dbConditionalTransitionStatus dbSettleOutgoingDirectPrivateTransport dbUpdateWireEnvelope in lib/features/conversation/application/handle_delivery_receipt_use_case.dart lib/features/conversation/application/send_chat_message_use_case.dart lib/core/database/helpers/messages_db_helpers.dart lib/features/conversation/data/repositories/message_repository_impl.dart" --profile review --budget 800; same fingerprint/freshness, with source expansion for media, tombstone, and preassigned-ID counterexamples.
- Anchors:
  - handleDeliveryReceipt -> lib/features/conversation/application/handle_delivery_receipt_use_case.dart:26
  - verifyInboxCustody -> lib/features/conversation/application/verify_inbox_custody_use_case.dart:19
  - MessageRepositoryImpl -> lib/features/conversation/data/repositories/message_repository_impl.dart:19
  - messages DB helpers -> lib/core/database/helpers/messages_db_helpers.dart
- Surfaced proof/gate files: handle_delivery_receipt_use_case_test.dart, messages_db_helpers_test.dart, message_repository_impl_test.dart, scripts/run_host_test_gates.sh, and scripts/run_test_gates.sh.
- Graph gaps requiring source search: the graph did not exhaust full-save/status writers, generated-ID callers, edit reuse, ordinary delete tombstones, UI/feed post-send callbacks, or device proof registration. Targeted source census supplied those facts.
- Reuse rule: these anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Add one optional typed OutgoingTransportMutationRepository capability. MessageRepositoryImpl and only tests/fakes that execute these paths implement it; do not add abstract-method churn to the 25 unrelated MessageRepository fakes.
- Add one narrow optional OutgoingOrdinaryAttemptStagingRepository capability for media-bearing attempts. It reuses MediaAttachmentRepositoryImpl's secure-key compensation, but commits the ordinary parent/envelope and exact attachment-row projection in one SQLite transaction; unrelated media fakes remain unchanged.
- Add guarded ordinary attempt staging:
  - an internally generated ID, or a caller-supplied ID carrying explicit preassigned-fresh authority, is insert-only and persists a sending row plus its exact encrypted envelope before network work; an existing-ID caller never falls through to insert;
  - an existing non-edit attempt may attach its exact envelope only from sending or failed while the complete observed peer/payload/envelope identity remains current; sent, inboxed, delivered, hidden, deleted, missing, or crossed-edit rows refuse;
  - an edit deliberately stages its new text, editedAt, sending state, and envelope under an exact predecessor/content/identity CAS and atomically clears old transport, relay expiry, and custody-check metadata;
  - media-bearing fresh, existing, and edit attempts use the combined staging capability, so the exact normalized attachment projection and parent/envelope CAS commit together or write nothing. Secure-key preparation retains its existing compensation on refusal/error. No ordinary attachment write remains after final settlement;
  - initial ordinary delete tombstones and rebuilt ordinary retry envelopes use update-only exact-snapshot staging. Both clear transport/relay/custody evidence belonging to the prior envelope and never resurrect a removed row.
- Add one ordinary non-deleted settlement operation that atomically owns status, transport, wire_envelope, relay_expires_at, and custody_checked_at.
- Add one narrow ordinary delete-tombstone settlement operation with the same proof/predecessor rules and atomic hidden_at = deleted_at derivation only when delivered.
- Add one expected-envelope column-only invalidation for ordinary media retry when key rotation makes a cached envelope unsafe, restricted to sending/failed rows, plus one separate expected-envelope guarded sent -> failed quarantine for an unsafe legacy outbound envelope.
- Route normal send/inbox completion, currently accepted peer-bound receipt application, retry-unacked, cached-envelope retry-failed, pause-flush accepted custody, ordinary delete stage/completion/retry, retry-upload invalidation, and the identified post-send UI/feed callbacks through the guarded operations.
- Reload and return the authoritative committed parent plus its current direct-owned attachment projection. A refused, preserved, missing-capability, media-stage failure, or removed-row outcome never falls back to saveMessage, an insert-capable operation, or transport/inbox work.

Settlement transition contract:

| Candidate | Allowed current statuses | Same-status behavior | Field result |
|---|---|---|---|
| delivered | sending, sent, inboxed, failed | deliberate envelope-free idempotent exception after row-shape validation | supported candidate transport or NULL for a legacy receipt; envelope, relay expiry, and custody check cleared |
| inboxed | sending, sent, failed | expected-envelope-bound mutation-free no-op | transport inbox; exact envelope retained; NULL or positive relay expiry; custody check cleared |
| sent | sending, failed | expected-envelope-bound mutation-free no-op | non-NULL supported candidate transport, including inbox for inbox-full; exact envelope retained; relay/custody metadata cleared |
| failed | sending | expected-envelope-bound mutation-free no-op | transport/relay/custody metadata cleared; exact envelope retained |

Additional invariants:

- No candidate replaces delivered. Sent or failed cannot replace inboxed. Failed -> sent and failed -> delivered remain allowed.
- Supported transport labels are exactly wifi, local, direct, reuse, relay, and inbox. Any other label, inboxed with a non-inbox transport, sent with NULL transport, failed with non-NULL transport/expiry, delivered with a non-NULL expiry, or a non-positive expiry is refused before SQL.
- A second delivered result is the only envelope-free same-status exception because delivery cleared the envelope. After validating ID, expected peer, outgoing ownership, visibility/deletion shape, and supported policy, it preserves every field and emits nothing even when supplied another route, expiry, or old envelope. Other same-status calls remain expected-envelope-bound.
- Normal live/inbox/retry settlement requires one non-empty expected envelope. A currently accepted peer-bound legacy receipt alone may settle an eligible NULL-envelope row. R1 does not claim that receipt ingress is authenticated.
- The receipt adapter preserves its current inboxed/sent/failed predecessor set and explicitly refuses sending. Live committed settlement, not the receipt adapter, exercises sending -> delivered. Receipt authentication and LAN/WebSocket authority belong to R2.
- Every DB predicate binds message ID, expected contact peer ID, outgoing ownership, visibility/deletion shape, supported policy, expected envelope where applicable, and the internal predecessor set.
- Supported normal policy exactly mirrors the existing generic envelope writer: legacy NULL/NULL, v0 ordinary, and v1 disappearing. Protected, view_once, and future/unsupported policy rows fail closed.
- Invalid candidate/transport/expiry shapes are refused before SQL. Callers never provide predecessor lists.
- Retry-upload envelope invalidation accepts only sending/failed. A refusal aborts that message's completion/send branch; it is never ignored before attachment-key persistence.
- Unsafe legacy sent -> failed quarantine is an explicitly named expected-envelope exception, not an added edge in the normal settlement table. It preserves content, editedAt, envelope, and the established ordinary transport policy.

Must preserve:

- Protected/view-once transport and delete settlement remains on its existing lifecycle lock/capability -> existing outgoing_direct_private_writer_guard_test.dart sentinels.
- Verified custody loss remains the only separate inboxed -> sent authority -> verify_inbox_custody_use_case_test.dart.
- Pause rows without an envelope and other pre-network failures retain exact sending -> failed CAS behavior; they do not masquerade as transport settlement.
- Initial composer/feed optimistic creation remains an initial write, not a settlement callback.
- MessageRepositoryImpl staging preserves the existing direct-reaction authored-target projection side effect; ordinary tombstone staging/removal preserves the matching reaction projection cleanup behavior.
- Edit retry convergence, no-ID share sends, host-minted Android voice IDs, media retry, and ordinary delete-for-everyone visibility retain their existing user behavior.
- Incoming messages, group messages, reactions, and local/system rows remain unchanged.

Hard Do not:

- Do not implement newStatus = max(current, candidate) or add a numeric rank.
- Do not insert a missing row from settlement; only the explicit fresh-attempt stage may insert.
- Do not retain any full-row fallback after a settlement/staging refusal.
- Do not make a parent/envelope transport-authoritative before its exact normalized attachment projection is durable, and do not write ordinary attachments after settlement.
- Do not force protected/view-once rows or private tombstones through the ordinary SQL path.
- Do not change ACK ranking/authentication, timeout constants, presence scheduling, inbox hedging, attachment relay eligibility, go-libp2p/Go code, WebSocket authority, or transport selection.
- Do not add a DB column, index, migration, ACK protocol, route-history model, queue, coordinator, cancellation system, or edit-generation protocol.

Deferred / accepted difference:

- Authenticated committed-ACK selection and WebSocket de-authority -> roadmap R2.
- Cross-layer deadlines -> R3; presence-independent inbox hedge -> R4; attachment envelopes over relay -> R5.
- Same-ID receipt-to-edit-attempt binding -> a separate protocol plan only if product/security evidence justifies a wire change; R1 must document that expected-envelope CAS does not solve it.
- Delivery-receipt/LAN authentication is not inferred from peer-ID correlation and remains R2 scope.
- General strengthening of verified custody-loss CAS -> outside R1; its existing exact transition and preservation tests remain authoritative.

Dependencies:

- No implementation prerequisite. R1 is the persistence foundation required before R2-R5 widen or retime callback concurrency.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-336-01 | The normal settlement table accepts only its four declared predecessor sets, including failed -> sent/delivered; ordinary same-status calls bind the expected envelope. | test/core/database/helpers/outgoing_transport_settlement_test.dart::normal settlement enforces the explicit predecessor table without a total rank | host DB integration / production schema on sqflite FFI | Compile RED: helper/outcome absent -> every accepted/refused edge and affected-row count matches the table | add inboxed -> failed, remove failed -> delivered, or bypass the envelope on inboxed -> inboxed -> red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart`; new file AUTO core-host-all and exactly once in both 1:1 arrays |
| TC-336-02 | First delivered freezes transport and all settlement fields across delivered-first and inboxed-first orders; a duplicate delivered is the deliberate envelope-free no-op and emits no new evidence. | test/core/database/helpers/outgoing_transport_settlement_test.dart::first delivered result owns fields across both callback orders | host DB integration / two independently seeded rows | Compile/behavior RED: current split/full writes permit a later result to alter fields -> first transport survives, envelope stays NULL, every later candidate changes zero columns | rewrite metadata on duplicate delivered or reuse one row for both order legs -> red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart`; same registration as TC-336-01 |
| TC-336-03 | Settlement refuses wrong peer/envelope, incoming, hidden/deleted, protected/view-once/future policy, removed rows, unsupported transports, and every invalid status/transport/expiry shape; legacy ordinary/disappearing remain eligible. | test/core/database/helpers/outgoing_transport_settlement_test.dart::normal settlement binds identity policy and exact field shapes | host DB integration / production schema | Compile RED -> every negative remains byte-identical; duplicate delivered still requires valid row shape | drop one predicate or accept inboxed/direct, sent/NULL, failed/inbox, delivered/expiry, unknown label, or non-positive expiry -> red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart`; same registration as TC-336-01 |
| TC-336-04 | Fresh staging is insert-only; existing non-edit staging accepts only exact sending/failed snapshots; crossed edits and sent/inboxed/delivered/removed rows refuse; edit staging atomically clears prior transport/relay/custody metadata. | test/core/database/helpers/outgoing_transport_settlement_test.dart::fresh existing and edit staging bind one exact attempt | host DB integration / production schema and crossed barriers | Compile RED; current envelope/full writers are broad -> only the exact attempt commits and an inboxed-origin edit cannot retain stale custody evidence | use upsert, omit content/envelope CAS, allow inboxed non-edit, or retain edit transport -> red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart`; same registration as TC-336-01 |
| TC-336-05 | Ordinary tombstone initial staging and rebuilt-envelope retry staging are update-only exact CAS operations; final settlement keeps non-delivered tombstones visible and atomically derives hidden_at = deleted_at only on delivered. | test/core/database/helpers/outgoing_transport_settlement_test.dart::ordinary tombstone staging and settlement never resurrect or cross envelopes | host DB integration / initial removal and old/new-envelope races | Compile/behavior RED: initial save can reinsert and ordinary rebuilt retry is unstaged -> removal wins, only the staged envelope can settle, deletion identity/content stay exact | replace either stage with upsert, send rebuilt envelope before stage, or update deleted_at/text during settlement -> red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart`; same registration as TC-336-01 |
| TC-336-06 | Media-key rotation invalidates only the exact sending/failed ordinary/disappearing envelope; refusal aborts attachment completion and send. | test/core/database/helpers/outgoing_transport_settlement_test.dart::media retry invalidates only an exact retryable cached envelope; test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart::invalidation refusal aborts attachment completion and send | host DB/application integration / changed-envelope and status races | Compile/behavior RED: current reload plus full save can clear a crossed edit and current flow continues -> one column changes only under the pre-upload snapshot CAS, otherwise zero attachment/save/send calls | allow sent/inboxed/delivered, use a post-upload reload as expected envelope, or continue after refusal -> corresponding proof red | `flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart` and exact retry-incomplete plain-name command; helper registration as TC-336-01, retry file already in 1:1 |
| TC-336-07 | Unsafe legacy ordinary replay uses a separate exact sent -> failed quarantine, clears stale custody metadata, and never expands the normal table or private path. | test/features/conversation/application/retry_unacked_messages_use_case_test.dart::unsafe legacy ordinary envelope is quarantined by exact identity without replay | host application / sent legacy chat and deletion rows plus crossed envelope | Behavior RED: current ordinary full save is stale -> exact row becomes failed with content/editedAt/envelope preserved and transport/relay/custody cleared; changed rows remain exact | route through normal failed settlement, omit expected envelope, retain inbox transport, or replay the envelope -> red | `flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart --plain-name 'unsafe legacy ordinary envelope is quarantined by exact identity without replay'`; existing 1:1 registration |
| TC-336-08 | Parent/envelope and the exact normalized ordinary attachment projection commit in one SQLite transaction before transport for generated, preassigned-fresh, existing, and edit attempts; refusal writes neither side, secure-key compensation runs, and no post-settlement attachment write exists. | test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart::ordinary media attempt stages parent and attachments atomically or writes nothing | host repository integration / production schema, secure-store fake, crossed attempts, crash barrier, removal race | Compile RED: combined capability absent; split staging admits envelope-A/projection-B and orphan rows -> exact parent/media pair or zero SQL rows/keys | split parent/media transactions, persist attachments after settlement, or omit secure-key compensation -> red | `flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart --plain-name 'ordinary media attempt stages parent and attachments atomically or writes nothing'`; AUTO feature-host-all |
| TC-336-09 | Repository adapters reload authoritative parent plus current direct media, emit only once for an applied mutation, preserve reaction authored-target/tombstone projection effects, and stay silent for idempotent/preserved/refused/removed outcomes. | test/features/conversation/domain/repositories/message_repository_impl_test.dart::ordinary attempt and settlement publish only authoritative applied state | host repository unit / injected closures, projection spy, broadcast stream | Compile RED: capabilities absent -> exact row/media/event/projection/outcome assertions pass | return candidate media, emit on no-op, skip a projection effect, or use saveMessage fallback -> red | `flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart --plain-name 'ordinary attempt and settlement publish only authoritative applied state'`; AUTO feature-host-all |
| TC-336-10 | sendChatMessage authorizes internal and explicitly preassigned fresh IDs but not missing existing IDs; stages before P2P/inbox, fails closed with zero transport work on missing/refused capability, returns authoritative parent/media, and cannot downgrade a concurrently delivered row. | test/features/conversation/application/send_chat_message_use_case_test.dart::attempt staging is authoritative before transport and late terminal work cannot replace delivery; test/features/conversation/application/send_voice_message_use_case_test.dart::caller-owned fresh voice ID is insert-only before transport | host application / repository spies and controllable P2P barriers | Behavior RED: generated rows are absent pre-network and final full save can replace delivered; explicit voice ID has no parent -> exact stage precedes first network call; collision/removal/refusal performs zero P2P/store calls | infer freshness from missing row, fail to propagate explicit voice authority, ignore refusal, delay stage, restore final full save, or return stale candidate -> corresponding proof red | both exact plain-name commands in Acceptance Gates; send-chat file in 1:1, both AUTO feature-host-all |
| TC-336-11 | A currently accepted peer-bound ordinary receipt uses one atomic settlement from inboxed/sent/failed, clears its envelope, handles legacy NULL-envelope/tombstones, refuses sending/foreign rows, and performs zero generic writes; no authentication claim is made. | test/features/conversation/application/handle_delivery_receipt_use_case_test.dart::peer-bound ordinary receipt uses one atomic settlement without widening authority | host application / receipt spy with ordinary, legacy, foreign, sending, and tombstone rows | Behavior RED: HEAD uses three status CAS calls plus save -> one typed call and exact no-ops | retain CAS-then-save, allow sending, omit expected peer, or label peer-ID correlation authenticated -> red/source assertion | `flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart --plain-name 'peer-bound ordinary receipt uses one atomic settlement without widening authority'`; existing 1:1 arrays |
| TC-336-12 | Retry-unacked, cached-envelope retry-failed, and accepted pause-flush custody settle through the ordinary capability; a live/receipt delivery winning during a barrier cannot be downgraded. | test/features/conversation/application/outgoing_transport_settlement_writers_test.dart::retry and pause custody writers preserve a concurrent delivered row | host application / shared authoritative fake and completion barriers | Behavior RED: current full saves can apply stale inboxed/failed candidates -> all end delivered with first fields and no fallback | restore one family writer or let missing capability fall back -> red | `flutter test test/features/conversation/application/outgoing_transport_settlement_writers_test.dart`; new file AUTO feature-host-all and exactly once in both 1:1 arrays |
| TC-336-13 | Ordinary delete stage/completion/retry, retry-upload invalidation, conversation post-result override, and feed/error fallbacks use only their exact guarded seams; envelope-less failures keep exact sending -> failed CAS. | test/features/conversation/application/outgoing_transport_settlement_writers_test.dart::media delete UI and feed writers have no stale settlement bypass | host mixed application/source contract / focused fakes and exact symbol census | Behavior/source RED: enumerated stale writers exist -> removal/crossed-envelope/delivered rows remain exact | reintroduce an enumerated saveMessage/updateMessageStatus site, ignore refusal, or route envelope-less failure through settlement -> red | `flutter test test/features/conversation/application/outgoing_transport_settlement_writers_test.dart`; same registration as TC-336-12 |
| TC-336-14 | Production bootstrap wires every new closure/capability; the writer census closes only R1; protected/private and verified custody-loss seams remain separate. | test/features/conversation/application/outgoing_transport_settlement_writers_test.dart::production wiring and writer census close only the R1 bypass set | host source contract / current lib and bootstrap | Compile/source RED -> exact wiring and bounded census pass | omit a closure, leave a bypass, or capture private/custody-loss writers -> red | `flutter test test/features/conversation/application/outgoing_transport_settlement_writers_test.dart`; same registration as TC-336-12 |
| TC-336-15 | Existing edit retry, ordinary encrypted send, tombstone visibility, private settlement, and verified custody loss retain established behavior. Generated/preassigned media and reaction projection are covered causally by TC-336-08/09/10 rather than credited here. | test/features/conversation/integration/edit_retry_round_trip_test.dart::sender and receiver text converge after a failed-then-retried edit (divergence repair); test/features/conversation/application/send_chat_message_use_case_test.dart::sends correct JSON envelope via P2P; test/features/conversation/application/handle_delivery_receipt_use_case_test.dart::sender tombstone flips 'inboxed' → 'delivered' on deletion receipt and becomes hidden; test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart::private transport settlement is column-only and concurrent intent wins; test/features/conversation/application/verify_inbox_custody_use_case_test.dart::'inbox_full' downgrades to 'sent' keeping the envelope (INBOX_CUSTODY_LOST) | host integration/unit / existing DB and fake-P2P fixtures | GREEN sentinels on HEAD -> each remains green after writer replacement | bypass edit stage, route private rows through ordinary SQL, omit tombstone hidden derivation, or absorb custody loss into normal ranking -> corresponding named sentinel red | literal commands in Acceptance Gates; existing registration |
| TC-336-16 | Real encrypted persistence rejects a wrong key, then with the correct key atomically stages one media-bearing parent/projection, commits first delivery, rejects a late weaker write, hides a delivered tombstone, and preserves all rows after close/reopen. | integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart::R1 keyed SQLCipher preserves atomic outgoing settlement across reopen | one available Android target / password-protected sqflite_sqlcipher and production schema | Boundary RED: file/helper absent -> non-empty cipher_version, wrong-key open/read failure, correct-key reopen, exact parent/media/settlement/tombstone rows | use plain SQLite, accept wrong key, split parent/media or delivery fields, or weaken CAS -> red | `flutter test -d <discovered-android-id> integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart --plain-name 'R1 keyed SQLCipher preserves atomic outgoing settlement across reopen'`; exact 1to1 discovery record |

### Test Notes

- TC-336-02 seeds separate rows for each callback order. Reusing one already-delivered row for both orders would make the second half vacuous.
- TC-336-04's exact payload CAS includes the caller-observed prior envelope null-safely. TC-336-05 rebuilt tombstone staging binds the raw prior envelope, including NULL/empty legacy values, and changes only attempt-owned columns.
- Implement receipt behavior as a dedicated typed settlement mode/operation, not as a caller-supplied predecessor list: live settlement allows sending -> delivered, while receipt settlement allows only inboxed/sent/failed -> delivered and alone may accept legacy NULL envelope. Apply the same discriminator to normal rows and tombstones.
- TC-336-08 must cross two attachment-bearing attempts that start from the same predecessor. A split implementation that commits envelope A with projection B must fail. Parent plus attachment rows share one SQLite transaction; only secure-store preparation/compensation sits outside it.
- TC-336-10 and TC-336-12 use barriers around transport/store work: commit delivered through the repository while stale work is paused, release it, then assert durable and returned/emitted state.
- TC-336-13/14 source census is a bypass lock, not a substitute for behavioral causality. Enumerate only grounded R1 functions; do not ban saveMessage/updateMessageStatus repository-wide.
- After the intentional missing-symbol compile RED, add minimal throwing/no-op stubs and capture semantic REDs before production behavior. A compile failure alone is not causal evidence.
- TC-336-16 opens the same encrypted file with a deliberately wrong key and requires failure before the successful correct-key parent/media/settlement reopen; cipher_version alone is insufficient.

## Implementation Steps

1. Snapshot git status --short and record unrelated notification/Graphify changes. Add TC-336-01 through TC-336-08 first, capture the intentional missing-symbol RED, add minimal stubs, then capture the semantic REDs before production behavior.
2. Add a small shared ordinary transport vocabulary plus optional OutgoingTransportMutationRepository and media-bearing OutgoingOrdinaryAttemptStagingRepository capabilities. Keep predecessor selection internal; expose typed stage/settlement outcomes and a dedicated receipt mode/operation, never caller-provided status lists or ranking.
3. Implement the DB helpers in messages_db_helpers.dart and media_attachments_db_helpers.dart:
   - guarded text-only fresh/existing/edit attempt staging, with explicit generated/preassigned-fresh authority at the application boundary;
   - one atomic parent-plus-attachment staging transaction for media-bearing attempts, reusing the preserving attachment merge and secure-key compensation rather than duplicating media policy;
   - update-only initial ordinary tombstone and rebuilt-envelope retry staging, clearing prior transport/relay/custody metadata;
   - atomic normal-row settlement;
   - atomic ordinary delete-tombstone settlement;
   - exact sending/failed cached-envelope invalidation;
   - exact unsafe-legacy sent -> failed quarantine outside the normal table.
   Use one transaction where update-plus-stable-outcome classification requires it. Stop-if: an implementation needs a new column/index or cannot keep insertion out of settlement; re-ground instead of widening.
4. Implement the capabilities using MessageRepositoryImpl, MediaAttachmentRepositoryImpl, and their injected DB closures. Preserve secure-key compensation, direct-reaction projection, and event semantics; reload authoritative parent plus current direct media. Do not modify base repository contracts or unrelated fakes.
5. Stage generated-ID, explicitly preassigned-fresh Android voice, existing, and edit attempts before eligible P2P or inbox work in send_chat_message_use_case.dart. Missing/refused capability and insert collision fail closed with zero transport calls. Replace ordinary final full saves/concurrent inbox writes with settlement, remove the ordinary post-settlement attachment loop, and return authoritative parent plus reloaded media.
6. Replace the normal receipt CAS-then-save sequence with one currently accepted peer-bound typed receipt settlement. It permits only inboxed/sent/failed predecessors, refuses sending, detects ordinary tombstones, and preserves private branches. Do not add or claim authentication in R1.
7. Migrate the exact census:
   - retry_unacked_messages_use_case.dart ordinary persistTransport plus the separate unsafe-legacy quarantine;
   - retry_failed_messages_use_case.dart cached-envelope settlement plus ordinary rebuilt-tombstone envelope staging and settlement;
   - handle_app_paused.dart accepted pause-flush custody only;
   - retry_incomplete_uploads_use_case.dart pre-upload-snapshot envelope invalidation, aborting the message branch on refusal;
   - delete_message_use_case.dart update-only initial ordinary tombstone stage and final settlement;
   - conversation_wired.dart post-result settlement, while envelope-less pre-network/cancel paths use exact sending CAS;
   - feed_wired.dart envelope-less catch/failure uses exact sending CAS.
   Stop-if: a caller would require a full-row fallback after refusal.
8. Add TC-336-09 through TC-336-15 and register both new headline host files exactly once in ONE_TO_ONE_TESTS and ONE_TO_ONE_HOST_TESTS. Keep initial optimistic writes, pause sending -> failed, bulk stuck recovery, verified custody loss, private lifecycle, incoming, and group paths unchanged.
9. Add and register TC-336-16 as one narrow real-SQLCipher device proof with wrong-key rejection and correct-key close/reopen. Register its discovery record exactly once. Do not add a migration, cross-device journey, relay, or iOS parity leg.
10. Run focused GREEN, exact preservation sentinels, literal registration counts, the 1:1 and feed curated lanes, affected core/feature family sweeps, analyzer, touched-file formatting, Graphify affected/refresh checks, and diff hygiene.

## Risks And Blind Spots

- Generated/preassigned-ID regression: an update-only settlement loses share/debug voice sends, while missing-row inference resurrects removals -> explicit fresh authority and insert-only TC-336-04/10.
- Media split-brain: separate parent and attachment transactions permit envelope A/projection B or orphan rows -> combined transaction and compensation TC-336-08/10.
- Edit regression: a terminal row must deliberately enter a new edit attempt; old custody metadata must not survive -> TC-336-04/10 and edit retry sentinel.
- Receipt version ambiguity: expected-envelope CAS protects local read/write races but does not cryptographically bind a receipt to one same-ID edit generation -> explicitly deferred, with no stronger claim in R1.
- Tombstone visibility/resurrection: normal predicates strand delivery, insert-capable staging revives removal, and unstaged rebuilt envelopes cannot settle -> TC-336-05/11/13/15.
- Fake-only confidence: SQL semantics close on FFI and the production encrypted plugin plus wrong-key rejection closes on TC-336-16.
- Capability absence: optional capabilities fail closed before P2P/inbox and never fall back -> TC-336-08/09/10/12.
- Lifecycle / derived-state durability: transport, relay expiry, custody check, envelope, attachment projection, and tombstone hidden_at are asserted together and after reopen -> TC-336-02/04/05/08/16.
- Sibling-surface consistency: send, receipt, retry, pause, delete, media retry, conversation, and feed are enumerated; private/incoming/group asymmetry is deliberate -> TC-336-11/12/13/14/15.
- Destructive-action side effects: row removal/hide/delete always wins over late settlement, and settlement never inserts -> TC-336-03/04/05.
- Receipt authority confusion: peer-ID correlation is not called authentication; typed receipt mode cannot use sending -> delivered or NULL-envelope live rules -> TC-336-11 and R2 deferral.
- Invariant re-verification under new transitions: exact same-state idempotence, failed -> sent/delivered, unsafe-legacy quarantine, and custody-loss exception are rechecked -> TC-336-01/02/07/15.

## Gate Cadence

- Per-plan closure:
  - focused TC-336 tests;
  - exact private, custody-loss, edit, no-ID, and tombstone sentinels;
  - ./scripts/run_host_test_gates.sh 1to1;
  - ./scripts/run_test_gates.sh feed because feed_wired.dart changes;
  - ./scripts/run_host_test_gates.sh core-host-all and feature-host-all because this plan changes both core persistence and feature application/repository surfaces;
  - one pinned Android SQLCipher proof.
- Do not run full host-all for this individual plan. Run ./scripts/run_host_test_gates.sh host-all once after the R1-R3 correctness dependency wave and once at final rollout/release closure after R5.
- Shared tests outside feature/core globs: integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart runs by exact pinned-device command and is registered exactly once in reliability discovery.

## Device/Relay Proof Profile

- Profile: single-device.
- Boundary being proven: combined parent/media staging, settlement, and tombstone fields persist through the production sqflite_sqlcipher plugin and encrypted close/reopen. Host SQLite proves policy and SQL causality but is not labeled SQLCipher.
- Live availability check: flutter devices --machine; adb devices; xcrun simctl list devices available -> observed USB Pixel 6 21071FDF600CSC, Android emulator emulator-5554, several USB iPhones, and booted iOS simulator DBE8C32E-9F19-4593-860A-B41113791D79 on 2026-08-05.
- Required setup: one available mobile target and a test-local password-protected temporary DB; current closure target is the pinned USB Pixel 6.
- Two-peer default: N/A — this proof has no peer, network, relay, transport-selection, or iOS-specific boundary.
- Closure role / PROD-CRITICAL leg: TC-336-16 is the required real-persistence proof for this plan. No wire, peer, or relay behavior changes, so a two-peer transport journey would not exercise the changed boundary.
- FLUTTER_DEVICE_ID: sufficient for this single-target row.
- Registration: add exactly one 1to1 test record for integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart in scripts/check_reliability_simulation_discovery.sh.
- Discovery command: flutter devices --machine -> 21071FDF600CSC must be listed before using the pinned command. If it is no longer available, select and pin another currently listed Android physical/emulator target; unavailable models/API bands are N/A by project policy.
- Closure command: flutter test -d 21071FDF600CSC integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart --plain-name 'R1 keyed SQLCipher preserves atomic outgoing settlement across reopen' -> exit 0, non-empty cipher_version, wrong-key open/read failure, successful correct-key reopen, applied then preserved outcomes, and reopened parent/media/settlement/tombstone rows exact.
- Deferred device work: no iOS, two-peer Android, relay, media-transfer, or network-speed proof; none of those boundaries changes in R1.

## Acceptance Gates

~~~bash
# Snapshot before execution; preserve unrelated dirty work.
git status --short

# First compile RED before production edits; expect non-zero for the missing API.
flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart \
  --plain-name 'normal settlement enforces the explicit predecessor table without a total rank'

# After minimal stubs, semantic REDs; each command must select its named test and
# fail for the documented stale/full/split-writer behavior, not a compile error.
flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'ordinary media attempt stages parent and attachments atomically or writes nothing'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'attempt staging is authoritative before transport and late terminal work cannot replace delivery'
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  --plain-name 'peer-bound ordinary receipt uses one atomic settlement without widening authority'
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  --plain-name 'invalidation refusal aborts attachment completion and send'
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --plain-name 'unsafe legacy ordinary envelope is quarantined by exact identity without replay'
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'caller-owned fresh voice ID is insert-only before transport'
flutter test test/features/conversation/application/outgoing_transport_settlement_writers_test.dart

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart
flutter test test/features/conversation/domain/repositories/message_repository_impl_test.dart
flutter test test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  --plain-name 'ordinary media attempt stages parent and attachments atomically or writes nothing'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/application/send_voice_message_use_case_test.dart \
  --plain-name 'caller-owned fresh voice ID is insert-only before transport'
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart
flutter test test/features/conversation/application/outgoing_transport_settlement_writers_test.dart
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart
flutter test test/features/conversation/application/delete_message_use_case_test.dart
flutter test test/core/lifecycle/handle_app_paused_pause_flush_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart

# Exact preservation sentinels; expect exit 0.
flutter test test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart \
  --plain-name 'private transport settlement is column-only and concurrent intent wins'
flutter test test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart \
  --plain-name 'generic envelope writer excludes private and future parents'
flutter test test/features/conversation/application/verify_inbox_custody_use_case_test.dart \
  --plain-name "'inbox_full' downgrades to 'sent' keeping the envelope (INBOX_CUSTODY_LOST)"
flutter test test/features/conversation/application/verify_inbox_custody_use_case_test.dart \
  --plain-name 'late sweep/retry persist does not downgrade a delivered row'
flutter test test/features/conversation/integration/edit_retry_round_trip_test.dart \
  --plain-name 'sender and receiver text converge after a failed-then-retried edit (divergence repair)'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'sends correct JSON envelope via P2P'
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --plain-name 'does not replay persisted v1 chat wireEnvelope when coming online'
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --plain-name 'legacy demotion preserves editedAt on the demoted row'
flutter test test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  --plain-name 'does not replay persisted v1 deletion wireEnvelope when coming online'
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  --plain-name "sender tombstone flips 'inboxed' → 'delivered' on deletion receipt and becomes hidden"
flutter test test/features/conversation/application/delivered_status_minting_sites_test.dart

# Registration; expect each host file exactly once in BOTH named arrays and the
# SQLCipher proof exactly once in discovery (not merely present in a list).
for test_path in \
  test/core/database/helpers/outgoing_transport_settlement_test.dart \
  test/features/conversation/application/outgoing_transport_settlement_writers_test.dart; do
  test "$(sed -n '/^readonly ONE_TO_ONE_TESTS=(/,/^)/p' scripts/run_test_gates.sh | \
    rg -Fxc "  \"$test_path\"")" -eq 1
  test "$(sed -n '/^readonly ONE_TO_ONE_HOST_TESTS=(/,/^)/p' scripts/run_host_test_gates.sh | \
    rg -Fxc "  \"$test_path\"")" -eq 1
done
test "$(./scripts/check_reliability_simulation_discovery.sh --records-tsv | \
  awk -F '\t' '$1 == "1to1" && $2 == "test" && $3 == "integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart" { count++ } END { print count + 0 }')" -eq 1

# Real SQLCipher boundary. Re-run discovery immediately before this command.
flutter devices --machine
adb devices
flutter test -d 21071FDF600CSC \
  integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart \
  --plain-name 'R1 keyed SQLCipher preserves atomic outgoing settlement across reopen'

# Curated and affected-family closure; expect exit 0 and zero failed tests.
./scripts/run_host_test_gates.sh 1to1
./scripts/run_test_gates.sh feed
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Hygiene; expect no new analyzer issues and no whitespace errors.
dart format --output=none --set-exit-if-changed \
  lib/core/database/helpers/messages_db_helpers.dart \
  lib/core/database/helpers/media_attachments_db_helpers.dart \
  lib/features/conversation/domain/repositories/message_repository.dart \
  lib/features/conversation/domain/repositories/media_attachment_repository.dart \
  lib/features/conversation/data/repositories/message_repository_impl.dart \
  lib/features/conversation/data/repositories/media_attachment_repository_impl.dart \
  lib/app/bootstrap/production_application_bootstrap.dart \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  lib/features/conversation/application/send_voice_message_use_case.dart \
  lib/features/conversation/application/handle_delivery_receipt_use_case.dart \
  lib/features/conversation/application/retry_unacked_messages_use_case.dart \
  lib/features/conversation/application/retry_failed_messages_use_case.dart \
  lib/features/conversation/application/retry_incomplete_uploads_use_case.dart \
  lib/features/conversation/application/delete_message_use_case.dart \
  lib/core/lifecycle/handle_app_paused.dart \
  lib/core/debug/android_voice_message_e2e.dart \
  lib/features/conversation/presentation/screens/conversation_wired.dart \
  lib/features/feed/presentation/screens/feed_wired.dart \
  test/core/database/helpers/outgoing_transport_settlement_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/domain/repositories/media_attachment_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/send_voice_message_use_case_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/outgoing_transport_settlement_writers_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/core/lifecycle/handle_app_paused_pause_flush_test.dart \
  test/features/conversation/presentation/screens/conversation_wired_test.dart \
  test/features/feed/presentation/screens/feed_wired_test.dart \
  integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart
flutter analyze
./graphify-arch/refresh_arch_graph.sh --incremental
python3 graphify-arch/tdd_context.py affected \
  lib/core/database/helpers/messages_db_helpers.dart \
  lib/core/database/helpers/media_attachments_db_helpers.dart \
  lib/features/conversation/application/send_chat_message_use_case.dart \
  --budget 600
git diff --check
~~~

## Execution Interpretation And Done Criteria

- Expected RED: TC-336-01 first fails because the API is absent; after minimal stubs, TC-336-05/06/08/10/11/12/13 must fail semantically for tombstone, invalidation, split-media, staging, receipt, and stale-writer behavior.
- Green sentinel: protected/private settlement, verified custody loss, unsafe-legacy non-replay, edit retry, generated/preassigned sends, and ordinary tombstone behavior remain green after writer replacement.
- Pre-existing dirty tree / known failure: the planning tree contains unrelated notification-recovery, iOS, Graphify, plan 333/335, gate, and test changes. Execution must snapshot and avoid attributing them to Plan 336.
- Environment blocker: none at planning time. Pixel 6 and emulator are currently available. A later unavailable version-specific target is N/A under project policy; discover and pin an available target rather than waiting for a model/API band.
- Scope drift:
  - any DB schema/index request;
  - any ACK/ranking/timeout/presence/relay/Go change;
  - any insert-on-settlement fallback;
  - any general MessageRepository fake migration;
  - any need to bind receipts to edit generations.
  Stop and re-plan rather than absorbing those changes.

- [x] Every transition and writer family has its named causal or preservation proof.
- [x] Compile RED, semantic causal RED, focused GREEN, and representative mutation re-red are recorded.
- [x] First delivered is mutation-free against every later candidate and different route metadata.
- [x] Typed receipt delivery and envelope clearing are one atomic operation, accept only inboxed/sent/failed, refuse sending, and make no authentication claim.
- [x] Generated, explicitly preassigned-fresh, existing, and edit attempts are durably staged before network work; missing existing rows and collisions never insert.
- [x] For media attempts, parent/envelope plus exact attachment rows commit in one SQLite transaction, secure-key refusal compensates, and no post-settlement attachment write remains.
- [x] Edit and ordinary tombstone staging clear transport/relay/custody evidence belonging to the prior envelope.
- [x] Initial and rebuilt ordinary tombstones are update-only, preserve deletion identity, and derive hidden state atomically on delivery.
- [x] Media invalidation binds the pre-upload envelope and aborts on refusal; unsafe legacy quarantine remains a distinct sent -> failed exception with stale custody cleared.
- [x] No in-scope refusal/missing-capability path performs saveMessage, an unconditional status fallback, P2P send, or inbox store.
- [x] Protected/view-once and verified custody-loss seams remain separate and green.
- [x] Each new host file is registered exactly once in both 1:1 arrays; the SQLCipher record appears exactly once in discovery.
- [x] Real SQLCipher rejects the wrong key and passes correct-key close/reopen on one explicitly discovered target.
- [x] Curated/family gates, analyzer, formatting, and diff hygiene pass.
- [x] Scope Contract And Guard is respected.

## Handoff

- First compile RED command: flutter test test/core/database/helpers/outgoing_transport_settlement_test.dart --plain-name 'normal settlement enforces the explicit predecessor table without a total rank'
- Preservation command: flutter test test/core/database/helpers/outgoing_direct_private_writer_guard_test.dart --plain-name 'private transport settlement is column-only and concurrent intent wins'
- Manual registration:
  - append test/core/database/helpers/outgoing_transport_settlement_test.dart and test/features/conversation/application/outgoing_transport_settlement_writers_test.dart to ONE_TO_ONE_TESTS and ONE_TO_ONE_HOST_TESTS;
  - classify integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart exactly once as family 1to1/type test.
- Migration: none; current status, transport, wire_envelope, relay_expires_at, custody_checked_at, deleted_at, and hidden_at columns are sufficient.
- Boundary closure: host policy/SQLite plus one available Android real-SQLCipher wrong-key and correct-key reopen proof; no peer, relay, Go, or iOS leg.
- Unresolved evidence: receipt-to-same-ID-edit generation binding is a known protocol limitation and not an R1 claim.

## Reviewer Findings

Initial verdict: **plan-fixes-required**. Plan classification remained implementation-ready and the core bet was **confirmed**: ordinary outgoing state needs one guarded persistence authority before later transport concurrency changes.

Applied findings:

1. **Ordinary tombstone staging was incomplete.** Initial saveMessage could resurrect a physically removed row, and a rebuilt ordinary retry envelope was sent without first replacing the stored envelope. TC-336-05 and steps 3/7 now require update-only exact-snapshot staging for both paths.
2. **Attempt staging admitted crossed or stale work.** Existing non-edit staging is now limited to exact sending/failed snapshots; edit staging binds the prior payload/envelope and clears old transport, relay expiry, and custody evidence. Generated versus preassigned-fresh authority is explicit and insert-only.
3. **Parent-only staging was unsafe for media.** Separate parent and attachment transactions permit envelope A with projection B, and post-settlement media writes can orphan rows after removal. TC-336-08 now requires one SQLite transaction for parent/envelope plus exact attachment rows, with existing secure-key compensation and no post-settlement attachment loop.
4. **Receipt authority was overstated.** Peer-ID correlation is not treated as authentication. A typed receipt mode preserves current inboxed/sent/failed predecessors, refuses sending, and alone handles eligible legacy NULL-envelope rows. R2 still owns ACK/LAN authentication and WebSocket authority.
5. **Two narrow exceptions needed explicit ownership.** Retry-upload invalidation now binds the pre-upload envelope, accepts only sending/failed, and aborts on refusal. Unsafe legacy sent -> failed is a separate quarantine that clears stale custody metadata without weakening the normal table.
6. **Idempotence, projections, and returned media needed precision.** Duplicate delivered is the only envelope-free same-status exception after row-shape validation; other no-ops remain envelope-bound. Repository tests now require authoritative parent/media reload, event silence on no-op/refusal, and reaction-projection preservation.
7. **Closure checks were presence-only.** The plan now counts both host files exactly once in both 1:1 arrays, counts the device discovery record exactly once, proves wrong-key SQLCipher failure, formats only listed touched Dart files, and separates compile RED from semantic RED.

Rejected findings / scope expansions:

- Adding sending -> delivered to receipt handling was rejected. That transition remains valid for live committed settlement, but widening receipt authority before R2 authentication would be unsafe.
- No schema/index, edit-generation protocol, native spool, new ACK level, pending-inbox protocol, queue/coordinator, discovery redesign, Go/libp2p change, or iOS/two-peer leg was justified for R1.

## Arbiter Decision

Final review verdict: **ready**. Disposition: **execute**.

- L1 evidence truth/classification: clear after correcting receipt-authentication language and grounding preassigned-ID/media/delete paths.
- L2 Test Contract causality: clear after adding semantic REDs, crossed-attempt media/tombstone races, fail-closed transport assertions, and non-vacuous duplicate-delivered rules.
- L3 bypass/scope safety: clear for the bounded R1 writer census; private, custody-loss, incoming, group, ACK, timing, and transport-selection seams remain deliberately outside it.
- L4 execution/gates: clear after exact dual-array/discovery counts, touched-file formatting, affected family gates, and wave-level rather than per-plan host-all.
- L5 boundary/state transitions: clear with a single available-Android keyed SQLCipher proof, atomic parent/media SQL staging, explicit tombstone/legacy exceptions, and no migration.

No user decision or unresolved implementation blocker remains. If execution cannot keep the combined parent/media stage atomic without a schema or broad repository redesign, the stop-if applies: pause and re-ground rather than splitting the transaction or widening R1.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-05 | causal RED + mutation | typed mutation contracts; DB/repository/application causal tests | The first core contract failed to compile while the mutation API was absent. After minimal contracts, semantic REDs exposed stale full-row settlement, split parent/media staging, crossed tombstone/media attempts, receipt split writes, and retry/pause/UI fallback writers. Representative predecessor-table, first-delivery overwrite, stage-CAS, invalidation, and stale-writer mutations re-failed their owning tests before GREEN was restored. | TC-336-01 through TC-336-14 were independently causal; failures were expected and no unrelated dirty-tree result was attributed to Plan 336. | none | implement the bounded R1 authority and run focused GREEN |
| 2026-08-05 | focused GREEN | DB helpers, repository capabilities, send/voice/receipt/retry/delete/pause/UI/feed writers and fakes | Core settlement file `10/10`; writer census/race file `4/4`; send-chat `145/145`; retry-failed `32/32`; retry-incomplete `38/38`; retry-unacked `18/18`; exact atomic-media repository proof passed; both DTR-18 placement contracts passed. Named voice, receipt, delete, pause, conversation, and feed commands also exited `0`. | Atomic attempt staging, first-delivery freeze, tombstone/quarantine exceptions, secure-key compensation, authoritative reloads, and fail-closed capability refusal are green. | none | run preservation and registered lanes |
| 2026-08-05 | preservation | private writer guard, custody-loss verification, edit retry, v1 non-replay/demotion, receipt tombstone, delivered-minting sentinels | Every literal preservation command in Acceptance Gates exited `0`; complete retry/send suites additionally exercised removal, crossed-envelope, protected/view-once, private, reaction-projection, and deletion races. | Private settlement and verified custody loss remain separate; legacy unsafe envelopes are quarantined without replay; edit retry and tombstone visibility remain intact. | none | run curated and affected-family closure |
| 2026-08-05 | curated + family gates | registered 1:1/feed/core/feature inventories | `1to1` passed all `106` host commands; `feed` passed `315/315`; `core-host-all --batch-flutter --concurrency 4 --reporter failures-only` passed `396` Flutter paths / `3141` tests plus both contract manifests; `feature-host-all` with the same four-way batching passed `836` paths / `8811` tests with one pre-existing declared skip. Final test-only causal additions after the core sweep passed in the exact core file. | All production changes were covered by the required family sweeps; full `host-all` remains wave/final-owned under project cadence. | none | run the real persistence proof and hygiene |
| 2026-08-05 | Android SQLCipher boundary | `integration_test/outgoing_transport_settlement_sqlcipher_proof_test.dart` | Immediately refreshed discovery found USB Pixel 6 `21071FDF600CSC` and emulator `emulator-5554`; the proof pinned to the Pixel passed `1/1` after build/install. It asserted non-empty `cipher_version`, wrong-key open/read rejection, correct-key close/reopen, atomic parent/media staging, first-delivery preservation, and exact reopened tombstone state. | TC-336-16 closes the changed encrypted-persistence boundary on an explicitly available physical Android target; no peer/iOS leg is applicable. | none | run static and registration closure |
| 2026-08-05 16:04 CEST | closure | touched Dart files, dual gate arrays, discovery inventory, Graphify architecture graph, plan/index | Both new host files count exactly once in `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`; the SQLCipher record counts exactly once. `flutter analyze` reported no issues in `98.7s`; the listed touched-file format checks were clean (final 12-file recheck: `0 changed`); `git diff --check` passed; the single incremental Graphify refresh and affected query succeeded with current compact-query fingerprint `31ab0813ec8f56ad`. | Plan-green with no schema/index, Go/relay, ACK/ranking, queue, protocol, iOS, or two-peer expansion. Unrelated notification/iOS/Graphify dirty-tree work remains preserved. | none | complete |
