# 349 - GAP-N01 Ordinary Direct Text Mutation ACK-or-Expiry Custody

Status: **IMPLEMENTED / DEFAULT-OFF CODE-CLOSED / PLAN-GREEN / HOST GATES GREEN / NOT STANDALONE RELEASE-ELIGIBLE** (2026-08-09)
Type: Modification
Spec: `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2.md` A-01/A-02/A-03/A-24/A-26; gap inventory `UI-23-notification/Mknoon_Private_Reliable_Notifications_PRD_v1.2_Codebase_Coverage_and_Gaps.md` GAP-N01/WP-01
Classification: implemented, bounded ordinary direct-text mutation adoption of the existing v109/ACK-or-expiry owner
Closure tier: host, including production relay/native protocol contracts and Android binding build; no mobile-runtime claim

## Planning Progress

| Time | Role | Files inspected | Decision/blocker | Next action |
|---|---|---|---|---|
| 2026-08-09 | Evidence Collector | PRD and GAP-N01 mechanism checkpoint; Plan 348 commit/evidence; edit/delete authoring, retry, receipt, receiver, v108/v109/v111, lifecycle/bootstrap, relay/node/bridge, gates | Confirmed the next uncovered ordinary-direct boundary: current EDIT and delete-for-everyone can replace the only mutable parent envelope and use legacy/evictable inbox storage, so neither owns an independent ACK-or-expiry obligation. | Bound the smallest shared event-owner adoption and identify preservation seams. |
| 2026-08-09 | Planner | DB v109 migration/helper/repository; ordinary mutation DB body; deletion payload; strict relay parser/dedupe; failed/unacked retry; delivery receipts | Reuse physical v109 with raw authenticated UUIDs, safe atomic collision refusal and one fair classifier-driven drain. Add no schema. A narrow event-aware receipt field is required because a delayed message-ID-only receipt can otherwise settle a newer mutation. | Write the causal Test Contract, run the sufficiency check, then invoke `$tdd-review`. |
| 2026-08-09 | Independent Reviewers | Current plan plus outgoing authoring/stage/completion, retry, receiver streams/DB upserts, receipt settlement, relay protected/shadow paths, native/bridge allowlists and gate scripts | Confirmed the core bet but found and closed raw-ID prefix overengineering, pre-349 retry ambiguity, destructive refusal/egress/ambiguity gaps, delayed-receipt settlement, and concurrent initial/edit/delete receiver bypasses. | Re-run the complete counterexample and gate-boundary sweep on the revised plan. |
| 2026-08-09 | Review Arbiter | Revised Test Contract, scope guard, literal commands, registration/device cadence and all independent findings | Verdict `ready`; core bet `confirmed`; disposition `execute`. No unresolved blocker or user-owned decision remains. | Append `EXECUTION_READY`; do not implement in this planning/review session. |

## Problem And Evidence

- Behavior to improve: a newly authored ordinary direct-text edit or delete-for-everyone must retain its own exact encrypted recipient-inbox obligation until protected relay ACK-or-expiry custody accepts it, even after live success, node stop, restart, retry, or a later mutation of the same message.
- Impact: today a successful direct leg or legacy inbox result can leave the only retry bytes in the mutable `messages.wire_envelope`. A later edit/delete overwrites those bytes, and a crash or background transition can permanently lose an earlier authored mutation. A delayed receipt for the initial message can also load the current mutation row and falsely clear that newer envelope.
- Confirmed edit gap: `sendChatMessage` gives an edit a distinct authenticated `eventId`, but `ownsDirectTextInboxCustody` is restricted to a fresh `actionSend` at `lib/features/conversation/application/send_chat_message_use_case.dart:869-892`. The edit therefore uses generic parent-only staging at `:1380-1460`, and node-not-running exits before authorship for this lane at `:987-1010`.
- Confirmed delete gap: `deleteMessageForEveryone` returns before authoring when the node is stopped (`lib/features/conversation/application/delete_message_use_case.dart:292-300`), replaces the parent with one exact tombstone envelope (`:320-447`), then uses legacy `storeInInbox` (`:670-725`). Its v2 payload has no event identity (`lib/features/conversation/domain/models/message_deletion_payload.dart:9-72`).
- Confirmed reusable owner: DB v109 has only `(recipient_peer_id, event_id)`, opaque exact `wire_envelope`, retry/CAS metadata, no foreign key and no event-kind constraint (`lib/core/database/migrations/109_direct_reaction_inbox_custody_outbox.dart:24-53`). Its fair load and exact failure/completion helpers are already envelope-opaque (`lib/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers.dart:206-309`). A new table, column, index or DB v112 is not justified.
- Confirmed atomic seam: `dbStageOutgoingOrdinaryAttemptWithinTransaction` already owns the exact parent CAS and can be composed with a v109 insert (`lib/core/database/helpers/messages_db_helpers.dart:1486-1650`). The new wrapper must additionally require version-0 ordinary policy and zero direct attachments; the existing broad "ordinary" predicate also permits disappearing messages.
- Confirmed drain gap: the one v109 lifecycle drain currently sends every row as `direct_reaction_v109` (`lib/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case.dart:12-68`). Separate filtered drains over the shared `LIMIT 50` head could starve each other; one fair loader must classify each exact envelope.
- Confirmed retry bypass: failed edit/delete and unacked-message paths recognize v108 but otherwise replay/rebuild through legacy inbox storage (`lib/features/conversation/application/retry_failed_messages_use_case.dart:447-495,789-840,961-1167`; `lib/features/conversation/application/retry_unacked_messages_use_case.dart:92-122,272-337`).
- Confirmed receipt hazard: receipts carry only `messageIds` (`lib/features/conversation/application/send_delivery_receipt_use_case.dart:83-110`). `handleDeliveryReceipt` then loads the current parent and passes that current row's envelope to settlement (`lib/features/conversation/application/handle_delivery_receipt_use_case.dart:44-65,144-174`). Thus a delayed receipt for initial event M can incorrectly settle current edit E or deletion D. The smallest fix is an additive optional `(messageId,eventId)` correlation plus a fail-closed legacy guard, not a receipt ledger or new status model.
- Confirmed receive race: chat and deletion are dispatched to independent streams (`lib/core/services/incoming_message_router.dart:174-181`), and async chat callbacks are not awaited against each other. Their handlers read current state and later perform a generic upsert (`lib/features/conversation/application/handle_incoming_chat_message_use_case.dart:369-500,566-689`; `lib/features/conversation/application/handle_incoming_message_deletion_use_case.dart:139-219`). A deletion followed by a stale edit, legacy mutation or delayed initial save can resurrect/regress the target. One no-schema transactional ordinary-text conditional-apply helper is required; a listener lock would miss direct staged-replay call sites.
- Existing coverage: TC-342 proves edit outer/inner event parity, the separate `edit-event-id:` relay namespace, and that edits remain outside v108. Plan 343 proves v109 reaction atomicity/fairness/CAS and lifecycle composition. Plan 344 proves the default-off Redis protected lane, mixed-version store/retrieve/ACK and exact `ack_or_expiry_v1` proof. Existing delete, retry, receiver ordering and receipt suites preserve current semantics.
- Missing coverage: no atomic message-mutation-plus-v109 stage, deletion event parity, unified reaction/mutation drain, mutation-aware protected relay kind, retry bypass guard, concurrent receiver conditional apply, or receipt/event correlation exists.
- Refuted findings: DB v112/new table is unnecessary because v109 already has the required event lifetime and exact bytes. A local subtype-prefix layer is also unnecessary: all newly authored event IDs are UUIDs, the existing v109 primary key safely refuses a forced same-recipient collision atomically, and arbitrary historical reaction IDs mean a prefix could not create an absolute namespace anyway. Keep the authenticated raw event ID locally and the existing type namespaces only at relay deduplication.
- Unresolved findings: N/A - every required production boundary has a current source seam. Production activation, historical rows and the remaining N01 modalities are explicit deferred work, not evidence uncertainty in this slice.
- Affected production, test and gate files: existing v109 contract/helper/entry/repository/drain; message repository and ordinary DB helper; chat edit/delete authoring and receiver payloads; failed/unacked retry and lifecycle/bootstrap; delivery receipt sender/handler/listeners; Dart P2P custody kind; relay protected parser/dedupe; Go node/bridge allowlists; existing focused tests, `1to1`, core/feature family gates and Android binding artifact.

