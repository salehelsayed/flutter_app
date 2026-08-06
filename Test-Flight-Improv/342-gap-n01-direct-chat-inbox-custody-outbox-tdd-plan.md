# 342 - GAP-N01 Direct-Text Recipient-Inbox Custody Outbox

Status: execution-ready after `$tdd-review` (2026-08-06)
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md`; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01
Classification: implementation-ready, bounded first slice of GAP-N01; this plan does not close GAP-N01 as a whole and is not independently release-eligible before GAP-N02/N03
Closure tier: device

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-06 | Evidence Collector | PRD v1.2; coverage/gaps report; direct send/retry/receipt code; relay direct/group inbox code and tests; v107 schema and migration registry | Confirmed that an authenticated direct ACK can cancel an unstarted inbox hedge, leaving no durable sender-owned relay-custody obligation. | Bound the first causal slice and identify preservation surfaces. |
| 2026-08-06 | Planner | Message repository mutation APIs, lifecycle retrier/resume wiring, receiver identity checks, account migration, test registries, live device matrix | Chose a separate v108 exact-envelope outbox for newly authored ordinary direct text; retain fast live delivery without waiting for relay completion. | Draft causal tests, migration proof, and gate contract. |
| 2026-08-06 | Reviewer | Relay message-ID dedupe, ordinary/private media retry, v108 downgrade/account-transfer blast radius, registration, concurrency, fresh-versus-existing attempts, discovery output, and N02/N03 interaction | First verdict was **not-ready**; revised-plan verdict was **plan-fixes-required**. Immutable text closed the blocker, while fresh-only eligibility, executable version/discovery census, and a dependency-wave release guard still required tightening. | Apply the remaining bounded deltas in place and rerun all five lenses. |
| 2026-08-06 | Arbiter | Final scope, Test Contract, device profile, release boundary, gate cadence, and all reviewer deltas | Final verdict **ready** for implementation, not standalone release; immutable fresh direct text is sufficient for the first slice, with media/iOS and broader GAP-N01 event coverage explicitly deferred. | Execute TC-342-01 through TC-342-11 in order; release only with the GAP-N01/N02/N03 dependency wave. |

## Problem And Evidence

- Behavior to improve: a newly authored direct text can be acknowledged over an authenticated live stream while the recipient is becoming inactive, yet the sender can return without a durable relay-inbox item or provider wake remaining available to recover the event.
- Impact: direct reachability is incorrectly allowed to erase notification recovery ownership. A suspend or crash after receipt but before presentation can leave neither a recoverable inbox event nor a push wake, which is the principal persistence-only failure described by GAP-N01.
- Confirmed root cause/current gap: `_SendScopedInboxHedge` is scheduled for connected sends at `lib/features/conversation/application/send_chat_message_use_case.dart:965-974`, but authenticated live-success branches call `cancelIfNotStarted` at `:1017-1018`, `:1103-1105`, and `:1294-1297`. The only crash-replay bytes live on the message row, while delivered settlement clears `wire_envelope` at `lib/features/conversation/application/send_chat_message_use_case.dart:2367-2385` and `lib/core/database/helpers/messages_db_helpers.dart:1626-1641,1668-1674`.
- Existing coverage: `send_chat_message_use_case_test.dart::R4 authenticated libp2p commitment cancels every scheduled unstarted hedge` locks the behavior that must change for eligible text. `::R4 started hedge completion after live ACK cannot downgrade ordinary or private delivery` already locks monotonic late custody. The relay direct handler persists before initiating push at `go-relay-server/inbox.go:1405-1486`, but `go-relay-server/inbox_test.go::TestHandleInboxStream_StoreTriggersPushSendAfterPersistence` is skipped.
- Missing coverage: no status-independent sender outbox survives a live delivery receipt; no atomic message-plus-custody stage exists; no lifecycle drain owns delivered rows; the direct receiver authenticates sender identity but does not compare the v2 envelope's outer `id` with decrypted `payload.id` at `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:186-304`.
- Refuted finding: reusing `messages.wire_envelope` is not sufficient because delivered settlement deliberately clears it and retry selection reads only sent rows with envelopes at `lib/core/database/helpers/messages_db_helpers.dart:719-755`. Replacing an outstanding outbox ciphertext under the same message ID is also unsafe: relay dedupe extracts the top-level `id` at `go-relay-server/inbox.go:1258-1305` and memory/Redis backends dedupe recipient plus ID at `go-relay-server/backend_memory.go:121-150` and `go-relay-server/backend_redis.go:289-330`, without comparing ciphertext.
- Resolved review finding: ordinary media is not safe to include in this slice. Re-upload can mint a new key/nonce and must invalidate the old envelope at `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart:247-253,470-511`; protected/view-once media has additional lifecycle authority. Both are deferred rather than inventing a content-hash or replacement protocol.
- Unresolved findings: none block this direct-text slice. Full GAP-N01 still requires ordinary/private media, reactions, group ordering/truthfulness, every recipient device, and remaining reconciliation triggers.
- Affected production, test, and gate files: `app_database_version.dart`, `production_migration_registry.dart`, new v108 migration/helper/model, `message_repository.dart`, `message_repository_impl.dart`, direct send/retry/drain/lifecycle files, direct receive handler, account-migration version consumers/tests, relay tests, the two 1:1 test arrays, and SQLCipher proof discovery.

## PRD And Gap Traceability

| Plan obligation | PRD/GAP-N01 connection | This plan's disposition |
|---|---|---|
| Persist exact encrypted custody before any live or relay attempt | Executive responsibility 1; G-01/G-04; target architecture 1 and 3; A-02/A-03; AC-04 | Implement for newly authored ordinary direct text to the current target peer. |
| A live ACK cannot cancel custody ownership | PRD §5.1; G-06; A-26; AC-05/AC-12 | Implement with a status-independent sender outbox; keep sender latency asynchronous. |
| Relay stores before generating a wake, and duplicate replay does not generate a second wake | Target architecture 3; A-24; AC-04/AC-10 | Prove the existing relay behavior with repaired Go tests; no relay production rewrite. |
| Launch/resume/reconnect/network-restored/periodic work retries retained obligations | G-04/G-06; A-03/A-26; AC-10/AC-12 | Implement deterministic lifecycle ownership and one available-Android persistence proof. |
| One authenticated event identity | Core invariant 2; target architecture 1; A-01 | Add direct v2 outer-ID versus authenticated-inner-ID parity; do not add a new hash protocol. |
| Text, media, reactions, direct, group, and every recipient device | GAP-N01 required target and acceptance paragraph | **Still open after Plan 342.** This plan is the first slice, not a GAP-N01 closure claim. |

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `b70d73652093c0bc`; `stale:ios/Flutter/flutter_export_environment.sh` (unrelated generated iOS environment file; selected app-owned anchors are current-source verified).
- Planning query / profile: `python3 graphify-arch/tdd_context.py query "Plan 342 GAP-N01 universal recipient-device inbox custody _SendScopedInboxHedge cancelIfNotStarted settleAcceptedInboxCustody send_chat_message_use_case.dart group pubsub inbox store-before-push gates" --profile tdd --budget 700`.
- Review refinement / profile: `python3 graphify-arch/tdd_context.py query "settleAcceptedInboxCustody _SendScopedInboxHedge cancelIfNotStarted dbStageOutgoingOrdinaryAttemptWithinTransaction dbCommitOutgoingDirectPrivateWireEnvelope PendingMessageRetrier" --profile review --budget 800`.
- Anchors: `settleAcceptedInboxCustody` and `_SendScopedInboxHedge` -> `send_chat_message_use_case.dart`; outgoing transaction mutation -> `message_repository_impl.dart` and `messages_db_helpers.dart`; lifecycle ownership -> `pending_message_retrier.dart` and `handle_app_resumed.dart`.
- Surfaced proof/gate files: `send_chat_message_use_case_test.dart`, `pending_message_retrier_test.dart`, `full_migration_chain_test.dart`, `go-relay-server/inbox_test.go`, `scripts/run_test_gates.sh`, and `scripts/run_host_test_gates.sh`.
- Graph gaps requiring source search: relay backend ID-only dedupe, media-key invalidation, exact v107 account-migration pins, and live device availability were verified directly from source/commands.
- Reuse rule: these anchors may be handed to execution, but line numbers must be refreshed after RED tests land and all conclusions remain current-source or command backed.

## Scope Contract And Guard

In scope:

- Eligible event: literally `OutgoingOrdinaryAttemptKind.fresh`—a newly authored ordinary direct `actionSend` text with no attachments and no protected/view-once policy. This includes generated IDs and caller-supplied IDs only when `preassignedMessageIdIsFresh == true`, plus quote metadata, forwarded marker, or ordinary disappearing policy already represented inside the encrypted payload. `OutgoingOrdinaryAttemptKind.existing` is never eligible to mint custody. The current `targetPeerId` is the recipient-device/peer key for this slice.
- DB v108 table `direct_inbox_custody_outbox`, with exactly: `recipient_peer_id`, `message_id`, immutable 32-character `incarnation_id`, exact encrypted `wire_envelope`, `retry_count`, nullable `last_attempt_at`, nullable `last_error_code`, `created_at`, and `updated_at`. Require nonblank peer/message/envelope/timestamps, nonnegative retry count, and `last_error_code` in `store_failed|store_rejected_full|store_threw|local_completion_failed`. Primary key is `(recipient_peer_id, message_id)`; `incarnation_id` is unique; `idx_direct_inbox_custody_outbox_fair_load` orders `(last_attempt_at, created_at, recipient_peer_id, message_id)` so NULL/unattempted rows lead. No cleartext, title/body/preview, media path/key, push copy, foreign key, or cascade is permitted.
- Constants: `kDirectInboxCustodyOutboxCapacity = 512` and `kDirectInboxCustodyOutboxMaxLoadBatch = 50`, matching the existing notification-outbox bounds in `direct_notification_display_outbox_db_helpers.dart:8-9`. At capacity, a new eligible send fails before either the message or outbox row commits and before any transport begins; no live-only fallback and no eviction are allowed.
- Atomic stage: add a narrow text-custody companion capability beside the existing optional ordinary mutation capability, implemented by `MessageRepositoryImpl`. One SQLCipher transaction inserts/updates the exact message attempt and stages its outbox row. Exact replay of the same scoped immutable bytes is idempotent; different bytes or authority for an occupied `(recipient_peer_id, message_id)` fail closed and never replace the row.
- Attempt immutability: once staged, `wire_envelope`, recipient, message ID, and incarnation never change. A v108 failed text with pending custody uses the exact drain path and does not fall through to re-encryption when that store fails; the row remains retryable. Existing failed/unacked attempts never mint or replace custody. Because v108 intentionally has empty backfill, a historical v107 existing attempt with no row retains its current retry behavior. Edit/delete or another send attempt against the same message cannot mutate the pending initial-event row.
- Drain outcomes: `stored` and `duplicate` are accepted remote custody. Completion runs one local transaction that preserves a stronger `delivered`/terminal message state, otherwise projects `inboxed`, records relay expiry when returned, and deletes only the exact incarnation. If the local message was already deleted, accepted remote custody still deletes the exact outbox row without recreating the message. `failed`, `rejectedFull`, thrown calls, or local completion failure retain the row and record bounded attempt metadata.
- Drain fairness: load at most 50, prioritizing never-attempted rows and then oldest `last_attempt_at`; handle each row independently so a poison row cannot stop later rows. Do not add a timer or exponential-backoff subsystem: existing startup, reconnect, network-restored, periodic, and resume triggers bound cadence. Concurrent owners are intentionally safe at-least-once work; relay duplicate suppression plus exact-incarnation completion converges them.
- Live latency: unknown presence starts the exact staged copy immediately; known/connected routes retain the existing bounded delayed hedge. Authenticated live success may return without awaiting the relay, but it must neither delete the row nor cancel its scheduled attempt.
- Receiver identity: for v2 direct chat, reject before persistence/receipt when top-level envelope `id` differs from authenticated decrypted `payload.id`. Legacy v1 behavior remains unchanged.

Must preserve:

- Stronger live delivery cannot be downgraded by late custody -> `send_chat_message_use_case_test.dart::R4 started hedge completion after live ACK cannot downgrade ordinary or private delivery`.
- Ordinary media, protected/view-once media, edit, and delete paths retain their current staging/rebuild/cancellation behavior -> new TC-342-03 exclusion subtests plus existing private/media suites.
- Direct reactions retain their already-durable unknown-presence copy behavior -> `send_reaction_use_case_test.dart::FDC-18-02 unknown-presence reaction whose live send WINS still deposits one concurrent inbox copy` and `remove_reaction_use_case_test.dart::FDC-18-R2 unknown-presence reaction REMOVE whose live send WINS still deposits one concurrent inbox copy`.
- Group send retains exact-envelope retry ownership and truthful live-only result on inbox failure -> `go-mknoon/node/group_inbox_test.go::{TestSendGroupMessageReliableStoresExactEnvelopeForActiveRecipients,TestSendGroupMessageReliableReturnsLiveOnlyWhenInboxStoreFails,TestGIRD004GroupInboxStoreRetryKeepsStableMessageID}` and `send_group_message_use_case_test.dart::GI-006 inbox failure leaves message sent with retry payload and no durable mark`.
- Direct relay store-at-cap eviction compatibility, seven-day remote retention, and delivery receipts remain unchanged; Plan 342 adds sender obligation storage but does not redefine the relay protocol.

Hard `Do not`:

- Do not replace ciphertext for a pending `(recipient_peer_id, message_id)`, add a ciphertext/content hash to the wire protocol, or teach the relay to compare ciphertext in this slice.
- Do not put custody on `messages.wire_envelope`, key outbox lifecycle from message status, or delete an outbox row on live ACK/delivery receipt alone.
- Do not include media/voice, protected/view-once content, edit/delete tombstones, reactions, group events, first-class mentions, or linked-device fanout in the eligible predicate.
- Do not classify an existing failed/unacked `actionSend` as fresh merely because it has text and no media; only the already-derived `OutgoingOrdinaryAttemptKind.fresh` may stage a new row.
- Do not rewrite group send production code, relay storage production code, notification display ledgers, FCM/APNs payloads, or native iOS/Android background services.
- Do not add WorkManager, a native scheduler, a global retry timer, a generic cross-event ledger, or an app-wide singleton solely for this plan.
- Do not ship or activate Plan 342 independently while the current rich provider payload and competing-alert behavior remain. Intermediate implementation builds are non-release artifacts until GAP-N02 and GAP-N03 close in the same dependency wave.

Deferred / accepted difference:

- Ordinary media/voice and protected/view-once media -> later GAP-N01 slice after defining immutable event generation versus key-rotation replacement; `retry_incomplete_uploads_use_case.dart:470-511` proves an old envelope can become undecryptable.
- Direct reactions and edit/delete events -> later GAP-N01 event expansion; current reaction unknown-presence behavior remains a preservation sentinel, not a universal-custody claim.
- Group inbox-first/truthful durability change -> later GAP-N01 group slice; current group persistent retry owner is preserved.
- Account-level sibling-device enumeration/fanout -> later GAP-N01 identity/device slice; Plan 342 covers the current direct target peer only and makes no cross-device clearing claim.
- iPhone/iOS simulator/device acceptance -> GAP-N12/WP-07 consolidated iOS closure, per the adopted sequencing in the gaps report §9.1. This plan touches no iOS production code and requires no iOS harness work.

Dependencies:

- `storeInInboxDetailed` must continue distinguishing `stored`, `duplicate`, `rejectedFull`, and `failed`; `stored|duplicate` is the only completion set.
- DB v108 is a one-way local schema floor. Same-version account transfer remains the only accepted transfer contract.
- Relay ID-only dedupe is a relied-on at-least-once boundary and is locked by TC-342-09; changing that protocol requires a separate reviewed plan.
- Release dependency: GAP-N02 must replace rich provider-visible direct payloads and GAP-N03 must establish outcome/alert arbitration before Plan 342 can ship. If an intermediate build must be distributed externally, stop for a product-owned activation/kill-switch decision; this plan does not invent a flag for builds that are not shipped.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-342-01 | DB v108 creates the exact identifier-plus-ciphertext table and indexes on fresh create and v107 upgrade; upgrade is idempotent with empty historical backfill; opening a v108 file as v107 fails without mutation. | `test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart::TC-342-01 v108 installs immutable direct-text custody and refuses downgrade without mutation` | Host / production create+upgrade callbacks with FFI SQLite | HEAD compile RED: v108 migration is absent -> GREEN: exact columns/checks/PK/unique/fair-load indexes, no forbidden columns/FKs, run twice stable, zero backfill rows, v107 downgrade throws through production `onDatabaseVersionChangeError`, and v108 reopen data/schema remain intact. | Omit upgrade registry entry, add cascade/cleartext, backfill history, or permit downgrade -> TC-342-01 red. | `flutter test test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart`; add exactly once to both 1:1 arrays and AUTO `core-host-all`. |
| TC-342-02 | Message attempt and immutable custody stage are one transaction; exact replay is idempotent; authority conflict/capacity/SQL error is all-or-nothing. Completion and failure mutations use exact incarnation. | `test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart::TC-342-02 atomic immutable direct-text custody mutations fail closed` | Host / real FFI DB, production repository/helper, capacity 2 fixture | HEAD compile RED -> GREEN: fresh and preassigned text commit two rows together; same bytes do not duplicate; changed bytes reject; cap leaves neither new message nor outbox; completion preserves delivered, projects weaker states to inboxed, handles an already-deleted message without resurrection, and only exact incarnation deletes; injected failure rolls back. | Split writes, use replace/upsert, delete by message ID only, evict at cap, require/recreate a deleted message, or downgrade delivered -> TC-342-02 red. | `flutter test test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart`; add exactly once to both 1:1 arrays and AUTO `core-host-all`. |
| TC-342-03 | Every fresh eligible direct-text route stages before transport and authenticated live success never cancels or deletes custody; unknown presence starts immediately and known routes keep the existing delayed budget. Excluded event kinds and existing attempts do not acquire or mutate this row. | `test/features/conversation/application/send_chat_message_use_case_test.dart::{TC-342-03a fresh direct text stages immutable custody before every transport,TC-342-03b live ACK leaves scheduled text custody owned,TC-342-03c media private edit delete and existing attempts remain outside new custody}` | Host / fake clock, repository transaction spy, direct/LAN/relay/unknown route matrix; generated ID, `preassignedMessageIdIsFresh`, and existing-attempt cells | HEAD RED: current R4 cancels the scheduled store and no outbox stage exists -> GREEN: fresh stage precedes all sends, returned live result remains fast/delivered, delayed store still runs or durable row survives; an existing failed/unacked actionSend stages zero rows and cannot replace a seeded row; exclusions preserve current paths. | Restore any `cancelIfNotStarted` call for fresh eligible text, await the delayed store before return, stage after live send, derive eligibility directly from action/media instead of `attemptKind`, or broaden the predicate -> a TC-342-03 cell red. | Exact `flutter test ... --plain-name` commands; existing file is already in both 1:1 arrays and AUTO `feature-host-all`. |
| TC-342-04 | A drain replays exact bytes; stored/duplicate completes, failed/full/throw retains; remote acceptance followed by local completion failure converges on duplicate; one poison row does not block the remaining batch and repeated batches rotate fairly. Failed-message retry with a pending row uses this exact path and never falls through to re-encryption. | `test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart::TC-342-04a exact at-least-once drain converges without poison starvation`; `test/features/conversation/application/retry_failed_messages_use_case_test.dart::TC-342-04b pending direct-text custody never falls through to re-encrypt` | Host / fake detailed inbox store plus real in-memory custody repository; retry bridge spy | HEAD compile RED -> GREEN outcome table covers all four statuses, exact bytes, retry metadata, max 50, never-attempted/oldest-attempt order, per-row fault isolation, accepted-then-local-throw retention, duplicate replay, exact deletion, and zero encrypt/live calls after a retained-row failure. | Re-encrypt, treat full/failed as success, delete before local transaction, stop on first throw, order only by creation, or enter full-send fallback -> a TC-342-04 cell red. | New drain file exactly once in both 1:1 arrays and AUTO `feature-host-all`; existing retry file remains in `ONE_TO_ONE_TESTS` and AUTO `feature-host-all`. |
| TC-342-05 | Delivered/user-terminal message truth remains stronger than inbox custody; failed/sending/sent can advance to inboxed; delivery receipt never removes the independent obligation. | `test/features/conversation/application/send_chat_message_use_case_test.dart::TC-342-05 accepted custody projects monotonic status but only exact outbox completion retires ownership`; existing R4 late-custody test | Host / blocked settlement barriers and real repository helper | HEAD RED: delivery clears the only envelope/obligation -> GREEN: direct ACK then receipt leaves the outbox until remote acceptance; late accepted custody leaves delivered unchanged and atomically retires only its incarnation. | Couple row deletion to `wire_envelope == null`, receipt, or status; overwrite delivered with inboxed -> TC-342-05 red. | Focused existing file; already registered in both 1:1 arrays. |
| TC-342-06 | Startup-already-online, reconnect, network-restored, periodic retry, and app resume invoke custody drain before failed/unacked rebuild; overlapping calls are safe; one drain failure does not suppress later retry families. | `test/core/services/pending_message_retrier_direct_inbox_custody_test.dart::TC-342-06 retrier lifecycle drains direct custody before message rebuild without cross-family starvation`; `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart::TC-342-06 resume drains direct text custody before failed and unacked rebuild` | Host / fake clock, callback order recorder, throwing drain | HEAD compile/order RED -> GREEN: all named triggers call the optional production-wired drain first, periodic cadence remains existing, thrown drain is isolated, and failed/unacked/upload ordering otherwise stays unchanged. | Place drain after rebuild, omit a trigger, start a new timer, or let a throw abort retry families -> TC-342-06 red. | New retrier file exactly once in both 1:1 arrays; existing resume file already registered; AUTO core/feature sweeps. |
| TC-342-07 | Production repository/bootstrap and every app-owned `sendChatMessage` path that can author eligible text have the atomic capability; capability/schema/capacity absence fails before transport, while unrelated fakes and excluded event kinds need no new implementation. | `test/features/conversation/application/send_chat_message_use_case_test.dart::TC-342-07 eligible text fails closed without atomic custody capability`; `test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart::TC-342-07 production wires direct custody drain and capable message repository` | Host / source census plus capability-negative fake | HEAD RED -> GREEN: negative fake produces `sendFailed`, zero network calls, and zero partial message; production repository implements the capability and bootstrap supplies the drain to its retry/resume owners. | Make capability optional/fail-open in production, add a second DB owner, or miss a production call path -> TC-342-07 red. | Exact focused tests; existing files are AUTO family-gated; no blanket fake-interface churn. |
| TC-342-08 | Direct v2 outer envelope `id` must equal authenticated decrypted `payload.id`; mismatch persists nothing and emits no delivery receipt. | `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart::TC-342-08 encrypted direct chat rejects outer and authenticated inner message ID mismatch` | Host / real envelope parser and deterministic decrypt bridge fake | HEAD RED: differing IDs are accepted under inner identity -> GREEN: exact parity accepts; mismatch returns unauthorized before contact/message mutation, notification projection, or receipt. | Remove the comparison or compare only sender IDs -> TC-342-08 red. | `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart --plain-name 'TC-342-08 encrypted direct chat rejects outer and authenticated inner message ID mismatch'`; existing file is in both 1:1 arrays. |
| TC-342-09 | Relay direct store persists before first push and an exact duplicate returns duplicate without a second push. | `go-relay-server/inbox_test.go::{TestRelayNotificationClosure_DirectStoreTriggersPushAfterPersistence,TestRelayNotificationClosure_DirectDuplicateDoesNotRefanoutPush}` | Host native / real stream handler, memory backend, injected recording push sender with bounded async wait | HEAD RED: the existing store-before-push test is skipped and duplicate coverage does not observe push -> GREEN: sender callback sees the row already stored; first request pushes once; duplicate retains one row and push count one. | Move push before store, push on duplicate, or dedupe on ciphertext instead of recipient+ID -> TC-342-09 red. | `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -run '^TestRelayNotificationClosure_Direct' -count=1)`; the `TestRelayNotificationClosure_` prefix enters the existing curated 1:1/group relay gate and the full-relay all gate; no production edit. |
| TC-342-10 | v108 remains compatible with exact same-version account transfer and all current-version consumers; a v107 manifest is rejected before target mutation; every literal `107` is classified as a current consumer to update or an intentional historical/non-version fixture to retain. | `test/features/account_migration/application/migration_database_schema_inventory_test.dart::TC-342-10a v108 inventory contains direct custody`; `test/features/account_migration/application/migration_database_active_importer_test.dart::TC-342-10b same-v108 transfer preserves pending custody and v107 rejection leaves target unchanged`; `test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart::TC-342-10c literal v107 inventory contains no stale current-version consumer` | Host / real staged DB importer, production manifest compatibility, and source census with explicit path/pattern allowlist | HEAD RED: current version is 107, schema lacks table, and the 54-hit baseline contains stale current-version/registry-tail/current-open assertions -> GREEN: v108 export/import round-trips exact pending row; v107 manifest reports unsupported DB version and target sentinel remains; current consumers assert 108; only migration-107 definitions, explicit v107 setup/downgrade/rejection, registry-order assertions, and unrelated RGB/Xcode literals remain allowlisted. | Omit table from inventory/import, allow cross-version import, mutate target before compatibility, restore any current/manifest/registry-tail/current-open assertion to 107, or silently widen the allowlist -> a TC-342-10 cell red. | Exact account-migration and v108 migration files; AUTO core/feature gates; baseline and post-change literal inventories plus focused device preservation commands in Acceptance Gates. |
| TC-342-11 | Real SQLCipher proves v107-to-v108 upgrade, encryption, restart durability, delivery-independent custody, accepted-then-local-failure replay, one-way downgrade, and previous v107 authority preservation on an available Android target. | `integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart::TC-342-11 Android SQLCipher v107-to-v108 direct-text custody survives delivery and crash replay` | Single device / production SQLCipher plugin and migration callbacks on Pixel 6 `21071FDF600CSC` | Device HEAD compile RED -> GREEN: wrong key rejected; PRAGMA exact; empty backfill; stage; mark delivered with row retained; close/reopen; simulate stored plus local throw; reopen/duplicate/complete; run migration twice; prior v107 notification data intact; v107 downgrade fails and v108 reopen is unchanged. | Use FFI/plain SQLite, clear on delivery, complete before local transaction, omit wrong-key/downgrade/reopen, or lose v107 rows -> TC-342-11 red. | Add one discovery case to `scripts/check_reliability_simulation_discovery.sh`; run `flutter test integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart -d 21071FDF600CSC`; manual device-proof classification, not a host array. |

### Test Notes

- TC-342-02: use a test-only capacity override of 2; production constant remains 512. Assert stored envelope bytes exactly, never by decrypting or logging their contents.
- TC-342-03: replace the obsolete text expectation in the existing R4 cancellation test; do not simply delete it. Keep explicit exclusion cells showing media/private/edit/delete still follow their pre-plan behavior.
- TC-342-03/04: the eligibility discriminator is the already-derived `attemptKind`, not a second approximation of message shape. Generated and explicitly fresh preassigned IDs stage; `existing` never stages. A pending v108 row diverts failed retry to exact drain, while an unbackfilled historical v107 row follows the existing cached-envelope/full-send decision tree.
- TC-342-04: concurrency does not need a global lock. Two drains may issue the same exact store; relay returns `stored` then `duplicate`, and only one exact-incarnation completion deletes the local row. Test this rather than adding singleton ownership. A per-message retry may join/reuse the same function, but it must never build replacement ciphertext while the row exists.
- TC-342-06: add an optional drain callback to `PendingMessageRetrier` so unrelated constructor tests remain source-compatible. TC-342-07 makes omission illegal in production composition.
- TC-342-09: the push recorder must wait with an existing bounded test primitive; do not use a sleep. The callback itself asserts the stored row is observable, discriminating store-before-push from mere eventual success.
- TC-342-10: the observed baseline has 54 literal `107` hits. Current consumers to update are in `app_database_version.dart`; `runtime_root_inventory_test.dart`; `full_migration_chain_test.dart`; migration tests 100 through 107 where they assert the current/tail version; account-migration schema/importer tests; and the direct-notification, group-exit-diagnostics, group-notification-display, group-exit-intents, and group-self-removed SQLCipher proofs where they assert a current open. Retain and explicitly allow migration registry entry/name 107, `entry.version == 107` ordering checks, explicit v107 create/open/downgrade/rejection fixtures, `runProductionOnCreate(..., 107)` historical fixtures, the unrelated RGB `107`, and the Xcode-version negative sentinel. TC-342-10c must fail on an unclassified new literal rather than accepting a broad directory or regex exemption.
- TC-342-11: this is a storage/plugin boundary proof, not a two-peer delivery claim. Do not add an emulator, iPhone, APNs/FCM, notification UI, or manual taps.

## Implementation Steps

1. Snapshot `git status --short` and record unrelated dirty paths. Re-run the two compact Graphify queries if source topology changed, then save/classify the complete `rg -n '\b107\b' lib test integration_test --glob '*.dart'` inventory and census all production `sendChatMessage`/`MessageRepositoryImpl` construction paths. Stop-if: another change already introduces a status-independent exact-envelope custody owner; re-review for stale overlap rather than creating a second owner.
2. Add TC-342-01 through TC-342-10 before production edits and capture the documented causal REDs. Replace the obsolete direct-text R4 cancellation expectation with TC-342-03b, retaining explicit exclusion sentinels. Repair/rename only the two relay tests under the existing `TestRelayNotificationClosure_` gate prefix; do not edit relay production code unless the repaired tests disprove the current source claim, in which case stop and replan.
3. Add DB v108 in `lib/core/database/app_database_version.dart`, `lib/core/database/migrations/108_direct_inbox_custody_outbox.dart`, and both ordered lists in `lib/core/database/production_migration_registry.dart`. Update the version comment. Implement exact schema, fresh-create/upgrade/run-twice/empty-backfill checks, and the v108-file-to-v107 failure test using production `onDatabaseVersionChangeError`.
4. Add `DirectInboxCustodyOutboxEntry` and the narrow optional `OutgoingDirectTextInboxCustodyRepository` beside the existing ordinary transport capability. Implement it only where required: production `MessageRepositoryImpl`, shared send-test fake(s), and the dedicated in-memory fixture. Its stage method must reuse the existing SQL write transaction to commit the message attempt and immutable outbox row together. Stop-if: implementation needs a second database connection, nested transaction, cleartext, or message-status trigger.
5. In `send_chat_message_use_case.dart`, derive eligibility from the existing `attemptKind == OutgoingOrdinaryAttemptKind.fresh` plus the text/no-media/no-protected-policy constraints after envelope construction and before transport. Route only those attempts through atomic message-plus-outbox stage. Make unknown-presence and delayed hedges send the staged exact bytes; live success must not cancel or complete the row. Capability/schema/capacity failures return `sendFailed` before any network call. Existing attempts, including historical v107 retry, must not stage; leave all other excluded branches on their current code.
6. Add `drain_direct_inbox_custody_outbox_use_case.dart`. Load the fair bounded batch; call detailed inbox store outside any DB transaction; complete `stored|duplicate` with one exact-incarnation local transaction; record all other outcomes independently and continue. Add the narrow per-message entrypoint used by `retry_failed_messages_use_case.dart`: when a pending direct-text row exists, attempt exact drain and return without the existing full-send/re-encrypt fallback regardless of store outcome. Emit identifier-prefix/status metrics only—never envelope bytes, recipient IDs in full, or plaintext. Do not add a timer, service locator, singleton, or bespoke backoff.
7. Call the drain from the existing `PendingMessageRetrier` startup-already-online, reconnect/network-restored, and periodic work before failed/unacked rebuilding. Call it in `handle_app_resumed.dart` after stuck-send/upload recovery but before `retryFailedMessages` and `retryUnackedMessages`, preserving current upload ordering and fault isolation. Wire the production closure once in `production_application_bootstrap.dart`/`application_root.dart`; keep constructor defaults test-compatible and lock production presence with TC-342-07.
8. Add the v2 outer/inner ID comparison in `handle_incoming_chat_message_use_case.dart` immediately after authenticated decrypt/parse and before contact lookup, persistence, notification projection, or delivery receipt. Leave v1 behavior unchanged.
9. Update account-migration and every classified current-version/tail/current-open expectation to 108. Add the outbox inventory and same-v108 pending-row transfer proof; retain exact-version compatibility and add a v107 rejection/unchanged-target discriminator. Add TC-342-10c's narrow allowlist and run all mechanically affected SQLCipher current-open proofs on the pinned Android; retain literals that deliberately construct or inspect historical v107 and the two unrelated non-DB values.
10. Register every new host test exactly once in both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS` as applicable. Register TC-342-11 once in `scripts/check_reliability_simulation_discovery.sh`; verify the actual `--records-tsv` tuple is exactly `1to1`, `test`, and the proof path, then run the existing discovery shell contract. Run registration-count and classified-v107-census checks before the curated/family gates.
11. Run focused GREEN, representative mutation re-reds, direct/group/reaction/media preservation sentinels, the curated `1to1` gate, justified `core-host-all` and `feature-host-all`, analyzer, and diff hygiene. Then rediscover live devices and run TC-342-11 plus every SQLCipher proof whose current-version assertion changed on the pinned available Android. Mark Plan 342 implementation-complete only; do not release it before the N01/N02/N03 wave closes. Do no iOS work in this plan.

