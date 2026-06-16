# 125 / F8 tier-2 — Wire-stamped `dedupKey` for forward/share re-mint dedup (TDD Plan)

Status: execution-ready | Date: 2026-06-16 | Branch: 124-harness-refactor
Source findings: 8-finding verification workflow (F8), re-anchored on `124-harness-refactor`; group double-card precedent (`Test-Flight-Improv/Group-Chat-Feature/double-stacked-message-cards-investigation-2026-06-04.md`); forward/share HARD-prereq memory note (`project_forward_share_dedup_key_prereq.md`).
Ownership: 125 owns the **wire contract, receiver dedup, persistence, and migration**, plus the "every normal send stamps `dedupKey = own id`" default. The forward/share affordance itself (UI/entry point + the call-site decision to copy a source key) is **co-owned with the forward/share feature plan** (see Open Questions OQ-2).
Relationship to the main 125 plan: this is the tier-2 deepening of F8. The main 125 plan lands F8 **tier-1** (`existsByContent`, timestamp-exact content dedup at `handle_incoming_chat_message_use_case.dart:373-402`). Tier-2 sits ON TOP of tier-1 and takes precedence only when a `dedupKey` is present; tier-1 stays byte-identical for keyless (legacy-sender) traffic. Land tier-1 first.

> **⚠ MIGRATION-NUMBER COLLISION (resolve before implementing §6).** Highest migration on disk is **077**, so this plan names the new migration **078**. The concurrently-in-flight `Test-Flight-Improv/Group-Chat-Feature/Improvement-Review-2026-06/02-P0-undecryptable-messages-self-heal-TDD-plan.md` **also** claims migration **078 / DB v78**. Whichever lands first takes 078; the other (likely this one, since it is the forward/share *prerequisite* and not yet urgent) MUST renumber to **079 / v79**. Re-confirm the highest on-disk migration at implementation time and pick the next free number.

---

## Problem statement

Tier-1 (F8, main 125 plan) dedups a divergent-id re-delivery of the *same logical message* by matching `(senderPeerId, text, timestamp)` exactly (`handle_incoming_chat_message_use_case.dart:373-402`; `messages_db_helpers.dart:46-62`, `dbExistsMessageByContent`). The `timestamp = ?` predicate is **timestamp-exact**. It catches a second delivery channel (GossipSub + relay) or a re-minted id that re-uses the **original wire timestamp**. It is **structurally unable** to catch a forward/share that re-mints a fresh id AND a fresh timestamp for the same content.

### Why tier-1 is insufficient — the forward/share re-mint scenario

The send use case mints a fresh id **and** a fresh timestamp **only when both are null**:

```dart
// send_chat_message_use_case.dart:340-342
final resolvedMessageId = messageId ?? _uuid.v4();
final resolvedTimestamp = timestamp ?? DateTime.now().toUtc().toIso8601String();
```

- **Edit** (`:1171-1189`) passes `messageId: originalMessage.id, timestamp: originalMessage.timestamp` → reuses both → already covered by the by-id gate (`:283`/`:292`) and tier-1.
- **Retry** (`retry_failed_messages_use_case.dart:351`) passes `messageId: msg.id` and the original timestamp → reuses both → already covered.
- **A forward / share-to-contact of stored content** would pass **neither** → a fresh id AND a fresh timestamp. This is the exact tier-2 hole: the same logical content re-emitted with a brand-new `(id, timestamp)` pair escapes both the by-id gate (id differs) and tier-1 (timestamp differs), persisting a **second card** — the 1:1 twin of the group double-card cascade.

The group precedent confirms the limitation is known: the group's `dbExistsGroupMessageByContent` (`group_messages_db_helpers.dart:592-613`) is also timestamp-exact and is explicitly the *secondary/legacy fallback* beneath the group's primary id-based dedup (`stableMessageId`).

### Live reachability today (scoping fact — LATENT/greenfield)

`dedupKey`/`dedup_key` does **not** exist anywhere in `lib/` or `test/` (grep: 0 hits) — greenfield.

A share-to-contact path exists (`lib/features/share/**`) but it **only re-sends brand-new external OS-share content** (`ShareIntent.text`/`filePaths`), routed through `_sendToContact` (`share_batch_delivery_coordinator.dart:270-371`) → `sendChatMessage(...)` at `:337` with **no `messageId`, no `timestamp`**. There is **no in-app affordance that re-emits an already-stored `ConversationMessage`** (grep for `forward`/`passAlong` in `lib/features/conversation/` returns only `AnimationController.forward()` and prose; the grep for the forward affordance returns empty).

**Implication:** the tier-2 double-card scenario is **latent** — not reachable from the share UI as-shipped. Two separate share invocations of the same OS payload would each mint id+timestamp and *would* double-card today, but no single send re-emits stored content. The dedupKey contract is being defined **ahead of** the forward feature, as a HARD prereq: land the wire field + receiver dedup + the "stamp dedupKey = own id on every send" policy NOW, so the future forward path only has to *copy* the source key.

---

## Methodology

- **RED-first.** Every tier-2 behavior gets a test that FAILS on tier-1-only HEAD for the stated mechanism before any production edit: the tier-2 receive gate, `existsByDedupKey`, the migration, payload round-trip, and the boomerang/no-false-positive locks. Tier-1's existing positive/negative/mismatch cases are kept and asserted **green and unchanged** as regression sentinels.
- **Mutation-check for guards / one-line value changes.** Tier-2 is a bool-returning gate plus a wire field; author each RED so it cannot pass without the behavior change, then confirm by reverting the GREEN edit that the test goes red. Two specific anti-vacuity disciplines (load-bearing):
  - **Distinct-event discriminator (kills the vacuous tier-1 catch).** Tier-1 and tier-2 both return `HandleChatMessageResult.duplicate`, so a status-only assertion cannot tell them apart, and a tier-2 RED whose arrival accidentally re-uses tier-1's timestamp passes **vacuously** even with tier-2 deleted. Every tier-2 positive case MUST assert the emitted event is `CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY` **AND NOT** `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT`. This converts "two duplicate codepaths look identical" into a hard discriminator (D1).
  - **Override the hardcoded timestamp.** `buildValidChatJson` hardcodes the timestamp at `:409`; a forward RED MUST override it (divergent id AND divergent timestamp) or tier-1 catches it and the tier-2 RED is meaningless. The harness extension makes timestamp overridable; the case MUST actually pass `timestamp: T1 ≠ T0`.