## Graph Grounding Snapshot

- Graph fingerprint / freshness: `1a115b6263d71ff0`; current after committed Plan 348 baseline `d06072d805eda7e549cd2b5d878f306297dba130`.
- Query / profile: `python3 graphify-arch/tdd_context.py query "Plan 349 ordinary direct text EDIT and delete-for-everyone event-scoped ACK-or-expiry custody; sendChatMessage MessagePayload.actionEdit resolvedEventId; deleteMessageForEveryone MessageDeletionPayload; direct_reaction_inbox_custody_outbox v109 fair drain; extractDirectInboxDedupeKey; retryFailedMessage; handleIncomingChatMessage; handleIncomingMessageDeletion" --profile tdd --budget 700`.
- Anchors: `MessageDeletionPayload` -> `lib/features/conversation/domain/models/message_deletion_payload.dart`; `handleIncomingChatMessage` -> `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`; `extractDirectInboxDedupeKey()` -> `go-relay-server/inbox.go`.
- Surfaced proof/gate files: deletion payload/receiver tests, direct edit/dedupe relay tests, v109 helper/drain tests, and curated 1:1 ownership.
- Graph gaps requiring source search: native/bridge custody allowlists, exact retry ordering, receipt settlement, account transfer and gate registration were verified directly in current source.
- Reuse rule: anchors may be handed to review/execution; all conclusions still require current-source or command evidence.

## Scope Contract And Guard

In scope:

- Bind execution to Plan 348 commit `d06072d805eda7e549cd2b5d878f306297dba130`. Preserve the pre-existing unrelated changes in the PRD, coverage report, `info.plist`, and `macos/Runner.xcodeproj/project.pbxproj`.
- Adopt custody only for newly authored ordinary, outgoing, one-to-one, text-only EDIT and delete-for-everyone events. Requalify version-0 ordinary policy, no `direct_media_custody_intent_id`, and no direct attachment rows inside the atomic transaction.
- Keep DB version 111 and physical table/index `direct_reaction_inbox_custody_outbox` unchanged. Share its existing capacity 512, batch cap 50, global FIFO, error codes, account-transfer behavior and exact-envelope CAS. Exact replay is checked before capacity.
- Store the authenticated raw event UUID as the v109 `event_id` for reactions, edits and deletions. Validate it against the exact outer envelope before staging. An exact existing key+bytes replay is idempotent; a forced same-recipient cross-kind/key collision with different bytes refuses the new mutation without altering the older row or parent. Relay dedupe keys remain type-namespaced.
- Add one optional message-owned mutation-custody capability beside `MessageRepository`. Its atomic stage calls `dbStageOutgoingOrdinaryAttemptWithinTransaction`, then inserts the exact v109 row in the same `dbWriteTransaction`. Parent drift, event-key collision with changed bytes, shared-capacity refusal, invalid policy/media, or insert failure changes neither half. Exact existing bytes are idempotent without replaying an older parent projection.
- For fresh edits, preserve the existing target message ID and immutable event UUID, re-read the authoritative repository parent rather than trusting the UI snapshot, and make newly authored `editedAt` strictly greater than that parent's parseable prior `editedAt` using `max(now, prior + 1 microsecond)`. Malformed or overflowing prior edit time fails closed before staging; exact retries retain their original timestamp and bytes.
- Give newly authored v2 deletions one UUID `eventId` in the encrypted inner payload and the same clear outer field. Keep the target `messageId` encrypted; do not add it to the outer deletion envelope. Both-absent legacy v2 deletions remain readable. Partial, blank or mismatched identities are rejected before contact lookup, persistence, cleanup or receipt.
- Move the eligible mutation node-running decision after encryption and atomic stage. A stopped node performs no network but leaves the exact event durable. When the node is running, schedule exactly one non-throwing protected mutation-custody hedge alongside the existing live path; no live/connected fast path may skip, cancel or delete the retained owner. Do not serialize live delivery behind relay completion or require the hedge future to begin before returning an authenticated live ACK. Missing capability, invalid shape or stage refusal fails closed before network and never falls back to generic staging.
- Add exactly one custody wire kind, `direct_mutation_v109`, to Dart, Go node/bridge and relay allowlists. Preserve `store_custody_v1`, `ack_or_expiry_v1`, the existing admission flag, capacity, expiry, metrics and command/export signatures. The exact relay parser accepts only current edit and deletion shapes for this kind, reuses `edit-event-id:` for edits, and adds `deletion-event-id:` for upgraded deletions.
- Extend `extractDirectInboxDedupeKey` only for upgraded deletion `eventId` so protected/legacy-shadow promotion derives the same key. Do not alter generic `extractMessageId`, push routing or edit target semantics.
- Generalize the existing v109 drain into one classifier-driven fair pass. Reaction ADD/REMOVE keeps `direct_reaction_v109`; exact edit/deletion uses `direct_mutation_v109`; malformed/unsupported rows are retained with bounded failure metadata and cannot starve later rows in the same loaded batch.
- Mutation protected acceptance performs one transaction: verify the exact local event row and classified edit/deletion shape; find the current outgoing parent by recipient plus exact envelope (edit may additionally bind its outer target); if exactly one current parent still owns those bytes, settle it to existing `inboxed`/visible-tombstone semantics with the relay proof's `expiresAtMs`; if zero, a newer/delivered/removed parent is preserved; if more than one, retain fail-closed; then delete only the exact accepted event. A transaction failure leaves the event retryable. Reaction completion remains projection-free.
- Preserve every edit and deletion obligation independently until its own protected acceptance; a later edit/delete never compacts, cancels or rewrites older event rows. v108 initial-message custody may coexist with all v109 events.
- Before cached replay, rebuild, re-encryption or legacy inbox storage, both failed and unacked retry paths perform an initial and pre-egress mutation-owner check. Manual retry may attempt that exact v109 row; the automatic pass runs after the shared drain and skips retained owners. A pre-Plan-349 edit already has an authenticated event ID but no durable provenance bit, so an ownerless exact cached edit keeps its historical exact-envelope inbox fallback and is never re-encrypted; this compatibility exception also covers an indistinguishable corrupt edit without inventing provenance storage. A truly legacy edit that the existing failed-row path rebuilds becomes newly authored at that point and must atomically acquire v109 before network. Both-absent legacy deletions keep their existing exact-v2/rebuild retry and remain v109-ineligible. A current event-bearing deletion with no exact owner is new-only corruption and fails closed. There is no scan or dormant-row promotion.
- Add an optional `mutationEventIds` map to the existing plaintext v1 delivery-receipt payload and sender API. New edit/deletion receivers include the authenticated event ID after durable apply, durable placeholder creation, exact replay or durable supersession. Sender settlement requires the pair to match the current outer event. A message-ID-only legacy receipt cannot settle a current event-bearing envelope; with an old receiver, that mutation therefore remains safely `inboxed`/pending until an exact event receipt or live authenticated apply proof arrives. Legacy initial/legacy-mutation rows retain current behavior, old senders ignore the additive map, and receipts never retire v109 custody.
- Add one narrow incoming ordinary-text apply capability beside `MessageRepository`. After authentication/decryption, the initial-chat, legacy/current edit and legacy/current deletion projections must transactionally re-read and conditionally apply the same target: an initial materializes only when it cannot overwrite a mutation winner, deletion dominates, and only a strictly newer edit can replace an ordinary parent. The same helper returns the durable disposition needed by current-event receipt scheduling. For these in-scope ordinary-text shapes, capability absence/throw fails closed with no generic upsert, cleanup or receipt; media/private/group and unrelated legacy shapes retain their current paths. Reuse one repository transaction boundary; do not add a process lock, event bus or scheduler.
- Reuse the one existing direct-custody lifecycle callback and ordering. The v108 family still drains first; the generalized v109 family runs once with per-row isolation; failed and unacked rebuilds follow. Add no scheduler or background service.