## Risks And Blind Spots

- Same-ID replacement can silently preserve the wrong ciphertext at the relay -> immutable rows and conflict refusal in TC-342-02/04; media is excluded.
- Remote acceptance can race a local transaction failure -> accepted-then-throw/duplicate convergence in TC-342-04 and real reopen in TC-342-11.
- Delivered settlement can erase the only replay bytes -> separate status-independent table and TC-342-05/11.
- Multiple lifecycle owners can duplicate work -> expected at-least-once relay dedupe plus exact-incarnation local CAS in TC-342-04/09; no correctness-dependent singleton.
- A poison row can monopolize a fixed batch -> never-attempted/oldest-attempt fairness and per-row fault isolation in TC-342-04.
- Schema-capacity failure can degrade to live-only delivery -> atomic fail-closed tests in TC-342-02/07.
- DB version bumps can break downgrade/account migration or leave stale assertions -> TC-342-01/10/11 and the literal census command.
- Universalizing direct-text store today also universalizes the current rich-push/competing-alert path -> Plan 342 is implementation-only until GAP-N02 removes provider-visible event material and GAP-N03 supplies outcome/alert arbitration; the dependency-wave release guard is a done criterion.
- Lifecycle / derived-state durability: TC-342-05/06/11 cover direct ACK, receipt, restart, resume, reconnect, and retry ordering.
- Sibling-surface consistency: TC-342-03 exclusions and TC-342 preservation commands cover media/private/edit/delete; group and reactions remain unchanged and openly deferred.
- Destructive-action side effects: no eviction, cascade, historical backfill, or deletion on delivery; only exact remote acceptance can retire an exact custody incarnation.
- Invariant re-verification under new transitions: TC-342-04/05 prove retry and late completion preserve stronger delivery truth; TC-342-08 authenticates one direct message identity.
- Remaining product blind spot: the PRD's every-event/every-device invariant is not achieved by this plan. The GAP-N01 row must remain open and its later slices must not cite Plan 342 as media, reaction, group, or linked-device proof.

