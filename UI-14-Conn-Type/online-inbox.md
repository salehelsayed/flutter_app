# Reliable Chat Message Delivery Fix

## Context

Messages sent to offline peers are lost. Go's `SendMessage` returns `("", nil)` when ACK read fails — Dart sees `sent=true`, returns early, never reaches inbox fallback. Voice messages also have a duplicate-row bug (missing messageId threading) and hardcode `'delivered'` status.

**Status model after this fix:**
| Status | Meaning | UI | Retried? |
|--------|---------|-----|----------|
| `'sending'` | Optimistic, in-flight | 1 tick, dim | No |
| `'sent'` | Written to stream, no ACK, inbox store pending | 1 tick | Yes (inbox-only) |
| `'queued'` | Stored in relay inbox, awaiting recipient drain | 1 tick | No |
| `'delivered'` | Peer ACK'd the message | 2 ticks | No |
| `'failed'` | All attempts exhausted | Error icon | Yes (full retry) |

---

## Fix 1: Explicit ACK from Go

### `go-mknoon/node/node.go` (~line 478)

Change `SendMessage` signature: `(string, error)` → `(string, bool, error)`:
- ACK received: `return string(replyBytes), true, nil`
- ACK read failed: `return "", false, nil`
- Stream/write error: `return "", false, err`

### `go-mknoon/bridge/bridge.go` (~line 567)

Add `"acked"` field to okJSON response:
```go
reply, acked, err := n.SendMessage(params.PeerId, params.Message)
if err != nil { return errJSON("SEND_ERROR", err.Error()) }
return okJSON(map[string]interface{}{
    "ok": true, "sent": true, "acked": acked, "reply": reply,
})
```

### `lib/features/p2p/domain/models/send_message_result.dart`

Backward-compatible — `acked` is nullable, getter falls back to old inference:
```dart
class SendMessageResult {
  final bool sent;
  final bool? acked;
  final String? reply;
  const SendMessageResult({required this.sent, this.acked, this.reply});
  bool get acknowledged => sent && (acked ?? (reply != null && reply!.isNotEmpty));
}
```
Existing tests that only set `reply` continue to work. New bridge responses set `acked` explicitly.

### `lib/core/services/p2p_service_impl.dart` (~line 406)

Read `response['acked'] as bool?` from bridge response, pass to `SendMessageResult(acked: ...)`.

---

## Fix 2: Persisted wire envelope + inbox safety net + retry

### DB migration 014 — wire_envelope column

**File:** `lib/core/database/migrations/014_wire_envelope_column.dart` (new)
```sql
ALTER TABLE messages ADD COLUMN wire_envelope TEXT
```

**File:** `lib/main.dart` — bump `version: 13` → `14`, add migration call.

**File:** `lib/features/conversation/domain/models/conversation_message.dart` — add `String? wireEnvelope`, update `fromMap`/`toMap`/`copyWith`.

### send_chat_message_use_case.dart — the core fix

**File:** `lib/features/conversation/application/send_chat_message_use_case.dart`

#### Fast path (~line 243) and discover-dial-send (~line 353): when `sent && !acked`

**Guard: skip inbox safety net when `wifiSent == true`** — WiFi delivery already succeeded locally, don't downgrade or enqueue duplicates.

```dart
if (sendResult.sent && !sendResult.acknowledged && !wifiSent) {
  // Try inbox safety net
  try {
    final stored = await p2pService.storeInInbox(targetPeerId, jsonString);
    if (stored) {
      final msg = payload.toConversationMessage(
        contactPeerId: targetPeerId, isIncoming: false,
        status: 'queued', transport: 'inbox',
      );
      await messageRepo.saveMessage(msg);
      // ... persist media, log ...
      return (SendChatMessageResult.success, msg);
    }
  } catch (_) {}
  // Inbox failed — save as 'sent' with wire_envelope for retrier
  final msg = payload.toConversationMessage(
    contactPeerId: targetPeerId, isIncoming: false,
    status: 'sent', transport: 'relay',
    wireEnvelope: jsonString,  // persisted for retry
  );
  await messageRepo.saveMessage(msg);
  // ... persist media, log ...
  return (SendChatMessageResult.success, msg);
}
// Acked path: save as 'delivered' (existing behavior, unchanged)
```