- **Anti-masking discipline:** the RED MUST use a DIFFERENT id with SAME content (reusing `'msg-uuid-001'` passes vacuously through the by-id gate at `:283`); and a content-hash derivation is explicitly rejected (it would false-positive on two genuine identical texts — see Design §2.1, locked by test 7.1 case 2).
- **Reuse named harnesses:** `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` reusing the in-file `FakeMessageRepository` (`:99`) + `buildValidChatJson` (`:393-416`); migration test clones `077_message_relay_custody_test.dart:13-78` (sqfliteFfi); repo unit reuses `message_repository_impl_test.dart` (`:15`) over sqfliteFfi; payload round-trip in `message_payload_test.dart`.

---

## Design decisions

### 2.1 dedupKey DERIVATION — propagated source-id, NOT content-hash (load-bearing)

**Decision: `dedupKey` is a propagated source-message identifier.** For a normal message it equals that message's own minted id; a forward copies the source's existing `dedupKey` verbatim.

**Justification (the load-bearing requirement is no-false-positive, requirement c):**

| Property | Propagated source-id | Content-hash |
|---|---|---|
| (a) two forwards of msg X dedup | yes — same source-id | yes — same hash |
| (b) re-mint of X (new id+ts) dedups | yes — source-id copied | yes — same hash |
| (c) two distinct identical texts ("ok" twice) do **NOT** collide | yes — two distinct minted ids → two distinct keys | **NO — same hash → 2nd silently dropped (NEW loss bug)** |

A content-hash violates requirement (c): two genuinely separate "ok" sends hash identically and the second is silently swallowed — the *inverse* failure of the double-card, an actual message-loss regression. A propagated id satisfies all three because identity is minted-once-per-logical-message, decoupled from content. This mirrors the group `stableMessageId` precedent exactly: the group's stable key is the sender's own UUID (`send_group_message_use_case.dart:357`/`908`), stamped once into the wire (`:986`), adopted by the receiver as the row id (`handle_incoming_group_message_use_case.dart:670`), and used as the **primary** dedup gate (`:475`) — `existsByContent` is only the timestamp-bound fallback.

The codebase has `sha256` (`crypto: ^3.0.6`, used at `contact_safety_number.dart:30` and `group_media_integrity_policy.dart:100`) but exclusively for **byte-integrity**, never logical-message identity. Do **not** repurpose it for dedupKey.

### 2.2 STAMPING POLICY

| Send kind | Stamps dedupKey? | Value |
|---|---|---|
| **Normal send** (new content) | **Yes** | `dedupKey = resolvedMessageId` (its own id) |
| **Forward / share-to-contact** of stored msg X | **Yes** | `dedupKey = X.dedupKey` (which, for a normal X, == X's own id) — copied verbatim onto the **fresh** id+timestamp |
| **Edit** (`:1171`) | **No new key** | already reuses id+timestamp; covered by by-id gate + tier-1. Threading a dedupKey is unnecessary and risks double-stamping. |
| **Retry** (`:351`) | **No new key** | reuses id+timestamp; covered by by-id gate + tier-1. |
| **Legacy / pre-rollout sender** | absent (null) | receiver falls back to tier-1 |

**Why stamp on EVERY normal send (not just on the future forward path):** stamping `dedupKey = own id` universally means a future forward only needs to *copy* the source's already-present key — no retrofitting of historical messages, no special-casing whether the source predates the feature. This is the safer prereq per the memory note. The marginal cost is one extra (already-known) string in the inner JSON.

**Forward semantics:** a forward copies the SOURCE message's `dedupKey`, NOT the source's `id`. The forward gets a fresh id (so it is a distinct row at sender and receiver and threads its own delivery/retry) but shares the source's `dedupKey` so the receiver recognizes "this is the same logical content I already have."

**Sender-N / receiver-1 is the intended invariant (D3).** Tier-2 is a RECEIVER-side dedup. The sender retains its own forward row (fresh id, own delivery/retry thread). On a tier-2 duplicate the receiver re-mints a delivery receipt for the forward's *fresh* id (so the sender's forward row goes `delivered`), then drops the row. Net: **sender shows N rows, receiver shows 1 row — by design.** Do not "fix" this asymmetry. It is locked by an explicit receipt-emission assertion on the tier-2 path (test 7.1 case 5 + the step-6 end-to-end test) so that a future refactor gating receipt emission behind "actually persisted" cannot silently break forward delivery-status.

---

## 3. Wire change — `MessagePayload.dedupKey`

**File:** `lib/features/conversation/domain/models/message_payload.dart`

Add a nullable, additive field. Every touch-point below must round-trip it; the v2 inner JSON (`toInnerJson`/`fromDecryptedJson`) is the prod-critical leg.

**GREEN production change:**

1. **Field decl** (`:19-27` block, after `media`): `final String? dedupKey;`
2. **Const ctor** (`:29-39`): add `this.dedupKey,` (defaulted-nullable → all 15 `MessagePayload(...)` call sites stay compiling).
3. **`toJson()` v1 payload map** (`:95-106`): `if (dedupKey != null) 'dedupKey': dedupKey,`
4. **`fromJson()` v1 parse** (`:46-77`, returned ctor `:78-88`): `dedupKey: json['payload']['dedupKey'] as String?,`
5. **`toInnerJson()` v2 inner** (`:208-219`) — **PROD-CRITICAL**: `if (dedupKey != null) 'dedupKey': dedupKey,`
6. **`fromDecryptedJson()` v2 inner parse** (`:163-188`, returned ctor `:189-199`): `dedupKey: json['dedupKey'] as String?,`
7. **`buildEncryptedEnvelope(...)`** (`:120-136`): **NO change** — the v2 outer envelope carries only `id` + `senderPeerId` cleartext; dedupKey rides the *inner* JSON. Keeping it inside the encrypted payload also avoids leaking a cross-message linkability handle to the relay.
8. **`toConversationMessage(...)`** (`:227-250`): thread `dedupKey: dedupKey` onto the produced `ConversationMessage` (required so persisted rows and real-store fakes expose the key — see §4/§5).