## Gate Cadence

- Per-plan closure: focused TC-342 tests, exact preservation sentinels, exact relay Go tests, `./scripts/run_test_gates.sh 1to1`, and the justified `core-host-all` plus `feature-host-all` sweeps because this plan changes shared DB/lifecycle and conversation feature production surfaces. Run TC-342-11 and every existing SQLCipher proof whose current-version assertion changed on the available physical Android.
- Do not run full `host-all` for this individual plan. Run `./scripts/run_host_test_gates.sh host-all` once after the GAP-N01/N02/N03 dependency wave is complete, and once at final rollout/release closure.
- Shared tests outside feature/core globs: run the exact relay Go command, account-migration tests, `test/unit/runtime_root_inventory_test.dart`, discovery contract/record check, and Android SQLCipher commands directly. The device proofs are discovery-registered but deliberately absent from host arrays.

## Acceptance Gates

```bash
# Baseline and exact current-version/callsite census before edits. Classify every
# literal 107 hit using TC-342-10's narrow retained categories; do not bulk-replace.
git status --short
rg -n '\b107\b' lib test integration_test --glob '*.dart'
rg -n "sendChatMessage\(|MessageRepositoryImpl\(" lib

# First causal REDs; expect non-zero for the named missing contracts.
flutter test test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart \
  --plain-name 'TC-342-01 v108 installs immutable direct-text custody and refuses downgrade without mutation'
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'TC-342-03b live ACK leaves scheduled text custody owned'
flutter test test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  --plain-name 'TC-342-04a exact at-least-once drain converges without poison starvation'

# Focused GREEN; expect exit 0 and zero failed tests.
flutter test \
  test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart
flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  --plain-name 'TC-342-04b pending direct-text custody never falls through to re-encrypt'
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  --plain-name 'TC-342-08 encrypted direct chat rejects outer and authenticated inner message ID mismatch'
flutter test \
  test/features/account_migration/application/migration_database_schema_inventory_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart
flutter test test/unit/runtime_root_inventory_test.dart

# Relay boundary: existing production must store before first push and suppress duplicate push.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... \
  -run '^TestRelayNotificationClosure_Direct' \
  -count=1)

# Exact preservation sentinels.
flutter test test/features/conversation/application/send_chat_message_use_case_test.dart \
  --plain-name 'R4 started hedge completion after live ACK cannot downgrade ordinary or private delivery'
flutter test test/features/conversation/application/send_reaction_use_case_test.dart \
  --plain-name 'FDC-18-02 unknown-presence reaction whose live send WINS still deposits one concurrent inbox copy'
flutter test test/features/conversation/application/remove_reaction_use_case_test.dart \
  --plain-name 'FDC-18-R2 unknown-presence reaction REMOVE whose live send WINS still deposits one concurrent inbox copy'
flutter test test/features/groups/application/send_group_message_use_case_test.dart \
  --plain-name 'GI-006 inbox failure leaves message sent with retry payload and no durable mark'
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^(TestSendGroupMessageReliableStoresExactEnvelopeForActiveRecipients|TestSendGroupMessageReliableReturnsLiveOnlyWhenInboxStoreFails|TestGIRD004GroupInboxStoreRetryKeepsStableMessageID)$' \
  -count=1)
flutter test test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart

# Registration: every new host test appears exactly once in each curated 1:1 array.
for plan_test in \
  test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart \
  test/core/database/helpers/direct_inbox_custody_outbox_db_helpers_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/features/conversation/application/drain_direct_inbox_custody_outbox_use_case_test.dart; do
  test "$(sed -n '/readonly ONE_TO_ONE_TESTS=(/,/^)/p' scripts/run_test_gates.sh | grep -Fxc "  \"$plan_test\"")" -eq 1
  test "$(sed -n '/readonly ONE_TO_ONE_HOST_TESTS=(/,/^)/p' scripts/run_host_test_gates.sh | grep -Fxc "  \"$plan_test\"")" -eq 1
done
test "$(./scripts/check_reliability_simulation_discovery.sh --records-tsv | \
  awk -F '\t' '$1 == "1to1" && $2 == "test" && \
    $3 == "integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart" { count++ } \
    END { print count + 0 }')" -eq 1
bash scripts/test/reliability_simulation_discovery_contract_test.sh

# After edits, the automated source allowlist must reject every stale or
# unclassified literal 107 while retaining deliberate historical fixtures.
flutter test test/core/database/migrations/108_direct_inbox_custody_outbox_test.dart \
  --plain-name 'TC-342-10c literal v107 inventory contains no stale current-version consumer'
rg -n '\b107\b' lib test integration_test --glob '*.dart'

# Per-plan curated and justified family gates; no full host-all here.
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all
./scripts/run_host_test_gates.sh feature-host-all

# Availability-bounded Android SQLCipher closure; pin the discovered target.
flutter devices --machine
adb devices -l
xcrun simctl list devices available
flutter test integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart \
  -d 21071FDF600CSC
for version_proof in \
  integration_test/direct_notification_durability_sqlcipher_proof_test.dart \
  integration_test/group_exit_release_diagnostics_sqlcipher_proof_test.dart \
  integration_test/group_notification_display_outbox_sqlcipher_proof_test.dart \
  integration_test/group_exit_intents_sqlcipher_proof_test.dart \
  integration_test/group_self_removed_marker_sqlcipher_proof_test.dart; do
  flutter test "$version_proof" -d 21071FDF600CSC
done

# Hygiene.
flutter analyze
git diff --check
```