Must preserve:

- Fresh ordinary direct text/media v108 behavior, v110/v111 media preparation/blob ownership and exact ACK-or-expiry completion -> existing Plan 342/345/347 tests.
- Direct reaction ADD/REMOVE atomic staging, raw local event keys, `reaction-event-id:` relay namespace, ADD-only wake eligibility, UI ordering guard and one fair v109 capacity -> TC-349-04/07.
- Legacy v1/v2 edit and deletion readability/retry, including both-absent deletion identity and exact ownerless pre-349 edit fallback -> TC-349-03/05/06/07. Their receiver projection semantics remain unchanged but share the ordinary-text transaction to prevent races. Only a legacy edit that the existing failed-row path actually rebuilds becomes new authorship and acquires v109; dormant historical rows are not scanned or backfilled.
- Existing delete visibility: protected relay custody means visible `inboxed`; only an exact device-apply receipt may mark the current deletion delivered/hidden -> TC-349-05/06.
- Current initial-message receipt batching and old-client receipt parsing -> TC-349-06/07.
- Relay admission remains default-off; new sender to old/disabled relay never legacy-falls back and retains v109. Old receivers may consume the compatibility shadow; upgraded receive/ACK still clears protected custody -> TC-349-04.

Hard `Do not`:

- Do not add DB v112, a table, column, index, foreign key, event-kind column, migration, per-kind quota, second outbox, filtered drain, timer, isolate, WorkManager job or admission flag.
- Do not rename the physical v109 table/migration or mass-rename reaction symbols solely for aesthetics. Do not add a local subtype-key translation layer. Limit new abstractions to the explicit outgoing mutation-custody capability, incoming conditional-apply capability and one narrow envelope classifier; do not build a generic event framework.
- Do not include edits/deletes of ordinary media, protected/view-once/disappearing content, group/announcement messages, linked-device fanout, a background historical scan/backfill, or dormant no-intent row promotion.
- Do not compact/supersede older event rows, rebuild exact owned ciphertext, or let live ACK/delivery receipt retire sender custody.
- Do not add a receipt table, per-mutation UI status/history, new receipt retry queue, push/provider payload change, notification ledger, telemetry framework, quota UX or rollout cohort machinery.
- Do not deploy/activate a production relay, run full per-plan `host-all`, create a mobile harness, or require Android/iOS device execution.

Deferred / accepted difference:

- Ordinary-media edit/delete crosses v111 cleanup and parent atomicity -> a later N01 adoption only after that authority is reviewed.
- Private/view-once/disappearing mutation lifetime and deletion semantics -> later N01 private-lifecycle adoption.
- Groups/announcements, per-device fanout and the explicit historical/no-intent decision -> later N01 slices/checkpoint.
- Historical/no-intent protected-custody promotion remains deferred. Ownerless pre-349 event-bearing edits cannot be distinguished from corruption without adding provenance storage, so they retain exact legacy fallback; both-absent deletions remain legacy.
- Accepted provenance ambiguity: if a Plan-349 edit owner is externally corrupted/lost, retry cannot distinguish it from a legitimate pre-349 event-bearing edit and therefore takes the same exact legacy fallback. Adding a marker/schema solely to distinguish those rows is outside this bounded plan.
- Per-event delivery history or UI state beyond the current parent status -> not claimed by this custody slice. The additive event receipt prevents false settlement but is not a delivery ledger.
- New sender + old receiver remains a safe mixed-version limitation: a target-only legacy receipt cannot prove the current mutation event, so the sender may remain `inboxed`/pending rather than be falsely marked delivered.
- Production ACK-custody admission, cohort/operations/quota UX, dependency-wave `host-all`, consolidated iOS and release eligibility -> WP-07/GAP-N12. Plan 349 remains default-off and not independently release-eligible.
- Real two-peer background/presentation recovery -> N01/N02/N03 dependency-wave Android acceptance; no OS-specific behavior changes here.

Dependencies:

