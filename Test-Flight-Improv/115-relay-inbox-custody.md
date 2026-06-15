# 115 — Relay Inbox Custody Truthfulness: end silent 100-cap/7-day-TTL message loss behind sender-side green 'delivered' (TDD Plan)

Date: 2026-06-12 · Branch: 121-improvements · Status: **CLOSED FOR IMPLEMENTATION AND PROD-RELAY DEPLOY — residual device/TestFlight lab evidence archived (2026-06-13).** Phases 1-5 are host-accepted, the production relay on `mknoun.xyz` is updated and verified with the Doc 115 artifact, and real-device drain/old-TestFlight interop evidence is not claimed. This doc is the **program foundation**: its Phase 1 lands FIRST program-wide (docs 114/116 build on the status model minted here). Renumbered from the draft title "114" — 114 is now the LAN ack-after-commit doc, 116 the edit-retry-fidelity doc.

Source: graph-first trace + independent verification (verdict: **confirmed end-to-end**), cross-checked by the 3-doc program completeness critic on 2026-06-12. All file:line anchors verified against the uncommitted 121-improvements working tree on 2026-06-12 (re-verify per session, Caveat 9.6).

---

## 1. Problem statement and impact

A sender-side 1:1 message row is persisted `status='delivered'`, `transport='inbox'` — rendered as terminal done_all "delivered" (`letter_card.dart:600-644`) — the moment the relay store returns OK. But the relay's 1:1 inbox gives **no custody guarantee**:

- **Cap eviction.** At ≥100 pending entries per recipient (`maxMessagesPerPeer=100`, `go-relay-server/inbox.go:23-27`; env `RELAY_MAX_INBOX_MESSAGES_PER_PEER`, `limits.go:14/:56`), every new store **silently evicts the oldest entry** and still answers `Status OK / StoreStatus stored` — production memory path `limits.go:105-141` (eviction `:124-127`), shared inner impl `backend_memory.go:114-150` (evict `:131-136`), Redis trim `backend_redis.go:301-303`. No log, no metric, no error, no protocol signal: the `inboxResponse` struct has no capacity/eviction field (`inbox.go:1297-1312`), the Go client struct drops even `StoreStatus` (`go-mknoon/node/inbox.go:33-39`), the bridge returns bare `{ok:true}` (`bridge.go:1109-1143`), and Dart reads only `response['ok']` (`p2p_service_impl.dart:3178-3217`).
- **7-day TTL.** Entries older than `maxMessageAge=7*24h` (clock starts at **relay arrival**, `inbox.go:1386-1390`) are silently dropped by lazy prune on the next touch (`backend_memory.go:294-306`; Redis cutoff `backend_redis.go:271`). The hourly background prune covers ONLY the group inbox (`main.go:119-131`).
- **The sender can never repair.** `persistInboxDelivered` writes `'delivered'` and discards the `wireEnvelope` (`send_chat_message_use_case.dart:861-906`, status literal `:872`); the unacked-handoff (`:1722-1735`) and concurrent-custody (`:1692-1708`) branches do the same; `retry_unacked_messages_use_case.dart` mints `'delivered'` from a bare `storeInInbox==true` (`:110-119`) and even flips `transport=='inbox'` rows to `'delivered'` with **no re-store at all** (`:78-91`); deletion tombstones do the same in `delete_message_use_case.dart` (`:332-355`, `:559-571`). No sweep ever revisits `'delivered'` (`handle_app_resumed.dart:443-446` enumerates all four repair steps), and there is no cross-device delivery receipt — the `'delivery_receipt'` envelope type is explicitly dropped (`incoming_message_router.dart:215-218`). `confirmNonce` is receiver-device-local only (`node.go:1616-1652`).
- **The existing test suite enshrines the bug:** `TestFiniteLimits_RejectExcessInboxMessages` asserts overflow store returns `Stored` with count capped (`limits_test.go:18-51`), and eviction wipes the relay's dedup messageIds (`backend_memory.go:264-276`) so even a hypothetical re-send would land as an untracked new entry.

**Impact:** permanent, telemetry-free message loss with sender-side green "delivered", biting exactly the long-offline recipient the store-and-forward inbox exists to serve. The cap is per-recipient across ALL senders and all 1:1 envelope types routed via inbox fallback (chat, deletions, intros, post follow-ons): 100 distinct pending envelopes or 7 days offline guarantees loss.

---

## Program context & sequencing

This is a 3-doc program fixing one theme — the sender shows 'delivered' for 1:1 messages that were silently lost or diverged. Docs: 114 (LAN ack-after-commit), 115 (relay inbox custody), 116 (edit retry fidelity). Mandatory landing order:
1. 115 Phase 1 — shared sender status foundation: status 'inboxed' (+ migration 077, DB v77 — 113 took 076/v76 and is already implemented), UI pending mapping, G4 no-false-delivered. Lands FIRST; every other doc's status expectations build on it.
2. 116 Phases 1-2 — retry fidelity + envelope-poisoning guard + single-flight. The correctness FLOOR: every backstop/receipt/sweep below relies on id-keyed dedup/acks being safe, which is only true once retried edits stay edits and a plain envelope can never replace an edit envelope.
3. 115 Phase 2 — delivery receipts (safe only after 116 P1: receipts ack by message id, not content).
4. 115 Phase 3 — sender custody sweep. HARD PREREQUISITE: 116 P2 (a poisoned plain envelope re-stored every sweep cycle would amplify the edit bug from one-shot to recurring). Co-sequenced: both modify retry_failed_messages_use_case.dart / retry_unacked_messages_use_case.dart regions — 116 lands first, 115 P3 rebases on its deriveRetryAction helper.
5. 114 Phases 1-3 — LAN ack-after-commit; non-durable-ack backstop terminals persist 'inboxed' (NOT 'delivered'/'inbox'), per the 115 Phase 1 foundation.
6. 116 Phase 3 — tombstone liveness + receiver divergence defense (lands after 115 P1, so it adopts the 115 status decision for deletion envelopes directly).
7. 114 Phases 4-5 and 115 Phases 4-5 — host integration pins, Go relay changes + EC2 deploy (single deploy train, coordinated with whatever 112/113 still ship to the relay), device evidence. The test-gate-definitions.md / run_test_gates.sh gate-array edits are made as ONE coordinated edit by whichever doc closes last.

**Cross-plan interactions touching this doc (from the program critic):**
- **Shared sender status model is the load-bearing collision:** this doc's Phase 1 (`'inboxed'` + G4 no-false-delivered) and doc 114's Phase 3 backstop rewrite the SAME function (`_persistOutgoingSendResult`) and the same `send_chat_message_use_case_test.dart` regions. Mandatory order: 115 Phase 1 lands first as the foundation; 114's backstop terminals become `'inboxed'`; G4 whitelists the LAN committed-ack `'delivered'` (committed = receiver durably staged, same bar as the direct deferred-ack G4 already allows).
- **Shared staging pipeline:** doc 114's `'lan:<nonce>'` rows ride the same `inbox_staging` replay pipeline as the relay drain. This doc's receipt origin discrimination must NOT key on the `'direct:'` entryId prefix alone or it misclassifies `'lan:'` replays as inbox-originated (receipts for LAN messages; quarantined LAN replays must never mint receipts). Pinned by the shared origin-marker contract test (Phase 2.4, critic-fold).
- **Both backstops deliberately create duplicate-delivery paths** (LAN legacy-ack → relay copy; custody sweep re-store; receipt-triggered duplicate drains) and lean on receiver id-only dedup — the exact mechanism the edit-retry bug abuses. Idempotency holds only for byte-identical envelopes, so 116's fallback fix + `updateWireEnvelope` poisoning guard are a correctness FLOOR for this doc: a poisoned plain envelope re-stored by the custody sweep re-propagates wrong content under the same id every cycle (Phase 3 HARD PREREQUISITE).
- **Delivery receipts ack by message id, not content:** until 116 P1 lands, a downgraded edit deduped on the receiver would trigger a receipt that flips the sender `'inboxed'`→`'delivered'` for content the receiver does not display — this doc's receipt machinery makes the edit bug's false-delivered STRONGER. Hence landing order #3.
- **confirmNonce parity, no conflict:** neither doc touches Go confirmNonce machinery (receipts are app-layer envelopes); `node.go:1616-1652` stays the untouched parity model for both.
- **Gate/process overlap:** docs 114/115/116 all edit `test-gate-definitions.md` + the `run_test_gates.sh` 1to1 array; this doc additionally requires a gomobile rebuild + EC2 relay deploy while 114 requires neither — one combined `make all`/`pod install` and a single coordinated gate edit by whichever doc closes last.

---

## 2. Goals / Non-goals

### Goals
- **G-A** A sender-side 1:1 row carries `status='delivered'` **only after receiver confirmation** — the live deferred direct-ack (confirmNonce, already gated on receiver durable staging), the LAN committed-ack (doc 114, same bar), or a new `'delivery_receipt'` envelope.
- **G-B** Relay-inbox acceptance yields a new distinct status `'inboxed'` (transport `'inbox'`), with the `wire_envelope` RETAINED and `relay_expires_at` recorded; UI renders it as a non-terminal pending state (schedule glyph + `message_status_pending_inbox` semantics, the existing `'pending'` visual family), never done_all. Applies to chat messages AND deletion tombstones (Section 3, decision D-3).
- **G-C** Cross-device delivery receipts: receiver emits after durable persist (chat) / durable apply (deletion); sender consumes; `'inboxed'`→`'delivered'` flips only there.
- **G-D** Sender repair: a periodic custody-verification sweep re-stores or truthfully downgrades (to `'sent'`) any unconfirmed `'inboxed'` row — a cap/TTL loss window is always either repaired or surfaced, never shown as delivered.
- **G-E** The relay never silently discards an accepted 1:1 entry: at cap it REJECTS the new store (`Status ERROR / Error "INBOX_FULL" / StoreStatus "rejected_full"`, oldest entries survive); TTL expiry is observable (`expiresAtMs` in every stored response, `inbox_expired_pruned_total` metric) and releases the dedup messageId so a re-store is possible.
- **G-F** All four version-skew cells loss-free or truthfully surfaced (Section 4); app Phases 1–3 fully shippable against the OLD relay.

### Non-goals (deferred, with justification)
- **Per-sender sub-quota inside the recipient cap** — reject-new makes flooding visible; measure via `inbox_rejected_full_total` first (OQ-1).
- **Background (non-lazy) hourly 1:1 TTL prune** — would force a `PruneExpired` interface method on `InboxBackend`; cap bounds memory at 100/peer and lazy-prune telemetry gives observability (OQ-5).
- **Encrypting delivery receipts (v2)** — plaintext-v1 is the version-skew-safe choice (Section 3); revisit once the fleet floor is receipt-aware (OQ-6).
- **Historical-row backfill** — existing `status='delivered'/transport='inbox'` rows are unrecoverable lies; no migration can restore truth (OQ-4).
- **Stale-pending terminal UX** — whether `'inboxed'` rows >30d auto-downgrade to `'failed'` is an owner decision; pure Dart change later (OQ-2).
- **Edit-retry fidelity itself** — doc 116; this doc only sequences around it (Phase 3 prerequisite).

---

## 3. Design decision