## Device/Relay Proof Profile

- Profile: single-device.
- Boundary being proven: production SQLCipher v107-to-v108 migration, wrong-key protection, real close/reopen durability, local transaction rollback after simulated remote acceptance, and one-way downgrade refusal. Host FFI SQLite cannot prove the plugin/encryption boundary.
- Live availability check: `flutter devices --machine`, `adb devices -l`, and `xcrun simctl list devices available` on 2026-08-06 found USB Pixel 6 `21071FDF600CSC` (Android API 36), Android emulator `emulator-5554` (API 37), and available Apple targets. Only the USB Android is required here.
- Required setup: one pinned USB Android `21071FDF600CSC`; production SQLCipher plugin; test-local temporary identity DB/key; fake detailed relay outcome at the repository boundary; no Firebase credential, remote relay, second peer, UI navigation, or manual tap.
- Two-peer default: N/A — TC-342-11 makes no delivery/presentation or Android/iOS parity claim; adding a second endpoint would not strengthen the storage boundary.
- Closure role: required Plan 342 boundary evidence, but only partial GAP-N01 evidence.
- `FLUTTER_DEVICE_ID`: sufficient for this single-device proof; use the explicit `-d 21071FDF600CSC` command.
- Registration: one `1to1` test record in `scripts/check_reliability_simulation_discovery.sh`; `_proof_test.dart` remains classified as a manual device-proof suite and is not inserted into host arrays.
- Discovery command: `flutter devices --machine` -> target `21071FDF600CSC` must be listed immediately before execution.
- Closure command: `flutter test integration_test/direct_inbox_custody_outbox_sqlcipher_proof_test.dart -d 21071FDF600CSC` -> all TC-342-11 checkpoints pass; then the five existing current-version SQLCipher proofs listed in Acceptance Gates pass on the same target after their classified 108 expectation updates.
- Deferred device work: no iOS and no two-peer campaign. Non-iOS two-peer work in later gaps defaults to USB Android `21071FDF600CSC` plus Android emulator `emulator-5554`; Apple-owned acceptance is consolidated under GAP-N12/WP-07.