> **DROP HAZARD (must not miss — highest-frequency footgun):** the receiver re-builds `payload` field-by-field at `handle_incoming_chat_message_use_case.dart:227-237` (bidi-sanitization rebuild — currently carries `id, text, senderPeerId, senderUsername, timestamp, action, editedAt, quotedMessageId, media`). A new `dedupKey` is **silently dropped** there unless explicitly added to that reconstruction. Add `dedupKey: payload.dedupKey,` to that constructor call. Verified against HEAD: this is the single easiest place to lose the field.

**RED tests (write first) — §7.5 payload round-trip:**

- In `message_payload_test.dart`: assert `dedupKey` survives `toJson→fromJson` (v1) AND `toInnerJson→fromDecryptedJson` (v2 inner). *Kills:* forgetting `toInnerJson` (the prod-critical drop — would silently strip dedupKey on every real 1:1 send while v1 tests pass).
- **Media-payload round-trip (M3):** add one case asserting `dedupKey` survives alongside a non-null `media` descriptor through the v2 inner leg — locks that a media forward carries its dedupKey (media forwards are in-contract; the receiver keeps the original media and dedups the duplicate card).

**Refactor notes / risks:** defaulted-nullable means all 15 `MessagePayload(...)` named-arg constructions compile unchanged. `GroupMessagePayload` is a **different class** — out of scope (groups already have `stableMessageId` as primary dedup; see §9 non-goals).

---

## 4. Receiver change — tier-2 dedup

**File:** `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`

### 4.1 GREEN — the tier-2 gate in `handleIncomingChatMessage`

**Placement & precedence:** tier-2 sits inside the **same** guard region as tier-1 (`if (existingMessage == null && !payload.isEdit)`, `:380`) so intentional transitions (same-id edits, hidden-edit materialization, deleted-placeholder merge) are never swallowed. Tier-2 takes **precedence** when `payload.dedupKey != null`; otherwise tier-1 runs:

```dart
if (existingMessage == null && !payload.isEdit) {
  if (payload.dedupKey != null && payload.dedupKey!.isNotEmpty) {
    // Tier-2: survives id+timestamp re-mint (forward/share).
    final isDedupKeyDuplicate = await messageRepo.existsByDedupKey(
      payload.senderPeerId,   // contactPeerId  (incoming 1:1: contact == sender)
      payload.senderPeerId,   // senderPeerId
      payload.dedupKey!,
    );
    if (isDedupKeyDuplicate) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY',
        details: {'id': _shortId(payload.id)},
      );
      await maybeSendDeliveryReceipt(payload.id); // re-mint receipt for the fresh id
      return (HandleChatMessageResult.duplicate, null, null);
    }
    // dedupKey present but no match → fall through to PERSIST (NOT tier-1;
    // a keyed message that doesn't match is genuinely new content).
  } else {
    // Tier-1 (legacy-sender fallback): timestamp-exact content dedup, unchanged.
    final isContentDuplicate = await messageRepo.existsByContent(
      payload.senderPeerId, payload.senderPeerId, payload.text, payload.timestamp,
    );
    if (isContentDuplicate) {
      emitFlowEvent(layer: 'FL', event: 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT',
        details: {'id': _shortId(payload.id)});
      await maybeSendDeliveryReceipt(payload.id);
      return (HandleChatMessageResult.duplicate, null, null);
    }
  }
}
```

Key contract points:
- **`contactPeerId == senderPeerId == payload.senderPeerId`** — mirrors tier-1's double-use (`:381-385`) and matches the persisted incoming row (`contact_peer_id = payload.senderPeerId`, `:450`). A tier-2 query with a different convention would never find the existing row.
- **Non-null + non-empty gate** is the false-positive guard. Two real identical "ok"s carry distinct/absent keys → never collapsed.
- **No new enum value** — tier-2 returns the existing `HandleChatMessageResult.duplicate` (`:45`).
- **Receipt re-mint preserved** — `maybeSendDeliveryReceipt(payload.id)` so the sender's new-id forward is still acked (D3 invariant), then dropped.
- The branch where `dedupKey != null` but **no** match falls through to persist (genuinely new); it does **not** also run tier-1 (the dedupKey is the authoritative signal for keyed senders).

### 4.2 GREEN — persist the key on the row

At persist (`:426-456`, `payload.toConversationMessage(...)`), the produced `ConversationMessage` now carries `dedupKey`, so `saveMessage` → `dbInsertMessage(message.toMap())` writes `dedup_key` automatically (see §5/§6). **Tier-2 MUST persist the key** (unlike tier-1, which keys on already-persisted text/timestamp), because `existsByDedupKey` runs a SQL gate against the `dedup_key` column; without persistence cross-restart dedup fails and the second copy is never detectable.

### 4.3 GREEN — repository plumbing `existsByDedupKey`

Mirror the tier-1 `existsByContent` fan-out across 3 layers + production wiring:

- **Interface** `message_repository.dart:38-43` — add:
  ```dart
  Future<bool> existsByDedupKey(
    String contactPeerId, String senderPeerId, String dedupKey);
  ```