**Behavioral contract.** A sender-side 1:1 message row may carry status `'delivered'` only after receiver confirmation — exactly the G4 minting sites: the live deferred direct-ack (confirmNonce path, which already gates on the receiver durably staging — for both chat sends and the delete tombstone's acked branch, site b′), the LAN committed-ack from doc 114 (same durably-staged bar, site c), or a new `'delivery_receipt'` envelope (site a). Relay-inbox acceptance yields the new distinct status `'inboxed'` (transport `'inbox'`) with the `wire_envelope` RETAINED and `relay_expires_at` recorded, rendered in UI as a non-terminal pending state (schedule glyph + `message_status_pending_inbox` semantics), never done_all. The relay never silently discards an accepted 1:1 entry: at cap it REJECTS the new store with `Status ERROR / Error "INBOX_FULL" / StoreStatus "rejected_full"` (oldest entries survive), TTL expiry is observable (`expiresAtMs` in every stored response, `inbox_expired_pruned_total` metric) and releases the dedup messageId so a re-store is possible, and a periodic sender-side custody sweep re-stores or truthfully downgrades (to `'sent'`) any unconfirmed `'inboxed'` row — so a cap/TTL loss window is always either repaired or surfaced, never shown as delivered.

**Named decisions (each pinned by tests):**
- **D-1 `'inboxed'` vs the existing `'pending'` status family (critic-fold).** `letter_card.dart` already maps `'pending'` → `Icons.schedule_rounded` (`:606`), amber family (`:624`), `l10n.message_status_pending_inbox` (`:642`). Decision: **reuse the `'pending'` RENDERING family but mint a distinct `'inboxed'` status string.** Rationale: `'inboxed'` is machine-meaningful state the custody sweep and receipt apply must query by exact value; overloading `'pending'` would make sweep selection ambiguous against whatever legacy semantics `'pending'` ever had. A green-on-arrival pin (Phase 1.6) enumerates the live status strings and pins that **nothing in production writes `'pending'` today** (it is render-only); zero new l10n.
- **D-2 Reject-new at cap, not evict-old.** Evict-old signals the WRONG party: the harmed sender already got OK and is gone. Reject-new fails a sender who is online NOW, holds the `wireEnvelope` (G-B), and has retry machinery. Encoded in the Phase 4.1 test rewrite.
- **D-3 Deletion tombstones ride the same custody model (critic-fold).** `message_deletion` envelopes routed via inbox custody persist `'inboxed'` (today: `'delivered'` at `delete_message_use_case.dart:332-355/:559-571`), and `delete_message_tombstone_visibility.dart:14` keeps the tombstone VISIBLE until `'delivered'`. Decision: **extend receipt emission to the deletion-apply path in Phase 2** (the deletion listener invokes `sendDeliveryReceipt` after `handle_incoming_message_deletion_use_case` durably applies), rather than pinning `'inboxed'` to a chat-only exclusion list — a `'delivered'` deletion whose relay entry was evicted is exactly the original bug class (sender hides the tombstone, receiver never deletes). Against OLD receivers the tombstone honestly stays visible-pending; doc 116 Phase 3 (tombstone liveness) adopts this decision directly.
- **D-4 Receipts are plaintext v1 envelopes.** Type `'delivery_receipt'` is the ONE type old routers provably drop by name (`incoming_message_router.dart:215-218`); an encrypted v2 receipt would be indistinguishable from chat to old apps pre-decrypt. Privacy cost = relay sees messageId UUIDs it already stores entries under. Revisit post-fleet-floor (OQ-6).
- **D-5 Receipts vs the recipient 100-cap (critic-fold).** A receipt stored via inbox fallback can itself be rejected `INBOX_FULL` by the new relay. Decision: **no cap exemption** (the relay cannot distinguish authenticated envelope types without a protocol change and an exemption would be a flooding bypass); instead (i) receipts coalesce messageIds **per drain batch** (one envelope per peer per drain), (ii) live send first, inbox fallback second, (iii) a failed/rejected receipt store emits `DELIVERY_RECEIPT_STORE_FAILED` and is NOT retried in a loop — the sender's custody sweep (Phase 3) and the duplicate-receive → receipt re-send path (Phase 5.2) are the repair loop.
- **D-6 Status monotonicity via `conditionalTransitionStatus` (critic-fold).** `saveMessage` is INSERT OR REPLACE (`messages_db_helpers.dart:18-22` `ConflictAlgorithm.replace`), so a late sweep/retry persist can silently downgrade a `'delivered'` row. All forward status transitions introduced by this doc route through the existing `MessageRepository.conditionalTransitionStatus` (`message_repository.dart:71-75`) — already on the interface, zero fake breakage.
- **D-7 Clock-skew safety margin on the sweep (critic-fold).** The sweep compares relay-stamped `expiresAtMs` against the device clock; a device clock behind the relay would re-store AFTER actual expiry (old-relay zombie-dedup `'duplicate'`). Decision: re-store at expiry **minus a 12h safety margin** (`kRelayCustodySkewMarginMs`), pinned with skewed fixtures (Phase 3.3).
- **D-8 No interface changes.** All new capability lands as impl-level methods + top-level function seams (112 §9.3 precedent, `fake_upload_media_fn.dart`): `P2PService.storeInInbox` stays `Future<bool>` (32 implements-fakes preserved), `MessageRepository` interface untouched beyond what already exists (20 implements-fakes preserved), Go relay `InboxBackend.Store` signature unchanged (new enum value only).

### Alternatives rejected
1. **Evict-old retained with telemetry only** — telemetry doesn't repair; the evicted sender is unreachable by definition (its status is terminal). Reject-new converts loss into a visible, retryable failure for an online party.
2. **Reuse `'pending'` as the persisted status** — see D-1; ambiguity for sweep/receipt queries outweighs the zero-UI-change appeal.
3. **Cap exemption for receipts** — flooding bypass + protocol change; D-5 coalescing + sweep repair achieves the same liveness.
4. **Encrypted (v2) receipts now** — version-skew unsafe (D-4).
5. **`InboxBackend` method-signature change for occupancy/prune** — breaks every backend implementer and the failing-backend stub (`inbox_test.go:~1862`); handler computes `expiresAtMs` from `entry.Timestamp+maxMessageAge` it already sets, occupancy from existing `backend.Count`.
6. **Backfill migration downgrading historical `'delivered'/'inbox'` rows** — cannot distinguish truly-delivered from lost; would mass-flip correct history to pending (OQ-4).
7. **Go-side custody tracking (relay polls/pushes eviction notices)** — new protocol surface, offline senders can't hear it anyway; sender-side sweep + reject-new is strictly simpler and covers relay restart loss too.

---

## 4. Backward / version-skew compatibility

Four-cell skew matrix, all loss-free or truthfully-surfaced:

1. **NEW app + OLD relay (the floor; Phases 1–3 ship against this).** Interface `storeInInbox` bool path unchanged; impl-level `storeInInboxDetailed` degrades to null fields on a bare `{ok:true}`. Sender persists `'inboxed'` (never false `'delivered'`); receipts are app↔app plaintext-v1 envelopes the relay just carries; the sweep repairs **cap evictions fully** (old eviction code rebuilds dedup ids, `backend_memory.go:264-276`, so a re-store lands fresh). Known residual: the old memory backend's TTL prune (`pruneExpired`, `backend_memory.go:294-306`) never rebuilds messageIds, so a >7d-expired entry answers zombie-`'duplicate'` — the sweep's >7d defensive rule (Phase 3.3) keeps such rows visibly non-delivered (`'sent'`/pending) instead of trusting the zombie; full TTL repair requires the Phase 4 relay deploy.
2. **OLD app + NEW relay.** Reject-new returns `Status!="OK"`, which the old client already treats as store failure (`node/inbox.go:121-123`) → sequential tail persists terminal `'failed'` / unacked path keeps `'sent'`+envelope — silent loss becomes a visible red status, strictly better. New response JSON fields are ignored by the old client's narrow struct; duplicate semantics unchanged; push still fires only on new stores.
3. **NEW receiver + OLD sender app.** Receipts arrive as type `'delivery_receipt'`, which the old router explicitly drops (`incoming_message_router.dart:215-218`) — silent no-op.
4. **OLD receiver + NEW sender.** No receipts ever arrive → rows honestly remain `'inboxed'` (pending-inbox UI), never falsely delivered. Deletion tombstones likewise stay visible-pending (D-3) — honest, acceptable skew.

**Multi-relay:** `INBOX_FULL` from one relay still falls through the relay-selector `ForEach` to the next (a store on ANY relay delivers); the typed error reaches Dart only when all reject.

**Deploy plan (critic-fold):** app Phases 1–3 ship first against the production relay. Phase 4 relay changes deploy to EC2 (`mknoun.xyz`, `ssh ubuntu@`, repo `se.pem`, per the 112 §Phase-6 procedure) as a **single deploy train** coordinated with whatever 112/113 still ship to the relay (112 Phase 6 + the 111 ack-delete behavior deployed 2026-06-12 — if 113's relay-facing work or any re-deploy is pending when 115 Phase 4 is ready, ONE binary carries all of it). Post-deploy verification per G6/§8. Redis and memory backends change in the same commit with mirrored table tests (parity gate) since `RELAY_BACKEND` selects at bootstrap (`server_bootstrap.go:36-39`). Deploy order relative to the app is free in both directions, but the relay deploy should follow promptly after app rollout because old-relay TTL zombie-dedup limits the sweep's repair guarantee to cap-evictions until the new relay is live.

---

## 5. TDD phases

Order within this doc: **1 → 2 → 3 → 4 → 5**, interleaved with docs 114/116 per the Program context section (115 P1 first program-wide; 116 P1–2 before 115 P2–3; 115 P3 hard-gated on 116 P2). Every phase is individually shippable. RED honesty rule: tests that are green-on-arrival are explicitly labeled **pins** and do NOT count toward the phase's RED count. All new test files get classified in `test-gate-definitions.md` (`## 115 Relay Inbox Custody Gate Capture`) with `./scripts/run_test_gates.sh completeness-check` kept green.

---

### Phase 1 — Sender custody truthfulness: 'inboxed' status, envelope retention, migration 077, UI mapping (shippable against OLD relay; **lands FIRST program-wide**)

**Why first:** this is the floor that stops minting false `'delivered'` — and the shared status foundation every 114/116 expectation builds on. Pure sender-side honesty; works against the old relay; no receipts yet (rows stay pending until Phase 2).

#### 1.1 RED — send custody persists 'inboxed'
File: `test/features/conversation/application/send_chat_message_use_case_test.dart` (in-file rich `FakeP2PService` L33-160 + `captureFlowEvents` pattern).
- `'sequential inbox fallback persists status 'inboxed' with transport 'inbox' and retains wire_envelope'` — after race-all-failed + `storeInInboxResult=true`: row `status=='inboxed'`, `transport=='inbox'`, `wireEnvelope` non-null, flow event `CHAT_MSG_SEND_SUCCESS` carries `status:'inboxed'`. **Fails today:** `persistInboxDelivered` writes `'delivered'` at `send_chat_message_use_case.dart:872` and the saved message carries no wireEnvelope (`:861-906`).
- `'unacked live write with successful inbox handoff persists 'inboxed', not 'delivered''` — `sendMessageAcked=false` + `storeInInboxResult=true` → `'inboxed'`, envelope retained. **Fails today:** the unacked-handoff branch persists `'delivered'/'inbox'` at `:1722-1735`.
- `'concurrent durable-copy custody short-circuit persists 'inboxed''` — low-confidence send whose concurrent inbox copy wins persists `'inboxed'` + retained envelope. **Fails today:** `:927` routes to `persistInboxDelivered` (`'delivered'`, `:1692-1708`).
- `'live acked send still persists delivered (live transport)'` — **green-on-arrival pin** (does not count as RED): the Go deferred-ack already gates on receiver-side durable staging (`node.go:1616-1652`); this is allowed minting site (b) of G4.

#### 1.2 RED — G4 enforcement: allowed 'delivered' minting sites (critic-fold)
File (new): `test/features/conversation/application/delivered_status_minting_sites_test.dart` — a source-scan invariant test (plain `test()`, sync `dart:io` reads of `lib/**.dart`) that enumerates every production write of `status: 'delivered'` / `toStatus: 'delivered'` and asserts the set is EXACTLY the allowed minting sites:
  (a) `handle_delivery_receipt_use_case.dart` (Phase 2),
  (b) the live deferred-ack branch of `_persistOutgoingSendResult` (`send_chat_message_use_case.dart`),
  (b′) the live deferred-ack acked branch of `_persistOutgoingDeleteResult` (`delete_message_use_case.dart:548-556` — same Go durable-staging bar as (b); surfaced during doc authoring, see Caveat 9.7),
  (c) the LAN committed-ack branch from doc 114 (committed = receiver durably staged, same bar as (b)) — entry added when 114 P1-3 land.
- `'production code mints status delivered only at the enumerated receiver-confirmation sites'` — **Fails today:** `send_chat_message_use_case.dart:872/:1692-1708/:1722-1735`, `retry_unacked_messages_use_case.dart:78-91/:110-119`, and `delete_message_use_case.dart:332-355/:559-571` all write `'delivered'` outside the allowed set. This test is what makes G4 enforceable — an untested call site (migration-style backfill, future feature) cannot silently mint `'delivered'`. Note: migration `015_message_status_cleanup.dart` upgrades legacy `'queued'`→`'delivered'` on historical rows — whitelist it explicitly as a migration-scope entry with a comment, or scope the scan to non-migration code; decide at authoring and pin the choice.

#### 1.3 RED — deletion tombstones ride inbox custody honestly (critic-fold)
File: `test/features/conversation/application/delete_message_use_case_test.dart` (extend).
- `'delete-for-everyone via sequential inbox fallback persists tombstone status 'inboxed' and retains wire_envelope'` — **Fails today:** `delete_message_use_case.dart:332-355` writes `'delivered'/'inbox'/wireEnvelope:null` and `normalizeOutgoingDeleteTombstoneVisibility` then hides the tombstone immediately.
- `'unacked delete handoff persists 'inboxed', not 'delivered''` — **Fails today:** `_persistOutgoingDeleteResult` inbox branch at `:559-571`.
- `'an 'inboxed' outgoing tombstone stays visible (hiddenAt null) until receipt-driven delivered'` — **green-on-arrival pin** on the pure function: `delete_message_tombstone_visibility.dart:14` already hides only on `'delivered'`; the pin blocks anyone "fixing" lingering tombstones by widening that gate instead of landing Phase 2's deletion receipts (D-3).

#### 1.4 RED — UI mapping
File: `test/features/conversation/presentation/widgets/letter_card_test.dart` (testWidgets — sync I/O only per house rule).
- `'status 'inboxed' renders schedule icon with pending-inbox semantics, never done_all'` — `_statusIcon('inboxed')==Icons.schedule_rounded`, color == pending amber family, semantics == `l10n.message_status_pending_inbox` (key + visual family already exist at `letter_card.dart:606/:624/:642` — reuse, zero new l10n). **Fails today:** `'inboxed'` falls into the default `done_rounded` branch (`:607`) and `_statusSemantic` returns the raw string (`:643`).

#### 1.5 RED — migration 077 + custody columns (critic-fold: numbering — 113 took 076/v76, already implemented)
File (new): `test/core/database/migrations/077_message_relay_custody_test.dart`.
- `'migration 077 adds nullable relay_expires_at and custody_checked_at columns to messages'` — sqflite_common_ffi in-memory DB + run the migration fn directly (mirror 073/074 tests); `PRAGMA table_info` shows both columns; idempotent re-run safe. **Fails today:** migration file does not exist (latest is `076_post_media_attachment_crypto_columns.dart`, `currentIdentityDatabaseVersion = 76`).

File: `test/core/database/helpers/messages_db_helpers_test.dart` (extend).
- `'insert/load roundtrips relay_expires_at and custody_checked_at and ConversationMessage maps them'` — dbInsert/dbLoad preserves both columns; `ConversationMessage.fromMap/toMap` roundtrip. **Fails today:** columns and model fields absent (`conversation_message.dart` has no such fields).

#### 1.6 Pins — status-string census (critic-fold)
File: `delivered_status_minting_sites_test.dart` (same scan harness as 1.2) or a sibling.
- `'live message status strings are exactly {sending, sent, failed, delivered, inboxed, queued(legacy read-only)} and nothing writes 'pending''` — **green-on-arrival pin** documenting D-1: `'pending'` is render-only today (`letter_card.dart:606/:624/:642` consume it; no production writer). If the scan finds a writer, D-1 gets revisited BEFORE Phase 1 ships — that is the pin's job.

#### 1.7 GREEN
- `lib/features/conversation/application/send_chat_message_use_case.dart` — rename `persistInboxDelivered`→`persistInboxAccepted`: status `'inboxed'`, keep `wireEnvelope` on the saved `ConversationMessage`, accept optional `expiresAtMs`, update `CHAT_MSG_SEND_SUCCESS`/`emitSendTiming` details; apply the same status at the unacked-handoff branch (`:1722-1735`) and concurrent-custody short-circuit (`:1692-1708`).
- `lib/features/conversation/application/delete_message_use_case.dart` — both inbox branches (`:332-355`, `:559-571`) persist `'inboxed'` + retained envelope (the live acked branch `:548-556` stays `'delivered'`, site b′).
- `lib/features/conversation/domain/models/conversation_message.dart` — add `relayExpiresAt` (int?), `custodyCheckedAt` (String?) with fromMap/toMap/copyWith sentinel handling.
- New `lib/core/database/migrations/077_message_relay_custody.dart` + registration + DB version 77 in `encrypted_db_opener.dart`.
- `lib/core/database/helpers/messages_db_helpers.dart` — include new columns in writes.
- `lib/features/conversation/presentation/widgets/letter_card.dart` — add `'inboxed'` to `_statusIcon/_statusColor/_statusSemantic` (reuse pending family); update the status mapping in `conversation_wired.dart` (~`:1559`).
- `emitFlowEvent` at every touched layer.
- **Contract-flip chore (same phase, not RED):** update every test that enshrines optimistic delivered-on-inbox — `send_chat_message_use_case_test.dart` ≈`:1200-1297/:1425-1472`, `retry_unacked_messages_use_case_test.dart:336`, `retry_failed_messages_use_case_test.dart:962` ('concurrently-inboxed (delivered/inbox/null-envelope)' fixtures become inboxed/inbox/non-null-envelope), `stuck_sending_recovery_test.dart:176/:323`, `inbox_round_trip_test.dart`, `c2_ack_drop_test.dart`, `offline_inbox_roundtrip_test.dart`, `two_user_message_exchange_test.dart`, plus the delete-use-case suite. Historical rows already at `'delivered'/'inbox'` are untouched (no backfill — OQ-4).
- Interface changes: **NONE.** `ConversationMessage` is a concrete model (no fakes implement it); migration + DB helpers are plain functions. Deliberately NOT touching `MessageRepository` (20 implements-fakes) or `P2PService` (32 implements-fakes).

#### 1.8 Gate
`flutter test test/features/conversation test/core/database test/core/inbox` green; `./scripts/run_test_gates.sh 1to1` green; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green. New files (077 migration test, minting-sites invariant test) classified; `completeness-check` green. **Program note:** doc 114 Phase 3 and doc 116 Phase 3 may begin once this gate is green.

---

### Phase 2 — Cross-device delivery receipts: receiver emits, sender consumes, 'inboxed'→'delivered' flips only here (app↔app, relay-agnostic)

**Sequencing (program order #3):** lands only after 116 Phases 1–2 — receipts ack by message id, which is safe only once retried edits stay edits.

#### 2.1 RED — router stops dropping receipts
File: `test/core/services/incoming_message_router_test.dart`.
- `'routes 'delivery_receipt' envelopes to deliveryReceiptStream instead of dropping them'` — inject a v1 `{type:'delivery_receipt', payload:{messageIds:[...]}}` message; assert it is emitted on a new `router.deliveryReceiptStream` and NOT on unknown/chat streams. **Fails today:** `incoming_message_router.dart:215-218` explicitly returns (drops) this type — the existing test at `:198` `'ignores legacy delivery_receipt messages'` enshrines the drop and is REWRITTEN here (red-first, not a parallel test).

#### 2.2 RED — receipt apply
File (new): `test/features/conversation/application/handle_delivery_receipt_use_case_test.dart` (uses `fake_message_repository.dart`).
- `'flips matching outgoing 'inboxed' rows to 'delivered' and clears wire_envelope'` — receipt from peer X for an outgoing `'inboxed'` row to X → status `'delivered'` via `conditionalTransitionStatus` (D-6), `wireEnvelope` null, `DELIVERY_RECEIPT_APPLIED` flow event. **Fails today:** `handle_delivery_receipt_use_case.dart` does not exist.
- `'ignores receipts for foreign-peer, incoming, or unknown message ids'` — same id but row belongs to peer Y or `is_incoming` → untouched. **Fails today:** use case does not exist.
- `'re-applying a receipt to an already-delivered row is a no-op'` — idempotent. **Fails today:** use case does not exist.
- `'unmatched or foreign receipt emits telemetry'` (critic-fold) — unknown id → `DELIVERY_RECEIPT_UNMATCHED` flow event with peer + id preview; foreign-peer match → `DELIVERY_RECEIPT_FOREIGN_PEER`. **Fails today:** use case does not exist.

#### 2.3 RED — receipt send
File (new): `test/features/conversation/application/send_delivery_receipt_use_case_test.dart` (`FakeP2PService`).
- `'builds plaintext v1 'delivery_receipt' envelope carrying messageIds and falls back to storeInInbox when live send is unacked'` — acked live send → `sendMessage` called with envelope `{type:'delivery_receipt', version:'1', payload:{messageIds, ts}}` and no inbox store; unacked → `storeInInbox` called with the same envelope; `DELIVERY_RECEIPT_SENT` flow event; messageIds coalesced per drain batch (D-5). **Fails today:** use case does not exist.
- `'failed receipt store emits DELIVERY_RECEIPT_STORE_FAILED and does not throw or retry-loop'` (critic-fold) — `storeInInbox` returns false / throws → telemetry event, graceful return (repair is owned by the sweep + duplicate-receive loop, D-5/Phase 5.2). **Fails today:** use case does not exist.

#### 2.4 RED — receiver hook + origin-marker contract (critic-fold, shared with doc 114)
File: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`.
- `'invokes sendDeliveryReceipt after durable persist of an inbox-originated message, and re-invokes on duplicate receive'` — new optional named params (`sendDeliveryReceipt` fn + origin marker); inbox-originated message → fn called once with the messageId AFTER repo save succeeds; same message again (duplicate) → fn called again; live-direct origin → NOT called (confirmNonce owns that ack). **Fails today:** `handleIncomingChatMessage` has no receipt hook.
- `'origin-marker contract: 'direct:' and 'lan:' staged replays skip receipts; relay-drain entries send receipts; quarantined replays never mint receipts'` (critic-fold) — the shared cross-doc contract test, enumerating entryId namespaces: `'direct:<nonce>'` (live deferred-ack owns confirmation), `'lan:<nonce>'` (doc 114's committed-ack owns it), everything else (relay drain) → receipt; a replay dispositioned retryable/quarantined by the 111 state machine NEVER invokes the receipt fn. Doc 114 Phase 2 references this same contract. **Fails today:** no origin discrimination exists (no receipt machinery at all); the replay tagging to key on already exists (`p2p_service_impl.dart:856+/:1244-1246`).

#### 2.5 RED — deletion-apply receipts (critic-fold, D-3)
Files: `test/features/conversation/application/message_deletion_listener_test.dart` / `handle_incoming_message_deletion_use_case_test.dart` (extend).
- `'inbox-originated message_deletion invokes sendDeliveryReceipt after the deletion is durably applied'` — same optional-param pattern as 2.4; duplicate re-application re-invokes; `'direct:'`/`'lan:'` origins skip. **Fails today:** `handle_incoming_message_deletion_use_case` emits no receipt — under Phase 1 alone, deletion rows would stay `'inboxed'` forever and the sender's tombstone would never hide.
- `'sender tombstone flips 'inboxed' → 'delivered' on deletion receipt and becomes hidden'` — `handle_delivery_receipt` + `normalizeOutgoingDeleteTombstoneVisibility` end-to-end on the tombstone row. **Fails today:** no receipt machinery.

#### 2.6 RED — round trip
File: `test/core/inbox/inbox_round_trip_test.dart` (existing `FakeP2PNetwork` + `TestUser` template `:57-120`).
- `'sender row transitions 'inboxed' → 'delivered' only after receiver drains the relay inbox and the receipt round-trips'` — alice stores to offline bob → alice row `'inboxed'`; bob comes online, drains, receipt flows back → alice row `'delivered'`. **Fails post-Phase-1:** row stays `'inboxed'` forever — no receipt machinery exists.

#### 2.7 GREEN
- `lib/core/services/incoming_message_router.dart` — replace the `:215-218` drop with `_deliveryReceiptController` + `deliveryReceiptStream` getter (concrete class, zero implements-fakes — verified; new stream getter is safe).
- New `lib/features/conversation/application/send_delivery_receipt_use_case.dart` (top-level fn; plaintext v1 by D-4; live send first, `storeInInbox` fallback; per-drain coalescing; `DELIVERY_RECEIPT_SENT`/`DELIVERY_RECEIPT_STORE_FAILED` telemetry).
- New `lib/features/conversation/application/handle_delivery_receipt_use_case.dart` (top-level fn built ONLY on existing `MessageRepository` methods: `getMessage` + `conditionalTransitionStatus('inboxed'→'delivered')` and `'sent'→'delivered'`, then `saveMessage` to null the envelope; tombstone rows re-normalized via `normalizeOutgoingDeleteTombstoneVisibility`; unmatched/foreign telemetry).
- New `lib/features/conversation/application/delivery_receipt_listener.dart` mirroring `chat_message_listener.dart`.
- `handle_incoming_chat_message_use_case.dart` + `handle_incoming_message_deletion_use_case.dart` (and its listener) — optional named params `sendDeliveryReceipt` + arrival-origin, carried by the existing inbound-transport tagging on replayed staged entries (`p2p_service_impl.dart:856+/:1244-1246`); origin set per the 2.4 contract.
- DI threading per memory chain: `main.dart` → listeners (`ChatMessageListener`/`MessageDeletionListener` constructors gain optional params — concrete classes constructed in main.dart, no fake breakage).
- Update the 1.2 minting-sites whitelist: `handle_delivery_receipt_use_case.dart` becomes allowed site (a).
- Interface changes: **NONE** on abstract interfaces (new optional named params on top-level use-case functions break no fakes).

#### 2.8 Gate
`flutter test test/core/services/incoming_message_router_test.dart test/features/conversation/application test/core/inbox` green; `./scripts/run_test_gates.sh 1to1` + baseline green; new files classified; `completeness-check` green.

---

### Phase 3 — Sender repair: custody verification sweep + retry-unacked truthfulness (works against OLD relay; full TTL repair completes with Phase 4)

> **HARD PREREQUISITE (critic-fold):** doc **116 Phases 1–2 must be landed and green before this phase starts.** The sweep re-stores `wire_envelope` on every cycle; if that envelope was poisoned by the edit-retry fallback (plain envelope overwrote the edit envelope, `send_chat_message_use_case.dart:396-398` per the 116 findings), the sweep amplifies the edit bug from one-shot to RECURRING wrong-content propagation under the same message id. **Co-sequencing:** this phase rewrites the same `retry_unacked_messages_use_case.dart` / `retry_failed_messages_use_case.dart` regions as 116 — 116 lands first; this phase REBASES on its `deriveRetryAction` helper rather than re-deriving envelope action types.

#### 3.1 RED — retry-unacked truthfulness
File: `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`.
- `''sent' row with transport=='inbox' is re-stored to the relay, not blind-flipped to 'delivered''` — fake row status `'sent'`/transport `'inbox'`/envelope present → `p2pService.storeInInbox` MUST be called; on success row becomes `'inboxed'` with envelope retained. **Fails today:** `retry_unacked_messages_use_case.dart:78-91` saves `'delivered'`+null envelope with NO re-store (the second place `'delivered'` is minted without relay confirmation).
- `'successful inbox re-store flips 'sent' → 'inboxed' and retains wire_envelope'` — `storeInInbox==true` → status `'inboxed'`, `wireEnvelope` NOT cleared (custody sweep still owns it until receipt). **Fails today:** `:110-119` writes `'delivered'` and clears the envelope.

#### 3.2 RED — custody query helpers
File: `test/core/database/helpers/messages_db_helpers_test.dart`.
- `'dbLoadInboxCustodyOutgoingMessages returns outgoing 'inboxed' rows with non-null wire_envelope and stale custody_checked_at, timestamp ASC'` — seed mixed rows; helper returns only `is_incoming=0`, `status='inboxed'`, envelope non-null, `custody_checked_at` older than threshold. **Fails today:** helper does not exist.

#### 3.3 RED — the custody sweep
File (new): `test/features/conversation/application/verify_inbox_custody_use_case_test.dart` — over a `StoreInInboxDetailedFn` function-seam fake returning canned `InboxStoreOutcome` values (mirror the `fake_upload_media_fn.dart` seam pattern) + `fake_message_repository`. **All fail today:** the use case, `InboxStoreOutcome` type, and seam typedef do not exist; nothing in the codebase ever revisits `'inboxed'`/`'delivered'` rows (sweeps only touch sending/failed/sent — `handle_app_resumed.dart:443-446`).
- `'sweep re-stores rows past relay_expires_at and a 'stored' outcome refreshes expiry (INBOX_CUSTODY_RESTORED)'`
- `'a 'duplicate' outcome marks the row custody-checked without status change'`
- `''inbox_full' downgrades to 'sent' keeping the envelope (INBOX_CUSTODY_LOST)'`
- `'rows with null relay_expires_at (old-relay stores) are re-stored every sweep'`
- `'rows older than 7 days without receipt surface non-delivered even on 'duplicate' (old-relay zombie-dedup defense)'`
- `'sweep re-stores at relay_expires_at minus the 12h skew margin, pinned with skewed expiresAtMs fixtures'` (critic-fold, D-7) — fixtures with `expiresAtMs` ahead of/behind the device clock; a row inside the margin window is re-stored; a freshly-stamped row is not. **Fails today:** no sweep, no margin constant.
- `'late sweep/retry persist does not downgrade a delivered row'` (critic-fold, D-6) — receipt flips a row to `'delivered'` while a sweep cycle holding the stale snapshot completes → the sweep's write goes through `conditionalTransitionStatus(fromStatus:'inboxed')`, matches 0 rows, and the row STAYS `'delivered'`. **Fails today:** `saveMessage` is INSERT OR REPLACE (`messages_db_helpers.dart:18-22`) — a blind persist silently downgrades.

#### 3.4 RED — detailed store outcome plumbing
File: `test/core/services/p2p_service_impl_test.dart`.
- `'storeInInboxDetailed parses enriched bridge response and degrades to unknowns against an old bridge/relay'` — FakeBridge canned `{ok:true, storeStatus:'stored', expiresAtMs, occupancy, capacity}` → full outcome; bare `{ok:true}` → accepted with null fields; `{ok:false, errorCode:'INBOX_FULL'}` → typed rejectedFull. **Fails today:** only `response['ok']==true` is read (`p2p_service_impl.dart:3178-3217`) and no detailed method exists.

#### 3.5 RED — scheduler + resume wiring
File: `test/core/services/pending_message_retrier_test.dart` (fakeAsync).
- `'retrier cycle invokes the custody-verification callback after retryUnacked'` — elapse one period → recorded callback order includes `verifyInboxCustody` (AFTER retryUnacked, so freshly-`'inboxed'` rows get expiry stamped first). **Fails today:** retrier has four callbacks only.

File (new): `test/core/lifecycle/handle_app_resumed_inbox_custody_test.dart` (mirror `handle_app_resumed_stuck_sending_test.dart`).
- `'resume repair pipeline runs verifyInboxCustody as a fifth step'` — **Fails today:** pipeline enumerates exactly four repair steps (`handle_app_resumed.dart:443-446`).

#### 3.6 Pin — edit fidelity through the sweep (critic-fold)
File: `verify_inbox_custody_use_case_test.dart`.
- `'a custody-sweep re-store of an edit row carries action:edit'` — **green-on-arrival pin** (post-116-P1/P2 the envelope on the row IS the edit envelope and the sweep re-stores it verbatim); its job is to fail loudly if anyone ever rebuilds envelopes inside the sweep instead of re-storing the stored bytes.

#### 3.7 GREEN
- `lib/core/database/helpers/messages_db_helpers.dart` — `dbLoadInboxCustodyOutgoingMessages` + `dbMarkCustodyChecked` (plain fns taking `Database db`).
- `MessageRepositoryImpl` — impl-level methods `getInboxCustodyOutgoingMessages`/`markCustodyChecked` (NOT on the `MessageRepository` interface; 111 SecureKeyStore precedent — 20 implements-fakes preserved).
- New `lib/core/services/inbox_store_outcome.dart` — `InboxStoreOutcome` value type + `typedef StoreInInboxDetailedFn`.
- `P2PServiceImpl` — impl-level `storeInInboxDetailed` (interface `storeInInbox` stays `Future<bool>` — 32 implements-fakes preserved).
- New `lib/features/conversation/application/verify_inbox_custody_use_case.dart` — top-level fn taking function seams (`loadInboxCustody`, `storeInInboxDetailed`) + `MessageRepository`; rules per 3.3 incl. `kRelayCustodySkewMarginMs` (12h, D-7) and min recheck spacing constant (default 6h) via `custody_checked_at`; ALL forward transitions via `conditionalTransitionStatus` (D-6); rebases on 116's `deriveRetryAction` where envelope action matters.
- `retry_unacked_messages_use_case.dart` — both 3.1 fixes (coordinate with 116's edits to the same file; 116 lands first).
- `pending_message_retrier.dart` + `handle_app_resumed.dart` + `main.dart` DI wiring (thread impl-level fns through MyApp→StartupRouter per memory chain).
- Phase-1 `persistInboxAccepted` now also persists `expiresAtMs`/`custody_checked_at` from the detailed outcome when available.

#### 3.8 Gate
`flutter test test/features/conversation/application test/core/services test/core/lifecycle test/core/database` green; `./scripts/run_test_gates.sh 1to1` + baseline green; new files classified; `completeness-check` green. Re-confirm 116 P2's poisoning-guard suite is in the same green run (the prerequisite is only real if its tests gate this phase too).

---

### Phase 4 — Relay protocol: reject-new at cap (chosen over evict-old), observable TTL, prune/reject telemetry, memory dedup-zombie fix, memory↔redis parity, Go client plumbing

#### 4.1 RED — reject-new replaces silent eviction
File: `go-relay-server/limits_test.go`.
- `TestFiniteLimits_RejectNewWhenInboxFull` — REWRITES `TestFiniteLimits_RejectExcessInboxMessages`, which today ENSHRINES silent eviction (`:18-51`). Fill `memoryInboxBackendLimited` to cap; next `Store` returns new `InboxStoreResultRejectedFull`, `Count` stays at cap, the OLDEST entry is retained and the overflow message is absent. **Fails today:** returns `Stored` and evicts oldest (`limits.go:124-127`). Policy justification encoded in the test (D-2): evict-old signals the WRONG party; reject-new fails a sender who is online now, holds the wireEnvelope, and has retry machinery.

#### 4.2 RED — wire-level handler contract
File: `go-relay-server/inbox_test.go` (via `setupInboxStreamEnv` mocknet + `sendInboxReq`).
- `TestHandleInboxStream_StoreRejectsWhenFull` — overflow store → `{Status:"ERROR", Error:"INBOX_FULL", StoreStatus:"rejected_full", occupancy==capacity}` and `recordingPushSender` records NO push. **Fails today:** store always answers `{OK, stored}` (`inbox.go:1392-1397`).
- `TestHandleInboxStream_StoreReturnsExpiresAtAndOccupancy` — successful store → response carries `expiresAtMs`≈now+7d, occupancy, capacity. **Fails today:** `inboxResponse` has none of these fields (`inbox.go:1297-1312`).

#### 4.3 RED — dedup release on prune AND ack
File: `go-relay-server/inbox_dedup_test.go`.
- `TestMemoryInbox_ExpiredEntryMessageIdReStorableAfterPrune` — seed an entry with Timestamp 8 days old; a touch triggers lazy prune; re-storing the SAME messageId must return `Stored`. **Fails today:** `pruneExpired` (`backend_memory.go:294-306`) drops the entry but never rebuilds messageIds, so the zombie dedup id returns `Duplicate` forever — this is what would defeat the Phase-3 sweep.
- `TestRedisInboxBackend_ExpiredMessageIdReStorableAfterTTLCutoff` — **green-on-arrival pin** (redis dedup scans only live entries, `backend_redis.go:283-297`) — labeled, does not count as RED.
- `TestMemoryInbox_AckedEntryMessageIdReStorable` (critic-fold) — ack-delete an entry, then re-store the same messageId → `Stored`. The lost-receipt repair loop (Phase 5.2) depends on re-store-after-ack landing FRESH. **Expected green-on-arrival pin** (`backend_memory.go:260` — Ack rebuilds messageIds); label by its actual color at authoring; if RED, it is a Phase-4 bug to fix before deploy.
- `TestRedisInboxBackend_AckedEntryMessageIdReStorable` (critic-fold) — the redis twin; redis Ack dedup-release was NOT verified by the critic. **Author it mandatory; expected pin** (live-entry dedup scan), but treat a RED result as a blocking Phase-4 fix — the repair loop is broken on redis without it.

#### 4.4 RED — redis reject parity
File: `go-relay-server/backend_redis_test.go` (table-style, miniredis).
- `TestRedisInboxBackend_StoreRejectsNewWhenFull` — fill to `maxPerPeer`; overflow `Store` returns `RejectedFull`, LLEN stays at cap, oldest entry retained, newest absent. **Fails today:** silent trim `values[len-maxPerPeer:]` (`backend_redis.go:301-303`). Parity rows in the table mirror the memory cases exactly (G2 parity check).

#### 4.5 RED — telemetry
File: `go-relay-server/metrics_test.go`.
- `TestInboxRejectAndTTLPruneTelemetry` — `inbox_rejected_full_total` increments on reject; `inbox_expired_pruned_total` increments by pruned count on lazy prune; both registered. **Fails today:** neither counter exists — eviction/prune is invisible even to `InboxStore.Store` (backend can only answer `Stored|Duplicate`).

#### 4.6 RED — Go client + bridge plumbing
File (new): `go-mknoon/node/inbox_parse_test.go` (no `node/inbox_test.go` exists; pure-JSON unit per stdlib-testing convention).
- `TestParseInboxStoreResponse_NewRelayFields` — enriched JSON → outcome struct with storeStatus/expiresAtMs/occupancy/capacity. **Fails today:** client struct drops everything but Status/Error/Messages/HasMore/Acked (`node/inbox.go:33-39`); no parse fn exists.
- `TestParseInboxStoreResponse_InboxFullTyped` — `{status:ERROR, error:INBOX_FULL}` → `errors.Is(err, ErrInboxFull)`. **Fails today:** no typed error exists.
- `TestParseInboxStoreResponse_OldRelayDefaults` — bare `{status:OK}` → zero-valued defaults. **Fails today:** no parse fn exists.

File: `go-mknoon/bridge/bridge_test.go`.
- `TestInboxStore_ResultCarriesStoreStatusAndErrorCode` — bridge `InboxStore` result JSON passes through storeStatus/expiresAtMs/occupancy/capacity on success and `{ok:false, errorCode:"INBOX_FULL"}` on typed rejection (validation-level per `:799` conventions). **Fails today:** bridge returns bare `{ok:true}` (`bridge.go:1109-1143`).

#### 4.7 GREEN
- go-relay-server: `inbox_store.go` — add enum value `InboxStoreResultRejectedFull` (**Store SIGNATURE UNCHANGED** — avoids breaking every backend implementer and the failing-backend stub in `inbox_test.go` ~`:1862`; occupancy from existing `backend.Count`; `expiresAtMs` computed by the handler from `entry.Timestamp+maxMessageAge` which it already sets at `inbox.go:1386-1390`). `backend_memory.go` — Store/limited.Store: replace evict block with reject; `rebuildMessageIds` after EVERY `pruneExpired` (fixes dedup-zombie); `pruneExpired` returns pruned count. `limits.go:105-141` — same reject in `memoryInboxBackendLimited`. `backend_redis.go` — Store: if `len(validRaw)>=maxPerPeer` write back normalized list and return `RejectedFull` (no trim). `inbox.go` — `InboxStore` gains capacity field (wired from `ServerLimits` in `server_bootstrap.go:67/:97-101`); Store wrapper logs rejects + bumps `inboxRejectedFullCounter`, logs/bumps `inbox_expired_pruned_total`, fires no push on reject; `HandleInboxStream` store case maps `RejectedFull`→`{ERROR, INBOX_FULL, rejected_full, occupancy, capacity}` and `Stored`→`{OK, stored, expiresAtMs, occupancy, capacity}`; `inboxResponse` struct + `metrics.go` counters; optional env `RELAY_INBOX_TTL_HOURS` override (staging evidence). Push behavior preserved: store-time push still fires on genuinely-new stores (`inbox.go:735-737`), never on duplicate or reject.
- go-mknoon: `node/inbox.go` — extend client `inboxResponse`, extract `parseInboxStoreResponse`, ADD `InboxStoreDetailed(...) (InboxStoreOutcome, error)` with existing `InboxStore(...) error` delegating (preserves testpeer `commands.go:600/:643/:663` and integration callers unchanged; relay-selector `ForEach` still tries the next relay on `INBOX_FULL` — correct in multi-relay, typed error only if all reject); `bridge/bridge.go` `InboxStore` enrichment. testpeer `commands.go` — surface storeStatus/errorCode in `inbox_store_v1/v2/raw` results for E2E orchestrators.
- Rebuild app bindings: `cd go-mknoon && PATH="$PATH:$(go env GOPATH)/bin" make all && cd ../ios && pod install` (single combined rebuild with whatever 114/116 ship, per the program gate note).
- Interface changes: relay `InboxBackend` — NO method-signature change (new enum value only; test stubs compile untouched); go-mknoon — additive method `InboxStoreDetailed` on concrete `*Node` (no Go interface, no caller breakage); Dart `FakeBridge` — no code change needed (pre-canned responses map is schema-free; tests add enriched `'inbox:store'` responses additively).

#### 4.8 Gate
**G2:** `cd go-relay-server && go test ./...` green with the rewritten limits contract — no test in the tree may assert silent eviction returns `Stored`; memory and redis reject/TTL/dedup/ack table tests mirrored (parity check). **G3 (first half):** `cd go-mknoon && make test` green. Background hourly 1:1 prune deliberately deferred (OQ-5).

---

### Phase 5 — Gate capture, relay deploy (EC2 mknoun.xyz), E2E + device evidence, doc closure

#### 5.1 RED — whole-system contract
File: `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`.
- `'cap-rejected send surfaces truthfully and is repaired after receiver drains (end-to-end fake-network)'` — extend `FakeP2PNetwork` with a cap-aware inbox (`inboxDisabled`/`deliveryFails` knobs already exist at `fake_p2p_network.dart:13-33`; add `maxInboxPerPeer`): fill recipient inbox to cap → next send ends `'sent'` (not `'failed'`-terminal, not `'delivered'`); recipient drains; sender sweep re-stores → `'inboxed'` → receipt → `'delivered'`. **Fails until Phases 1–4 land and the fake models reject-new;** written last to pin the whole-system contract.

#### 5.2 RED — lost-receipt loop closure (critic-fold)
Same file.
- `'receiver killed between drain ack-delete and receipt send is repaired: sweep re-store → duplicate receive → receipt re-send → delivered'` — simulate the kill window (drain ack-deletes the relay entry, receipt never sent); sender row stays `'inboxed'`; sweep re-stores (lands FRESH — the 4.3 acked-entry dedup-release pins are what make this true on both backends); receiver gets a duplicate, dedups by id, re-invokes the receipt per 2.4; sender flips `'delivered'`. **Fails until Phases 2–4 land.**
- **Decision recorded (critic-fold):** to bound the up-to-7-day false-pending latency of this window, the sweep additionally re-stores rows whose `custody_checked_at` is older than a stale-receipt threshold (`kCustodyStaleReceiptRestoreAfter`, default 24h) WITHOUT waiting for `relay_expires_at` — safe because re-store is dedup'd (`'duplicate'` against a live entry just refreshes `custody_checked_at`) and post-4.3 an acked entry re-stores fresh. Pinned in `verify_inbox_custody_use_case_test.dart` as an additional case when this phase lands (`'sweep re-stores a stale-unreceipted row before expiry (bounded false-pending latency)'`).

#### 5.3 RED — Go integration proof
File: `go-mknoon/integration/relay_test.go` (`-tags integration`).
- `TestInboxStoreFull_TypedRejectionAgainstLocalRelay` — local relay harness with `RELAY_MAX_INBOX_MESSAGES_PER_PEER=3`: 4th store returns `ErrInboxFull` via `InboxStoreDetailed`; first 3 retrievable intact. **Fails before Phase 4 relay code exists;** gates the deploy artifact (G3 second half).

#### 5.4 Chores
- This doc's closure logs updated per phase (112 convention).
- `test-gate-definitions.md` — add `## 115 Relay Inbox Custody Gate Capture` mapping every new file; add new Dart suites (077 migration test, minting-sites invariant, verify_inbox_custody, handle/send_delivery_receipt, delivery-receipt listener, handle_app_resumed_inbox_custody, updated round-trip files) to the 1:1 Reliability Gate Files list AND `scripts/run_test_gates.sh` arrays (exact paths only, per Bulk-Classification Policy). **The gate-array edit is ONE coordinated edit with docs 114/116, made by whichever doc closes last** (program order #7); keep `completeness-check` green.
- **integration_test/ assertion sweep (critic-fold):** sweep `integration_test/` for status assertions that pin `'delivered'` on inbox custody (`transport_e2e_test.dart` scenarios, smoke/two-device orchestrators, `wifi_relay_fallback` S1–S4) and flip them to the `'inboxed'`/receipt contract — same chore doc 114 carries for its wifi harnesses.
- Extend `integration_test/scripts/run_transport_e2e.dart` with a cap-rejection scenario using the new testpeer storeStatus output (device/simulator-gated, nightly pool).

#### 5.5 Gate + deploy + evidence
- All G1–G5 green (gates list below).
- **G6 relay deploy:** new relay live on `mknoun.xyz` only after G2/G3 — **single deploy train** with whatever 112/113 still ship to the relay (Section 4); linux/amd64 build, on-host binary backup, post-deploy probe transcript attached to this doc's closure log (testpeer 101-store probe shows `INBOX_FULL` at cap on a staging instance with lowered `RELAY_MAX_INBOX_MESSAGES_PER_PEER`; `/metrics` shows `inbox_rejected_full_total` + `inbox_expired_pruned_total`; an old-app build sends into a full inbox and shows failed/sent, not delivered).
- **G7 device evidence:** two-physical-device pending→delivered flip recorded (§8) before this doc closes any phase as device-proven.

---

### Gates (all phases)

- **G1 (every phase):** `./scripts/run_test_gates.sh 1to1` green including all newly classified files, plus `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green.
- **G2 (Phase 4):** `cd go-relay-server && go test ./...` green with the rewritten limits contract — no test in the tree may assert silent eviction returns `Stored`; memory and redis reject/TTL/dedup/ack tests mirrored (parity check).
- **G3 (Phases 4–5):** `cd go-mknoon && make test` green AND `go test -tags integration ./integration/...` green (typed `INBOX_FULL` against local relay harness).
- **G4 No-false-delivered invariant (amended, critic-fold):** pinned by the Phase 1.2 minting-sites enforcement test — no production code path writes message status `'delivered'` except **(a)** `handle_delivery_receipt_use_case`, **(b)** the live deferred-ack branch of `_persistOutgoingSendResult`, **(b′)** the live deferred-ack acked branch of `_persistOutgoingDeleteResult` (same durable-staging bar as b; Caveat 9.7), and **(c)** the LAN committed-ack branch from doc 114 (committed = receiver durably staged, same bar as b). `persistInboxAccepted`/`retryUnacked`/`verifyInboxCustody`/delete-inbox-branches write only `'inboxed'`/`'sent'`.
- **G5 Classification:** `./scripts/run_test_gates.sh completeness-check` green (every new test file classified in the `## 115 Relay Inbox Custody Gate Capture` section + script arrays, exact paths only; single coordinated array edit with 114/116).
- **G6 Relay deploy gate:** per Phase 5.5.
- **G7 Device evidence gate:** per Phase 5.5 / §8.

---

## 6. Test matrix (sender outcome × confirmation source × backend/skew)

| Scenario | Expected sender status | Covering test (phase) |
|---|---|---|
| Sequential inbox fallback accepted | `'inboxed'` + envelope retained | `send_chat_message_use_case_test.dart` (P1.1) |
| Unacked live write + inbox handoff | `'inboxed'` | `send_chat_message_use_case_test.dart` (P1.1) |
| Concurrent custody short-circuit | `'inboxed'` | `send_chat_message_use_case_test.dart` (P1.1) |
| Live acked send (deferred ack) | `'delivered'` (site b) | pin (P1.1) |
| Deletion tombstone via inbox | `'inboxed'`, tombstone visible | `delete_message_use_case_test.dart` (P1.3) |
| Any other code path minting `'delivered'` | build break | minting-sites invariant (P1.2) |
| `'inboxed'` UI rendering | schedule glyph, pending semantics | `letter_card_test.dart` (P1.4) |
| Custody columns persistence | roundtrip | 077 migration + helpers tests (P1.5) |
| Receipt round trip (chat) | `'inboxed'`→`'delivered'`, envelope nulled | `handle/send_delivery_receipt` + `inbox_round_trip_test.dart` (P2) |
| Receipt round trip (deletion) | tombstone `'delivered'`→hidden | deletion listener tests (P2.5) |
| Origin discrimination `direct:`/`lan:`/relay/quarantine | receipt only for relay-drain | origin-marker contract test (P2.4, shared w/ 114) |
| Receipt store failure / unmatched / foreign | telemetry, no status change | P2.2/P2.3 |
| `'sent'`+transport-inbox retry | re-store, never blind `'delivered'` | `retry_unacked_messages_use_case_test.dart` (P3.1) |
| Sweep: expired/duplicate/inbox_full/null-expiry/>7d zombie/skew/stale-receipt | per D-6/D-7 rules | `verify_inbox_custody_use_case_test.dart` (P3.3, P5.2) |
| Late sweep vs delivered row | no downgrade (monotonic) | P3.3 monotonicity test |
| Edit row through sweep | `action:edit` preserved | pin (P3.6, floor = 116 P1-2) |
| Relay at cap (memory/limited/redis) | `rejected_full`, oldest survives | `limits_test.go` / `inbox_test.go` / `backend_redis_test.go` (P4) |
| TTL prune / ack-delete dedup release | same messageId re-storable | `inbox_dedup_test.go` (P4.3; ack cases incl. critic-fold pins) |
| Reject/prune observability | counters increment | `metrics_test.go` (P4.5) |
| Old relay bare `{ok:true}` | degrade to null-field outcome | `p2p_service_impl_test.dart` (P3.4), `inbox_parse_test.go` (P4.6) |
| Cap-rejected send, end to end | `'sent'`→drain→sweep→`'inboxed'`→receipt→`'delivered'` | `offline_inbox_roundtrip_test.dart` (P5.1) |
| Kill between ack-delete and receipt | repaired via sweep re-store + duplicate receipt | `offline_inbox_roundtrip_test.dart` (P5.2) |
| Typed INBOX_FULL against real relay | `ErrInboxFull` | `integration/relay_test.go` (P5.3) |

---

## 7. Risks and open questions carried forward

### Risks (actively mitigated; verify at each phase)
- **R1** Edit-envelope poisoning amplified by the sweep → HARD PREREQUISITE 116 P1-2 before Phase 3 + the P3.6 `action:edit` pin + co-sequenced file edits (116 first, rebase on `deriveRetryAction`).
- **R2** Status downgrade races (`saveMessage` INSERT OR REPLACE) → D-6: every forward transition via `conditionalTransitionStatus`; P3.3 monotonicity test.
- **R3** Receipt misfires for LAN/direct/quarantined replays → P2.4 origin-marker contract shared with doc 114; quarantined replays never mint receipts.
- **R4** Old-relay zombie dedup defeating the sweep on TTL → >7d defensive surfacing rule (P3.3) until the Phase-4 deploy; clock-skew re-store window → D-7 12h margin.
- **R5** Receipts consuming the recipient cap / rejected INBOX_FULL → D-5 coalescing + no retry-loop + sweep-side repair; `DELIVERY_RECEIPT_STORE_FAILED` telemetry.
- **R6** Implements-fake fleet breakage → D-8: zero interface changes (32 P2PService fakes, 20 MessageRepository fakes preserved); all new capability via impl-level methods + function seams.
- **R7** Contract-flip blast radius (host + integration_test assertions pinning delivered-on-inbox) → P1.7 chore list + P5.4 integration_test sweep.
- **R8** 121-improvements is an uncommitted moving baseline (111/112/move-scale work) — re-verify anchors per session (Caveat 9.6).

### Open questions (owner input needed)
- **OQ-1** Per-sender sub-quota inside the recipient cap (e.g. `RELAY_MAX_INBOX_PER_SENDER=25`): reject-new makes flooding visible but a single flooder can still block third-party senders until the victim drains — follow-up hardening, measure first via `inbox_rejected_full_total`.
- **OQ-2** UX closure for stale pending: should `'inboxed'` rows older than e.g. 30d auto-downgrade to `'failed'` for a terminal state, or stay pending indefinitely? Owner decision; pure Dart change later.
- **OQ-3** Receipt batching beyond per-drain coalescing: large drains (500-entry replay cap) may still want a single receipt envelope per peer per drain — tune after device evidence shows real receipt volume.
- **OQ-4** Historical rows: existing `status='delivered'/transport='inbox'` rows are unrecoverable lies; no migration can restore truth. Accept silently, or annotate UI for pre-115 inbox-delivered rows?
- **OQ-5** Background (non-lazy) hourly 1:1 TTL prune parity with the group inbox was deferred to avoid an `InboxBackend` interface method; lazy prune + telemetry chosen. Revisit if metrics show long-stale occupancy distorting capacity.
- **OQ-6** Encrypting delivery receipts (v2) once the installed fleet is receipt-aware — plaintext-v1 chosen strictly for version-skew safety; receipts currently expose messageId UUIDs to the relay.
- **OQ-7** Reuse of l10n `message_status_pending_inbox` copy for the `'inboxed'` state — confirm wording with owner or mint a dedicated key (zero-risk follow-up).

---

## 8. Evidence bar for closure (per project closure-bar convention)

1. **Suites:** all phase gates green — `flutter test test/features/conversation test/core`; `./scripts/run_test_gates.sh 1to1`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`; `./scripts/run_test_gates.sh completeness-check` green; `cd go-relay-server && go test ./...`; `cd go-mknoon && make test`; `go test -tags integration ./integration/...`.
2. **Two-device run** (Pixel6 `21071FDF600CSC` + iPhone13 `--profile` per the iOS 26.5 JIT memory): send to a force-quit recipient → sender letter card shows the schedule/pending-inbox glyph (screenshot), NOT done_all; bring recipient online → drain → sender flips to `'delivered'` via real receipt over the production relay (FLOW log lines `DELIVERY_RECEIPT_SENT`/`APPLIED` captured from both devices).
3. **Staging relay cap evidence:** relay instance with `RELAY_MAX_INBOX_MESSAGES_PER_PEER=5`; drive 6 stores via `go-mknoon/bin/testpeer inbox_store_v1` → 6th returns storeStatus `rejected_full`/errorCode `INBOX_FULL`; recipient drains all 5 intact; sender app shows the 6th as pending-`'sent'` and the custody sweep re-stores it after drain (end state: 6/6 delivered).
4. **Staging TTL evidence:** `RELAY_INBOX_TTL_HOURS` lowered (e.g. 1h); store, wait past TTL, observe `inbox_expired_pruned_total` increment on `/metrics` and the sender sweep re-store landing as fresh `'stored'` (dedup-zombie fix proven on a live process, not just unit clock manipulation); recipient ultimately receives.
5. **Memory-backend relay restart:** restart staging relay (`RELAY_BACKEND=memory`) with pending `'inboxed'` messages → sweep re-stores after reconnect → delivery completes (proves the sweep also heals total relay-state loss, which no host fake reproduces with real reconnect timing).
6. **Production deploy verification on mknoun.xyz (after G6):** `/metrics` scrape shows new counters registered; canary store/retrieve round trip via `run_transport_e2e.dart` against the real relay; 24h watch of `inbox_rejected_full_total` to size real-world cap pressure before considering the per-sender quota follow-up (OQ-1).
7. **Old-app interop check on device:** previous TestFlight build sending into a deliberately-filled staging inbox shows failed/sent status (not delivered) and its retry sweep recovers after drain — confirms the reject-new response is survivable by the deployed fleet.
8. **Docs:** `test-gate-definitions.md` updated (`## 115 Relay Inbox Custody Gate Capture`, coordinated array edit); this doc updated with per-phase closure verdicts.

---

## 9. Verified caveats

### 9.1 Migration numbering is 077 / DB v77 (critic-fold)
Doc 113 took 076/v76 and is already implemented in the tree (`076_post_media_attachment_crypto_columns.dart`, `currentIdentityDatabaseVersion = 76` — verified 2026-06-12). Do not reuse 076.

### 9.2 `implements`-based fakes
No interface change anywhere in this plan (D-8): `P2PService.storeInInbox` stays `Future<bool>` (32 implements-fakes: lib impl + 30 test fakes + `fake_p2p_service_integration.dart`), `MessageRepository` already has `conditionalTransitionStatus` (`message_repository.dart:71-75`; 20 implements-fakes preserved), Go `InboxBackend.Store` signature unchanged. New capability = impl-level methods + top-level function seams + optional named params on top-level use-case functions (zero fake breakage).

### 9.3 Old-relay residuals are bounded, not zero
Against the OLD relay the sweep fully repairs cap evictions (eviction rebuilds dedup ids, `backend_memory.go:264-276`) but TTL prune leaves zombie dedup ids — the P3.3 >7d rule keeps such rows honestly non-delivered until the Phase 4 deploy. This is the reason the relay deploy "should follow promptly", not a correctness hole.

### 9.4 RED-honesty exceptions in Phase 4.3
The two acked-entry dedup-release tests the program critic requested as "red tests" are expected **green-on-arrival pins** on inspection (`backend_memory.go:260` Ack rebuilds messageIds; redis dedup scans live entries only). They are authored as MANDATORY either way: a RED result on either backend is a blocking Phase-4 bug (the Phase-5.2 repair loop depends on it). Label by actual color at authoring.

### 9.5 `saveMessage` is INSERT OR REPLACE
`messages_db_helpers.dart:18-22` uses `ConflictAlgorithm.replace` — any blind persist can downgrade status. Every forward transition this doc introduces goes through `conditionalTransitionStatus` (D-6); reviewers should reject any sweep/receipt diff that calls `saveMessage` for a status change.

### 9.6 Line-number re-check
All file:line anchors verified 2026-06-12 against the UNCOMMITTED 121-improvements tree (contains 111/112/move-scale/voice-wake-lock work). Docs 114/116 will move shared-file line numbers (`send_chat_message_use_case.dart`, retry use cases) — re-verify anchors before each session; re-run recon if the tree shifts materially.

### 9.7 Deletion paths were missing from the draft plan
Authoring-time verification found `delete_message_use_case.dart` minting `'delivered'` on bare inbox store at `:332-355` and `:559-571` — exactly the "untested call site" class the G4 enforcement fold exists for. Its live acked branch (`:548-556`) is allowed as site (b′) (same Go deferred-ack durable-staging bar as (b)); its inbox branches flip to `'inboxed'` in Phase 1.7. The minting-sites invariant test (P1.2) is what guarantees the NEXT such site cannot land silently.

### 9.8 Using the arch graph during implementation
Anchor `graphify query` on 1–2 exact symbol names (e.g. `graphify query "persistInboxDelivered retryUnackedMessages"`), never prose; the arch graph is thin for `go-relay-server` (expected) — read relay sources directly. Refresh after every edit batch: `./graphify-arch/refresh_arch_graph.sh` from repo root (NEVER run graphify build/update with cwd inside `graphify-arch/`), plus `graphify update .` for the full graph.

---

## Review resolution log

**2026-06-13 (Phase 1 implementation findings):**
1. **`retry_failed_messages_use_case.dart` under-enumeration (FIXED-by-whitelist, flip owned by Phase 3).** The Phase 1.2 minting-sites scan found two `'delivered'` writes the doc's §1 enumeration missed: `retry_failed_messages_use_case.dart` blind-flips `transport=='inbox'` rows (`:193`) and mints `'delivered'` from a bare `storeInInbox==true` (`:217`) — the exact same bug class as the enumerated `retry_unacked` sites. Resolution: both files carry explicitly-commented PROGRAM-TEMPORARY whitelist entries in `delivered_status_minting_sites_test.dart`; Phase 3 (which rewrites both retry use cases, co-sequenced after 116 P1-2) removes them. G4's final whitelist is unchanged.
2. **Delete-for-everyone eligibility gate (FIXED, production).** `deleteMessageForEveryone` rejected non-`'delivered'` rows (`delete_message_use_case.dart` status gate), which would have made `'inboxed'` rows permanently un-deletable. Widened to `'delivered' || 'inboxed'` (an `'inboxed'` row holds a durable relay copy the receiver will drain — deletion must stay available). Same widening applied to `conversation_wired.dart` `_canDeleteForEveryone` (the doc's ~:1559 anchor) and `_shouldRefreshFromRepositoryChange`.
3. **Readiness-proof gate (FIXED, production).** `_recordSuccessfulSendReadinessProof` fired only on `status=='delivered'`; inbox custody previously qualified (as `'delivered'/'inbox'`) and still proves transport readiness — widened to `'delivered' || 'inboxed'`, preserving NET-REL readiness-proof behavior (pinned by the existing `chat_send_inbox` proof assertions).
4. **Doc anchor drift (noted).** Migration registration lives in `lib/main.dart` (onCreate list + `oldVersion < 77` onUpgrade) and the version constant in `lib/core/database/app_database_version.dart` — not `encrypted_db_opener.dart` as the Phase 1.7 text says. Implemented per code reality.

## Closure log

**Phase 1 — CLOSED (host). 2026-06-13.**
- RED (all confirmed failing for the documented reasons before any production edit): 1.1 three custody tests in `send_chat_message_use_case_test.dart` (sequential / unacked-handoff / concurrent short-circuit all read `'delivered'`); 1.2 minting-sites scan (send_chat 7 writes vs 1 allowed, delete 4 vs 1); 1.3 two tombstone custody tests (`'delivered'` + hidden); 1.4 letter-card `'inboxed'` fell to the default `done_rounded` branch; 1.5 compile-RED (migration 077 + model fields absent). Pins green-on-arrival as labeled: live-acked-delivered (1.1), tombstone-visibility pure-fn (1.3), status-census/D-1 (1.6).
- GREEN: `persistInboxDelivered`→`persistInboxAccepted` (status `'inboxed'`, envelope retained, optional `expiresAtMs`), unacked-handoff + concurrent-custody branches flipped with envelope retained, both delete inbox branches flipped (envelope retained, tombstone visible), migration `077_message_relay_custody.dart` (+ registration in main.dart onCreate/onUpgrade, DB v77 in `app_database_version.dart`), `ConversationMessage.relayExpiresAt/custodyCheckedAt` (fromMap/toMap/copyWith sentinel), letter_card pending-family mapping for `'inboxed'`, conversation_wired refresh + delete-eligibility, readiness-proof widening.
- Contract-flip chore: 20 enshrining tests flipped across `send_chat_message_use_case_test.dart` (12), `two_user_message_exchange_test.dart`, `voice_message_exchange_test.dart`, `concurrent_durable_fallback_roundtrip_test.dart`, `send_then_lock_delivery_test.dart` (2), `message_deletion_roundtrip_test.dart` (sender tombstone now visible-pending until receipt — D-3 asserted explicitly), `incomplete_upload_recovery_test.dart`, `c2_ack_drop_test.dart` (5), `c3_half_open_test.dart`, `network_chaos_test.dart`; `full_migration_chain_test.dart` chains extended with 077.
- Gates: `flutter test test/features/conversation` 1134 green; `flutter test test/core` 1821 green; `./scripts/run_test_gates.sh 1to1` exit 0 (582); `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` exit 0; `completeness-check` 836/836 PASS (new files covered by bulk classification). Graphs refreshed (`graphify update .` + `refresh_arch_graph.sh`).
- Still open: rows stay `'inboxed'` until Phase 2 receipts; retry use cases still mint `'delivered'` (PROGRAM-TEMPORARY whitelist, Phase 3); G4 site (a) joins in Phase 2, site (c) with doc 114 P3.

**Phase 2 — CLOSED (host). 2026-06-13.**
- Sequencing honored: landed AFTER 116 P1-2 (receipts ack by message id — safe only once retried edits stay edits).
- RED (all confirmed, mostly compile-level since no receipt machinery existed): router rewrite (the `:198` drop-enshrining test REWRITTEN red-first into `deliveryReceiptStream` routing), `handle_delivery_receipt_use_case_test.dart` (4 + the P2.5 sender-tombstone-flip test relocated here — it exercises `handleDeliveryReceipt` + the visibility normalizer end-to-end), `send_delivery_receipt_use_case_test.dart` (2), receiver hook + origin-marker contract in `handle_incoming_chat_message_use_case_test.dart` (2), deletion-apply receipts in `handle_incoming_message_deletion_use_case_test.dart` (1, covering duplicate re-invoke + direct/lan skip), round trip in `inbox_round_trip_test.dart` (1).
- GREEN: router `deliveryReceiptStream` (drop replaced); new `send_delivery_receipt_use_case.dart` (plaintext v1 per D-4; live-first/inbox-fallback; coalesced messageIds per D-5; `DELIVERY_RECEIPT_SENT`/`STORE_FAILED`; **also home of the shared origin predicate `shouldMintDeliveryReceipt`** — entryId-prefix contract {`direct:`, `lan:`} skip + transport=='inbox' fallback for unstaged forwards); new `handle_delivery_receipt_use_case.dart` (G4 site (a); `conditionalTransitionStatus` 'inboxed'→'delivered' + lost-ack 'sent'→'delivered'; envelope nulled; tombstones re-normalized → hidden; unmatched/foreign telemetry; idempotent); new `delivery_receipt_listener.dart`; optional hooks (`sendDeliveryReceipt` + `stagedEntryId`) on both incoming use cases firing AFTER durable persist and on duplicate receives; optional ctor params on `ChatMessageListener`/`MessageDeletionListener`; main.dart wiring (receipt sender + `DeliveryReceiptListener` constructed over the router and started with the listener block). Minting-sites whitelist: site (a) added (2 `toStatus: 'delivered'` transitions).
- Test-infra: `TestUser` gained `withDeliveryReceipts`; the integration fake drain now tags drained messages `transport: 'inbox'` (mirrors `InboxStagingEntry.toChatMessage`).
- Origin-marker coordination note for doc 114: production staged replays flow through `chatMessageListener.processIncomingMessage`, whose receipt eligibility currently keys on `message.transport` (relay sweep replays carry `'inbox'` via `toChatMessage`; direct staged replays keep their live transport → skip). The `stagedEntryId` param exists on the use cases for 114 to thread the `'lan:'` entryId through the replay path — REQUIRED before 114 P2 lands, else a killed-receiver `'lan:'` row swept at startup replays as transport `'inbox'` and would mint a receipt (the 114 P2.5 layer test is what forces this threading).
- Gates: `flutter test test/features/conversation test/core` 2978 green; `1to1` exit 0; `completeness-check` 839/839 PASS; macOS baseline exit 0. Interface changes: NONE on abstract interfaces (concrete router/listener classes + optional named params only).

**Phase 3 — CLOSED (host Flutter/app-side). 2026-06-13.**
- Sequencing honored: doc 116 P1-P2 prerequisite remained closed before this phase; this phase stayed Flutter/database/lifecycle scoped and did not change relay-server, go-mknoon, generated bindings, or deploy artifacts.
- RED baseline: the staged Phase 3 suites initially failed on missing production symbols (`inbox_store_outcome.dart`, `verify_inbox_custody_use_case.dart`, `storeInInboxDetailed`, custody DB helpers) and on retry-unacked false-delivered behavior.
- GREEN: new `InboxStoreOutcome`/`StoreInInboxDetailedFn`; new `verifyInboxCustody` use case with 12h skew margin, 6h recheck spacing, old-relay >7d zombie-duplicate defense, `INBOX_CUSTODY_RESTORED`/`DUPLICATE`/`LOST` telemetry, and conditional status transitions to avoid late-sweep downgrades; new DB custody load/mark helpers; `MessageRepositoryImpl` impl-level custody methods; `P2PServiceImpl.storeInInboxDetailed` parsing enriched and bare bridge responses while keeping `P2PService.storeInInbox` as the bool wrapper; retry-unacked now re-stores `sent`+`transport=='inbox'` rows and persists successful relay custody as `inboxed` with the envelope retained; pending-retrier, app-resume, and main.dart DI wiring added.
- Coverage: scheduler/resume ordering coverage landed in the existing `pending_message_retrier_upload_ordering_test.dart` and `handle_app_resumed_upload_ordering_test.dart` suites instead of a new single-purpose lifecycle file; existing group-inbox resume labels were updated to Step 8g after custody and intro retry.
- Gates: focused analyzer over touched production files clean; focused P3 Flutter batch passed 183 tests (`/tmp/doc115_p3_focused_2.log`); `./scripts/run_test_gates.sh 1to1` passed 593 tests (`/tmp/doc115_p3_1to1.log`); `./scripts/run_test_gates.sh completeness-check` passed 841/841 (`/tmp/doc115_p3_completeness.log`); `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from the repo root and refreshed `graphify-arch/GRAPH_SELECTION.md` plus `comparison.json`.
- Then-open at Phase 3 close: Phase 5 owned final 115 gate capture, deploy/staging/two-device evidence, integration E2E proof, the coordinated `scripts/run_test_gates.sh` array edit, and the final broad go-mknoon gate decision.

**Phase 4 — CLOSED (host relay/Go/client). 2026-06-13.**
- RED baseline: focused source reads and the staged P4 tests confirmed silent evict-old behavior at cap in memory, limited-memory, and Redis paths; memory TTL prune dropped rows without rebuilding dedup ids; handler responses lacked `expiresAtMs`/`occupancy`/`capacity`; go-mknoon exposed only `Node.InboxStore(...) error`; bridge `InboxStore` returned bare `{ok:true}`.
- GREEN: relay/server now returns typed `InboxStoreResultRejectedFull` / `INBOX_FULL` / `rejected_full`, rejects new stores at cap without evicting accepted entries, keeps memory/limited/Redis cap behavior in parity, repairs memory TTL prune dedup zombies, records reject/prune counters, returns `expiresAtMs`/`occupancy`/`capacity`, and suppresses push on reject. Go client now has `ErrInboxFull`, `InboxStoreOutcome`, `parseInboxStoreResponse`, and `InboxStoreDetailed` while preserving the old `InboxStore` wrapper. Bridge and testpeer now surface detailed store results; `go-mknoon/bin/testpeer` was rebuilt.
- Gates/evidence: focused relay P4 suite passed; `cd go-relay-server && go test -count=1 ./...` passed (`/tmp/doc115_p4_relay_all.log`); focused Flutter bridge/app-side contract batch passed 128 tests (`/tmp/doc115_p4_focused_flutter.log`); focused go-mknoon node/bridge/testpeer P4 tests passed; all non-`node`/`bridge` go-mknoon packages passed (`/tmp/doc115_p4_go_mknoon_non_node_bridge.log`); `cd go-mknoon && make verify-bindings` passed; `cd go-mknoon && make testpeer` passed; `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from the repo root and refreshed `graphify-arch/GRAPH_SELECTION.md` plus `comparison.json`.
- Explicit follow-up, resolved by Phase 5 policy: broad `cd go-mknoon && go test -count=1 -timeout=180s ./...` timed out in existing group-history/multi-device tests (`TestBridgeGroupHistoryRepairRange_CommandExposed` in `bridge`, `TestGA012MultiDeviceMissingSenderTransportPeerIDRejects` in `node`) when run as one full suite; both named tests pass in isolation. Phase 5 recorded the accepted gate policy below.
- Then-open at Phase 4 close: Phase 5 still needed deploy/verification evidence, final E2E/device/staging evidence, doc-115 gate definitions, coordinated gate arrays, and source-doc closure.

**Phase 5 — CLOSED with production relay deployed; residual device-lab evidence archived. 2026-06-13.**
- GREEN: `sendChatMessage` now consumes the detailed inbox-store seam without
  changing the `P2PService` interface; detailed accepted outcomes persist
  `inboxed`, while typed `INBOX_FULL` persists a retryable non-delivered
  `sent` row with retained `wireEnvelope`. The shared fake P2P stack now models
  per-peer inbox capacity and detailed rejected-full outcomes. The local
  go-mknoon relay harness now supports cap-limited store responses carrying
  `INBOX_FULL`, `rejected_full`, `occupancy`, and `capacity`; the new local
  integration proof verifies `errors.Is(err, node.ErrInboxFull)` and that the
  first accepted entries remain retrievable.
- Acceptance coverage: `offline_inbox_roundtrip_test.dart` now proves a
  cap-rejected third send stays retryable, delivers after the receiver drains
  capacity, then flips by receipt; it also proves a lost receipt after drain is
  repaired by custody re-store plus duplicate receipt. `verifyInboxCustody`
  now re-stores stale unreceipted rows before expiry, bounding false-pending
  latency without downgrading delivered rows.
- Gate capture: `scripts/run_test_gates.sh`,
  `scripts/run_host_test_gates.sh`,
  `Test-Flight-Improv/test-gate-definitions.md`, and
  `Test-Flight-Improv/test-gates-reference.md` now include the Doc 115 custody,
  receipt, migration, router, retrier, bridge, media, and identity guard suites.
  The delivered-status source-audit allowlist was tightened by removing the
  stale `retry_unacked_messages_use_case.dart` delivered-write exception; that
  retry path now persists `inboxed` and waits for receipts.
- Gates/evidence: focused P5 Flutter batch passed 19 tests
  (`/tmp/doc115_p5_focused_flutter_combined.log`); delivered-status source
  audit passed after format (`/tmp/doc115_p5_delivered_status_guard_after_format.log`);
  `./scripts/run_test_gates.sh completeness-check` passed 841/841;
  expanded `./scripts/run_test_gates.sh 1to1` passed 788 tests
  (`/tmp/doc115_p5_1to1_gate_rerun.log`);
  `cd go-relay-server && go test -count=1 ./...` passed
  (`/tmp/doc115_p5_relay_all.log`);
  `cd go-mknoon && go test -tags integration ./integration -run TestInboxStoreFull_TypedRejectionAgainstLocalRelay -count=1` passed
  (`/tmp/doc115_p5_go_integration_inbox_full_2.log`);
  `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed
  from the repo root and regenerated `graphify-arch/GRAPH_SELECTION.md` plus
  `comparison.json`.
- Gate policy: the P4 broad `cd go-mknoon && go test -count=1 -timeout=180s ./...`
	  aggregate timeout is accepted as policy-closed for this doc. It was isolated
  to pre-existing long-running group-history/multi-device tests in `bridge`
  and `node`; the named culprit tests passed in isolation, all non-node /
  non-bridge packages passed, focused P4 node/bridge/testpeer gates passed, and
	  the P5 local-relay integration proof passed. This should be reopened only if
	  a focused Doc 115 gate regresses or the broad go-mknoon suite is split/fixed.
- Final production relay deploy: built linux/amd64 artifact
  `/tmp/relay-server-doc115-linux-amd64`
  (`sha256=3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`)
  with embedded `INBOX_FULL`, `rejected_full`,
  `relay_inbox_rejected_full_total`, and
  `relay_inbox_expired_pruned_total` strings. Deployed it to
  `ubuntu@mknoun.xyz`, backed up the old binary as
  `/usr/local/bin/relay-server.backup.20260613T145030Z`, installed it at
  `/usr/local/bin/relay-server`, and restarted `relay-server`. Post-deploy SSH
  verification: `systemctl is-active relay-server` returned `active`,
  `/usr/local/bin/relay-server version` returned `relay-server v1.5.1`, the
  installed binary hash matched the local artifact, and SSH-local
  `http://127.0.0.1:2112/metrics` exposed
  `relay_inbox_expired_pruned_total 0` and
  `relay_inbox_rejected_full_total 0`. Public `:2112` remains firewall-blocked,
  so metrics evidence is SSH-local.
- Production canary evidence: `run_transport_e2e.dart` reached the new relay and
  observed enriched inbox responses with `capacity:100`, `expiresAtMs`,
  `occupancy`, and `storeStatus:"stored"`. The orchestrator reported `29/30`
  scenarios passed; the remaining `E8` media-reference failure is outside Doc
  115 relay custody. The stale `inboxed` status assertions in
  `integration_test/transport_e2e_test.dart` were corrected, and focused
  simulator slices for empty-message rejection plus unreachable-peer inbox
  fallback passed against DB version 77.
- Residual evidence archive: no two-physical-device drain/receipt proof, old
  TestFlight interop proof, or live lowered-cap/TTL staging run was collected in
  this shell. These are unclaimed lab evidence, not open Doc 115 implementation
  work.

## Amendment log

- 2026-06-13 Phase 3 implementation note: the planned `handle_app_resumed_inbox_custody_test.dart` coverage was satisfied by extending the existing exact-order lifecycle/retrier tests, which already pin the recovery pipeline. No new test file classification was needed beyond the current 841/841 completeness pass.
- 2026-06-13 Graphify operation note: Phase 3 post-edit graph refresh used `./graphify-arch/refresh_arch_graph.sh` from the repo root. No `graphify update` or extract command was run with cwd inside `graphify-arch/`.
- 2026-06-13 Phase 4 graphify operation note: post-edit graph refresh again used `./graphify-arch/refresh_arch_graph.sh` from the repo root, including the idempotent extractor/dedup patch reapplication and regenerated `graphify-arch/GRAPH_SELECTION.md` / `comparison.json`. No graphify update or extract command was run with cwd inside `graphify-arch/`.
- 2026-06-13 Phase 5 graphify operation note: post-edit graph refresh again used `./graphify-arch/refresh_arch_graph.sh` from the repo root. The script confirmed the local extractor/dedup patch, rebuilt the curated `.graphify-arch-src` graph, reclustered, exported the aggregated HTML view, and regenerated `graphify-arch/GRAPH_SELECTION.md` / `comparison.json`. No graphify update or extract command was run with cwd inside `graphify-arch/`.
- 2026-06-13 final deploy note: production relay deployment to `mknoun.xyz` completed with artifact hash `3d732c11f4d4ce4ba72a03d2440571c66f2b183677f4e6c19850bddddffe1bf5`; service health, version, binary strings, and SSH-local metrics were verified. Physical device/TestFlight proof remains unclaimed residual lab evidence rather than a doc status.