## Execution Interpretation And Done Criteria

- Expected RED: TC-342-01 cannot compile because v108 is absent; TC-342-03b observes canceled/no custody after live ACK; TC-342-04 cannot compile because no outbox drain exists; TC-342-08 accepts a mismatched outer/inner ID.
- Green sentinel: fresh eligible text is atomically staged before transport, live ACK does not retire custody, remote accepted/duplicate converges without downgrading delivery, existing attempts never mint/replace custody, and excluded sibling paths pass unchanged.
- Pre-existing dirty tree / known failure: the worktree was already broadly dirty, including other plans, notification work, graph outputs, and harness changes. Execution must record the baseline and touch only Plan 342's explicit files; unrelated failures remain baseline, not permission to overwrite user work.
- Environment blocker: none at planning time. If Pixel `21071FDF600CSC` is absent when executing, rediscover and pin any available Android device; an unavailable version-specific target is `N/A (target unavailable by project policy)`, not grounds to add iOS.
- Scope drift: any need for mutable ciphertext, media key replacement, relay protocol/hash changes, linked-device enumeration, group production changes, native scheduler, or iOS code stops execution for a new reviewed plan.

- [ ] Every in-scope behavior has a named causal test/proof; all broader GAP-N01 claims remain explicitly open.
- [ ] Causal RED, focused GREEN, and representative mutation re-red are recorded.
- [ ] Atomic failure/capacity/conflict, status monotonicity, concurrency, retry fairness, and poison-row isolation pass.
- [ ] Relay store-before-push and duplicate-no-second-push tests pass without relay production changes, or execution stops for replan.
- [ ] All four new host files are registered exactly once in both 1:1 arrays, and the SQLCipher proof has one discovery record.
- [ ] The discovery `--records-tsv` output contains exactly one `1to1/test` tuple for TC-342-11, and its shell contract passes.
- [ ] v108 fresh/upgrade/run-twice/downgrade/account-transfer contracts, classified literal-107 census, the new Android SQLCipher proof, and all affected current-version Android SQLCipher sentinels pass.
- [ ] Curated 1:1, justified core/feature family gates, analyzer, and diff hygiene pass with semantic outcomes.
- [ ] No iOS harness/device work, media/reaction/group expansion, or generic notification ledger is introduced.
- [ ] Closure is recorded as implementation-complete and **not independently release-eligible**; release remains blocked until the GAP-N01/N02/N03 dependency wave closes, or an explicit product-owned activation strategy is separately approved.