When `wifiSent == true && !acknowledged`: keep current behavior — save as `'sent'` with `transport: 'wifi'`, no inbox safety net. WiFi delivery is already local.

#### Existing inbox fallback (~line 399): when all 3 direct-send retries failed

- storeInInbox succeeds → status `'queued'`, transport `'inbox'` (was `'delivered'`)
- storeInInbox fails → falls through to `'failed'` (unchanged)
- Wire envelope NOT persisted here (inbox already has the message)

### `toConversationMessage` — add wireEnvelope passthrough

**File:** `lib/features/conversation/domain/models/message_payload.dart`

Add optional `String? wireEnvelope` parameter to `toConversationMessage()`.

### DB helper — load unacked messages

**File:** `lib/core/database/helpers/messages_db_helpers.dart`

New `dbLoadUnackedOutgoingMessages(db, {required DateTime olderThan})`:
```sql
WHERE status = 'sent' AND is_incoming = 0
  AND wire_envelope IS NOT NULL
  AND timestamp < ?
ORDER BY timestamp ASC LIMIT 50
```
No max age bound — retry until storeInInbox succeeds. The natural bound is that once queued, the message exits the retry pool. Messages without `wire_envelope` are skipped (nothing to store).

### Repository additions

**File:** `lib/features/conversation/domain/repositories/message_repository.dart` — add `getUnackedOutgoingMessages({required Duration olderThan})`.

**File:** `lib/features/conversation/data/repositories/message_repository_impl.dart` — implement using new DB helper.

### New retry use case — inbox-only, uses persisted wire_envelope

**File:** `lib/features/conversation/application/retry_unacked_messages_use_case.dart` (new)

```dart
Future<int> retryUnackedMessages({
  required MessageRepository messageRepo,
  required P2PService p2pService,
}) async {
  final unacked = await messageRepo.getUnackedOutgoingMessages(
    olderThan: Duration(seconds: 60),
  );
  var count = 0;
  for (final msg in unacked) {
    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId, msg.wireEnvelope!,
      );
      if (stored) {
        await messageRepo.saveMessage(
          msg.copyWith(status: 'queued', wireEnvelope: null),
        );
        count++;
      }
      // Not stored → leave as 'sent', retry on next online transition
    } catch (_) {}
  }
  return count;
}
```

**Properties:**
- Inbox-only → no ghost direct sends, no duplicate risk
- Uses persisted wire_envelope → no re-encrypt, no media-rebuild problem
- `'queued'` stops re-pickup → no duplicate inbox stores / push spam
- No max age → "always eventually" until success
- 60s minimum age → doesn't interfere with in-flight sends
- `wire_envelope IS NOT NULL` in query → only retries messages with stored envelope

### retryFailedMessages — also use wire_envelope when available

**File:** `lib/features/conversation/application/retry_failed_messages_use_case.dart`

In the retry loop, try wire_envelope path first (fixes media-only retry):
```dart
for (final msg in failedMessages) {
  // Prefer wire_envelope → inbox-only (preserves media, no re-encrypt)
  if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty) {
    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId, msg.wireEnvelope!,
      );
      if (stored) {
        await messageRepo.saveMessage(
          msg.copyWith(status: 'queued', wireEnvelope: null),
        );
        successCount++;
        continue;
      }
    } catch (_) {}
  }
  // Fallback: re-encrypt + full send (existing behavior, text-only)
  final (result, _) = await sendChatMessage(...);
  ...
}
```

### PendingMessageRetrier — call both retriers

**File:** `lib/core/services/pending_message_retrier.dart`

In `_retryIfNeeded()`, after `retryFailedMessages()`:
```dart
final unackedCount = await retryUnackedMessages(
  messageRepo: messageRepo,
  p2pService: p2pService,
);
```

**File:** `lib/main.dart` — add `p2pService` to retrier constructor (already has it). No new DI needed.