- **Impl** `message_repository_impl.dart` — add injected fn field `dbExistsMessageByDedupKey` (next to `:36`), **optional/nullable** ctor param (NOT `required` — avoids touching the 4 test ctor sites, fail-open `false` when null), `@override existsByDedupKey` delegating to it (next to `:207-219`).
- **DB helper** `messages_db_helpers.dart` (next to `:46-62`):
  ```dart
  Future<bool> dbExistsMessageByDedupKey(
    Database db, String contactPeerId, String senderPeerId, String dedupKey,
  ) async {
    if (dedupKey.isEmpty) return false; // never dedup on absent key
    final rows = await db.query('messages', columns: const ['id'],
      where: 'contact_peer_id = ? AND sender_peer_id = ? AND dedup_key = ? AND is_incoming = 1',
      whereArgs: [contactPeerId, senderPeerId, dedupKey], limit: 1);
    return rows.isNotEmpty;
  }
  ```
- **Production construction** `main.dart:778` (`MessageRepositoryImpl(...)`): thread the closure next to `:799-800`:
  ```dart
  dbExistsMessageByDedupKey: (contactPeerId, senderPeerId, dedupKey) =>
      dbExistsMessageByDedupKey(db, contactPeerId, senderPeerId, dedupKey),
  ```

### 4.4 RED tests (write first) — §7.1 tier-2 receive

Harness extensions (in-file `FakeMessageRepository` at `:99-230`):
- Add an `existsByDedupKey` override scanning `_existingMessages.values` for `m.isIncoming && m.contactPeerId == … && m.senderPeerId == … && m.dedupKey == dedupKey`.
- Extend `buildValidChatJson(...)` (`:393-416`) with a `String? dedupKey` param (`if (dedupKey != null) 'dedupKey': dedupKey,` in the payload map `:404-414`) **and** allow overriding the hardcoded `timestamp` (`:409`) so a forward can re-mint BOTH.

New cases (mirroring the tier-1 positive/negative at `:499-566`):

1. **Core tier-2 proof — divergent id + DIVERGENT timestamp + SAME dedupKey → `duplicate`, `saved` empty.**
   Seed `existingMessages: {'msg-001': existing(dedupKey:'src-1', ts:T0)}`; receive `buildValidChatJson(id:'msg-002', dedupKey:'src-1', timestamp:T1≠T0)`.
   Assert `HandleChatMessageResult.duplicate`, `messageRepo.saved` empty, **event `CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY` emitted AND `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT` NOT emitted** (D1 discriminator — without this assertion the RED can pass vacuously if `T1` accidentally equals the hardcoded `T0` and tier-1 catches it). The case MUST pass an explicit `timestamp: T1 ≠ T0`.
   *Kills:* removing the tier-2 `existsByDedupKey` branch (tier-1 misses it because timestamp differs → would persist → test fails; or, if timestamp accidentally matched, tier-1 emits the wrong event → discriminator fails).

2. **No false-positive on identical text — SAME text, DIFFERENT dedupKey, divergent id+ts → `chatMessage`, persisted.**
   Seed `existing(text:'ok', dedupKey:'src-1')`; receive `(id:'msg-002', text:'ok', dedupKey:'src-2', ts:T1)`. Assert `chatMessage`, row saved, no duplicate event.
   *Kills:* a content-hash derivation or a tier-2 that ignores key equality (requirement c).

3. **No false-positive when key ABSENT — two sub-cases lock the legacy fallback.**
   (3a) keyless + same ts → tier-1 `duplicate` (emits `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT`); (3b) keyless + different ts → `chatMessage` persisted.
   *Kills:* a tier-2 that fires on null/empty key (would over-dedup keyless legacy traffic).

4. **dedupKey present but UNMATCHED → persisted (not falsely deduped, and does NOT fall back to tier-1).**
   Seed `existing(text:'ok', ts:T0, dedupKey:'src-1')`; receive `(text:'ok', ts:T0, dedupKey:'src-9')`. Assert `chatMessage` persisted even though text+timestamp match tier-1's predicate — proves the keyed branch is authoritative.
   *Kills:* an `if/else` that runs tier-1 after a tier-2 miss.

5. **Receipt re-mint on tier-2 duplicate (D3 invariant lock).**
   Seed as case 1; receive the divergent forward. Assert `maybeSendDeliveryReceipt` was invoked **with the fresh `payload.id`** on the tier-2 duplicate path (not only on tier-1). Locks the sender-N/receiver-1 delivery-status contract against a future "emit receipt only when persisted" refactor.

6. **Boomerang lock (D4).**
   Seed an OUTGOING row from me (`is_incoming=0`, `senderPeerId = me`, `dedup_key='X'`); receive an inbound forward from the contact carrying `dedup_key='X'` (`senderPeerId = contact`). Assert the inbound **PERSISTS** (genuinely new from the contact — the `sender_peer_id = payload.senderPeerId` discriminator excludes my outgoing row). Locks the `sender_peer_id` discriminator against a future "global dedup_key" simplification.

### 4.5 Refactor notes / risks

- Highest-frequency footgun is the §3 `:227-237` reconstruction drop — covered by land-order step 5 depending on step 3.
- The `contactPeerId == senderPeerId for incoming 1:1` comment is correct but fragile; OQ-5 flags the multi-recipient revisit.

---

## 5. Persistence — `ConversationMessage.dedupKey`

**File:** `lib/features/conversation/domain/models/conversation_message.dart`

Clone the `wireEnvelope` nullable-column template verbatim (it is the exact pattern):

**GREEN production change:**
- Field decl `final String? dedupKey;` after `custodyCheckedAt` (`:67`); ctor `this.dedupKey,` (`:73-93`).
- `fromMap`: `dedupKey: map['dedup_key'] as String?,` (after `:115`).
- `toMap`: `'dedup_key': dedupKey,` (after `:139`).
- `copyWith`: follow the `_sentinel` nullable pattern (`:163`, `:188-189`).
- `==`/`hashCode` are id-only (`:206-212`) — **unaffected**.
- `media` stays transient (NOT a column).

`MessageRepositoryImpl.saveMessage` already inserts via `message.toMap()` (`message_repository_impl.dart:122` → `dbInsertMessage`); once `toMap` carries `dedup_key`, every save persists it — **no write-path repo change**.