## Handoff

- First causal RED command: `flutter test test/features/conversation/application/send_chat_message_use_case_test.dart --plain-name 'TC-342-03b live ACK leaves scheduled text custody owned'`.
- Preservation command: the exact R4 late-custody, FDC-18 reaction, GI-006 group, native group, and incomplete-upload commands in Acceptance Gates.
- Manual registration: four new host tests exactly once in both curated 1:1 arrays; one SQLCipher proof case in `scripts/check_reliability_simulation_discovery.sh`; no new Sims scenario or manual registry row.
- Migration: DB v108, exact host migration/account-transfer/census tests, real Android SQLCipher migration/reopen/downgrade proof, and all five affected current-version SQLCipher sentinels.
- Boundary closure: host plus one physical Android storage proof. This does not prove receiver delivery, notification presentation, or iOS parity.
- Unresolved evidence: the remaining GAP-N01 media/reaction/group/every-device slices and GAP-N12 iOS closure; none block executing this bounded text slice.

## Reviewer Findings

First verdict: **not-ready**. The revised-plan re-audit verdict was **plan-fixes-required**. The following source-backed corrections were applied before the final verdict:

1. **[blocker, resolved] Same-ID ciphertext replacement was unsafe.** Relay memory/Redis dedupe uses recipient plus extracted top-level message ID and does not compare ciphertext. A remote old-envelope acceptance racing a local replacement could make the replacement receive `duplicate` and retire while the relay still held the old bytes. The plan now makes custody bytes immutable, treats changed bytes as authority conflict, and narrows eligibility to text. Ordinary/private media replacement is deferred because re-upload explicitly invalidates key-stale envelopes.
2. **[plan-fix, resolved] DB v108 needed a one-way version-floor contract.** TC-342-01 and TC-342-11 now open a v108 file with a v107 production opener, require `onDatabaseVersionChangeError`, and prove the v108 schema/data remain intact after refusal. The version comment and current-version census are explicit implementation work.
3. **[plan-fix, resolved] Account migration and version consumers were incomplete.** TC-342-10 now proves schema inventory, exact same-v108 pending-custody transfer, v107-manifest rejection before target mutation, and updates all assertions that mean current version while retaining deliberate v107 fixture literals.
4. **[plan-fix, resolved] Retry ownership risked overengineering.** The revised plan names capacity 512 and batch 50, specifies fair ordering and poison isolation, and relies on existing lifecycle cadence plus relay dedupe/exact local CAS. It expressly forbids a new global singleton, timer, WorkManager job, or custom backoff service.
5. **[plan-fix, resolved] Registration and boundary preservation were too narrow.** Acceptance now counts every new host file exactly once in both curated 1:1 arrays, adds one discovery record for the device proof, reruns the v107 SQLCipher authority proof, and follows repository wave-level rather than per-plan full-`host-all` cadence.
6. **[note, applied] Event identity needed one cheap authenticated parity check.** TC-342-08 compares outer v2 ID to decrypted inner ID before any side effect; a universal content-hash protocol remains out of scope.
7. **[plan-fix, resolved] Existing retry could bypass fresh-only intent.** `retry_failed_messages_use_case.dart:656-680` re-enters `sendChatMessage` as an existing action-send after exact cached-envelope failure. Eligibility is now literally `attemptKind == fresh`, a pending v108 row diverts to exact drain without re-encryption, existing attempts cannot mint/replace rows, and empty-backfill historical v107 retries retain current behavior.
8. **[plan-fix, resolved] Version/discovery checks could pass with stale consumers or a vacuous case label.** TC-342-10c now classifies the complete 54-hit literal-v107 baseline with a narrow allowlist, all mechanically affected current-open SQLCipher proofs run on Android, and discovery is asserted from the exact `--records-tsv` `1to1/test/path` tuple plus its shell contract.
9. **[plan-fix, resolved] Standalone release would widen current rich-push and competing-alert behavior.** Every newly stored direct chat reaches the existing provider path in `go-relay-server/inbox.go:1440-1480`; the gaps report keeps provider privacy and outcome arbitration open under GAP-N02/N03. Plan 342 is therefore implementation-ready but not independently release-eligible; no flag is added unless an intermediate external build creates a product-owned activation decision.

