# 114 — LAN/Wi-Fi Ack-After-Commit: Durable-Delivery Parity for the Local WebSocket Leg (TDD Plan)

Date: 2026-06-12 · Branch: 121-improvements · Status: **CLOSED FOR IMPLEMENTATION — residual device-lab evidence archived (2026-06-13).** S1-S5 are implemented and host-accepted; the Wi-Fi relay fallback smoke schema issue is resolved and command 16 now passes. Physical mDNS, force-kill, notification, and mixed-version evidence was not collected in this shell and is not claimed.

Source: verified-confirmed audit trace (LAN parse-time-ack loss windows W1–W6), independent verification pass (all anchors re-checked on the uncommitted 121-improvements tree 2026-06-12), and the cross-plan completeness critic. Re-verify anchors before each session (Caveat 9.5).

---

## 1. Problem statement and impact

A 1:1 chat message sent over the LAN WebSocket path is acked by the receiver at **JSON-parse time** — `lib/core/local_discovery/local_ws_server.dart:269-274`, after only `jsonDecode` (`:250`) and a from/to/content null-check (`:259-265`) — before any decrypt, dedup, or persist. After the ack, the message exists solely in RAM through three broadcast `StreamController`s (`local_ws_server.dart:290` → `p2p_service_impl.dart:850-854` → `incoming_message_router.dart:161-162`) until the first durable write at `handle_incoming_chat_message_use_case.dart:376`. The LAN-built `ChatMessage` carries **no confirmNonce** (`p2p_service_impl.dart:267-274`), so the durable-staging gate `_shouldDurablyStageDeferredDirectChat` (`:747-752`) is false and the message bypasses the `inbox_staging` table entirely, falling to in-memory `_emitIncomingMessage` (`:2863`).

The sender, on the WS ack, gets `_RaceResult(via:'local', acknowledged:true)` (`send_chat_message_use_case.dart:1235-1241`), and `_persistOutgoingSendResult`'s `if (acknowledged)` early-return persists status `'delivered'` (`:1675-1684`), skipping the unacked→`storeInInbox` durable handoff (`:1692-1748`). The row is written **without** `wireEnvelope`, so it is invisible to `retryUnackedMessages` (`retry_unacked_messages_use_case.dart:43-45`) and every other retrier forever.

**Loss windows (all verified):**
- **W1** — receiver process killed post-ack, pre-`saveMessage`: receiver persists NOTHING; sender shows the terminal double-check (`letter_card.dart:602-603`). Permanent, silent.
- **W2** — decrypt fails after LAN ack (`decryptionFailed`, `handle_incoming_chat_message_use_case.dart:165-172`): listener maps it `ok=false` but `_maybeConfirmDirectNonce` no-ops for nonce-null LAN messages (`chat_message_listener.dart:305-309`); the outcome is discarded at `:326-331` with nothing to mark. Permanent loss — the 111 quarantine machinery operates on `inbox_staging` rows the LAN path never creates.
- **W3** — `decryptionDeferred` (BRIDGE_TIMEOUT, `:127-133`): a transient failure explicitly designed to be retried from a staged entry — which doesn't exist for LAN.
- **W5** — account-migration gate blocks inbound (`p2p_service_impl.dart:2810-2827`) AFTER the WS ack was already written: a LAN message gated during a Move-Account pause is acked-then-dropped.
- **W6 (amplifier)** — a LAN win records learned transport `'local'` (`send_chat_message_use_case.dart:1647-1649`; 30s TTL + LAN-visibility revalidation, `p2p_service_impl.dart:3469-3491`), so subsequent sends short-circuit to a SINGLE-leg LAN send (`:1267-1283`) with no parallel direct leg and no concurrent inbox copy (`lowConfidence` requires `!isLocalPeer`, `:567`). The loss windows above are the **steady state** for two same-Wi-Fi devices, not a corner case. Worse, the connection-reuse path mislabels strong Go-channel wins as `'local'` (`preserveLocalPeerLabel:true` at `:435` → `_resolveGoSendTransport` `:1159-1161`), actively training the sticky router onto the weakest transport.

The direct and relay paths have the exact parity model the LAN path lacks: Go mints a confirmNonce and withholds the wire ack until Dart has durably staged (`go-mknoon/node/node.go:1616-1651`, `EnableDeferredDirectAck` default true `feature_flags.go:42`, `DirectConfirmTimeout=2s` `config.go:81`; Dart receiver order stage `:778` → confirm `:796` → replay `:820-830`), and the relay inbox is stage-then-ack-delete (`go-relay-server/inbox.go:771-791`). **Impact:** "delivered" has three different meanings today, and the LAN one — "receiver merely parsed the JSON" — is the weakest guarantee behind the same terminal indicator. W4 (no-listener broadcast drop) was investigated and is **out of P0 scope**: production wiring subscribes every hop before the WS server can accept a connection (verification correction).

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
- **Shared sender status model (the load-bearing collision):** 115 Phase 1 (`'inboxed'` + G4 no-false-delivered) and this doc's Phase 3 rewrite the SAME function (`_persistOutgoingSendResult`) and the same `send_chat_message_use_case_test.dart` regions. Mandatory order: 115 Phase 1 lands first as the foundation; 114 Phase 3 backstop terminals become `'inboxed'`; 115's G4 whitelists the LAN committed-ack `'delivered'` (committed = receiver durably staged, the same bar as the direct deferred-ack G4 already allows).
- **Shared staging pipeline:** the `'lan:<nonce>'` rows introduced here ride `inbox_staging`, `_applyRecoveredInboxOutcome` dispositions, and the 111 quarantine state machine that the relay drain also uses — good reuse, but the critic flagged that receipt origin discrimination keyed on the `'direct:'` entryId prefix alone would misclassify `'lan:'` replays as inbox-originated (receipts for LAN messages; quarantined LAN replays must never mint receipts). 115 Phase 2.4 specifies the full `'direct:'`/`'lan:'`/relay-drain namespace contract at the receipt-emission layer; this doc pins the same contract at the staging/replay layer (Phase 2.5 here) — two layers, one contract.
- **Backstop duplicates lean on id-only dedup:** this doc's legacy-ack backstop deliberately creates a duplicate-delivery path (LAN copy + relay copy) absorbed by receiver `payload.id` dedup — the exact mechanism the edit-retry bug abuses. Idempotency holds only for byte-identical envelopes, so 116 Phases 1–2 (edit fallback fidelity + `updateWireEnvelope` poisoning guard) are a correctness FLOOR for this plan's backstop.
- **Go parity model untouched by both docs:** both 114 and 115 converge on confirm-before-ack parity with the existing Go deferred-ack path but neither touches Go confirmNonce machinery (LAN mints local staging ids; relay receipts are app-layer envelopes) — no conflict; `node.go:1616-1651` stays the untouched parity model.
- **Gate/process overlap:** 114 and 115 Phase 5s both edit the `run_test_gates.sh` 1to1 array and the 1:1 Reliability Files list; 115 additionally requires a relay deploy while 114 requires neither relay nor gomobile changes — one coordinated gate edit by whichever doc closes last (landing-order step 7).

---

## 2. Goals / Non-goals

### Goals
- **G-A** The LAN WS leg gains the same custody bar as the direct deferred-ack path: the receiver durably stages the message in `inbox_staging` (entryId namespace `'lan:<nonce>'`) BEFORE the ack frame is written; the ack carries `committed:true` + the echoed nonce.
- **G-B** Sender truthfulness: status `'delivered'`/transport `'local'` is persisted ONLY for a committed LAN ack. Any legacy/bool ack is non-durable → the existing durable-inbox backstop runs → terminal is `'inboxed'` (relay custody, per the 115 Phase 1 foundation) or truthful `'sent'` + `wireEnvelope`. (critic-fold: status-model rebase)
- **G-C** Zero-loss failure injection: receiver kill post-ack, decrypt fail, decrypt deferral, migration-gate block, and staging write failure each leave at least one durable copy (staged row that replays/quarantines/retries, or relay copy via nack-triggered backstop). Extends the 111 quarantine state machine to LAN rows.
- **G-D** Sticky-transport integrity: learned `'local'` is trained only by committed acks; connection-reuse wins over the Go channel record their actual transport (`preserveLocalPeerLabel` removed).
- **G-E** Version-skew safety in both directions with no handshake: old senders keep matching the committed ack within budget; new senders classify legacy parse-time acks as non-durable.