### Also persist wire_envelope for failed messages

In `send_chat_message_use_case.dart` at the `'failed'` path (~line 457):
```dart
final failedMessage = payload.toConversationMessage(
  contactPeerId: targetPeerId, isIncoming: false,
  status: 'failed',
  wireEnvelope: jsonString,  // enable wire_envelope retry for failed too
);
```

---

## Fix 3: `'queued'` UI rendering

**Goal:** `'queued'` shows single tick (not double), since the peer hasn't confirmed receipt.

### `lib/features/conversation/presentation/widgets/letter_card.dart`

```dart
static IconData _statusIcon(String status) {
  if (status == 'delivered') return Icons.done_all_rounded;
  // Remove: if (status == 'queued') return Icons.done_all_rounded;
  if (status == 'failed') return Icons.error_outline_rounded;
  return Icons.done_rounded;  // 'sent', 'queued', 'sending' all show single tick
}

static Color _statusColor(String status) {
  if (status == 'delivered') return const Color.fromRGBO(255, 255, 255, 0.45);
  // Remove queued case — falls through to default dim color
  if (status == 'failed') return const Color.fromRGBO(255, 100, 100, 0.60);
  return const Color.fromRGBO(255, 255, 255, 0.25);
}

static String _statusSemantic(String status) {
  if (status == 'delivered') return 'delivered';
  if (status == 'queued') return 'queued';  // distinct semantic, not 'delivered'
  if (status == 'failed') return 'failed';
  if (status == 'sending') return 'sending';
  if (status == 'sent') return 'sent';
  return status;
}
```

### `lib/features/feed/presentation/widgets/message_bubble.dart`

Same changes — remove `'queued'` → double-tick mapping. Identical pattern.

---

## Fix 4: Voice message ID threading + status fix

### `lib/features/conversation/application/send_voice_message_use_case.dart`

1. Add `String? messageId` and `String? timestamp` parameters
2. Pass to `sendChatMessage(... messageId: messageId, timestamp: timestamp ...)`
3. Return type: `Future<(SendVoiceMessageResult, ConversationMessage?)>`
4. Capture: `final (result, message) = await sendChatMessage(...)` (was `final (result, _)`)
5. Success: `return (SendVoiceMessageResult.success, message)`; failures: `return (*.failure, null)`

### `lib/features/conversation/presentation/screens/conversation_wired.dart`

Voice send (~line 903):
1. Pass `messageId: optimisticMessage.id, timestamp: optimisticMessage.timestamp`
2. Destructure: `final (result, voiceMessage) = await sendVoiceMessage(...)`
3. Use actual status:
```dart
if (result == SendVoiceMessageResult.success) {
  final actualStatus = voiceMessage?.status ?? 'sent';
  _updateLocalMessageStatus(optimisticMessage.id, actualStatus);
  await _persistMessageStatus(optimisticMessage.id, actualStatus);
}
```

Fixes: duplicate DB rows (same ID → INSERT OR REPLACE), hardcoded `'delivered'` status.

---

## Fix 5: Test updates

### Scope of `'queued'` impact (replaces old `'delivered'` on inbox path only)