- Plan 343 supplies the unchanged physical v109 event owner and lifecycle cadence.
- Plan 344 supplies default-off Redis protected custody, exact proof, compatibility shadow and mixed-version negotiation.
- Plan 348 is committed at the exact baseline above; no unfinished Plan 348 path is part of Plan 349.

## Test Contract

| Case | Behavior | Named test/proof | Tier / fixture | HEAD -> GREEN | Mutation | Gate / registration |
|---|---|---|---|---|---|---|
| TC-349-01 | Ordinary-text edit/delete parent mutation and raw-event-ID v109 ownership are one transaction; exact replay precedes shared capacity; forced cross-kind/key collisions and policy/media drift refuse atomically | `test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart::{TC-349-01 ordinary text mutations stage atomically in shared v109,TC-349-01 exact mutation replay wins at capacity and changed bytes refuse,TC-349-01 forced reaction mutation event collision preserves prior owner,TC-349-01 attachment or policy drift refuses parent and owner}`; `test/features/conversation/domain/repositories/message_repository_impl_test.dart::TC-349-01 committed mutation authority survives publication failure` | Host repository/integration; real SQLite FFI, second-connection barrier, abort trigger, bounded capacity seam | HEAD has reaction-only stage -> GREEN neither half is visible before commit; abort/CAS/capacity/attachment/policy refusal changes neither; edit A/edit B/delete retain exact rows; same exact key/bytes is idempotent; a forced different-kind collision safely refuses | Call generic parent stage before event insert, omit the tombstone attachment guard, check capacity before replay, overwrite a colliding row, or treat publication throw as refusal -> red | Exact files; AUTO core/feature; existing v109 helper is curated 1:1 in both inventories |
| TC-349-02 | Newly authored ordinary direct-text EDIT requires mutation custody, stages before every network decision, survives node-off, schedules one protected hedge without serializing live delivery, uses a repository-current strictly increasing `editedAt`, and retains all event bytes | `test/features/conversation/application/send_chat_message_use_case_test.dart::{TC-349-02 edit stages exact v109 authority before network,TC-349-02 live ACK retains custody and does not cancel scheduled hedge,TC-349-02 stopped node authors edit custody without network,TC-349-02 stale UI or regressed clock uses repository-current strictly newer timestamp,TC-349-02 malformed or overflowing prior editedAt fails closed,TC-349-02 edit stage refusal has zero network and preserves parent}` | Host application; custody-capable repository fake plus real-repository crossing for ordering | HEAD edits use generic staging/node early-return -> GREEN first network observer sees exact parent+event; live ACK may return without awaiting relay but cannot skip/cancel/delete the retained owner; node-off returns existing diagnostic with durable edit; repository-current A/B timestamps and events are distinct | Restore generic edit stage, trust stale UI state, put node gate/network before authority, serialize live delivery on relay, cancel custody on live ACK, reuse event ID, accept malformed/overflow time, or use raw/regressed clock -> red | Exact file; already in both 1:1 inventories and AUTO feature |
| TC-349-03 | Newly authored ordinary direct-text delete carries matching outer/inner event ID, atomically stages visible tombstone+v109 before network/node return, and schedules one protected hedge without blocking a running-node fast path, while legacy both-absent deletion remains readable and dormant/non-owned | `test/features/conversation/domain/models/message_deletion_payload_test.dart::{TC-349-03 current deletion round-trips outer and inner event identity,TC-349-03 legacy deletion remains readable}`; `test/features/conversation/application/delete_message_use_case_test.dart::{TC-349-03 ordinary text deletion stages before network and live ACK retains custody,TC-349-03 stopped node retains exact deletion custody,TC-349-03 stage refusal has zero parent reaction cleanup or network,TC-349-03 media private and disappearing deletion remain excluded}`; `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart::TC-349-03 partial blank or mismatched deletion identity has zero side effects` | Host domain/application; deterministic crypto bridge, mutation-capable real/fake repository | HEAD deletion has no event ID and exits/stores legacy -> GREEN fresh identity is exact, stage is authoritative, refusal is nondestructive, live ACK does not await/cancel custody, node-off leaves custody, malformed current identity is unauthorized before side effects | Omit inner/outer parity, call legacy store for a current event, clean reactions before stage authority, put network before atomic authority, serialize live delivery on relay, delete custody on live ACK, expose target ID, or select an excluded lane -> red | Exact files; application files already in both 1:1 inventories; model AUTO feature |
| TC-349-04 | One global FIFO v109 drain classifies reaction versus mutation, isolates poison/ambiguous rows, uses exact proof/CAS, and the Dart/relay/native stack accepts only exact `direct_mutation_v109` edit/deletion shapes | `test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart::{TC-349-04 one fair batch routes reaction edit and deletion kinds,TC-349-04 accepted old mutation preserves newer parent,TC-349-04 duplicate-parent ambiguity retains exact mutation,TC-349-04 full generic proof throw and completion rollback retain exact row}`; `test/core/services/p2p_service_impl_test.dart::TC-349-04 direct mutation custody kind reaches existing strict bridge command`; `go-relay-server/ack_custody_protocol_test.go::TestRelayNotificationClosure_DirectMutationCustody` covers exact shapes plus cross-kind/media-expiry rejection; `go-relay-server/ack_custody_shadow_test.go::TestRelayNotificationClosure_AckCustodyProtectedShadowAtomicity/direct_mutation_legacy_first_promotion` proves same relay ID/timestamp, no repush, and a legacy destructive read leaves protected authority; existing direct edit/reaction dedupe tests extend deletion/type namespaces; existing Go node/bridge/mixed-version parents add one mutation-kind row | Host Dart real SQLite + host Go production handler/miniredis and framed libp2p selector | HEAD routes all v109 as reaction and relay/native reject mutations -> GREEN global order progresses; exact stored/duplicate proof alone retires and passes proof expiry to the exact current parent; duplicate-parent ambiguity changes neither parent and retains the row with bounded failure; legacy-first mutation promotion preserves identity/no-repush/protected authority; old/new/disabled/full/malformed/cross-kind/media-expiry retain; relay namespaces do not collide | Add a second filtered drain, route deletion as edit/reaction, accept generic OK/legacy fallback, omit sender/shape/proof expiry, repush/remint during promotion, let legacy destructive read remove protected authority, settle an ambiguous parent set, or delete on completion failure -> red | Existing AUTO/curated Dart/core files; relay parents remain under `TestRelayNotificationClosure_`; extend existing `run_ack_custody_go_gate`, no new gate function |
| TC-349-05 | Restart/manual/automatic recovery uses v109 as sole owner for Plan-349 mutations, preserves exact legacy fallback only where provenance is absent, rechecks authority at egress, and exact accepted completion settles only the current matching parent while atomically closing owned-event fallback | `test/features/conversation/application/retry_failed_messages_use_case_test.dart::{TC-349-05 failed owned edit and deletion drain exact v109 without legacy replay,TC-349-05 pre349 event edit keeps exact legacy fallback without rebuild,TC-349-05 legacy edit rebuild acquires v109 while both-absent deletion stays legacy,TC-349-05 owner winning after failed edit or deletion lookup blocks all legacy egress,TC-349-05 current event deletion without owner fails closed}`; `test/features/conversation/application/retry_unacked_messages_use_case_test.dart::{TC-349-05 unacked mutation checks owner again at egress,TC-349-05 ownerless pre349 edit preserves exact legacy fallback}`; `test/core/services/pending_message_retrier_direct_inbox_custody_test.dart::TC-349-05 shared v109 drain precedes failed and unacked rebuild`; production bootstrap phase contract updated for one generalized v109 pass | Host application/integration; persistent real DB for restart, strict/legacy recording stores, pre-egress barrier | HEAD failed/unacked paths legacy-store or rebuild -> GREEN restart replays owned exact bytes/IDs; an owner winning after initial lookup blocks both failed shapes before store/send; ownerless pre349 event edits preserve exact cached legacy behavior without re-encryption; accepted current parent becomes inboxed with proof expiry in the same transaction; newer/removed parent is untouched | Delete row before parent settlement, omit either ownership check, re-encrypt an event-bearing legacy edit, legacy-store a current owned event, promote a both-absent deletion, or move drain after failed/unacked -> red | Existing files; retry-unacked/pending/bootstrap are curated or core; remaining AUTO feature |
| TC-349-06 | Receiver convergence and receipt correlation are mutation-aware under sequential and concurrent arrival: delayed initial/legacy events cannot overwrite a mutation winner, deletion dominates edits, only the newest edit wins, durable ignored/placeholder events emit exact receipt identity, and delayed/stale receipts cannot settle a newer mutation | `test/core/database/helpers/messages_db_helpers_test.dart::{TC-349-06 concurrent initial edit deletion conditional apply cannot resurrect or regress parent,TC-349-06 concurrent older newer edit commits newest in both orders,TC-349-06 legacy current mutation crossing preserves current winner}`; `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart::{TC-349-06 edit placeholder stale and deleted convergence emits event receipt,TC-349-06 initial edit delete and legacy current crossed barriers converge,TC-349-06 ordinary text apply capability absence has zero persistence or receipt}`; `test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart::TC-349-06 ordinary text deletion capability absence has zero persistence cleanup or receipt`; deletion receiver/listener tests for event receipt; `test/features/conversation/application/send_delivery_receipt_use_case_test.dart::TC-349-06 v1 receipt adds optional mutation event map`; `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart::{TC-349-06 delayed initial receipt cannot settle current edit,TC-349-06 stale edit receipt cannot settle current deletion and exact event receipt can,TC-349-06 mixed receipt batch settles legacy IDs but not blank wrong mutation entries}` | Host application/integration; real SQLite transactional apply with second-connection barriers, persistent repositories, recording receipt hooks | HEAD independent handlers/callbacks can save stale state and receipt has only target IDs -> GREEN crossed initial/edit/delete, legacy/current or edit/edit commits cannot resurrect/regress; missing/throwing ordinary-text capability cannot reach generic upsert/cleanup/receipt; exact event pair is required for event-bearing current rows; valid legacy entries in the same batch still settle; old-receiver target-only receipt leaves current mutation inboxed; receipt never removes v109 | Keep any ordinary-text read-then-generic-upsert bypass, use only a process lock, fall back when the required capability is absent/throws, ignore event pairing, let a blank/wrong map entry fall through via `messageIds`, accept a legacy receipt for current mutation, fail to receipt durable supersession, or let receipt delete custody -> red | Existing core/receipt/chat/delete files are already in both 1:1 inventories or AUTO feature; no new file registration |
| TC-349-07 | Existing v108/v109 reaction/v111, schema/account transfer, legacy/excluded lanes, rollout default and no-new-infrastructure guard remain intact | Existing `TC-342-03c media private edit delete and existing attempts remain outside new custody`; unchanged v109 migration/schema and existing opaque-row account active-import tests; reaction send/remove tests; `scripts/test/relay_ack_custody_rollout_contract_test.sh` pins the one new kind and existing sole flag | Host preservation; real SQLite schema/inventory/import plus source/shell contracts | GREEN sentinel on HEAD -> GREEN DB stays v111 and physical v109 shape unchanged; generic transfer preserves opaque bytes; reactions and excluded lanes retain owners; admission stays off | Add schema/kind column, alter reaction keys/wake, specialize generic account transfer, promote legacy/private/media/group, or add a flag/gate -> sentinel red | Existing AUTO/curated files; completeness check; rollout shell already in ACK-custody gate |