### Non-goals (deferred, with justification)
- **Delivery receipts / sender custody sweep** — doc 115's scope (Phases 2–3 there); this doc only guarantees its `'lan:'` rows interoperate with that machinery (Phase 2.5).
- **Edit/tombstone retry fidelity** — doc 116; this doc's backstop assumes 116 P1–P2 landed (program floor).
- **Fixing notification suppression on the LIVE direct deferred-ack path** (`suppressNotification:true` via the shared replay closure, `main.dart:1605-1609`) — pre-existing 1:1-audit backlog item; this plan only ensures LAN does not inherit it (Phase 2.4). OQ-6 records the decision point.
- **W4 no-listener broadcast drop** — verified non-issue at production startup ordering (Section 1); not worth a startup-ordering pin in this doc.
- **Go/relay changes of any kind** — the entire fix is Dart-side; `node.go` deferred-ack and relay inbox semantics are the untouched parity models.
- **LAN media transport changes** — 112 owns LAN media encryption; this doc only pins that staged-text replay never silently loses the media reference (Phase 4.4).

---

## 3. Design decision

**Give the LAN intake the existing direct-path parity: stage-then-ack.** The receiver-side `LocalWsServer` gains a commit-handler seam (`configureInboundChatCommitHandler`, mirroring the `configureMediaServer`/`configureMigrationTransferHandler` setter precedent at `local_ws_server.dart:73-85`); `P2PServiceImpl` wires it to a handler that runs the migration gate FIRST, stages the envelope as `InboxStagingEntry(entryId: 'lan:<nonce>')`, returns the commit decision, and replays through the existing `_applyRecoveredInboxOutcome` dispositions (`:822-830`). The ack frame is written only after the staging insert returns, and carries `committed:true`. The sender-side classifies three ack kinds (`LanSendAck { committed, legacyAck, failed }`), maps only `committed` to `acknowledged:true`, and routes everything else through the already-existing unacked machinery. Receiver dedup by `payload.id` (`handle_incoming:252-276`) plus the same `jsonString` envelope reused across transports (`send_chat_message_use_case.dart:592-593`) makes every added durable copy idempotent.

No version negotiation: ack v2 is a purely additive field on the existing frame. No DB migration: `inbox_staging_entries` is reused with a new `'lan:'` entryId namespace and the recovery sweep is prefix-agnostic.

### Alternatives rejected
1. **Mint a confirmNonce and route LAN through `_processDurablyStagedDirectChat` verbatim** — the direct path's confirm leg calls `callP2PConfirmDirectMessage` into Go (`:796`), which has no Go-side waiter for a LAN message; a synthetic-nonce no-op confirm would silently couple LAN correctness to Go bridge availability. The commit-handler seam keeps the WS ack and the staging insert in one process with no bridge hop.
2. **Sender-side only (treat every LAN ack as non-durable, always run the backstop)** — closes the false-'delivered' but forfeits LAN's latency win permanently, doubles relay traffic for every same-Wi-Fi send, and leaves the receiver-side RAM-only intake (W2/W3 quarantine/retry parity) unfixed.
3. **Move the ack after `saveMessage` (full processing) instead of after staging** — ties the interactive ack budget to decrypt + contact resolution + media metadata; the relay itself acks storage without decrypting, and the direct deferred-ack bar is stage-or-committed. Staging custody is the proven bar (clause (b) below).
4. **New WS protocol version / handshake** — no capability channel exists; additive ack field + sender classification covers both skew directions with zero negotiation (Section 4), same approach the deferred direct ack shipped with.
5. **Keep `preserveLocalPeerLabel` and special-case the census** — would keep training the sticky router onto the weakest transport; the census gets a separate dimension if it needs LAN visibility (OQ-4).

### Behavioral contract (pinned by tests)
For every 1:1 chat send, the sender persists status `'delivered'` only when at least one durable copy of the wire envelope provably exists outside sender RAM: **(a)** a receiver `inbox_staging` row committed BEFORE the LAN WS ack frame is written (ack carries `committed:true` and the echoed nonce), or **(b)** a receiver durably **staged-or-committed** copy via the direct deferred-ack path, unchanged — the verified direct path acks after the `inbox_staging` stage (stage `p2p_service_impl.dart:778` → confirm `:796` → replay), not after a `messages` row (critic-fold: contract wording fix). Relay-inbox custody **(c)** persists status `'inboxed'` per the 115 Phase 1 foundation — custody, not delivery (critic-fold: status-model rebase). Any LAN ack lacking `committed:true` (legacy parse-time ack from an old peer, or bool-only fake/wiring) is classified non-durable: the send resolves success-with-`acknowledged:false` and MUST run the existing durable-inbox backstop — `'inboxed'` on relay custody, else truthful `'sent'` + `wireEnvelope` visible to `retryUnackedMessages`. Receiver-side, a LAN chat message acked committed survives process kill (staged row replays via the recovery sweep), decrypt failure (quarantined, 111 semantics), decrypt deferral (retryable), and replay exceptions (retryable); migration-gate blocks and staging write failures produce an explicit `{'ack':false, reason}` reply pre-custody (sender never sees delivered). Sticky learned transport `'local'` is trained ONLY by committed LAN acks, and connection-reuse wins over the Go channel record their actual transport (never mislabeled `'local'`), so the single-leg sticky LAN path can never be entered on the strength of a non-durable ack.

### Gates
- **G1 receiver-custody-before-ack:** no WS frame containing `committed:true` may be written before the `inbox_staging` insert for that message returns, and the migration gate must run before staging — pinned by Phase 1.1 + Phase 2.1. Ship-blocked on `./scripts/run_test_gates.sh 1to1`.
- **G2 sender-truthfulness (amended, critic-fold):** status `'delivered'` with transport `'local'` requires `LanSendAck.committed`; any legacy/bool LAN ack must route through the durable-inbox backstop and **may only terminate as `'inboxed'` or `'sent'`+`wireEnvelope`** — Phase 3.2 + Phase 4.2's nack test. Depends on 115 Phase 1 (the `'inboxed'` status + migration 077 must exist); 115's G4 in turn whitelists the LAN committed-ack `'delivered'` (committed = receiver durably staged, the same bar as the direct deferred-ack).
- **G3 zero-loss failure injection:** receiver kill post-ack, `decryptionFailed`, `decryptionDeferred`, and staging DB-write failure each leave at least one durable copy — Phase 2.2–2.4 + Phase 4.1; extends the 111 quarantine state machine to LAN rows.
- **G4 version-skew:** old-matcher acceptance of the committed ack within `interactiveLocalBudget` AND legacy-ack-classified-non-durable AND old-matcher-skips-nack (critic-fold) all pinned as permanent host tests — Phase 4.2–4.3.
- **G5 sticky-integrity:** learned transport `'local'` is trained only by committed LAN acks, the sticky short-circuit honors non-durable results with the backstop, and connection-reuse wins record the actual Go transport (`preserveLocalPeerLabel` removed) — Phase 3.3.

---

## 4. Backward / version-skew compatibility

Ack v2 is a purely additive field on the existing WS ack frame — no version negotiation, no handshake.

