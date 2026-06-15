# 116 — Edit Retry Fidelity: Failed Edits Retried via the Full-Send Fallback Must Stay Edits (TDD Plan)

Date: 2026-06-12 · Branch: 121-improvements · Status: **CLOSED FOR IMPLEMENTATION — residual device/TestFlight evidence archived (2026-06-13).** Phases 1-2, 3A, 3B, and closure host gates are recorded, and the final expanded `1to1` gate is green. Doc 3 of the 3-doc false-delivered program (114 LAN ack-after-commit, 115 relay inbox custody, 116 this doc). Phases 1–2 of THIS doc are the program's correctness FLOOR and a **hard prerequisite of 115 Phase 3** (see Program context below and the Phase 2 prerequisite box).

Source: graph-first trace + adversarial verification (findings + verdict JSON, every load-bearing claim file:line re-read in source on 2026-06-12) + cross-plan completeness critic. The verdict's verdict: **confirmed end-to-end as claimed** — a failed edit retried through the full-send fallback is silently downgraded to a plain send, poisons its own stored envelope, gets deduped by id on the receiver, and acks back as `delivered`. Re-verify anchors before each session (Caveat 9.4).

---

## 1. Problem statement and impact

Edits travel as `action:'edit'` + `editedAt` **inside the encrypted v2 inner payload** (`message_payload.dart:208-220`; the outer envelope carries no action field, `:120-136`). A genuinely failed edit persists exactly the right row: `status='failed'`, `editedAt` set, `wire_envelope` = the v2 EDIT envelope (`send_chat_message_use_case.dart:1002-1010`). The retry pipeline then destroys it in four steps:

1. **Downgrade.** `retryFailedMessages` first replays the stored envelope to the relay inbox (correct). But when that store returns false (`retry_failed_messages_use_case.dart:213` has no else), throws (`:233-235`), or the envelope is legacy v1 (`:204-207`, `:236-242` via `outbound_envelope_policy.dart:3-20`), it falls through to a full `sendChatMessage` call (`:283-298`) that omits `action:`, `editedAt:`, and `createdAt:`. `action` defaults to `actionSend` (`send_chat_message_use_case.dart:173`), `resolvedEditedAt` is forced null (`:307-309`), and the edit-contract validation only runs for `actionEdit` (`:244-253`) — the downgraded retry passes silently. The edit goes out as a **plain send under the original message id**.
2. **Poisoning.** Before the transport race, `updateWireEnvelope` (`send_chat_message_use_case.dart:396-398`) overwrites the stored EDIT envelope with the plain one. Even if the fallback then fails, the failed persist (`:1002-1010`) saves `editedAt=null` + the plain envelope via INSERT OR REPLACE (`messages_db_helpers.dart:18-22`). **The edit is unrecoverable after one fallback attempt** — every future retry, including the otherwise-correct envelope-replay path, ships plain content.
3. **False ack.** The receiver dedups non-edit payloads purely by id (`handle_incoming_chat_message_use_case.dart:252, 261-276` — text never compared), the listener confirms the deferred nonce `ok=true` for `duplicate` (`chat_message_listener.dart:248-264, 312, 446-453`), and Go writes a genuine `{"ack":true}` to the sender (`go-mknoon/node/node.go:1616-1651`).
4. **False delivered.** The sender persists `status='delivered'` with `editedAt=null` and `createdAt=now` (`send_chat_message_use_case.dart:1675-1683` via `message_payload.dart:227-250`).

**End state: silent content divergence.** The sender shows the edited text as delivered with the 'edited' badge silently gone (`conversation_screen.dart:531`); the receiver permanently keeps the pre-edit text. The only logs are success-shaped (`RETRY_FAILED_MESSAGE_SUCCESS` sender-side, `CHAT_MSG_RECEIVE_DUPLICATE` receiver-side). Zero user action required: `PendingMessageRetrier` fires `retryFailedMessages` periodically and on online transitions (`pending_message_retrier.dart:169-181, 193-201`), and app-resume step 8c does too (`handle_app_resumed.dart:493-509`).

**No compensating mechanism exists.** `retryUnackedMessages` never re-examines `delivered` rows and actually FEEDS the bug — it demotes legacy v1 `'sent'` rows to `'failed'` (`retry_unacked_messages_use_case.dart:92-104`), deterministically routing them into the downgrading fallback. Receiver inbox-replay of a staged plain copy is `duplicate → rejected` (staged envelope destroyed, `recovered_inbox_chat_disposition.dart:74-79`). `_repairDuplicateReplayMedia` repairs media rows only, never text (`handle_incoming_chat_message_use_case.dart:439-492`). The single partial compensation: a FALSE-NEGATIVE `storeInInbox` (relay actually stored the edit, sender saw an error) heals later via inbox drain — permanent divergence requires the store to have genuinely failed while a live fallback leg succeeds, after which poisoning guarantees no copy of the edit envelope exists anywhere.

**Sibling defects in the same pipeline (in scope, Phase 3):**
- **Delete-for-everyone starvation.** A failed delete tombstone (`text=''` + `message_deletion` v2 envelope, `delete_message_use_case.dart:364-367, 386-405`) bounces off the fallback's empty-text gate (`send_chat_message_use_case.dart:234-242`) and stays `'failed'` forever — the receiver keeps showing a message the sender believes is deleted; the sender UI hides the tombstone only once `'delivered'` (`delete_message_tombstone_visibility.dart:14`).
- **Receiver blindness.** A non-edit duplicate whose text diverges from the stored row is invisible — only `CHAT_MSG_RECEIVE_DUPLICATE` fires (`handle_incoming_chat_message_use_case.dart:270-274`).
- **ignoredEdit churn loop (latent, armed by Phase 1).** `HandleChatMessageResult.ignoredEdit` has no branch in `processIncomingMessage` — it falls through to the error outcome and confirms `ok=false` (`chat_message_listener.dart:564-570`); once retried edits are real edits, a lost-ack retry would loop (ack false → unacked → inbox handoff → staged replay → ignoredEdit → retryable churn) until the 111 attempt cap.

Reactions never enter this pipeline (`send_reaction_use_case.dart:104-119` writes no failed messages row — pinned in Phase 1).

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

### Why THIS doc is the correctness floor

Id-keyed dedup, id-keyed acks, and id-keyed delivery receipts are only safe when a retried envelope is **byte-identical (or semantically identical) to what the sender's row means**. Both sibling plans deliberately create duplicate-delivery paths (114's LAN legacy-ack relay copy and staged replays; 115's custody-sweep re-store and receipt-triggered duplicate drains) and both lean on receiver id-only dedup for idempotency — **the exact mechanism this bug abuses**. Until 116 P1 lands, a downgraded edit deduped on the receiver flips the sender to 'delivered' (and under 115, 'inboxed'→'delivered' via a receipt) **for content the receiver does not display**: the receipt machinery makes the false-delivered STRONGER, not weaker. And until 116 P2 lands, the 115 Phase 3 custody sweep — which re-stores `wire_envelope` on every cycle — would re-propagate a poisoned plain envelope under the same message id every sweep period, amplifying the bug from one-shot to recurring.

### Cross-plan interactions touching this doc (from the completeness critic)