**RED test (write first):** round-trip `toMap→fromMap` carries `dedupKey`; `copyWith(dedupKey: null)` clears it (sentinel) while `copyWith()` preserves it.

---

## 6. Migration

> **NUMBER CONFLICT WARNING (M1 — resolve with the owner BEFORE landing):** HEAD's highest migration is **077** (`077_message_relay_custody.dart`), DB v77 (`app_database_version.dart:1`). Project memory's undecryptable-self-heal plan ALSO claims **078/v78**. **Whichever lands second must renumber.** The migration test filename, the `onUpgrade` `if (oldVersion < N)` guard, and `currentIdentityDatabaseVersion` all hardcode the number, so this is a sequencing decision the owner must make up front, not at implementation time. This plan provisionally uses **078/v78**; if self-heal lands first, this becomes **079/v79** across §6 + the §7.3 filename + the `oldVersion < 79` guard. Re-verify HEAD's highest migration at implementation time.

**New file** `lib/core/database/migrations/078_message_dedup_key.dart` (mirror 077's PRAGMA-guarded idempotent ALTER + 006's `CREATE INDEX IF NOT EXISTS`):

```dart
Future<void> runMessageDedupKeyMigration(Database db) async {
  emitFlowEvent(layer: 'DB', event: 'MESSAGES_DEDUP_KEY_MIGRATION_START',
      details: {'migration': '078_message_dedup_key'});
  try {
    final columns = await db.rawQuery('PRAGMA table_info(messages)');
    final names = columns.map((c) => c['name']).toSet();
    if (!names.contains('dedup_key')) {
      await db.execute('ALTER TABLE messages ADD COLUMN dedup_key TEXT'); // nullable
    }
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_messages_dedup_key
  ON messages(contact_peer_id, sender_peer_id, dedup_key)''');
    emitFlowEvent(layer: 'DB', event: 'MESSAGES_DEDUP_KEY_MIGRATION_SUCCESS',
        details: {'migration': '078_message_dedup_key'});
  } catch (e) {
    emitFlowEvent(layer: 'DB', event: 'MESSAGES_DEDUP_KEY_MIGRATION_ERROR',
        details: {'migration': '078_message_dedup_key', 'error': e.toString()});
    rethrow;
  }
}
```

**Registration (2 edits):**
- `app_database_version.dart:1` → `const int currentIdentityDatabaseVersion = 78;`
- `main.dart`: add `await runMessageDedupKeyMigration(db);` to the onCreate ladder immediately after `:456`; add `if (oldVersion < 78) { await runMessageDedupKeyMigration(db); }` before the closing `},` at `:685`.

**Index, NOT unique:** the index is non-UNIQUE on purpose. A UNIQUE constraint would reject legitimate repeated forwards (same key, distinct rows) and would also be ambiguous across many NULL keys. Dedup is **query-time only**; `ConflictAlgorithm.replace` on the `id` PK in `dbInsertMessage` (`:8-37`) does NOT help (a forward re-mints id → no PK collision), which is precisely why dedup must run **pre-persist**, as tier-1 already does.

**Cross-version safety:** existing rows have NULL `dedup_key`; the tier-2 SQL gate requires a non-null `dedupKey` on the *incoming payload* and never matches a non-null arg against a NULL row, so pre-migration rows survive and never break tier-2 lookups.

---

## 7. RED-first test catalog (mutation-checkable summary)

All new/extended tests fail on tier-1-only HEAD and pass only after the corresponding production change.

### 7.1 Tier-2 receive — `handle_incoming_chat_message_use_case_test.dart`
Cases 1–6 as enumerated in §4.4 (core proof with D1 discriminator; identical-text no-false-positive; keyless fallback 3a/3b; unmatched-key-persists; D3 receipt re-mint; D4 boomerang).

### 7.2 `existsByDedupKey` unit — `message_repository_impl_test.dart` (ctor site `:15`) / `messages_db_helpers` over sqfliteFfi
Insert an incoming row with `dedup_key='k1'`; assert `existsByDedupKey(c,s,'k1')==true`, `(c,s,'k2')==false`, `(c,s,'')==false`, and that an **outgoing** (`is_incoming=0`) row with `dedup_key='k1'` does **not** match.
*Kills:* dropping the `is_incoming = 1` clause or the empty-key early-return.

### 7.3 Migration — `test/core/database/migrations/078_message_dedup_key_test.dart`
Clone `077_message_relay_custody_test.dart:13-78` (sqfliteFfi). Three cases:
1. column added — `PRAGMA table_info(messages)` contains `dedup_key`;
2. preserves existing rows with NULL `dedup_key` (pre-migration rows survive, `dedup_key IS NULL`);
3. idempotent — running twice does not throw (PRAGMA guard + `IF NOT EXISTS` index).
Auto-classified into the "core database" suite by `run_test_gates.sh:488` → no gate-array edit needed.

### 7.4 Preserved-tier-1 regression sentinels
Keep/assert the existing tier-1 cases (`:499-531` positive, `:533-566` negative, `:569+` mismatch-telemetry) **unchanged and green** — proves tier-2 did not regress the legacy-sender path. The "keyless arrival still hits tier-1" sentinel is covered by 7.1 case 3a.

### 7.5 Payload round-trip — `message_payload_test.dart`
v1 (`toJson→fromJson`) AND v2 inner (`toInnerJson→fromDecryptedJson`) carry `dedupKey`; plus the media-payload variant (dedupKey survives alongside `media`, M3). *Kills:* the prod-critical `toInnerJson` drop.

### 7.6 End-to-end two-user dedup (INTEGRATION) — `two_user_message_exchange_test.dart` (extend) or new sibling `forward_remint_dedup_test.dart`