Final `$tdd-review` verification: **ready**; core bet **confirmed**; disposition **execute for implementation**, with no remaining blocker or plan-fix and release still gated on the GAP-N01/N02/N03 wave.

Rejected scope expansions: a generic event ledger, ciphertext hash/version protocol, reaction outbox, group rewrite, linked-device protocol, native Android scheduler, iOS worker, and per-gap iPhone harness. None is required to make this direct-text slice causally correct.

## Arbiter Decision

- Final verdict: **ready**.
- Plan classification: implementation-ready bounded first slice, not standalone release; core bet **confirmed**.
- Disposition: **execute**.
- Coherence: one DB authority owns immutable sender custody; remote acceptance is the only retirement authority; message delivery remains a monotonic projection; duplicate work is expected and safely convergent.
- Sufficiency: causal tests cover fresh-versus-existing eligibility, atomic staging, routing, failure/capacity, immutable replay, crash windows, lifecycle triggers, authenticated identity, schema/account/version-census boundaries, relay ordering, discovery registration, and the real SQLCipher plugin boundary.
- Overengineering guard: text-only eligibility avoids unresolved media-generation semantics, and the plan reuses existing repository transactions, detailed inbox outcomes, lifecycle triggers, relay dedupe, and gate infrastructure.
- Five-lens result after applied fixes: L1 evidence truth clear; L2 causality clear with fresh/existing discriminators; L3 bypass/scope clear; L4 commands/registration clear; L5 boundary/reversibility clear for implementation. Full GAP-N01, N02/N03 release dependencies, and iOS closure remain open by contract.
- Evergreen blind-spot sweep: B-2/B-4/B-9 re-audit hits are resolved by fresh-only retry tests, exact census/discovery output, and the release-wave guard. Lifecycle durability, destructive cleanup, state monotonicity, migration/downgrade, concurrency, registration, and device-boundary classes are covered. No user decision blocks implementation; distributing an intermediate build would create a separate release decision.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| - | not started | - | - | reviewed plan is execution-ready | awaiting implementation authorization | snapshot dirty tree and run first causal RED |