- **Correctness floor (critic interaction #3):** both backstops absorb deliberate duplicates via receiver id-only dedup, "which is only safe for byte-identical envelopes, so the edit fallback fix + updateWireEnvelope poisoning guard are a correctness FLOOR for the other two plans: a poisoned plain envelope re-stored by the custody sweep re-propagates wrong content under the same id every cycle."
- **Receipts ack by id, not content (critic interaction #4):** "until the edit fix lands, a downgraded edit deduped on the receiver now triggers a receipt that flips the sender 'inboxed'→'delivered' for content the receiver does not display — the relay plan's receipt machinery makes the edit bug's false-delivered STRONGER, another reason the edit plan cannot remain unwritten." Resolved by landing 116 P1 before 115 P2.
- **Sequencing constraint with 115 P3 (critic interaction / gap #6, folded into Phase 2):** 116 P2 is a declared PREREQUISITE of the 115 custody sweep in BOTH docs; 115 Phase 3 gains the green-on-arrival pin "sweep re-store of an edit row carries action:edit" (authored here in Phase 2, inherited by 115 P3 after rebase on `deriveRetryAction`).
- **Go parity model untouched (critic interaction #5):** like 114/115, this plan does not touch the Go confirmNonce machinery — `node.go:1616-1651` stays the untouched deferred-ack parity model; the only listener change is the Dart-side `ignoredEdit → confirm ok=true` mapping (Phase 3).
- **Gate/process overlap (critic interaction #6 + gap #7, folded into Phase 3):** doc numbering fixed program-wide (114 LAN, 115 relay, 116 this doc); the `test-gate-definitions.md` Gate Capture sections and the `run_test_gates.sh` 1to1 array are edited as ONE coordinated change by whichever doc closes last. This plan requires no relay deploy and no gomobile rebuild — it rides any release train.
- **Status-model neutrality:** this plan deliberately asserts **action / editedAt / envelope content, not status strings**, so it composes with 115 Phase 1's 'inboxed' rename in either landing order. The one unavoidable status coupling (tombstone terminal visibility) is isolated in Phase 3 and carries an explicit coordination rule (Phase 3 notes, OQ-4).

---

## 2. Goals / Non-goals

### Goals
- **G1 retry-fidelity:** any full-send retry of a failed outgoing row carries **row-derived** action metadata — `editedAt` rows go out `action:'edit'` with the ORIGINAL `editedAt`+`createdAt` (same inner-payload shape as first-try edits, `message_payload.dart:208-220`), plain rows stay plain with original `createdAt`. Pinned by the Phase 1 retry suite + `edit_retry_round_trip_test.dart` convergence test. Ship-blocked on `./scripts/run_test_gates.sh 1to1`.
- **G2 no-downgrade-write (PREREQUISITE of 115 Phase 3):** `sendChatMessage` never transmits nor persists (`updateWireEnvelope` OR failed-row persist) a plain-send payload under a message id whose outgoing row carries `editedAt` or `deletedAt` — fail-closed `invalidMessage` + `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED`; the stored edit envelope survives every fallback attempt. Pinned by Phase 2 gate tests + the 'edit metadata survives a failed fallback' Phase 1 test + the green pin 'sweep re-store of an edit row carries action:edit'.
- **G3 single-flight:** at most one in-flight retry per message id across PendingMessageRetrier / reconnect debounce / app-resume 8c / UI retry button triggers, and settled rows are never re-sent — Phase 2 concurrency + stale-snapshot tests.
- **G4 tombstone-liveness:** a failed delete-for-everyone tombstone always has a live retry route (stored-v2 direct replay, or v2 rebuild for legacy) that never traverses `sendChatMessage` and never leaks v1 bytes; missing-key starvation is telemetry-visible (`RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE`) — Phase 3 tombstone trio.
- **G5 receiver-truthfulness:** edits for known ids apply (pin), superseded identical edits ack `ok=true` and their staged copies map to `rejected/'ignored_edit'`, and non-edit duplicates with divergent text emit `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` (lengths only, no plaintext) while never applying unauthenticated content — Phase 3 receiver tests.
- **G6 process (every phase):** `./scripts/run_test_gates.sh 1to1` green, `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green, `./scripts/run_test_gates.sh completeness-check` green with `edit_retry_round_trip_test.dart` classified in '## 116 Edit Retry Fidelity Gate Capture' + the 1to1 Files list in BOTH `test-gate-definitions.md` and the `run_test_gates.sh` array (single coordinated edit with plans 114/115); regression sanity `(cd go-mknoon && make test)` and `(cd go-relay-server && go test ./...)` green (no Go changes expected — any red there means scope leak).

**Net invariant (the behavioral contract):** a failed-then-retried edit always converges sender and receiver text + edited badge, or surfaces a visible non-delivered state — it never silently diverges, and no compensating sweep (`retryUnacked`, the 115 custody sweep) can ever replay downgraded content because the downgrade can no longer be minted or persisted.

### Non-goals (deferred, with justification)
- **Repairing already-poisoned field rows** — a pre-fix fallback nulled `editedAt` and stored a plain envelope; no migration can recover the edit metadata (it exists nowhere). They surface via the new mismatch telemetry only; one-time UI annotation deferred to the field-telemetry watch (OQ-1).
- **Automated receiver-initiated content reconciliation on duplicate mismatch** — the duplicate branch has no author check; applying content from a duplicate would be an unauthenticated rewrite. Needs a new protocol surface; out of scope (OQ-2).
- **Hardening the `unauthorized` listener fallthrough** — same fallthrough pattern `ignoredEdit` had, but it is an attack/foreign-sender path, not a user-loss path (OQ-3).
- **Rebuilding v2 envelopes in place during legacy demotion** (`retry_unacked_messages_use_case.dart:92-104`) — with P1 the fallback reconstructs correctly; the one-less-hop optimization waits for 115 Phase 3's rewrite of that file (OQ-6).
- **UI affordance distinguishing 'retry will resend your edit' from plain retry** — UX-only follow-up (OQ-5).
- **Any status-string redesign** — owned by 115 Phase 1; this plan stays status-model neutral except the Phase 3 tombstone terminal (coordination rule there).

---

## 3. Design decision

**Fix the content AND gate the writer (critic option choice, justified).** Two candidate fixes existed: **(a)** skip the `:396-398` envelope overwrite for edit rows, so the stored edit envelope survives the fallback; **(b)** make the fallback rebuild a proper edit envelope from the DB row, so the overwrite becomes harmless. We pick **(b) PLUS a fail-closed writer gate as defense-in-depth**, because (a) alone would still transmit wrong plain CONTENT on the wire under the edit id — only rebuilding fixes content; and the gate guarantees no current or future caller can reintroduce the downgrade or null the row's `editedAt` via the failed-persist path (`:1002-1010`). Verified: all UI retry paths route through `retryFailedMessage` (`conversation_wired.dart:2197-2235`), so the gate has **zero legitimate trips** — any `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED` in the field is a bug detector, not a feature.

Concretely:
1. **Row-derived action metadata (Phase 1).** The fallback derives the semantic action from the DB row, never from caller defaults: `editedAt != null && !isDeleted` → `action:'edit'` + the ORIGINAL `editedAt` and `createdAt`; `deletedAt` set → never through the chat path at all (Phase 3 dedicated route); plain rows stay plain and keep their original `createdAt`. Passing the ROW's `editedAt` (not `now()`) preserves the receiver staleness-gate ordering (`handle_incoming_chat_message_use_case.dart:308-321`). The derivation lives in a small top-level helper `deriveRetryAction(ConversationMessage msg)` so Phase 3's tombstone branch and the 115 custody sweep can share it.
2. **No-downgrade writer gate (Phase 2).** `sendChatMessage` fail-closes (`SendChatMessageResult.invalidMessage` + `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED`) any `action:'send'` invocation whose `messageId` resolves to an outgoing row carrying `editedAt` or `deletedAt`, BEFORE encryption and before the pre-race `updateWireEnvelope` at `:396-398`.
3. **Single-flight + settled-recheck (Phase 2).** A file-private in-flight id set + a candidate-start re-fetch close the double-run and stale-snapshot windows across all four retry triggers.
4. **Tombstone retry route + receiver truthfulness (Phase 3).** Deletions get a dedicated replay/rebuild route (never `sendChatMessage`; the empty-text gate stays as a correct guard); the receiver gains divergence telemetry, idempotent `ok=true` acks for superseded edits, and a content-safe staging disposition for them.

### Alternatives rejected
1. **Option (a) alone — skip the `:396-398` overwrite for edit rows.** Preserves the stored envelope but still transmits plain content under the edit id on the only production route; the receiver dedups it and the sender goes false-delivered anyway. Fixes the poisoning, not the divergence.
2. **Content-aware receiver dedup (apply divergent duplicate text).** The duplicate branch has NO author check (`handle_incoming_chat_message_use_case.dart:261-276`); applying unauthenticated content rewrites is rejected by design. We emit telemetry instead (lengths only) and keep returning `duplicate`.
3. **One-time migration to repair poisoned rows.** The edit metadata was destroyed by INSERT OR REPLACE — there is nothing to restore from. Residual accepted; sized by the field-telemetry watch (OQ-1).
4. **Exempting empty-text tombstones from the `sendChatMessage` gate so deletions can use the chat path.** Wrong layer: a deletion is not a chat send; routing it through `sendChatMessage` would re-introduce the action-defaulting hazard the gate exists to kill. Dedicated route instead; the empty-text gate (`:234-242`) is correct and stays.
5. **Repo/interface-level locking for single-flight.** Would touch `MessageRepository` and break the ~20-fake fleet (implements-no-default-bodies memory). A file-private top-level `Set<String>` covers all triggers because every trigger funnels through `_retryFailedMessageCandidate`.
6. **Excluding edit/tombstone rows from `getFailedOutgoingMessages` (`messages_db_helpers.dart:555-561`).** Starvation by another name — failed edits would simply never retry. The query stays inclusive; the candidate routes by row shape.

### Fidelity contracts (new, must be pinned by tests)
- **EF-1 (row-derived action):** any re-send of a failed outgoing row derives its semantic action from the DB row, never from caller defaults — same inner-payload shape as first-try edits (`message_payload.dart:208-220`).
- **EF-2 (no-downgrade write):** a stored edit envelope can never be overwritten by a plain-send envelope under the same id, and a failed fallback attempt can never null the row's `editedAt` — gate fires before encryption and before `:396-398`.
- **EF-3 (single-flight):** at most one retry per message id in flight at any moment across all triggers; a candidate whose row settled between load and execution is skipped, not re-sent.
- **EF-4 (receiver truthfulness):** dedup stays action-aware (edits for known ids apply — existing behavior, pinned); a superseded/identical re-applied edit is acked `ok=true` (idempotent) and its staged copy maps to `rejected/'ignored_edit'`; a non-edit duplicate with divergent text emits mismatch telemetry while still returning `duplicate`.

---

## 4. Backward / version-skew compatibility

**Pure Dart, app-side only:** no relay deploy, no gomobile rebuild, no Go changes (node.go deferred-ack and bridge confirm machinery untouched). **Wire format is unchanged** — a retried edit uses the EXACT v2 encrypted envelope shape first-try edits already use (`action`/`editedAt` live only in the encrypted inner JSON, `message_payload.dart:208-220`; the outer envelope is byte-shape-identical to any `chat_message` v2), so old relays carry it opaquely.

**Skew matrix:**
1. **NEW sender → OLD receiver:** old receivers already ship the full action-aware edit-apply path (`handle_incoming:291-321/358-368` predates this fix), so a retried edit applies correctly on every deployed build. The only behavioral delta: OLD receivers confirm a superseded identical edit with `ok=false` (the ignoredEdit→error fallthrough) — the new sender then lands the envelope in relay-inbox custody, the old receiver's staged replay re-hits ignoredEdit, and the 111 attempt cap quarantines the staged copy: bounded churn, zero loss, strictly no worse than today, self-healing as the fleet upgrades.
2. **OLD sender → NEW receiver:** old senders can still emit the downgraded plain retry — the NEW receiver still dedups by id (unchanged, so old-sender messages behave exactly as today) but now emits `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH`, giving field visibility of the residual old-fleet bug. The `ignoredEdit ok=true` change only ever ACKS MORE truthfully (the receiver provably holds equal-or-newer content), which old Go sender code consumes identically to any positive ack.
3. **Deletion rebuild:** emits the same `message_deletion` v2 envelope old receivers already parse; v1 bytes still never leave the device (`outbound_envelope_policy` preserved, fail-closed on missing recipient key).
4. **Cross-plan:** receipts in the 115 plan ack by message id, not content — this plan is the correctness floor making that safe (a receipt for a retried edit now confirms content the receiver actually displays); 116 P2 must land BEFORE 115 Phase 3's custody sweep, and both touch `retry_failed_messages_use_case.dart`/`retry_unacked_messages_use_case.dart`, so they are explicitly co-sequenced (116 first, 115 P3 rebases).

**Rollback:** each phase reverts independently to today's behavior, never worse. **Residual accepted:** rows already poisoned in the field (editedAt nulled + plain envelope persisted by past fallbacks) carry no recoverable edit metadata — no migration can restore truth; they surface via the mismatch telemetry only.

---

## 5. TDD phases

Each phase lands independently shippable. Order matters and is program-bound (Program context): **116 P1 → 116 P2 → [115 P2, 115 P3] → 116 P3**. All new test files get classified in `test-gate-definitions.md` with `./scripts/run_test_gates.sh completeness-check` kept green (rules at `test-gate-definitions.md:5, 115-122`). RED honesty rule: tests that are green-on-arrival are explicitly labeled **pins** below — the RED count per phase is only the tests that genuinely fail when written. Genuine RED counts: Phase 1 = 5, Phase 2 = 4, Phase 3 = 6 (total 15).

---

### Phase 1 — Fallback fidelity: row-derived action metadata in the full-send retry + end-to-end convergence proof (the correctness floor for plans 114/115)

**Why first:** this is the minimal change that stops minting downgraded content, and the critic declares it the correctness FLOOR for 114/115 idempotency assumptions (their backstops deliberately create duplicate deliveries absorbed by id-only dedup, which is only safe for byte-identical envelopes; and 115 Phase 2 delivery receipts ack by message id, not content — until P1 lands, a downgraded edit deduped on the receiver flips the sender 'inboxed'→'delivered' for content the receiver does not display). *(critic-fold: gap 1, red tests (a) and (c) — fallback fidelity + v1-legacy reconstruction live in this phase as the critic's slotting named.)*

#### 1.1 RED — failed-edit fidelity through the full-send fallback
File: `test/features/conversation/application/retry_failed_messages_use_case_test.dart` (extend — shared fakes + `captureFlowEvents` at `:21-48`, builders at `:50-140`).

- `'failed edit retry preserves action edit, original editedAt, and createdAt through the full-send fallback'` — New builder `makeFailedEditMessage()` (mirror `makeFailedMessage` `:62-79`): row id `'msg-edit-fail-001'`, text `'edited text'`, editedAt `'2026-01-01T00:05:00.000Z'`, createdAt `'2026-01-01T00:00:00.000Z'`, wireEnvelope = a v2 `chat_message` envelope fixture. `FakeP2PService(storeInInboxResult:false`, direct leg healthy: `discoverPeerResult`/`dialPeerResult`/`sendMessageWithReplyResult(sent:true, reply:'ack')`) so the envelope-replay `storeInInbox` fails (`:213` has no else) and the fallback fires. Bridge: `PassthroughCryptoBridge` (existing pattern `:358`). Assert `decodeWirePayload(p2pService.lastSendMessageContent!)['action'] == MessagePayload.actionEdit`, `['editedAt'] == '2026-01-01T00:05:00.000Z'`, `['id']`/`['timestamp']` == row values; `messageRepo.lastSavedMessage!.editedAt` == row editedAt and `.createdAt` == row createdAt; `messageRepo.wireEnvelopeUpdates.single` decodes to action `'edit'` (proves the `:396-398` overwrite now writes an EDIT envelope). **Fails today:** `retry_failed_messages_use_case.dart:283-298` omits `action:`/`editedAt:`/`createdAt:`, `sendChatMessage` defaults action to `actionSend` (`send_chat_message_use_case.dart:173`) and forces `resolvedEditedAt` null (`:307-309`), so `payload['action']` is absent/`'send'`, `payload['editedAt']` null, saved row editedAt null, createdAt re-minted to now.
- `'edit metadata survives a fallback attempt that fails terminally'` — Same `makeFailedEditMessage` seed; `FakeP2PService` with ALL transports failing (`storeInInboxResult:false`, `discoverPeerResult:null`, `sendMessageWithReplyResult sent:false`). After `retryFailedMessages` returns 0, assert the repo row is still status `'failed'` WITH `editedAt` == original and its wireEnvelope (via `wireEnvelopeUpdates.last`) decodes to action `'edit'`. **Fails today:** the fallback's failed persist (`send_chat_message_use_case.dart:1002-1010`, `editedAt: resolvedEditedAt == null`) rewrites the row with editedAt null via INSERT OR REPLACE (`messages_db_helpers.dart:18-22`) and `:396-398` has already poisoned the envelope to plain — the edit is unrecoverable after one attempt. This test pins the end-state repair that the P1 param fix delivers and that P2's gate defends.
- `'v1-legacy failed edit row reconstructs edit params from the DB row'` — New builder `makeFailedLegacyEditMessage()`: editedAt set on the row, wireEnvelope = `'{"type":"chat_message","version":"1",...}'` (mirror `makeFailedLegacyChatMessage` `:100-116`). Contact has mlKemPublicKey; `storeInInbox` must NOT be called with the v1 envelope (leak guard preserved, `outbound_envelope_policy.dart:3-20` routes legacy to the fallback at `:204-207`/`:236-242`); assert `RETRY_FAILED_MESSAGE_SKIP_LEGACY_WIRE_ENVELOPE` flow event still fires AND the rebuilt outgoing payload carries action `'edit'` + the row's editedAt/timestamp/id. This covers the deterministic v1-demotion feeder (`retryUnackedMessages` demotes legacy `'sent'` rows to `'failed'` at `retry_unacked_messages_use_case.dart:92-104` via `copyWith(status:'failed')`, which preserves editedAt). **Fails today:** fallback sends action `'send'`/editedAt null.
- `'plain failed retry preserves the original createdAt on the settled row'` — Extend the existing fallback test scenario (`:323-376` seed): after retry, `messageRepo.lastSavedMessage!.createdAt == '2026-01-01T00:00:00.000Z'`. **Fails today:** `createdAt` is omitted by the fallback call so `toConversationMessage` re-mints createdAt=now (`message_payload.dart:227-250`).

Companion **green-on-arrival pin** (labeled, does NOT count as RED) in `test/features/conversation/application/retry_unacked_messages_use_case_test.dart`: `'legacy demotion preserves editedAt on the demoted row'` — pins that the `:92-104` `copyWith(status:'failed')` demotion keeps editedAt intact, so Phase 1's row-derived reconstruction has the metadata it needs.

Test chore in the same commit (not RED): re-frame the `:373-374` assertions with a comment — `action != edit` / `editedAt == null` remains CORRECT for PLAIN rows (no fabricated edit metadata) but is no longer the contract for edit rows; this is the assertion the verified findings flagged as locking the bug in.

#### 1.2 RED — end-to-end convergence proof (new integration file)
File (new): `test/features/conversation/integration/edit_retry_round_trip_test.dart` — `FakeP2PNetwork` + `TestUser` template (`two_user_message_exchange_test.dart` / `inbox_round_trip_test.dart:57-120`). Plain `test()` only (zero testWidgets in this tree per infra conventions).

- `'sender and receiver text converge after a failed-then-retried edit (divergence repair)'` — Alice sends original to Bob (healthy) → Bob holds pre-edit text. Set `network.deliveryFails=true` + `network.inboxDisabled=true` (knobs verified at `fake_p2p_network.dart:13-33`); alice runs `editChatMessage` → row `'failed'` with editedAt + v2 edit envelope (`send_chat_message_use_case.dart:1002-1010`). Heal direct only (`deliveryFails=false`, `inboxDisabled` stays true so the envelope-replay `storeInInbox` fails and the fallback fires); run `retryFailedMessages` with alice's repos + a seeded `FakeIdentityRepository`. Assert: `bob.messageRepo` row text == edited text AND `editedAt != null` (edit applied via `handle_incoming_chat_message_use_case.dart:291-321/358-368`); alice row `editedAt != null` (edited badge survives, `conversation_screen.dart:531`). **Fails today:** bob's handler dedups the downgraded plain retry by id (`handle_incoming:252-276`, no text comparison), bob keeps the pre-edit text, and alice's row loses editedAt — both assertions red.

Per-type enumeration **green-on-arrival pins** in the same phase (labeled, do NOT count as RED):
- plain-row fallback — existing `:323-376` scenario, re-framed per the 1.1 chore;
- media-bearing retry — existing coverage in `retry_failed_messages_media_test.dart` (cited, no new test);
- reaction non-involvement — NEW pin in `test/features/conversation/application/send_reaction_use_case_test.dart` asserting `messageRepo` untouched on reaction failure (`send_reaction_use_case` never writes a failed messages row, `send_reaction_use_case.dart:104-119`).

#### 1.3 GREEN
`lib/features/conversation/application/retry_failed_messages_use_case.dart` — `_retryFailedMessageCandidate` fallback call (`:283-298`) only:
- Derive `final isEditRetry = msg.editedAt != null && !msg.isDeleted;` and pass `action: isEditRetry ? MessagePayload.actionEdit : MessagePayload.actionSend, editedAt: msg.editedAt, createdAt: msg.createdAt` (import `message_payload.dart`). Passing the ROW's editedAt (not now()) preserves the receiver staleness-gate ordering (`handle_incoming:308-321`). The edit contract at `send_chat_message_use_case.dart:244-253` is satisfied because messageId/timestamp/createdAt all come from the row. **No change to `sendChatMessage` itself in this phase.**
- `emitFlowEvent`: extend `RETRY_FAILED_MESSAGE_SUCCESS`/`STILL_FAILED` details with `'action'`: the derived action (telemetry parity at the use-case layer).
- Refactor note: keep the derivation as a small top-level helper `deriveRetryAction(ConversationMessage msg)` in the same file so P3's tombstone branch and the 115 custody sweep can share it.
- Test chore in the same commit: re-frame `retry_failed_messages_use_case_test.dart:373-374` comment as plain-row-only.

Interface changes: **NONE.** `sendChatMessage` already has `action`/`editedAt`/`createdAt` named params (`:173-177`); `retryFailedMessages` signature unchanged; no abstract interface or fake touched (32 implements-P2PService fakes, 20 implements-MessageRepository fakes all untouched). New test builders + one new integration test file only.

#### 1.4 Gate
`flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/features/conversation/integration/` green; `./scripts/run_test_gates.sh 1to1` green; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green; `./scripts/run_test_gates.sh completeness-check` green (new integration file classified — final gate-array/Gate-Capture edit is the Phase 3 coordinated chore). Regression sanity: `(cd go-mknoon && make test)` and `(cd go-relay-server && go test ./...)` green (no Go changes expected — any red means scope leak).

---

### Phase 2 — Poisoning guard + single-flight: no plain envelope may ever replace an edit envelope, no double-running of a retry

> ### ⚠️ DECLARED PREREQUISITE OF 115 PHASE 3 (CUSTODY SWEEP) — DO NOT REORDER
>
> The 115 relay plan's Phase 3 custody sweep **re-stores `wire_envelope` on every sweep cycle**. Without 116 P1+P2, a poisoned plain envelope would be re-propagated under the same message id every sweep period — **amplifying the edit bug from one-shot to recurring**. This phase MUST be landed and green before any 115 Phase 3 work begins. *(critic-fold: gap 7 — sequencing constraint declared in both docs; 115 P3 inherits the green-on-arrival pin authored below.)*
>
> Co-sequencing rule: this phase and 115 Phase 3 modify the same `retry_failed_messages_use_case.dart` + `retry_unacked_messages_use_case.dart` test regions — **land 116 P1+P2 first, then 115 P3 rebases on the `deriveRetryAction` helper** and inherits the pin 'sweep re-store of an edit row carries action:edit'.

**Why here:** P1 fixes the only production route's content; P2 makes the downgrade **unmintable and unpersistable** by any caller, and closes the concurrency windows (double-run, stale snapshot) that the critic flagged as untested everywhere. Status-model neutrality: this phase deliberately asserts action/editedAt/envelope content, not status strings, so it composes with 115 Phase 1's 'inboxed' rename in either landing order.

#### 2.1 RED — no-downgrade writer gate in sendChatMessage
File: `test/features/conversation/application/send_chat_message_use_case_test.dart` (extend — in-file rich FakeP2PService `:33-160`, `captureFlowEvents` pattern).

- `'refuses a plain send under an edited message id and leaves the stored edit envelope untouched'` — Seed fake repo with an outgoing row id X carrying editedAt + wireEnvelope = v2 edit envelope; call `sendChatMessage(messageId: X, text: 'anything', action default)`. Assert result == `SendChatMessageResult.invalidMessage`, returned message null, `messageRepo.wireEnvelopeUpdates isEmpty` (the `:396-398` overwrite never ran), row unchanged (status/editedAt/wireEnvelope), and flow event `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED` with reason `'edited_row_plain_send'` (`captureFlowEvents` pattern). **Fails today:** the call proceeds — encrypts a plain payload, overwrites the envelope (`wireEnvelopeUpdates` length 1 decoding to action-less inner JSON), and transmits plain content under the edit id.
- `'refuses a plain send under a deleted tombstone id'` — Seed outgoing row id Y with deletedAt set (`buildDeletedMessageTombstone` shape, `delete_message_use_case.dart:386-405`) and call `sendChatMessage(messageId: Y, text: 'non-empty so the empty-text gate does not mask the check')`. Assert `invalidMessage` + `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED` reason `'deleted_row_plain_send'`, no wireEnvelope update. **Fails today:** with non-empty text the send proceeds and transmits a plain chat payload under a tombstone id (resurrection hazard); only `text==''` is blocked (`:234-242`).

#### 2.2 RED — single-flight + settled-skip *(critic-fold: gap 5 — "concurrent-retry-vs-edit red test goes in the new edit plan")*
File: `test/features/conversation/application/retry_failed_messages_use_case_test.dart`.

- `'concurrent retries of the same failed row send at most once (single-flight per message id)'` — `FakeP2PService` subclass (mirror `_PerMessageThrowingP2PService` `:165-193`) whose `storeInInbox` awaits a test-held Completer. Seed one failed row with v2 envelope; launch `Future.wait([retryFailedMessage(id...), retryFailedMessage(id...)])`; complete the gate; assert `storeInInboxCallCount == 1`, `sendMessageWithReplyCallCount == 0` extra sends, one call returned 1 and the other 0, and `RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT` was emitted once. Models the real overlap of PendingMessageRetrier periodic + reconnect debounce + app-resume 8c + UI retry button. **Fails today:** no guard exists — both invocations run the candidate, two `storeInInbox` calls (and on fallback routes, two full sends of the same id, each re-running the `:396-398` envelope overwrite).
- `'retry candidate skips a row that settled between load and execution'` — In-file `FakeMessageRepository` subclass overriding `getFailedOutgoingMessages` to return a STALE copy (status `'failed'`) of a row whose current stored state is `'delivered'`. `retryFailedMessages` must not send anything (`storeInInboxCallCount` 0, `sendMessageWithReplyCallCount` 0) and must emit `RETRY_FAILED_MESSAGE_SKIPPED_SETTLED`. **Fails today:** the candidate trusts the loaded list and re-sends a delivered message (duplicate full-send under a settled id).

Companion **green-on-arrival pin** (labeled, does NOT count as RED): `'retried edit pre-race envelope persist writes an edit envelope'` — post-P1, the explicit prerequisite pin the 115 plan's Phase 3 needs (a custody-sweep re-store of an edit row carries `action:edit`). 115 P3 inherits this pin after its rebase.

#### 2.3 GREEN
`lib/features/conversation/application/send_chat_message_use_case.dart` — insert the downgrade gate immediately after the edit-contract validation (`:244-253`) and BEFORE payload build/encrypt/`updateWireEnvelope`:

```dart
if (action == MessagePayload.actionSend && messageId != null) {
  final existing = await messageRepo.getMessage(messageId);
  if (existing != null && !existing.isIncoming &&
      (existing.editedAt != null || existing.isDeleted)) {
    emitFlowEvent(/* CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED,
        reason: edited_row_plain_send | deleted_row_plain_send */);
    emitSendTiming(outcome: 'action_downgrade_blocked');
    return (SendChatMessageResult.invalidMessage, null);
  }
}
```

One extra repo read ONLY on retry-shaped calls (`messageId` is non-null only for retries/edits; the check is skipped for `actionEdit`). Verified: all UI retry paths route through `retryFailedMessage` (`conversation_wired.dart:2197-2235`), so the gate has zero legitimate trips.

`lib/features/conversation/application/retry_failed_messages_use_case.dart`:
- Top-level private `final Set<String> _retryInFlightMessageIds = {};`
- `_retryFailedMessageCandidate`: (1) `if (!_retryInFlightMessageIds.add(msg.id))` emit `RETRY_FAILED_MESSAGE_SKIPPED_IN_FLIGHT` and return false; wrap the body in try/finally removing the id; (2) settled-recheck at candidate start: re-fetch `messageRepo.getMessage(msg.id)`; if null/incoming/status != `'failed'` emit `RETRY_FAILED_MESSAGE_SKIPPED_SETTLED` and return false — and use the FRESH row for all subsequent derivation, closing the stale-snapshot window.

Interface changes: **NONE on any abstract interface** — the single-flight set is a file-private top-level, the gate uses the existing `MessageRepository.getMessage`. Zero fake breakage (`fake_message_repository.dart` already implements `getMessage`; no new members anywhere).

#### 2.4 Gate
`flutter test test/features/conversation/application/send_chat_message_use_case_test.dart test/features/conversation/application/retry_failed_messages_use_case_test.dart` green; `./scripts/run_test_gates.sh 1to1` green; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green; `./scripts/run_test_gates.sh completeness-check` green. Go regression sanity per G6. **Hand-off checkpoint: notify the 115 owner that the P3 prerequisite is green (the pin 'retried edit pre-race envelope persist writes an edit envelope' exists and passes) before any 115 Phase 3 work starts.**

---

### Phase 3 — Tombstone liveness + receiver divergence defense: delete-for-everyone retry route, duplicate-content-mismatch telemetry, idempotent edit ack

**Why last (program step 6):** lands after 115 Phase 1, so the tombstone retry terminal adopts the 115 status decision directly instead of writing a string that must immediately flip (see STATUS-MODEL COUPLING below). *(critic-fold: gap 1, red tests (d) tombstone decision and (e) receiver mismatch telemetry — slotted here per the critic's "tombstone/telemetry" phase naming.)*

#### 3.1 RED — tombstone retry trio (sender side)
File: `test/features/conversation/application/retry_failed_messages_use_case_test.dart`.

- `'failed delete tombstone retries over the direct leg instead of bouncing off the empty-text gate'` — Seed `makeFailedDeletedMessage()` (existing builder `:81-98`, v2 `message_deletion` envelope, text `''`); `FakeP2PService(storeInInboxResult:false, sendMessageWithReplyResult sent:true acked)`. Assert count == 1; `p2pService.lastSendMessageContent` decodes to type `'message_deletion'` version `'2'` (the STORED envelope replayed byte-identical over the direct stream — the router on the receiver dispatches by envelope type regardless of transport); saved row status terminal-delivered shape via `normalizeOutgoingDeleteTombstoneVisibility` with wireEnvelope null; `sendChatMessage` never invoked (no `CHAT_MSG_SEND_START` flow event). DECISION ENCODED (critic gap (d)): tombstones get a dedicated retry route — rebuild/replay the deletion envelope, never the chat-send path; the empty-text gate (`:234-242`) stays as a correct guard. **Fails today:** envelope-replay `storeInInbox=false` falls through to `sendChatMessage` which returns `invalidMessage` on `text==''` — count 0, nothing sent, the receiver keeps showing a message the sender believes is deleted, forever.
- `'legacy v1 delete tombstone is rebuilt as a v2 deletion envelope before any send'` — Seed `makeFailedLegacyDeletedMessage()` (existing builder `:118-136`) + contact with mlKemPublicKey + `storeInInboxResult:true`. Assert the envelope handed to `storeInInbox` is type `'message_deletion'` with version `'2'` and an `'encrypted'` block (`PassthroughCryptoBridge`), v1 bytes never reach any transport (leak guard intact), row settles delivered/inbox, count 1. **Fails today:** legacy skip (`:204-207`) → fallback → empty-text bounce → stays `'failed'` forever (this is also the v1-demotion feeder terminal state for deletions: `retry_unacked_messages_use_case.dart:92-104` demotes a legacy `'sent'` tombstone into exactly this starvation).
- `'legacy tombstone without a recipient key stays failed with explicit telemetry, never leaks v1'` — Same seed, contact mlKemPublicKey null. Assert count 0, no `storeInInbox`/send calls, row still `'failed'`, and new flow event `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE {reason:'missing_recipient_key'}`. **Fails today** only on the telemetry (end state is the same silent starvation but with zero observability) — counted RED because the event does not exist; this is the fail-closed cell of the rebuild matrix.

#### 3.2 RED — receiver divergence defense
File: `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`.

- `'emits duplicate-content-mismatch telemetry when a non-edit duplicate carries different text'` — Seed existing incoming row id X text `'pre-edit'`; deliver a plain (non-edit) payload id X text `'post-edit'` via the existing v2 fixture helpers. Assert result is still `HandleChatMessageResult.duplicate` (no content apply — the duplicate branch has NO author check, so applying unauthenticated content rewrites is rejected by design) AND `captureFlowEvents` contains `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` with id prefix + `incomingTextLength`/`existingTextLength` (no plaintext in logs). **Fails today:** only `CHAT_MSG_RECEIVE_DUPLICATE` fires (`handle_incoming:270-274`); divergence is invisible. Defense-in-depth per the critic (gap (e)): with P1/P2 landed this event firing in the field means a pre-fix poisoned row or an unknown downgrade path — it is the field-detection canary.

Companion **green-on-arrival pin** (labeled, does NOT count as RED): `'applies a retried edit for a known id instead of dropping it'` — the action-aware dedup half already exists (`:291-321, 358-368`).

#### 3.3 RED — idempotent edit ack + staging disposition
File: `test/features/conversation/application/chat_message_listener_test.dart`.

- `'confirms a superseded (ignored) edit nonce with ok=true (idempotent edit re-application)'` — Receiver already holds row id X with editedAt T; incoming v2 edit payload id X with the SAME editedAt T and confirmNonce `'n1'` → `handleIncomingChatMessage` returns `ignoredEdit` (staleness gate `:308-321`). Assert the listener calls `callP2PConfirmDirectMessage(nonce:'n1', ok:TRUE)` (mirror the existing `'confirms duplicate direct chat nonce with ok=true'` test `:756-771`). **Fails today:** `HandleChatMessageResult.ignoredEdit` has no branch in `processIncomingMessage` — it falls through to the `ChatMessageProcessState.error` outcome (`chat_message_listener.dart:564-570`) and confirms `ok=false`, so once P1 makes retried edits real edits, a lost-ack retry (the benign subcase) would otherwise loop forever: ack false → sender unacked → inbox handoff → staged replay → ignoredEdit → retryable `'listener_error'` churn until the 111 attempt cap. This test closes that loop.

File: `test/features/conversation/application/recovered_inbox_chat_disposition_test.dart`.

- `'maps ignoredEdit replay outcome to rejected with reason ignored_edit'` — `mapChatReplayOutcomeToDisposition(outcome with new state ChatMessageProcessState.ignoredEdit)` returns `(disposition: rejected, reasonCode: 'ignored_edit')` — content-safe destruction of the staged superseded copy (the receiver provably holds equal-or-newer editedAt; same INV-1 reasoning as the `'duplicate'` row of the matrix, `recovered_inbox_chat_disposition.dart:74-79`). **Fails today at compile time:** the enum value does not exist — adding it breaks the exhaustive switch and drives the implementation.

#### 3.4 GREEN
`lib/features/conversation/application/retry_failed_messages_use_case.dart` — at the top of `_retryFailedMessageCandidate`'s post-envelope-replay section: `if (msg.isDeleted) return _retryFailedDeletionTombstone(...)` — new private helper:
1. Stored v2 envelope present → replay it via `p2pService.sendMessageWithReply` (acceptance bar mirrors `delete_message_use_case`'s direct leg); on success persist `normalizeOutgoingDeleteTombstoneVisibility(msg.copyWith(status:'delivered', transport: via, wireEnvelope: null))` + `RETRY_FAILED_DELETE_TOMBSTONE_SUCCESS`.
2. Legacy v1 or missing envelope → rebuild v2 via the extracted builder (below) using `contact.mlKemPublicKey`, then storeInInbox-first/direct-second; missing key → `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE`, stay `'failed'`. Never call `sendChatMessage`.

`lib/features/conversation/application/delete_message_use_case.dart` — REFACTOR: extract the inline deletion-envelope construction into top-level `Future<String?> buildDeletionWireEnvelope({required Bridge bridge, required String recipientMlKemPublicKey, required ConversationMessage tombstone, required String senderPeerId})` (function seam per 112 §9.3 — no interface change; `delete_message_use_case`'s own send path delegates to it, pinned by its existing suite staying green).

`lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` — in the duplicate branch (`:261-276`), before returning duplicate: `if (payload.text != existingMessage.text)` emitFlowEvent `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH {id prefix, incomingTextLength, existingTextLength, existingHasEditedAt}`.

`lib/features/conversation/application/chat_message_listener.dart` — add `ChatMessageProcessState.ignoredEdit` (enum at `:26`); map `HandleChatMessageResult.ignoredEdit` → new explicit branch returning that state; `_confirmationValueForState`: `ignoredEdit → true` (`:248-264`).

`lib/features/conversation/application/recovered_inbox_chat_disposition.dart` — new switch case `ignoredEdit → rejected/'ignored_edit'`.

`emitFlowEvent` at every touched layer per house rules.

Interface changes:
- `ChatMessageProcessState` +1 enum value `ignoredEdit` — breaks exactly TWO exhaustive switches, both production: `chat_message_listener.dart` `_confirmationValueForState` (`:248-264`) and `recovered_inbox_chat_disposition.dart` `mapChatReplayOutcomeToDisposition` (`:19-86`); compile-driven, fixed in the same commit. Verified non-breakage elsewhere: `lib/main.dart` uses only `==` comparisons (`:1610`/`:1625`); test referencers (`chat_message_listener_test.dart`, `recovered_inbox_chat_disposition_test.dart`, `post_restore_stale_key_recovery_test.dart`, `two_user_message_exchange_test.dart`) reference values, not exhaustive switches — the disposition matrix test gains one row. Enums have no implements-fakes: zero of the 32 P2PService / 20 MessageRepository fakes touched.
- New top-level function `buildDeletionWireEnvelope` (extracted) — function seam, breaks nothing.
- No Bridge/P2PService/MessageRepository/repository interface changes anywhere in this plan.

**STATUS-MODEL COUPLING (the one place this plan touches status strings):** the tombstone retry persists today's `'delivered'`/`'inbox'` terminals. The 115 relay plan renames inbox custody to `'inboxed'` and its critic-flagged major gap is that deletion envelopes get no delivery receipts (orphaned `'inboxed'` + the visibility gate at `delete_message_tombstone_visibility.dart:14` keys on `'delivered'`). Coordinate: if 116 P3 lands BEFORE 115 Phase 1, write today's strings and list both tests in the 115 contract-flip chore; if AFTER (the program's intended order), adopt the 115 decision (receipt-extension or pinned chat_message-only `'inboxed'` scope) directly. Recorded in both docs' Review-resolution logs; ownership of the flip commit is OQ-4.

#### 3.5 Gate + doc chore
`flutter test test/features/conversation/application/retry_failed_messages_use_case_test.dart test/features/conversation/application/send_chat_message_use_case_test.dart test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart test/features/conversation/application/delete_message_use_case_test.dart test/features/conversation/application/chat_message_listener_test.dart test/features/conversation/application/recovered_inbox_chat_disposition_test.dart` green; `./scripts/run_test_gates.sh 1to1` green; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline` green; `./scripts/run_test_gates.sh completeness-check` green. Go regression sanity per G6.

Doc chore closing the plan *(critic-fold: gap 8 — numbering collision / coordinated gate edit)*: add '## 116 Edit Retry Fidelity Gate Capture' to `test-gate-definitions.md`; add `edit_retry_round_trip_test.dart` to the 1:1 Reliability Gate Files list in BOTH the gate doc (`:233-271`) and the `scripts/run_test_gates.sh` 1to1 array — as a SINGLE coordinated gate-array edit with the 114/115 plans (whichever doc closes last merges the array; if 116 closes last, this chore executes the merged edit, otherwise it hands its two entries to the closing doc).

---

## 6. Test matrix (row shape × retry route × side)

| Row / scenario | Route | Side | Covering test (phase) |
|---|---|---|---|
| edit row, v2 envelope, inbox store fails | full-send fallback | sender | `retry_failed_messages_use_case_test.dart` fidelity test (P1.1) |
| edit row, all transports fail | fallback terminal persist | sender | 'edit metadata survives…fails terminally' (P1.1) |
| legacy v1 edit row | fallback rebuild (leak guard) | sender | v1-legacy reconstruction test (P1.1) |
| legacy `'sent'` edit row demoted to `'failed'` | v1-demotion feeder | sender | `retry_unacked_messages_use_case_test.dart` editedAt-preservation **pin** (P1.1) |
| plain row | full-send fallback | sender | createdAt test (P1.1) + re-framed `:323-376` **pin** |
| media-bearing failed row | fallback attachments | sender | existing `retry_failed_messages_media_test.dart` (**pin**, cited P1.2) |
| reaction failure | (never enters pipeline) | sender | `send_reaction_use_case_test.dart` non-involvement **pin** (P1.2) |
| failed-then-retried edit, divergence repair | end-to-end | both | `edit_retry_round_trip_test.dart` (P1.2, NEW file) |
| plain send under edited id | writer gate | sender | `send_chat_message_use_case_test.dart` (P2.1) |
| plain send under tombstone id | writer gate | sender | `send_chat_message_use_case_test.dart` (P2.1) |
| concurrent same-id retries | single-flight | sender | concurrency test (P2.2) |
| row settled between load and execution | settled-recheck | sender | stale-snapshot test (P2.2) |
| sweep re-store of an edit row (115 P3 prerequisite) | envelope persist | sender | 'pre-race envelope persist writes an edit envelope' **pin** (P2.2) |
| v2 tombstone, inbox store fails | direct replay route | sender | tombstone direct-leg test (P3.1) — **CLOSED host, 2026-06-13** |
| legacy v1 tombstone, key present | v2 rebuild route | sender | legacy rebuild test (P3.1) — **CLOSED host, 2026-06-13** |
| legacy v1 tombstone, key missing | fail-closed + telemetry | sender | `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` test (P3.1) — **CLOSED host, 2026-06-13** |
| non-edit duplicate, divergent text | dedup + canary telemetry | receiver | mismatch-telemetry test (P3.2) — **CLOSED host, 2026-06-13** |
| edit for known id | action-aware apply | receiver | 'applies a retried edit…' **pin** (P3.2) |
| superseded identical edit | idempotent ack ok=true | receiver | `chat_message_listener_test.dart` (P3.3) — **CLOSED host, 2026-06-13** |
| staged superseded edit replay | disposition `rejected/'ignored_edit'` | receiver | `recovered_inbox_chat_disposition_test.dart` (P3.3) — **CLOSED host, 2026-06-13** |
| old receiver vs new sender's retried edit | skew cell 1 | both | host: compatibility prose §4; device: evidence item 3 |
| old sender's downgraded retry vs new receiver | skew cell 2 | receiver | mismatch telemetry (P3.2) + device evidence item 3 |

---

## 7. Risks and open questions carried forward

### Risks (actively mitigated by this plan; verify at each phase)
- **R1 Enum exhaustive-switch breakage** — `ChatMessageProcessState.ignoredEdit` breaks exactly two production switches (verified, Phase 3 interface notes); compile-driven, same-commit fix; no fakes touched (enums have no implements-fakes).
- **R2 Test-region collision with 115 Phase 3** — both edit `retry_failed_messages_use_case.dart`/`retry_unacked_messages_use_case.dart` and their suites; mitigated by the mandatory co-sequencing (116 first, 115 P3 rebases on `deriveRetryAction`) and the Phase 2.4 hand-off checkpoint.
- **R3 Status-string coupling** — only the Phase 3 tombstone terminal touches status strings; everything else asserts action/editedAt/envelope content (status-model neutral by design); coordination rule + OQ-4 own the flip.
- **R4 Single-flight set vs process model** — the file-private `Set<String>` covers all four triggers because every trigger funnels through `_retryFailedMessageCandidate` in the same isolate; if a future change moves retries to a background isolate, the guard must move with it (note in code comment).
- **R5 Downgrade gate false-positives** — the gate fires only on `action==actionSend && messageId != null` against rows with editedAt/deletedAt; verified all UI retry paths route through `retryFailedMessage`, so legitimate trips are zero. Any field occurrence of `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED` = bug detector.
- **R6 Poisoning preconditions narrower than the headline** (verdict correction) — the `:396-398` overwrite runs only after several early returns (node not running `:256-264`, encryptionRequired `:266-282`, media gate `:289-301`, encrypt failure `:353-366, :376-384`, empty text `:234-242`); in those cases the row keeps its intact edit envelope. The Phase 2.1 tests pin the boundary where poisoning DOES occur (recipient key present, encryption succeeds — the normal case).
- **R7 Media-bearing edit rows can stall before the fallback** (verdict correction) — `_resolveAttachmentsForRetry` skipReasons (upload_cancelled `:356-363`, localFileMissing `:386-391`) return false BEFORE the fallback; those edit rows stay `'failed'` undowngraded. Text-only edits have no such barrier. No new test needed; noted so the matrix isn't misread as covering a non-existent route.
- **R8 121-improvements is an uncommitted moving baseline** (112/113/111/114/115 work in flight) — pin tests against branch state; re-verify anchors per session (Caveat 9.4).

### Open questions (unresolved — owner input needed)
- **OQ-1** Already-poisoned field rows: a pre-fix fallback nulled editedAt and stored a plain envelope — no migration can recover the edit metadata. Accept silently (current plan) or add a one-time UI annotation for outgoing rows whose receiver reported content mismatch? Decide after the field-telemetry watch (Evidence item 6).
- **OQ-2** Should duplicate-content-mismatch ever trigger automated repair (receiver-initiated resend/content-reconcile)? Deferred: requires authenticated content-replacement semantics in the duplicate branch (it has no author check today) — a new protocol surface, out of scope for this correctness fix.
- **OQ-3** Listener fallthrough for `HandleChatMessageResult.unauthorized` also lands on error/confirm-false (same pattern ignoredEdit had) — an unauthorized edit retry will churn to the 111 attempt cap. Harden in a follow-up or accept (it is an attack/foreign-sender path, not a user-loss path)?
- **OQ-4** Status-string flip coordination: tombstone retry terminals written as `'delivered'`/`'inbox'` today must flip to the 115 plan's custody model (`'inboxed'` + receipt or pinned exclusion for `message_deletion`) in whichever plan lands second — tracked in both docs' Amendment logs; who owns the flip commit?
- **OQ-5** Should `editChatMessage`'s `'failed_message_requires_retry'` rejection (`send_chat_message_use_case.dart:1060-1067`) gain a UI affordance distinguishing 'retry will resend your edit' from plain retry, now that retry truly preserves the edit? UX-only follow-up.
- **OQ-6** `retryUnackedMessages` legacy demotion (`:92-104`) still funnels v1-era rows into the fallback by design — with P1 the fallback now reconstructs correctly, but should demotion eventually rebuild v2 envelopes in place instead (one less hop)? Defer until 115 Phase 3 rewrites that file anyway.

---

## 8. Evidence bar for closure (per project closure-bar convention)

1. **Suites:** all phase gates green — `flutter test test/features/conversation/application test/features/conversation/integration`; `./scripts/run_test_gates.sh 1to1`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`; `./scripts/run_test_gates.sh completeness-check` green; regression sanity `(cd go-mknoon && make test)` and `(cd go-relay-server && go test ./...)` green (any Go red = scope leak; this plan ships no Go change).
2. **Two-device divergence repro→repair:** Pixel6 (`21071FDF600CSC`) + iPhone13 (`--profile` per the iOS 26.5 JIT memory) — deliver a 1:1 message, blackhole the relay at the router and background the receiver, edit on the sender until the row shows failed; restore direct/LAN reachability with relay still blocked, tap retry — receiver must display the EDITED text with the edited badge and the sender's edited badge must survive (`conversation_screen.dart:531`); capture FLOW logs showing `RETRY_FAILED_MESSAGE_SUCCESS` with `action:edit` on the sender and the edit-apply (not `CHAT_MSG_RECEIVE_DUPLICATE`) on the receiver. Host fakes cannot reproduce real transport-race timing + Go deferred-ack interleaving.
3. **Lost-ack idempotency on hardware:** force the benign subcase (edit delivered but ack lost — kill the sender app inside the ack window), retry on relaunch — receiver FLOW must show ignoredEdit confirmed `ok=true` and the sender must settle delivered without a retry loop; verifies the Go confirmNonce path end-to-end with the new listener mapping.
4. **Mixed-version interop:** previous TestFlight build as RECEIVER against a new-build sender's retried edit (applies via the old edit path, edited text visible); and old build as SENDER against a new receiver (downgraded retry still dedups, `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` appears in the new receiver's logs) — confirms both skew cells on real fleet binaries.
5. **Delete-for-everyone retry on device:** relay blackholed, delete-for-everyone fails, retry over direct/LAN — message disappears on the receiver, tombstone hides on the sender once terminal; FLOW shows the `message_deletion` v2 replay, never a `chat_message` frame.
6. **Cross-plan canary + field telemetry watch:** after 115 Phase 3 deploys, observe one custody-sweep re-store of an edit row on a real device and confirm the re-stored envelope applies as an edit on the receiver (the G2/115-P3 prerequisite holding under the real sweep cadence against the production relay mknoun.xyz). Plus a 1–2 week watch of `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` occurrence in collected device logs to size the pre-existing poisoned-row population, informing OQ-1.
7. **Docs:** `test-gate-definitions.md` updated ('## 116 Edit Retry Fidelity Gate Capture' + `edit_retry_round_trip_test.dart` in the 1to1 Files list, as the single coordinated gate-array edit with 114/115); this doc updated with closure verdicts per phase.

---

## 9. Verified caveats

### 9.1 No DB migration, no relay deploy, no gomobile rebuild
Pure Dart, app-side only. No schema change (no new columns or status strings minted by this plan — the Phase 3 tombstone terminal reuses whatever the 115 foundation defines). Go node/relay untouched; the Go suites run as scope-leak detectors only (G6).

### 9.2 `implements`-based fakes and the one enum change
No Bridge/P2PService/MessageRepository interface changes anywhere (32 + 20 implements-fakes untouched). The single type-level change is `ChatMessageProcessState` +1 value, which breaks exactly two exhaustive production switches (verified: `chat_message_listener.dart:248-264`, `recovered_inbox_chat_disposition.dart:19-86`); `lib/main.dart` uses `==` only (`:1610/:1625`); test referencers reference values, not exhaustive switches. The two new production seams are top-level functions (`deriveRetryAction`, `buildDeletionWireEnvelope`) per the project's function-seam preference (112 §9.3).

### 9.3 Poisoning boundary (verdict corrections folded in)
The downgrade+poisoning requires the recipient ML-KEM key to be present and encryption to succeed — the `:396-398` overwrite sits after several early returns (node-not-running, encryptionRequired, media gate, encrypt failure, empty text), in all of which the fallback exits with NO persist and the row keeps its intact edit envelope. Media-bearing edit rows can additionally stall at `_resolveAttachmentsForRetry` skipReasons BEFORE the fallback (no downgrade). The "benign-looking subcase" (edit actually reached the receiver, sender marked failed) is a thin transport edge: a written-but-unacked live edit yields `'sent'`, not `'failed'` (`send_chat_message_use_case.dart:1755-1763`); reaching `'failed'` requires race+probe+inbox all to fail. And a FALSE-NEGATIVE storeInInbox leaves the edit envelope on the relay where a later inbox drain heals the divergence — permanent divergence requires a genuine store failure plus a live fallback leg. The TDD tests pin the harmful boundary, not the benign edges.

### 9.4 Line-number re-check
All file:line anchors verified 2026-06-12 against the UNCOMMITTED 121-improvements tree (carries 111/112/113, move-scale, voice-wake-lock, and in-flight 114/115 work). The verdict confirmed claim line numbers exact at verification time (one correction: `dbRecoverStuckSendingMessages` UPDATE is at `messages_db_helpers.dart:795-798`, not 769/796-797 — `:769` is a doc-comment line noting `wire_envelope` is typically NULL for stuck-'sending' rows, so that feeder usually routes straight to the fallback). Re-verify before each session; 115 Phase 1 landing first WILL shift `send_chat_message_use_case.dart` anchors.

### 9.5 Using the arch graph during implementation
Per 112 §9.6 discipline: anchor `graphify query` on 1–2 exact symbol names (e.g. `graphify query "retryFailedMessages _retryFailedMessageCandidate"`), never prose; refresh after every edit batch (`./graphify-arch/refresh_arch_graph.sh` from repo root — never run graphify build/update with cwd inside `graphify-arch/`). The trace for this doc was graph-first with every cited line re-read in source; one pipe-filtered token scan proved the retry test file contains no failed-edit seed anywhere (the `:373-374` assertion is the only `actionEdit`/`editedAt` mention — the bug is effectively locked in as 'correct' until Phase 1.1 rewrites that framing).

### 9.6 Post-downgrade user-repairability (severity bound, not a mechanism)
After the downgrade the sender row is `'delivered'`, so `editChatMessage` is no longer blocked (`:1060-1067` only rejects `'failed'`) — a manual re-edit would propagate correctly. Not compensation: nothing signals the user (the sender's text already reads as intended; only the badge quietly vanished). Bounds severity slightly; the divergence is user-repairable but invisibly broken.

---

## Review resolution log

**2026-06-13 (Phases 1–2 implementation notes):**
1. **Landing order followed:** 115 Phase 1 landed first (status `'inboxed'` + migration 077/v77 are in the tree); this doc's Phases 1–2 were implemented against that landed state — the status-model-neutral design held (no test in these phases asserts status strings beyond seeding fixtures).
2. **Anchor drift (noted, harmless):** `retry_failed_messages_use_case_test.dart` builders sit at `:62-136` (not `:50-140`) and the plain-row assertion the plan calls `:373-374` sat at `:373-374` pre-edit — both matched in substance; re-framed per the 1.1 chore.
3. **In-file FakeMessageRepository `getMessage` (test-fake change):** the rich in-file fake in `send_chat_message_use_case_test.dart` hardcoded `getMessage → null`; the writer gate needs seedable rows, so it gained an `existingMessages` map (empty by default — zero behavior change for the 120+ existing tests in that file).

## Closure log

**Phase 1 — CLOSED (host). 2026-06-13.**
- RED (5, confirmed failing for the documented reasons): fallback fidelity (`payload['action']` null, expected `'edit'`), terminal-failure metadata survival (`editedAt` nulled), v1-legacy reconstruction (action null), plain-row createdAt re-mint (now() vs original), and the end-to-end convergence test (bob kept `'original text'`, the downgraded retry deduped by id). Pins green-on-arrival as labeled: legacy-demotion-preserves-editedAt (`retry_unacked_messages_use_case_test.dart`), reaction non-involvement source pin (`send_reaction_use_case_test.dart`); plain-row/media coverage cited per plan.
- GREEN: top-level `deriveRetryAction(ConversationMessage)` helper (EF-1, shared with 116 P3 + 115 P3); `_retryFailedMessageCandidate` fallback now passes `action`/`editedAt`/`createdAt` from the ROW; `RETRY_FAILED_MESSAGE_SUCCESS`/`STILL_FAILED` carry `action`. New integration file `test/features/conversation/integration/edit_retry_round_trip_test.dart` (classified; completeness-check 837/837 PASS).
- Gate: retry+send+integration suites green; `flutter test test/features/conversation` 1141 green; `./scripts/run_test_gates.sh 1to1` exit 0; Go regression sanity `(cd go-mknoon && make test)` exit 0, `(cd go-relay-server && go test ./...)` exit 0 (no scope leak).

**Phase 2 — CLOSED (host). 2026-06-13.**
- RED (4, confirmed): writer gate edited-id (proceeded `success`, envelope overwritten), writer gate tombstone-id (plain chat payload transmitted under a tombstone id), single-flight (2 `storeInInbox` calls for one id), settled-skip (stale `'failed'` snapshot re-sent over a `'delivered'` row). Companion pin green-on-arrival post-P1: `'retried edit pre-race envelope persist writes an edit envelope'` — **the 115 P3 prerequisite pin now EXISTS and PASSES** (hand-off checkpoint satisfied; 115 P3 may begin).
- GREEN: `CHAT_MSG_SEND_ACTION_DOWNGRADE_BLOCKED` fail-closed gate in `sendChatMessage` (after the edit-contract validation, before encrypt/`updateWireEnvelope`; reasons `edited_row_plain_send`/`deleted_row_plain_send`; `emitSendTiming(outcome: 'action_downgrade_blocked')`); file-private `_retryInFlightMessageIds` single-flight set + settled-recheck (fresh-row re-fetch) in `_retryFailedMessageCandidate` with try/finally release.
- Gates: `flutter test test/features/conversation test/core` 2967 green; `1to1` exit 0; `completeness-check` 837/837 PASS; macOS baseline green (exit 0). Interface changes: NONE on abstract interfaces (gate uses existing `MessageRepository.getMessage`; zero fake breakage).
- Then-open (resolved later): Phase 3 (tombstone liveness + receiver divergence defense) lands at program step 6, after 115 P2–P3; device evidence items §8 are now archived as unclaimed residual lab evidence.

**Phase 3A — CLOSED (host). 2026-06-13.**
- RED (confirmed): direct-leg v2 tombstone retry returned count 0 after inbox failure; successful v2 inbox retry used delivered/hidden semantics instead of `inboxed` custody; legacy v1 tombstone with key did not rebuild to v2; legacy v1 tombstone without key had no explicit fail-closed telemetry; `buildDeletionWireEnvelope` did not exist as a shared builder seam.
- GREEN: `buildDeletionWireEnvelope` extracted from `deleteMessageForEveryone`; `_retryFailedDeletedTombstone` now handles deleted failed rows before `sendChatMessage`, preserves the empty-text chat guard, retries safe v2 `message_deletion` envelopes through inbox/direct, rebuilds legacy v1 tombstones to encrypted v2 when the recipient key exists, emits `RETRY_FAILED_DELETE_REBUILD_UNAVAILABLE` on missing key, and uses landed 115 `inboxed` custody semantics for deletion inbox storage.
- Gates: direct retry/delete suite passed 41 tests; macOS baseline passed; completeness-check passed 841/841; `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from repo root. The later final `./scripts/run_test_gates.sh 1to1` rerun passed with `+793` after the aggregate bridge timeout test was made deterministic and the send-then-lock 7c expectation was aligned with Doc 115 receipt-gated custody semantics.
- Then-open (resolved later): Phase 3B receiver divergence/ignored-edit idempotency and final 116 gate capture are now closed; device evidence items §8 are archived as unclaimed residual lab evidence.

**Phase 3B — CLOSED (host). 2026-06-13.**
- GREEN: receiver duplicate mismatch telemetry now emits `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH` with id prefix and text lengths only, while still returning duplicate and leaving stored content unchanged. `HandleChatMessageResult.ignoredEdit` now maps to `ChatMessageProcessState.ignoredEdit`, confirms direct nonces with `ok=true`, and maps staged ignored-edit replays to `rejected/'ignored_edit'`.
- Gates: direct receiver/listener/disposition suite passed 96 tests; macOS baseline passed; completeness-check passed 841/841; `git diff --check` passed; `./graphify-arch/refresh_arch_graph.sh` passed from repo root. The final expanded `./scripts/run_test_gates.sh 1to1` rerun passed with `+793`.

**Final closure — CLOSED FOR IMPLEMENTATION / RESIDUAL-ONLY LAB EVIDENCE. 2026-06-13.**
- Gate capture updated: `test/features/conversation/integration/edit_retry_round_trip_test.dart` is now listed in both `Test-Flight-Improv/test-gate-definitions.md` and the frozen `scripts/run_test_gates.sh` `1to1` array, and the 116 gate-capture section records the focused host coverage.
- Scope-leak sanity passed: `(cd go-mknoon && make test)` and `(cd go-relay-server && go test ./...)` both passed.
- Final host revalidation passed: `./scripts/run_test_gates.sh 1to1` passed with `+793` after the aggregate bridge timeout and send-then-lock 7c stale expectation were closed; `./scripts/run_test_gates.sh completeness-check` later passed `844/844`.
- Residual evidence archive: release/device evidence from §8 (two-device divergence repair, lost-ack idempotency, mixed-version interop, delete retry on device, cross-plan production canary, and field telemetry watch) was not collected in this shell and is not claimed. No host-code or named-gate blocker remains.

Final verdict: `residual_only`.

## Amendment log

- 2026-06-13 P3A status-model decision: current 115 custody semantics are authoritative for deletion inbox storage. P3A writes retry-stored deletion tombstones as `status: 'inboxed'`, `transport: 'inbox'`, retained `wireEnvelope`, and visible until a receipt or direct ack confirms delivery. Direct acknowledged deletion replay writes `delivered`, clears `wireEnvelope`, and hides the tombstone.
- 2026-06-13 final re-audit: the previous aggregate bridge timeout caveat is resolved by the final `1to1` pass with `+793`; hardware/TestFlight items from §8 remain archived as unclaimed lab evidence rather than an implementation status.