**OLD sender + NEW receiver:** the committed ack keeps `ack:true` plus the echoed nonce, so the old matcher (`json['ack']==true && json['nonce']==nonce`, old `local_ws_server.dart:410-419`) matches unchanged; the receiver's commit is a single SQLCipher `inbox_staging` insert bounded by a commit budget (~1200ms) strictly inside the old sender's 1500ms `interactiveLocalBudget` (`send_chat_message_use_case.dart:19`), pinned by Phase 4.2's old-matcher test. On gate/staging failure the receiver replies `ack:false`, which the old matcher simply never matches — the old sender's `firstWhere` skips the nack frame and times out into its existing direct/relay/inbox fallback (indistinguishable from today's no-ack case — no new failure mode, and crucially no false 'delivered'); pinned by Phase 4.3 (critic-fold).

**NEW sender + OLD receiver:** the old receiver acks at parse time without `committed` → the new sender classifies `legacyAck` → success-with-`acknowledged:false` → durable-inbox backstop (`'inboxed'` on relay custody per the 115 Phase 1 status model, else truthful `'sent'` + `wireEnvelope` retried by `retryUnackedMessages`); the resulting duplicate delivery (LAN copy + backstop copy) is absorbed by the old receiver's already-shipped `payload.id` dedup (`handle_incoming_chat_message_use_case.dart:252-276`), so no user-visible duplicates. **Accepted mixed-version tradeoff (needs owner sign-off, OQ-1):** on same-Wi-Fi-without-internet, a new sender to an OLD receiver shows the pending-family indicator (`'sent'`, or `'inboxed'` once relay reachability returns) instead of 'delivered' even though the old receiver displayed the message — safe direction (never delivered-but-lost), self-resolving as the fleet upgrades, and after 115 Phase 2 the receipt path upgrades `'inboxed'` rows honestly.

**Old-relay interop:** zero relay/protocol changes (go-relay-server and go-mknoon untouched); the backstop uses the existing `inbox:store` path against already-deployed relays.

**Cross-doc skew:** Phase 3 must NOT ship in a build whose DB predates migration 077 (115 Phase 1) — the `'inboxed'` terminal would be unrepresentable. Phases 1–2 are receiver-side and status-model-agnostic; they may ship ahead of 115 entirely.

**Rollback:** receiver-side handler and sender-side policy are independent — reverting either build degrades to today's behavior, never worse.

---

## 5. TDD phases

Order: **1 → 2 → 3 → 4 → 5**, with the program landing order overlaid: Phases 1–3 land at program step 5 (after 115 P1, 116 P1–2, 115 P2–3), Phases 4–5 at program step 7. Phases 1+2 (receiver) and 3 (sender) ship in one app build, so in-app ordering is atomic; the Section-4 story covers the fleet. All new test files get classified in `test-gate-definitions.md` with `./scripts/run_test_gates.sh completeness-check` kept green (rules at `test-gate-definitions.md:5, 115-122`). RED honesty rule: tests that are green-on-arrival are explicitly labeled **pins** below — the RED count per phase is only the tests that genuinely fail when written.

---

### Phase 1 — LocalWsServer ack-after-commit wire protocol (receiver commit seam + sender ack classification)

**Why first:** the wire seam is the foundation both the receiver intake (Phase 2) and sender policy (Phase 3) build on; it is self-contained in `local_discovery` and ships dark (no behavior change until a handler is configured).

#### 1.1 RED — receiver withholds ack until commit
File: `test/core/local_discovery/local_ws_server_test.dart` (extend; real dart:io WebSocket over localhost per file convention).
- `'withholds ack until inbound commit handler completes and marks it committed'` — configure `server.configureInboundChatCommitHandler(...)` returning a Completer-gated `LanInboundDecision.committed`; raw WS client sends chat JSON with a nonce; assert NO frame arrives during a 150ms settle before the handler completes, then the ack frame is `{'ack':true,'committed':true,'nonce':<echoed>}`. **Fails today:** ack is written unconditionally at JSON-parse time (`lib/core/local_discovery/local_ws_server.dart:269-274`, after only `jsonDecode` `:250` and from/to/content null-check `:259-265`); no commit-handler seam exists (compile-red drives the API, mirroring the `configureMediaServer`/`configureMigrationTransferHandler` setter precedent at `:73-85`).
- `'replies explicit nack with reason when commit handler rejects'` — handler returns `LanInboundDecision.rejected('staging_failed')`; assert frame `{'ack':false,'nonce':n,'reason':'staging_failed'}` and `messageStream` emits nothing. **Fails today:** rejection is unrepresentable — only `{'ack':true}` exists and malformed/blocked inputs are silently swallowed (`:291-293`).
- `'does not emit on messageStream when commit handler is configured'` — handler commits; assert the broadcast `_messageController` stream got zero events (chat routes exclusively through the handler — eliminates the acked-but-RAM-only double path). **Fails today:** `:290` always adds to the broadcast controller.
- `'commit handler timeout produces nack not legacy ack'` — handler never completes; with an injectable commit budget (ctor param beside `idleTimeout`, default ~1200ms), assert nack `{'ack':false,'reason':'commit_timeout'}` after the budget elapses and no committed ack ever. **Fails today:** seam absent.

#### 1.2 Pin — legacy parse-time ack mode (green-on-arrival, does not count toward RED)
Same file.
- `'acks legacy shape at parse time when no commit handler configured'` — **green-on-arrival pin** (per the 112 RED-honesty rule): without a handler the server behaves exactly as today — `{'ack':true,'nonce':n}` with NO `committed` field, plus broadcast emit. Pins the legacy mode that mixed-version sender policy depends on.

#### 1.3 RED — sender-side ack classification
Same file.
- `'sendMessageWithAck classifies committed ack, legacy ack, and nack'` — three two-server cases (template: `'sendMessage delivers and gets ack'` `:99`): receiver with committing handler → `LanSendAck.committed`; receiver with no handler → `LanSendAck.legacyAck`; receiver with rejecting handler → `LanSendAck.failed` resolving in well under the 5s `_ackTimeout` (nack short-circuits the wait). **Fails today:** `sendMessage` returns bool and its matcher only matches `json['ack']==true` (`:410-419`), so a nack frame would be ignored until timeout and committed/legacy are indistinguishable.

#### 1.4 GREEN
`lib/core/local_discovery/lan_ack.dart` (new): `enum LanSendAck { committed, legacyAck, failed }`; sealed/record `LanInboundDecision { committed | accepted (legacy in-memory, acks legacy shape) | rejected(String reason) }`; `typedef LanInboundChatCommitHandler = Future<LanInboundDecision> Function(LocalChatMessage message, {required String? nonce})`.

`lib/core/local_discovery/local_ws_server.dart`:
1. `configureInboundChatCommitHandler(handler)` setter + `commitBudget` ctor param;
2. `_handleInboundMessage` (`:246-294`): when handler configured, do NOT ack at parse time — await handler bounded by `commitBudget`, then write `{'ack':true,'committed':true,'nonce':n}` on committed, legacy-shape `{'ack':true,'nonce':n}` on accepted, `{'ack':false,'nonce':n,'reason':r}` on rejected/timeout/throw; never broadcast-emit for handled chat (handler owns routing); unconfigured path byte-identical to today;
3. `sendMessageWithAck(...)` → `Future<LanSendAck>`: same framing/nonce mint as `sendMessage` but `firstWhere` matches ANY frame with the matching nonce (ack true OR false) then classifies; existing `sendMessage` delegates and returns `(await sendMessageWithAck(...)) == LanSendAck.committed`;
4. `emitFlowEvent` at every branch: `LOCAL_WS_COMMIT_ACK_SENT`, `LOCAL_WS_COMMIT_NACK_SENT {reason}`, `LOCAL_WS_COMMIT_TIMEOUT`, `LOCAL_WS_ACK_LEGACY_CLASSIFIED`, `LOCAL_WS_ACK_COMMITTED_CLASSIFIED`.

Interface notes: no abstract-interface changes — `LocalWsServer` is concrete: new members only. `_RecordingLocalWsServer` (`test/core/local_discovery/local_p2p_service_test.dart:319`) overrides only `sendMessage`, whose signature is unchanged, so it keeps compiling. `_DelayedAckPeer` (`local_ws_server_test.dart:359`) is a raw-socket peer, untouched — it doubles as the 'old receiver' fixture for Phase 4's mixed-version tests. Nonce-less inbound (ancient sender) still runs the handler; reply omits the nonce field (best-effort legacy). Refactor: extract ack-frame builders so committed/legacy/nack shapes are pinned in one place.

#### 1.5 Gate
`flutter test test/core/local_discovery` green; `./scripts/run_test_gates.sh 1to1` green; `./scripts/run_test_gates.sh completeness-check` green.

---

### Phase 2 — P2PServiceImpl durable LAN intake: gate → stage → ack → replay with dispositions

**Why here:** consumes the Phase-1 seam; makes the receiver loss-windows (W1/W2/W3/W5) closable before any sender policy changes.

#### 2.1 RED — stage-before-decision + migration gate
File: `test/core/services/p2p_service_impl_test.dart` (extend the `'durable inbox staging'` group at `:570`).
- `'stages LAN chat into inbox_staging before the commit decision and deletes the row on committed replay'` — `FakeLocalP2PService` (extended with a captured `configureInboundChatCommitHandler`) hands the handler to the test; invoke it with a v2 chat envelope + nonce `'n1'`; assert `InMemoryInboxStagingRepository` received entryId `'lan:n1'` BEFORE the handler future resolves committed; committed replay disposition → entry deleted; FLOW event `P2P_SERVICE_LAN_STAGED_CHAT_COMMITTED` (assert via the `captureFlowEvents` pattern, `retry_failed_messages_use_case_test.dart:21-48`). Mirror `'stages, acks, and deletes committed chat entries'` `:968`. **Fails today:** nothing configures a commit handler; LAN `ChatMessage` carries no confirmNonce (`p2p_service_impl.dart:267-274`) so `_shouldDurablyStageDeferredDirectChat` (`:747-752`) is false and the message goes to in-memory `_emitIncomingMessage` (`:2863`) — no staging call ever happens.
- `'rejects LAN commit when the account-migration gate blocks inbound'` — gate closure returns false → handler resolves `rejected('account_migration_blocked')`; nothing staged, nothing emitted on `messageStream`, `ACCOUNT_MIGRATION_INBOUND_EVENT_BLOCKED` emitted. **Fails today (W5):** the WS ack at `local_ws_server.dart:269-274` precedes the gate check at `p2p_service_impl.dart:2810-2827`, so a migration-gated LAN message is acked-then-dropped.

#### 2.2 RED — replay dispositions (111 state machine extended to LAN rows)
Same file.
- `'marks LAN staged row retryable on decryptionDeferred replay outcome'` — replay callback returns the retryable disposition (`decryptionDeferred`/BRIDGE_TIMEOUT shape); assert row status `'retryable'` with reasonCode, row NOT deleted (W3 closed: a transient decrypt now has a durable row to retry from). **Fails today:** no LAN row exists; the outcome is discarded at `chat_message_listener.dart:326-331` with nothing to mark.
- `'quarantines LAN staged row on decryptionFailed replay outcome'` — replay returns quarantined; assert quarantine status + reason codes per the 111 state machine (`InMemoryInboxStagingRepository` `:59-114`), sender-visible decision stays committed (custody already truthfully taken — same bar as the relay, which acks storage without decrypting). **Fails today (W2):** permanent silent loss.

#### 2.3 RED — fault injection + kill recovery
File: `test/core/services/p2p_service_fault_injection_test.dart`.
- `'LAN staging write failure produces rejected commit and falls back to in-memory emit'` — staging repo `stageEntries` throws (DB write failure injection, mirroring the existing direct stage-error fault test): handler resolves `rejected('staging_error')`, `P2P_SERVICE_LAN_STAGE_ERROR` emitted, AND the message is emitted in-memory (parity with the direct-path fallback at `p2p_service_impl.dart:790`) — loss-free either way because the sender's nack triggers the backstop and receiver dedup (`handle_incoming:252-276`) absorbs the duplicate. **Fails today:** no handler/decision path exists.

File: `test/core/services/p2p_service_impl_test.dart`.
- `'LAN staged row left by a killed process is recovered by the startup replay sweep'` — stage via the handler, do NOT run replay (simulated kill); construct a second `P2PServiceImpl` over the SAME staging repo and drive the resume replay (template: `'replays staged chat rows before fetching new relay pages'` `:717`); assert the LAN row replays exactly once and commits (W1 closed). **Fails today:** no LAN row is ever staged, so restart recovers nothing.

#### 2.4 RED — live replay routing (notification parity)
File: `test/core/services/p2p_service_impl_test.dart`.
- `'live LAN replay routes through the live replay callback so notifications are not suppressed'` — new optional ctor param `replayLiveLanChatMessage`: assert the handler's post-ack replay invokes it (and falls back to `replayRecoveredInboxChatMessage` when absent). **Fails today:** param does not exist. Guards the regression where moving LAN off the in-memory path would silently inherit the recovery path's `suppressNotification:true` (`main.dart:1605-1609`); today's LAN in-memory path reaches `ChatMessageListener` unsuppressed and must stay that way.

#### 2.5 RED — origin-marker contract shared with doc 115 Phase 2 (critic-fold)
File: `test/core/services/p2p_service_impl_test.dart`.
- `'origin-marker contract: direct- and lan-prefixed staged rows never mint delivery receipts on replay; quarantined and retryable replays never mint receipts'` — enumerate the contract: `'direct:'`-prefixed AND `'lan:'`-prefixed staged rows replay WITHOUT emitting a delivery receipt (their senders already hold the deferred-ack / committed-ack `'delivered'`); relay-drain entries are the only receipt-minting origin; quarantined and retryable replays never mint receipts regardless of origin. **Same contract as doc 115 Phase 2.4, pinned at a different layer:** 115 pins receipt emission at the use-case layer (`test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`); this test pins the staging/replay layer (`test/core/services/p2p_service_impl_test.dart`) so a wiring regression between the two layers cannot slip through. Expected green-on-arrival at this doc's landing slot (program step 5, after 115 Phase 2) — re-label it a pin in the closure log if so; it is RED only if 115 landed its receipt origin discrimination keyed on the `'direct:'` prefix alone, in which case `'lan:'` replays are misclassified as inbox-originated and mint receipts.

#### 2.6 GREEN
`lib/core/services/p2p_service_impl.dart`: new `_commitInboundLanChatMessage(LocalChatMessage msg, {String? nonce})` —
1. `_allowsAccountNetworkSideEffects('p2p_inbound_message')` FIRST → rejected on block;
2. parse envelopeType; for `'chat_message'` with staging repo + replay callback available: build `InboxStagingEntry(entryId 'lan:<nonce|uuid>', ownerPeerId msg.to, senderPeerId msg.from, envelope msg.content, stagedAt now)` and await `stageEntries` → return committed, then unawaited replay via `(replayLiveLanChatMessage ?? replayRecoveredInboxChatMessage)` + the existing `_applyRecoveredInboxOutcome` (`:822-830`) with LAN event names `P2P_SERVICE_LAN_STAGED_CHAT_{COMMITTED,RETRYABLE,REJECTED,QUARANTINED}`;
3. non-chat envelopes or missing repo/callback → legacy: `_emitIncomingMessage` + return accepted;
4. move `transportMetrics.recordTransport('wifi')` + `MSG_RECEIVED_TRANSPORT` emission (`:252-264`) into the handler so NET-REL-01 I3 telemetry keeps firing.
Constructor: when `_localP2P != null`, call `_localP2P.configureInboundChatCommitHandler(_commitInboundLanChatMessage)` next to the existing `_localMessageSub` subscription (`:251` — subscription kept for legacy/unconfigured paths).

`lib/core/local_discovery/local_p2p_service.dart`: passthrough `configureInboundChatCommitHandler(handler)` → `_wsServer`.

`lib/main.dart`: wire `replayLiveLanChatMessage` with `suppressNotification:false` (clone of the `:1605-1637` closure including unknown-sender intro recovery). Origin-marker contract (2.5): replay receipt-minting (115 Phase 2 machinery) must key on `entryId` prefix ∈ {`'direct:'`, `'lan:'`} → skip receipt; coordinate the helper with 115's implementation rather than duplicating the predicate.

Interface notes: `LocalP2PService` (concrete class used as interface) +1 method `configureInboundChatCommitHandler` → breaks exactly 1 implements-based fake: `test/core/local_discovery/fake_local_p2p_service.dart:8` `FakeLocalP2PService` (add a recording stub that captures the handler — also what the new tests use). `P2PServiceImpl` constructor +1 OPTIONAL named param `replayLiveLanChatMessage` — non-breaking for all existing constructions (`p2p_service_impl_test.dart`, `p2p_service_fault_injection_test.dart`, `durable_storage_recovery_test.dart`, lan availability/census/inbound-transport suites). `P2PService` abstract interface UNCHANGED — zero of the 32 implements-P2PService fakes touched (`implements` ignores default bodies per project memory, so even defaulted additions are forbidden).

No DB migration: `inbox_staging_entries` is reused with a new `'lan:'` entryId namespace; the recovery sweep (`getRecoverableEntries`) is prefix-agnostic — add a green-on-arrival pin in `test/core/database/helpers/inbox_staging_db_helpers_test.dart` that a `'lan:'` entryId round-trips, only if any format assumption is found.

#### 2.7 Gate
`flutter test test/core/services test/core/local_discovery` green; `./scripts/run_test_gates.sh 1to1` green; `completeness-check` green.

---

### Phase 3 — Sender durable-ack policy + sticky-transport amplifier fix

**HARD PREREQUISITE (critic-fold: status-model rebase): 115 Phase 1 landed** — status `'inboxed'` (+ migration 077, DB v77), UI pending mapping, and 115's G4 no-false-delivered (which whitelists the LAN committed-ack `'delivered'`: committed = receiver durably staged, the same bar as the direct deferred-ack). This phase rewrites `_persistOutgoingSendResult` and `send_chat_message_use_case_test.dart` regions that 115 Phase 1 touches first; rebase on its landed state. Program slot: step 5 (also after 116 P1–2 and 115 P2–3).

#### 3.1 RED — DurableLanSender capability + committed ack
File: `test/features/conversation/application/send_chat_message_use_case_test.dart`.
- `'LAN committed ack persists delivered with transport local'` — in-file `FakeP2PService` (`:33-160`) additionally implements the new `DurableLanSender` capability with knob `localSendAck = LanSendAck.committed`; expect status `'delivered'`, transport `'local'`, `storeInInboxCallCount 0`. **Compile-red:** `DurableLanSender` and the knob do not exist (drives the capability API; behaviorally this is the only LAN case still allowed to produce delivered/local — the 115 G4 whitelist entry).

#### 3.2 RED — non-durable backstop terminals (rewritten to `'inboxed'`, critic-fold)
Same file. These three tests were originally planned to expect `'delivered'`/`'inbox'`; per the program critic and the 115 Phase 1 foundation they are REWRITTEN to expect status `'inboxed'` / transport `'inbox'` on backstop custody.
- `'LAN legacy ack is non-durable: inbox handoff takes custody and status is inboxed'` — `localSendAck = legacyAck`, `storeInInboxResult = true`; expect status `'inboxed'`, transport `'inbox'`, `storeInInboxCallCount 1`. **Fails today:** bool `ack==true` maps to `_RaceResult(acknowledged:true)` (`:1235-1241`) and `_persistOutgoingSendResult`'s acknowledged early-return persists `'delivered'`/`'local'` skipping the handoff entirely (`:1675-1684` vs `:1692-1748`).
- `'LAN legacy ack with failed inbox handoff keeps truthful sent with wireEnvelope'` — `localSendAck = legacyAck`, `storeInInboxResult = false`; expect status `'sent'`, transport `'local'`, `wireEnvelope` non-null (row reachable by `retryUnackedMessages`, `retry_unacked_messages_use_case.dart:43-45`). **Fails today:** `'delivered'` with `wireEnvelope` null — invisible to every retrier forever.
- `'P2PService without DurableLanSender capability treats a bool LAN ack as non-durable'` — plain `FakeP2PService` (no capability), `localSendResult = true`, `storeInInboxResult = true` → status `'inboxed'`, transport `'inbox'`. **Fails today:** `'delivered'`/`'local'`. Pins the fail-safe default for any wiring that lacks the capability.

#### 3.3 RED — sticky-transport integrity (G5)
Same file.
- `'legacy LAN ack never trains the sticky learned transport; committed ack does'` — add `lastRecordedTransport` recording to the in-file fake's `recordSuccessfulTransport`; legacyAck send → never called with `'local'`; committed send → called with `'local'`. **Fails today:** `:1647-1649` records `'local'` for any delivered non-inbox win, making the weakest path the steady state.
- `'sticky local short-circuit honors a non-durable legacy ack with the inbox backstop'` — fake `lastKnownGoodTransport` returns `'local'` (engaging the single-leg short-circuit `:1267-1283`), `localSendAck = legacyAck`, `storeInInboxResult = true`; expect status `'inboxed'`/transport `'inbox'` NOT delivered/local (rewritten per the status-model rebase, critic-fold). **Fails today on THE zero-compensation steady-state path:** sticky win → `acknowledged:true` → delivered/local, no other leg even runs (`lowConfidence` requires `!isLocalPeer` at `:567`, so no concurrent copy either).
- `'connection-reuse win over the Go channel records the actual transport, not local'` — peer both LAN-visible (`localPeers`) and connected (`currentState.connections` entry); `sendMessageWithReply` acked with `sendMessageTransport 'direct'`; expect `message.transport 'direct'` and `recordSuccessfulTransport('direct')`. **Fails today:** `preserveLocalPeerLabel:true` at `:435` makes `_resolveGoSendTransport` return `'local'` (`:1159-1161`), training the sticky router onto the weakest transport (the amplifier the original claim missed).

#### 3.4 RED — intentional contract updates (not silent edits)
Same file. `'sends locally when peer is on local WiFi'` (`:1476`), `'passes interactive local budget to the WiFi transport'` (`:1523`), and the NET-REL-01 U1 happy path (`:1608+`) currently LOCK IN acknowledged→delivered-on-parse-ack as expected; revise each to use the committed-ack capability fake where delivered/local is asserted, and verify `'falls through to relay when local send fails'` (`:1500`) and `'skips local send when peer is not on local WiFi'` (`:1545`) stay green unchanged. Listed here so this doc's Review-resolution log records them as deliberate behavior changes.

#### 3.5 GREEN
`lib/core/services/p2p_service.dart`: new optional capability `abstract class DurableLanSender { Future<LanSendAck> sendLocalMessageDurable(String peerId, String message, String fromPeerId, {int? timeoutMs}); }` (precedent: `P2PFullInboxDrain` `:236-238` and `ReadinessProofRecorder` `:18` — capability interfaces are opt-in and break none of the 32 implements-P2PService fakes).

`lib/core/local_discovery/local_p2p_service.dart`: `sendMessageDetailed(...)` → `_wsServer.sendMessageWithAck`.

`lib/core/services/p2p_service_impl.dart`: implements `DurableLanSender` via `sendMessageDetailed`; existing `sendLocalMessage` tightened to `(await detailed) == committed`.

`lib/features/conversation/application/send_chat_message_use_case.dart`: `_tryLocalSend` (`:1217-1243`) — if `p2pService is DurableLanSender`, map committed → `_RaceResult.succeeded(via:'local', acknowledged:true)`; legacyAck → `_RaceResult.succeeded(via:'local', acknowledged:false)` (existing unacked machinery at `:1686-1763` then does concurrent-custody check, `storeInInbox` handoff — persisting `'inboxed'` per the landed 115 Phase 1 — or `'sent'`+`wireEnvelope`); failed → `_RaceResult.failed('local_send_failed')`; capability absent → bool true maps to legacyAck (fail-safe). Sticky short-circuit (`:1267-1283`) inherits the mapping through `_tryLocalSend` automatically. Remove `preserveLocalPeerLabel:true` at `:435` (reuse path records actual Go transport). `emitFlowEvent CHAT_MSG_SEND_LAN_ACK {kind: committed|legacy|failed}` at classification.

Interface notes: `DurableLanSender` is a NEW capability abstract class — breaks nothing (opt-in implements; only `P2PServiceImpl` and the fakes that choose to implement it). `LocalP2PService` +1 method `sendMessageDetailed` → breaks the same single fake again: `FakeLocalP2PService` (add knob-driven stub; do Phase 2+3 `LocalP2PService` additions together to touch the fake once). `P2PService.sendLocalMessage`: SIGNATURE unchanged (no fake breakage across the 32 implements-fakes); semantic tightening only (true = committed) — audit `p2p_service_lan_availability_test.dart` / `p2p_service_transport_census_test.dart` (fake at `:134`) / `p2p_service_inbound_transport_test.dart` for assertions on the bool and update expectations where they pinned parse-time-ack semantics. In-file `FakeP2PService` (`send_chat_message_use_case_test.dart:33`) and shared `test/core/services/fake_p2p_service.dart` + `test/shared/fakes/fake_p2p_service_integration.dart`: OPT-IN `implements DurableLanSender` with `localSendAck` knob where LAN tests need it — non-mandatory, other fakes untouched.

Census/I3 caveat: removing `preserveLocalPeerLabel` changes the reuse-rung transport label from `'local'` to actual — check `p2p_service_transport_census_test.dart` and the Startup/Transport gate before landing; if the census needs LAN-visibility, give it a separate dimension rather than corrupting the sticky trainer (OQ-4).

#### 3.6 Gate
`flutter test test/features/conversation/application/send_chat_message_use_case_test.dart` + retry trio (`retry_failed_messages_use_case_test.dart retry_unacked_messages_use_case_test.dart pending_message_retrier_test.dart`) green; `./scripts/run_test_gates.sh 1to1` green; `completeness-check` green. G2 (amended form) ship-blocks here: legacy/bool LAN acks may only terminate as `'inboxed'` or `'sent'`+`wireEnvelope`.

---

### Phase 4 — Host integration: loss-window closure and version-skew pins over real loopback WS

**Why here:** forces real-socket + real-SQLCipher-staging integration over Phases 1–3 and catches wiring gaps (handler not configured before server start, nonce threading). Program slot: step 7. Expected to be glue-only — any production fix discovered lands in the files already listed in Phases 1–3.

New host-runnable file modeled on `local_ws_integration_i1_i2_test.dart` (real `LocalWsServer` pair over loopback, plain `test()`, header documenting host-runnability; keep mDNS out — direct host:port like I1/I2). Receiver stack: `LocalWsServer` + commit handler wired to a real `sqflite_common_ffi` `inbox_staging` DB (`sqfliteFfiInit` + `runInboxStagingEntriesMigration`, per `inbox_staging_db_helpers_test.dart:6-21`).

#### 4.1 RED — loss-window closure
File: `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` (new).
- `'receiver killed after committed ack does not lose the message: staged row replays on restart'` — sender `sendMessageWithAck` → committed; simulate kill by tearing the receiver down WITHOUT replay; 'restarted' stack over the same DB runs the recovery sweep; assert the chat message lands in the message repo exactly once (`payload.id` dedup) and the staged row is deleted. **Fails today:** the LAN path stages nothing — restart recovers nothing (W1 reproduced as a failing assertion before the fix).
- `'decrypt failure after committed ack quarantines the staged row instead of losing the message'` — replay fn returns quarantined (`decryptionFailed` shape); assert row quarantined with reason code and envelope intact for manual recovery, while the sender observed committed (custody truthfully held — same bar as the relay path which acks storage without decrypting). **Fails today:** W2 — outcome discarded, nothing persisted anywhere.

#### 4.2 RED — version-skew pins
Same file.
- `'old sender matcher accepts the committed ack within the interactive budget'` — raw WS client implementing the OLD matcher verbatim (`json['ack']==true && json['nonce']==nonce`, 1500ms budget = `interactiveLocalBudget` at `send_chat_message_use_case.dart:19`) against a new committing receiver; assert match succeeds and elapsed < 1500ms (single SQLCipher staging insert inside the commit budget). RED with Phase 1 unimplemented; thereafter the permanent version-skew pin.
- `'new sender against old receiver classifies the parse-time ack as legacy and non-durable'` — receiver = the `_DelayedAckPeer`-style raw fixture acking at parse time with no `committed` field (exact old-binary behavior); sender `sendMessageWithAck` → `LanSendAck.legacyAck` (never committed). Integration-level pin of the Phase 3 backstop trigger.
- `'rejected commit nack resolves the sender promptly with no delivered state possible'` — receiver handler rejects (migration-gate shape); assert sender resolves `LanSendAck.failed` in well under the ack timeout, and a composed `sendChatMessage` over a capability fake mapping that result persists a non-`'delivered'` terminal (`'inboxed'` or `'sent'`) — never delivered/local.

#### 4.3 RED — old-matcher client vs a REJECTING new receiver (critic-fold)
Same file (raw-socket fixture).
- `'old sender matcher skips a nack frame mid-wait and times out into its direct-relay fallback'` — raw client implementing the OLD `firstWhere` matcher (`json['ack']==true && json['nonce']==nonce`) against a new receiver whose commit handler REJECTS: the `{'ack':false,'nonce':n,'reason':...}` frame arrives mid-wait and must be skipped by the matcher (no match, no throw), which then times out exactly as today's no-ack case — the old sender's existing direct/relay fallback engages, never a false 'delivered'. This is the third skew cell the compatibility prose claimed but no test pinned. **Fails today:** the nack frame is unrepresentable pre-Phase-1 (`local_ws_server.dart:291-293` swallows everything; only `{'ack':true}` exists), so the fixture cannot even elicit the frame.

#### 4.4 RED — media-bearing LAN message replay after receiver kill (critic-fold)
Same file (integration red test).
- `'media-bearing LAN message replay after receiver kill falls back to relay media or surfaces retryable, never silent media loss'` — stage a LAN chat envelope referencing a media attachment, kill the receiver pre-replay, restart over the same DB with the sender's LAN media endpoint GONE (offer host:port dead — sender off network): assert the staged TEXT commits exactly once, and the media attachment is either recovered via the 112 relay-media fallback (`downloadMedia` against the relay copy) or persisted in a retryable/pending-download state — never `done`-with-missing-bytes, never silently dropped. **Fails today:** no `'lan:'` replay path exists, and the 112 relay-media fallback has never been exercised from a LAN-staged replay.

#### 4.5 GREEN
Expected glue-only: no new production code beyond Phases 1–3; any production fix discovered (handler configured before server start, nonce threading, media-fallback wiring for `'lan:'` replays) lands in the files already listed. Use sync-IO-safe patterns only if any assertion migrates to a `testWidgets` body (none planned — plain `test()` with real async per `local_discovery` conventions).

#### 4.6 Gate
`flutter test test/core/local_discovery` green (includes the new file); `./scripts/run_test_gates.sh 1to1` green; `completeness-check` green (new file classified — see Phase 5). The device-only mDNS leg stays in `integration_test/wifi_transport_test.dart`; extend F1–F4 expectations there for the committed-ack frame in the same change (device-gated, listed in §8).

---

### Phase 5 — Gate capture, classification, and doc closure

#### 5.1 Process RED — completeness-check classification
File: `Test-Flight-Improv/test-gate-definitions.md` (process red, not a Dart test).
- `./scripts/run_test_gates.sh completeness-check` fails the moment `local_ws_durable_ack_integration_test.dart` exists unclassified — that failing run is the trigger to (1) add `'## 114 LAN Ack-After-Commit Gate Capture'` to `test-gate-definitions.md`, (2) add the new file + `local_ws_server_test.dart` to the 1:1 Reliability Gate Files list (exact paths per the Bulk-Classification Policy `:115-122`) in BOTH the doc (`:233-271`) and the `scripts/run_test_gates.sh` 1to1 array (doc `:5`: the script wins on disagreement). Per the program landing order, the gate-array edit is made as ONE coordinated edit with docs 115/116 by whichever doc closes last.

#### 5.2 Chore — integration_test sweep for delivered-on-parse-ack assertions (critic-fold)
Sweep `integration_test/` for assertions that pin delivered-on-parse-ack (or bool-LAN-ack ⇒ delivered) semantics, and list every hit in the `'## 114 LAN Ack-After-Commit Gate Capture'` section with its updated expectation:
- `integration_test/wifi_transport_test.dart` **F1–F4** — extend for the committed-ack frame (device-gated; §8 device suite).
- `integration_test/wifi_relay_fallback_smoke_test.dart` **S1–S4** (orchestrator `dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p ios`) — S-scenarios assert LAN-ack/fallback status transitions; re-pin against committed/legacy classification and the `'inboxed'` backstop terminal.
- Any other `integration_test/` harness asserting `'delivered'` on a LAN/bool-ack win (the sweep is the deliverable; the two files above are the known hits).

#### 5.3 Final sweep + closure
`flutter test test/core/local_discovery && flutter test test/core/services && flutter test test/features/conversation/application/send_chat_message_use_case_test.dart && flutter test test/features/conversation/integration/ && ./scripts/run_test_gates.sh 1to1 && FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline && ./scripts/run_test_gates.sh completeness-check` — all green (completeness-check green; baseline was 834/834 at the 113 closure — do not pin counts, the program adds files). Regression sanity only (no Go changes in this plan): `(cd go-mknoon && make test)` and `(cd go-relay-server && go test ./...)`. No relay deploy and no gomobile rebuild required — the entire fix is Dart-side (the Go deferred-ack direct path is the parity model, untouched).

---

## 6. Test matrix (loss window / skew cell × covering test)

| Scenario | Covering test (phase) |
|---|---|
| W1 receiver killed post-ack pre-persist | `p2p_service_impl_test.dart` kill-recovery (P2.3); `local_ws_durable_ack_integration_test.dart` kill+restart (P4.1) |
| W2 decrypt fails after LAN ack | `p2p_service_impl_test.dart` quarantine disposition (P2.2); integration quarantine (P4.1) |
| W3 decryptionDeferred (BRIDGE_TIMEOUT) | `p2p_service_impl_test.dart` retryable disposition (P2.2) |
| W5 migration gate blocks post-ack | `p2p_service_impl_test.dart` gate-reject (P2.1); nack→non-delivered terminal (P4.2) |
| W6 sticky single-leg amplifier | `send_chat_message_use_case_test.dart` sticky short-circuit + training + reuse-label tests (P3.3) |
| Staging DB write failure | `p2p_service_fault_injection_test.dart` (P2.3) |
| Ack-before-commit ordering (G1) | `local_ws_server_test.dart` withholds-ack + Phase 2 stage-before-decision (P1.1/P2.1) |
| Sender classification committed/legacy/failed | `local_ws_server_test.dart` sendMessageWithAck (P1.3) |
| Backstop terminals `'inboxed'` / `'sent'`+envelope (G2, rebased) | `send_chat_message_use_case_test.dart` (P3.2) |
| Skew: old sender × new committing receiver | integration old-matcher budget pin (P4.2) |
| Skew: old sender × new REJECTING receiver (nack mid-wait) | integration old-matcher-skips-nack (P4.3, critic-fold) |
| Skew: new sender × old receiver (legacy ack) | integration legacy classification pin (P4.2) |
| Media-bearing `'lan:'` replay, dead LAN media endpoint | integration media-fallback test (P4.4, critic-fold) |
| Receipt origin discrimination for `'lan:'`/`'direct:'` rows | origin-marker contract test, shared with doc 115 (P2.5, critic-fold) |
| Notification parity for live LAN replay | `p2p_service_impl_test.dart` live-replay-callback (P2.4); device evidence §8 |
| Legacy unconfigured-server behavior | `local_ws_server_test.dart` parse-time-ack **pin** (P1.2) |
| Device LAN leg (real mDNS/WS) | `integration_test/wifi_transport_test.dart` F1–F4 + smoke S1–S4 re-pins (P5.2 chore; §8) |

---

## 7. Risks and open questions carried forward

### Risks (actively mitigated; verify at each phase)
- **R1** Status-model collision with 115 — Phase 3 and 115 Phase 1 rewrite the same `_persistOutgoingSendResult` and test regions → hard landing-order dependency (115 P1 first), G2 amended, 115 G4 whitelists LAN-committed `'delivered'`.
- **R2** Backstop duplicates ride id-only dedup — safe only with 116 P1–P2 landed (poisoned plain envelopes must never replace edit envelopes); program floor, not this doc's code.
- **R3** Receipt misclassification of `'lan:'` rows (receipts for LAN messages; receipts from quarantined replays) → Phase 2.5 shared origin-marker contract with doc 115.
- **R4** Commit-budget vs old-sender 1500ms budget — a slow SQLCipher insert could push the committed ack past `interactiveLocalBudget` → 1200ms commit budget strictly inside it, P4.2 elapsed-time pin, device p95 evidence (OQ-2).
- **R5** Removing `preserveLocalPeerLabel` shifts census/I3 transport labels → audit `p2p_service_transport_census_test.dart` + Startup/Transport gate before landing (OQ-4).
- **R6** Moving LAN off the in-memory path could inherit `suppressNotification:true` from the shared recovery closure → `replayLiveLanChatMessage` (P2.4) + device notification-parity evidence (§8).
- **R7** `FakeLocalP2PService` breaks twice (P2 + P3 method additions) → do both `LocalP2PService` additions together, touch the fake once.
- **R8** 121-improvements is an uncommitted moving baseline (111/112/113/move-scale work) — re-verify all anchors per session (Caveat 9.5).

### Open questions (unresolved — owner input needed)
- **OQ-1** Owner sign-off on the mixed-version UX tradeoff: new sender → old receiver on offline-LAN shows the pending-family indicator (`'sent'`/`'inboxed'`) for a message the old receiver actually displays, until the fleet upgrades. Alternative (treating legacy acks as delivered) reintroduces the bug by definition.
- **OQ-2** Receiver commit-budget value: proposal 1200ms (< `interactiveLocalBudget` 1500ms; `DirectConfirmTimeout` precedent is 2s but sits inside a larger direct budget) — confirm with device p95 staging-insert latency from the evidence run before freezing the constant.
- **OQ-3** Does anything besides chat traverse the LAN WS message path in production (`sendLocalMessage` is only called from the chat send race today)? If confirmed chat-only, the `LanInboundDecision.accepted` legacy variant for non-chat envelopes is dead code and should be dropped rather than kept.
- **OQ-4** Census/I3 semantics after removing `preserveLocalPeerLabel`: the reuse rung previously labeled LAN-visible peers `'local'` for the transport census — decide whether the census needs a separate LAN-visibility dimension, and re-check `p2p_service_transport_census_test.dart` + the Startup/Transport gate expectations.
- **OQ-5** Should the live-LAN replay reuse the unknown-sender intro recovery exactly as the relay replay does (`main.dart:1610-1633`)? Plan assumes yes via a cloned closure; confirm no notification/UX divergence is wanted for live vs recovered unknown senders.
- **OQ-6** Notification suppression on the LIVE direct deferred-ack path (`suppressNotification:true` today via the shared replay closure) is a pre-existing known issue from the 1:1 audit — this plan deliberately gives LAN the unsuppressed live callback; decide whether to fix the direct path's suppression in a follow-up or keep it in the audit backlog (currently a non-goal here).
- **OQ-7** Should a `legacyAck` retain any sticky weight (e.g. keep the LAN leg in the cold race without short-circuit eligibility)? Plan currently trains nothing on legacy acks — strictly safe, possibly over-conservative for mixed-version fleets.

---

## 8. Evidence bar for closure (per project closure-bar convention)

1. **Suites:** all phase gates green — `flutter test test/core/local_discovery test/core/services test/features/conversation`; `./scripts/run_test_gates.sh 1to1`; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh baseline`; `./scripts/run_test_gates.sh completeness-check` green; `(cd go-mknoon && make test)`; `(cd go-relay-server && go test ./...)` (regression sanity — no Go changes in this plan).
2. **W1 two-device kill proof:** Pixel6 (`21071FDF600CSC`) + iPhone13 (`00008110-...`), same Wi-Fi; iPhone13 in `--profile` per the iOS26.5 JIT memory: send 1:1 over LAN, force-kill the receiver app within ~1s of the sender showing the double-check, relaunch receiver → message present exactly once; FLOW logs must show `LOCAL_WS_COMMIT_ACK_SENT` strictly after the staging insert and `P2P_SERVICE_LAN_STAGED_CHAT_COMMITTED` on the post-restart replay.
3. **Sticky steady-state proof:** ≥3 sends inside the 30s learned-transport TTL window so `CHAT_MSG_SEND_STICKY_TRANSPORT {learned: local}` appears (single-leg path engaged), then repeat the kill test on THAT path — the zero-compensation window the host race tests cannot fully reproduce with real mDNS+WS+SQLCipher timing.
4. **Mixed-version interop on hardware:** previous TestFlight/internal build paired against the new build in BOTH directions — old sender must keep getting acks within budget (no LAN latency regression from the pre-ack DB write; capture p50/p95 ack latency before/after), new sender must show `'sent'`/`'inboxed'` (never delivered/local) against the old receiver.
5. **Offline-LAN scenario** (same Wi-Fi, internet/relay blackholed at the router): new↔new pair delivers with committed ack and shows 'delivered'; new→old shows the truthful pending-family status with the message visible on the old receiver and no failed-status flood.
6. **Move-account migration-gate window:** start a move session on the receiver, send over LAN → sender must NOT show 'delivered' (nack path); after the migration completes/aborts, the backstop copy arrives (W5 device proof).
7. **iOS backgrounding/suspension:** background the receiver mid-send → commit-timeout nack or sender timeout → backstop engages, no false delivered; host tests cannot simulate iOS socket suspension semantics.
8. **Notification parity:** a live LAN message on a locked device still raises a notification (`replayLiveLanChatMessage` wiring) — platform notification channels are unreachable from host tests.
9. **Device LAN suite:** `integration_test/wifi_transport_test.dart` F1–F4 re-run on simulator/device with the committed-ack frame expectations, the `run_wifi_relay_fallback_smoke` S1–S4 re-pins (Phase 5.2 sweep), plus one run of `dart run integration_test/scripts/run_transport_e2e.dart -d <simulator-id>` to confirm the relay/inbox legs are unaffected.
10. **Docs:** `test-gate-definitions.md` updated (`## 114 LAN Ack-After-Commit Gate Capture`; both new/extended files in the 1to1 list, doc + script arrays as one coordinated edit with docs 115/116); this doc updated with closure verdicts per phase.

---

## 9. Verified caveats

### 9.1 No DB migration in this doc
`inbox_staging_entries` is reused with the new `'lan:'` entryId namespace; the recovery sweep (`getRecoverableEntries`) is prefix-agnostic. The only migration this program needs from this doc's perspective is 115 Phase 1's 077 (status `'inboxed'`, DB v77) — a Phase-3 prerequisite, not a 114 deliverable. (113 took 076/v76 and is already implemented.)

### 9.2 No Go or relay changes
The entire fix is Dart-side. `node.go:1616-1651` (deferred direct ack), `feature_flags.go:42`, `config.go:81`, and the relay's stage-then-ack-delete (`go-relay-server/inbox.go:771-791`) are the untouched parity models. No gomobile rebuild, no relay deploy from this doc; the program's single deploy train (landing-order step 7) carries only 115's relay changes.

### 9.3 `implements`-based fakes
`P2PService` abstract interface is UNCHANGED — zero of the 32 implements-P2PService fakes touched (`implements` ignores default bodies per project memory). The only fake that breaks is `FakeLocalP2PService` (`test/core/local_discovery/fake_local_p2p_service.dart:8`), twice (P2 `configureInboundChatCommitHandler`, P3 `sendMessageDetailed`) — do both additions together. `DurableLanSender` is opt-in; only fakes that LAN tests need implement it.

### 9.4 Status-model dependency is load-bearing
Phase 3's expectations (`'inboxed'` terminals, G2 amended) are only satisfiable on a tree where 115 Phase 1 has landed. Do not start Phase 3 RED work against a pre-077 tree — the tests would be red for the wrong reason (missing status) and would mask the actual behavior change. Phases 1–2 have no such dependency.

### 9.5 Line-number re-check
All file:line anchors verified 2026-06-12 against the UNCOMMITTED 121-improvements tree (contains the 111/112/113 work, move-scale, voice-wake-lock). The sender-side anchors (`:1235-1241`, `:1675-1684`, `:1692-1748`) already drifted once from the original audit claim — and 115 Phase 1 + 116 Phases 1–2 will rewrite these exact regions BEFORE this doc's Phase 3 runs. Re-verify every anchor per session; re-run the recon agents if the tree shifts materially.

### 9.6 Using the arch graph during implementation
Anchor `graphify query` on 1–2 exact symbol names (`LocalWsServer`, `_tryLocalSend`, `_shouldDurablyStageDeferredDirectChat`), never prose. For this repo, refresh the architecture graph after code edits with `./graphify-arch/refresh_arch_graph.sh` from the repo root. Never run `graphify update` or extraction with cwd inside `graphify-arch/`; if `uv tool upgrade graphifyy` occurs, remove `graphify-out/cache/ast` before rebuilding.

---

## Review resolution log

- 2026-06-13 — S1 accepted: `LocalWsServer` gained the committed/legacy/failed LAN ack seam via `lan_ack.dart`; handler-configured chat withholds ack until commit, explicit nacks are classified, legacy unconfigured parse-time ack remains byte-compatible, and local-discovery tests plus `1to1` and completeness passed.
- 2026-06-13 — S2 accepted: `LocalP2PService` and `P2PServiceImpl` now stage LAN chat envelopes as `lan:<nonce>` rows before committed ack, replay through staging dispositions, keep live LAN notification routing unsuppressed, and reject/fallback truthfully on staging errors. Host local/core service gates, `1to1`, completeness, analyzer, diff check, and arch graph refresh passed.
- 2026-06-13 — S3 accepted: sender-side durable LAN capability now maps only committed LAN ack to delivered/local; legacy/bool LAN acks route through the durable inbox/backstop path as `inboxed` or retryable `sent` with `wireEnvelope`; sticky `local` is trained only by committed LAN ack; Go reuse wins record actual transport. Host sender/core/local tests, `1to1`, completeness, analyzer, diff check, and arch graph refresh passed. The later closure pass resolved the simulator schema issue.
- 2026-06-13 — S4 accepted: `test/core/local_discovery/local_ws_durable_ack_integration_test.dart` proves real loopback WS committed ack over a real staging DB, restart replay deletion, quarantine, old/new ack skew, rejecting nacks, old matcher nack timeout, and media envelope preservation. Focused analyzer/test, `test/core/local_discovery`, `1to1`, completeness `841/841`, diff check, and arch graph refresh passed.
- 2026-06-13 — S5 closure decision at the time: doc 114 was not the last-closing doc in the 114/115/116 batch, so the shared frozen `1to1` script-array edit was recorded in `test-gate-definitions.md` and left for the last-closing sibling doc. Superseded by the closure re-audit below.
- 2026-06-13 — Final closure re-audit: doc 116 completed the coordinated gate-array edit (`edit_retry_round_trip_test.dart` is in both `test-gate-definitions.md` and `scripts/run_test_gates.sh`; `test-gate-definitions.md` also records docs 115/116 expanding the frozen `1to1` gate). Doc 115 P3 is closed in doc 115 evidence. The Wi-Fi relay fallback smoke harness now applies migrations 075 and 077, uses DB version 77, and accepts truthful `inboxed` fallback statuses; `./scripts/run_reliability_simulations.sh 1to1 --only 16` passed S1-S4 at 4/4 on 2026-06-13. Doc 114 is closed for implementation with residual physical-device proof archived, not claimed.

---

## Closure log

Final doc 114 verdict: **closed for implementation; residual device-lab evidence archived**.

Accepted host scope:

- LAN WebSocket 1:1 text ack is committed only after receiver-side durable staging.
- Rejected, failed, legacy, or bool-only LAN acks do not mint delivered/local.
- Legacy and bool-only LAN sends run the durable custody backstop and persist `inboxed` or retryable `sent` with `wireEnvelope`.
- `lan:<nonce>` staged rows participate in replay, quarantine, and retry dispositions.
- Sticky local transport is trained only by committed LAN ack, and Go-channel reuse is no longer mislabeled as local.
- Host loopback coverage verifies the composed S1-S3 behavior over real WS frames and a real staging DB.

Verification recorded during S1-S4:

- `flutter test test/core/local_discovery/local_ws_server_test.dart`
- `flutter test test/core/local_discovery/local_ws_durable_ack_integration_test.dart`
- `flutter test test/core/local_discovery` (`+118` in S4)
- focused S2/S3 local, core-service, sender, listener, incoming-message, and integration slices
- `./scripts/run_test_gates.sh 1to1` (`+593` in S3/S4; final expanded
  three-doc rerun passed with `+793` on 2026-06-13)
- `./scripts/run_test_gates.sh completeness-check` (`841/841` in S4)
- targeted analyzer checks, `git diff --check`, and `./graphify-arch/refresh_arch_graph.sh`

Residual evidence archive:

- Device/mDNS/mixed-version proof from Evidence bar items 2-9 was not collected by this host/simulator run. Local device discovery found the named Pixel 6 (`21071FDF600CSC`) and iPhone (`00008110-00184D622289801E`) plus booted iOS simulators, but no force-kill, sticky steady-state, old-TestFlight/internal-build, router-blackhole/offline-LAN, migration-window, iOS suspension, or locked-device notification transcript was produced. This is archived as unclaimed external lab evidence, not an open implementation task.
- `wifi_relay_fallback_smoke_test.dart` S1-S4 is no longer blocked: command `./scripts/run_reliability_simulations.sh 1to1 --only 16` passed on 2026-06-13 after the harness added migrations 075/077, DB version 77, and truthful `inboxed` fallback expectations. The run reported S1-S4 `4/4 passed, 0 failed` and final result `PASSED`.
- Resolved/stale items: doc 116 completed the coordinated 114/115/116 frozen `1to1` gate-array edit, and doc 115 P3 retry-unacked truthfulness is accepted/closed in doc 115 evidence. These are not doc-114 blockers.

---

## Amendment log

- 2026-06-13 — Updated graphify implementation guidance to use `./graphify-arch/refresh_arch_graph.sh` from repo root and removed the stale instruction to run `graphify update .` for this repo's arch graph.
- 2026-06-13 — Final re-audit removed the stale command-16 schema issue after `integration_test/wifi_relay_fallback_smoke_test.dart` was brought to DB version 77 and command 16 passed. Physical-device lab evidence remains unclaimed residual evidence rather than a doc status.