### Test Notes

- TC-349-01 uses the authenticated raw event UUID as both local and wire identity. A forced different-envelope collision is a safe refusal, not a requirement to support coexistence; relay dedupe remains type-namespaced.
- TC-349-04 malformed/unknown rows remain retryable and do not call either strict kind. Processing continues to later entries from the already-loaded global batch; no second query/filter is introduced.
- TC-349-04 treats more than one current parent matching recipient+exact envelope as local ambiguity: no projection or row deletion occurs, bounded failure metadata is recorded, and later batch rows still progress.
- TC-349-04 extends the existing protected-shadow atomicity parent for the new kind; it does not create a mutation-specific backend, Redis keyspace, expiry policy or push path.
- TC-349-04 protected acceptance is relay custody transfer, not device delivery. It may project an exact current parent to `inboxed`; TC-349-06 alone may establish `delivered` for a mutation.
- TC-349-06 preserves `messageIds` in every receipt for old senders. `mutationEventIds` is additive and omitted when empty. Blank, non-string or mismatched map entries are ignored fail-closed rather than degrading the whole valid legacy receipt.
- TC-349-06 uses one DB-transaction conditional apply shared by ordinary text initial materialization plus legacy/current edit/deletion projection. It does not serialize decryption, unrelated message IDs, media/private/group handling or receipt network sends.

## Implementation Steps