**Tests that assert inbox fallback status → change to `'queued'`:**
- `test/features/conversation/application/send_chat_message_use_case_test.dart` — inbox fallback tests
- `test/core/resilience/c2_ack_drop_test.dart` — inbox path assertions
- `test/core/resilience/c3_half_open_test.dart` — inbox path assertions
- `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
- `test/core/inbox/inbox_round_trip_test.dart`
- `test/features/conversation/application/retry_failed_messages_use_case_test.dart` — if exercises inbox path

**NOT affected:** Direct-send-with-ACK tests (still `'delivered'`). Fixture data in load/display tests (historical `'delivered'` is valid).

### `'queued'` UI tests

**File:** `test/features/conversation/presentation/widgets/letter_card_test.dart`
- `'queued'` → single tick (was double tick)
- `'queued'` → dim color (was bright)
- `'queued'` semantic → `'queued'` (was `'delivered'`)

### Voice message tests

**File:** `test/features/conversation/application/send_voice_message_use_case_test.dart`
- All `expect(result, ...)` → destructure: `final (result, message) = ...`
- Add: voice message returns actual status, uses same messageId/timestamp
- Add: no duplicate DB rows

### `SendMessageResult` — no test breakage (backward-compatible)

The nullable `acked` field with fallback getter means existing fakes that set `reply` continue working without changes.

### New tests

- Unacked non-WiFi triggers inbox → `'queued'` / `'sent'` (inbox fail)
- Unacked WiFi does NOT trigger inbox safety net
- Acked send → `'delivered'`, no inbox triggered
- `retryUnackedMessages`: uses wire_envelope, updates `'sent'` → `'queued'`
- `retryUnackedMessages`: skips messages newer than 60s
- `retryUnackedMessages`: skips messages without wire_envelope
- `retryUnackedMessages`: leaves `'sent'` on inbox failure
- `retryFailedMessages`: prefers wire_envelope → inbox when available
- `retryFailedMessages`: falls back to sendChatMessage when no wire_envelope
- DB migration 014: wire_envelope column added, existing messages unaffected

### Fake/mock updates

- Fake message repositories — implement `getUnackedOutgoingMessages()`, add `wireEnvelope` to test helpers
- `test/core/services/fake_p2p_service.dart` — track `storeInInbox` calls

---

## Complete file list

| File | Change | New? |
|------|--------|------|
| `go-mknoon/node/node.go` | `SendMessage` → `(string, bool, error)` | |
| `go-mknoon/bridge/bridge.go` | Add `acked` to response JSON | |
| `lib/features/p2p/domain/models/send_message_result.dart` | Add nullable `acked`, backward-compat getter | |
| `lib/core/services/p2p_service_impl.dart` | Read `acked` from bridge | |
| `lib/core/database/migrations/014_wire_envelope_column.dart` | `ALTER TABLE messages ADD COLUMN wire_envelope TEXT` | Yes |
| `lib/main.dart` | DB version → 14, migration call | |
| `lib/features/conversation/domain/models/conversation_message.dart` | Add `wireEnvelope` field | |
| `lib/features/conversation/domain/models/message_payload.dart` | `toConversationMessage` adds `wireEnvelope` param | |
| `lib/core/database/helpers/messages_db_helpers.dart` | Add `dbLoadUnackedOutgoingMessages` | |
| `lib/features/conversation/domain/repositories/message_repository.dart` | Add `getUnackedOutgoingMessages` | |
| `lib/features/conversation/data/repositories/message_repository_impl.dart` | Implement new method | |
| `lib/features/conversation/application/send_chat_message_use_case.dart` | Unacked → inbox safety net (guard `!wifiSent`), inbox status → `'queued'`, persist `wireEnvelope` for `'sent'`/`'failed'` | |
| `lib/features/conversation/application/retry_unacked_messages_use_case.dart` | Inbox-only retry for `'sent'` via wire_envelope | Yes |
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Prefer wire_envelope → inbox, fallback to sendChatMessage | |
| `lib/core/services/pending_message_retrier.dart` | Call `retryUnackedMessages` after failed retry | |
| `lib/features/conversation/presentation/widgets/letter_card.dart` | `'queued'` → single tick, dim, semantic `'queued'` | |
| `lib/features/feed/presentation/widgets/message_bubble.dart` | Same `'queued'` UI fix | |
| `lib/features/conversation/application/send_voice_message_use_case.dart` | messageId/timestamp params, record return | |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Pass voice messageId, use actual status | |
| Tests (~12 files) | Status assertions, fakes, new tests | |

## Implementation order

1. **Go ACK** — node.go, bridge.go → `make all` → pod install
2. **Flutter ACK model** — send_message_result.dart, p2p_service_impl.dart
3. **DB migration** — 014_wire_envelope_column.dart, main.dart version bump
4. **ConversationMessage model** — add wireEnvelope, update fromMap/toMap/copyWith
5. **message_payload.dart** — toConversationMessage wireEnvelope param
6. **DB helper + repo** — dbLoadUnackedOutgoingMessages, repository interface + impl
7. **send_chat_message_use_case.dart** — unacked→inbox (guard !wifiSent), inbox→'queued', persist wireEnvelope for 'sent'/'failed'
8. **retry_unacked_messages_use_case.dart** (new) — inbox-only retry
9. **retry_failed_messages_use_case.dart** — prefer wire_envelope, fallback sendChatMessage
10. **pending_message_retrier.dart** — call both retriers
11. **UI** — letter_card.dart, message_bubble.dart queued rendering
12. **Voice fix** — send_voice_message_use_case.dart, conversation_wired.dart
13. **Tests** — all updates
14. **Verify** — `flutter test`, manual testing

## Verification

1. `cd go-mknoon && make all && cd ../ios && pod install`
2. `flutter test` — all pass
3. **Offline delivery:** Send text + voice to offline peer → both show 1 tick. Bring recipient online → messages drain via inbox within 30s.
4. **Online delivery:** Send to online peer → both show 2 ticks. No inbox store triggered.
5. **WiFi delivery:** Send to local WiFi peer who then disconnects → message shows 1 tick via WiFi, no inbox downgrade.
6. **App kill:** Send to offline peer, kill sender app before inbox completes → message saved as `'sent'` with `wire_envelope` → relaunch → retrier stores in inbox → status → `'queued'`.
7. **Failed media retry:** Voice message fails → saved as `'failed'` with `wire_envelope` → retrier uses wire_envelope → inbox → `'queued'`. No media-rebuild needed.
8. **Dedup:** Verify no duplicate messages when message arrives via direct + inbox.
9. **No re-queue spam:** Once `'queued'`, message is not retried again.






3 Attempts

  ┌─────────────────────┬──────────┬───────────────────┐
  │        Step         │ Duration │    Timestamps     │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Optimistic DB save  │ ~91ms    │ 14.282 → 14.373   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Contact lookup      │ ~1ms     │ 14.374 → 14.374   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ ML-KEM encrypt      │ ~2ms     │ 14.377 → 14.378   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 1: discover │ ~951ms   │ 14.379 → 15.330   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 1: dial     │ ~10s     │ 15.331 → 25.335   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 1 total     │ 10,956ms │ durationMs: 10956 │
  ├─────────────────────┼──────────┼───────────────────┤
  │ backoff sleep       │ ~502ms   │ 25.335 → 25.837   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 2: discover │ ~48ms    │ 25.838 → 25.886   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 2: dial     │ ~5.1s    │ 25.887 → 30.980   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 2 total     │ 5,143ms  │ durationMs: 5143  │
  ├─────────────────────┼──────────┼───────────────────┤
  │ backoff sleep       │ ~1s      │ 30.981 → 31.982   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 3: discover │ ~48ms    │ 31.982 → 32.030   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 3: dial     │ ~5.1s    │ 32.031 → 37.083   │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Attempt 3 total     │ 5,101ms  │ durationMs: 5101  │
  ├─────────────────────┼──────────┼───────────────────┤
  │ Inbox store         │ 1,441ms  │ durationMs: 1441  │
  ├─────────────────────┼──────────┼───────────────────┤
  │ DB save (queued)    │ ~2ms     │ 38.522 → 38.524   │
  └─────────────────────┴──────────┴───────────────────┘

first lets reduce attempts to 1. create a detailed plan to do this change

DialPeer wraps the call with context.WithTimeout(n.ctx, DialTimeout) — so the 15s context deadline is what governs how long it waits for all addresses to fail. The ~10s you saw in the logs is the dial giving up before the full 15s because all addresses had already errored or timed out at the TCP/QUIC level.






  So we're already in the "probably offline" territory. The relay NO_RESERVATION check would slot in right at the top of step
   5, before any dial attempts:

  1. Ask relay: does this peer have a reservation?
  2. NO_RESERVATION → skip dial loop entirely, go straight to inbox
  3. Reservation exists → peer is online somewhere, proceed with discover/dial (1 attempt, lower timeout)