The §7.1–7.5 tests all stop at a use-case/repo boundary with in-file fakes. **§7.6 is the only test that proves the full loop closes**: `sendChatMessage` → `MessagePayload.toInnerJson` → FakeBridge **v2 encrypt** → `FakeP2PNetwork` wire → FakeBridge **decrypt** → `ChatMessageListener` → `handleIncomingChatMessage` → tier-2 gate → `existsByDedupKey` over the receiver's real store. It exercises the **prod-critical `toInnerJson`/`fromDecryptedJson` leg over the actual transport** (a divergent receive-path reconstruction — see `:227-237` sanitization rebuild — that strips `dedupKey` survives §7.5's isolated unit but dies here), AND closes the **sender-stamps-own-id → receiver-dedups loop** plus the D3 cross-party receipt invariant. Contacts carry an `mlKemPublicKey` (`TestUser.addContact:549`) so the send is genuinely **v2-encrypted** — the inner-JSON leg is real, not the v1 fallback.

**Harness (verified anchors):** `FakeP2PNetwork` (`:37`) + `TestUser` (`:490`, `.create`/`.sendMessage:555`/`.loadConversation:573`/`.chatListener.incomingMessageStream`) + `InMemoryMessageRepository` (`:278`). The standard `setUp` (`:609-631`) wires alice↔bob as mutual contacts with listeners started. **Prereq:** `InMemoryMessageRepository.existsByDedupKey` MUST have a REAL body (scan stored incoming rows by `dedupKey`), per §8.1 — a `=> false` stub makes this test pass vacuously, so the §8.1 "real-store fake" requirement is load-bearing for §7.6.

**Forward simulation (no forward affordance exists — D-LATENT):** drive the re-mint through the public send use case directly rather than the (nonexistent) forward UI:
```dart
// 1) Normal send → stamps dedupKey = own id; Bob persists exactly 1 row.
final (res1, sent1) = await alice.sendMessage(bob.peerId, 'Hello Bob!');
await bob.chatListener.incomingMessageStream.first.timeout(const Duration(seconds: 2));
expect((await bob.loadConversation(alice.peerId)).length, 1);
final sourceKey = sent1!.dedupKey;            // == sent1.id (own-id default)
expect(sourceKey, isNotNull);

// 2) "Forward" of the SAME content: COPY dedupKey, RE-MINT id AND timestamp.
final flow = <Map<String, dynamic>>[];
debugSetFlowEventSink(flow.add);
addTearDown(() => debugSetFlowEventSink(null));
await sendChatMessage(
  p2pService: alice.p2pService, messageRepo: alice.messageRepo,
  targetPeerId: bob.peerId, text: 'Hello Bob!',
  senderPeerId: alice.peerId, senderUsername: alice.username,
  bridge: alice.bridge,
  recipientMlKemPublicKey: (await alice.contactRepo.getContact(bob.peerId))!.mlKemPublicKey,
  dedupKey: sourceKey,                          // ← propagated source id
  messageId: 'forward-fresh-id-0001',           // ← divergent id
  timestamp: '2099-01-01T00:00:00.000Z',        // ← divergent timestamp (tier-1 cannot catch)
);
await _pumpUntil(() => flow.any((e) => e['event'] == 'CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY'));
```

**Assertions (RED on tier-1-only HEAD):**
1. **Receiver shows exactly 1 row** — `(await bob.loadConversation(alice.peerId)).length == 1`. *On HEAD Bob double-cards (2 rows): the forward's id differs from the by-id gate and its timestamp differs from tier-1, so neither catches it.*
2. **The dedup fired on the KEY, not content** — `flow` contains `CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY` and **NOT** `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT` (the D1 discriminator end-to-end — proves the wire carried `dedupKey` and tier-2 (not tier-1) made the call). *Kills the vacuous-tier-1-catch failure mode at the integration layer.*
3. **D3 sender-N/receiver-1 + receipt** — the receiver re-mints a delivery receipt for the forward's **fresh** id (so the sender's forward row can reach `delivered`), asserted via the receipt hook / a `delivered`-status check on the forward row; the receiver still shows 1 row.
4. **No-false-positive control (integration)** — a THIRD send of identical text `'Hello Bob!'` as a NORMAL send (fresh own-id dedupKey, NOT the source key) → Bob now shows **2 rows** (the genuine repeat is NOT swallowed). Locks the propagated-source-id choice over a content-hash at the end-to-end layer.