1. Snapshot `git status --short`, `git rev-parse HEAD`, and the unrelated four-path baseline. Require HEAD `d06072d805eda7e549cd2b5d878f306297dba130`; preserve planning artifacts and all unrelated user changes. Add TC-349-01 plus the receipt and concurrent-receiver counterexamples before production edits; record all three causal nonzero RED families.
2. Add the smallest shared Dart outer-envelope classifier needed by stage, drain, retry and receipt guards. Use the authenticated raw event UUID directly; a forced key collision with changed bytes refuses atomically. Keep the exact legacy retry distinctions in Step 8; do not create subtype-key translation, a generic event framework, provenance field or historical scanner.
3. In the existing v109 helper/contract, add mutation stage and mutation-aware exact completion. Compose `dbStageOutgoingOrdinaryAttemptWithinTransaction`, strict ordinary-text qualification, exact-replay-before-capacity, and v109 insert in one transaction. Completion settles at most one exact current parent and deletes the exact event in the same transaction; stop-if this requires a schema change.
4. Add the optional message-repository mutation-custody capability and production delegates. Publication after committed stage/completion is best-effort and cannot revoke DB authority. Reuse the existing table loader/failure CAS rather than duplicate storage code.
5. Route only eligible `sendChatMessage(action: edit)`/`editChatMessage` through atomic v109 staging. Re-read the authoritative parent, make fresh `editedAt` monotonic, fail closed on malformed/overflowing prior order, keep exact retry values stable, move only this lane's node gate after stage, and schedule one non-throwing `direct_mutation_v109` hedge beside the existing running-node live path. Preserve the live transport/race and result enums; do not await relay before a live ACK, and never cancel/delete custody on live success.
6. Extend `MessageDeletionPayload` with optional current `eventId`; mint it once for a newly authored eligible deletion, verify outer/inner parity on receive, and atomically stage the text tombstone plus v109 before network/node return. Schedule one non-throwing protected hedge beside the existing running-node delete race; do not serialize its connected fast path on relay completion or cancel custody on live ACK. Keep legacy deletion builders/retries and every excluded lane on their present behavior. Stop-if target ID must become cleartext.
7. Generalize the existing v109 drain once. Classify each loaded envelope, choose the existing reaction or new mutation custody kind, invoke reaction or mutation completion, retain per-row failure isolation, and keep the one existing lifecycle callback/order. Do not add another drain or timer.
8. Guard failed and unacked retry at lookup and egress. Manual mutation retry may call the exact entry drain; automatic retry after the lifecycle pass skips retained owners. Preserve an ownerless pre-349 event-bearing edit's exact legacy fallback without re-encryption; a truly legacy edit rebuilt by the existing failed-row path becomes new authorship and must atomically stage v109. Keep both-absent legacy deletion retry v109-ineligible. A current event-bearing deletion without an owner fails closed. Add no provenance marker or historical scan.
9. Add one transactionally conditional incoming ordinary-text apply capability and use it after authentication/decryption for initial materialization plus legacy/current edit and deletion projection. Re-read the target inside the transaction, prevent initial/legacy overwrite of a mutation winner, enforce deletion dominance and strict edit ordering, and return a typed durable disposition for current-event receipt scheduling. Required capability absence/throw fails closed for these ordinary-text shapes; media/private/group and unrelated legacy paths remain unchanged. Do not add a global/process lock or serialize unrelated messages and network receipt sends.
10. Add optional receipt event correlation through the current sender, chat/deletion handlers and listeners. Durable edit/delete convergence sends the raw event ID. The receipt handler compares it with the current outer envelope before existing settlement; message-ID-only receipts cannot settle current mutation envelopes and may conservatively leave new-sender/old-receiver rows `inboxed`. Add no new persistence or retry mechanism.
11. Add `direct_mutation_v109` to Dart, P2P mapping, Go node and bridge allowlists. Extend only the protected relay parser and direct-inbox deletion dedupe path; preserve actions, contract, flag, metrics, expiry, APIs and generic push identity. Extend the existing mixed-version parent by one kind row.
12. Extend existing focused tests and gate-owned parents. Keep DB v109/v111 migration and account-transfer schema unchanged. Update the coverage assessment and Plan 349/index execution receipts only during implementation closure; do not change the PRD target requirements.
13. Rebuild/verify Android bindings because compiled Go changes, run focused and aggregate gates below, refresh Graphify once with `./graphify-arch/refresh_arch_graph.sh --incremental`, then append `- Plan 349 — EXECUTION_COMPLETED` only after every required closure item passes.

## Risks And Blind Spots

- Forced cross-kind raw-ID collision -> exact existing bytes replay, different bytes refuse atomically without parent drift in TC-349-01; generated production identities remain UUIDs and relay keys remain type-namespaced.
- Shared cap could starve one kind -> exact replay before cap plus one global FIFO/batch and mixed-kind progress in TC-349-01/04; no speculative per-kind quota.
- Crash after protected acceptance but before parent settlement could expose legacy retry -> one completion transaction plus failed/unacked double checks in TC-349-04/05.
- An older accepted event could overwrite a newer edit/delete -> zero-match preservation and exact-parent settlement in TC-349-04/05.
- Equal/regressed sender clock could make edit convergence arrival-dependent -> strict monotonic authoring and reorder proof in TC-349-02/06.
- Delayed initial/edit receipt could falsely deliver or hide the current mutation -> additive event correlation and legacy guard in TC-349-06.
- Legacy clients/rows could be accidentally stranded or broadly promoted -> exact pre-349 edit fallback, no provenance/schema/scan, both-absent readability and mixed/default-off sentinels in TC-349-03/04/05/07.
- Independent chat/deletion streams and unawaited same-stream callbacks can cross stale reads and resurrect/regress a target -> one narrow ordinary-text transactional conditional apply plus initial/edit/delete, legacy/current and edit/edit barriers in TC-349-06.
- Lifecycle / derived-state durability: DB v109 is status-independent and the existing startup/reconnect/network-restored/periodic/resume callback drains it before failed/unacked rebuild -> TC-349-05.
- Sibling-surface consistency: reactions remain on the same fair owner; v108/v111, media/private/disappearing/group lanes keep their current owners -> TC-349-07.
- Destructive-action side effects: deletion stages a visible tombstone only with exact event authority; a false/stale receipt cannot hide it, and excluded media/private cleanup is untouched -> TC-349-03/06/07.
- Invariant re-verification under new transitions: node-off, full capacity, transaction abort, process restart, accepted-completion rollback, stale parent, delayed receipt and mixed relay version each recheck current authority -> TC-349-01 through TC-349-06.

## Gate Cadence

- Per-plan closure: focused causal Dart/SQLite tests; exact relay/node/bridge/mixed-version tests; existing ACK-custody rollout/binding contracts; curated `1to1`; `core-host-all` because shared DB/P2P/receipt code changes; serial `feature-host-all` because edit/delete/retry/listener production paths change; analyzer, format/diff hygiene and one Graphify refresh.
- Do not run full `host-all` for Plan 349. Run `./scripts/run_host_test_gates.sh host-all` once after the remaining GAP-N01 dependency wave, then again at final rollout/release closure.
- Shared tests outside feature/core globs: Go relay/node/bridge/integration and the rollout/binding shell contracts run by exact commands and the existing non-vacuous `run_ack_custody_go_gate` tail. No new family gate is added.

## Device/Relay Proof Profile

- Profile: host-only.
- Boundary being proven: the production protected relay parser/backend accepts only exact edit/deletion mutation envelopes, the native selector forwards the one new kind without legacy fallback for Plan-349-owned current events, and Dart accepts only exact ACK-or-expiry proof.
- Live availability check: N/A - no OS, device, schema migration or platform-channel API changes; an Android AAR build is required but is not a device claim.
- Required setup: Go 1.25 toolchain; relay production handler with the existing Redis/miniredis fixtures; existing framed libp2p mixed-version fixture; available Android SDK/NDK for gomobile binding build.
- Two-peer default: N/A - no mobile-runtime claim. The dependency-wave Android scenario owns later two-peer presentation recovery.
- Closure role: required code-boundary evidence for this default-off slice; not production deployment/activation or full recipient-presentation evidence.
- `FLUTTER_DEVICE_ID`: N/A - no Flutter device command.
- Registration: new relay test stays under `TestRelayNotificationClosure_`; node/bridge/mixed rows extend parents already selected by `run_ack_custody_go_gate`; no `classify_path`, dart-define or device scenario.
- Discovery command: `(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . -list '^TestRelayNotificationClosure_DirectMutationCustody$')` and existing ACK-custody gate `-list` checks -> exact parents must be printed and non-skipped.
- Closure command: focused/full Go commands plus Android binding commands in Acceptance Gates -> exact protected proof, no legacy fallback for Plan-349-owned events, and one mutation-kind frame pass.
- Deferred device work: N01/N02/N03 dependency-wave Android two-peer recovery and GAP-N12 consolidated iOS/release closure.

## Acceptance Gates

```bash
# Baseline and ownership snapshot. HEAD must be the isolated Plan 348 commit.
git status --short
git rev-parse HEAD

# First causal RED before production edits: expect non-zero because HEAD has
# no atomic ordinary-message-mutation + shared-v109 stage.
flutter test test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  --plain-name 'TC-349-01 ordinary text mutations stage atomically in shared v109'

# Independent receipt RED: expect non-zero because HEAD accepts a target-only
# delayed receipt against whichever mutation envelope is current.
flutter test test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  --plain-name 'TC-349-06 delayed initial receipt cannot settle current edit'

# Independent receiver-order RED: expect non-zero because HEAD performs
# separate ordinary-text initial/edit/deletion read-then-upsert decisions.
flutter test test/core/database/helpers/messages_db_helpers_test.dart \
  --plain-name 'TC-349-06 concurrent initial edit deletion conditional apply cannot resurrect or regress parent'

# Focused DB/repository/authoring/drain/retry/lifecycle GREEN.
flutter test --concurrency=1 \
  test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart \
  test/core/database/helpers/messages_db_helpers_test.dart \
  test/features/conversation/domain/repositories/message_repository_impl_test.dart \
  test/features/conversation/application/send_chat_message_use_case_test.dart \
  test/features/conversation/application/delete_message_use_case_test.dart \
  test/features/conversation/application/drain_direct_reaction_inbox_custody_outbox_use_case_test.dart \
  test/features/conversation/application/retry_failed_messages_use_case_test.dart \
  test/features/conversation/application/retry_unacked_messages_use_case_test.dart \
  test/core/services/pending_message_retrier_direct_inbox_custody_test.dart \
  test/core/services/p2p_service_impl_test.dart \
  test/core/bootstrap/production_application_bootstrap_phase_contract_test.dart

# Focused payload/receiver/receipt/listener and preservation GREEN.
flutter test --concurrency=1 \
  test/features/conversation/domain/models/message_payload_test.dart \
  test/features/conversation/domain/models/message_deletion_payload_test.dart \
  test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart \
  test/features/conversation/application/handle_incoming_message_deletion_use_case_test.dart \
  test/features/conversation/application/chat_message_listener_test.dart \
  test/features/conversation/application/message_deletion_listener_test.dart \
  test/features/conversation/application/send_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/handle_delivery_receipt_use_case_test.dart \
  test/features/conversation/application/send_reaction_use_case_test.dart \
  test/features/conversation/application/remove_reaction_use_case_test.dart \
  test/core/database/migrations/109_direct_reaction_inbox_custody_outbox_test.dart \
  test/features/account_migration/application/migration_database_active_importer_test.dart \
  test/features/account_migration/application/migration_database_schema_inventory_test.dart

# Relay/native causal and complete affected-package proof.
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test . \
  -run '^TestRelayNotificationClosure_(AckCustodyEligibilityIsNarrow|DirectMutationCustody|AckCustodyProtectedShadowAtomicity)$' \
  -count=1)
(cd go-relay-server && GOTOOLCHAIN=go1.25.0 go test ./... -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node \
  -run '^TestInboxAckCustodyMixedRelayAndProofContract$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./bridge \
  -run '^TestDispatchInboxAckCustodyContract$' -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test ./node ./bridge -count=1)
(cd go-mknoon && GOTOOLCHAIN=go1.25.0 go test -tags integration ./integration \
  -run '^TestAckCustodyMixedVersionMatrix$' -count=1)
bash scripts/test/relay_ack_custody_rollout_contract_test.sh

# Changed compiled Go must be present in the Android artifact; no device run.
bash scripts/ensure_go_android_bindings.sh
./scripts/verify_gomobile_bindings.sh android
bash scripts/test/go_binding_staleness_contract_test.sh

# Registration/completeness, affected curated lane and justified families.
./scripts/run_test_gates.sh completeness-check
./scripts/run_test_gates.sh 1to1
./scripts/run_host_test_gates.sh core-host-all --batch-flutter --concurrency 2
./scripts/run_host_test_gates.sh feature-host-all --batch-flutter --concurrency 1

# Hygiene and one post-change architecture refresh.
flutter analyze
dart format --output=none --set-exit-if-changed $(
  {
    git diff --name-only --diff-filter=ACMR -- '*.dart'
    git ls-files --others --exclude-standard -- '*.dart'
  } | sort -u
)
./graphify-arch/refresh_arch_graph.sh --incremental
git diff --check
```

## Execution Interpretation And Done Criteria

- Expected RED: TC-349-01 fails because no message-owned v109 mutation transaction exists; TC-349-06 receipt RED fails because the current receipt cannot identify the event it proves; TC-349-06 receiver RED fails because ordinary initial/edit/deletion projections are separate read-then-upsert operations.
- Green sentinel: v109 schema/reaction behavior, v108/v111 owners, legacy edit/delete parsing/retry, initial receipts, excluded modalities and default-off rollout remain unchanged.
- Pre-existing dirty tree / known failure: baseline HEAD is `d06072d805eda7e549cd2b5d878f306297dba130`. The PRD, coverage report, `info.plist`, and macOS project file were already modified outside Plan 349; preserve them and attribute any intentional coverage update separately.
- Environment blocker: none expected. Android binding build requires the locally configured SDK/NDK; absence blocks only the compiled-Go artifact receipt, not permission to substitute a device/iOS campaign.
- Scope drift: any required schema migration, outer deletion target ID, second drain/scheduler, media/private/group mutation adoption, receipt persistence/queue, platform API, production activation or mobile runtime code stops execution for re-review.