**Gate placement:** add the file to `ONE_TO_ONE_TESTS` (`run_test_gates.sh`, near `two_user_message_exchange_test.dart`) and run completeness-check. **Mutation-check:** revert the `handleIncomingChatMessage` tier-2 gate → assertion 1 goes red (2 rows); revert the `toInnerJson`/`fromDecryptedJson` dedupKey serialization → assertion 2 flips (the wire drops the key → tier-2 can't fire → `_CONTENT` or no dedup), proving §7.6 covers the prod-critical leg §7.5 only unit-tests.

**Out of scope (correctly deferred):** a test driving the real **forward/share UI affordance** belongs to the forward/share feature plan (no such affordance exists yet — D-LATENT). §7.6 proves the *receiver contract + wire survival + stamping loop* that the affordance will sit on top of; reliability-sim/`transport_e2e` is NOT added (tier-2 is not timing/transport-race sensitive, unlike F3/F5/F7 — a deterministic fake-network round-trip is the right altitude).

---

## 8. Blast radius

### 8.1 `MessageRepository` implementers (1 prod + fakes)
`existsByDedupKey` on the abstract interface forces an override on **every** implementer. Pin the **exact** count at implementation time by grepping `implements MessageRepository` / `extends MessageRepository` on HEAD — a miscount means the suite will not compile (the loose "≈15/19" arithmetic in recon is not authoritative).
- **Production (1):** `MessageRepositoryImpl` — real impl delegating to `dbExistsMessageByDedupKey`.
- **Real-store fakes (4)** — need REAL bodies scanning their store by `dedupKey` (a `false` stub would silently break tier-2 assertions). These also require `ConversationMessage.dedupKey` to compare against:
  - `handle_incoming_chat_message_use_case_test.dart:99` (tier-2's own test fake)
  - `test/features/conversation/domain/repositories/fake_message_repository.dart:7`
  - `test/shared/fakes/in_memory_message_repository.dart:9`
  - `two_user_message_exchange_test.dart:278`
- **Stub fakes (remaining)** — safe `Future<bool> existsByDedupKey(...) async => false;` (none seed incoming content tier-2 dedups): resilience c4, p2p census, delete-contact, chat_message_listener, media-hydration, load_conversation, send-no-bg, send-use-case, send-voice-no-bg, conversation_wired ×3, load_feed, intro-smoke, load_orbit.

### 8.2 `MessageRepositoryImpl` constructor sites
Making `dbExistsMessageByDedupKey` **optional/nullable** (NOT `required`, fail-open `false`) keeps the 4 test ctor sites untouched (`full_migration_chain_test:288`, `app_lifecycle_pause_integration_test:43`, `message_repository_impl_stuck_sending_test:13`, `message_repository_impl_test:15`); only `main.dart:778` gets the new closure. Mirrors the already-optional `dbUpdateWireEnvelope`/`dbLoadInboxCustodyOutgoingMessages` pattern.

### 8.3 `MessagePayload` callers (15)
Defaulted-nullable `dedupKey` → all 15 `MessagePayload(...)` named-arg constructions compile unchanged. `GroupMessagePayload` is a **different class** — out of scope.

### 8.4 Sender stamping call sites
- `send_chat_message_use_case.dart` — add `String? dedupKey` param; default a normal send to `dedupKey ?? resolvedMessageId` (`:340` region), set on the `MessagePayload` (`:357-369`), serialized via `toInnerJson()` (`:380`).
- `conversation_wired.dart` normal-send sites (`:1842`, `:1887`, `:1995`, `:2052`, `:2865`) — **no change** (use-case defaults dedupKey = own id).
- `editChatMessage` (`:1171`) / `retryFailedMessage` (`:351`) — **no new dedupKey** (reuse id+timestamp; covered). An edit of a *forwarded* message reuses the forward's own id, so tier-1/by-id covers it — no gap.
- **Forward/share** (`share_batch_delivery_coordinator.dart:337`) — **co-owned (OQ-2)**: only relevant once a forward path re-sends stored content. For the *current* share path (new OS content) the default `dedupKey = own id` is correct.

### 8.5 Gate & acceptance
**Gate:** `./scripts/run_test_gates.sh 1to1` (the use-case test is in `ONE_TO_ONE_TESTS:33`) + `./scripts/run_test_gates.sh completeness-check`. The new migration test auto-classifies (`:488`) → completeness stays green with no array edit. Optionally add the 078 test to `ONE_TO_ONE_TESTS` near `:28` (mirroring 077). Also run the full suite (`-j 1` if parallel flake recurs per the 120 note) and `flutter analyze` (expect 0 new issues). The §7.5 `toInnerJson` round-trip is a **PROD-CRITICAL** gate (the only thing standing between "every real send" and silent field stripping — M2).

**Acceptance:** all 7.1–7.6 RED→GREEN (incl. the §7.6 end-to-end two-user dedup over the real transport); tier-1 sentinels (7.4) green and unchanged; 0 new analyze issues; mutation check confirmed (revert each GREEN edit → matching test goes red, incl. reverting `toInnerJson` serialization → §7.6 assertion 2 flips); migration idempotent and column-additive on a v77→v78 upgrade.

### 8.6 Recommended landing order (each step RED→GREEN before the next)
1. **Migration 078** + DB version bump + `main.dart` registration + migration test (7.3). *Foundation; nothing depends on it yet.*
2. **`ConversationMessage.dedupKey`** field + `toMap`/`fromMap`/`copyWith` (clone `wireEnvelope`). *No behavior change; round-trip test (§5).*
3. **`MessagePayload.dedupKey`** all 6 round-trip touch-points + the `:227-237` sanitization reconstruction + payload round-trip test (7.5).
4. **`existsByDedupKey`** interface + impl + db helper + `main.dart` closure + all fakes (4 real, rest stub) + unit test (7.2). *Suite must still compile/pass.*
5. **Tier-2 receiver gate** in `handleIncomingChatMessage` + tier-2 receive tests (7.1, incl. D1 discriminator + D3 receipt + D4 boomerang) + preserved-tier-1 (7.4).
6. **Sender stamping** `dedupKey = own id` default in `send_chat_message_use_case`. *Closes the loop on the send side.*
7. **End-to-end integration lock (§7.6)** — extend `two_user_message_exchange_test.dart` (or new `forward_remint_dedup_test.dart`): real send → v2 encrypt → wire → decrypt → receive → tier-2 dedup. A simulated forward (copied dedupKey, **re-minted id AND timestamp**) leaves the receiver with **1 row** via `CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY` (RED on HEAD = 2 rows), the re-minted-id receipt fires (D3), and a genuine identical-text repeat with a fresh key still shows 2 rows. **This is the only step that proves the prod-critical `toInnerJson` leg + the stamping loop end-to-end over the transport — do NOT treat §7.1–7.5 unit coverage as sufficient on its own.** Register in `ONE_TO_ONE_TESTS`.
7. **(Deferred / co-owned)** forward/share call-site copy of source dedupKey — owned with the forward feature plan (OQ-2).

INV preserved throughout: no new `HandleChatMessageResult` value; receipt re-mint behavior intact; tier-1 keyless path byte-identical.

---

## 9. Non-goals (stated to prevent misreading scope as oversight)
- **Group parity:** `GroupMessagePayload` is a different class and groups already use `stableMessageId` as the **primary** dedup gate — groups do not need tier-2. Out of scope.
- **The forward/share affordance UI/entry point:** does not exist on HEAD (grep empty) and is co-owned with the forward feature plan. 125 lands only the contract + receiver + the "normal send stamps own id" default + the documented forward invariant + the tier-2 receive test that *simulates* a forward (OQ-2).
- **Old-receiver protection:** tier-2 dedup is **receiver-side only**; an un-upgraded receiver has only timestamp-exact tier-1 and will double-card a forward. This is acceptable (old build = old behavior) but it makes tier-2 a **both-ends-upgraded** guarantee. See OQ-7 release floor.

---

## 10. Open questions for the owner

1. **Stamping universality (recommend YES).** Confirm every normal send stamps `dedupKey = own id` (so a future forward only copies), vs. stamping only on the not-yet-built forward path. Universal stamping is the safer prereq (no retrofitting historical messages) but writes a `dedup_key` on **every** outgoing-then-received row. Acceptable?

2. **Forward/share co-ownership boundary (125 vs forward feature plan).** 125 owns: wire field, receiver dedup, persistence, migration, AND the "normal send stamps own id" default. The forward feature plan owns: the forward UI/entry point and the call-site decision to pass `dedupKey: source.dedupKey` into `sendChatMessage`. Confirm 125 does NOT build the forward affordance (none exists today) and only lands the contract + a documented invariant ("forward MUST copy source dedupKey, MUST NOT mint a fresh one") + the tier-2 receive test that *simulates* a forward (divergent id+ts, copied key). Is that the right cut?

3. **Migration number (M1).** Provisional **078/v78** collides with the undecryptable-self-heal plan's claimed 078/v78. Which lands first? The second must take **079/v79** across §6, the §7.3 filename, and the `oldVersion < N` guard. Resolve sequencing with the self-heal owner BEFORE either lands.

4. **`dedupKey != null` but unmatched → persist (no tier-1 fallback).** This plan treats a keyed-but-unmatched arrival as authoritatively new (does NOT also run tier-1). Confirm — the alternative (run tier-1 as a secondary net even when a key is present) risks deduping a *new* keyed message that merely shares text+timestamp with an old one. Recommend the authoritative-key behavior as specified.

5. **Outgoing rows & multi-recipient.** Tier-2 query gates on `is_incoming = 1` and `contactPeerId == senderPeerId`. If a future relay/multi-recipient path makes `contactPeerId` differ from `senderPeerId`, the tuple needs revisiting. Confirm 1:1-incoming-only scope for now.

6. **Telemetry event name.** New `CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY` (consistent with tier-1 `CHAT_MSG_RECEIVE_DUPLICATE_CONTENT`). D1 makes the distinct name load-bearing (the discriminator that defeats vacuous tier-1 catches) — confirm naming and keep the two names distinct.

7. **Receiver-first release floor (M2/D2 — HARD prereq).** Tier-2 is effective only receiver-side; a forward double-cards on any un-upgraded receiver (timestamp-exact tier-1 only). The forward/share affordance (co-owned plan) MUST NOT ship until the tier-2 receiver build has a deployment floor in the field — mirror the 112/113 "receiver-first release hold" pattern. Confirm this gate, and confirm the owner explicitly accepts that 125 ships a **live wire-format change (`dedupKey` on 100% of 1:1 traffic) with no immediate consumer**, with the §7.5 `toInnerJson` round-trip treated as the PROD-CRITICAL gate against silent field stripping.

8. **Media forwards in-contract (M3).** A forward of a media message copies the source `dedupKey` over a fresh id/blob; the receiver dedups the card and keeps the ORIGINAL media. Confirm this is intended (for a true forward of the same content it is). Locked by the §7.5 media-payload round-trip case.

---

## 11. Risk ledger

- **`:227-237` reconstruction drop** — dedupKey silently lost unless added there (step 3). Highest-frequency footgun; verified against HEAD.
- **`toInnerJson` omission** — drops dedupKey on every real (v2) 1:1 send while v1 tests pass. Covered by 7.5; PROD-CRITICAL gate.
- **Vacuous tier-2 RED (D1)** — tier-1 and tier-2 both return `duplicate`; without the distinct-event assertion + an explicit `timestamp: T1≠T0` the headline RED can pass even with tier-2 deleted. Mitigated by the discriminator in 7.1 case 1.
- **Receiver-first floor (D2)** — tier-2 protects only upgraded receivers; forward UI must not ship ahead of the deployment floor (OQ-7).
- **Sender-N/receiver-1 asymmetry (D3)** — intended; locked as an invariant + receipt-emission test (7.1 case 5) so a "receipt only when persisted" refactor cannot silently break forward delivery-status.
- **Boomerang collision (D4)** — `sender_peer_id` discriminator must survive any future "global dedup_key" simplification; locked by 7.1 case 6.
- **Content-hash temptation** — rejected; would introduce a real loss bug on repeated identical text (requirement c). Covered by 7.1 case 2.
- **`required` ctor param** — would break 4 test ctor sites; use optional/nullable fail-open.
- **UNIQUE index temptation** — rejected; would reject legitimate repeated forwards. Index is non-UNIQUE.
- **Migration number drift (M1)** — re-verify HEAD's highest migration at implementation time; renumber to 079/v79 if self-heal landed first.
- **Fake fan-out miscount** — missing one breaks suite compilation; pin the exact implementer count by grep on HEAD; 4 need real bodies.

---

**Files touched (summary, all absolute under `/Users/I560101/Project-Sat/mknoon-2/flutter_app/`):**
`lib/features/conversation/domain/models/message_payload.dart`, `lib/features/conversation/domain/models/conversation_message.dart`, `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, `lib/features/conversation/application/send_chat_message_use_case.dart`, `lib/features/conversation/domain/repositories/message_repository.dart`, `lib/features/conversation/domain/repositories/message_repository_impl.dart`, `lib/core/database/helpers/messages_db_helpers.dart`, `lib/core/database/migrations/078_message_dedup_key.dart` (new), `lib/core/database/app_database_version.dart`, `lib/main.dart`, plus the `MessageRepository` fakes (4 real-store + remaining stubs) and new/extended tests under `test/features/conversation/**`, `test/core/database/migrations/078_message_dedup_key_test.dart`, and the `existsByDedupKey` repo/helper unit.