- [x] Every behavior has a named test or justified proof.
- [x] TC-349-01 and both TC-349-06 causal RED families, focused GREEN and representative network-before-stage / wrong-kind / stale-receipt / stale-receiver-write mutation re-reds are recorded.
- [x] Atomic stage/completion, shared fairness, restart/retry, identity parity, transactional receiver convergence and receipt correlation pass with semantic outcomes.
- [x] Existing registration is verified; no duplicate gate or unclassified new test exists.
- [x] Relay/native exact proof and Android binding build/verification pass; no device/iOS claim is made.
- [x] Curated `1to1`, justified core/feature families, analyzer and diff hygiene pass.
- [x] Graphify is refreshed exactly once after coherent code changes.
- [x] Scope Contract And Guard is respected and coverage/index/status receipts are truthful.

## Handoff

- First causal RED command: `flutter test test/core/database/helpers/direct_reaction_inbox_custody_outbox_db_helpers_test.dart --plain-name 'TC-349-01 ordinary text mutations stage atomically in shared v109'`.
- Preservation command: the second focused Flutter command plus `./scripts/run_test_gates.sh 1to1`.
- Manual registration: no new gate function. Extend existing test files/parents; if implementation proves a new host file unavoidable, add it exactly once to both `ONE_TO_ONE_TESTS` and `ONE_TO_ONE_HOST_TESTS`, then rerun completeness.
- Migration: none; DB remains v111 and the existing v109 schema/migration test is preservation-only.
- Boundary closure: host production relay/native contracts plus rebuilt Android AAR; no simulator/device/iOS run.
- Unresolved evidence: none inside the bounded slice. Production activation, other N01 modalities and wave/release evidence remain deferred owners above.
- Gate receipt: focused Dart/SQLite authoring, drain, retry, receiver, receipt, listener, repository and preservation suites are green; completeness classified 1,437/1,437 tests; `core-host-all` passed 404 paths / 3,207 tests; `feature-host-all` passed 841 paths / 8,992 tests / 7 declared skips; final `1to1` passed 3,015 Flutter tests / 6 declared skips plus every relay ACK/media/mixed-version tail. Full relay, node, bridge and mixed integration packages, rollout contract, Android AAR ensure/verification/staleness, analyzer, exact format, diff hygiene and Graphify are green.

## Reviewer Findings

- Verdict: `ready`.
- Plan classification: `implementation-ready`; core bet: `confirmed`.
- Disposition: `execute`.
- Required deltas applied in place: raw v109 event IDs with atomic collision refusal; exact pre-349 edit fallback without provenance/schema; repository-current monotonic edit time; nondestructive delete refusal; one shared fair v109 classifier; exact mutation completion/expiry and retry egress guards; mutation-specific shadow promotion; transactional ordinary-text initial/edit/delete receiver convergence; additive event-aware receipts with mixed-version precedence; exact P2P/Go/binding/format gates.
- Overengineering removed or prohibited: v112/schema/kind column, local subtype translation, second drain/outbox/scheduler, account-transfer specialization, historical scan, process lock, receipt ledger/queue, new rollout flag, per-plan full `host-all`, and mobile/iOS harness work.
- Accepted limitation: externally lost/corrupt Plan-349 edit ownership is indistinguishable from a legitimate pre-349 event-bearing edit and takes the same exact legacy fallback. Adding provenance solely for that distinction is deferred.
- Blind-spot hits for stale cause, rollback/authority, concurrency, mixed version, derived state and sibling bypasses are represented by TC-349-01 through TC-349-07; remaining review classes are clear or N/A.

## Arbiter Decision

Execute this bounded Plan 349 contract as written. It closes newly authored ordinary direct-text edit/delete custody and the receiver/receipt invariants needed to make that custody truthful while reusing existing v109/relay/lifecycle machinery. It does not close GAP-N01, activate production custody, or authorize media/private/group/historical/device/iOS expansion. No implementation is part of this session.

## Execution Progress

| Time | Phase | Files | Last command/result | Current evidence | Decision/blocker | Next |
|---|---|---|---|---|---|---|
| 2026-08-09 | execution not started | planning artifacts only | `$tdd-plan` + `$tdd-review`: `ready` | Source-grounded contract, three causal RED families, focused/preservation/aggregate gates and scope stops are specified | none; execution handoff is ready | implement in a separate execution session and append `EXECUTION_COMPLETED` only after closure |
| 2026-08-09 | baseline + RED | Plan 349 TC-349-01/06 DB, receipt and receiver sentinels | baseline `d06072d805eda7e549cd2b5d878f306297dba130`; all three exact causal tests exited non-zero before production edits | missing atomic shared-v109 mutation stage, event-aware receipt settlement and transactional ordinary-text apply were independently reproduced | none | implement the bounded shared-owner adoption |
| 2026-08-09 | GREEN + hardening | v109 classifier/stage/completion, message repository, edit/delete authoring, retry/lifecycle, receiver/receipt, fakes and protocol contracts | focused authoring/drain/retry and payload/receiver/receipt batches passed 509 + 297 tests; additional convergence and analyzer-fix batches passed | exact event ownership, collision refusal, fair drain, monotonic edit/delete identity, retry bypass guards, conditional receive and event-aware receipts are green | none | close relay/native/binding and aggregate gates |
| 2026-08-09 | relay/native + binding closure | relay protected/shadow parser and dedupe; Go node/bridge; mixed integration; Android artifact | full relay passed; node 327.060s and bridge 147.993s passed; mixed integration and rollout contract passed; Android AAR ensure/verify/staleness passed | `direct_mutation_v109` is strict across Dart, relay, node, bridge and the rebuilt Android artifact; admission remains default-off | none | run registration and affected host families |
| 2026-08-09 | host closure | registered Dart/Go/shell families | completeness 1,437/1,437; core 404 paths / 3,207 tests; final feature 841 paths / 8,992 tests / 7 skips; final `1to1` 3,015 Flutter tests / 6 skips plus all Go tails | the first feature run exposed and fixed the all-live-failed deletion-custody result plus a fail-closed test fake; focused 33-test proof and the complete rerun are green | none | hygiene and architecture refresh |
| 2026-08-09 | closure | 45 changed/new Dart paths plus architecture graph | analyzer `No issues found` in 32.3s; format 45 files / 0 changed; incremental Graphify 57 changed / 3,094 unchanged / 0 deleted, 70,328 nodes / 103,449 edges | every done criterion is satisfied; no schema, activation, device/iOS or standalone release claim was added | none | implementation handoff complete |
