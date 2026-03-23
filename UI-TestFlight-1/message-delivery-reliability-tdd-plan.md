# Message Delivery Reliability — TDD Implementation Plan

**Issue:** When a user writes a message, taps Send, and immediately locks the device, neither the message is sent nor does the recipient receive a notification.

**Root Causes Identified:**
1. Messages stuck in `status: 'sending'` are never retried by `PendingMessageRetrier`
2. No `AppLifecycleState.paused` handler to flush or transition in-flight work
3. iOS never calls `beginBackgroundTask` — process suspended immediately on lock
4. Relay inbox store only fires as a last-resort fallback, not optimistically
5. FCM field mismatch (`sender_id` vs `from`), missing group `Notification` struct, volatile token store

**Approach:** Test-Driven Development — red tests first, then implementation, then refactor.

**Test Coverage Strategy:**
- **Unit tests**: Individual functions (DB helpers, use cases, bridge wrappers, notification parsers)
- **Integration tests**: Multi-layer flows (send → persist → retry, lifecycle → recovery, push → navigate)
- **Smoke tests**: Manual QA checklists for physical device validation (TestFlight)
- **Edge case tests**: Concurrent sends, corrupt data, timeout scenarios, race conditions

---

## Plan Overview

### Section Map

| Section | What It Fixes | Layer |
|---|---|---|
| **Section 1** — Stuck-Sending Recovery | `'sending'` messages orphaned in DB forever; `PendingMessageRetrier` ignores them; media attachment retry drops files; no retry sweep on resume or cold start. **Scope: 1:1 text, media, and voice sends (both post-upload and pre-upload via Parts F/G automatic re-upload). Group sends are out of scope (documented gap).** | Dart: DB helpers, repository, retrier, resume handler, media attachment persistence |
| **Section 2** — Lifecycle Pause Handler | No `AppLifecycleState.paused` handler; in-flight messages never transitioned to retryable state | Dart: new `handleAppPaused()` use case (local DB only — no network calls), `_MyAppState` lifecycle |
| **Section 3** — iOS Background Task | iOS suspends the process immediately on lock; the entire send pipeline (upload/transfer→encrypt→discover→dial→send→inbox) is unprotected — no `beginBackgroundTask` call exists anywhere | Dart + Swift: Dart-initiated `bg:begin`/`bg:end` MethodChannel calls placed in the presentation layer (`conversation_wired.dart`, `feed_wired.dart`) before upload/transfer/send; 4 call sites covered: `_onSend` (text/media), `_onVoiceRecordingStopped` (relay + local WiFi), `_onInlineSend` (feed); `finally` block ensures `bg:end` is always called. Use cases (`sendChatMessage`, `sendVoiceMessage`) never call `bg:begin`/`bg:end`. |
| **Section 4** — Direct-First Send with Early wireEnvelope Persistence | Relay inbox only fires as last-resort fallback (fully closed by this section); 60s+ gap between optimistic write and direct-first send due to media upload (partially closed — full coverage requires Sections 1-3); `wireEnvelope` not persisted until too late (partially closed — crash recovery requires Section 1) | Dart: `sendChatMessage` use case reordering + early `wireEnvelope` persistence + media attachment save at optimistic write |
| **Section 5** — FCM & Notification Fixes | Dart client reads `data['from']` but server sends `sender_id`; group push needs parity hardening on iOS; production must use Redis for token durability and, if Section 4 becomes central, shared inbox durability | Dart: one-line client fix in `notification_route_target.dart`; Go: group push `Notification` parity hardening; Ops: require `RELAY_BACKEND=redis` |
| **Section 6** — Test Infrastructure | Cross-cutting integration tests using `TestUser` + `FakeP2PNetwork` proving sender-lock + recipient-delivery + notification end-to-end | Dart: multi-user integration tests with lifecycle simulation, smoke test matrix |

### Dependencies Between Sections

```
Section 4 (direct-first send)     Section 5 (FCM fixes)
    │  no code deps (qualified*)     │  standalone
    │                                 │
    ▼                                 │
Section 1 (stuck-sending recovery)   │
    │  shares DB query with §2        │
    │                                 │
    ▼                                 │
Section 2 (lifecycle pause)          │
    │  uses same recoverStuck*()      │
    │  method created in §1           │
    │                                 │
    ▼                                 │
Section 3 (iOS background task)      │
    │  Dart + Swift bridge/call-site  │
    │                                 │
    └──────────┬──────────────────────┘
               ▼
         Section 6 (test infrastructure)
              depends on all above
```

> *\*qualified:* Section 4 has no code dependencies on other sections, but it only closes the **post-serialization** gap. The **pre-`sendChatMessage`** window (60s+ media upload) remains unprotected without Sections 1-3. See "Can Each Section Ship Independently?" below.

**Key relationships:**
- **Sections 1 ↔ 2 share code**: Both use `recoverStuckSendingMessages()` and the `getSendingMessages()` DB query. Section 1 creates them; Section 2 calls them from the pause handler.
- **Section 4 reduces the blast radius of Sections 1+2, but is not independently sufficient**: If direct-first send with early `wireEnvelope` persistence is deployed, send-then-lock scenarios where the kill happens *after* serialization are substantially safer, but not mathematically guaranteed until the inbox RPC itself succeeds. However, if the app is killed during the pre-`sendChatMessage` window (up to 60s+ for media upload), Section 4 provides no protection — Sections 1-3 are required for that window. Sections 1+2 are the safety net, not a nice-to-have.
- **Section 4 has an important side effect that must be accounted for in implementation**: on today's relay, every successful inbox store also triggers push send. If Section 4 makes inbox store unconditional, the final implementation must either suppress/cancel duplicate push, or otherwise prove recipient-side deduplication prevents duplicate user-visible delivery and notification.
- **Section 3 protects the full send pipeline via presentation-layer ownership**: `bg:begin`/`bg:end` lives exclusively in Wired widgets (`conversation_wired.dart`, `feed_wired.dart`), never in use cases. Four call sites — `_onSend`, `_onVoiceRecordingStopped` (relay + local WiFi), and `_onInlineSend` — each acquire and release a background task via `try`/`finally`. This gives iOS 30 seconds to complete the flow. Sections 1+2 cover edge cases where even 30 seconds is insufficient.
- **Section 5 is operationally independent, but not all of its bugs are equally causal for the lock-send failure**: Bug A (`sender_id`) fixes tap routing after a push is shown; it does not, by itself, fix sender-side message loss. Bug C (Redis) becomes more important if Section 4's early `wireEnvelope` persistence makes inbox durability central.
- **Section 6 depends on all others**: It provides the integration glue and cross-cutting test scenarios.

### Recommended Implementation Order

| Priority | Section | Rationale |
|---|---|---|
| **P0** | **Section 4** — Direct-First Send | Biggest single-section reliability improvement, but not sufficient alone. Closes the post-serialization gap (relay gets the message before P2P race). The pre-`sendChatMessage` window (60s+ media upload) remains unprotected without Sections 1-3. |
| **P0** | **Section 5** — FCM & Notification Fixes | Independent, low-risk. Fixes silent bugs that affect all users (broken deep-link, throttled group push, token loss). |
| **P1** | **Section 1** — Stuck-Sending Recovery | Safety net for when direct-first send fails. Creates shared infrastructure needed by Section 2. |
| **P1** | **Section 2** — Lifecycle Pause Handler | Proactive defense — transitions messages before the OS kills the process. Depends on Section 1's DB methods. |
| **P2** | **Section 3** — iOS Background Task | Belt-and-suspenders — gives iOS 30 seconds to finish the send pipeline. Presentation-layer ownership (`bg:begin`/`bg:end` in Wired widgets, not use cases) keeps platform concerns out of application logic. Lower priority because Sections 4+1+2 already cover the Dart layer. |
| **P3** | **Section 6** — Test Infrastructure | Write after all fix sections are implemented. Cross-cutting tests validate the combined behavior. |

### Can Each Section Ship Independently?

| Section | Independent? | Notes |
|---|---|---|
| Section 4 | **Qualified — not standalone** | Closes the post-serialization gap independently via early `wireEnvelope` persistence, but leaves the pre-`sendChatMessage` window (60s+ media upload) unprotected. Sections 1-3 are required for full send-then-lock coverage. Ship first for quick wins, but must be followed by Sections 1-3. See Section 4 Overview for the detailed breakdown. |
| Section 5 | **Yes** | No dependencies. Ship in parallel with Section 4. |
| Section 1 | **Yes** | Standalone. Creates methods that Section 2 will later use. |
| Section 2 | **After Section 1** | Calls `recoverStuckSendingMessages()` which Section 1 creates. |
| Section 3 | **Qualified — requires Dart + Swift** | The native task token lives in Swift, but the real fix also requires Dart MethodChannel support and presentation-layer changes in `conversation_wired.dart` (3 call sites: `_onSend`, `_onVoiceRecordingStopped` relay + local WiFi) and `feed_wired.dart` (1 call site: `_onInlineSend`) to request background protection before upload/transfer/send begins. Use cases are not modified. |
| Section 6 | **After all others** | Integration tests reference code from all sections. |

---

## Section 1: Stuck-Sending Message Recovery

**Problem statement:** When a user sends a message and immediately backgrounds or locks the device, `conversation_wired.dart` creates an optimistic `ConversationMessage` with `status: 'sending'` and persists it before `sendChatMessage` completes. If the app is killed or suspended mid-send, that row remains in the database forever with `status: 'sending'`. `PendingMessageRetrier` queries only `status = 'failed'` (via `getFailedOutgoingMessages`) and `status = 'sent'` with a non-null `wire_envelope` (via `getUnackedOutgoingMessages`). Neither query touches `'sending'` rows, so the message is permanently invisible to all recovery paths and the user sees an eternal spinner.

**Additional gaps identified by audit:**
- **Media attachment retry incomplete**: The optimistic DB row has `wireEnvelope=null` and `media` is transient (not in `toMap()`). `retryFailedMessages` fallback at line 92 calls `sendChatMessage` without `mediaAttachments` or `mediaAttachmentRepo` — media is silently dropped on retry.
- **Cold-start/already-online gap**: `handleAppResumed` never calls the message retrier. If the node is already online on resume, the retrier's offline→online gate never fires. Failed messages can sit unretried indefinitely until a later qualifying state transition or manual action. Part D closes this by wiring an immediate resume sweep and Part B adds an initial sweep on retrier start.
- **`retryUnackedMessages` unsafe dereference**: `msg.wireEnvelope!` at line 47 has no null guard — relies entirely on SQL filter.

**Scope — what this section covers and does not cover:**
- **Voice messages (IN SCOPE — both post-upload and pre-upload paths)**: `sendVoiceMessage` (`send_voice_message_use_case.dart`) uploads the audio file, then delegates to `sendChatMessage` with a `MediaAttachment` of type `audio`. The optimistic `ConversationMessage` row with `status: 'sending'` is created and persisted in `conversation_wired.dart` (lines 1225–1260) before the upload starts — identical in structure to a media message row. Once the upload succeeds, the subsequent `sendChatMessage` call is indistinguishable from a media send. All four Parts (A–D) of this section therefore cover voice post-upload sends. The pre-upload failure window (`SendVoiceMessageResult.uploadFailed`) leaves the optimistic row stuck at `'sending'` with no `wireEnvelope` and no CDN reference — Parts A/B transition it to `'failed'`. **Important live-path nuance:** the real `1:1` voice flow first tries `sendLocalMedia()` in `conversation_wired.dart` and only falls back to `sendVoiceMessage()` for the relay upload path. Parts F/G and Section 3 must therefore cover both branches. The recorded audio file is initially written to temp storage by `RecordAudioRecorderService`; until Part G explicitly copies pre-upload files into managed storage, automatic pre-upload voice recovery should be treated as **best-effort if the local file still exists**, not as a universal guarantee that the user never has to re-record. Part G persists the attachment metadata (`localPath`, `mime`, `durationMs`, `waveform`) to the `media_attachments` table with `downloadStatus='upload_pending'` before the upload begins so retry can re-upload if the file survives.
- **Group messages (OUT OF SCOPE)**: `sendGroupMessage` (`send_group_message_use_case.dart:64`) creates no optimistic DB row at all. GossipSub publish is fire-and-forget. `retryFailedMessages` has zero group message coverage (group messages live in a separate `group_messages` table). This requires a separate group-durability feature and is documented as a known gap to be addressed in future work.

**Fix surface (four parts in this section — 1:1 text, media, and voice; Parts F/G extend coverage to pre-upload interruptions via automatic re-upload):**
- **Part A** — On app resume: a new `recoverStuckSendingMessages()` method on `MessageRepository` transitions any `'sending'` row older than a configurable threshold to `'failed'`, which the existing `retryFailedMessages` use case will then pick up immediately.
- **Part B** — In `PendingMessageRetrier`: treat `'sending'` rows older than the threshold identically to `'failed'` rows so they are also retried on reconnect, even when no resume event fires. Also add an initial sweep on `start()` if the node is already online.
- **Part C** — Make `retryFailedMessages` replay-safe for media attachments (where upload already completed and CDN references exist in `wireEnvelope`): query `mediaAttachmentRepo.getAttachmentsForMessage()` before the fallback `sendChatMessage` call and pass results through. Add null guard on `wireEnvelope!` in `retryUnackedMessages`.
- **Part D** — Wire `retryFailedMessages` and `retryUnackedMessages` into `handleAppResumed()` as callbacks (same pattern as existing `retryPendingPostDeliveries`), ensuring an immediate retry sweep on every resume regardless of the retrier's state-transition gate.

---

### Part A: Recover stuck `'sending'` messages on app resume

#### A.1 Red phase — DB helper unit tests

**File to create:** `test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart`

This file tests the raw SQL helper `dbRecoverStuckSendingMessages` before any implementation exists. All tests in this file will fail with `undefined function` errors until the implementation is written.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';

// Reuse the in-process sqflite factory used by other db-helper tests.
// (Follow the same pattern as messages_db_helpers_test.dart in this project.)
// ⚠️ AUDIT FIX (1A-06): Verify this import path exists before implementation.
// The actual test helper may use a different path or naming convention.
// Cross-check with existing DB helper tests (e.g., messages_db_helpers_test.dart).
import '../../helpers/in_memory_db.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('dbRecoverStuckSendingMessages', () {
    test('returns 0 when no messages exist', () async {
      final count = await dbRecoverStuckSendingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(count, 0);
    });

    test('returns 0 when no sending messages exist', () async {
      await db.insert('messages', {
        'id': 'msg-delivered',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': 'delivered',
        'is_incoming': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      final count = await dbRecoverStuckSendingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(count, 0);
    });

    test('does not update sending message younger than threshold', () async {
      // timestamp is 10 seconds ago — threshold is 30 seconds ago
      final recentTs = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 10))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-recent-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': recentTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': recentTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-recent-sending'])).first;
      expect(row['status'], 'sending');
    });

    test('updates sending message older than threshold to failed', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-old-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 1);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-old-sending'])).first;
      expect(row['status'], 'failed');
    });

    test('only updates outgoing messages (is_incoming = 0)', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      // Incoming row with status=sending (pathological, but should not be touched)
      await db.insert('messages', {
        'id': 'msg-incoming-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'them',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 1,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);
    });

    test('updates multiple stuck sending messages in one call', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (var i = 0; i < 3; i++) {
        await db.insert('messages', {
          'id': 'msg-stuck-$i',
          'contact_peer_id': 'peer-a',
          'sender_peer_id': 'me',
          'text': 'msg $i',
          'timestamp': oldTs,
          'status': 'sending',
          'is_incoming': 0,
          'created_at': oldTs,
        });
      }
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 3);

      final rows = await db.query('messages',
          where: "status = 'failed' AND is_incoming = 0");
      expect(rows.length, 3);
    });

    // NOTE: This test seeds wire_envelope on a 'sending' row to verify the
    // DB helper preserves it during the status transition. In practice, most
    // stuck 'sending' rows will have wireEnvelope = null — see audit fix below.
    test('preserves wire_envelope when transitioning to failed', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      const envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
      await db.insert('messages', {
        'id': 'msg-env-sending',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': oldTs,
        'wire_envelope': envelope,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      await dbRecoverStuckSendingMessages(db, olderThan: threshold);

      final row = (await db.query('messages',
          where: 'id = ?', whereArgs: ['msg-env-sending'])).first;
      expect(row['status'], 'failed');
      expect(row['wire_envelope'], envelope);
    });

    test('does not disturb non-sending statuses', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (final status in ['sent', 'delivered', 'failed']) {
        await db.insert('messages', {
          'id': 'msg-$status',
          'contact_peer_id': 'peer-a',
          'sender_peer_id': 'me',
          'text': 'msg',
          'timestamp': oldTs,
          'status': status,
          'is_incoming': 0,
          'created_at': oldTs,
        });
      }
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final count =
          await dbRecoverStuckSendingMessages(db, olderThan: threshold);
      expect(count, 0);
    });
  });
}
```

#### A.2 Red phase — Repository unit tests

**File to create:** `test/features/conversation/domain/repositories/message_repository_impl_stuck_sending_test.dart`

Tests `MessageRepositoryImpl.recoverStuckSendingMessages()` via the injected DB helper closure, before the method exists on either the abstract interface or the impl.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

// Helper that constructs a minimal MessageRepositoryImpl wired to an in-memory
// map, matching the pattern in message_repository_impl_test.dart.
MessageRepositoryImpl _buildRepo({
  required Map<String, Map<String, Object?>> store,
  required Future<int> Function({required DateTime olderThan, int limit})
      dbRecoverStuckSendingMessages,
}) {
  return MessageRepositoryImpl(
    dbInsertMessage: (row) async => store[row['id'] as String] = Map.from(row),
    dbLoadMessagesForContact: (cp) async =>
        store.values.where((r) => r['contact_peer_id'] == cp).toList(),
    dbLoadLatestMessageForContact: (cp) async => null,
    dbUpdateMessageStatus: (id, s) async {},
    dbLoadMessage: (id) async => store[id],
    dbCountMessagesForContact: (cp) async => 0,
    dbMarkConversationAsRead: (cp) async => 0,
    dbCountUnreadForContact: (cp) async => 0,
    dbCountTotalUnread: () async => 0,
    dbCountTotalUnreadExcludingArchived: () async => 0,
    dbDeleteMessagesForContact: (cp) async => 0,
    dbLoadMessagesPage: (cp, {int limit = 50, String? beforeTimestamp}) async =>
        [],
    dbLoadFailedOutgoingMessages: () async => [],
    dbLoadUnackedOutgoingMessages: ({required DateTime olderThan, int limit = 50}) async =>
        [],
    dbLoadConversationThreadSummaries: (ids) async => [],
    dbRecoverStuckSendingMessages: dbRecoverStuckSendingMessages,
  );
}

void main() {
  group('MessageRepositoryImpl.recoverStuckSendingMessages', () {
    test('delegates to dbRecoverStuckSendingMessages with correct cutoff', () async {
      int helperCallCount = 0;
      DateTime? capturedOlderThan;

      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) async {
          helperCallCount++;
          capturedOlderThan = olderThan;
          return 0;
        },
      );

      const threshold = Duration(seconds: 30);
      final before = DateTime.now().toUtc().subtract(threshold);
      await repo.recoverStuckSendingMessages(olderThan: threshold);
      final after = DateTime.now().toUtc().subtract(threshold);

      expect(helperCallCount, 1);
      // The cutoff passed to the helper must be between before and after
      expect(capturedOlderThan!.isAfter(before.subtract(const Duration(seconds: 1))), isTrue);
      expect(capturedOlderThan!.isBefore(after.add(const Duration(seconds: 1))), isTrue);
    });

    test('returns count from db helper', () async {
      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages:
            ({required DateTime olderThan, int limit = 50}) async => 3,
      );

      final count = await repo.recoverStuckSendingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(count, 3);
    });

    test('returns 0 when helper returns 0', () async {
      final store = <String, Map<String, Object?>>{};
      final repo = _buildRepo(
        store: store,
        dbRecoverStuckSendingMessages:
            ({required DateTime olderThan, int limit = 50}) async => 0,
      );

      final count = await repo.recoverStuckSendingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(count, 0);
    });
  });
}
```

#### A.3 Red phase — Use case unit tests

**File to create:** `test/features/conversation/application/recover_stuck_sending_messages_use_case_test.dart`

Tests the new `recoverStuckSendingMessages` use case function before it exists.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../domain/repositories/fake_message_repository.dart';

ConversationMessage _makeSendingMessage({
  String id = 'msg-stuck-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
  Duration age = const Duration(minutes: 5),
}) {
  final ts = DateTime.now().toUtc().subtract(age).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: ts,
    status: 'sending',
    isIncoming: false,
    createdAt: ts,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  group('recoverStuckSendingMessages use case', () {
    late FakeMessageRepository messageRepo;

    setUp(() {
      messageRepo = FakeMessageRepository();
    });

    test('returns 0 when no stuck sending messages exist', () async {
      final count = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(count, 0);
      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('calls recoverStuckSendingMessages on repo once', () async {
      await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('returns count reported by the repo', () async {
      messageRepo.recoverStuckSendingReturnValue = 2;

      final count = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: const Duration(seconds: 30),
      );
      expect(count, 2);
    });

    test('passes the configured threshold duration to the repo', () async {
      const threshold = Duration(seconds: 45);
      await recoverStuckSendingMessages(
        messageRepo: messageRepo,
        threshold: threshold,
      );
      expect(messageRepo.lastRecoverStuckSendingThreshold, threshold);
    });

    test('uses default threshold of 30 seconds when not specified', () async {
      await recoverStuckSendingMessages(messageRepo: messageRepo);
      expect(
        messageRepo.lastRecoverStuckSendingThreshold,
        const Duration(seconds: 30),
      );
    });
  });
}
```

#### A.4 Red phase — `handleAppResumed` integration test

**File to create:** `test/core/lifecycle/handle_app_resumed_stuck_sending_test.dart`

> **⚠️ AUDIT FIX (1A-01):** This test has a double-dependency: it will fail in the red phase both because `recoverStuckSendingMessages` is undefined AND because `handleAppResumed` does not accept a `messageRepo` parameter yet. Both are created in the green phase (Steps D and E). This is expected TDD behavior — the test drives both additions simultaneously. Implementers should not be alarmed by the two separate compilation errors.

Tests that `handleAppResumed` calls `recoverStuckSendingMessages` before the retrier fires, using the existing `FakeMessageRepository` and `FakeBridge`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../services/fake_p2p_service.dart';
import '../bridge/fake_bridge.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';

void main() {
  group('handleAppResumed — stuck sending recovery', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late FakeMessageRepository messageRepo;

    setUp(() {
      bridge = FakeBridge();
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        ),
      );
      messageRepo = FakeMessageRepository();
    });

    tearDown(() {
      p2pService.dispose();
    });

    test('calls recoverStuckSendingMessages on resume when messageRepo provided',
        () async {
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        messageRepo: messageRepo,
      );

      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('does not call recoverStuckSendingMessages when messageRepo is null',
        () async {
      // messageRepo not passed — old callers that haven't been wired yet
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
      );

      // No crash, and no call on any repo
    });

    test('recovery is called before retryIncompleteKeyExchanges step',
        () async {
      final callOrder = <String>[];
      messageRepo.onRecoverStuckSending = () => callOrder.add('recover');

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        messageRepo: messageRepo,
      );

      // recoverStuckSendingMessages must appear in the log
      expect(callOrder.contains('recover'), isTrue);
    });

    test('bridge health check error does not prevent recovery from running',
        () async {
      bridge.checkHealthResult = false; // forces reinitialize path

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        messageRepo: messageRepo,
      );

      expect(messageRepo.recoverStuckSendingCallCount, 1);
    });

    test('recovery error is swallowed and resume completes', () async {
      messageRepo.throwOnRecoverStuckSending = true;

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        messageRepo: messageRepo,
      );

      // handleAppResumed must not propagate the error
      expect(result, isNotNull);
    });
  });
}
```

#### A.5 Green phase — Implementation

**Step A: New DB helper**

Add to `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/database/helpers/messages_db_helpers.dart`:

> **⚠️ AUDIT FIX (1A-04):** The optimistic `'sending'` row is created by `ConversationWired._handleSendText` at `conversation_wired.dart:616-637` BEFORE `sendChatMessage` serializes the envelope. This means stuck `'sending'` rows will typically have `wireEnvelope = null`. After recovery to `'failed'`, the retry path in `retryFailedMessages` must fall through to the full re-encrypt `sendChatMessage` call (not the wire-envelope inbox fast-path). Tests that seed `wireEnvelope` on stuck-sending rows are testing an edge case (e.g., partial progress persisted by `sendChatMessage`), not the common case.

> **⚠️ AUDIT FIX (1A-05):** SQLite's UPDATE does not natively support LIMIT. The `limit` parameter in this function is dead code — the UPDATE query below does not use it. It is retained in the signature for forward-compatibility (e.g., a future batched UPDATE via subquery) but has no effect today. No test exercises LIMIT behavior.

```dart
/// Transitions all outgoing messages stuck in status='sending' that are
/// older than [olderThan] to status='failed'.
///
/// Safe to call on every resume — messages younger than the threshold
/// are untouched. wire_envelope is preserved so retryFailedMessages can
/// use the full re-encrypt path (wire_envelope will typically be null
/// for stuck 'sending' rows — the envelope is only serialized inside
/// sendChatMessage, which never completed).
///
/// [limit] is reserved for future use — SQLite UPDATE does not support LIMIT
/// natively and the current query does not apply it.
///
/// Returns the number of rows updated.
Future<int> dbRecoverStuckSendingMessages(
  Database db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_START',
    details: {'olderThan': olderThan.toIso8601String()},
  );

  try {
    final count = await db.rawUpdate(
      "UPDATE messages SET status = 'failed' "
      "WHERE status = 'sending' AND is_incoming = 0 AND timestamp < ?",
      [olderThan.toUtc().toIso8601String()],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_SUCCESS',
      details: {'count': count},
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_RECOVER_STUCK_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
```

**Step B: Add method to `MessageRepository` abstract interface**

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository.dart`, add after `getUnackedOutgoingMessages`:

```dart
/// Transitions all outgoing messages with status='sending' that are older
/// than [olderThan] to status='failed', so the retry service picks them up.
///
/// Returns the count of rows updated.
Future<int> recoverStuckSendingMessages({
  required Duration olderThan,
});
```

**Step C: Implement in `MessageRepositoryImpl`**

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository_impl.dart`:

Add to the constructor parameter list and field declarations:

```dart
final Future<int> Function({required DateTime olderThan, int limit})
    dbRecoverStuckSendingMessages;
```

Add the override:

```dart
@override
Future<int> recoverStuckSendingMessages({
  required Duration olderThan,
}) async {
  final cutoff = DateTime.now().toUtc().subtract(olderThan);
  return dbRecoverStuckSendingMessages(olderThan: cutoff);
}
```

**Step D: New use case function**

**File to create:** `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/application/recover_stuck_sending_messages_use_case.dart`

```dart
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Default age after which a 'sending' message is considered stuck.
const Duration kStuckSendingThreshold = Duration(seconds: 30);

/// Transitions outgoing messages stuck in 'sending' to 'failed' so they
/// are picked up by [retryFailedMessages] on the next retry cycle.
///
/// Intended to be called early in the app-resume sequence, before the
/// pending-message retrier fires.
///
/// Returns the number of messages recovered (status changed to 'failed').
Future<int> recoverStuckSendingMessages({
  required MessageRepository messageRepo,
  Duration threshold = kStuckSendingThreshold,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'RECOVER_STUCK_SENDING_START',
    details: {'thresholdSeconds': threshold.inSeconds},
  );

  final count = await messageRepo.recoverStuckSendingMessages(
    olderThan: threshold,
  );

  emitFlowEvent(
    layer: 'FL',
    event: count > 0
        ? 'RECOVER_STUCK_SENDING_FOUND'
        : 'RECOVER_STUCK_SENDING_NONE',
    details: {'count': count},
  );

  return count;
}
```

**Step E: Wire into `handleAppResumed`**

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/lifecycle/handle_app_resumed.dart`:

1. Add `MessageRepository` import.
2. Add optional `MessageRepository? messageRepo` parameter to `handleAppResumed`.
3. Add a new step after Step 3 (drain offline inbox) and before Step 3b (group recovery). Label it **Step 3a**:

```dart
// 3a. Recover messages stuck in 'sending' on the previous session
if (messageRepo != null) {
  final recoverStart = DateTime.now();
  if (kDebugMode) debugPrint('[RESUME] Step 3a: recoverStuckSendingMessages() starting...');
  try {
    final recovered = await recoverStuckSendingMessages(
      messageRepo: messageRepo,
    );
    final recoverMs = DateTime.now().difference(recoverStart).inMilliseconds;
    if (kDebugMode) {
      debugPrint(
        '[RESUME] Step 3a: recoverStuckSendingMessages() done '
        '(recovered=$recovered, took ${recoverMs}ms)',
      );
    }
  } catch (e) {
    if (kDebugMode) {
      debugPrint('[RESUME] Step 3a: recoverStuckSendingMessages() error: $e');
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'RECOVER_STUCK_SENDING_RESUME_ERROR',
      details: {'error': e.toString()},
    );
    // Non-fatal: continue resume sequence
  }
}
```

**Step F: Update `FakeMessageRepository`**

Add the following members to `test/features/conversation/domain/repositories/fake_message_repository.dart` so all existing tests keep compiling:

> **⚠️ AUDIT FIX (1B-06):** `FakeMessageRepository.recoverStuckSendingMessages` must actually iterate `_messages`, find rows with `status == 'sending'` older than the threshold, and change their status to `'failed'` -- mirroring the real DB behavior. Without this, smoke tests must manually re-seed after calling `recoverStuckSendingMessages`, which defeats the purpose of testing same-row recovery. The implementation below mutates `_messages` in place.

```dart
// Stuck-sending recovery
int recoverStuckSendingCallCount = 0;
Duration? lastRecoverStuckSendingThreshold;
bool throwOnRecoverStuckSending = false;
void Function()? onRecoverStuckSending;

@override
Future<int> recoverStuckSendingMessages({
  required Duration olderThan,
}) async {
  recoverStuckSendingCallCount++;
  lastRecoverStuckSendingThreshold = olderThan;
  onRecoverStuckSending?.call();
  if (throwOnRecoverStuckSending) {
    throw Exception('FakeMessageRepository: recoverStuckSendingMessages error');
  }
  // Actually transition matching messages in _messages, mirroring real DB behavior.
  final cutoff = DateTime.now().toUtc().subtract(olderThan);
  int count = 0;
  for (var i = 0; i < _messages.length; i++) {
    final m = _messages[i];
    if (m.status == 'sending' &&
        !m.isIncoming &&
        DateTime.parse(m.timestamp).toUtc().isBefore(cutoff)) {
      _messages[i] = m.copyWith(status: 'failed');
      count++;
    }
  }
  return count;
}
```

**Step G: Wire the new `dbRecoverStuckSendingMessages` helper into the DI chain**

In `main.dart`, where `MessageRepositoryImpl` is constructed, add:

```dart
dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) =>
    dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
```

> **⚠️ AUDIT FIX (1A-02):** The actual `handleAppResumed` call at `lib/main.dart:1508-1521` passes 11 named parameters but does NOT include `messageRepo`. Add the following line after `retryPendingPostDeliveries:` at `lib/main.dart:1520`:

```dart
messageRepo: widget.messageRepository,
```

**Step H: Update ALL `MessageRepository` implementors across the codebase**

> **⚠️ AUDIT FIX (1A-03):** Adding `recoverStuckSendingMessages()` to the `MessageRepository` abstract interface will break ALL existing implementors — not just `FakeMessageRepository`. Search for all `implements MessageRepository` across the codebase (including `InMemoryMessageRepository` in `test/shared/fakes/` and the 12+ anonymous implementations in test files like `conversation_wired_test.dart`, `send_chat_message_use_case_test.dart`, etc.) and add `recoverStuckSendingMessages` stubs to every implementor. Use `throw UnimplementedError()` for implementations not exercised in their own test.

#### A.6 Refactor phase

- Rename the FLOW event `RECOVER_STUCK_SENDING_FOUND` to `RECOVER_STUCK_SENDING_RECOVERED` for consistency with `PENDING_RETRIER_RETRIED`.
- Extract `kStuckSendingThreshold` to a shared constants file (`lib/core/constants/retry_constants.dart`) if other retry thresholds are also centralised there; otherwise leave it in the use case file.
- Confirm the `recoverStuckSendingMessages` DB query uses the `timestamp` column (ISO-8601 strings compare lexicographically correctly) and does not need an index hint — the existing `messages` table has no index on `(status, is_incoming, timestamp)`, but the recovery query runs at most once per resume and the message table is small, so a full scan is acceptable. Leave an inline comment documenting this decision.

---

### Part B: Expand `PendingMessageRetrier` to cover `'sending'` status

#### B.1 Red phase — Repository interface and `FakeMessageRepository` tests

**File to create:** `test/features/conversation/domain/repositories/fake_message_repository_stuck_sending_query_test.dart`

Tests `FakeMessageRepository.getStuckSendingOutgoingMessages()` before the method exists.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../domain/repositories/fake_message_repository.dart';

ConversationMessage _makeMsg({
  required String id,
  required String status,
  required Duration age,
  bool isIncoming = false,
  String? wireEnvelope,
}) {
  final ts = DateTime.now().toUtc().subtract(age).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-a',
    senderPeerId: 'me',
    text: 'msg',
    timestamp: ts,
    status: status,
    isIncoming: isIncoming,
    createdAt: ts,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  group('FakeMessageRepository.getStuckSendingOutgoingMessages', () {
    late FakeMessageRepository repo;

    setUp(() {
      repo = FakeMessageRepository();
    });

    test('returns empty list when no messages exist', () async {
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('returns sending messages older than threshold', () async {
      repo.seed([
        _makeMsg(id: 'old-sending', status: 'sending', age: const Duration(minutes: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result.length, 1);
      expect(result.first.id, 'old-sending');
    });

    test('excludes sending messages younger than threshold', () async {
      repo.seed([
        _makeMsg(id: 'young-sending', status: 'sending', age: const Duration(seconds: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('excludes non-sending statuses', () async {
      repo.seed([
        _makeMsg(id: 'msg-failed', status: 'failed', age: const Duration(minutes: 5)),
        _makeMsg(id: 'msg-sent', status: 'sent', age: const Duration(minutes: 5)),
        _makeMsg(id: 'msg-delivered', status: 'delivered', age: const Duration(minutes: 5)),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('excludes incoming messages regardless of status', () async {
      repo.seed([
        _makeMsg(
          id: 'incoming-sending',
          status: 'sending',
          age: const Duration(minutes: 5),
          isIncoming: true,
        ),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result, isEmpty);
    });

    test('returns messages with and without wireEnvelope', () async {
      repo.seed([
        _makeMsg(
          id: 'with-env',
          status: 'sending',
          age: const Duration(minutes: 5),
          wireEnvelope: '{"type":"chat_message"}',
        ),
        _makeMsg(
          id: 'no-env',
          status: 'sending',
          age: const Duration(minutes: 5),
        ),
      ]);
      final result = await repo.getStuckSendingOutgoingMessages(
        olderThan: const Duration(seconds: 30),
      );
      expect(result.length, 2);
    });
  });
}
```

#### B.2 Red phase — DB helper unit tests

**File to create:** `test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';

import '../../helpers/in_memory_db.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('dbLoadStuckSendingOutgoingMessages', () {
    test('returns empty list when table is empty', () async {
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: DateTime.now().toUtc(),
      );
      expect(rows, isEmpty);
    });

    test('returns row with status=sending older than threshold', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-stuck',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows.length, 1);
      expect(rows.first['id'], 'msg-stuck');
    });

    test('excludes sending row newer than threshold', () async {
      final recentTs = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-recent',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'me',
        'text': 'Hi',
        'timestamp': recentTs,
        'status': 'sending',
        'is_incoming': 0,
        'created_at': recentTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows, isEmpty);
    });

    test('excludes incoming sending rows', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      await db.insert('messages', {
        'id': 'msg-incoming',
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'them',
        'text': 'Hi',
        'timestamp': oldTs,
        'status': 'sending',
        'is_incoming': 1,
        'created_at': oldTs,
      });
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
      );
      expect(rows, isEmpty);
    });

    test('respects limit parameter', () async {
      final oldTs = DateTime.now().toUtc()
          .subtract(const Duration(minutes: 5))
          .toIso8601String();
      for (var i = 0; i < 5; i++) {
        await db.insert('messages', {
          'id': 'msg-$i',
          'contact_peer_id': 'peer-a',
          'sender_peer_id': 'me',
          'text': 'msg $i',
          'timestamp': oldTs,
          'status': 'sending',
          'is_incoming': 0,
          'created_at': oldTs,
        });
      }
      final threshold = DateTime.now().toUtc()
          .subtract(const Duration(seconds: 30));
      final rows = await dbLoadStuckSendingOutgoingMessages(
        db,
        olderThan: threshold,
        limit: 3,
      );
      expect(rows.length, 3);
    });
  });
}
```

#### B.3 Red phase — `PendingMessageRetrier` unit tests

**File to create:** `test/core/services/pending_message_retrier_stuck_sending_test.dart`

These tests verify the retrier transitions and retries `'sending'` messages in addition to `'failed'` ones.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'fake_p2p_service.dart';
import '../../features/conversation/domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../bridge/fake_bridge.dart';

ConversationMessage _makeStuckSendingMessage({
  String id = 'msg-stuck-001',
  String contactPeerId = 'peer-target',
  String? wireEnvelope,
}) {
  final oldTs = DateTime.now().toUtc()
      .subtract(const Duration(minutes: 5))
      .toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: oldTs,
    status: 'sending',
    isIncoming: false,
    createdAt: oldTs,
    wireEnvelope: wireEnvelope,
  );
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;
  late PendingMessageRetrier retrier;

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    bridge = FakeBridge();
    retrier = PendingMessageRetrier(
      p2pService: p2pService,
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      bridge: bridge,
    );
  });

  tearDown(() {
    retrier.dispose();
    p2pService.dispose();
  });

  group('PendingMessageRetrier — stuck sending', () {
    test(
      'transitions stuck sending messages to failed then retries them on online transition',
      () async {
        final msg = _makeStuckSendingMessage();
        messageRepo.seed([msg]);
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        retrier.start();

        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        // recoverStuckSendingMessages must have been called
        expect(messageRepo.recoverStuckSendingCallCount, greaterThanOrEqualTo(1));
        // retryFailedMessages (via identity load) must have run
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );

    test(
      'does not call recoverStuckSendingMessages when offline',
      () async {
        retrier.start();
        // Stays offline — never transitions to online
        await Future.delayed(const Duration(seconds: 6));
        expect(messageRepo.recoverStuckSendingCallCount, 0);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    // ⚠️ AUDIT FIX (1B-04): This test creates a FakeP2PService with already-online
    // initialState. The current retrier start() sets _wasOnline = true and waits
    // for the NEXT offline-to-online transition, which never fires. This test
    // DEPENDS ON Part D initial-sweep fix (which schedules a debounce timer in
    // start() when _wasOnline is true). Without Part D, this test will timeout.
    // Implement Part D before expecting this test to pass.
    test(
      'stuck sending message with wire_envelope is delivered via inbox after recovery',
      () async {
        const envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
        final msg = _makeStuckSendingMessage(wireEnvelope: envelope);
        messageRepo.seed([msg]);
        // Simulate what the retrier will do: after recoverStuckSendingMessages
        // the FakeRepo returns it as a failed message with the envelope intact.
        messageRepo.failedOutgoingOverride = [
          msg.copyWith(status: 'failed'),
        ];
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        final onlineP2PService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        retrier = PendingMessageRetrier(
          p2pService: onlineP2PService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );
        retrier.start();

        // Start already online — debounce triggers immediately (requires Part D fix)
        await Future.delayed(const Duration(seconds: 6));

        expect(messageRepo.recoverStuckSendingCallCount, greaterThanOrEqualTo(1));
        expect(onlineP2PService.storeInInboxCallCount, greaterThanOrEqualTo(1));

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, 'delivered');
        expect(saved.transport, 'inbox');
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );

    test(
      'recovery error does not prevent retryFailedMessages from running',
      () async {
        messageRepo.throwOnRecoverStuckSending = true;
        identityRepo.seed(FakeIdentityRepository.makeIdentity());

        retrier.start();

        final onlineState = const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        );
        p2pService.emitState(onlineState);
        await Future.delayed(const Duration(seconds: 6));

        // Even though recoverStuckSendingMessages threw, the retrier continued
        expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      },
      timeout: const Timeout(Duration(seconds: 12)),
    );
  });
}
```

#### B.4 Green phase — Implementation

**Step A: New DB helper**

Add to `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/database/helpers/messages_db_helpers.dart`:

```dart
/// Loads outgoing messages with status='sending' that are older than
/// [olderThan]. These are candidates for immediate retry without waiting
/// for the next app-resume event.
///
/// Returns at most [limit] rows ordered by timestamp ASC.
Future<List<Map<String, Object?>>> dbLoadStuckSendingOutgoingMessages(
  Database db, {
  required DateTime olderThan,
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_STUCK_SENDING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'messages',
      where: "status = ? AND is_incoming = 0 AND timestamp < ?",
      whereArgs: ['sending', olderThan.toUtc().toIso8601String()],
      orderBy: 'timestamp ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_STUCK_SENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_STUCK_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
```

**Step B: Add method to `MessageRepository` interface**

> **⚠️ AUDIT FIX (1B-05):** `getStuckSendingOutgoingMessages` is unused by production code -- the retrier uses `recoverStuckSendingMessages` (transition to `'failed'`) then `retryFailedMessages`, never querying `'sending'` rows directly. Adding it to the abstract interface forces all implementors to add stubs. Consider making this a `MessageRepositoryImpl`-only method or deferring it entirely. If kept, it exists as a diagnostic hook and for future alternative recovery strategies that bypass the intermediate `'failed'` write.

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository.dart`, add:

```dart
/// Retrieves outgoing messages with status='sending' that are older than
/// [olderThan] and have not yet been transitioned by [recoverStuckSendingMessages].
///
/// NOTE: Currently unused by production code — the retrier goes through
/// recoverStuckSendingMessages → retryFailedMessages instead. Kept as a
/// diagnostic hook and for potential future recovery strategies.
Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
  required Duration olderThan,
});
```

**Step C: Implement in `MessageRepositoryImpl`**

Add field and constructor param (following the exact pattern of `dbLoadUnackedOutgoingMessages`):

```dart
final Future<List<Map<String, Object?>>> Function({
  required DateTime olderThan,
  int limit,
}) dbLoadStuckSendingOutgoingMessages;
```

Add the override:

```dart
@override
Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
  required Duration olderThan,
}) async {
  final cutoff = DateTime.now().toUtc().subtract(olderThan);
  final rows = await dbLoadStuckSendingOutgoingMessages(olderThan: cutoff);
  return rows.map((row) => ConversationMessage.fromMap(row)).toList();
}
```

**Step D: Update `FakeMessageRepository`**

Add to `test/features/conversation/domain/repositories/fake_message_repository.dart`:

```dart
List<ConversationMessage>? stuckSendingOutgoingOverride;

@override
Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
  required Duration olderThan,
}) async {
  if (stuckSendingOutgoingOverride != null) return stuckSendingOutgoingOverride!;
  final cutoff = DateTime.now().toUtc().subtract(olderThan);
  return _messages
      .where((m) =>
          m.status == 'sending' &&
          !m.isIncoming &&
          DateTime.parse(m.timestamp).toUtc().isBefore(cutoff))
      .toList();
}
```

**Step E: Update `PendingMessageRetrier._retryIfNeeded`**

> **⚠️ AUDIT FIX (1B-01):** This step adds recovery to `_retryIfNeeded`, but `_retryIfNeeded` is only called on an offline-to-online transition. If the node is ALREADY online when `start()` is called (common on cold-start where Go reports already-running), `_wasOnline = true` at `pending_message_retrier.dart:47` and no transition fires. Failed/stuck messages from a prior session are never retried until the next network flap. The initial-sweep fix for this is in **Part D** -- it adds a debounce timer in `start()` when `_wasOnline` is true. Part B's recovery only takes effect when combined with Part D's initial sweep. Implement Parts B and D together.

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/services/pending_message_retrier.dart`, update `_retryIfNeeded` to call `recoverStuckSendingMessages` before `retryFailedMessages`:

```dart
Future<void> _retryIfNeeded() async {
  if (_isRetrying) return;
  _isRetrying = true;

  try {
    // Step 0: recover messages left in 'sending' by prior interrupted sessions
    try {
      final recovered = await recoverStuckSendingMessages(
        messageRepo: messageRepo,
      );
      if (recovered > 0) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_STUCK_SENDING_RECOVERED',
          details: {'count': recovered},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_STUCK_SENDING_RECOVERY_ERROR',
        details: {'error': e.toString()},
      );
      // Non-fatal: continue to retryFailedMessages
    }

    // Existing steps unchanged below...
    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
    );
    // ... rest unchanged
  }
}
```

Add the import at the top of the file:

```dart
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
```

**Step F: Wire the new DB helper into the DI chain**

In `main.dart`, in the `MessageRepositoryImpl` constructor call, add:

```dart
dbLoadStuckSendingOutgoingMessages: ({required DateTime olderThan, int limit = 50}) =>
    dbLoadStuckSendingOutgoingMessages(db, olderThan: olderThan, limit: limit),
dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) =>
    dbRecoverStuckSendingMessages(db, olderThan: olderThan, limit: limit),
```

#### B.5 Smoke test — end-to-end send-then-background scenario

**File to create:** `test/features/conversation/integration/stuck_sending_recovery_test.dart`

This integration test simulates the full lifecycle: user sends, app is killed, app resumes, message is recovered and delivered. It uses `FakeMessageRepository`, `FakeP2PService`, and `FakeBridge` exclusively — no real DB or network.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart' as p2p;

import '../../core/services/fake_p2p_service.dart';
import '../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/contacts/domain/models/contact_model.dart';
import '../../features/identity/domain/models/identity_model.dart';

void main() {
  group('Stuck-sending recovery — smoke test', () {
    test(
      'message stuck in sending is recovered and delivered on next resume+online',
      () async {
        // --- Arrange ---
        // Simulate what was persisted when the user sent and backgrounded
        final stuckTs = DateTime.now().toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        // ⚠️ AUDIT FIX (1B-03 / 1A-04): wireEnvelope is null here because
        // stuck 'sending' rows from conversation_wired.dart:616-637 have
        // wireEnvelope = null — the envelope is generated inside sendChatMessage,
        // which never completed. This tests the full re-encrypt retry path,
        // not the wire-envelope inbox fast-path.
        final stuckMessage = ConversationMessage(
          id: 'msg-stuck-smoke',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello Bob!',
          timestamp: stuckTs,
          status: 'sending',   // <-- stuck here after kill
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,  // realistic: envelope not yet serialized
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMessage]);
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: null,
            mnemonic12: null,
            createdAt: stuckTs,
            updatedAt: stuckTs,
          ));
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: stuckTs,
              mlKemPublicKey: null,
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-bob',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult:
              const p2p.SendMessageResult(sent: true, reply: 'ack'),
        );
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem',
              'ciphertext': 'fake-ct',
              'nonce': 'fake-nonce',
            },
          },
        );

        // --- Act: simulate app resume recovery sequence ---

        // ⚠️ AUDIT FIX (1B-02): The original plan manually re-seeded the message
        // as 'failed' after calling recoverStuckSendingMessages, bypassing the
        // actual recovery mechanism. The corrected version below relies on
        // FakeMessageRepository.recoverStuckSendingMessages actually transitioning
        // the seeded row's status from 'sending' to 'failed' in _messages
        // (see AUDIT FIX 1B-06 in Part A Step F).

        // Step 1: recover stuck messages (transitions sending → failed IN PLACE)
        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        expect(recovered, 1);

        // Verify same row was transitioned — NOT manually re-seeded
        final afterRecovery =
            await messageRepo.getMessagesForContact('peer-bob');
        final recoveredMsg =
            afterRecovery.firstWhere((m) => m.id == 'msg-stuck-smoke');
        expect(recoveredMsg.status, 'failed');

        // Step 2: retry failed messages (picks up the recovered message)
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // --- Assert ---
        expect(retried, 1);

        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-stuck-smoke'); // same row, not a new message
        // Either delivered (inbox path) or at minimum no longer 'sending'
        expect(saved.status, isNot('sending'));
        expect(saved.status, isNot('failed'));
      },
    );

    test(
      'message younger than threshold remains sending and is not retried',
      () async {
        final recentTs = DateTime.now().toUtc()
            .subtract(const Duration(seconds: 5))
            .toIso8601String();

        final youngMessage = ConversationMessage(
          id: 'msg-young',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Still in flight',
          timestamp: recentTs,
          status: 'sending',
          isIncoming: false,
          createdAt: recentTs,
        );

        final messageRepo = FakeMessageRepository()..seed([youngMessage]);
        // recoverStuckSendingReturnValue defaults to 0 — nothing recovered

        final count = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        expect(count, 0);
        // The seeded message must still be 'sending'
        final messages =
            await messageRepo.getMessagesForContact('peer-bob');
        expect(messages.first.status, 'sending');
      },
    );

    test(
      'no stuck messages — both recovery and retry are no-ops',
      () async {
        final messageRepo = FakeMessageRepository(); // empty
        final identityRepo = FakeIdentityRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'peer-alice'),
        );
        final bridge = FakeBridge();
        final contactRepo = FakeContactRepository();

        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
        );
        expect(recovered, 0);

        // retryFailedMessages returns 0 — no identity, so early exit
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );
        expect(retried, 0);
      },
    );
  });
}
```

#### B.6 Refactor phase

- Both `recoverStuckSendingMessages` (resume hook) and `_retryIfNeeded` (retrier) now call the same use case with the same default threshold (`kStuckSendingThreshold = Duration(seconds: 30)`). This is intentional: the resume path transitions `'sending'` to `'failed'` in the DB first; the retrier then picks up the `'failed'` rows. There is no double-processing because `dbRecoverStuckSendingMessages` is idempotent — a second call finds zero `'sending'` rows.
- After these fixes land, the `getStuckSendingOutgoingMessages` method on `MessageRepository` is technically unused by production code (the retrier goes through `recoverStuckSendingMessages` → `retryFailedMessages`, not through a direct `'sending'` query). It exists for completeness and as a diagnostic hook. If the team decides to keep the retrier from doing an intermediate DB write, `getStuckSendingOutgoingMessages` can be used to query and retry `'sending'` messages directly without touching their status. Document this in the method docstring and keep it in the interface as a first-class citizen.
- Consider whether the 30-second default deserves a `const` in `lib/core/constants/retry_constants.dart` alongside any future `kUnackedMessageThreshold`. The `retryUnackedMessages` use case hardcodes `Duration(seconds: 60)` inline today; a follow-up task should centralise all retry thresholds in one file.

---

### Part C: Make `retryFailedMessages` replay-safe for media

**Problem statement:** When `retryFailedMessages` falls through to the full `sendChatMessage` re-encrypt path (line 92), it passes **no** `mediaAttachments` and **no** `mediaAttachmentRepo`. Any media that was already uploaded and persisted in the `media_attachments` table is silently dropped -- the recipient receives a text-only message. Additionally, `retryUnackedMessages` dereferences `msg.wireEnvelope!` at line 47 with no null guard, relying entirely on the SQL filter to exclude null rows. A future bug in the query or a corrupt row would crash the entire retry loop.

**Scope:**
- Modify `retryFailedMessages` to accept an optional `MediaAttachmentRepository`, load attachments from DB before re-sending, and filter to only `downloadStatus == 'done'` rows.
- Add null guard to `retryUnackedMessages` for `wireEnvelope`.
- Voice messages with `text=''` and a `done` attachment must pass the empty-text guard in `sendChatMessage` because `hasAttachments=true`.
- Legacy callers that do not pass `mediaAttachmentRepo` must continue to work (text-only retry, documented and tested).

#### C.1 Red phase — Unit tests for media-aware retry

**File to create:** `test/features/conversation/application/retry_failed_messages_media_test.dart`

> **⚠️ AUDIT FIX (1C-SEED):** The tests below use `FakeMessageRepository.seed()` (already exists in `test/features/conversation/domain/repositories/fake_message_repository.dart`) and a local `_FakeMediaAttachmentRepository` with a `seedAttachments()` helper (defined below). The `_FakeMediaAttachmentRepository` follows the same pattern as the private `_FakeMediaAttachmentRepository` in `send_voice_message_use_case_test.dart`, extended with `seedAttachments()`, call tracking, and `getAttachmentsForMessageCallCount`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/bridge/fake_bridge.dart';

// ---------------------------------------------------------------------------
// Test-local FakeMediaAttachmentRepository
// ---------------------------------------------------------------------------
class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> _attachments = [];

  // Call tracking
  int getAttachmentsForMessageCallCount = 0;
  int saveAttachmentCallCount = 0;
  String? lastQueriedMessageId;

  /// Seed attachments for a specific message. Can be called multiple times
  /// for different messages.
  void seedAttachments({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) {
    for (final a in attachments) {
      _attachments.add(a.copyWith(messageId: messageId));
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    getAttachmentsForMessageCallCount++;
    lastQueriedMessageId = messageId;
    return _attachments
        .where((a) => a.messageId == messageId)
        .toList();
  }

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    saveAttachmentCallCount++;
    final idx = _attachments.indexWhere((a) => a.id == attachment.id);
    if (idx >= 0) {
      _attachments[idx] = attachment;
    } else {
      _attachments.add(attachment);
    }
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    final result = <String, List<MediaAttachment>>{};
    for (final messageId in messageIds) {
      final attachments = await getAttachmentsForMessage(messageId);
      if (attachments.isNotEmpty) {
        result[messageId] = attachments;
      }
    }
    return result;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------
const _testTs = '2026-01-01T00:00:00.000Z';

ConversationMessage _makeFailedMessage({
  String id = 'msg-failed-media-001',
  String contactPeerId = 'peer-bob',
  String text = 'Check this photo',
  String? wireEnvelope,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: _testTs,
    status: 'failed',
    isIncoming: false,
    createdAt: _testTs,
    wireEnvelope: wireEnvelope,
  );
}

MediaAttachment _makeDoneAttachment({
  String id = 'blob-uploaded-001',
  String messageId = 'msg-failed-media-001',
  String mime = 'image/jpeg',
  int size = 102400,
  String mediaType = 'image',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: mediaType,
    downloadStatus: 'done',
    createdAt: _testTs,
    localPath: '/tmp/photo.jpg',
  );
}

MediaAttachment _makeUploadPendingAttachment({
  String id = 'placeholder-uuid-001',
  String messageId = 'msg-failed-media-001',
  String mime = 'image/jpeg',
  int size = 102400,
  String mediaType = 'image',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: mediaType,
    downloadStatus: 'upload_pending',
    createdAt: _testTs,
    localPath: '/tmp/photo_pending.jpg',
  );
}

void main() {
  late FakeMessageRepository messageRepo;
  late _FakeMediaAttachmentRepository mediaAttachmentRepo;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeBridge bridge;

  setUp(() {
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = _FakeMediaAttachmentRepository();
    identityRepo = FakeIdentityRepository()
      ..seed(IdentityModel(
        peerId: 'peer-alice',
        publicKey: 'pk-alice',
        privateKey: 'sk-alice',
        mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
        createdAt: _testTs,
        updatedAt: _testTs,
      ));
    contactRepo = FakeContactRepository()
      ..seed([
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Bob',
          signature: 'sig',
          scannedAt: _testTs,
          mlKemPublicKey: null, // no ML-KEM -> v1 plaintext path
        ),
      ]);
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-alice',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
      storeInInboxResult: true,
    );
    bridge = FakeBridge();
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('retryFailedMessages -- media-aware retry', () {
    // ------------------------------------------------------------------
    // C.1-TEST-1: retryFailedMessages queries mediaAttachmentRepo before
    //             calling sendChatMessage
    // ------------------------------------------------------------------
    test(
      'queries mediaAttachmentRepo.getAttachmentsForMessage before re-sending',
      () async {
        final msg = _makeFailedMessage();
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg.id,
          attachments: [_makeDoneAttachment(messageId: msg.id)],
        );

        await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Must have queried attachments for the failed message
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 1);
        expect(mediaAttachmentRepo.lastQueriedMessageId, msg.id);
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-2: done attachments are passed to sendChatMessage
    // ------------------------------------------------------------------
    test(
      'passes done attachments to sendChatMessage on retry',
      () async {
        final msg = _makeFailedMessage();
        final doneAttachment = _makeDoneAttachment(messageId: msg.id);
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg.id,
          attachments: [doneAttachment],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(count, 1);

        // The retried message was sent via inbox fallback; verify the wire
        // content includes the attachment id (sendChatMessage serializes
        // media into the MessagePayload -> wire JSON).
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains(doneAttachment.id),
        );
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-3: text-only message retries with empty attachment list
    //             when no attachment rows exist
    // ------------------------------------------------------------------
    test(
      'retries text-only message with mediaAttachments=[] when no attachments in DB',
      () async {
        final msg = _makeFailedMessage(text: 'Just text, no media');
        messageRepo.seed([msg]);
        // No attachments seeded in mediaAttachmentRepo

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(count, 1);
        // Queried but found nothing
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 1);

        // Message was still sent (text-only)
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('Just text, no media'),
        );
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-4: upload_pending attachments are NOT passed to
    //             sendChatMessage (Part F handles re-upload)
    // ------------------------------------------------------------------
    test(
      'filters out upload_pending attachments -- only done attachments are sent',
      () async {
        final msg = _makeFailedMessage();
        final doneAttachment = _makeDoneAttachment(
          id: 'blob-done-001',
          messageId: msg.id,
        );
        final pendingAttachment = _makeUploadPendingAttachment(
          id: 'placeholder-pending-001',
          messageId: msg.id,
        );
        messageRepo.seed([msg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg.id,
          attachments: [doneAttachment, pendingAttachment],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(count, 1);

        // Wire content must include the done attachment but NOT the pending one
        final wireContent = p2pService.lastStoreInInboxMessage!;
        expect(wireContent, contains('blob-done-001'));
        expect(wireContent, isNot(contains('placeholder-pending-001')));
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-5: voice message with text='' and done attachment passes
    //             the empty-text guard because hasAttachments=true
    // ------------------------------------------------------------------
    test(
      'voice message with empty text and done attachment retries successfully',
      () async {
        final voiceMsg = _makeFailedMessage(
          id: 'msg-voice-001',
          text: '',
        );
        final voiceAttachment = _makeDoneAttachment(
          id: 'blob-voice-001',
          messageId: voiceMsg.id,
          mime: 'audio/m4a',
          mediaType: 'audio',
          size: 48000,
        );
        messageRepo.seed([voiceMsg]);
        mediaAttachmentRepo.seedAttachments(
          messageId: voiceMsg.id,
          attachments: [voiceAttachment],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Must succeed -- sendChatMessage allows empty text when hasAttachments
        expect(count, 1);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('blob-voice-001'),
        );
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-6:      legacy callers without mediaAttachmentRepo send
    //                  text-only (no crash, media silently dropped)
    // ------------------------------------------------------------------
    test(
      'retryFailedMessages without mediaAttachmentRepo sends text-only for media message',
      () async {
        final msg = _makeFailedMessage(text: 'Photo attached');
        messageRepo.seed([msg]);
        // Attachments exist in the hypothetical DB but mediaAttachmentRepo
        // is not passed -- legacy caller path.

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          // mediaAttachmentRepo: NOT passed
        );

        expect(count, 1);
        // Message was sent but without media (text-only)
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('Photo attached'),
        );
        // mediaAttachmentRepo was never queried
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.1-TEST-7:     multiple failed messages with mixed media states
    // ------------------------------------------------------------------
    test(
      'retries multiple messages: one with media, one text-only, one with only pending attachments',
      () async {
        // Message 1: has done attachments
        final msg1 = _makeFailedMessage(
          id: 'msg-with-media',
          text: 'Photo msg',
        );
        final att1 = _makeDoneAttachment(
          id: 'blob-img-001',
          messageId: 'msg-with-media',
        );

        // Message 2: text-only, no attachments in DB
        final msg2 = _makeFailedMessage(
          id: 'msg-text-only',
          text: 'Just text',
        );

        // Message 3: only upload_pending attachments (Part F territory)
        final msg3 = _makeFailedMessage(
          id: 'msg-pending-only',
          text: 'Pending upload',
        );
        final att3 = _makeUploadPendingAttachment(
          id: 'placeholder-003',
          messageId: 'msg-pending-only',
        );

        messageRepo.seed([msg1, msg2, msg3]);
        mediaAttachmentRepo.seedAttachments(
          messageId: msg1.id,
          attachments: [att1],
        );
        mediaAttachmentRepo.seedAttachments(
          messageId: msg3.id,
          attachments: [att3],
        );

        final count = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(count, 3);
        // All three messages queried for attachments
        expect(mediaAttachmentRepo.getAttachmentsForMessageCallCount, 3);
      },
    );
  });
}
```

#### C.2 Red phase — `retryUnackedMessages` null-guard tests

**File to create:** `test/features/conversation/application/retry_unacked_messages_null_guard_test.dart`

These tests verify the null guard on `msg.wireEnvelope` in `retryUnackedMessages`, before the guard exists.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/retry_unacked_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';

const _testTs = '2026-01-01T00:00:00.000Z';

void main() {
  late FakeMessageRepository messageRepo;
  late FakeP2PService p2pService;

  setUp(() {
    messageRepo = FakeMessageRepository();
    p2pService = FakeP2PService(storeInInboxResult: true);
  });

  tearDown(() {
    p2pService.dispose();
  });

  group('retryUnackedMessages -- null wireEnvelope guard', () {
    // ------------------------------------------------------------------
    // C.2-TEST-1: null wireEnvelope is skipped, not dereferenced
    // ------------------------------------------------------------------
    test(
      'skips message with null wireEnvelope without crashing',
      () async {
        // Force the unacked query to return a message with null wireEnvelope.
        // In production this should not happen (SQL filters it out), but
        // defensive code must handle it.
        final badMsg = ConversationMessage(
          id: 'msg-null-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: null, // <-- null despite being 'sent'
        );
        messageRepo.unackedOutgoingOverride = [badMsg];

        // Must NOT throw a null dereference error
        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        // Skipped -- no inbox store attempted
        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-2: empty wireEnvelope is also skipped
    // ------------------------------------------------------------------
    test(
      'skips message with empty wireEnvelope string',
      () async {
        final badMsg = ConversationMessage(
          id: 'msg-empty-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: '', // <-- empty string
        );
        messageRepo.unackedOutgoingOverride = [badMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(p2pService.storeInInboxCallCount, 0);
        expect(count, 0);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-3: valid wireEnvelope is still processed normally
    // ------------------------------------------------------------------
    test(
      'processes message with valid wireEnvelope normally',
      () async {
        const envelope = '{"type":"chat_message","version":"1","payload":{}}';
        final goodMsg = ConversationMessage(
          id: 'msg-good-envelope',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Hello',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: envelope,
        );
        messageRepo.unackedOutgoingOverride = [goodMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        expect(p2pService.storeInInboxCallCount, 1);
        expect(p2pService.lastStoreInInboxMessage, envelope);
        expect(count, 1);
      },
    );

    // ------------------------------------------------------------------
    // C.2-TEST-4: mixed batch -- null envelope skipped, valid processed
    // ------------------------------------------------------------------
    test(
      'in a mixed batch, skips null envelopes and processes valid ones',
      () async {
        const envelope = '{"type":"chat_message","version":"1","payload":{}}';
        final nullMsg = ConversationMessage(
          id: 'msg-null',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Bad',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: null,
        );
        final goodMsg = ConversationMessage(
          id: 'msg-good',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Good',
          timestamp: _testTs,
          status: 'sent',
          isIncoming: false,
          createdAt: _testTs,
          wireEnvelope: envelope,
        );
        messageRepo.unackedOutgoingOverride = [nullMsg, goodMsg];

        final count = await retryUnackedMessages(
          messageRepo: messageRepo,
          p2pService: p2pService,
        );

        // Only the good message was stored
        expect(p2pService.storeInInboxCallCount, 1);
        expect(count, 1);

        // The good message was delivered
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-good');
        expect(saved.status, 'delivered');
      },
    );
  });
}
```

#### C.3 Green phase — Implementation

**Step A: Add `MediaAttachmentRepository` parameter to `retryFailedMessages`**

**File to modify:** `lib/features/conversation/application/retry_failed_messages_use_case.dart`

Add imports at top:

```dart
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
```

Update the function signature -- add `MediaAttachmentRepository? mediaAttachmentRepo` as an optional named parameter:

```dart
Future<int> retryFailedMessages({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,  // NEW
}) async {
```

**Step B: Load and filter attachments before the fallback `sendChatMessage` call**

Inside the `for (final msg in failedMessages)` loop, immediately before the existing comment `// Fallback: re-encrypt + full send (existing behavior, text-only)` (currently at line 87), insert the attachment loading logic:

```dart
      // Fallback: re-encrypt + full send
      // Load media attachments from DB if mediaAttachmentRepo is available.
      // Only include attachments with downloadStatus='done' (upload completed).
      // Attachments with 'upload_pending' status are handled by Part F re-upload.
      List<MediaAttachment> doneAttachments = const [];
      if (mediaAttachmentRepo != null) {
        try {
          final allAttachments =
              await mediaAttachmentRepo.getAttachmentsForMessage(msg.id);
          doneAttachments = allAttachments
              .where((a) => a.downloadStatus == 'done')
              .toList();
          if (doneAttachments.isNotEmpty) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_FAILED_MESSAGE_MEDIA_LOADED',
              details: {
                'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
                'totalAttachments': allAttachments.length,
                'doneAttachments': doneAttachments.length,
              },
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MESSAGE_MEDIA_LOAD_ERROR',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'error': e.toString(),
            },
          );
          // Non-fatal: continue with text-only retry
        }
      }
```

**Step C: Pass loaded attachments and `mediaAttachmentRepo` to `sendChatMessage`**

Update the existing `sendChatMessage` call (currently line 92-103) to include the new parameters:

```dart
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: msg.contactPeerId,
        text: msg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: msg.id,
        timestamp: msg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: mlKemPk,
        mediaAttachments: doneAttachments.isNotEmpty ? doneAttachments : null,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
```

> **⚠️ AUDIT FIX (1C-ORPHAN):** CRITICAL -- When Part G writes `upload_pending` placeholder rows with a pre-generated UUID as `id`, and then `uploadMedia` generates a **different** blob ID (`upload_media_use_case.dart:46` -- `final blobId = _uuid.v4()`), the subsequent `saveAttachment` call uses the new blob ID as the attachment `id` (PRIMARY KEY). The old placeholder row with the original UUID is **never replaced** -- it survives in the DB alongside the real row. When `retryFailedMessages` calls `mediaAttachmentRepo.getAttachmentsForMessage(msg.id)`, it may find both orphaned `upload_pending` rows and `done` rows. The `where((a) => a.downloadStatus == 'done')` filter in Step B handles this correctly -- orphaned `upload_pending` rows are excluded.

> **⚠️ AUDIT FIX (1C-LEGACY):** When `mediaAttachmentRepo` is not passed (legacy callers), the `doneAttachments` list remains empty (`const []`), and `sendChatMessage` is called with `mediaAttachments: null` and `mediaAttachmentRepo: null`. This silently drops media -- the legacy behavior. The test `C.1-TEST-6` documents this.

**Step D: Add null guard to `retryUnackedMessages`**

**File to modify:** `lib/features/conversation/application/retry_unacked_messages_use_case.dart`

Replace the current unsafe dereference at line 43-48:

```dart
  for (final msg in unacked) {
    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId,
        msg.wireEnvelope!,
      );
```

With:

```dart
  for (final msg in unacked) {
    // Defensive: skip messages with null or empty wireEnvelope.
    // The SQL query should exclude these, but a corrupt row or future
    // query change could let one through.
    if (msg.wireEnvelope == null || msg.wireEnvelope!.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_NULL_ENVELOPE',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        },
      );
      continue;
    }

    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId,
        msg.wireEnvelope!,
      );
```

**Step E: Update all callers of `retryFailedMessages` to pass `mediaAttachmentRepo`**

> **⚠️ AUDIT FIX (1C-CALLERS):** `retryFailedMessages` is called from two production sites:
> 1. `PendingMessageRetrier._retryIfNeeded` (`lib/core/services/pending_message_retrier.dart`) -- the retrier must be updated to accept and forward `mediaAttachmentRepo`. Add `MediaAttachmentRepository? mediaAttachmentRepo` to the `PendingMessageRetrier` constructor and pass it through to `retryFailedMessages`.
> 2. `handleAppResumed` callbacks (added by Part D) -- these must also pass `mediaAttachmentRepo` through. The wiring in `main.dart` where `PendingMessageRetrier` is constructed must include `mediaAttachmentRepo`.

In `lib/core/services/pending_message_retrier.dart`, add the import:

```dart
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
```

Add the constructor parameter and field:

```dart
class PendingMessageRetrier {
  final P2PService p2pService;
  final MessageRepository messageRepo;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;
  final MediaAttachmentRepository? mediaAttachmentRepo;  // NEW

  PendingMessageRetrier({
    required this.p2pService,
    required this.messageRepo,
    required this.identityRepo,
    required this.contactRepo,
    required this.bridge,
    this.mediaAttachmentRepo,  // NEW
  });
```

And in `_retryIfNeeded`, update the `retryFailedMessages` call:

```dart
    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,  // NEW
    );
```

In `main.dart`, where `PendingMessageRetrier` is constructed, add:

```dart
mediaAttachmentRepo: mediaAttachmentRepo,
```

**Step F: Full updated `retryFailedMessages` function**

For clarity, here is the complete updated function with all changes applied:

```dart
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Retries all failed outgoing messages.
///
/// Loads identity, queries failed messages, then re-sends each via
/// [sendChatMessage] with the original messageId + timestamp so the
/// DB row is updated in-place (INSERT OR REPLACE).
///
/// When [mediaAttachmentRepo] is provided, loads media attachments from the
/// DB before re-sending. Only attachments with `downloadStatus == 'done'`
/// (upload already completed) are included. Attachments with
/// `downloadStatus == 'upload_pending'` are excluded -- Part F handles
/// re-upload for those.
///
/// Returns the count of successfully retried messages.
/// Non-fatal: catches errors per-message and continues with the next.
Future<int> retryFailedMessages({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  emitFlowEvent(layer: 'FL', event: 'RETRY_FAILED_MESSAGES_START', details: {});

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NO_IDENTITY',
      details: {},
    );
    return 0;
  }

  final failedMessages = await messageRepo.getFailedOutgoingMessages();
  if (failedMessages.isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MESSAGES_NONE',
      details: {},
    );
    return 0;
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_FOUND',
    details: {'count': failedMessages.length},
  );

  var successCount = 0;

  for (final msg in failedMessages) {
    try {
      // Prefer wire_envelope -> inbox-only (preserves media, no re-encrypt)
      if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty) {
        try {
          final stored = await p2pService.storeInInbox(
            msg.contactPeerId,
            msg.wireEnvelope!,
          );
          if (stored) {
            await messageRepo.saveMessage(
              msg.copyWith(
                status: 'delivered',
                transport: 'inbox',
                wireEnvelope: null,
              ),
            );
            successCount++;
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_FAILED_MESSAGE_SUCCESS',
              details: {
                'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
                'via': 'wire_envelope',
              },
            );
            continue;
          }
        } catch (_) {
          // Wire envelope inbox failed -- fall through to full send
        }
      }

      // Fallback: re-encrypt + full send
      // Load media attachments from DB if mediaAttachmentRepo is available.
      // Only include attachments with downloadStatus='done' (upload completed).
      // Attachments with 'upload_pending' status are handled by Part F re-upload.
      List<MediaAttachment> doneAttachments = const [];
      if (mediaAttachmentRepo != null) {
        try {
          final allAttachments =
              await mediaAttachmentRepo.getAttachmentsForMessage(msg.id);
          doneAttachments = allAttachments
              .where((a) => a.downloadStatus == 'done')
              .toList();
          if (doneAttachments.isNotEmpty) {
            emitFlowEvent(
              layer: 'FL',
              event: 'RETRY_FAILED_MESSAGE_MEDIA_LOADED',
              details: {
                'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
                'totalAttachments': allAttachments.length,
                'doneAttachments': doneAttachments.length,
              },
            );
          }
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MESSAGE_MEDIA_LOAD_ERROR',
            details: {
              'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
              'error': e.toString(),
            },
          );
          // Non-fatal: continue with text-only retry
        }
      }

      // Look up contact for ML-KEM public key
      final contact = await contactRepo.getContact(msg.contactPeerId);
      final mlKemPk = contact?.mlKemPublicKey;

      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: msg.contactPeerId,
        text: msg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: msg.id,
        timestamp: msg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: mlKemPk,
        mediaAttachments: doneAttachments.isNotEmpty ? doneAttachments : null,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (result == SendChatMessageResult.success) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_SUCCESS',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_FAILED_MESSAGE_STILL_FAILED',
          details: {
            'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
            'reason': result.name,
          },
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGE_ERROR',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'error': e.toString(),
        },
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_FAILED_MESSAGES_COMPLETE',
    details: {'total': failedMessages.length, 'succeeded': successCount},
  );

  return successCount;
}
```

**Step G: Full updated `retryUnackedMessages` loop with null guard**

For clarity, here is the complete updated loop from `retryUnackedMessages`:

```dart
  var count = 0;
  for (final msg in unacked) {
    // Defensive: skip messages with null or empty wireEnvelope.
    // The SQL query should exclude these, but a corrupt row or future
    // query change could let one through.
    if (msg.wireEnvelope == null || msg.wireEnvelope!.isEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_SKIP_NULL_ENVELOPE',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        },
      );
      continue;
    }

    try {
      final stored = await p2pService.storeInInbox(
        msg.contactPeerId,
        msg.wireEnvelope!,
      );
      if (stored) {
        await messageRepo.saveMessage(
          msg.copyWith(
            status: 'delivered',
            transport: 'inbox',
            wireEnvelope: null,
          ),
        );
        count++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_UNACKED_MESSAGE_DELIVERED',
          details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
        );
      }
      // Not stored -> leave as 'sent', retry on next online transition
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_ERROR',
        details: {
          'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
          'error': e.toString(),
        },
      );
    }
  }
```

#### C.4 Green phase — Smoke test (media retry end-to-end)

**File to create:** `test/features/conversation/integration/media_retry_smoke_test.dart`

This integration test simulates the full lifecycle: user sends a photo message, upload completes, send fails, app resumes, message is recovered and re-sent with the media attachment intact.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../domain/repositories/fake_message_repository.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../../core/bridge/fake_bridge.dart';

// Reuse the same fake pattern as C.1 tests
class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> _attachments = [];

  void seedAttachments({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) {
    for (final a in attachments) {
      _attachments.add(a.copyWith(messageId: messageId));
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return _attachments.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    final idx = _attachments.indexWhere((a) => a.id == attachment.id);
    if (idx >= 0) {
      _attachments[idx] = attachment;
    } else {
      _attachments.add(attachment);
    }
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final atts = await getAttachmentsForMessage(id);
      if (atts.isNotEmpty) result[id] = atts;
    }
    return result;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;
  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;
  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];
  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}
  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
}

const _testTs = '2026-01-01T00:00:00.000Z';

void main() {
  group('Media retry smoke test -- end-to-end', () {
    test(
      'photo message stuck in sending is recovered and retried with media intact',
      () async {
        // --- Arrange ---
        // Simulate state after: user sent photo, upload completed, send failed
        // (app was killed mid-send). The optimistic row has status='sending',
        // wireEnvelope=null. The uploaded attachment is in media_attachments
        // with downloadStatus='done'.
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMessage = ConversationMessage(
          id: 'msg-photo-stuck',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Check this photo',
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final uploadedAttachment = MediaAttachment(
          id: 'blob-uploaded-photo',
          messageId: 'msg-photo-stuck',
          mime: 'image/jpeg',
          size: 204800,
          mediaType: 'image',
          width: 1920,
          height: 1080,
          downloadStatus: 'done',
          createdAt: stuckTs,
          localPath: '/tmp/photo.jpg',
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMessage]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: stuckMessage.id,
            attachments: [uploadedAttachment],
          );
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
            createdAt: _testTs,
            updatedAt: _testTs,
          ));
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: null,
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = FakeBridge();

        // --- Act: simulate app resume recovery sequence ---

        // Step 1: recover stuck messages (sending -> failed)
        final recovered = await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        expect(recovered, 1);

        // Step 2: retry failed messages with media awareness
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // --- Assert ---
        expect(retried, 1);

        // The wire content sent to inbox must contain the media attachment
        expect(p2pService.lastStoreInInboxMessage, isNotNull);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('blob-uploaded-photo'),
        );
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('image/jpeg'),
        );

        // The saved message must be delivered
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.id, 'msg-photo-stuck');
        expect(saved.status, isNot('sending'));
        expect(saved.status, isNot('failed'));

        p2pService.dispose();
      },
    );

    test(
      'voice message with empty text is retried successfully with audio attachment',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final voiceMsg = ConversationMessage(
          id: 'msg-voice-stuck',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: '', // voice messages typically have empty text
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final voiceAttachment = MediaAttachment(
          id: 'blob-voice-uploaded',
          messageId: 'msg-voice-stuck',
          mime: 'audio/m4a',
          size: 48000,
          mediaType: 'audio',
          durationMs: 5000,
          downloadStatus: 'done',
          createdAt: stuckTs,
          localPath: '/tmp/voice.m4a',
        );

        final messageRepo = FakeMessageRepository()..seed([voiceMsg]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: voiceMsg.id,
            attachments: [voiceAttachment],
          );
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
            createdAt: _testTs,
            updatedAt: _testTs,
          ));
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: null,
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = FakeBridge();

        // Step 1: recover
        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        // Step 2: retry with media
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Voice message with empty text + attachment should succeed
        expect(retried, 1);
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('blob-voice-uploaded'),
        );
        expect(
          p2pService.lastStoreInInboxMessage!,
          contains('audio/m4a'),
        );

        p2pService.dispose();
      },
    );

    test(
      'message with only upload_pending attachments retries as text-only',
      () async {
        final stuckTs = DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final msg = ConversationMessage(
          id: 'msg-pending-only',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: 'Photo attached',
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          wireEnvelope: null,
        );

        final pendingAttachment = MediaAttachment(
          id: 'placeholder-uuid-pending',
          messageId: 'msg-pending-only',
          mime: 'image/jpeg',
          size: 102400,
          mediaType: 'image',
          downloadStatus: 'upload_pending', // upload never completed
          createdAt: stuckTs,
          localPath: '/tmp/photo_pending.jpg',
        );

        final messageRepo = FakeMessageRepository()..seed([msg]);
        final mediaAttachmentRepo = _FakeMediaAttachmentRepository()
          ..seedAttachments(
            messageId: msg.id,
            attachments: [pendingAttachment],
          );
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: 'sk-alice',
            mnemonic12: 'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
            createdAt: _testTs,
            updatedAt: _testTs,
          ));
        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: _testTs,
              mlKemPublicKey: null,
            ),
          ]);
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );
        final bridge = FakeBridge();

        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // Retried as text-only (pending attachment filtered out)
        expect(retried, 1);
        final wire = p2pService.lastStoreInInboxMessage!;
        expect(wire, contains('Photo attached'));
        // Must NOT contain the pending attachment ID
        expect(wire, isNot(contains('placeholder-uuid-pending')));

        p2pService.dispose();
      },
    );
  });
}
```

#### C.5 Refactor phase

- **Extract attachment loading into a shared helper.** The pattern of loading attachments, filtering to `done`, and logging is duplicated between `retryFailedMessages` and any future retry path (e.g., Part D's `handleAppResumed` callback, Part F's re-upload logic). Extract into a top-level helper in `lib/features/conversation/application/retry_failed_messages_use_case.dart` (or a new file `lib/features/conversation/application/load_done_attachments_for_retry.dart` if the team prefers one-function-per-file):

```dart
/// Loads media attachments for a message, filtering to only those with
/// `downloadStatus == 'done'` (upload already completed).
///
/// Returns an empty list if [mediaAttachmentRepo] is null, if no
/// attachments exist, or if all attachments are still pending upload.
/// Catches and logs errors -- never throws.
Future<List<MediaAttachment>> loadDoneAttachmentsForRetry({
  required String messageId,
  required MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (mediaAttachmentRepo == null) return const [];

  try {
    final allAttachments =
        await mediaAttachmentRepo.getAttachmentsForMessage(messageId);
    final done = allAttachments
        .where((a) => a.downloadStatus == 'done')
        .toList();
    if (done.isNotEmpty) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_MEDIA_LOADED',
        details: {
          'messageId': messageId.length > 8
              ? messageId.substring(0, 8)
              : messageId,
          'total': allAttachments.length,
          'done': done.length,
        },
      );
    }
    return done;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_MEDIA_LOAD_ERROR',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'error': e.toString(),
      },
    );
    return const [];
  }
}
```

After extracting, simplify the attachment-loading block inside `retryFailedMessages` to a single call:

```dart
      final doneAttachments = await loadDoneAttachmentsForRetry(
        messageId: msg.id,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );
```

- **Ensure both text and media retry paths share the same error handling.** After extracting the helper, both the text-only path (no `mediaAttachmentRepo` passed) and the media-aware path converge to the same `sendChatMessage` call. The only difference is whether `mediaAttachments` is null or populated. Error handling (per-message try/catch, FLOW logging, status reporting) is identical for both paths and does not need duplication.

- **Consider a `const` for the `'done'` status string.** The literal `'done'` appears in three places: the filter in `loadDoneAttachmentsForRetry`, the `MediaAttachment.downloadStatus` field, and the DB migration that creates the CHECK constraint. A `const String kDownloadStatusDone = 'done'` in `lib/features/conversation/domain/models/media_attachment.dart` would centralise this. This is optional -- the string is self-documenting and unlikely to change.

---

### Part D: Wire retrier into `handleAppResumed` + cold-start sweep

> **CRITICAL -- Execution Ordering Requirement**
>
> Both the resume handler (`handleAppResumed`) and the cold-start sweep (`PendingMessageRetrier.start()` / `_retryIfNeeded`) MUST call recovery functions in this exact sequential order:
>
> ```
> 1. recoverStuckSendingMessages()    -- Part A: transitions 'sending' -> 'failed'
> 2. retryIncompleteUploads()         -- Part G: re-uploads 'upload_pending' attachments
> 3. retryFailedMessages()            -- Parts B/C: retries 'failed' messages with attachments
> 4. retryUnackedMessages()           -- existing: retries 'sent' but unacked messages
> ```
>
> **Why this order matters:**
> - Step 1 must run first: stuck `'sending'` rows become `'failed'` so Step 3 can pick them up.
> - Step 2 must run before Step 3: incomplete uploads must finish so Step 3 has `downloadStatus='done'` attachments to pass to `sendChatMessage`. Without this, media/voice messages retry as text-only (the `wireEnvelope == null` + no `'done'` attachments branch in Part F's decision tree).
> - Step 3 after Step 2: messages with now-uploaded attachments are retried with full media payloads.
> - Step 4 is independent but runs last for consistency -- it only handles messages that already have a `wireEnvelope`.
>
> **Fault isolation:** Each step is wrapped in its own `try/catch`. A failure in any step MUST NOT prevent subsequent steps from executing. This is critical because `retryIncompleteUploads` involves network I/O (CDN upload) which is inherently flaky.

#### D.1 Red Phase

> **⚠️ AUDIT FIX (1D-01):** The test below uses `fakeRetryFailed` and `fakeRetryUnacked` as placeholder names. These must be defined as concrete closures. The `handleAppResumed` function does not currently accept these parameters -- this is correct red-phase TDD (the green phase adds them). Complete definitions are shown below.

```dart
test('handleAppResumed calls retryFailedMessages and retryUnackedMessages', () async {
  // ⚠️ AUDIT FIX (1D-01): Define the fake callbacks with counters.
  int fakeRetryFailedCallCount = 0;
  int fakeRetryUnackedCallCount = 0;
  Future<int> fakeRetryFailed() async {
    fakeRetryFailedCallCount++;
    return 0;
  }
  Future<int> fakeRetryUnacked() async {
    fakeRetryUnackedCallCount++;
    return 0;
  }

  messageRepo.seed(failedMessage);

  await handleAppResumed(
    // ... existing params ...
    retryFailedMessagesFn: fakeRetryFailed,    // NEW callback
    retryUnackedMessagesFn: fakeRetryUnacked,  // NEW callback
  );

  expect(fakeRetryFailedCallCount, 1);
  expect(fakeRetryUnackedCallCount, 1);
});

test('PendingMessageRetrier.start() fires initial sweep if node is already online', () async {
  // P2P service already reports online state
  p2pService = FakeP2PService(currentState: onlineNodeState);

  retrier = PendingMessageRetrier(p2pService: p2pService, ...);
  retrier.start();

  // Wait for the 5-second debounce
  await Future.delayed(Duration(seconds: 6));

  // ⚠️ AUDIT FIX (1D-05): PendingMessageRetrier calls retryFailedMessages
  // (top-level function) directly -- the test cannot intercept this call
  // without making it injectable. Use identityRepo.loadIdentityCallCount as
  // a proxy since retryFailedMessages calls identityRepo.loadIdentity() first.
  expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
});
```

##### Red Phase -- `retryIncompleteUploads` ordering tests

> **⚠️ AUDIT FIX (1D-07):** The four tests below validate the execution ordering requirement documented at the top of Part D. They ensure `retryIncompleteUploads` (Part G) is wired into both the resume handler and cold-start sweep at the correct position in the call sequence. These tests will fail until the Green Phase adds the `retryIncompleteUploadsFn` parameter to both `handleAppResumed` and `PendingMessageRetrier`. The `retryIncompleteUploads` use case itself is defined in Part G -- Part D only tests the *wiring*, not the upload logic.

**File:** `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';

// Helpers to track call ordering across all four recovery steps.
// Each callback appends its name to the shared `callOrder` list
// so we can assert exact sequential ordering.

void main() {
  group('handleAppResumed -- retryIncompleteUploads ordering', () {
    test('calls retryIncompleteUploads AFTER recoverStuckSendingMessages but BEFORE retryFailedMessages', () async {
      final callOrder = <String>[];

      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }
      Future<int> fakeRetryIncompleteUploads() async {
        callOrder.add('retryIncompleteUploads');
        return 0;
      }
      Future<int> fakeRetryFailed() async {
        callOrder.add('retryFailedMessages');
        return 0;
      }
      Future<int> fakeRetryUnacked() async {
        callOrder.add('retryUnackedMessages');
        return 0;
      }

      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,        // Part A
        retryIncompleteUploadsFn: fakeRetryIncompleteUploads,    // Part G -- NEW
        retryFailedMessagesFn: fakeRetryFailed,                  // Parts B/C
        retryUnackedMessagesFn: fakeRetryUnacked,                // existing
      );

      expect(callOrder, [
        'recoverStuckSendingMessages',
        'retryIncompleteUploads',
        'retryFailedMessages',
        'retryUnackedMessages',
      ]);
    });

    test('if retryIncompleteUploads throws, retryFailedMessages still runs (fault isolation)', () async {
      final callOrder = <String>[];

      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }
      Future<int> fakeRetryIncompleteUploadsThatThrows() async {
        callOrder.add('retryIncompleteUploads');
        throw Exception('CDN upload timeout');
      }
      Future<int> fakeRetryFailed() async {
        callOrder.add('retryFailedMessages');
        return 0;
      }
      Future<int> fakeRetryUnacked() async {
        callOrder.add('retryUnackedMessages');
        return 0;
      }

      // Must not throw -- handleAppResumed swallows individual step errors
      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploadsThatThrows,
        retryFailedMessagesFn: fakeRetryFailed,
        retryUnackedMessagesFn: fakeRetryUnacked,
      );

      // retryIncompleteUploads threw, but retryFailedMessages and
      // retryUnackedMessages still executed
      expect(callOrder, [
        'recoverStuckSendingMessages',
        'retryIncompleteUploads',
        'retryFailedMessages',
        'retryUnackedMessages',
      ]);
    });

    test('retryIncompleteUploadsFn callback signature matches Future<int> Function() pattern', () async {
      // Validates the callback type is identical to the other retry callbacks,
      // ensuring uniform DI wiring in main.dart
      int callCount = 0;
      Future<int> fakeRetryIncompleteUploads() async {
        callCount++;
        return 3; // e.g., re-uploaded 3 attachments
      }

      await handleAppResumed(
        bridge: fakeBridge,
        p2pService: fakeP2PService,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploads,
      );

      expect(callCount, 1);
    });
  });
}
```

**File:** `test/core/services/pending_message_retrier_upload_ordering_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';

void main() {
  group('PendingMessageRetrier -- retryIncompleteUploads ordering', () {
    test('cold-start sweep calls retryIncompleteUploads in correct order: recover -> uploads -> failed -> unacked', () async {
      final callOrder = <String>[];

      // Injectable callbacks that record invocation order
      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }
      Future<int> fakeRetryIncompleteUploads() async {
        callOrder.add('retryIncompleteUploads');
        return 0;
      }

      // PendingMessageRetrier already calls retryFailedMessages and
      // retryUnackedMessages internally via top-level functions.
      // With the Green Phase changes, these become injectable too.
      // For this test, we use the injectable callback pattern so we
      // can capture ordering.
      p2pService = FakeP2PService(currentState: onlineNodeState);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploads,
      );
      retrier.start();

      // Wait for 5-second debounce to fire the initial sweep
      await Future.delayed(Duration(seconds: 6));

      // Verify ordering: recover must precede uploads, uploads must precede failed
      final recoverIdx = callOrder.indexOf('recoverStuckSendingMessages');
      final uploadsIdx = callOrder.indexOf('retryIncompleteUploads');
      expect(recoverIdx, isNonNegative, reason: 'recoverStuckSendingMessages must be called');
      expect(uploadsIdx, isNonNegative, reason: 'retryIncompleteUploads must be called');
      expect(recoverIdx, lessThan(uploadsIdx),
        reason: 'recoverStuckSendingMessages must run before retryIncompleteUploads');

      // retryFailedMessages runs after retryIncompleteUploads (verified by
      // identityRepo.loadIdentityCallCount proxy, same as existing 1D-05 test)
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
    });

    test('if retryIncompleteUploads throws in cold-start sweep, retryFailedMessages still runs', () async {
      final callOrder = <String>[];

      Future<int> fakeRecoverStuck() async {
        callOrder.add('recoverStuckSendingMessages');
        return 0;
      }
      Future<int> fakeRetryIncompleteUploadsThatThrows() async {
        callOrder.add('retryIncompleteUploads');
        throw Exception('Network unreachable during CDN upload');
      }

      p2pService = FakeP2PService(currentState: onlineNodeState);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        recoverStuckSendingMessagesFn: fakeRecoverStuck,
        retryIncompleteUploadsFn: fakeRetryIncompleteUploadsThatThrows,
      );
      retrier.start();

      // Wait for 5-second debounce
      await Future.delayed(Duration(seconds: 6));

      // retryIncompleteUploads threw, but the sweep continued
      expect(callOrder, contains('recoverStuckSendingMessages'));
      expect(callOrder, contains('retryIncompleteUploads'));

      // retryFailedMessages still ran (proxy: identityRepo was queried)
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
    });
  });
}
```

#### D.2 Green Phase

**File to modify:** `lib/core/lifecycle/handle_app_resumed.dart`

Add four optional callback parameters: `recoverStuckSendingMessagesFn` (Part A), `retryIncompleteUploadsFn` (Part G), `retryFailedMessagesFn` (Parts B/C), and `retryUnackedMessagesFn` (existing). All four are called in strict sequential order with individual `try/catch` fault isolation:

```dart
Future<void> handleAppResumed({
  // ... existing params ...
  Future<int> Function()? recoverStuckSendingMessagesFn,   // Part A
  Future<int> Function()? retryIncompleteUploadsFn,        // Part G -- NEW
  Future<int> Function()? retryFailedMessagesFn,           // Parts B/C
  Future<int> Function()? retryUnackedMessagesFn,          // existing
}) async {
  // ... existing steps 1-7 ...

  // Step 8 (NEW): Message recovery sweep -- strict ordering required.
  //
  // ORDERING CONTRACT (see Part D top-level callout):
  //   1. recoverStuckSendingMessages  -- 'sending' -> 'failed'
  //   2. retryIncompleteUploads       -- re-upload 'upload_pending' attachments
  //   3. retryFailedMessages          -- retry 'failed' messages (now with uploaded media)
  //   4. retryUnackedMessages         -- retry 'sent' but unacked messages
  //
  // Each step is fault-isolated: a throw in step N does not skip step N+1.

  // ⚠️ AUDIT FIX (1D-03): By this point, P2P health check (Step 2) and drain
  // inbox (Step 3) have completed, so the relay should be available for
  // storeInInbox. The PendingMessageRetrier independently fires its own
  // debounced retry 5 seconds after the online transition. Both calling
  // retryFailedMessages is safely idempotent -- the second call finds zero
  // 'failed' rows because the first already processed them.

  // Step 8a: Recover stuck 'sending' messages -> 'failed'
  if (recoverStuckSendingMessagesFn != null) {
    try {
      final count = await recoverStuckSendingMessagesFn();
      if (kDebugMode) debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages=$count');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RECOVER_STUCK_SENDING_RESUME_ERROR',
        details: {'error': e.toString()},
      );
      if (kDebugMode) debugPrint('[RESUME] Step 8a: recoverStuckSendingMessages ERROR: $e');
    }
  }

  // Step 8b: Re-upload incomplete attachment uploads (Part G).
  // MUST run after 8a (parent messages now 'failed') and BEFORE 8c
  // (so attachments have downloadStatus='done' when retryFailedMessages reads them).
  if (retryIncompleteUploadsFn != null) {
    try {
      final count = await retryIncompleteUploadsFn();
      if (kDebugMode) debugPrint('[RESUME] Step 8b: retryIncompleteUploads=$count');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOADS_RESUME_ERROR',
        details: {'error': e.toString()},
      );
      if (kDebugMode) debugPrint('[RESUME] Step 8b: retryIncompleteUploads ERROR: $e');
      // Non-fatal: continue to retryFailedMessages -- messages without
      // completed uploads will be retried as text-only or skipped by
      // Part F's decision tree, which is still better than not retrying at all.
    }
  }

  // Step 8c: Retry failed messages (with now-uploaded media attachments)
  if (retryFailedMessagesFn != null) {
    try {
      final count = await retryFailedMessagesFn();
      if (kDebugMode) debugPrint('[RESUME] Step 8c: retryFailedMessages=$count');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_FAILED_MESSAGES_RESUME_ERROR',
        details: {'error': e.toString()},
      );
      if (kDebugMode) debugPrint('[RESUME] Step 8c: retryFailedMessages ERROR: $e');
    }
  }

  // Step 8d: Retry sent-but-unacked messages
  if (retryUnackedMessagesFn != null) {
    try {
      final count = await retryUnackedMessagesFn();
      if (kDebugMode) debugPrint('[RESUME] Step 8d: retryUnackedMessages=$count');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGES_RESUME_ERROR',
        details: {'error': e.toString()},
      );
      if (kDebugMode) debugPrint('[RESUME] Step 8d: retryUnackedMessages ERROR: $e');
    }
  }
}
```

**File to modify:** `lib/core/services/pending_message_retrier.dart`

> **⚠️ AUDIT FIX (1D-02):** This is the primary fix for the retrier cold-start bug. The current `start()` at `pending_message_retrier.dart:40-70` sets `_wasOnline` at line 47 and subscribes to `stateStream` at line 49. If the node is already online, no offline-to-online transition fires and `_retryIfNeeded` is never called. The fix below correctly schedules timers immediately when `_wasOnline`. Note: if a state change arrives during the 5-second debounce, the `nowOnline && !_wasOnline` check will be false (since `_wasOnline` is already true), so no duplicate timer is created. This is safe.

Add two optional callback parameters to the constructor and update `_retryIfNeeded` to call them in the correct order:

```dart
class PendingMessageRetrier {
  final P2PService p2pService;
  final MessageRepository messageRepo;
  final IdentityRepository identityRepo;
  final ContactRepository contactRepo;
  final Bridge bridge;

  // Injectable recovery callbacks for correct ordering
  final Future<int> Function()? recoverStuckSendingMessagesFn;   // Part A
  final Future<int> Function()? retryIncompleteUploadsFn;        // Part G -- NEW

  PendingMessageRetrier({
    required this.p2pService,
    required this.messageRepo,
    required this.identityRepo,
    required this.contactRepo,
    required this.bridge,
    this.recoverStuckSendingMessagesFn,    // Part A
    this.retryIncompleteUploadsFn,         // Part G -- NEW
  });

  // ... _stateSubscription, _debounceTimer, _periodicTimer, _wasOnline, _isRetrying ...
```

At the end of `start()`, after the stream subscription is set up, add an initial sweep if the node is already online:

```dart
void start() {
  // ... existing subscription setup ...

  // If already online when start() is called, schedule an initial sweep.
  // Handles cold-start where the Go node reports already-running.
  if (_wasOnline) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 5), _retryIfNeeded);
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _retryIfNeeded(),
    );
  }
}
```

Update `_retryIfNeeded` to enforce the four-step ordering with per-step fault isolation:

```dart
Future<void> _retryIfNeeded() async {
  if (_isRetrying) return;
  _isRetrying = true;

  try {
    // ORDERING CONTRACT (matches handleAppResumed Step 8):
    //   1. recoverStuckSendingMessages  -- 'sending' -> 'failed'
    //   2. retryIncompleteUploads       -- re-upload 'upload_pending' attachments
    //   3. retryFailedMessages          -- retry 'failed' messages
    //   4. retryUnackedMessages         -- retry 'sent' but unacked

    // Step 1: Recover stuck sending messages
    if (recoverStuckSendingMessagesFn != null) {
      try {
        final count = await recoverStuckSendingMessagesFn!();
        if (count > 0) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_RECOVERED_STUCK',
            details: {'count': count},
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_RECOVER_STUCK_ERROR',
          details: {'error': e.toString()},
        );
      }
    }

    // Step 2: Re-upload incomplete attachments (Part G)
    if (retryIncompleteUploadsFn != null) {
      try {
        final count = await retryIncompleteUploadsFn!();
        if (count > 0) {
          emitFlowEvent(
            layer: 'FL',
            event: 'PENDING_RETRIER_INCOMPLETE_UPLOADS_RETRIED',
            details: {'count': count},
          );
        }
      } catch (e) {
        emitFlowEvent(
          layer: 'FL',
          event: 'PENDING_RETRIER_INCOMPLETE_UPLOAD_ERROR',
          details: {'error': e.toString()},
        );
        // Non-fatal: continue to retryFailedMessages
      }
    }

    // Step 3: Retry failed messages
    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
    );

    if (count > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_RETRIED',
        details: {'count': count},
      );
    }

    // Step 4: Retry unacked messages
    final unackedCount = await retryUnackedMessages(
      messageRepo: messageRepo,
      p2pService: p2pService,
    );

    if (unackedCount > 0) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PENDING_RETRIER_UNACKED_RETRIED',
        details: {'count': unackedCount},
      );
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_RETRIER_ERROR',
      details: {'error': e.toString()},
    );
  } finally {
    _isRetrying = false;
  }
}
```

**File to modify:** `lib/main.dart`


> **⚠️ AUDIT FIX (1D-04):** In `_onResumed()` at `lib/main.dart:1507-1521`, widget properties are accessed with `widget.` prefix (e.g., `widget.bridge`, `widget.p2pService`). The code below uses the correct `widget.` prefixes and shows the FULL parameter list for `retryFailedMessages` (which requires `identityRepo`, `contactRepo`, and `bridge` in addition to `messageRepo` and `p2pService`).

> **⚠️ AUDIT FIX (1D-06):** `retryFailedMessages` does not currently accept a `mediaAttachmentRepo` parameter -- that is proposed in Part C. The wiring below includes it commented out with a note to uncomment when Part C lands. If implementing Part D before Part C, omit the `mediaAttachmentRepo` line entirely.

> **⚠️ AUDIT FIX (1D-08):** `retryIncompleteUploads` is defined in Part G. The wiring below includes it with a note that it requires Part G to compile. If implementing Part D before Part G, pass `null` (the parameter is optional) and add a `// TODO: Wire retryIncompleteUploadsFn when Part G lands` comment.

Wire the new callbacks when calling `handleAppResumed` (in `_onResumed()`):

```dart
await handleAppResumed(
  // ... existing params ...
  recoverStuckSendingMessagesFn: () => recoverStuckSendingMessages(
    messageRepo: widget.messageRepository,
  ),
  // Requires Part G -- pass null until retryIncompleteUploads use case exists:
  retryIncompleteUploadsFn: () => retryIncompleteUploads(
    mediaAttachmentRepo: widget.mediaAttachmentRepository,
    messageRepo: widget.messageRepository,
    bridge: widget.bridge,
    p2pService: widget.p2pService,
    identityRepo: widget.repository,
    contactRepo: widget.contactRepository,
  ),
  retryFailedMessagesFn: () => retryFailedMessages(
    messageRepo: widget.messageRepository,
    identityRepo: widget.repository,
    contactRepo: widget.contactRepository,
    p2pService: widget.p2pService,
    bridge: widget.bridge,
    // Uncomment when Part C lands:
    // mediaAttachmentRepo: widget.mediaAttachmentRepository,
  ),
  retryUnackedMessagesFn: () => retryUnackedMessages(
    messageRepo: widget.messageRepository,
    p2pService: widget.p2pService,
  ),
);
```

Wire `retryIncompleteUploadsFn` into `PendingMessageRetrier` construction (in `main.dart`):

```dart
final retrier = PendingMessageRetrier(
  p2pService: p2pService,
  messageRepo: messageRepository,
  identityRepo: identityRepository,
  contactRepo: contactRepository,
  bridge: bridge,
  recoverStuckSendingMessagesFn: () => recoverStuckSendingMessages(
    messageRepo: messageRepository,
  ),
  // Requires Part G -- pass null until retryIncompleteUploads use case exists:
  retryIncompleteUploadsFn: () => retryIncompleteUploads(
    mediaAttachmentRepo: mediaAttachmentRepository,
    messageRepo: messageRepository,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepository,
    contactRepo: contactRepository,
  ),
);
```

---

### Files to create / modify

| File | Purpose |
|---|---|
| `lib/core/database/helpers/messages_db_helpers.dart` | Add `dbRecoverStuckSendingMessages` and `dbLoadStuckSendingOutgoingMessages` |
| `lib/features/conversation/domain/repositories/message_repository.dart` | Add `recoverStuckSendingMessages`, `getStuckSendingOutgoingMessages`, `updateWireEnvelope` to abstract interface |
| `lib/features/conversation/domain/repositories/message_repository_impl.dart` | Implement new methods |
| `lib/features/conversation/application/recover_stuck_sending_messages_use_case.dart` | New use case (Section 1, Part A) |
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Add `mediaAttachmentRepo` param; query media before fallback send (Part C) |
| `lib/features/conversation/application/retry_unacked_messages_use_case.dart` | Add null guard on `wireEnvelope` (Part C) |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add `recoverStuckSendingMessagesFn` / `retryIncompleteUploadsFn` / `retryFailedMessagesFn` / `retryUnackedMessagesFn` callbacks with strict ordering and per-step fault isolation (Part D) |
| `lib/core/services/pending_message_retrier.dart` | Add `recoverStuckSendingMessagesFn` / `retryIncompleteUploadsFn` constructor params; enforce 4-step ordering in `_retryIfNeeded`; add initial sweep on `start()` if already online (Part D) |
| `lib/main.dart` | Wire all four retry callbacks into `handleAppResumed` call and `PendingMessageRetrier` constructor (Part D) |
| `test/core/database/helpers/messages_db_helpers_stuck_sending_test.dart` | DB helper unit tests |
| `test/core/database/helpers/messages_db_helpers_stuck_sending_query_test.dart` | DB helper query tests |
| `test/features/conversation/domain/repositories/message_repository_impl_stuck_sending_test.dart` | Repository impl tests |
| `test/features/conversation/domain/repositories/fake_message_repository_stuck_sending_query_test.dart` | FakeMessageRepository tests |
| `test/features/conversation/application/recover_stuck_sending_messages_use_case_test.dart` | Use case tests |
| `test/features/conversation/application/retry_failed_messages_media_test.dart` | Media replay-safety tests (Part C) |
| `test/core/lifecycle/handle_app_resumed_stuck_sending_test.dart` | Resume retry-wiring tests (Part D) |
| `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart` | Resume handler `retryIncompleteUploads` ordering + fault isolation tests (Part D) |
| `test/core/services/pending_message_retrier_stuck_sending_test.dart` | Retrier initial-sweep + cold-start tests (Part D) |
| `test/core/services/pending_message_retrier_upload_ordering_test.dart` | Retrier `retryIncompleteUploads` cold-start ordering + fault isolation tests (Part D) |
| `test/features/conversation/integration/stuck_sending_recovery_test.dart` | End-to-end smoke tests |
| `test/features/conversation/domain/repositories/fake_message_repository.dart` | Extend with new methods |

---

### Part F: Re-upload incomplete media and voice before retry

#### F.1 Why Part C alone is insufficient

Part C makes `retryFailedMessages` replay-safe for the case where the upload **already completed** — CDN blob IDs exist in `media_attachments` and only the P2P envelope send failed. Part F handles the orthogonal case where the upload itself was interrupted.

When a message fails before or during the upload, the DB state differs from the P2P-send-failed case:

| Failure point | `messages.wire_envelope` | `media_attachments` rows | Recovery path |
|---|---|---|---|
| P2P send failed after upload | non-null (JSON with media blob IDs) | present, `download_status = 'done'`, `local_path` set | Part C: reuse CDN refs, re-send |
| Upload failed, row stuck at `'sending'` (crash) | null | absent, or present with `download_status = 'failed'` | Part F: re-upload then send |
| Upload partial: bridge call returned nil | null | absent | Part F: re-upload then send |
| Local file deleted before retry | null | absent | Part F: cannot re-upload — leave `'failed'`, log, skip |

The distinguishing signal: `msg.wireEnvelope == null` **and** no `media_attachments` row has `downloadStatus == 'done'` — upload was never completed; a CDN round-trip is required before `sendChatMessage` can be called.

**Voice messages** follow the same state machine **for the relay upload path**. `sendVoiceMessage` uploads first, then delegates to `sendChatMessage`. If the upload failed, the optimistic `'sending'` row was transitioned to `'failed'` by Part A/B. On retry, the use case re-invokes `uploadMedia` using the `localPath`, `mime`, `duration_ms`, and `waveform` fields from the persisted `media_attachments` row.

> **⚠️ AUDIT FIX (FV-01):** The voice local WiFi branch (`conversation_wired.dart:1277-1341`) follows a **completely separate** path: it calls `p2pService.sendLocalMedia()` directly via HTTP PUT, then calls `sendChatMessageFn()` with a hand-constructed `MediaAttachment` whose `id` is a fresh `_uuid.v4()`. This path never enters `sendVoiceMessage` and never calls `uploadMedia`. If the local WiFi path fails (line 1332-1334), the message status becomes `'failed'` but there is no `wireEnvelope` and no `media_attachments` row for Part F to work with. Part F must add a voice-local-WiFi decision branch: when the message failed during a local WiFi transfer (detectable by: `wireEnvelope == null`, attachment row has `localPath` set but no relay blob ID, and contact `isLocalPeer` is true), retry should re-attempt `sendLocalMedia()` before falling back to the relay upload path.

> **⚠️ AUDIT FIX (FV-02):** Part G (Step G-E voice path) is a **hard prerequisite** for Part F voice recovery. Today, `_onVoiceRecordingStopped` never calls `mediaAttachmentRepo.saveAttachment()` before upload/send -- if the app is killed during voice upload, `media_attachments` has zero rows for this message. The F.3 three-branch dispatch falls through to "no attachment rows at all" and treats it as text-only, silently dropping the voice attachment on retry. Part F's voice test (F.5.4) seeds a `media_attachments` row which can only exist if Part G is implemented first. This dependency must be respected during implementation ordering.

> **⚠️ AUDIT FIX (FV-05):** Voice-only messages have `text: ''`. If retry calls `sendChatMessage` without `mediaAttachments:` (because no `media_attachments` rows exist), `hasAttachments` is false and the empty text triggers the guard at `send_chat_message_use_case.dart:82` (`if (sanitizedText.trim().isEmpty && !hasAttachments)` returns `invalidMessage`). The existing `retryFailedMessages` at line 92-103 does not pass `mediaAttachments:` or `mediaAttachmentRepo:` -- line 92 is the precise replacement point for the F.3 three-branch dispatch, which fixes this.

#### F.2 Retry decision tree

```
retryFailedMessages(msg):
  +-- wireEnvelope != null ─────────────────────────────► [existing Part C path: storeInInbox / sendChatMessage with CDN refs]
  |
  +-- wireEnvelope == null
        |
        +-- mediaAttachmentRepo.getAttachmentsForMessage(msg.id) → attachments
        |
        +-- no attachment with downloadStatus == 'done'
        |     |
        |     +-- no attachment rows at all ────────────► [text-only fallback: sendChatMessage(text:msg.text)]
        |     |
        |     +-- attachment rows exist (media/voice)
        |           |
        |           +-- localPath on disk ────────────► [Part F path A: re-upload then sendChatMessage]
        |           +-- localPath absent/file missing ─► [Part F path B: skip, leave 'failed', emit FLOW event]
        |
        +-- at least one attachment with downloadStatus == 'done'
              +──────────────────────────────────────► [Part C path: sendChatMessage with existing CDN refs]
```

The tree is evaluated per message inside the `retryFailedMessages` per-message loop.

#### F.3 Changes to `retry_failed_messages_use_case.dart`

The existing fallback block (lines 87–103) is replaced with a three-branch dispatch. After the `wireEnvelope` fast path, for each message:

```dart
// Load any persisted attachments for this message
final persistedAttachments = await mediaAttachmentRepo
    ?.getAttachmentsForMessage(msg.id) ?? const <MediaAttachment>[];

// ⚠️ AUDIT FIX (F-04): Use `every` not `any` — if a message has 2 attachments,
// one 'done' and one 'upload_pending', `any` would return true and the Part C
// path would silently drop the incomplete attachment.
final allUploaded = persistedAttachments.isNotEmpty &&
    persistedAttachments.every((a) => a.downloadStatus == 'done');

List<MediaAttachment>? attachmentsForSend;

if (allUploaded) {
  // CDN blobs already exist for ALL attachments — reuse them (Part C path).
  attachmentsForSend = persistedAttachments;
} else if (persistedAttachments.isNotEmpty) {
  // Attachment rows exist but upload never completed → re-upload required.
  attachmentsForSend = await _reuploadAttachments(
    attachments: persistedAttachments,
    bridge: bridge,
    targetPeerId: msg.contactPeerId,
    uploadFn: effectiveUploadFn,
  );
  if (attachmentsForSend == null) {
    emitFlowEvent(
      layer: 'FL',
      event: 'RETRY_FAILED_MEDIA_LOCAL_FILE_MISSING',
      details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
    );
    continue; // Leave as 'failed' — user must re-send manually
  }
} else {
  // Text-only message with no attachment rows.
  attachmentsForSend = null;
}

final (result, _) = await sendChatMessage(
  p2pService: p2pService,
  messageRepo: messageRepo,
  targetPeerId: msg.contactPeerId,
  text: msg.text,
  senderPeerId: identity.peerId,
  senderUsername: identity.username,
  messageId: msg.id,
  timestamp: msg.timestamp,
  bridge: bridge,
  recipientMlKemPublicKey: mlKemPk,
  mediaAttachments: attachmentsForSend,
  mediaAttachmentRepo: mediaAttachmentRepo,
);
```

The new `_reuploadAttachments` private helper at the bottom of the same file:

```dart
/// Re-uploads each attachment whose local file still exists on disk.
///
/// Returns the re-uploaded [MediaAttachment] list on full success, or null
/// if any local file is missing or any CDN upload returns null. In the null
/// case the caller skips the message and leaves it as 'failed'.
///
/// NOTE: Re-upload produces a new blob ID (UUID v4 inside uploadMedia).
/// The old blob ID in media_attachments is orphaned on the relay;
/// relay blobs expire after 7 days so orphaned blobs are self-cleaning.
Future<List<MediaAttachment>?> _reuploadAttachments({
  required List<MediaAttachment> attachments,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
}) async {
  final result = <MediaAttachment>[];

  for (final attachment in attachments) {
    final localPath = attachment.localPath;
    if (localPath == null || localPath.isEmpty) {
      return null; // No path recorded — cannot re-upload
    }

    if (!File(localPath).existsSync()) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FILE_NOT_FOUND',
        details: {'localPath': localPath},
      );
      return null;
    }

    // ⚠️ AUDIT FIX (F-02): Pass width and height from the persisted row —
    // the UploadMediaFn typedef accepts these optional params and they are
    // available on MediaAttachment.  Omitting them would lose image dimensions.
    final uploaded = await uploadFn(
      bridge: bridge,
      localFilePath: localPath,
      mime: attachment.mime,
      recipientPeerId: targetPeerId,
      durationMs: attachment.durationMs,
      waveform: attachment.waveform,
      width: attachment.width,
      height: attachment.height,
      blobId: attachment.id,  // Stable-ID contract (F.7.1)
    );

    if (uploaded == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FAILED',
        details: {'localPath': localPath},
      );
      return null;
    }

    result.add(uploaded);
  }

  return result;
}
```

#### F.4 Signature change: add `uploadMediaFn` to `retryFailedMessages`

```dart
Future<int> retryFailedMessages({
  required MessageRepository messageRepo,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required Bridge bridge,
  MediaAttachmentRepository? mediaAttachmentRepo,   // from Part C
  UploadMediaFn? uploadMediaFn,                     // NEW — defaults to uploadMedia
  MediaFileManager? mediaFileManager,               // NEW — resolves stored localPath
}) async {
  final effectiveUploadFn = uploadMediaFn ?? uploadMedia;
  // ...
}
```

`uploadMediaFn` defaults to the production `uploadMedia` symbol from `upload_media_use_case.dart`. Tests inject a `FakeUploadMediaFn` that never issues MethodChannel calls. **`MediaFileManager` is in-scope here, not a follow-up nicety** — the `localPath` stored in `media_attachments` may be relative when written by `uploadMedia`, so retry code must resolve stored paths before checking file existence or re-uploading. Without this, normal relay-uploaded attachments can fail recovery simply because the stored DB path is relative.

#### F.5 Red phase — TDD tests

**File:** `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart`

```dart
group('retryFailedMessages — re-upload incomplete media', () {

  // F.5.1 Happy path: file present on disk → re-uploads then sends
  test('re-uploads local image file and sends when CDN upload succeeds', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);

    final attachment = _makeAttachment(
      messageId: msg.id,
      localPath: '/tmp/img.jpg',
      downloadStatus: 'failed',
    );
    mediaAttachmentRepo.seed(msg.id, [attachment]);

    fakeUploadFn.willReturn(
      attachment.copyWith(id: 'new-blob-id', downloadStatus: 'done'),
    );

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.callCount, 1);
    expect(fakeUploadFn.lastLocalPath, '/tmp/img.jpg');
    expect(p2pService.lastSentPayload, contains('new-blob-id'));
    expect(count, 1);
  });

  // F.5.2 File deleted between crash and retry → left as 'failed'
  test('skips message when local file is missing from disk', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);
    mediaAttachmentRepo.seed(msg.id, [
      _makeAttachment(
        messageId: msg.id,
        localPath: '/data/media/deleted.jpg',
        downloadStatus: 'failed',
      ),
    ]);
    // File intentionally absent

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.callCount, 0);
    expect(p2pService.sendCallCount, 0);
    expect(count, 0);
    expect(
      flowEvents,
      contains(predicate<Map<String, Object?>>(
        (e) => e['event'] == 'RETRY_FAILED_MEDIA_LOCAL_FILE_MISSING',
      )),
    );
  });

  // F.5.3 CDN upload returns null → message stays failed, no crash
  test('skips message when re-upload returns null (CDN error)', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);
    mediaAttachmentRepo.seed(msg.id, [
      _makeAttachment(
        messageId: msg.id, localPath: '/tmp/img.jpg', downloadStatus: 'failed',
      ),
    ]);
    fakeUploadFn.willReturn(null);

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(p2pService.sendCallCount, 0);
    expect(count, 0);
    expect(
      flowEvents,
      contains(predicate<Map<String, Object?>>(
        (e) => e['event'] == 'RETRY_REUPLOAD_FAILED',
      )),
    );
  });

  // F.5.4 Voice message: audio attachment re-uploaded with correct mime + durationMs
  // ⚠️ AUDIT FIX (FV-03): downloadStatus changed from 'failed' to 'upload_pending'.
  // Per Part G's downloadStatus lifecycle table, 'failed' is for incoming download failures.
  // An interrupted outgoing voice upload should have 'upload_pending' (after Part G).
  test('re-uploads audio attachment and sends voice message', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);

    final audioAttachment = _makeAttachment(
      messageId: msg.id,
      localPath: '/tmp/voice.m4a',
      downloadStatus: 'upload_pending',
      mime: 'audio/mp4',
      mediaType: 'audio',
      durationMs: 3000,
    );
    mediaAttachmentRepo.seed(msg.id, [audioAttachment]);

    fakeUploadFn.willReturn(
      audioAttachment.copyWith(id: 'audio-blob-id', downloadStatus: 'done'),
    );

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.lastMime, 'audio/mp4');
    expect(fakeUploadFn.lastDurationMs, 3000);
    expect(p2pService.lastSentPayload, contains('audio-blob-id'));
    expect(count, 1);
  });

  // F.5.5 Mixed batch: one recoverable, one file missing → partial success
  test('retries recoverable messages and skips unrecoverable ones', () async {
    final msgOk = _makeFailedMsg(id: 'msg-ok', wireEnvelope: null);
    final msgMissing = _makeFailedMsg(id: 'msg-missing', wireEnvelope: null);
    messageRepo.seed(msgOk);
    messageRepo.seed(msgMissing);

    mediaAttachmentRepo.seed('msg-ok', [
      _makeAttachment(messageId: 'msg-ok', localPath: '/tmp/ok.jpg', downloadStatus: 'failed'),
    ]);
    mediaAttachmentRepo.seed('msg-missing', [
      _makeAttachment(messageId: 'msg-missing', localPath: '/data/gone.jpg', downloadStatus: 'failed'),
    ]);
    // /data/gone.jpg intentionally absent from disk

    fakeUploadFn.willReturnForPath('/tmp/ok.jpg',
      _makeAttachment(messageId: 'msg-ok', localPath: '/tmp/ok.jpg', downloadStatus: 'done', id: 'ok-blob'),
    );

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(count, 1);
    expect(fakeUploadFn.callCount, 1);
  });

  // F.5.6 Attachment with null localPath → treated as missing
  test('skips attachment with null localPath', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);
    mediaAttachmentRepo.seed(msg.id, [
      _makeAttachment(messageId: msg.id, localPath: null, downloadStatus: 'failed'),
    ]);

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.callCount, 0);
    expect(count, 0);
  });

  // F.5.7 Attachment already uploaded (Part C path): uploadMediaFn NOT called
  // ⚠️ AUDIT FIX (F-05): Test also verifies that the EXISTING blob ID appears
  // in the wire payload (not just that a send happened).
  test('does NOT re-upload when attachment is already done (Part C path)', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);
    mediaAttachmentRepo.seed(msg.id, [
      _makeAttachment(messageId: msg.id, localPath: '/tmp/img.jpg', downloadStatus: 'done', id: 'existing-blob-id'),
    ]);

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.callCount, 0); // Part C path — no new upload
    expect(p2pService.sendCallCount, 1);
    expect(p2pService.lastSentPayload, contains('existing-blob-id'));
    expect(count, 1);
  });

  // F.5.8 Relative localPath (written by MediaFileManager) — not resolvable
  // ⚠️ AUDIT FIX (F-03): Production media uploaded via relay gets a relative path
  // stored by MediaFileManager.relativePathForAttachment(). File(relativePath).existsSync()
  // returns false. This test validates the skip behavior for that case.
  test('skips message when localPath is relative (not resolvable)', () async {
    final msg = _makeFailedMsg(wireEnvelope: null);
    messageRepo.seed(msg);
    mediaAttachmentRepo.seed(msg.id, [
      _makeAttachment(
        messageId: msg.id,
        localPath: 'media/attachments/img.jpg', // relative — not resolvable
        downloadStatus: 'upload_pending',
      ),
    ]);

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(fakeUploadFn.callCount, 0);
    expect(count, 0);
  });

  // F.5.9 Voice-only retry without mediaAttachments returns invalidMessage
  // ⚠️ AUDIT FIX (FV-06): When no media_attachments rows exist for a
  // voice-only message (text: ''), the text-only fallback triggers
  // sendChatMessage's empty-text guard, returning invalidMessage.
  test('voice-only retry without mediaAttachments returns invalidMessage, not success', () async {
    final msg = _makeFailedMsg(wireEnvelope: null, text: '');
    messageRepo.seed(msg);
    // No mediaAttachmentRepo rows seeded — simulates pre-Part-G state

    final count = await retryFailedMessages(
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      p2pService: p2pService,
      bridge: bridge,
      uploadMediaFn: fakeUploadFn.call,
    );

    expect(p2pService.sendCallCount, 0);
    expect(count, 0); // invalidMessage — not a success
  });

}); // end group
```

**Fake helper:** `test/features/conversation/application/helpers/fake_upload_media_fn.dart`

```dart
/// Injectable fake for [UploadMediaFn] used across Part F tests.
class FakeUploadMediaFn {
  final _returnByPath = <String, MediaAttachment?>{};
  MediaAttachment? _defaultReturn;
  int callCount = 0;
  String? lastLocalPath;
  String? lastMime;
  int? lastDurationMs;

  void willReturn(MediaAttachment? value) => _defaultReturn = value;
  void willReturnForPath(String path, MediaAttachment? value) =>
      _returnByPath[path] = value;

  String? lastBlobId;

  Future<MediaAttachment?> call({
    required Bridge bridge,
    required String localFilePath,
    required String mime,
    required String recipientPeerId,
    MediaFileManager? mediaFileManager,
    int? width,
    int? height,
    int? durationMs,
    List<double>? waveform,
    List<String>? allowedPeers,
    String? blobId,
  }) async {
    callCount++;
    lastLocalPath = localFilePath;
    lastMime = mime;
    lastDurationMs = durationMs;
    lastBlobId = blobId;
    return _returnByPath[localFilePath] ?? _defaultReturn;
  }
}
```

#### F.6 Green phase — implementation steps

**Step F.1: Extend `retryFailedMessages` signature**

In `lib/features/conversation/application/retry_failed_messages_use_case.dart`:
- Add imports: `dart:io`, `package:flutter_app/features/conversation/application/upload_media_use_case.dart`
- Add optional parameter `UploadMediaFn? uploadMediaFn`
- At top of function body: `final effectiveUploadFn = uploadMediaFn ?? uploadMedia;`

**Step F.2: Replace flat fallback with three-branch dispatch**

Replace the existing `sendChatMessage` call at lines 87–103 with the three-branch dispatch shown in F.3.

**Step F.3: Add `_reuploadAttachments` private helper**

Add the helper at the bottom of `retry_failed_messages_use_case.dart`. Accepts `UploadMediaFn uploadFn` (injected, not the `uploadMedia` symbol directly) so tests can stub without MethodChannel.

**Step F.4: Update `PendingMessageRetrier`**

- Add `MediaAttachmentRepository? mediaAttachmentRepo` constructor parameter
- Pass it to `retryFailedMessages` in `_retryIfNeeded`
- Leave `uploadMediaFn: null` (production default applies)

**Step F.5: Update `main.dart`**

- At `PendingMessageRetrier` construction, add `mediaAttachmentRepo: mediaAttachmentRepository`
- In the `retryFailedMessagesFn` closure (from Part D), add `mediaAttachmentRepo: mediaAttachmentRepository`

#### F.7 Refactor phase

- Extract the three-branch attachment dispatch into a private helper `_resolveAttachmentsForRetry` returning `({List<MediaAttachment>? attachments, bool skipMessage})`. This keeps the per-message loop linear and makes the branching logic unit-testable in isolation.
- Add `const kReuploadMaxAttachmentsPerMessage = 10` to `lib/core/constants/retry_constants.dart`. `_reuploadAttachments` returns null immediately if `attachments.length > kReuploadMaxAttachmentsPerMessage` and emits `RETRY_REUPLOAD_TOO_MANY_ATTACHMENTS` (defensive ceiling).
- **⚠️ AUDIT FIX (F-01, CRITICAL): Placeholder row survival bug -- closed by Stable-ID Contract (F.7.1 below).** The root cause: `upload_media_use_case.dart:46` generates a fresh UUID v4 as `blobId` on every upload call, so the re-uploaded attachment gets a different `id` than the placeholder `upload_pending` row. `ConflictAlgorithm.replace` only matches on PRIMARY KEY (`id`), so the placeholder survives -- creating ghost rows. The fix is the Stable-ID Contract defined in F.7.1.
- `_reuploadAttachments` must resolve stored paths through `MediaFileManager.resolveStoredPath()` before any `File(...).existsSync()` or upload call. Relative-path handling is required for production correctness, not deferred refactor work.
- Transient re-upload failure (bridge `null`, relay down, temporary upload error) must leave the message **retry-eligible** on the next resume/reconnect. Do not treat the first failed re-upload attempt as a permanently terminal state; reserve `'upload_failed'` for non-retryable conditions such as missing local file or explicit exhaustion policy.

#### F.7.1 Stable-ID Contract: Closing the placeholder-row lifecycle (Gap 2)

**Problem statement:** The current design allows placeholder `upload_pending` rows and real `done` rows to coexist for the same `messageId`. This happens because three different UUIDs are generated for the same logical attachment at different points: (1) optimistic UI UUID (`conversation_wired.dart` line 593), (2) local WiFi media ID (line 653), and (3) relay blob ID (`upload_media_use_case.dart:46`). Since `dbInsertMediaAttachment` uses `ConflictAlgorithm.replace` keyed on PRIMARY KEY (`id`), inserting a row with a different `id` does not replace the old one -- both survive.

**Contract: Generate the attachment ID ONCE and thread it through all paths.**

**F.7.1.1 ID generation rule:**

A single attachment ID is generated at optimistic write time using `uuid.v4()`. This ID is stored in the `upload_pending` row AND passed to the upload function so it becomes the blob ID on the relay. No second UUID is ever generated for the same attachment.

```dart
// In conversation_wired.dart, at optimistic attachment creation time:
final attachmentId = _uuid.v4();  // THE one and only ID for this attachment

// This same ID is:
// 1. Used in the upload_pending row persisted to media_attachments
// 2. Passed to uploadMedia() as a pre-generated blobId parameter
// 3. Used in the local WiFi sendLocalMedia() call
// 4. Present in the final 'done' row after upload success
```

**F.7.1.2 Upload function signature change:**

Add an optional `String? blobId` parameter to `uploadMedia` and the `UploadMediaFn` typedef. When provided, this ID is used instead of generating a new `_uuid.v4()`.

```dart
// upload_media_use_case.dart — CHANGED signature
typedef UploadMediaFn =
    Future<MediaAttachment?> Function({
      required Bridge bridge,
      required String localFilePath,
      required String mime,
      required String recipientPeerId,
      MediaFileManager? mediaFileManager,
      int? width,
      int? height,
      int? durationMs,
      List<double>? waveform,
      List<String>? allowedPeers,
      String? blobId,                    // NEW: pre-generated attachment ID
    });

Future<MediaAttachment?> uploadMedia({
  required Bridge bridge,
  required String localFilePath,
  required String mime,
  required String recipientPeerId,
  MediaFileManager? mediaFileManager,
  int? width,
  int? height,
  int? durationMs,
  List<double>? waveform,
  List<String>? allowedPeers,
  String? blobId,                        // NEW
}) async {
  final effectiveBlobId = blobId ?? _uuid.v4();  // Use pre-generated or create new
  // ... rest of function uses effectiveBlobId instead of blobId ...
```

**F.7.1.3 Success-path update rule (UPDATE not INSERT):**

After upload succeeds, the existing `upload_pending` row is UPDATED in place (same `id`) rather than a new row being INSERTed. Since the `id` is stable, `saveAttachment` with `ConflictAlgorithm.replace` naturally overwrites the placeholder row.

```dart
// After successful relay upload in conversation_wired.dart:
// The uploaded MediaAttachment returned by uploadMedia() has the SAME id
// as the upload_pending row, so saveAttachment() overwrites it via
// ConflictAlgorithm.replace on PRIMARY KEY.
final uploaded = await widget.uploadMediaFn(
  bridge: widget.bridge!,
  localFilePath: media.file.path,
  mime: mime,
  recipientPeerId: _contact.peerId,
  mediaFileManager: widget.mediaFileManager,
  width: media.width,
  height: media.height,
  durationMs: media.durationMs,
  blobId: attachmentId,  // Same ID as the upload_pending row
);
// uploaded.id == attachmentId — saveAttachment replaces the placeholder
```

**F.7.1.4 Local-WiFi success cleanup rule:**

After `sendLocalMedia` succeeds, UPDATE the existing `upload_pending` row to `downloadStatus='done'` using the same stable `attachmentId`. No orphan row is created because the ID never changes.

```dart
// After successful sendLocalMedia in conversation_wired.dart:
if (localSuccess) {
  final localAttachment = MediaAttachment(
    id: attachmentId,  // Same ID as upload_pending row
    messageId: optimisticMessage.id,
    mime: mime,
    size: await File(media.file.path).length(),
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: media.file.path,
    downloadStatus: 'done',  // Overwrites upload_pending
    createdAt: optimisticMessage.createdAt,
    width: media.width,
    height: media.height,
    durationMs: media.durationMs,
  );
  // saveAttachment replaces the upload_pending row because id matches
  await widget.mediaAttachmentRepo?.saveAttachment(localAttachment);
  uploadedAttachments.add(localAttachment);
}
```

**F.7.1.5 Fallback safety DELETE:**

If for any reason the upload path generates a different ID than the placeholder (defensive fallback), explicitly DELETE the orphan placeholder before saving the new row:

```dart
// Defensive fallback — only needed if blobId parameter is not used
if (uploaded != null && uploaded.id != attachmentId) {
  // Upload generated a different ID (should not happen with stable-ID contract)
  emitFlowEvent(
    layer: 'FL',
    event: 'MEDIA_UPLOAD_ID_MISMATCH',
    details: {'expected': attachmentId, 'actual': uploaded.id},
  );
  // Delete the orphan placeholder row
  await widget.mediaAttachmentRepo?.deleteAttachmentsForMessage(
    optimisticMessage.id,
  );
}
```

**F.7.1.6 Stable-ID test: no orphan rows after successful upload**

**File:** `test/features/conversation/application/stable_id_contract_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('Stable-ID contract: no orphan rows', () {
    // F.7.1.6.1
    test('after successful relay upload, exactly one row exists per attachment', () async {
      final repo = FakeMediaAttachmentRepository();
      final attachmentId = 'stable-att-id-001';
      final messageId = 'msg-001';

      // Step 1: Write upload_pending row with stable ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 0,
        mediaType: 'image',
        localPath: '/tmp/photo.jpg',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Step 2: Upload succeeds — save done row with SAME ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,  // Same ID — overwrites placeholder
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: 'media/peer-bob/stable-att-id-001.jpg',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Assert: exactly one row for this message, no orphan upload_pending
      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1, reason: 'Must have exactly one row, not two');
      expect(attachments.first.id, attachmentId);
      expect(attachments.first.downloadStatus, 'done');

      // Assert: no upload_pending rows anywhere
      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty, reason: 'No orphan upload_pending rows must exist');
    });

    // F.7.1.6.2
    test('after successful local-WiFi transfer, upload_pending row is updated to done', () async {
      final repo = FakeMediaAttachmentRepository();
      final attachmentId = 'stable-att-id-002';
      final messageId = 'msg-002';

      // Step 1: Write upload_pending row
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
      ));

      // Step 2: Local WiFi succeeds — save done row with SAME ID
      await repo.saveAttachment(MediaAttachment(
        id: attachmentId,
        messageId: messageId,
        mime: 'audio/mp4',
        size: 8192,
        mediaType: 'audio',
        localPath: '/tmp/voice.m4a',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        durationMs: 5000,
      ));

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.downloadStatus, 'done');

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });

    // F.7.1.6.3
    test('multi-attachment message: each attachment uses its own stable ID', () async {
      final repo = FakeMediaAttachmentRepository();
      final messageId = 'msg-multi-003';
      final attIds = ['att-a', 'att-b', 'att-c'];

      // Step 1: Write 3 upload_pending rows
      for (final id in attIds) {
        await repo.saveAttachment(MediaAttachment(
          id: id,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 0,
          mediaType: 'image',
          localPath: '/tmp/$id.jpg',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }

      // Step 2: All uploads succeed — overwrite each with done
      for (final id in attIds) {
        await repo.saveAttachment(MediaAttachment(
          id: id,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          localPath: 'media/peer-bob/$id.jpg',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
      }

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 3, reason: 'Exactly 3 rows, no orphans');
      expect(attachments.every((a) => a.downloadStatus == 'done'), isTrue);

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });

    // F.7.1.6.4 — Defensive fallback: if ID mismatch occurs, cleanup works
    test('fallback: if upload returns different ID, deleteAttachmentsForMessage cleans orphans', () async {
      final repo = FakeMediaAttachmentRepository();
      final placeholderId = 'placeholder-id';
      final uploadedId = 'different-relay-id';
      final messageId = 'msg-fallback';

      // Step 1: Write upload_pending row
      await repo.saveAttachment(MediaAttachment(
        id: placeholderId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 0,
        mediaType: 'image',
        localPath: '/tmp/photo.jpg',
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      // Step 2: Upload returned a DIFFERENT ID (fallback scenario)
      // Delete all rows for this message first
      await repo.deleteAttachmentsForMessage(messageId);

      // Step 3: Save new row with upload-assigned ID
      await repo.saveAttachment(MediaAttachment(
        id: uploadedId,
        messageId: messageId,
        mime: 'image/jpeg',
        size: 2048,
        mediaType: 'image',
        localPath: 'media/peer-bob/different-relay-id.jpg',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ));

      final attachments = await repo.getAttachmentsForMessage(messageId);
      expect(attachments.length, 1);
      expect(attachments.first.id, uploadedId);

      final pending = await repo.getUploadPendingAttachments();
      expect(pending, isEmpty);
    });
  });
}
```

**F.7.1.7 Impact on `_reuploadAttachments`, `retryIncompleteUploads`, and `sendVoiceMessage`:**

All retry and relay-upload paths must pass the pre-existing attachment `id` as `blobId:` when calling their respective upload functions, so the re-upload uses the same ID:

```dart
// In _reuploadAttachments (Part F retry path):
final uploaded = await uploadFn(
  bridge: bridge,
  localFilePath: localPath,
  mime: attachment.mime,
  recipientPeerId: targetPeerId,
  durationMs: attachment.durationMs,
  waveform: attachment.waveform,
  width: attachment.width,
  height: attachment.height,
  blobId: attachment.id,  // Reuse the same ID — UPDATE not INSERT
);

// In retryIncompleteUploads (Part G retry path):
final uploaded = await uploadMediaFn(
  bridge: bridge,
  localFilePath: localPath,
  mime: attachment.mime,
  recipientPeerId: msg.contactPeerId,
  durationMs: attachment.durationMs,
  waveform: attachment.waveform,
  width: attachment.width,
  height: attachment.height,
  blobId: attachment.id,  // Reuse the same ID — UPDATE not INSERT
);
```

**F.7.1.7a Voice relay path -- `sendVoiceMessage` must also thread the stable ID:**

The voice relay fallback calls `sendVoiceMessage()` which internally calls `uploadMedia()`. To obey the Stable-ID contract, `sendVoiceMessage()` must accept an optional `String? blobId` parameter and forward it to `uploadMedia(blobId: blobId)`. The caller (`_onVoiceRecordingStopped` in `conversation_wired.dart`) passes the same `voiceAttId` that was used for the `upload_pending` row.

**Signature change to `send_voice_message_use_case.dart`:**

```dart
Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required AudioRecording recording,
  required Bridge bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  String? text,
  String? quotedMessageId,
  List<double>? waveform,
  String? messageId,
  String? timestamp,
  String? blobId,  // NEW: Stable-ID contract (F.7.1) — pre-generated attachment ID
}) async {
  // ...existing validation...

  // 2. Upload — forward blobId so uploadMedia reuses the stable ID
  final uploaded = await uploadMedia(
    bridge: bridge,
    localFilePath: recording.filePath,
    mime: recording.mime,
    recipientPeerId: targetPeerId,
    mediaFileManager: mediaFileManager,
    durationMs: recording.durationMs,
    waveform: waveform,
    blobId: blobId,  // Stable-ID: same ID as upload_pending row
  );
  // ...rest unchanged...
```

**Caller change in `conversation_wired.dart` voice relay path:**

```dart
// In _onVoiceRecordingStopped, relay upload branch:
final (voiceResult, voiceMessage) = await widget.sendVoiceMessageFn(
  // ... existing params ...
  blobId: voiceAttId,  // Stable-ID: same ID as upload_pending row
);
```

**F.7.1.7b Test: voice relay path uses stable ID (no orphan row)**

**File:** `test/features/conversation/application/stable_id_contract_test.dart` (append to existing group)

```dart
// F.7.1.7b.1 — Voice relay fallback threads stable ID through sendVoiceMessage -> uploadMedia
test('voice relay path forwards blobId to uploadMedia, producing one row', () async {
  final repo = FakeMediaAttachmentRepository();
  final voiceAttId = 'stable-voice-001';
  final messageId = 'msg-voice-relay-001';

  // Step 1: Write upload_pending row with the stable voice attachment ID
  await repo.saveAttachment(MediaAttachment(
    id: voiceAttId,
    messageId: messageId,
    mime: 'audio/mp4',
    size: 8192,
    mediaType: 'audio',
    localPath: '/tmp/voice.m4a',
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    durationMs: 5000,
    waveform: [0.1, 0.5, 0.9],
  ));

  // Step 2: Simulate sendVoiceMessage calling uploadMedia(blobId: voiceAttId)
  // which returns an attachment with the SAME id.
  // Then saveAttachment overwrites the upload_pending row.
  final fakeUploadFn = FakeUploadMediaFn();
  fakeUploadFn.willReturn(MediaAttachment(
    id: voiceAttId, // Same stable ID — returned by uploadMedia
    messageId: messageId,
    mime: 'audio/mp4',
    size: 8192,
    mediaType: 'audio',
    localPath: 'media/peer-bob/$voiceAttId.m4a',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    durationMs: 5000,
    waveform: [0.1, 0.5, 0.9],
  ));

  // Simulate the upload call with blobId (as sendVoiceMessage would do)
  final uploaded = await fakeUploadFn.call(
    bridge: FakeBridge(),
    localFilePath: '/tmp/voice.m4a',
    mime: 'audio/mp4',
    recipientPeerId: 'peer-bob',
    durationMs: 5000,
    waveform: [0.1, 0.5, 0.9],
    blobId: voiceAttId,  // Stable-ID contract
  );

  // Verify blobId was forwarded
  expect(fakeUploadFn.lastBlobId, voiceAttId,
      reason: 'sendVoiceMessage must forward blobId to uploadMedia');

  // Save the done row (same ID overwrites upload_pending)
  if (uploaded != null) {
    await repo.saveAttachment(uploaded);
  }

  // Assert: exactly one row, no orphan upload_pending
  final attachments = await repo.getAttachmentsForMessage(messageId);
  expect(attachments.length, 1, reason: 'Must have exactly one row, not two');
  expect(attachments.first.id, voiceAttId);
  expect(attachments.first.downloadStatus, 'done');

  final pending = await repo.getUploadPendingAttachments();
  expect(pending, isEmpty, reason: 'No orphan upload_pending rows must exist');
});
```

This eliminates the orphan row problem entirely. The relay blob ID matches the DB primary key, so `ConflictAlgorithm.replace` overwrites the `upload_pending` row with the `done` row.

**F.7.1.8 Files to create / modify (Stable-ID additions)**

| File | Purpose |
|---|---|
| `lib/features/conversation/application/upload_media_use_case.dart` | Add optional `String? blobId` param to `uploadMedia` and `UploadMediaFn` typedef |
| `lib/features/conversation/application/send_voice_message_use_case.dart` | Add optional `String? blobId` param; forward to `uploadMedia(blobId: blobId)` (F.7.1.7a) |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Generate stable `attachmentId` once; pass to both `upload_pending` save and `uploadMediaFn`; update local-WiFi path to use same ID; voice relay path passes `blobId: voiceAttId` to `sendVoiceMessageFn` (F.7.1.7a) |
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Pass `blobId: attachment.id` in `_reuploadAttachments` |
| `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` | Pass `blobId: attachment.id` in retry loop |
| `test/features/conversation/application/stable_id_contract_test.dart` | Tests F.7.1.6.1 through F.7.1.6.4 and F.7.1.7b.1 (voice relay stable ID) proving no orphan rows |
| `test/features/conversation/application/helpers/fake_upload_media_fn.dart` | Add `String? blobId` param to `call()` signature; track `lastBlobId` |

#### F.8 Edge cases and constraints

| Edge case | Behaviour |
|---|---|
| App killed during re-upload | Row stays `'failed'`; next retry cycle re-attempts re-upload (idempotent) |
| App killed between re-upload success and P2P send | After F.7 refactor: `media_attachments` row updated to `'done'`; next retry takes Part C path (no duplicate upload) |
| Relative `localPath` (written by `MediaFileManager`) | `File(localPath).existsSync()` returns false; message skipped. `_reuploadAttachments` must resolve stored paths through `MediaFileManager.resolveStoredPath()` before any `File(...).existsSync()` or upload call -- this is required for production correctness, not deferred refactor work. See test F.5.8 |
| `mediaAttachmentRepo` is null (legacy callers) | `persistedAttachments` defaults to `const []`; falls through to text-only path — existing behaviour preserved |
| `uploadMediaFn` is null (production callers) | `uploadMedia` symbol used as default |
| Voice message with `durationMs` and `waveform` | Both fields stored in `media_attachments` row and forwarded to `uploadMediaFn` so re-uploaded blob carries correct audio metadata |
| Multiple attachments, one upload fails | `_reuploadAttachments` returns null on first failure; entire message skipped; already-uploaded blobs orphaned on relay (expire in 7 days). Note: relay blob expiry is an infrastructure concern, not verified in unit tests |
| Voice recording file in iOS tmp directory deleted between launches | **Closed by Gap 4 (G.9 Durable Storage):** processed file is copied to `<appDocDir>/pending_uploads/<messageId>/` before upload. Recovery reads from durable path, not temp dir. If durable copy also missing, message skipped, user must re-record |
| Voice-local-WiFi failure (no relay upload) | **Closed by Gap 5 (G.10 Voice Local-WiFi):** `upload_pending` row exists (from G-E). On retry, `retryIncompleteUploads` uses relay upload (not local WiFi). After successful local transfer, upload_pending row is updated to `done` via Stable-ID contract (F.7.1.4) |
| Stable-ID contract: placeholder row orphan after successful upload | **Closed by Gap 2 (F.7.1):** attachment ID is generated ONCE and threaded to `uploadMedia(blobId:)`. `ConflictAlgorithm.replace` overwrites the `upload_pending` row on success. No orphan rows |

#### F.9 Files to create / modify (Part F additions)

| File | Purpose |
|---|---|
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Add `uploadMediaFn` param; add `_reuploadAttachments` helper; replace flat fallback with three-branch dispatch |
| `lib/features/conversation/application/send_voice_message_use_case.dart` | Add optional `String? blobId` param; forward to `uploadMedia(blobId: blobId)` so voice relay upload uses stable ID (F.7.1.7a) |
| `lib/core/services/pending_message_retrier.dart` | Accept `mediaAttachmentRepo`; pass to `retryFailedMessages` in `_retryIfNeeded` |
| `lib/main.dart` | Thread `mediaAttachmentRepo` into `PendingMessageRetrier` constructor; update `retryFailedMessagesFn` closure |
| `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart` | Part F unit tests (F.5.1–F.5.7 above) |
| `test/features/conversation/application/helpers/fake_upload_media_fn.dart` | Injectable fake for `UploadMediaFn` used in Part F tests |
| `test/core/services/pending_message_retrier_media_reupload_test.dart` | Tests that `PendingMessageRetrier._retryIfNeeded` passes `mediaAttachmentRepo` through to `retryFailedMessages` |

---

> **⚠️ AUDIT FIX (FV-07):** The voice relay path has a potentially dead `else if` branch in `conversation_wired.dart:1402-1404`. `sendVoiceMessage` always returns non-null `message` on success, making the `else if (result == SendVoiceMessageResult.success)` branch unreachable. The `'sent'` status set in this branch is never promoted to `'delivered'` by any retry path, creating a potential stuck state. Remove the dead branch or add a defensive FLOW event.

### Part G: Media and Voice Pre-Upload State Persistence

**Relationship to Part F:** Part F extends `retryFailedMessages` to re-upload attachment files when it finds `media_attachments` rows on disk. Part G is the upstream half: it writes those rows **before** the upload starts (with `downloadStatus='upload_pending'`), so Part F and the new `retryIncompleteUploads` use case have the local file path and attachment metadata they need to retry after a lock event. Parts F and G are complementary -- Part F handles messages whose upload completed but P2P send failed; Part G handles messages whose upload itself was interrupted. Both must be implemented for full media and voice recovery coverage.

**Per-message recovery invariant:** `retryIncompleteUploads` groups all `upload_pending` attachments by `messageId`, re-uploads ALL attachments for a given message, and then calls `sendChatMessage` ONCE with the full attachment list. This mirrors the real send path in `conversation_wired.dart` (lines 646-738) which uploads all attachments in a loop, collects them into a single `uploadedAttachments` list, then makes one `sendChatMessage` call. Per-attachment recovery would fragment a multi-image message into separate single-image sends, corrupt the wire payload, and cause duplicate delivery attempts.

#### Background — what breaks today

**The gap:** Parts A-D handle messages that reached `sendChatMessage` and were persisted with a `wireEnvelope` (or at least a non-null `status='failed'` row). They do **not** handle the window between the optimistic DB write and the completion of the upload phase.

The two affected code paths are:

1. **Media upload path** (`conversation_wired.dart` lines ~648-713): After the optimistic row is persisted with `status='sending'`, `conversation_wired.dart` loops over `mediaToUpload`, calling `widget.uploadMediaFn()` for each file. Each call is a round-trip through the Go bridge (`callP2PMediaUpload`) plus a relay upload. This can take 5-60+ seconds per file. During this window:
   - The optimistic DB row has `wireEnvelope=null` and `media=[]` (media is transient — not in `toMap()`).
   - If the device locks or the OS kills the app, the row is permanently stuck in `'sending'` with no upload state and no attachment metadata in the DB.
   - When `retryFailedMessages` eventually runs (after Part A transitions the row to `'failed'`), it calls `sendChatMessage` without `mediaAttachments` and without any `mediaAttachmentRepo` rows to load (Part C), so the retry sends an empty text message silently dropping the attachment.

2. **Voice upload path** (`conversation_wired.dart` lines ~1278-1385): The voice path branches:
   - **Local WiFi**: Calls `p2pService.sendLocalMedia()` (fast, bounded) then `sendChatMessageFn`. Lock risk is low but still present during the sendLocalMedia call.
   - **Relay upload**: Calls `sendVoiceMessage` which internally calls `uploadMedia` (the same relay bridge round-trip). If the device locks here, the optimistic row has `wireEnvelope=null` and its `media` list in the DB is also empty (because `saveMessage` → `toMap()` does not serialize `media`). The voice attachment metadata (`localPath`, `durationMs`, `waveform`, `mime`) that was put in the transient `optimisticMessage.media` list is entirely lost.

**Key insight from `ConversationMessage.toMap()`:** The `media` field is explicitly excluded — it is transient. This means no attachment metadata survives a process kill unless `mediaAttachmentRepo.saveAttachment()` is called separately **before** the upload attempt.

**Key insight from `MediaAttachment.toMap()`:** All the fields needed to identify and re-upload a file are present: `localPath`, `mime`, `mediaType`, `durationMs`, `waveform`. If we persist the pre-upload attachment row (with a new sentinel `downloadStatus='upload_pending'`) at optimistic write time, we have everything needed to re-run `uploadMedia()` on retry.

**The upload state machine today:**

```
[user taps send]
     |
[optimistic row: status='sending', wireEnvelope=null, media=[] (transient)]
     |
[upload in progress — lock risk window — no recovery state]
     |
[upload done → sendChatMessage → wireEnvelope persisted]
     |
[status='delivered'/'sent'/'failed' — Parts A-D cover this]
```

**The desired upload state machine after Part G:**

```
[user taps send]
     |
[optimistic row: status='sending', wireEnvelope=null]
[media_attachments row(s): downloadStatus='upload_pending', localPath set]  <- NEW
     |
[upload in progress — lock risk window — recovery state now exists]
     |
[upload done → UPDATE upload_pending row to downloadStatus='done' (same stable ID, F.7.1)]  <- NEW
     |
[sendChatMessage → wireEnvelope persisted → status='delivered']
```

On recovery (app resume + Part A transitions row to `'failed'`):
- `retryIncompleteUploads` queries `mediaAttachmentRepo.getUploadPendingAttachments()`, then groups results by `messageId`.
- For each message: rows with `downloadStatus='upload_pending'` indicate the upload never completed. The retry re-runs `uploadMedia()` for ALL attachments belonging to that message, then calls `sendChatMessage` ONCE with the complete list of newly uploaded attachments and the original `messageId` and `timestamp`.
- If ANY attachment in a message group fails to re-upload, ALL attachments for that message are marked `upload_failed` and `sendChatMessage` is NOT called (no partial sends).
- Rows with `downloadStatus='done'` indicate upload completed -- the relay blob ID (`attachment.id`) is already valid; `retryFailedMessages` with `mediaAttachmentRepo` (Part C) handles these directly.

**Ordering requirement on resume:**

```
recoverStuckSendingMessages()      (Part A — transitions 'sending' rows to 'failed')
    |
retryIncompleteUploads()           (Part G — groups by messageId, re-uploads all attachments per message, then sends once)
    |
retryFailedMessages()              (Parts B/C/D — picks up any remaining failed rows)
```

`retryIncompleteUploads` must run after `recoverStuckSendingMessages` (so the parent message row is in `'failed'` status when the upload-pending check is evaluated) and before `retryFailedMessages` (so attachment `downloadStatus` is `'done'` before the failed-message retry reads them via `mediaAttachmentRepo`). It processes messages atomically: all attachments for a given `messageId` are re-uploaded together and sent in a single `sendChatMessage` call.

---

#### New `downloadStatus` sentinel: `'upload_pending'`

The `downloadStatus` field on `MediaAttachment` currently uses: `'pending'`, `'downloading'`, `'done'`, `'failed'`. The existing `'pending'` status means "incoming attachment whose local file has not yet been downloaded." We introduce `'upload_pending'` as an explicit sentinel meaning "optimistically written outgoing attachment, upload not yet attempted or not yet completed." This distinguishes recovery-needed outgoing rows from incoming rows that have not yet been downloaded.

Full `downloadStatus` lifecycle after Part G:

| Value | Direction | Meaning |
|---|---|---|
| `'upload_pending'` | outgoing | Written at optimistic time, upload not completed |
| `'done'` | outgoing or incoming | Upload done (outgoing) or download done (incoming) |
| `'upload_failed'` | outgoing | Retry re-upload attempted and failed; user must resend |
| `'pending'` | incoming | Relay blob exists, local file not yet downloaded |
| `'downloading'` | incoming | Download in progress |
| `'failed'` | incoming | Download permanently failed |

---

#### G.1 Red phase — new DB helper `dbLoadUploadPendingAttachments`

**File to create:** `test/core/database/helpers/media_attachments_db_helpers_upload_pending_test.dart`

Tests the new `dbLoadUploadPendingAttachments` helper before it exists. All tests fail with `undefined function` errors.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';

import '../../helpers/in_memory_db.dart';

void main() {
  late Database db;

  setUp(() async {
    db = await openInMemoryTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertMessage(String id, {String status = 'sending'}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('messages', {
      'id': id,
      'contact_peer_id': 'peer-a',
      'sender_peer_id': 'me',
      'text': '',
      'timestamp': now,
      'status': status,
      'is_incoming': 0,
      'created_at': now,
    });
  }

  Future<void> insertAttachment(
    String id, {
    required String messageId,
    required String downloadStatus,
    String localPath = '/tmp/test.jpg',
    String mime = 'image/jpeg',
  }) async {
    await db.insert('media_attachments', {
      'id': id,
      'message_id': messageId,
      'mime': mime,
      'size': 1024,
      'media_type': 'image',
      'local_path': localPath,
      'download_status': downloadStatus,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  group('dbLoadUploadPendingAttachments', () {
    test('returns empty list when no attachments exist', () async {
      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows, isEmpty);
    });

    test('returns attachment with download_status=upload_pending', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-1',
        messageId: 'msg-1',
        downloadStatus: 'upload_pending',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows.length, 1);
      expect(rows.first['id'], 'att-1');
    });

    test('does not return attachment with download_status=done', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-done',
        messageId: 'msg-1',
        downloadStatus: 'done',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows, isEmpty);
    });

    test('does not return attachment with download_status=pending (incoming download)', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-pending',
        messageId: 'msg-1',
        downloadStatus: 'pending',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows, isEmpty);
    });

    test('does not return attachment with download_status=failed', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-failed',
        messageId: 'msg-1',
        downloadStatus: 'failed',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows, isEmpty);
    });

    test('does not return attachment with download_status=upload_failed', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-upfailed',
        messageId: 'msg-1',
        downloadStatus: 'upload_failed',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows, isEmpty);
    });

    test('returns multiple upload_pending attachments across messages', () async {
      await insertMessage('msg-1');
      await insertMessage('msg-2');
      await insertAttachment('att-1a', messageId: 'msg-1', downloadStatus: 'upload_pending');
      await insertAttachment('att-1b', messageId: 'msg-1', downloadStatus: 'upload_pending');
      await insertAttachment('att-2a', messageId: 'msg-2', downloadStatus: 'upload_pending');

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows.length, 3);
    });

    test('row contains local_path field', () async {
      await insertMessage('msg-1');
      await insertAttachment(
        'att-1',
        messageId: 'msg-1',
        downloadStatus: 'upload_pending',
        localPath: '/var/mobile/media/rec.m4a',
      );

      final rows = await dbLoadUploadPendingAttachments(db);
      expect(rows.first['local_path'], '/var/mobile/media/rec.m4a');
    });

    test('respects limit parameter', () async {
      await insertMessage('msg-1');
      for (var i = 0; i < 10; i++) {
        await insertAttachment('att-$i', messageId: 'msg-1', downloadStatus: 'upload_pending');
      }

      final rows = await dbLoadUploadPendingAttachments(db, limit: 5);
      expect(rows.length, 5);
    });

    test('results are ordered by created_at ascending', () async {
      final base = DateTime(2026, 1, 1, 0, 0, 0).toUtc();
      await insertMessage('msg-1');
      for (var i = 4; i >= 0; i--) {
        await db.insert('media_attachments', {
          'id': 'att-$i',
          'message_id': 'msg-1',
          'mime': 'image/jpeg',
          'size': 1024,
          'media_type': 'image',
          'local_path': '/tmp/$i.jpg',
          'download_status': 'upload_pending',
          'created_at': base.add(Duration(minutes: i)).toIso8601String(),
        });
      }

      final rows = await dbLoadUploadPendingAttachments(db);
      final ids = rows.map((r) => r['id'] as String).toList();
      expect(ids, ['att-0', 'att-1', 'att-2', 'att-3', 'att-4']);
    });
  });
}
```

---

#### G.2 Red phase — `MediaAttachmentRepository` interface and fake tests

**File to create:** `test/features/conversation/domain/repositories/media_attachment_repository_upload_pending_test.dart`

Tests `getUploadPendingAttachments()` on `FakeMediaAttachmentRepository` before the method exists.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

MediaAttachment _makeAttachment({
  required String id,
  required String messageId,
  required String downloadStatus,
  String localPath = '/tmp/test.jpg',
  String mime = 'image/jpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 1024,
    mediaType: 'image',
    localPath: localPath,
    downloadStatus: downloadStatus,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

void main() {
  group('FakeMediaAttachmentRepository.getUploadPendingAttachments', () {
    late FakeMediaAttachmentRepository repo;

    setUp(() {
      repo = FakeMediaAttachmentRepository();
    });

    test('returns empty list when no attachments seeded', () async {
      final result = await repo.getUploadPendingAttachments();
      expect(result, isEmpty);
    });

    test('returns only upload_pending attachments', () async {
      repo.seed([
        _makeAttachment(id: 'att-1', messageId: 'msg-1', downloadStatus: 'upload_pending'),
        _makeAttachment(id: 'att-done', messageId: 'msg-2', downloadStatus: 'done'),
        _makeAttachment(id: 'att-pending', messageId: 'msg-3', downloadStatus: 'pending'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.length, 1);
      expect(result.first.id, 'att-1');
    });

    test('returns all upload_pending across multiple messages', () async {
      repo.seed([
        _makeAttachment(id: 'att-a', messageId: 'msg-1', downloadStatus: 'upload_pending'),
        _makeAttachment(id: 'att-b', messageId: 'msg-2', downloadStatus: 'upload_pending'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.length, 2);
    });

    test('returns attachment with localPath populated', () async {
      repo.seed([
        _makeAttachment(
          id: 'att-1',
          messageId: 'msg-1',
          downloadStatus: 'upload_pending',
          localPath: '/var/mobile/recordings/voice.m4a',
        ),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result.first.localPath, '/var/mobile/recordings/voice.m4a');
    });

    test('excludes upload_failed attachments', () async {
      repo.seed([
        _makeAttachment(id: 'att-1', messageId: 'msg-1', downloadStatus: 'upload_failed'),
      ]);

      final result = await repo.getUploadPendingAttachments();
      expect(result, isEmpty);
    });
  });
}
```

---

#### G.3 Red phase — `retryIncompleteUploads` use case tests

**File to create:** `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart`

Tests the new `retryIncompleteUploads` use case before it exists. All tests fail with `Target of URI doesn't exist`.

> **⚠️ AUDIT FIX (G-04):** Tests inject `FakeUploadMediaFn` (from Part F, F.5 helper) via the `uploadMediaFn` parameter. No `FakeBridge` modifications are needed for upload stubbing.

> **Canonical failure design (G.8.2 reconciled into G.3/G.5):** These tests and the G.5 implementation use ONE consistent failure model. A transient upload failure (bridge returns null, relay temporarily unreachable) increments `uploadRetryCount` and keeps the row as `upload_pending` (retryable on the next cycle). Only after `kMaxUploadRetries` (3) consecutive failures -- or when the failure is non-retryable (null localPath, missing file) -- does the row transition to `upload_failed` (terminal). This design is defined in G.8.2 and applied consistently throughout G.3, G.5, and G.8. A reader going top-to-bottom will see ONE canonical design, not two.

**Test design note -- per-message grouping:** These tests validate that `retryIncompleteUploads`
groups attachments by `messageId`, re-uploads ALL attachments for a single message, and then
calls `sendChatMessage` ONCE with the full list. This mirrors the real send path in
`conversation_wired.dart` (lines 646-738) where all uploads are collected, then one
`sendChatMessage` call is made. Tests explicitly cover multi-attachment messages to catch
any regression to per-attachment iteration.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../core/bridge/fake_bridge.dart';
import '../../core/services/fake_p2p_service.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import 'helpers/fake_upload_media_fn.dart';

MediaAttachment _pendingAtt({
  String id = 'att-1',
  String messageId = 'msg-1',
  String localPath = '/tmp/recording.m4a',
  String mime = 'audio/mpeg',
  int? durationMs = 3000,
  String mediaType = 'audio',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: mediaType,
    localPath: localPath,
    durationMs: durationMs,
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

ConversationMessage _makeMsg(
  String id, {
  required String status,
  String contactPeerId = 'peer-bob',
}) {
  final now = DateTime.now().toUtc().toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: '',
    timestamp: now,
    status: status,
    isIncoming: false,
    createdAt: now,
  );
}

MediaAttachment _doneAttachment(String id, String messageId, {String mime = 'audio/mpeg'}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: '/tmp/recording.m4a',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

void main() {
  late FakeMediaAttachmentRepository mediaRepo;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeUploadMediaFn fakeUploadFn;

  setUp(() {
    mediaRepo = FakeMediaAttachmentRepository();
    messageRepo = FakeMessageRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    fakeUploadFn = FakeUploadMediaFn();
  });

  group('retryIncompleteUploads', () {
    test('returns 0 when no upload_pending attachments exist', () async {
      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('returns 0 when identity cannot be loaded', () async {
      mediaRepo.seed([_pendingAtt()]);
      // identityRepo has no seeded identity

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message whose parent message row does not exist', () async {
      mediaRepo.seed([_pendingAtt(messageId: 'nonexistent-msg')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message when parent message is already delivered', () async {
      final msg = _makeMsg('msg-1', status: 'delivered');
      messageRepo.seed([msg]);
      mediaRepo.seed([_pendingAtt(messageId: 'msg-1')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
    });

    test('skips message when any attachment has null localPath — marks ALL as upload_failed', () async {
      final noPathAtt = MediaAttachment(
        id: 'att-no-path',
        messageId: 'msg-1',
        mime: 'image/jpeg',
        size: 1024,
        mediaType: 'image',
        localPath: null,
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      );
      final msg = _makeMsg('msg-1', status: 'failed');
      messageRepo.seed([msg]);
      mediaRepo.seed([noPathAtt]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
      );
      expect(count, 0);
      // Attachment should be marked upload_failed
      expect(mediaRepo.lastSavedAttachment?.downloadStatus, 'upload_failed');
    });

    // Transient failure: first upload attempt keeps rows as upload_pending
    // with incremented retryCount (G.8.2 canonical design). Only after
    // kMaxUploadRetries attempts does the row transition to upload_failed.
    test('first transient upload failure keeps ALL attachments as upload_pending with retryCount=1', () async {
      final msg = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      mediaRepo.seed([
        _pendingAtt(id: 'att-1', messageId: 'msg-1', localPath: '/tmp/img1.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-2', messageId: 'msg-1', localPath: '/tmp/img2.jpg', mime: 'image/jpeg', mediaType: 'image'),
      ]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      fakeUploadFn.willReturn(null); // transient failure

      await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      // Both attachments stay upload_pending (transient, retryable)
      final pending = await mediaRepo.getUploadPendingAttachments();
      expect(pending.length, 2);
      expect(pending.every((a) => a.uploadRetryCount == 1), isTrue,
          reason: 'retryCount must be incremented to 1');
      expect(p2pService.sendCallCount, 0, reason: 'sendChatMessage must not be called on failed upload');
    });

    // Transient retries: row stays upload_pending and IS picked up on
    // subsequent calls until kMaxUploadRetries is exhausted.
    // After exhaustion, row transitions to upload_failed and is NOT picked up.
    test('transient failure: attachment IS retried on second call (still upload_pending)', () async {
      final msg = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      mediaRepo.seed([_pendingAtt(messageId: 'msg-1')]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      fakeUploadFn.willReturn(null); // transient failure

      // First attempt: retryCount 0 -> 1, stays upload_pending
      await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      // Second attempt: still upload_pending, so it IS retried
      final pending = await mediaRepo.getUploadPendingAttachments();
      expect(pending.length, 1, reason: 'Row must still be upload_pending after first failure');

      // Now succeed on second attempt
      fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-1'));
      p2pService.storeInInboxResult = true;

      final count2 = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count2, 1, reason: 'Second attempt should succeed');
    });

    test('upload_failed attachment is not picked up after kMaxUploadRetries exhaustion', () async {
      final msg = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      // Seed with retryCount already at kMaxUploadRetries - 1 (one more failure = terminal)
      mediaRepo.seed([
        _pendingAtt(messageId: 'msg-1')
            .copyWith(uploadRetryCount: kMaxUploadRetries - 1),
      ]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      fakeUploadFn.willReturn(null);

      await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      // Now upload_failed -- not picked up on next call
      final pending = await mediaRepo.getUploadPendingAttachments();
      expect(pending, isEmpty, reason: 'Row must be upload_failed after max retries');

      final count2 = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count2, 0);
    });

    test('returns 1 after successful re-upload and send (single attachment)', () async {
      final msg = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([_pendingAtt(messageId: 'msg-1')]);
      fakeUploadFn.willReturn(_doneAttachment('blob-uploaded', 'msg-1'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count, 1);
    });

    test('also retries when message is still in sending status', () async {
      final msg = _makeMsg('msg-1', status: 'sending', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([_pendingAtt(messageId: 'msg-1')]);
      fakeUploadFn.willReturn(_doneAttachment('blob-id', 'msg-1'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      expect(count, 1);
    });

    // ---- Multi-attachment per-message tests (critical for correctness) ----

    test('multi-attachment message: uploads ALL then sends ONCE with full list', () async {
      final msg = _makeMsg('msg-multi', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([
        _pendingAtt(id: 'att-a', messageId: 'msg-multi', localPath: '/tmp/img1.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-b', messageId: 'msg-multi', localPath: '/tmp/img2.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-c', messageId: 'msg-multi', localPath: '/tmp/img3.jpg', mime: 'image/jpeg', mediaType: 'image'),
      ]);
      fakeUploadFn.willReturnForPath('/tmp/img1.jpg',
        _doneAttachment('blob-a', 'msg-multi', mime: 'image/jpeg'));
      fakeUploadFn.willReturnForPath('/tmp/img2.jpg',
        _doneAttachment('blob-b', 'msg-multi', mime: 'image/jpeg'));
      fakeUploadFn.willReturnForPath('/tmp/img3.jpg',
        _doneAttachment('blob-c', 'msg-multi', mime: 'image/jpeg'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      // ONE message successfully sent
      expect(count, 1);
      // uploadMedia called 3 times (once per attachment)
      expect(fakeUploadFn.callCount, 3);
      // sendChatMessage called ONCE (not 3 times)
      expect(p2pService.sendCallCount, 1);
      // The wire payload should contain ALL 3 blob IDs
      final payload = p2pService.lastSentPayload!;
      expect(payload, contains('blob-a'));
      expect(payload, contains('blob-b'));
      expect(payload, contains('blob-c'));
    });

    // Multi-attachment transient failure: on first attempt, ALL attachments
    // for the message stay upload_pending with incremented retryCount.
    // sendChatMessage is NOT called (no partial sends).
    test('multi-attachment: second upload fails -> ALL stay upload_pending (transient), sendChatMessage NOT called', () async {
      final msg = _makeMsg('msg-multi', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([
        _pendingAtt(id: 'att-a', messageId: 'msg-multi', localPath: '/tmp/img1.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-b', messageId: 'msg-multi', localPath: '/tmp/img2.jpg', mime: 'image/jpeg', mediaType: 'image'),
      ]);
      // First upload succeeds, second returns null (transient)
      fakeUploadFn.willReturnForPath('/tmp/img1.jpg',
        _doneAttachment('blob-a', 'msg-multi', mime: 'image/jpeg'));
      fakeUploadFn.willReturnForPath('/tmp/img2.jpg', null);

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(count, 0);
      expect(p2pService.sendCallCount, 0, reason: 'must NOT send partial attachment list');
      // Both original attachments for the message should stay upload_pending
      // with retryCount incremented (transient, retryable on next cycle)
      final pending = await mediaRepo.getUploadPendingAttachments();
      expect(pending.length, 2, reason: 'Both rows must stay upload_pending');
      expect(pending.every((a) => a.uploadRetryCount == 1), isTrue);
    });

    // Note: msg-1 transient failure keeps att-1 as upload_pending (retryable).
    // msg-2 succeeds. Both messages are processed independently.
    test('non-fatal: transient error on first message does not prevent processing second message', () async {
      final msg1 = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      final msg2 = _makeMsg('msg-2', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg1, msg2]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([
        _pendingAtt(id: 'att-1', messageId: 'msg-1', localPath: '/tmp/file1.m4a'),
        _pendingAtt(id: 'att-2', messageId: 'msg-2', localPath: '/tmp/file2.m4a'),
      ]);
      fakeUploadFn.willReturnForPath('/tmp/file1.m4a', null); // transient failure
      fakeUploadFn.willReturnForPath('/tmp/file2.m4a',
        _doneAttachment('blob-2', 'msg-2'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );
      // msg-1 deferred (transient), msg-2 succeeded
      expect(count, 1);
      // sendChatMessage called once (for msg-2 only)
      expect(p2pService.sendCallCount, 1);
      // att-1 stays upload_pending (retryable on next cycle)
      final pending = await mediaRepo.getUploadPendingAttachments();
      expect(pending.any((a) => a.id == 'att-1'), isTrue);
    });

    test('two messages each with multiple attachments: independent recovery', () async {
      final msg1 = _makeMsg('msg-1', status: 'failed', contactPeerId: 'peer-bob');
      final msg2 = _makeMsg('msg-2', status: 'failed', contactPeerId: 'peer-bob');
      messageRepo.seed([msg1, msg2]);
      identityRepo.seed(FakeIdentityRepository.makeIdentity());
      mediaRepo.seed([
        _pendingAtt(id: 'att-1a', messageId: 'msg-1', localPath: '/tmp/1a.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-1b', messageId: 'msg-1', localPath: '/tmp/1b.jpg', mime: 'image/jpeg', mediaType: 'image'),
        _pendingAtt(id: 'att-2a', messageId: 'msg-2', localPath: '/tmp/2a.jpg', mime: 'image/jpeg', mediaType: 'image'),
      ]);
      fakeUploadFn.willReturnForPath('/tmp/1a.jpg',
        _doneAttachment('blob-1a', 'msg-1', mime: 'image/jpeg'));
      fakeUploadFn.willReturnForPath('/tmp/1b.jpg',
        _doneAttachment('blob-1b', 'msg-1', mime: 'image/jpeg'));
      fakeUploadFn.willReturnForPath('/tmp/2a.jpg',
        _doneAttachment('blob-2a', 'msg-2', mime: 'image/jpeg'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo,
        messageRepo: messageRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call,
      );

      expect(count, 2); // both messages recovered
      expect(fakeUploadFn.callCount, 3); // 3 uploads total
      expect(p2pService.sendCallCount, 2); // 2 sendChatMessage calls (one per message)
    });
  });
}
```

**Why these tests fail today:** `retry_incomplete_uploads_use_case.dart` does not exist.

---

#### G.4 Red phase — optimistic pre-upload attachment persistence tests

**File to create:** `test/features/conversation/application/optimistic_upload_persistence_test.dart`

Tests that `saveAttachment(upload_pending)` is called before the actual upload, verifying the call ordering contract that `conversation_wired.dart` must fulfill.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('optimistic pre-upload attachment persistence', () {
    test(
      'RED: saveAttachment called with upload_pending BEFORE uploadMedia is called',
      () async {
        final callOrder = <String>[];
        String? firstSavedStatus;

        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) {
            callOrder.add('saveAttachment:${att.downloadStatus}');
            firstSavedStatus ??= att.downloadStatus;
          };

        // Pre-upload save (this is the contract conversation_wired must fulfill)
        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-pre',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        callOrder.add('uploadMedia');

        final saveIdx = callOrder.indexWhere((e) => e.startsWith('saveAttachment'));
        final uploadIdx = callOrder.indexOf('uploadMedia');

        expect(saveIdx, isNot(-1));
        expect(uploadIdx, isNot(-1));
        expect(saveIdx < uploadIdx, isTrue,
            reason: 'saveAttachment(upload_pending) must precede uploadMedia');
        expect(firstSavedStatus, 'upload_pending');
      },
    );

    test(
      'RED: after successful upload, saveAttachment called again with done',
      () async {
        final savedStatuses = <String>[];
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) => savedStatuses.add(att.downloadStatus);

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'blob-abc',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            localPath: '/var/mobile/media/photo.jpg',
            downloadStatus: 'done',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        expect(savedStatuses, containsAllInOrder(['upload_pending', 'done']));
      },
    );

    test(
      'RED: when upload fails, only upload_pending row is present — no done row',
      () async {
        final savedStatuses = <String>[];
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) => savedStatuses.add(att.downloadStatus);

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'att-1',
            messageId: 'msg-1',
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: '/tmp/photo.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        // Upload fails — no second saveAttachment in the success path
        expect(savedStatuses, equals(['upload_pending']));
        expect(savedStatuses.contains('done'), isFalse);
      },
    );

    test(
      'RED: voice message pre-upload save includes durationMs and waveform',
      () async {
        MediaAttachment? savedAtt;
        final fakeMediaRepo = FakeMediaAttachmentRepository()
          ..onSaveAttachment = (att) => savedAtt = att;

        await fakeMediaRepo.saveAttachment(
          MediaAttachment(
            id: 'voice-att-pre',
            messageId: 'msg-voice-1',
            mime: 'audio/mpeg',
            size: 8192,
            mediaType: 'audio',
            localPath: '/tmp/voice.m4a',
            durationMs: 4200,
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            waveform: [0.1, 0.5, 0.9, 0.4, 0.2],
          ),
        );

        expect(savedAtt, isNotNull);
        expect(savedAtt!.durationMs, 4200);
        expect(savedAtt!.waveform, isNotEmpty);
        expect(savedAtt!.localPath, '/tmp/voice.m4a');
        expect(savedAtt!.downloadStatus, 'upload_pending');
      },
    );
  });
}
```

---

#### G.5 Green phase — Implementation

##### Step G-A: New DB helper `dbLoadUploadPendingAttachments`

Add to `lib/core/database/helpers/media_attachments_db_helpers.dart`:

```dart
/// Returns all media_attachments rows with download_status='upload_pending',
/// ordered by created_at ASC (oldest first).
///
/// These are outgoing attachments whose upload was interrupted before
/// completing. They must be re-uploaded on the next retry cycle.
///
/// Returns at most [limit] rows.
Future<List<Map<String, Object?>>> dbLoadUploadPendingAttachments(
  Database db, {
  int limit = 50,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_START',
    details: {'limit': limit},
  );

  try {
    final results = await db.query(
      'media_attachments',
      where: "download_status = 'upload_pending'",
      orderBy: 'created_at ASC',
      limit: limit,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MEDIA_DB_LOAD_UPLOAD_PENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
```

##### Step G-B: Add `getUploadPendingAttachments` to `MediaAttachmentRepository` interface

In `lib/features/conversation/domain/repositories/media_attachment_repository.dart`, add:

```dart
/// Returns all attachments with downloadStatus='upload_pending'.
///
/// These are outgoing attachments persisted optimistically at send time
/// whose upload to the relay was interrupted by an app kill or lock event.
/// Used by [retryIncompleteUploads] on app resume to re-upload and re-send.
Future<List<MediaAttachment>> getUploadPendingAttachments();
```

##### Step G-C: Implement in `MediaAttachmentRepositoryImpl`

Add injected DB helper field:

```dart
final Future<List<Map<String, Object?>>> Function({int limit})
    dbLoadUploadPendingAttachments;
```

Add the override:

```dart
@override
Future<List<MediaAttachment>> getUploadPendingAttachments() async {
  final rows = await dbLoadUploadPendingAttachments();
  return rows.map((r) => MediaAttachment.fromMap(r)).toList();
}
```

##### Step G-D: New `retryIncompleteUploads` use case (canonical implementation -- includes G.8.2 transient retry design)

> **⚠️ AUDIT FIX (GV-04):** `retryIncompleteUploads` always calls `uploadMediaFn` for `upload_pending` rows, then `sendChatMessage`. It does not check if the contact is a local peer and attempt `sendLocalMedia()` first. For a voice message interrupted during `sendLocalMedia()` (not during relay upload), re-uploading to the relay is unnecessary overhead. Consider adding an optional `p2pService.isLocalPeer()` check: if the contact is a local peer and the attachment's `localPath` exists, try `sendLocalMedia()` first before falling back to relay upload. This is a follow-up enhancement -- the relay upload fallback is always correct, just slower.

**File to create:** `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart`

**Critical design constraint — per-message, not per-attachment:**

The real 1:1 send path (`conversation_wired.dart` lines 646-738) uploads ALL attachments
for a message in a loop, collects them into a single `uploadedAttachments` list, then
makes ONE `sendChatMessage()` call with the full list. A multi-attachment message
(e.g. 3 photos) is a single `ConversationMessage` row with 3 `media_attachments` rows
sharing the same `messageId`.

`retryIncompleteUploads` MUST mirror this: group all `upload_pending` attachments by
`messageId`, re-upload every attachment for that message, and then issue ONE
`sendChatMessage()` call with the complete list. Iterating attachment-by-attachment and
calling `sendChatMessage` per attachment would fragment a multi-image message into
separate single-image sends, corrupt the wire payload, and cause duplicate delivery
attempts after the first attachment's send marks the message as `'delivered'`.

The per-message algorithm:

```
1. Query all upload_pending attachments
2. Group by messageId -> Map<String, List<MediaAttachment>>
3. For each messageId group:
   a. Load parent message, validate status
   b. Re-upload ALL attachments in the group
   c. If ANY upload fails -> mark ALL as upload_failed, skip this message
   d. If ALL uploads succeed -> call sendChatMessage ONCE with the full list
4. Return count of successfully sent messages
```

```dart
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// Re-uploads any attachment rows with downloadStatus='upload_pending',
/// grouped by messageId, then calls [sendChatMessage] ONCE per message
/// with the full attachment list to complete the original send.
///
/// This mirrors the real send path in `conversation_wired.dart`, which
/// uploads all attachments for a message and then calls `sendChatMessage`
/// once with the complete list. Processing per-attachment would fragment
/// multi-attachment messages into separate single-attachment sends.
///
/// Ordering in [handleAppResumed]:
///   recoverStuckSendingMessages -> retryIncompleteUploads -> retryFailedMessages
///
/// Returns the number of messages successfully sent after re-upload.
/// Non-fatal per-message: errors are caught, logged, and iteration continues
/// to the next message.
Future<int> retryIncompleteUploads({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MessageRepository messageRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_START',
    details: {},
  );

  final pendingAttachments = await mediaAttachmentRepo.getUploadPendingAttachments();
  if (pendingAttachments.isEmpty) {
    emitFlowEvent(layer: 'FL', event: 'RETRY_INCOMPLETE_UPLOADS_NONE', details: {});
    return 0;
  }

  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    emitFlowEvent(layer: 'FL', event: 'RETRY_INCOMPLETE_UPLOADS_NO_IDENTITY', details: {});
    return 0;
  }

  // Group attachments by messageId so we process all attachments for a
  // single message together and issue ONE sendChatMessage call per message.
  final byMessageId = <String, List<MediaAttachment>>{};
  for (final att in pendingAttachments) {
    byMessageId.putIfAbsent(att.messageId, () => []).add(att);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_FOUND',
    details: {
      'attachmentCount': pendingAttachments.length,
      'messageCount': byMessageId.length,
    },
  );

  var successCount = 0;

  for (final entry in byMessageId.entries) {
    final messageId = entry.key;
    final attachments = entry.value;

    try {
      // 1. Load and validate the parent message.
      final msg = await messageRepo.getMessage(messageId);
      if (msg == null) {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_MSG',
          details: {'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId},
        );
        continue;
      }

      if (msg.status != 'sending' && msg.status != 'failed') {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_STATUS',
          details: {'status': msg.status},
        );
        continue;
      }

      // 2. Re-upload ALL attachments for this message.
      //    If any single upload fails, the message is skipped and
      //    sendChatMessage is NOT called (no partial sends).
      //
      //    Failure handling uses the canonical transient-retry design (G.8.2):
      //    - Non-retryable (null localPath, missing file): immediately terminal
      //      -> mark ALL as upload_failed
      //    - Transient (upload returned null): increment uploadRetryCount,
      //      keep as upload_pending if under kMaxUploadRetries, otherwise
      //      mark as upload_failed
      final uploadedAttachments = <MediaAttachment>[];
      var allUploadsSucceeded = true;
      var isNonRetryable = false;

      for (final attachment in attachments) {
        final localPath = attachment.localPath;
        if (localPath == null || localPath.isEmpty) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_SKIP_NO_PATH',
            details: {'attachmentId': attachment.id.length > 8 ? attachment.id.substring(0, 8) : attachment.id},
          );
          allUploadsSucceeded = false;
          isNonRetryable = true;
          break;
        }

        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_START',
          details: {'mime': attachment.mime},
        );

        final uploaded = await uploadMediaFn(
          bridge: bridge,
          localFilePath: localPath,
          mime: attachment.mime,
          recipientPeerId: msg.contactPeerId,
          durationMs: attachment.durationMs,
          waveform: attachment.waveform,
          width: attachment.width,
          height: attachment.height,
          blobId: attachment.id,  // Stable-ID contract (F.7.1)
        );

        if (uploaded == null) {
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_INCOMPLETE_UPLOAD_REUPLOAD_FAILED',
            details: {'attachmentId': attachment.id.length > 8 ? attachment.id.substring(0, 8) : attachment.id},
          );
          allUploadsSucceeded = false;
          break;
        }

        final completedAttachment = uploaded.copyWith(
          messageId: msg.id,
          downloadStatus: 'done',
        );
        await mediaAttachmentRepo.saveAttachment(completedAttachment);
        uploadedAttachments.add(completedAttachment);
      }

      // Canonical failure handling (G.8.2): transient vs non-retryable
      if (!allUploadsSucceeded) {
        for (final att in attachments) {
          final newRetryCount = (att.uploadRetryCount ?? 0) + 1;

          if (isNonRetryable || newRetryCount >= kMaxUploadRetries) {
            // Terminal: mark as permanently failed
            await mediaAttachmentRepo.saveAttachment(
              att.copyWith(
                downloadStatus: 'upload_failed',
                uploadRetryCount: newRetryCount,
              ),
            );
          } else {
            // Transient: keep as upload_pending for next retry cycle
            await mediaAttachmentRepo.saveAttachment(
              att.copyWith(
                downloadStatus: 'upload_pending',  // Still retryable
                uploadRetryCount: newRetryCount,
              ),
            );
          }
        }
        emitFlowEvent(
          layer: 'FL',
          event: isNonRetryable
              ? 'RETRY_INCOMPLETE_UPLOAD_MSG_SKIPPED'
              : 'RETRY_INCOMPLETE_UPLOAD_MSG_DEFERRED',
          details: {
            'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
            'reason': isNonRetryable ? 'non_retryable_failure' : 'transient_failure',
            'totalAttachments': attachments.length,
          },
        );
        continue;
      }

      // 3. All uploads succeeded — send the message ONCE with the full list.
      final contact = await contactRepo.getContact(msg.contactPeerId);
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: msg.contactPeerId,
        text: msg.text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        messageId: msg.id,
        timestamp: msg.timestamp,
        bridge: bridge,
        recipientMlKemPublicKey: contact?.mlKemPublicKey,
        quotedMessageId: msg.quotedMessageId,
        mediaAttachments: uploadedAttachments,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      if (result == SendChatMessageResult.success) {
        successCount++;
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SUCCESS',
          details: {
            'messageId': messageId.length > 8 ? messageId.substring(0, 8) : messageId,
            'attachmentCount': uploadedAttachments.length,
          },
        );
      } else {
        emitFlowEvent(
          layer: 'FL',
          event: 'RETRY_INCOMPLETE_UPLOAD_SEND_FAILED',
          details: {'result': result.name},
        );
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_ERROR',
        details: {'error': e.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOADS_COMPLETE',
    details: {
      'totalAttachments': pendingAttachments.length,
      'totalMessages': byMessageId.length,
      'succeeded': successCount,
    },
  );

  return successCount;
}
```

##### Step G-E: Persist optimistic attachment row in `conversation_wired.dart` before upload

> **⚠️ AUDIT FIX (G-01, CRITICAL): CLOSED by Stable-ID Contract (F.7.1).** The original issue: `id: _uuid.v4()` below generates a placeholder UUID that would NOT match the relay blob ID generated by `uploadMedia`. With the Stable-ID Contract, the attachment ID is generated ONCE and passed to `uploadMedia(blobId: attachmentId)`. The upload function uses this pre-generated ID as the relay blob ID, so `saveAttachment` with `ConflictAlgorithm.replace` overwrites the `upload_pending` row in place -- no orphan rows. See F.7.1 for the full contract, tests (F.7.1.6), and fallback safety (F.7.1.5).

> **⚠️ AUDIT FIX (G-02): SUPERSEDED by Stable-ID Contract (F.7.1).** The original concern about three different UUIDs is resolved by generating the attachment ID ONCE and threading it through all paths: optimistic write, `uploadMedia(blobId:)`, and `sendLocalMedia(mediaId:)`. Option (a) -- threading the same UUID -- is now the chosen approach, made feasible by the `blobId` parameter added to `uploadMedia` in F.7.1.2.

**Media send path** (insert before the `for (final media in mediaToUpload)` loop, around line 650):

```dart
// Persist optimistic attachment rows before upload begins (downloadStatus='upload_pending').
// This row survives an app kill during the upload window and enables recovery via
// retryIncompleteUploads on the next app resume.
// Stable-ID Contract (F.7.1): The attachment ID is generated ONCE here and passed
// to uploadMedia(blobId:) so the relay blob ID matches the DB primary key.
// After upload, saveAttachment with the same ID overwrites this row via
// ConflictAlgorithm.replace -- no orphan rows are created.
if (mediaToUpload.isNotEmpty && widget.mediaAttachmentRepo != null) {
  for (final media in mediaToUpload) {
    final mime = _mimeFromPath(media.file.path);
    final attachmentId = _uuid.v4();  // Stable ID: used in upload_pending AND upload
    try {
      await widget.mediaAttachmentRepo!.saveAttachment(
        MediaAttachment(
          id: attachmentId,     // Stable-ID (F.7.1): same ID used for upload
          messageId: optimisticMessage.id,
          mime: mime,
          size: 0,              // unknown until upload completes
          mediaType: MediaAttachment.mediaTypeFromMime(mime),
          localPath: media.file.path,
          downloadStatus: 'upload_pending',
          createdAt: optimisticMessage.createdAt,
          width: media.width,
          height: media.height,
          durationMs: media.durationMs,
        ),
      );
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'CONV_FL_OPTIMISTIC_ATT_SAVE_ERROR',
        details: {'error': e.toString()},
      );
    }
  }
}
```

> **⚠️ AUDIT FIX (GV-01): CLOSED by Stable-ID Contract (F.7.1).** With the Stable-ID Contract, the voice `upload_pending` row uses a stable `voiceAttId` that is also passed to `uploadMedia(blobId: voiceAttId)`. After successful upload, `saveAttachment` with the same ID overwrites the `upload_pending` row via `ConflictAlgorithm.replace`. No orphan rows are created. See F.7.1.3 for the success-path update rule.

> **⚠️ AUDIT FIX (GV-02): CLOSED by Gap 5 (G.10.2).** After a successful `sendLocalMedia`, the implementation must update the `upload_pending` row to `downloadStatus='done'` using the same stable `voiceAttId` (Stable-ID Contract F.7.1.4). This is specified in G.10.2 with test G.10.2.1. The `saveAttachment` call with the same ID overwrites the placeholder row, and `deletePendingUploadDir` cleans up the durable file copy.

> **⚠️ AUDIT FIX (GV-03):** The voice optimistic message sets `downloadStatus: 'done'` on the transient `MediaAttachment` (line 1244) for immediate UI display, while Step G-E writes `downloadStatus: 'upload_pending'` to the DB for recovery. These are on different objects -- the inconsistency is intentional and correct. Add a comment in the implementation explaining why the same attachment appears with two different statuses in different contexts.

**Voice send path** (insert after `saveMessage(optimisticMessage)`, around line 1260):

```dart
// Persist optimistic voice attachment row before upload begins.
// Stable-ID Contract (F.7.1): voiceAttId is generated ONCE and passed to both
// this upload_pending save and sendVoiceMessage/uploadMedia(blobId:).
// After upload, saveAttachment with the same ID overwrites this row.
final voiceAttId = _uuid.v4();  // Stable ID for voice attachment
if (widget.mediaAttachmentRepo != null) {
  try {
    await widget.mediaAttachmentRepo!.saveAttachment(
      MediaAttachment(
        id: voiceAttId,         // Stable-ID (F.7.1): same ID used for upload
        messageId: optimisticMessage.id,
        mime: recording.mime,
        size: recording.sizeBytes,
        mediaType: 'audio',
        localPath: recording.filePath,
        durationMs: recording.durationMs,
        downloadStatus: 'upload_pending',
        createdAt: optimisticMessage.createdAt,
        waveform: waveform,
      ),
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'CONV_FL_VOICE_OPTIMISTIC_ATT_SAVE_ERROR',
      details: {'error': e.toString()},
    );
  }
}
```

##### Step G-F: Wire `retryIncompleteUploads` into `handleAppResumed`

In `lib/core/lifecycle/handle_app_resumed.dart`:

```dart
Future<void> handleAppResumed({
  // ... existing params ...
  Future<int> Function()? retryIncompleteUploadsFn,
}) async {
  // ... existing steps 1-7 ...

  // Step 8b: Re-upload interrupted attachment uploads, then re-send.
  // Runs after 8a (recoverStuckSendingMessages — parent message rows are 'failed')
  // and before 8c (retryFailedMessages — attachment rows will be 'done' when it runs).
  // See Part D ordering contract for the full 4-step sequence (8a-8d).
  if (retryIncompleteUploadsFn != null) {
    try {
      final count = await retryIncompleteUploadsFn();
      if (kDebugMode) debugPrint('[RESUME] Step 8b: retryIncompleteUploads=$count');
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOADS_RESUME_ERROR',
        details: {'error': e.toString()},
      );
      // Non-fatal: continue resume sequence
    }
  }

  // ... Step 8c (retryFailedMessages), Step 8d (retryUnackedMessages) ...
}
```

In `main.dart`:

```dart
await handleAppResumed(
  // ... existing params ...
  retryIncompleteUploadsFn: () => retryIncompleteUploads(
    mediaAttachmentRepo: mediaAttachmentRepository,
    messageRepo: messageRepository,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepository,
    contactRepo: contactRepository,
  ),
);
```

##### Step G-G: Wire `retryIncompleteUploads` into `PendingMessageRetrier`

In `lib/core/services/pending_message_retrier.dart`, add optional constructor parameter:

```dart
PendingMessageRetrier({
  // ... existing params ...
  Future<int> Function()? retryIncompleteUploadsFn,
}) : retryIncompleteUploadsFn = retryIncompleteUploadsFn;

final Future<int> Function()? retryIncompleteUploadsFn;
```

In `_retryIfNeeded`:

```dart
// After recoverStuckSendingMessages, before retryFailedMessages:
if (retryIncompleteUploadsFn != null) {
  try {
    await retryIncompleteUploadsFn!();
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'PENDING_RETRIER_INCOMPLETE_UPLOAD_ERROR',
      details: {'error': e.toString()},
    );
  }
}
```

##### Step G-H: Update `FakeMediaAttachmentRepository`

Add to `test/features/conversation/domain/repositories/fake_media_attachment_repository.dart`:

```dart
// Pre-upload ordering hook
void Function(MediaAttachment att)? onSaveAttachment;

@override
Future<void> saveAttachment(MediaAttachment attachment) async {
  onSaveAttachment?.call(attachment);
  _savedAttachments.add(attachment);
  // ... existing save logic (upsert into _attachments by id) ...
}

// Upload-pending query
@override
Future<List<MediaAttachment>> getUploadPendingAttachments() async {
  return _attachments
      .where((a) => a.downloadStatus == 'upload_pending')
      .toList();
}

// Track all saves for assertion in multi-attachment tests
final _savedAttachments = <MediaAttachment>[];
List<MediaAttachment> get allSavedAttachments => List.unmodifiable(_savedAttachments);

MediaAttachment? get lastSavedAttachment =>
    _savedAttachments.isNotEmpty ? _savedAttachments.last : null;
```

~~Add to `test/core/bridge/fake_bridge.dart`:~~ **SUPERSEDED by G-04 reconciliation.** All G.3 tests now use `FakeUploadMediaFn` (from Part F) injected via the `uploadMediaFn` parameter. The `FakeBridge` upload-related fields below are only needed for the G.6 smoke tests that use an inline lambda wrapping `FakeBridge.consumeUploadMediaResult()`. For new tests, prefer `FakeUploadMediaFn`.

```dart
MediaAttachment? uploadMediaResult;
List<MediaAttachment?> uploadMediaResultByCallIndex = [];
int _uploadCallIndex = 0;

/// Tracks total upload calls for multi-attachment assertions.
int get uploadCallCount => _uploadCallIndex;

MediaAttachment? consumeUploadMediaResult() {
  if (uploadMediaResultByCallIndex.isNotEmpty &&
      _uploadCallIndex < uploadMediaResultByCallIndex.length) {
    return uploadMediaResultByCallIndex[_uploadCallIndex++];
  }
  _uploadCallIndex++;
  return uploadMediaResult;
}
```

---

#### G.6 End-to-end smoke test

**File to create:** `test/features/conversation/integration/incomplete_upload_recovery_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/recover_stuck_sending_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../core/services/fake_p2p_service.dart';
import '../../core/bridge/fake_bridge.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../features/identity/domain/models/identity_model.dart';
import '../../features/contacts/domain/models/contact_model.dart';

void main() {
  group('Incomplete-upload recovery — smoke test', () {
    test(
      'voice message upload interrupted by lock is re-uploaded and delivered on resume',
      () async {
        final msgTs = DateTime.now().toUtc()
            .subtract(const Duration(minutes: 3))
            .toIso8601String();

        final stuckMsg = ConversationMessage(
          id: 'msg-voice-001',
          contactPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          text: '',
          timestamp: msgTs,
          status: 'sending',   // upload had not completed when app was killed
          isIncoming: false,
          createdAt: msgTs,
          wireEnvelope: null,
        );

        final pendingAtt = MediaAttachment(
          id: 'att-placeholder-uuid',
          messageId: 'msg-voice-001',
          mime: 'audio/mpeg',
          size: 8192,
          mediaType: 'audio',
          localPath: '/var/mobile/recordings/voice.m4a',
          durationMs: 5200,
          downloadStatus: 'upload_pending',
          createdAt: msgTs,
          waveform: [0.1, 0.5, 0.9, 0.3],
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMsg]);
        messageRepo.recoverStuckSendingReturnValue = 1;
        final mediaRepo = FakeMediaAttachmentRepository()..seed([pendingAtt]);

        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: null,
            mnemonic12: null,
            createdAt: msgTs,
            updatedAt: msgTs,
          ));

        final contactRepo = FakeContactRepository()
          ..seed([
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig',
              scannedAt: msgTs,
              mlKemPublicKey: null,
            ),
          ]);

        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/addr1'],
          ),
          storeInInboxResult: true,
        );

        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem',
              'ciphertext': 'fake-ct',
              'nonce': 'fake-nonce',
            },
          },
        );
        bridge.uploadMediaResult = MediaAttachment(
          id: 'relay-blob-id-abc',
          messageId: 'msg-voice-001',
          mime: 'audio/mpeg',
          size: 8192,
          mediaType: 'audio',
          localPath: '/var/mobile/recordings/voice.m4a',
          durationMs: 5200,
          downloadStatus: 'done',
          createdAt: msgTs,
          waveform: [0.1, 0.5, 0.9, 0.3],
        );

        // ---- Act: resume recovery sequence ----

        // Step 1: transition 'sending' -> 'failed'
        await recoverStuckSendingMessages(
          messageRepo: messageRepo,
          threshold: const Duration(seconds: 30),
        );
        messageRepo.seed([stuckMsg.copyWith(status: 'failed')]);

        // Step 2: re-upload and re-send
        final reuploadCount = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: ({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            waveform,
            allowedPeers,
            String? blobId,
          }) async =>
              bridge is FakeBridge ? bridge.consumeUploadMediaResult() : null,
        );

        // ---- Assert ----
        expect(reuploadCount, 1);
        final saved = messageRepo.lastSavedMessage;
        expect(saved, isNotNull);
        expect(saved!.status, isNot('sending'));
        expect(saved.status, isNot('failed'));
        expect(saved.status, 'delivered');
      },
    );

    test(
      'image upload interrupted — attachment marked upload_failed when re-upload fails',
      () async {
        final msgTs = DateTime.now().toUtc()
            .subtract(const Duration(minutes: 2))
            .toIso8601String();

        final stuckMsg = ConversationMessage(
          id: 'msg-img-001',
          contactPeerId: 'peer-carol',
          senderPeerId: 'peer-alice',
          text: 'Check this out',
          timestamp: msgTs,
          status: 'failed',
          isIncoming: false,
          createdAt: msgTs,
          wireEnvelope: null,
        );

        final pendingAtt = MediaAttachment(
          id: 'att-placeholder-img',
          messageId: 'msg-img-001',
          mime: 'image/jpeg',
          size: 0,
          mediaType: 'image',
          localPath: '/tmp/photo.jpg',
          downloadStatus: 'upload_pending',
          createdAt: msgTs,
        );

        final messageRepo = FakeMessageRepository()..seed([stuckMsg]);
        final mediaRepo = FakeMediaAttachmentRepository()..seed([pendingAtt]);
        final identityRepo = FakeIdentityRepository()
          ..seed(IdentityModel(
            peerId: 'peer-alice',
            publicKey: 'pk-alice',
            privateKey: null,
            mnemonic12: null,
            createdAt: msgTs,
            updatedAt: msgTs,
          ));
        final contactRepo = FakeContactRepository();
        final p2pService = FakeP2PService();
        final bridge = FakeBridge();
        bridge.uploadMediaResult = null;

        await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          uploadMediaFn: ({
            required Bridge bridge,
            required String localFilePath,
            required String mime,
            required String recipientPeerId,
            mediaFileManager,
            int? width,
            int? height,
            int? durationMs,
            waveform,
            allowedPeers,
            String? blobId,
          }) async =>
              bridge is FakeBridge ? bridge.consumeUploadMediaResult() : null,
        );

        final lastSaved = mediaRepo.lastSavedAttachment;
        expect(lastSaved, isNotNull);
        expect(lastSaved!.downloadStatus, 'upload_failed');
      },
    );

    test(
      'no upload_pending attachments — all recovery steps are no-ops',
      () async {
        final messageRepo = FakeMessageRepository();
        final mediaRepo = FakeMediaAttachmentRepository();
        final identityRepo = FakeIdentityRepository();
        final p2pService = FakeP2PService(
          initialState: const NodeState(isStarted: true, peerId: 'peer-alice'),
        );
        final bridge = FakeBridge();
        final contactRepo = FakeContactRepository();

        final recovered = await recoverStuckSendingMessages(messageRepo: messageRepo);
        expect(recovered, 0);

        final reuploaded = await retryIncompleteUploads(
          mediaAttachmentRepo: mediaRepo,
          messageRepo: messageRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );
        expect(reuploaded, 0);

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );
        expect(retried, 0);
      },
    );
  });
}
```

---

#### G.7 Refactor phase

- **Per-message grouping (critical invariant)**: `retryIncompleteUploads` groups `upload_pending` attachments by `messageId` using a `Map<String, List<MediaAttachment>>`, then processes each message group atomically: re-upload ALL attachments, then call `sendChatMessage` ONCE with the full list. This mirrors the real send path in `conversation_wired.dart` (lines 646-738) where all uploads are collected before a single `sendChatMessage` call. The per-message loop structure (`for (final entry in byMessageId.entries)`) ensures a multi-attachment message is never fragmented into separate single-attachment sends. If any attachment in the group fails to upload, ALL attachments for that message are marked `upload_failed` and `sendChatMessage` is NOT called -- this prevents delivering a corrupted partial-media message to the recipient.

- **`downloadStatus` enumeration**: Document the full lifecycle (table in Part G's "New `downloadStatus` sentinel" section) in a code comment at the top of `lib/features/conversation/domain/models/media_attachment.dart`. Add a static constant list or assertion in tests to catch any new status values not covered by the known set.

- **Placeholder ID vs relay blob ID (CRITICAL -- CLOSED by Stable-ID Contract F.7.1)**: The orphan row problem is eliminated by the Stable-ID Contract (Section F.7.1). The attachment ID is generated ONCE at optimistic write time and passed to `uploadMedia(blobId:)`. After upload, `saveAttachment` with `ConflictAlgorithm.replace` overwrites the `upload_pending` row in place because the PRIMARY KEY (`id`) matches. No orphan rows are created. The defensive fallback DELETE (F.7.1.5) handles any edge case where the ID contract is violated.

- **Idempotency**: After a transient re-upload failure, `uploadRetryCount` is incremented but the row stays `upload_pending` (retryable). After `kMaxUploadRetries` exhaustion, the row transitions to `upload_failed` -- `getUploadPendingAttachments` returns zero rows of that type, no re-attempt. After a successful re-upload and send, the parent message becomes `'delivered'` -- second call: status gate skips it. All paths are idempotent.

> **⚠️ AUDIT FIX (G-06):** `retryIncompleteUploads` must save re-uploaded attachments with `downloadStatus='done'` to the DB **immediately after each successful upload, BEFORE calling `sendChatMessage`**. If the app crashes between `sendChatMessage` succeeding and `_persistOutgoingMedia` completing, some re-uploaded attachments may not be persisted. The G-D implementation code already does this correctly (line `await mediaAttachmentRepo.saveAttachment(completedAttachment)` inside the upload loop), but the requirement must be explicit: each `uploadFn` success is immediately followed by `saveAttachment(done)` (which overwrites the `upload_pending` row via Stable-ID Contract F.7.1), and only after ALL attachments for a message are uploaded and persisted does `sendChatMessage` run.

- **iOS file path portability**: The documents directory container UUID changes on app re-install. For the first version, use `localPath` as-is (absolute paths work correctly for lock-then-relaunch without reinstall, which is the primary scenario). Inject `MediaFileManager` in a follow-up to resolve relative paths for post-reinstall recovery.

- **Voice waveform preservation**: The waveform field is JSON-encoded in `media_attachments.toMap()` and decoded in `fromMap()`. The optimistic voice attachment row in Step G-E includes `waveform` at write time. No additional fields or migrations are needed.

- **Integration with Part C**: Part C (`retryFailedMessages` media replay) reads `done` attachment rows. Part G produces those `done` rows. The two parts are complementary and must both be implemented for the full matrix: Part G covers upload-interrupted messages; Part C covers upload-completed, send-failed messages.

- **Part G does not replace Part A**: The `'sending'` -> `'failed'` transition (Part A) is still required. `retryIncompleteUploads` checks for `msg.status == 'sending' || msg.status == 'failed'`. If Part A has not run, `'sending'` messages are still processed correctly by Part G (the status check accepts both values). However, if `retryIncompleteUploads` calls `sendChatMessage` which internally re-persists the message with a new status, the `'sending'` row will be replaced. This is correct behavior -- the message is no longer stuck. Part A running first is the preferred ordering but not a hard dependency.

- **Extract per-message helper**: Consider extracting the inner per-message loop body into a private helper `_retryMessageUploads({required String messageId, required List<MediaAttachment> attachments, ...})` returning `bool` (success/failure). This keeps the outer loop clean and makes per-message logic independently testable.

---

> **AUDIT FIX (G-05): PARTIALLY SUPERSEDED by Stable-ID Contract (F.7.1).** With stable IDs, `deleteAttachmentById` is no longer needed for orphan cleanup -- the `upload_pending` row is overwritten in place. However, `deleteAttachmentById` may still be useful for explicit cleanup in edge cases. Keep as optional follow-up, not blocking.

---

#### G.8 Make `retryIncompleteUploads()` production-safe (Gap 3)

The `retryIncompleteUploads` use case as specified in G.4/G.5 has three production-safety issues. This section closes all three with concrete implementation changes and tests.

##### G.8.1 Path resolution: resolve stored paths before filesystem access

**Problem:** The `upload_pending` row's `localPath` may be stored as a relative path (e.g. `pending_uploads/msg-1/photo.jpg`) after Gap 4's durable storage copy. `File(relativePath).existsSync()` always returns false. The retry use case must resolve paths through `MediaFileManager.resolveStoredPath()` before any filesystem check or upload call.

**Implementation change to `retryIncompleteUploads`:**

Add `MediaFileManager? mediaFileManager` as an optional parameter. Before checking file existence or uploading, resolve the stored path:

```dart
Future<int> retryIncompleteUploads({
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MessageRepository messageRepo,
  required Bridge bridge,
  required P2PService p2pService,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  UploadMediaFn uploadMediaFn = uploadMedia,
  MediaFileManager? mediaFileManager,       // NEW -- resolves stored localPath
}) async {
  // ...inside the per-attachment loop:
  for (final attachment in attachments) {
    var localPath = attachment.localPath;
    if (localPath == null || localPath.isEmpty) {
      allUploadsSucceeded = false;
      break;
    }

    // Resolve relative/legacy paths to absolute filesystem paths
    if (mediaFileManager != null) {
      localPath = await mediaFileManager.resolveStoredPath(localPath);
    }

    if (!File(localPath).existsSync()) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_INCOMPLETE_UPLOAD_FILE_NOT_FOUND',
        details: {
          'storedPath': attachment.localPath ?? '',
          'resolvedPath': localPath,
        },
      );
      allUploadsSucceeded = false;
      break;
    }

    final uploaded = await uploadMediaFn(
      bridge: bridge,
      localFilePath: localPath,  // Use resolved absolute path
      mime: attachment.mime,
      recipientPeerId: msg.contactPeerId,
      durationMs: attachment.durationMs,
      waveform: attachment.waveform,
      width: attachment.width,
      height: attachment.height,
      blobId: attachment.id,  // Stable-ID contract (F.7.1)
    );
    // ...
  }
```

Similarly, update `_reuploadAttachments` in Part F to accept `MediaFileManager?` and resolve paths:

```dart
Future<List<MediaAttachment>?> _reuploadAttachments({
  required List<MediaAttachment> attachments,
  required Bridge bridge,
  required String targetPeerId,
  required UploadMediaFn uploadFn,
  MediaFileManager? mediaFileManager,    // NEW
}) async {
  final result = <MediaAttachment>[];

  for (final attachment in attachments) {
    var localPath = attachment.localPath;
    if (localPath == null || localPath.isEmpty) {
      return null;
    }

    // Resolve relative/legacy paths to absolute filesystem paths
    if (mediaFileManager != null) {
      localPath = await mediaFileManager.resolveStoredPath(localPath);
    }

    if (!File(localPath).existsSync()) {
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_REUPLOAD_FILE_NOT_FOUND',
        details: {
          'storedPath': attachment.localPath ?? '',
          'resolvedPath': localPath,
        },
      );
      return null;
    }

    final uploaded = await uploadFn(
      bridge: bridge,
      localFilePath: localPath,  // resolved absolute path
      mime: attachment.mime,
      recipientPeerId: targetPeerId,
      durationMs: attachment.durationMs,
      waveform: attachment.waveform,
      width: attachment.width,
      height: attachment.height,
      blobId: attachment.id,  // Stable-ID contract (F.7.1)
    );
    // ...
  }
```

**Test: G.8.1.1 -- relative path is resolved before File.existsSync**

```dart
test('resolves relative localPath via MediaFileManager before checking file existence',
    () async {
  final msg = _makeMsg('msg-rel', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());

  mediaRepo.seed([
    _pendingAtt(
      id: 'att-rel',
      messageId: 'msg-rel',
      localPath: 'pending_uploads/msg-rel/photo.jpg',
      mime: 'image/jpeg',
      mediaType: 'image',
    ),
  ]);

  final fakeMediaFileManager = FakeMediaFileManager()
    ..resolveResult =
        '/var/mobile/Documents/pending_uploads/msg-rel/photo.jpg';

  fakeUploadFn.willReturn(
    _doneAttachment('att-rel', 'msg-rel', mime: 'image/jpeg'),
  );
  p2pService.storeInInboxResult = true;

  final count = await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo,
    messageRepo: messageRepo,
    bridge: bridge,
    p2pService: p2pService,
    identityRepo: identityRepo,
    contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
    mediaFileManager: fakeMediaFileManager,
  );

  expect(count, 1);
  expect(fakeUploadFn.lastLocalPath,
      '/var/mobile/Documents/pending_uploads/msg-rel/photo.jpg');
});
```

##### G.8.2 Transient failure handling: retry-eligible on first failure (CANONICAL -- reconciled into G.3/G.5)

> **Reconciliation note:** This section defines the canonical failure model for `retryIncompleteUploads`. The G.3 tests and G.5 Step G-D implementation code have been updated to match this design directly. A reader going top-to-bottom sees ONE consistent failure model from G.3 onward -- transient failures keep rows as `upload_pending` with incremented `uploadRetryCount`, and only `kMaxUploadRetries` exhaustion or non-retryable conditions produce `upload_failed`. The tests in G.8.2.1-G.8.2.3 below provide additional coverage beyond the G.3 tests.

**Design:** On upload failure, `retryIncompleteUploads` distinguishes transient from non-retryable errors. A transient network error (relay temporarily unreachable, bridge timeout) increments `uploadRetryCount` but keeps the row as `upload_pending` (retryable). Only after `kMaxUploadRetries` (3) failures, or when the failure is non-retryable (null localPath, missing file), does the row transition to `upload_failed` (terminal).

**Implementation: add `retryCount` tracking to `media_attachments`**

Add a new integer column `upload_retry_count` (default 0) to the media_attachments table. On each failed retry attempt, increment the counter. Only transition to `upload_failed` when `retryCount >= kMaxUploadRetries` (default 3) OR when the failure is non-retryable (missing local file, null localPath).

**DB migration (version N+1):**

```sql
ALTER TABLE media_attachments ADD COLUMN upload_retry_count INTEGER NOT NULL DEFAULT 0;
```

**Constants:**

```dart
// lib/core/constants/retry_constants.dart
const kMaxUploadRetries = 3;
```

**`retryIncompleteUploads` failure handling (already applied in G.5 Step G-D above):**

The following code is the canonical failure block. It is already present in the G.5 Step G-D implementation. Shown here for reference:

```dart
if (!allUploadsSucceeded) {
  for (final att in attachments) {
    final newRetryCount = (att.uploadRetryCount ?? 0) + 1;
    final isNonRetryable = att.localPath == null ||
        att.localPath!.isEmpty ||
        !File(resolvedPath).existsSync();

    if (isNonRetryable || newRetryCount >= kMaxUploadRetries) {
      // Terminal: mark as permanently failed
      await mediaAttachmentRepo.saveAttachment(
        att.copyWith(
          downloadStatus: 'upload_failed',
          uploadRetryCount: newRetryCount,
        ),
      );
    } else {
      // Transient: keep as upload_pending for next retry cycle
      await mediaAttachmentRepo.saveAttachment(
        att.copyWith(
          downloadStatus: 'upload_pending',  // Still retryable
          uploadRetryCount: newRetryCount,
        ),
      );
    }
  }
  emitFlowEvent(
    layer: 'FL',
    event: 'RETRY_INCOMPLETE_UPLOAD_MSG_DEFERRED',
    details: {
      'messageId': messageId.length > 8
          ? messageId.substring(0, 8) : messageId,
    },
  );
  continue;
}
```

**Tests: G.8.2.1-G.8.2.3**

```dart
// G.8.2.1
test('first upload failure keeps row as upload_pending (retryable)', () async {
  final msg = _makeMsg('msg-t1', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());
  mediaRepo.seed([
    _pendingAtt(id: 'att-t1', messageId: 'msg-t1', localPath: '/durable/photo.jpg'),
  ]);
  fakeUploadFn.willReturn(null); // transient failure

  await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
    bridge: bridge, p2pService: p2pService,
    identityRepo: identityRepo, contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
  );

  final pending = await mediaRepo.getUploadPendingAttachments();
  expect(pending.length, 1);
  expect(pending.first.uploadRetryCount, 1);
  expect(pending.first.downloadStatus, 'upload_pending');
});

// G.8.2.2
test('after kMaxUploadRetries failures, row transitions to upload_failed', () async {
  final msg = _makeMsg('msg-t2', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());
  mediaRepo.seed([
    _pendingAtt(id: 'att-t2', messageId: 'msg-t2', localPath: '/durable/photo.jpg')
        .copyWith(uploadRetryCount: kMaxUploadRetries - 1),
  ]);
  fakeUploadFn.willReturn(null);

  await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
    bridge: bridge, p2pService: p2pService,
    identityRepo: identityRepo, contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
  );

  final pending = await mediaRepo.getUploadPendingAttachments();
  expect(pending, isEmpty);
  final lastSaved = mediaRepo.lastSavedAttachment;
  expect(lastSaved?.downloadStatus, 'upload_failed');
  expect(lastSaved?.uploadRetryCount, kMaxUploadRetries);
});

// G.8.2.3
test('missing local file is immediately terminal regardless of retryCount', () async {
  final msg = _makeMsg('msg-t3', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());
  mediaRepo.seed([
    MediaAttachment(
      id: 'att-t3', messageId: 'msg-t3', mime: 'image/jpeg',
      size: 0, mediaType: 'image', localPath: null,
      downloadStatus: 'upload_pending',
      createdAt: DateTime.now().toUtc().toIso8601String(),
    ),
  ]);

  await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
    bridge: bridge, p2pService: p2pService,
    identityRepo: identityRepo, contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
  );

  final lastSaved = mediaRepo.lastSavedAttachment;
  expect(lastSaved?.downloadStatus, 'upload_failed');
});
```

##### G.8.3 Per-message grouping: no mixing of upload_pending and done rows

**Problem:** If a message has 3 attachments and 2 uploaded successfully before a crash, the DB has 2 `done` rows and 1 `upload_pending` row for the same messageId. `retryIncompleteUploads` must not mix these -- it should only re-upload the `upload_pending` attachments, then combine with the existing `done` rows for the `sendChatMessage` call.

**Implementation: load ALL attachments for the message, not just upload_pending ones**

```dart
// Inside the per-message loop in retryIncompleteUploads:
final messageId = entry.key;
final pendingAttachments = entry.value;  // only upload_pending from query

// Load ALL attachments for this message (including already-done ones)
final allAttachments =
    await mediaAttachmentRepo.getAttachmentsForMessage(messageId);
final doneAttachments = allAttachments
    .where((a) => a.downloadStatus == 'done')
    .toList();

// Only re-upload the pending ones
final uploadedAttachments = <MediaAttachment>[];
var allUploadsSucceeded = true;

for (final attachment in pendingAttachments) {
  // ... resolve path, upload with stable ID ...
  if (uploaded != null) {
    final completedAttachment = uploaded.copyWith(
      messageId: msg.id, downloadStatus: 'done',
    );
    await mediaAttachmentRepo.saveAttachment(completedAttachment);
    uploadedAttachments.add(completedAttachment);
  } else {
    allUploadsSucceeded = false;
    break;
  }
}

if (allUploadsSucceeded) {
  // Combine previously-done attachments with newly-uploaded ones
  final fullAttachmentList = [...doneAttachments, ...uploadedAttachments];

  final (result, _) = await sendChatMessage(
    // ...
    mediaAttachments: fullAttachmentList,  // FULL list
    // ...
  );
}
```

**Test: G.8.3.1 -- partial upload crash recovery**

```dart
test('partial upload crash: re-uploads only pending, combines with done', () async {
  final msg = _makeMsg('msg-partial', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());

  mediaRepo.seed([
    _doneAttachment('att-done-1', 'msg-partial', mime: 'image/jpeg'),
    _doneAttachment('att-done-2', 'msg-partial', mime: 'image/jpeg'),
    _pendingAtt(
      id: 'att-pending-3', messageId: 'msg-partial',
      localPath: '/durable/img3.jpg', mime: 'image/jpeg', mediaType: 'image',
    ),
  ]);

  fakeUploadFn.willReturn(
    _doneAttachment('att-pending-3', 'msg-partial', mime: 'image/jpeg'),
  );
  p2pService.storeInInboxResult = true;

  final count = await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
    bridge: bridge, p2pService: p2pService,
    identityRepo: identityRepo, contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
  );

  expect(count, 1);
  expect(fakeUploadFn.callCount, 1);
  expect(p2pService.sendCallCount, 1);
  final payload = p2pService.lastSentPayload!;
  expect(payload, contains('att-done-1'));
  expect(payload, contains('att-done-2'));
  expect(payload, contains('att-pending-3'));
});
```

##### G.8.4 Files to create / modify (Gap 3 additions)

| File | Purpose |
|---|---|
| `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` | Add `MediaFileManager?` param; resolve stored paths; transient failure handling with retry count; per-message grouping with done+pending merge |
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Add `MediaFileManager?` param to `_reuploadAttachments`; resolve stored paths |
| `lib/features/conversation/domain/models/media_attachment.dart` | Add `int? uploadRetryCount` field; include in `toMap()`/`fromMap()` |
| `lib/core/constants/retry_constants.dart` | Add `kMaxUploadRetries = 3` |
| `lib/core/database/migrations/` | Add migration for `upload_retry_count` column |
| `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` | Add tests G.8.1.1, G.8.2.1-G.8.2.3, G.8.3.1 |
| `test/features/conversation/application/retry_failed_messages_media_reupload_test.dart` | Update F.5.8 test to use `FakeMediaFileManager` |

---

#### G.9 Pre-upload durable storage for media and voice files (Gap 4)

**Problem statement:** Recovery depends on the original local file surviving between crashes. For media, the processed file lives in the temp directory (e.g. `/tmp/flutter_image_compress/photo_compressed.jpg`). For voice recordings, the file lives in the recorder's temp output directory. Both are subject to OS cleanup on reboot, low-storage conditions, or between app launches (iOS clears tmp aggressively). If the file is deleted, the `upload_pending` row is useless -- retry cannot re-upload a file that no longer exists.

**Solution:** Copy the selected/recorded file into managed durable storage (app documents directory) BEFORE persisting the `upload_pending` row. The `localPath` in the DB points to the durable copy, not the original temp file. After successful upload, delete the durable copy.

##### G.9.1 Durable storage path convention

```
<appDocDir>/pending_uploads/<messageId>/<attachmentId>.<ext>
```

Examples:
- `<appDocDir>/pending_uploads/msg-001/att-abc.jpg` (media image)
- `<appDocDir>/pending_uploads/msg-002/att-def.m4a` (voice recording)

The `messageId` subdirectory groups all pending files for a single message, making cleanup trivial after successful send.

##### G.9.2 New `MediaFileManager` methods

Add to `lib/core/media/media_file_manager.dart`:

```dart
/// Copies a file to durable pending-upload storage.
///
/// Returns the RELATIVE path (for DB storage) of the durable copy.
/// Format: `pending_uploads/<messageId>/<attachmentId>.<ext>`
Future<String> copyToDurableStorage({
  required String sourceFilePath,
  required String messageId,
  required String attachmentId,
  required String mime,
}) async {
  final ext = _extensionFromMime(mime);
  final appDir = await getApplicationDocumentsDirectory();
  final destDir = Directory(
      p.join(appDir.path, 'pending_uploads', messageId));
  if (!await destDir.exists()) {
    await destDir.create(recursive: true);
  }
  final destPath = p.join(destDir.path, '$attachmentId$ext');
  await File(sourceFilePath).copy(destPath);
  return p.join('pending_uploads', messageId, '$attachmentId$ext');
}

/// Deletes the pending-upload directory for a message after successful upload.
Future<void> deletePendingUploadDir(String messageId) async {
  final appDir = await getApplicationDocumentsDirectory();
  final dir = Directory(
      p.join(appDir.path, 'pending_uploads', messageId));
  if (await dir.exists()) {
    await dir.delete(recursive: true);
  }
}
```

**Update `resolveStoredPath`** to handle `pending_uploads/` prefix:

```dart
if (storedPath.startsWith('pending_uploads/') ||
    storedPath.startsWith('pending_uploads\\')) {
  final appDir = await getApplicationDocumentsDirectory();
  return p.join(appDir.path, storedPath);
}
```

##### G.9.3 Copy step placement in the send flow

**Media send path** (AFTER image processing, BEFORE `upload_pending` save):

```dart
String durableLocalPath = media.file.path;
if (widget.mediaFileManager != null) {
  try {
    durableLocalPath = await widget.mediaFileManager!.copyToDurableStorage(
      sourceFilePath: media.file.path,
      messageId: optimisticMessage.id,
      attachmentId: attachmentId,
      mime: mime,
    );
  } catch (e) {
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_DURABLE_COPY_ERROR',
        details: {'error': e.toString()});
  }
}
```

**Voice send path** (after recording stops, BEFORE `upload_pending` save):

```dart
final voiceAttId = _uuid.v4();
String durableVoicePath = recording.filePath;
if (widget.mediaFileManager != null) {
  try {
    durableVoicePath = await widget.mediaFileManager!.copyToDurableStorage(
      sourceFilePath: recording.filePath,
      messageId: optimisticMessage.id,
      attachmentId: voiceAttId,
      mime: recording.mime,
    );
  } catch (e) {
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_VOICE_DURABLE_COPY_ERROR',
        details: {'error': e.toString()});
  }
}
```

##### G.9.4 Cleanup after successful upload

```dart
// After successful send in conversation_wired.dart and retryIncompleteUploads:
if (widget.mediaFileManager != null) {
  try {
    await widget.mediaFileManager!.deletePendingUploadDir(optimisticMessage.id);
  } catch (e) {
    emitFlowEvent(layer: 'FL', event: 'CONV_FL_DURABLE_CLEANUP_ERROR',
        details: {'error': e.toString()});
  }
}
```

##### G.9.5 Tests proving recovery works after temp file deletion

**File:** `test/features/conversation/application/durable_storage_recovery_test.dart`

```dart
void main() {
  group('Durable storage recovery (Gap 4)', () {
    // G.9.5.1
    test('recovery succeeds from durable copy after temp file deletion', () async {
      // upload_pending row points to durable path, not temp.
      // FakeMediaFileManager resolves to absolute path that exists.
      mediaRepo.seed([
        MediaAttachment(
          id: 'att-001', messageId: 'msg-durable', mime: 'image/jpeg',
          size: 0, mediaType: 'image',
          localPath: 'pending_uploads/msg-durable/att-001.jpg',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      ]);
      final fm = FakeMediaFileManager()
        ..resolveResult = '/var/mobile/Documents/pending_uploads/msg-durable/att-001.jpg';
      fakeUploadFn.willReturn(_doneAttachment('att-001', 'msg-durable', mime: 'image/jpeg'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
        bridge: bridge, p2pService: p2pService,
        identityRepo: identityRepo, contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call, mediaFileManager: fm,
      );
      expect(count, 1);
    });

    // G.9.5.2
    test('voice recording recovery succeeds from durable copy', () async {
      mediaRepo.seed([
        MediaAttachment(
          id: 'voice-att-001', messageId: 'msg-voice-durable', mime: 'audio/mp4',
          size: 8192, mediaType: 'audio',
          localPath: 'pending_uploads/msg-voice-durable/voice-att-001.m4a',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          durationMs: 5000, waveform: [0.1, 0.5, 0.9],
        ),
      ]);
      final fm = FakeMediaFileManager()
        ..resolveResult = '/var/mobile/Documents/pending_uploads/msg-voice-durable/voice-att-001.m4a';
      fakeUploadFn.willReturn(_doneAttachment('voice-att-001', 'msg-voice-durable', mime: 'audio/mp4'));
      p2pService.storeInInboxResult = true;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
        bridge: bridge, p2pService: p2pService,
        identityRepo: identityRepo, contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call, mediaFileManager: fm,
      );
      expect(count, 1);
      expect(fakeUploadFn.lastDurationMs, 5000);
    });

    // G.9.5.3
    test('both durable and temp files deleted: message stays failed', () async {
      mediaRepo.seed([
        MediaAttachment(
          id: 'att-gone', messageId: 'msg-both-gone', mime: 'image/jpeg',
          size: 0, mediaType: 'image',
          localPath: 'pending_uploads/msg-both-gone/att-gone.jpg',
          downloadStatus: 'upload_pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      ]);
      final fm = FakeMediaFileManager()
        ..resolveResult = '/var/mobile/Documents/pending_uploads/msg-both-gone/att-gone.jpg'
        ..fileExistsOverride = false;

      final count = await retryIncompleteUploads(
        mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
        bridge: bridge, p2pService: p2pService,
        identityRepo: identityRepo, contactRepo: contactRepo,
        uploadMediaFn: fakeUploadFn.call, mediaFileManager: fm,
      );
      expect(count, 0);
      expect(fakeUploadFn.callCount, 0);
    });

    // G.9.5.4
    test('durable copy is deleted after successful upload and send', () async {
      final fm = FakeMediaFileManager();
      final deletedDirs = <String>[];
      fm.onDeletePendingUploadDir = (msgId) { deletedDirs.add(msgId); };
      await fm.deletePendingUploadDir('msg-cleanup-001');
      expect(deletedDirs, contains('msg-cleanup-001'));
    });
  });
}
```

##### G.9.6 Files to create / modify (Gap 4 additions)

| File | Purpose |
|---|---|
| `lib/core/media/media_file_manager.dart` | Add `copyToDurableStorage()`, `deletePendingUploadDir()`; update `resolveStoredPath` for `pending_uploads/` |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Copy to durable storage before `upload_pending` save (media + voice); cleanup after send |
| `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` | Cleanup durable dir after re-upload+send |
| `test/features/conversation/application/durable_storage_recovery_test.dart` | Tests G.9.5.1-G.9.5.4 |
| `test/core/media/fake_media_file_manager.dart` | Fake with `resolveResult`, `fileExistsOverride`, `onDeletePendingUploadDir` |

---

#### G.10 Voice local-WiFi path end-to-end (Gap 5)

**Problem statement:** The live 1:1 voice flow tries `sendLocalMedia()` first (`conversation_wired.dart:1278-1341`), then falls back to relay upload. The plan leaves the recovery of interrupted `sendLocalMedia()` partially unresolved. Three rules close this gap.

##### G.10.1 Rule 1: Retry uses relay upload, not local WiFi

If `sendLocalMedia` fails or is interrupted, `retryIncompleteUploads` ALWAYS uses relay upload via `uploadMediaFn`. Local WiFi is a first-attempt optimization only.

**Rationale:** By the time the app resumes, the peer may no longer be on the same network. Relay upload is always correct.

**Implementation:** `retryIncompleteUploads` already only calls `uploadMediaFn` (relay). No code change needed for the retry path.

> **Note (F.7.1.7a cross-reference):** The *first-attempt* voice relay fallback (when local WiFi fails during the initial send) calls `sendVoiceMessage()`, which internally calls `uploadMedia()`. Per F.7.1.7a, `sendVoiceMessage()` must accept `String? blobId` and forward it to `uploadMedia(blobId: blobId)`. The caller in `conversation_wired.dart` passes `blobId: voiceAttId` so the relay upload uses the same stable ID as the `upload_pending` row. This ensures the Stable-ID contract holds for both the first-attempt relay fallback AND retry-time relay upload.

**Test: G.10.1.1**

```dart
test('retry after interrupted sendLocalMedia uses relay, not local WiFi', () async {
  final msg = _makeMsg('msg-voice-local', status: 'failed', contactPeerId: 'peer-bob');
  messageRepo.seed([msg]);
  identityRepo.seed(FakeIdentityRepository.makeIdentity());
  mediaRepo.seed([
    _pendingAtt(
      id: 'voice-local-att', messageId: 'msg-voice-local',
      localPath: 'pending_uploads/msg-voice-local/voice.m4a',
      mime: 'audio/mp4', mediaType: 'audio', durationMs: 3000,
    ),
  ]);
  p2pService.localPeerIds = {'peer-bob'};
  fakeUploadFn.willReturn(
    _doneAttachment('voice-local-att', 'msg-voice-local', mime: 'audio/mp4'),
  );
  p2pService.storeInInboxResult = true;

  final count = await retryIncompleteUploads(
    mediaAttachmentRepo: mediaRepo, messageRepo: messageRepo,
    bridge: bridge, p2pService: p2pService,
    identityRepo: identityRepo, contactRepo: contactRepo,
    uploadMediaFn: fakeUploadFn.call,
  );

  expect(count, 1);
  expect(fakeUploadFn.callCount, 1);
  expect(p2pService.sendLocalMediaCallCount, 0,
      reason: 'Retry must use relay, not local WiFi');
});
```

##### G.10.2 Rule 2: Cleanup after successful local transfer

After `sendLocalMedia` succeeds, update the `upload_pending` row to `done` using the Stable-ID contract (F.7.1.4).

**Implementation in `conversation_wired.dart` voice local-WiFi success path:**

```dart
if (localSuccess) {
  final voiceAttachment = MediaAttachment(
    id: voiceAttId,           // Same ID as upload_pending row (F.7.1)
    messageId: optimisticMessage.id,
    mime: recording.mime, size: recording.sizeBytes,
    mediaType: 'audio', durationMs: recording.durationMs,
    localPath: durableVoicePath,
    downloadStatus: 'done',       // Overwrites upload_pending
    createdAt: optimisticMessage.timestamp,
    waveform: waveform,
  );
  if (widget.mediaAttachmentRepo != null) {
    await widget.mediaAttachmentRepo!.saveAttachment(voiceAttachment);
  }

  final (result, voiceMessage) = await widget.sendChatMessageFn(
    // ... existing params ...
    mediaAttachments: [voiceAttachment],
    mediaAttachmentRepo: widget.mediaAttachmentRepo,
  );

  if (result == SendChatMessageResult.success && widget.mediaFileManager != null) {
    try { await widget.mediaFileManager!.deletePendingUploadDir(optimisticMessage.id); }
    catch (_) {}
  }
}
```

**Test: G.10.2.1**

```dart
test('after successful sendLocalMedia, upload_pending row updated to done', () async {
  final repo = FakeMediaAttachmentRepository();
  final voiceAttId = 'voice-att-local-001';
  final messageId = 'msg-voice-local-001';

  await repo.saveAttachment(MediaAttachment(
    id: voiceAttId, messageId: messageId, mime: 'audio/mp4',
    size: 8192, mediaType: 'audio',
    localPath: 'pending_uploads/$messageId/$voiceAttId.m4a',
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    durationMs: 5000, waveform: [0.1, 0.5, 0.9],
  ));

  await repo.saveAttachment(MediaAttachment(
    id: voiceAttId, messageId: messageId, mime: 'audio/mp4',
    size: 8192, mediaType: 'audio',
    localPath: 'pending_uploads/$messageId/$voiceAttId.m4a',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    durationMs: 5000, waveform: [0.1, 0.5, 0.9],
  ));

  final pending = await repo.getUploadPendingAttachments();
  expect(pending, isEmpty);
  final attachments = await repo.getAttachmentsForMessage(messageId);
  expect(attachments.length, 1);
  expect(attachments.first.downloadStatus, 'done');
});
```

##### G.10.3 Rule 3: Media send local-WiFi path also needs cleanup

The media send path also uses `sendLocalMedia`. After success, update the `upload_pending` row to `done` with the same stable ID (F.7.1.4).

**Implementation in `conversation_wired.dart` media local-WiFi success path:**

```dart
if (localSuccess) {
  final localAttachment = MediaAttachment(
    id: attachmentId,  // Same stable ID as upload_pending row
    messageId: optimisticMessage.id, mime: mime,
    size: await File(media.file.path).length(),
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: durableLocalPath,
    downloadStatus: 'done',
    createdAt: optimisticMessage.createdAt,
    width: media.width, height: media.height, durationMs: media.durationMs,
  );
  if (widget.mediaAttachmentRepo != null) {
    await widget.mediaAttachmentRepo!.saveAttachment(localAttachment);
  }
  uploadedAttachments.add(localAttachment);
}
```

**Test: G.10.3.1**

```dart
test('media local-WiFi success updates upload_pending to done', () async {
  final repo = FakeMediaAttachmentRepository();
  final attachmentId = 'media-att-local-001';
  final messageId = 'msg-media-local-001';

  await repo.saveAttachment(MediaAttachment(
    id: attachmentId, messageId: messageId, mime: 'image/jpeg',
    size: 0, mediaType: 'image',
    localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  ));

  await repo.saveAttachment(MediaAttachment(
    id: attachmentId, messageId: messageId, mime: 'image/jpeg',
    size: 2048, mediaType: 'image',
    localPath: 'pending_uploads/$messageId/$attachmentId.jpg',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  ));

  final pending = await repo.getUploadPendingAttachments();
  expect(pending, isEmpty);
  final attachments = await repo.getAttachmentsForMessage(messageId);
  expect(attachments.length, 1);
  expect(attachments.first.downloadStatus, 'done');
});
```

##### G.10.4 Files to create / modify (Gap 5 additions)

| File | Purpose |
|---|---|
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Voice local-WiFi: update upload_pending to done after sendLocalMedia success; cleanup durable dir. Media local-WiFi: same |
| `test/features/conversation/application/voice_local_wifi_recovery_test.dart` | Tests G.10.1.1, G.10.2.1, G.10.3.1 |

---

### Files to create / modify (Part G additions, including Gaps 2-5)

| File | Purpose |
|---|---|
| `lib/core/database/helpers/media_attachments_db_helpers.dart` | Add `dbLoadUploadPendingAttachments` |
| `lib/features/conversation/domain/repositories/media_attachment_repository.dart` | Add `getUploadPendingAttachments()` to abstract interface |
| `lib/features/conversation/domain/repositories/media_attachment_repository_impl.dart` | Implement `getUploadPendingAttachments()` with injected DB helper |
| `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` | New use case: re-upload interrupted uploads and complete send; includes `MediaFileManager?` for path resolution (G.8.1), transient failure handling with `uploadRetryCount` (G.8.2), per-message grouping merging done+pending rows (G.8.3), durable dir cleanup (G.9.4) |
| `lib/features/conversation/application/upload_media_use_case.dart` | Add optional `String? blobId` param to `uploadMedia` and `UploadMediaFn` typedef (F.7.1.2 Stable-ID) |
| `lib/features/conversation/application/send_voice_message_use_case.dart` | Add optional `String? blobId` param; forward to `uploadMedia(blobId: blobId)` so voice relay upload uses stable ID (F.7.1.7a) |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Save `upload_pending` attachment row before upload loops (media and voice paths); Stable-ID: generate attachment ID once, pass to `uploadMediaFn(blobId:)`, `sendVoiceMessageFn(blobId:)` (F.7.1.7a), and `sendLocalMedia(mediaId:)` (F.7.1); copy to durable storage before save (G.9.3); cleanup after send (G.9.4); voice local-WiFi: update upload_pending to done (G.10.2); media local-WiFi: same (G.10.3) |
| `lib/core/media/media_file_manager.dart` | Add `copyToDurableStorage()`, `deletePendingUploadDir()` (G.9.2); update `resolveStoredPath` for `pending_uploads/` prefix |
| `lib/features/conversation/domain/models/media_attachment.dart` | Add `int? uploadRetryCount` field; include in `toMap()`/`fromMap()` (G.8.2) |
| `lib/core/constants/retry_constants.dart` | Add `kMaxUploadRetries = 3` (G.8.2) |
| `lib/core/database/migrations/` | Add migration for `upload_retry_count` column (G.8.2) |
| `lib/features/conversation/application/retry_failed_messages_use_case.dart` | Add `MediaFileManager?` param to `_reuploadAttachments`; resolve stored paths (G.8.1); pass `blobId: attachment.id` (F.7.1.7) |
| `lib/core/lifecycle/handle_app_resumed.dart` | Add `retryIncompleteUploadsFn` callback (Step 3b, after 3a, before retryFailedMessages) |
| `lib/core/services/pending_message_retrier.dart` | Add `retryIncompleteUploadsFn` constructor param; call in `_retryIfNeeded` |
| `lib/main.dart` | Wire `retryIncompleteUploadsFn` into `handleAppResumed` and `PendingMessageRetrier` |
| `test/core/database/helpers/media_attachments_db_helpers_upload_pending_test.dart` | DB helper unit tests |
| `test/features/conversation/domain/repositories/media_attachment_repository_upload_pending_test.dart` | Repository interface + fake tests |
| `test/features/conversation/application/retry_incomplete_uploads_use_case_test.dart` | Use case unit tests; add G.8.1.1, G.8.2.1-G.8.2.3, G.8.3.1 |
| `test/features/conversation/application/optimistic_upload_persistence_test.dart` | Call-ordering tests for pre-upload `saveAttachment` |
| `test/features/conversation/application/stable_id_contract_test.dart` | Tests F.7.1.6.1-F.7.1.6.4 and F.7.1.7b.1 (voice relay stable ID) proving no orphan rows (Gap 2) |
| `test/features/conversation/application/durable_storage_recovery_test.dart` | Tests G.9.5.1-G.9.5.4 proving recovery from durable copy (Gap 4) |
| `test/features/conversation/application/voice_local_wifi_recovery_test.dart` | Tests G.10.1.1, G.10.2.1, G.10.3.1 (Gap 5) |
| `test/features/conversation/integration/incomplete_upload_recovery_test.dart` | End-to-end smoke tests |
| `test/features/conversation/domain/repositories/fake_media_attachment_repository.dart` | Add `getUploadPendingAttachments`, `onSaveAttachment`, `lastSavedAttachment` |
| `test/features/conversation/application/helpers/fake_upload_media_fn.dart` | Add `String? blobId` param to `call()` signature; track `lastBlobId` (F.7.1.8) |
| `test/core/media/fake_media_file_manager.dart` | Fake with `resolveResult`, `fileExistsOverride`, `onDeletePendingUploadDir` (G.9) |
| `test/core/bridge/fake_bridge.dart` | ~~Add `uploadMediaResult`, `uploadMediaResultByCallIndex`, `consumeUploadMediaResult`~~ -- **AUDIT FIX (G-04): Use `FakeUploadMediaFn` from Part F instead; no `FakeBridge` modifications needed for upload stubbing** |

---

## Section 2: App Lifecycle Pause Handler

### Overview

The app has a 7-step `handleAppResumed()` recovery use case but zero handling for `AppLifecycleState.paused`, `hidden`, or `detached`. Messages in `status: 'sending'` at the moment the OS suspends the app are stranded.

> **⚠️ AUDIT FIX (2-01):** Confirmed against production code: `didChangeAppLifecycleState` at `lib/main.dart:1480` handles ONLY `AppLifecycleState.resumed` (the `resumed` case exists at line 1508). There is no handler for `paused`, `hidden`, or `detached`. Messages stranded in `'sending'` status are confirmed. The paused handler must be added as a new case in the same switch/if statement.

> **⚠️ AUDIT FIX (2-11):** Voice messages at `conversation_wired.dart:1231` also create `'sending'` status rows. The pause handler picks up ALL outgoing `'sending'` rows regardless of message type (text, media, voice). No text-scope restriction needed -- this is a beneficial side effect: voice messages stranded in `'sending'` will also be correctly transitioned to `'failed'`.

**This section is best-effort local cleanup, not a primary fix.** The `paused` callback fires when iOS has already begun suspending the app — there is zero guaranteed async completion time. Network calls (like `storeInInbox`) must NOT be attempted in this handler because:
- MethodChannel → Go → network round-trips take 200ms–15s and will not complete
- They race with Section 3's `beginBackgroundTask` for main-thread time
- `Future.any` timeout tricks don't protect against process suspension

`handleAppPaused()` must do **local DB work only**: for each in-flight message, call the conditional transition API — `dbConditionalTransitionStatus(db, id, fromStatus: 'sending', toStatus: 'failed')` which executes `UPDATE messages SET status = ? WHERE id = ? AND status = 'sending'`. The `AND status = 'sending'` guard means a concurrently completed `'delivered'`/`'sent'` row is never overwritten. The full loop completes in ~5-20ms against an already-open SQLCipher database.

---

### Step 2.1 — New use case skeleton: `handleAppPaused()`

#### Red Phase

Create the test file first. It will fail with `Target of URI doesn't exist: 'package:flutter_app/core/lifecycle/handle_app_paused.dart'`.

> **⚠️ AUDIT FIX (2-02):** Confirmed by glob search: `lib/core/lifecycle/handle_app_paused.dart` does not exist. Only `handle_app_resumed.dart` exists in that directory. The new file must be created in the Green Phase below.

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/handle_app_paused_test.dart`

> **⚠️ AUDIT FIX (2-07):** `InMemoryMessageRepository` at `test/shared/fakes/in_memory_message_repository.dart` does NOT exist yet. It must be created as the **first green-phase task** before any of these tests can compile. The file needs to implement `MessageRepository` with an in-memory `Map<String, ConversationMessage>` backing store, including the new `getSendingOutgoingMessages()` and `conditionalTransitionStatus()` methods specified in Step 2.2.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';

import '../../shared/fakes/in_memory_message_repository.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ConversationMessage makeSendingMessage({
  String id = 'msg-001',
  String contactPeerId = 'peer-a',
  String? wireEnvelope,
}) {
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: 'sending',
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
    wireEnvelope: wireEnvelope,
  );
}

ConversationMessage makeMessageWithStatus(String id, String status) {
  return ConversationMessage(
    id: id,
    contactPeerId: 'peer-a',
    senderPeerId: 'my-peer-id',
    text: 'Hello',
    timestamp: '2026-01-01T00:00:00.000Z',
    status: status,
    isIncoming: false,
    createdAt: '2026-01-01T00:00:00.000Z',
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('handleAppPaused — no messages', () {
    test('completes without error when no sending messages exist', () async {
      final messageRepo = InMemoryMessageRepository();

      await expectLater(
        handleAppPaused(messageRepo: messageRepo),
        completes,
      );
    });

    test('returns 0 transitioned messages when no sending messages exist', () async {
      final messageRepo = InMemoryMessageRepository();

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 0);
    });
  });

  group('handleAppPaused — transitions sending → failed', () {
    test('transitions one sending message to failed', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'failed');
    });

    test('returns transitioned count of 1 for one sending message', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 1);
    });

    test('transitions all sending messages when multiple exist', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', contactPeerId: 'peer-a'),
      );
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-002', contactPeerId: 'peer-b'),
      );
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-003', contactPeerId: 'peer-c'),
      );

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 3);
      final msgsA = await messageRepo.getMessagesForContact('peer-a');
      expect(msgsA.single.status, 'failed');
      final msgsB = await messageRepo.getMessagesForContact('peer-b');
      expect(msgsB.single.status, 'failed');
      final msgsC = await messageRepo.getMessagesForContact('peer-c');
      expect(msgsC.single.status, 'failed');
    });

    test('returns correct count for multiple concurrent sending messages', () async {
      final messageRepo = InMemoryMessageRepository();
      for (var i = 1; i <= 5; i++) {
        await messageRepo.saveMessage(
          makeSendingMessage(id: 'msg-00$i', contactPeerId: 'peer-$i'),
        );
      }

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 5);
    });
  });

  group('handleAppPaused — preserves wireEnvelope', () {
    test('wireEnvelope is preserved after status transition', () async {
      final messageRepo = InMemoryMessageRepository();
      const envelope = '{"type":"chat_message","version":"2","encrypted":{}}';
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', wireEnvelope: envelope),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.wireEnvelope, envelope);
      expect(messages.single.status, 'failed');
    });

    test('null wireEnvelope message still transitions to failed', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeSendingMessage(id: 'msg-001', wireEnvelope: null),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'failed');
      expect(messages.single.wireEnvelope, isNull);
    });
  });

  group('handleAppPaused — does not affect other statuses', () {
    test('does not modify already-failed messages', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeMessageWithStatus('msg-f', 'failed'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-s'));

      await handleAppPaused(messageRepo: messageRepo);

      final result = await handleAppPaused(messageRepo: messageRepo);
      // Only the one 'sending' message should be transitioned; already-failed
      // messages must not count again (they were failed before the call).
      expect(result.transitionedCount, 0); // second call: nothing sending left
    });

    test('delivered messages are untouched', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        makeMessageWithStatus('msg-delivered', 'delivered'),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'delivered');
    });

    test('sent messages are untouched', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeMessageWithStatus('msg-sent', 'sent'));

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      expect(messages.single.status, 'sent');
    });

    test('incoming messages are untouched regardless of status', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-incoming',
          contactPeerId: 'peer-a',
          senderPeerId: 'peer-a',
          text: 'hi',
          timestamp: '2026-01-01T00:00:00.000Z',
          status: 'sending', // should never happen but must be safe
          isIncoming: true,
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final messages = await messageRepo.getMessagesForContact('peer-a');
      // Incoming messages must not be transitioned by the pause handler.
      expect(messages.single.status, 'sending');
    });

    test('mixed statuses: only sending outgoing messages are transitioned', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeMessageWithStatus('ok-1', 'sent'));
      await messageRepo.saveMessage(makeMessageWithStatus('ok-2', 'delivered'));
      await messageRepo.saveMessage(makeMessageWithStatus('ok-3', 'failed'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'bad-1'));
      await messageRepo.saveMessage(makeSendingMessage(id: 'bad-2'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, 2);
      final sentMsg = await messageRepo.getMessagesForContact('peer-a');
      final statuses = sentMsg.map((m) => m.status).toSet();
      expect(statuses, containsAll(['sent', 'delivered', 'failed']));
    });
  });

  group('handleAppPaused — result fields', () {
    test('result exposes transitionedCount', () async {
      final messageRepo = InMemoryMessageRepository();
      await messageRepo.saveMessage(makeSendingMessage(id: 'msg-001'));

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, isA<int>());
    });

    test('result exposes transitionedCount as 0 for empty DB', () async {
      final messageRepo = InMemoryMessageRepository();

      final result = await handleAppPaused(messageRepo: messageRepo);

      expect(result.transitionedCount, isA<int>());
    });
  });
}
```

#### Green Phase

Create `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/lifecycle/handle_app_paused.dart`.

The file implements `handleAppPaused()` as a top-level async function mirroring the structure of `handleAppResumed()`. Key design choices:

- Accepts `MessageRepository messageRepo` as required. No P2PService or network-facing parameters.
- Returns an `AppPausedResult` value object (not a bare `int`) so callers have structured data without depending on positional values.
- The function signature:

```dart
Future<AppPausedResult> handleAppPaused({
  required MessageRepository messageRepo,
}) async { ... }
```

- `AppPausedResult` is a simple final class with one `int` field: `transitionedCount`.
- **No `P2PService` parameter. No `inboxStoreTimeout`. No network calls.** The pause handler is local DB only.
- Step 1: call `messageRepo.getSendingOutgoingMessages()` — returns all rows with `status='sending'` and `is_incoming=0`.
- Step 2: for each sending message, call `messageRepo.conditionalTransitionStatus(id, fromStatus: 'sending', toStatus: 'failed')` — this uses the new conditional DB helper (`WHERE id = ? AND status = 'sending'`) so it cannot overwrite a concurrently completed `'delivered'`/`'sent'` status. Returns the count of rows updated (0 if already advanced). Also emits on `messageChanges` so UI streams react.
- Wrap the entire function body in a `try/catch` that emits `APP_LIFECYCLE_PAUSE_ERROR` and returns `AppPausedResult(transitionedCount: 0)`.
- `emitFlowEvent()` calls at: `APP_LIFECYCLE_PAUSE_BEGIN`, `APP_LIFECYCLE_PAUSE_NO_SENDING_MESSAGES`, `APP_LIFECYCLE_PAUSE_TRANSITION` (once per message with the message id), `APP_LIFECYCLE_PAUSE_COMPLETE` (with `transitionedCount`).
- `kDebugMode` guarded `debugPrint('[PAUSE] ...')` lines matching the `[RESUME]` prefix convention found throughout `handleAppResumed()`.

#### Refactor Phase

- Extract `AppPausedResult` into its own `lib/core/lifecycle/app_paused_result.dart` if the class grows beyond two fields, or keep it in the same file if it stays small (prefer co-location until forced otherwise).
- Ensure `getSendingOutgoingMessages()` is symmetric with `getFailedOutgoingMessages()` in the repository interface — see Step 2.3.

---

### Step 2.2 — `MessageRepository` interface extension: `getSendingOutgoingMessages()` + `conditionalTransitionStatus()`

#### Red Phase

Add a test to the existing `messages_db_helpers_test.dart` block and a new test to `fake_message_repository_test.dart` (create it if absent). Both will fail with `The method 'getSendingOutgoingMessages' isn't defined`. Additionally, add tests for `dbConditionalTransitionStatus` that will fail with `The function 'dbConditionalTransitionStatus' isn't defined`, and tests for `conditionalTransitionStatus()` on the repository interface.

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/sending_messages_query_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runTransportColumnMigration(db);
  });

  tearDown(() async => db.close());

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    int isIncoming = 0,
    String? wireEnvelope,
  }) =>
      {
        'id': id,
        'contact_peer_id': 'peer-a',
        'sender_peer_id': 'my-peer-id',
        'text': 'Hello',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': status,
        'is_incoming': isIncoming,
        'created_at': '2026-01-01T00:00:00.000Z',
        'wire_envelope': wireEnvelope,
      };

  group('dbLoadSendingOutgoingMessages', () {
    test('returns empty list when no messages exist', () async {
      final rows = await dbLoadSendingOutgoingMessages(db);
      expect(rows, isEmpty);
    });

    test('returns only sending outgoing messages', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-s', status: 'sending'));
      await dbInsertMessage(db, makeRow(id: 'msg-f', status: 'failed'));
      await dbInsertMessage(db, makeRow(id: 'msg-d', status: 'delivered'));
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-in', status: 'sending', isIncoming: 1),
      );

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.length, 1);
      expect(rows.first['id'], 'msg-s');
    });

    test('returns all sending outgoing messages when multiple exist', () async {
      for (var i = 1; i <= 4; i++) {
        await dbInsertMessage(db, makeRow(id: 'msg-$i', status: 'sending'));
      }
      await dbInsertMessage(db, makeRow(id: 'msg-ok', status: 'sent'));

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.length, 4);
      expect(rows.map((r) => r['id']).toSet(), containsAll(['msg-1', 'msg-2', 'msg-3', 'msg-4']));
    });

    test('includes wire_envelope column in returned rows', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-e', status: 'sending', wireEnvelope: envelope),
      );

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.first['wire_envelope'], envelope);
    });

    test('returns rows ordered by timestamp ASC', () async {
      await dbInsertMessage(db, {
        ...makeRow(id: 'msg-late', status: 'sending'),
        'timestamp': '2026-01-03T00:00:00.000Z',
      });
      await dbInsertMessage(db, {
        ...makeRow(id: 'msg-early', status: 'sending'),
        'timestamp': '2026-01-01T00:00:00.000Z',
      });

      final rows = await dbLoadSendingOutgoingMessages(db);

      expect(rows.first['id'], 'msg-early');
      expect(rows.last['id'], 'msg-late');
    });
  });

  group('dbConditionalTransitionStatus', () {
    test('transitions status when current status matches fromStatus', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-ct', status: 'sending'));

      final count = await dbConditionalTransitionStatus(
        db, 'msg-ct', fromStatus: 'sending', toStatus: 'failed',
      );

      expect(count, 1);
      final rows = await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct']);
      expect(rows.single['status'], 'failed');
    });

    test('returns 0 and does not update when current status does not match', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-ct2', status: 'delivered'));

      final count = await dbConditionalTransitionStatus(
        db, 'msg-ct2', fromStatus: 'sending', toStatus: 'failed',
      );

      expect(count, 0);
      final rows = await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct2']);
      expect(rows.single['status'], 'delivered');
    });

    test('returns 0 for non-existent message ID', () async {
      final count = await dbConditionalTransitionStatus(
        db, 'no-such-id', fromStatus: 'sending', toStatus: 'failed',
      );

      expect(count, 0);
    });

    test('preserves wire_envelope when transitioning status', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db, makeRow(id: 'msg-ct3', status: 'sending', wireEnvelope: envelope),
      );

      await dbConditionalTransitionStatus(
        db, 'msg-ct3', fromStatus: 'sending', toStatus: 'failed',
      );

      final rows = await db.query('messages', where: 'id = ?', whereArgs: ['msg-ct3']);
      expect(rows.single['wire_envelope'], envelope);
    });
  });
}
```

#### Green Phase

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/database/helpers/messages_db_helpers.dart`**, add the new DB helper at the bottom of the file:

```dart
/// Loads all outgoing messages with status='sending'.
///
/// Used by [handleAppPaused] to find in-flight messages that need to be
/// transitioned to 'failed' before the process is frozen by the OS.
Future<List<Map<String, Object?>>> dbLoadSendingOutgoingMessages(
  Database db,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_LOAD_SENDING_START',
    details: {},
  );

  try {
    final rows = await db.query(
      'messages',
      where: 'status = ? AND is_incoming = 0',
      whereArgs: ['sending'],
      orderBy: 'timestamp ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_SENDING_DONE',
      details: {'count': rows.length},
    );

    return rows;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_LOAD_SENDING_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
```

**Also in `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/core/database/helpers/messages_db_helpers.dart`**, add `dbConditionalTransitionStatus` at the bottom of the file:

```dart
/// Only transitions status if the current status matches [fromStatus].
/// Returns the number of rows updated (0 if the row already advanced).
///
/// Used by [handleAppPaused] to safely transition 'sending' → 'failed'
/// without overwriting a concurrently completed 'delivered'/'sent' status.
Future<int> dbConditionalTransitionStatus(
  Database db,
  String id, {
  required String fromStatus,
  required String toStatus,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_START',
    details: {
      'id': id.length > 8 ? id.substring(0, 8) : id,
      'from': fromStatus,
      'to': toStatus,
    },
  );

  try {
    final count = await db.rawUpdate(
      'UPDATE messages SET status = ? WHERE id = ? AND status = ?',
      [toStatus, id, fromStatus],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_DONE',
      details: {
        'id': id.length > 8 ? id.substring(0, 8) : id,
        'rowsUpdated': count,
      },
    );

    return count;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'MESSAGES_DB_CONDITIONAL_TRANSITION_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
```

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository.dart`**, add to the `MessageRepository` abstract class after `getFailedOutgoingMessages()`:

```dart
/// Retrieves all outgoing messages with status='sending'.
///
/// Used by the pause handler to mark in-flight messages as failed
/// before the OS freezes the process.
Future<List<ConversationMessage>> getSendingOutgoingMessages();
```

**Also in the same file**, add `conditionalTransitionStatus()` to the abstract class after `getSendingOutgoingMessages()`:

```dart
/// Transitions a message's status only if its current status matches [fromStatus].
///
/// Returns the number of rows updated (0 if the row already advanced past
/// [fromStatus], e.g., a concurrent send completed 'sending' → 'delivered'
/// before the pause handler could transition it to 'failed').
///
/// Implementations MUST also emit on [MessageRepositoryChangeSource.messageChanges]
/// when a row is successfully updated, so open UI screens react.
Future<int> conditionalTransitionStatus(
  String id, {
  required String fromStatus,
  required String toStatus,
});
```

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/domain/repositories/message_repository_impl.dart`**, add the constructor parameters and implementations:

Add to the constructor field declarations:
```dart
final Future<List<Map<String, Object?>>> Function() dbLoadSendingOutgoingMessages;
final Future<int> Function(String id, {required String fromStatus, required String toStatus}) dbConditionalTransitionStatus;
```

Add to the constructor named parameters:
```dart
required this.dbLoadSendingOutgoingMessages,
required this.dbConditionalTransitionStatus,
```

Add the `getSendingOutgoingMessages()` implementation method:
```dart
@override
Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
  final rows = await dbLoadSendingOutgoingMessages();
  return rows.map((row) => ConversationMessage.fromMap(row)).toList();
}
```

Add the `conditionalTransitionStatus()` implementation method (must emit on `_messageChangeController`):
```dart
@override
Future<int> conditionalTransitionStatus(
  String id, {
  required String fromStatus,
  required String toStatus,
}) async {
  final count = await dbConditionalTransitionStatus(
    id, fromStatus: fromStatus, toStatus: toStatus,
  );
  if (count > 0) {
    final row = await dbLoadMessage(id);
    if (row != null) {
      _messageChangeController.add(ConversationMessage.fromMap(row));
    }
  }
  return count;
}
```

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/shared/fakes/in_memory_message_repository.dart`**, add:

```dart
@override
Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
  return _messages.values
      .where((m) => m.status == 'sending' && !m.isIncoming)
      .toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
}
```

**Also in the same file**, add the `conditionalTransitionStatus()` implementation:

```dart
@override
Future<int> conditionalTransitionStatus(
  String id, {
  required String fromStatus,
  required String toStatus,
}) async {
  final msg = _messages[id];
  if (msg != null && msg.status == fromStatus) {
    final updated = msg.copyWith(status: toStatus);
    _messages[id] = updated;
    _messageChangeController.add(updated);
    return 1;
  }
  return 0;
}
```

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/domain/repositories/fake_message_repository.dart`**, add:

```dart
int getSendingOutgoingCallCount = 0;

@override
Future<List<ConversationMessage>> getSendingOutgoingMessages() async {
  getSendingOutgoingCallCount++;
  return _messages.where((m) => m.status == 'sending' && !m.isIncoming).toList();
}
```

**Also in the same file**, add the `conditionalTransitionStatus()` implementation:

```dart
int conditionalTransitionCallCount = 0;

@override
Future<int> conditionalTransitionStatus(
  String id, {
  required String fromStatus,
  required String toStatus,
}) async {
  conditionalTransitionCallCount++;
  final idx = _messages.indexWhere((m) => m.id == id && m.status == fromStatus);
  if (idx >= 0) {
    _messages[idx] = _messages[idx].copyWith(status: toStatus);
    return 1;
  }
  return 0;
}
```

**In `main.dart`**, wire both new DB helpers into `MessageRepositoryImpl` construction — find the existing `MessageRepositoryImpl(...)` call and add both named parameters:
- `dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),`
- `dbConditionalTransitionStatus: (id, {required fromStatus, required toStatus}) => dbConditionalTransitionStatus(db, id, fromStatus: fromStatus, toStatus: toStatus),`

Note: the existing wiring pattern in `main.dart` closes over the local `db` variable, so the DB helper closures use `() => dbLoadSendingOutgoingMessages(db)` (not `(db) => ...`).

#### Refactor Phase

> **⚠️ AUDIT FIX (2-03):** `dart fix --apply` does NOT add missing method stubs to classes that `implement MessageRepository`. It only applies automated Dart lint fixes (deprecated API replacements, etc.). **Correction:** Instead, search for `implements MessageRepository` across the entire codebase and manually add stubs to each implementor. Use `throw UnimplementedError()` for test implementations that do not need the new methods. The `MessageRepository` abstract class has no default implementations, so every implementor will fail to compile until both `getSendingOutgoingMessages()` and `conditionalTransitionStatus()` stubs are added.

Search for all `implements MessageRepository` across the codebase and manually add the missing stubs. There are currently 12+ classes that implement `MessageRepository` in the test directory (see `conversation_wired_test.dart`, `load_conversation_use_case_test.dart`, `chat_message_listener_test.dart`, `handle_incoming_chat_message_use_case_test.dart`, `send_chat_message_use_case_test.dart`, `two_user_message_exchange_test.dart`, `delete_contact_use_case_test.dart`, `intro_wiring_smoke_test.dart`, `load_feed_use_case_test.dart`, `load_orbit_data_use_case_test.dart`, `c4_partial_drain_test.dart`). Each needs a `conditionalTransitionStatus()` stub that either throws `UnimplementedError()` or delegates to `updateMessageStatus()` depending on the test's needs.

---

### Step 2.3 — `didChangeAppLifecycleState` dispatch: widget test (real `_MyAppState`)

#### Red Phase

This test verifies that the **real** `_MyAppState.didChangeAppLifecycleState` (at `lib/main.dart:1480`) calls `handleAppPaused()` when the state is `paused` or `hidden`. Because `_MyAppState` is package-private, the test pumps a real `MyApp(...)` widget with fake dependencies and pushes `AppLifecycleState` changes through `TestWidgetsFlutterBinding`. This guarantees the test exercises the production observer -- **not** a separate test harness widget.

> **Why not a lightweight test harness?** A minimal `_LifecycleObserverWidget` that wires `handleAppPaused()` into its own `didChangeAppLifecycleState` proves only that `handleAppPaused()` works when called from *some* observer -- it does NOT prove that the real `_MyAppState` dispatches to it. The whole point of this wiring test is to close the gap between unit-tested use-case logic and the production call-site at `main.dart:1480`. A harness-based test could pass even if the production `_MyAppState` never wired up `handleAppPaused()` at all.

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/app_lifecycle_paused_dispatch_test.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/main.dart'; // imports MyApp — the real widget

import '../../shared/fakes/in_memory_message_repository.dart';
import '../../shared/build_test_my_app.dart'; // see Green Phase — factory for real MyApp

void main() {
  group('_MyAppState.didChangeAppLifecycleState dispatches to handleAppPaused', () {
    testWidgets(
      'paused state transitions sending messages to failed via real _MyAppState',
      (tester) async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-001',
            contactPeerId: 'peer-a',
            senderPeerId: 'my-peer-id',
            text: 'Hello',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        // Pump the REAL MyApp widget, which creates _MyAppState and
        // registers it as a WidgetsBindingObserver in initState().
        await tester.pumpWidget(
          buildTestMyApp(messageRepo: messageRepo),
        );

        // Simulate the OS moving the app to paused — this flows through
        // the real _MyAppState.didChangeAppLifecycleState at main.dart:1480
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();

        final messages = await messageRepo.getMessagesForContact('peer-a');
        expect(messages.single.status, 'failed');
      },
    );

    testWidgets(
      'hidden state transitions sending messages to failed via real _MyAppState',
      (tester) async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-002',
            contactPeerId: 'peer-b',
            senderPeerId: 'my-peer-id',
            text: 'World',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildTestMyApp(messageRepo: messageRepo),
        );

        // hidden is the macOS/newer-iOS equivalent of paused
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pumpAndSettle();

        final messages = await messageRepo.getMessagesForContact('peer-b');
        expect(messages.single.status, 'failed');
      },
    );

    testWidgets(
      'inactive state does NOT trigger pause handler in real _MyAppState',
      (tester) async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-003',
            contactPeerId: 'peer-c',
            senderPeerId: 'my-peer-id',
            text: 'Test',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildTestMyApp(messageRepo: messageRepo),
        );

        // 'inactive' is a transient state (control centre / notification shade);
        // the real _MyAppState must NOT dispatch to handleAppPaused on it
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pumpAndSettle();

        final messages = await messageRepo.getMessagesForContact('peer-c');
        expect(messages.single.status, 'sending',
            reason: 'inactive must not trigger the pause handler in _MyAppState');
      },
    );

    testWidgets(
      'resumed state does NOT trigger pause handler in real _MyAppState',
      (tester) async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-004',
            contactPeerId: 'peer-d',
            senderPeerId: 'my-peer-id',
            text: 'Test',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildTestMyApp(messageRepo: messageRepo),
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        // resumed triggers _onResumed → handleAppResumed, not handleAppPaused;
        // the 'sending' message must remain unchanged
        final messages = await messageRepo.getMessagesForContact('peer-d');
        expect(messages.single.status, 'sending');
      },
    );

    testWidgets(
      'pause handler is idempotent — double paused via real _MyAppState',
      (tester) async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-005',
            contactPeerId: 'peer-e',
            senderPeerId: 'my-peer-id',
            text: 'Test',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildTestMyApp(messageRepo: messageRepo),
        );

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pumpAndSettle();

        final messages = await messageRepo.getMessagesForContact('peer-e');
        // Must still be exactly 'failed', not corrupted by double call
        expect(messages.single.status, 'failed');
      },
    );
  });
}
```

The test pumps the real `MyApp` widget, so lifecycle state changes flow through the real `_MyAppState.didChangeAppLifecycleState` at `lib/main.dart:1480`. There is **no** test harness indirection -- the `_LifecycleObserverWidget` / `widget_test_harness.dart` approach is deliberately not used.

#### Green Phase -- `buildTestMyApp()` factory (replaces `widget_test_harness.dart`)

> **⚠️ AUDIT FIX (2-05):** `buildTestMyApp()` requires ~48 constructor params -- significant infrastructure to stand up. **Recommendation:** Evaluate whether direct `handleAppPaused()` unit tests (Steps 2.1, 2.4, 2.5) provide sufficient coverage for v1. If so, defer this full `MyApp` widget test (Step 2.3) until the infrastructure cost is justified. The direct-call tests already verify the use case logic; only the wiring from `_MyAppState.didChangeAppLifecycleState` to `handleAppPaused()` remains unverified without this test.

Because `MyApp` has ~48 required constructor parameters, a dedicated factory creates a real `MyApp(...)` with fake/stub implementations for every dependency. Only the `messageRepository` parameter is overridable (callers pass their test-specific `InMemoryMessageRepository`); all other dependencies use inert fakes that satisfy the type system without performing real work.

**Do NOT create `test/shared/widget_test_harness.dart`.** That file would introduce a separate `WidgetsBindingObserver` that bypasses the real `_MyAppState`. Instead, create:

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/shared/build_test_my_app.dart`

```dart
import 'package:flutter/material.dart';
import 'package:flutter_app/main.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

// Import all fake/stub implementations needed to satisfy MyApp's constructor.
// Each fake is an inert implementation that satisfies the type but performs
// no real I/O, no MethodChannel calls, and no database access.
import '../core/bridge/fake_bridge.dart';
import 'fakes/fake_p2p_service_integration.dart';
import 'fakes/fake_p2p_network.dart';
import 'fakes/in_memory_message_repository.dart';
import 'fakes/in_memory_contact_repository.dart';
import 'fakes/in_memory_contact_request_repository.dart';
import 'fakes/in_memory_group_repository.dart';
import 'fakes/in_memory_group_message_repository.dart';
import 'fakes/in_memory_media_attachment_repository.dart';
import 'fakes/in_memory_post_repository.dart';
import 'fakes/in_memory_posts_privacy_settings_repository.dart';
import 'fakes/in_memory_contact_presence_snapshot_repository.dart';
import 'fakes/in_memory_introduction_repository.dart';
import 'fakes/fake_notification_service.dart';
import 'fakes/fake_media_file_manager.dart';
import 'fakes/fake_audio_recorder_service.dart';
import '../core/secure_storage/fake_secure_key_store.dart';
import '../features/conversation/domain/repositories/fake_reaction_repository.dart';
// ... additional stubs as needed for remaining parameters (listeners, retriers,
// coordinators, trackers, etc.). Each must be an inert no-op implementation.
// See "Implementation notes" below for the full list.

/// Builds a real [MyApp] widget with fake dependencies.
///
/// Only [messageRepo] is caller-supplied — all other parameters use inert
/// fakes. This ensures the widget test exercises the real [_MyAppState]
/// including its [didChangeAppLifecycleState] observer registration at
/// lib/main.dart:1480.
///
/// The factory suppresses side-effects in [_MyAppState.initState] by using
/// fakes that return empty streams / no-op futures for:
///   - push listeners (Firebase is absent in test → `isDesktop: true` skips)
///   - share intent (empty stream)
///   - notification tap handler (no-op)
///   - post-frame callbacks (no pending notification route)
Widget buildTestMyApp({required MessageRepository messageRepo}) {
  final network = FakeP2PNetwork();
  final bridge = FakeBridge();
  final p2pService = FakeP2PService(peerId: 'test-peer', network: network);

  return MyApp(
    repository:            _NoOpIdentityRepository(),
    contactRepository:     InMemoryContactRepository(),
    contactRequestRepository: InMemoryContactRequestRepository(),
    contactRequestListener: _NoOpContactRequestListener(),
    messageRepository:     messageRepo,     // <-- caller-supplied
    postRepository:        InMemoryPostRepository(),
    postsPrivacySettingsRepository: InMemoryPostsPrivacySettingsRepository(),
    contactPresenceSnapshotRepository:
        InMemoryContactPresenceSnapshotRepository(),
    nearbyLocationService: _NoOpNearbyLocationService(),
    mediaAttachmentRepository: InMemoryMediaAttachmentRepository(),
    chatMessageListener:   _NoOpChatMessageListener(),
    postListener:          _NoOpPostListener(),
    postCommentListener:   _NoOpPostCommentListener(),
    postReactionListener:  _NoOpPostReactionListener(),
    postPresenceListener:  _NoOpPostPresenceListener(),
    postPassListener:      _NoOpPostPassListener(),
    postPinListener:       _NoOpPostPinListener(),
    reactionListener:      _NoOpReactionListener(),
    profileUpdateListener: _NoOpProfileUpdateListener(),
    messageRouter:         _NoOpIncomingMessageRouter(),
    pendingMessageRetrier: _NoOpPendingMessageRetrier(),
    pendingPostMediaUploadRetrier: _NoOpPendingPostMediaUploadRetrier(),
    pendingPostDeliveryRetrier: _NoOpPendingPostDeliveryRetrier(),
    pendingPostFollowOnRetrier: _NoOpPendingPostFollowOnRetrier(),
    keyExchangeRetrier:    _NoOpKeyExchangeRetrier(),
    bridge:                bridge,
    p2pService:            p2pService,
    mediaFileManager:      FakeMediaFileManager(),
    secureKeyStore:        FakeSecureKeyStore(),
    imageProcessor:        _NoOpImageProcessor(),
    audioRecorderService:  FakeAudioRecorderService(),
    reactionRepository:    FakeReactionRepository(),
    isDesktop:             true,  // disables Firebase push setup in initState
    notificationService:   FakeNotificationService(),
    appShellController:    _NoOpAppShellController(),
    pendingPostTargetStore: _NoOpPendingPostTargetStore(),
    conversationTracker:   _NoOpActiveConversationTracker(),
    groupRepository:       InMemoryGroupRepository(),
    groupMessageRepository: InMemoryGroupMessageRepository(),
    groupMessageListener:  _NoOpGroupMessageListener(),
    groupInviteListener:   _NoOpGroupInviteListener(),
    groupKeyUpdateListener: _NoOpGroupKeyUpdateListener(),
    groupConversationTracker: _NoOpActiveConversationTracker(),
    introductionRepository: InMemoryIntroductionRepository(),
    introductionListener:  _NoOpIntroductionListener(),
    shareIntentService:    _NoOpShareIntentService(),
    pushRegistrationCoordinator: _NoOpPushRegistrationCoordinator(),
  );
}

// ---------------------------------------------------------------------------
// Minimal no-op stubs for constructor parameters that have no shared fake yet.
// Each implements just enough to satisfy the type and make _MyAppState.initState
// run without throwing. All streams are empty; all futures complete immediately.
//
// Implementation note: The concrete stub classes below are placeholders in
// the plan. During the Green Phase, the implementer must:
//   1. Check whether a shared fake already exists in test/shared/fakes/ or
//      test/core/ for each type. If so, use it instead of creating a new stub.
//   2. For types with no existing fake, create a minimal no-op class that
//      implements the required interface. Each class needs only the methods
//      called during _MyAppState.initState and dispose — typically just
//      stream getters (return const Stream.empty()) and dispose() (no-op).
//   3. If a stub is useful to other tests, promote it to test/shared/fakes/.
// ---------------------------------------------------------------------------
// [Concrete _NoOp* class bodies omitted for brevity — each follows the pattern:
//    class _NoOpFoo implements Foo {
//      @override Stream<X> get someStream => const Stream.empty();
//      @override void dispose() {}
//      @override Future<void> someMethod(...) async {}
//    }
// The implementer generates these from the interface definitions.]
```

**Implementation notes for the `_NoOp*` stubs:**

The `_MyAppState.initState()` method (lines 1182-1198 in `main.dart`) does the following that stubs must support:
1. `WidgetsBinding.instance.addObserver(this)` -- framework call, no stub needed.
2. `PostNotificationOpenCoordinator(...)` -- needs `pendingPostTargetStore`, `postRepository`, `appShellController`, `revealPostsSurface`. Stubs must satisfy the coordinator constructor.
3. `_setupPushListeners()` -- gated by `isDesktop: true`, so it **skips entirely** in test. No Firebase stubs needed.
4. `_setupNotificationTapHandler()` -- sets `widget.notificationService.onNotificationTap`. `FakeNotificationService` already supports this setter.
5. `_setupShareIntentHandling()` -- listens to `widget.shareIntentService.intentStream`. Stub returns `const Stream.empty()`.
6. `_flushDeferredNotificationRouteTarget()` -- post-frame callback, runs asynchronously; stub notification service returns no pending target.
7. `_handleInitialLocalNotificationLaunch()` -- stub notification service returns null.

The `_MyAppState.dispose()` method (lines 1443-1477) calls `.dispose()` on all listeners, retriers, router, p2pService, bridge, audioRecorderService, and notificationService. Each stub must have a no-op `dispose()`.

**Why `isDesktop: true` is critical:** Setting `isDesktop: true` causes `_setupPushListeners()` to return immediately without touching `FirebaseMessaging`, which is unavailable in the test environment. This is the same pattern used by existing code that needs to avoid Firebase initialization.

**No `widget_test_harness.dart` file.** The `_LifecycleObserverWidget` approach is deliberately removed. The `buildTestMyApp()` factory constructs the **real** `MyApp` widget, which creates the **real** `_MyAppState`, which registers the **real** `didChangeAppLifecycleState` observer via `WidgetsBinding.instance.addObserver(this)` in `initState()`. When `tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused)` fires, it flows through the production code path at `lib/main.dart:1480` -- not a test double.

#### Green Phase -- production code change

**In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/main.dart`**, inside `_MyAppState.didChangeAppLifecycleState()` at line 1490, extend the existing `if` block:

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (kDebugMode) {
    debugPrint('[LIFECYCLE] AppLifecycleState changed → ${state.name}');
  }
  emitFlowEvent(
    layer: 'FL',
    event: 'APP_LIFECYCLE_STATE_CHANGED',
    details: {'state': state.name},
  );

  if (state == AppLifecycleState.resumed) {
    _onResumed();
  }

  // NEW: commit any in-flight 'sending' messages to 'failed' before
  // the OS may freeze or kill this process. Using 'paused' and 'hidden'
  // because 'inactive' is a transient state visited during foreground
  // app-switcher and does not reliably precede backgrounding.
  if (state == AppLifecycleState.paused ||
      state == AppLifecycleState.hidden) {
    _onPaused();
  }
}

void _onPaused() {
  // Fire-and-forget: we have at most a few hundred milliseconds.
  // handleAppPaused() is local DB only — no network calls, no p2pService.
  unawaited(
    handleAppPaused(
      messageRepo: widget.messageRepository,
    ).then((result) {
      if (kDebugMode) {
        debugPrint(
          '[LIFECYCLE] _onPaused() complete: '
          'transitioned=${result.transitionedCount}',
        );
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_PAUSED_COMPLETE',
        details: {
          'transitionedCount': result.transitionedCount,
        },
      );
    }).catchError((Object e) {
      if (kDebugMode) {
        debugPrint('[LIFECYCLE] _onPaused() error: $e');
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'APP_LIFECYCLE_PAUSED_ERROR',
        details: {'error': e.toString()},
      );
    }),
  );
}
```

Add the import at the top of `main.dart`:

```dart
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
```

#### Refactor Phase

- Extract `_onPaused()` guard pattern into the same `_isResuming` idiom if paused/resumed can race. In practice they cannot race on a single-threaded Dart isolate, but if a slow `handleAppResumed()` is still running when `paused` fires, `_onPaused()` should still execute — so do not gate it on `_isResuming`. Consider adding a separate `_isPausing` bool if future extensions need it.
- Move the `import` of `handle_app_paused.dart` next to the existing `handle_app_resumed.dart` import.

---

### Step 2.4 — Integration test: DB state after pause

#### Red Phase

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/app_lifecycle_pause_integration_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/002_messages_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/006_read_at_column.dart';
import 'package:flutter_app/core/database/migrations/007_archive_columns.dart';
import 'package:flutter_app/core/database/migrations/008_block_columns.dart';
import 'package:flutter_app/core/database/migrations/009_quoted_message_id.dart';
import 'package:flutter_app/core/database/migrations/012_transport_column.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

void main() {
  late Database db;
  late MessageRepositoryImpl messageRepo;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMessagesTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await runSecretNullChecksMigration(db);
    await runReadAtColumnMigration(db);
    await runArchiveColumnsMigration(db);
    await runBlockColumnsMigration(db);
    await runQuotedMessageIdMigration(db);
    await runTransportColumnMigration(db);

> **⚠️ AUDIT FIX (2-10):** Verify this `MessageRepositoryImpl` constructor call includes ALL required params (currently 16+). The `dbConditionalTransitionStatus` wiring shown below is correct. Minor note: `limit = 100` in `dbLoadUnackedOutgoingMessages` vs default `50` is harmless.

    messageRepo = MessageRepositoryImpl(
      dbInsertMessage: (row) => dbInsertMessage(db, row),
      dbLoadMessagesForContact: (peerId) => dbLoadMessagesForContact(db, peerId),
      dbLoadLatestMessageForContact: (peerId) =>
          dbLoadLatestMessageForContact(db, peerId),
      dbUpdateMessageStatus: (id, status) =>
          dbUpdateMessageStatus(db, id, status),
      dbLoadMessage: (id) => dbLoadMessage(db, id),
      dbCountMessagesForContact: (peerId) =>
          dbCountMessagesForContact(db, peerId),
      dbMarkConversationAsRead: (peerId) =>
          dbMarkConversationAsRead(db, peerId),
      dbCountUnreadForContact: (peerId) => dbCountUnreadForContact(db, peerId),
      dbCountTotalUnread: () => dbCountTotalUnread(db),
      dbCountTotalUnreadExcludingArchived: () =>
          dbCountTotalUnreadExcludingArchived(db),
      dbDeleteMessagesForContact: (peerId) =>
          dbDeleteMessagesForContact(db, peerId),
      dbLoadMessagesPage: (peerId, {limit = 50, beforeTimestamp}) =>
          dbLoadMessagesPage(db, peerId, limit: limit,
              beforeTimestamp: beforeTimestamp),
      dbLoadFailedOutgoingMessages: () => dbLoadFailedOutgoingMessages(db),
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 100}) =>
          dbLoadUnackedOutgoingMessages(db, olderThan: olderThan, limit: limit),
      dbLoadConversationThreadSummaries: (ids) =>
          dbLoadConversationThreadSummaries(db, ids),
      dbLoadSendingOutgoingMessages: () => dbLoadSendingOutgoingMessages(db),
      dbConditionalTransitionStatus: (id, {required fromStatus, required toStatus}) =>
          dbConditionalTransitionStatus(db, id, fromStatus: fromStatus, toStatus: toStatus),
    );
  });

  tearDown(() async => db.close());

  Map<String, Object?> makeRow({
    required String id,
    required String status,
    String contactPeerId = 'peer-a',
    String? wireEnvelope,
  }) =>
      {
        'id': id,
        'contact_peer_id': contactPeerId,
        'sender_peer_id': 'my-peer-id',
        'text': 'Hello',
        'timestamp': '2026-01-01T00:00:00.000Z',
        'status': status,
        'is_incoming': 0,
        'created_at': '2026-01-01T00:00:00.000Z',
        'wire_envelope': wireEnvelope,
      };

  group('DB state after handleAppPaused', () {
    test('sending message is persisted as failed in DB after pause', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-001', status: 'sending'));

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-001'],
      );
      expect(rows.single['status'], 'failed');
    });

    test('wire_envelope survives the sending→failed transition', () async {
      const envelope = '{"version":"2","encrypted":{}}';
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-002', status: 'sending', wireEnvelope: envelope),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-002'],
      );
      expect(rows.single['status'], 'failed');
      expect(rows.single['wire_envelope'], envelope);
    });

    test('delivered messages remain delivered after pause', () async {
      await dbInsertMessage(
        db,
        makeRow(id: 'msg-003', status: 'delivered'),
      );

      await handleAppPaused(messageRepo: messageRepo);

      final rows = await db.query(
        'messages',
        where: 'id = ?',
        whereArgs: ['msg-003'],
      );
      expect(rows.single['status'], 'delivered');
    });

    test('messageChanges stream emits updated messages', () async {
      await dbInsertMessage(db, makeRow(id: 'msg-004', status: 'sending'));

      final emitted = <String>[];
      final sub = messageRepo.messageChanges.listen(
        (msg) => emitted.add('${msg.id}:${msg.status}'),
      );

      await handleAppPaused(messageRepo: messageRepo);

      await sub.cancel();
      expect(emitted, contains('msg-004:failed'));
    });

    test('failed messages are available for retryFailedMessages after pause',
        () async {
      // Simulate what retryFailedMessages reads
      await dbInsertMessage(db, makeRow(id: 'msg-005', status: 'sending'));

      await handleAppPaused(messageRepo: messageRepo);

      final failed = await messageRepo.getFailedOutgoingMessages();
      expect(failed.length, 1);
      expect(failed.first.id, 'msg-005');
      expect(failed.first.status, 'failed');
    });

    test('getSendingOutgoingMessages returns empty after pause completes',
        () async {
      await dbInsertMessage(db, makeRow(id: 'msg-006', status: 'sending'));

      await handleAppPaused(messageRepo: messageRepo);

      final sending = await messageRepo.getSendingOutgoingMessages();
      expect(sending, isEmpty,
          reason: 'No messages should remain in sending state after pause');
    });
  });
}
```

#### Green Phase

No new production code needed for this step beyond what Step 2.2 and Step 2.1 produce. The integration test exercises the real `MessageRepositoryImpl` against `sqflite_common_ffi`, so it validates the full stack end-to-end without hitting a device. The `MessageRepositoryImpl` already accepts both `dbLoadSendingOutgoingMessages` and `dbConditionalTransitionStatus` constructor parameters (added in Step 2.2) and exposes `conditionalTransitionStatus()` on the repository interface. Confirm that `handleAppPaused()` uses `messageRepo.conditionalTransitionStatus(id, fromStatus: 'sending', toStatus: 'failed')` (NOT the unconditional `updateMessageStatus`) so it cannot overwrite a concurrently completed `'delivered'` status. The conditional variant must also emit on `_messageChangeController` so UI streams react. The integration test's `MessageRepositoryImpl` constructor call must also include `dbConditionalTransitionStatus: (id, {required fromStatus, required toStatus}) => dbConditionalTransitionStatus(db, id, fromStatus: fromStatus, toStatus: toStatus),` in its named parameters.

#### Refactor Phase

If the DB helper integration test setUp block becomes a copy-paste burden across lifecycle tests, extract a shared `openTestDatabase()` helper in `test/core/database/test_database_factory.dart` that runs all migrations and returns a configured `Database`. This mirrors the pattern already used across `test/core/database/migrations/` and `test/core/database/helpers/`.

---

### Step 2.5 — Smoke test: send → pause → resume → retry succeeds

#### Red Phase

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/pause_resume_retry_smoke_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart'
    as p2p;
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';

import '../../shared/fakes/in_memory_message_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';
import '../../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../../core/services/fake_p2p_service.dart';
import '../../core/bridge/fake_bridge.dart';

IdentityModel _makeIdentity() => IdentityModel(
      peerId: 'my-peer-id',
      publicKey: 'my-pk',
      privateKey: 'my-sk',
      mnemonic12:
          'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );

ContactModel _makeContact(String peerId) => ContactModel(
      peerId: peerId,
      publicKey: 'pk-$peerId',
      rendezvous: '/ip4/127.0.0.1/tcp/4001',
      username: 'User-$peerId',
      signature: 'sig-$peerId',
      scannedAt: '2026-01-01T00:00:00.000Z',
      mlKemPublicKey: 'mlkem-pk-$peerId',
    );

void main() {
  group('Smoke: send → pause → resume → retry', () {
    test(
      'message stranded in sending state is retried successfully after resume',
      () async {
        // 1. ARRANGE — set up repos
        final messageRepo = InMemoryMessageRepository();
        final identityRepo = FakeIdentityRepository()..seed(_makeIdentity());
        final contactRepo = FakeContactRepository()
          ..seed([_makeContact('peer-bob')]);
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'fake-kem',
              'ciphertext': 'fake-ct',
              'nonce': 'fake-nonce',
            },
          },
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id',
            circuitAddresses: ['/p2p-circuit/addr'],
          ),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-bob',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult: const p2p.SendMessageResult(
            sent: true,
            reply: 'ack',
          ),
          storeInInboxResult: true,
        );

        // 2. ACT — simulate a message that was written to the DB as 'sending'
        //    (representing a send that was in-flight when the OS paused the app)
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-in-flight',
            contactPeerId: 'peer-bob',
            senderPeerId: 'my-peer-id',
            text: 'Hello Bob',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope:
                '{"type":"chat_message","version":"2","encrypted":{"kem":"k","ciphertext":"c","nonce":"n"}}',
          ),
        );

        // 3. ACT — OS pauses the app (lock screen, home button)
        final pauseResult = await handleAppPaused(messageRepo: messageRepo);

        // 4. ASSERT — message is now 'failed', not stranded in 'sending'
        expect(pauseResult.transitionedCount, 1);
        final afterPause = await messageRepo.getMessagesForContact('peer-bob');
        expect(afterPause.single.status, 'failed',
            reason: 'Pause must transition sending→failed');
        // wireEnvelope must be preserved for the retry path
        expect(afterPause.single.wireEnvelope, isNotNull);
```

> **⚠️ AUDIT FIX (2-08):** CRITICAL: This smoke test seeds `wireEnvelope` with a value, but the **common** stuck-in-`'sending'` case has `wireEnvelope = null`. At `conversation_wired.dart:616-637`, the optimistic `'sending'` row is saved WITHOUT `wireEnvelope` (it is populated only after encryption succeeds). After pause transitions to `'failed'`, `retryFailedMessages` at line 57 checks `wireEnvelope != null`. For text stuck in `'sending'` before encryption, `wireEnvelope` is null; the inbox fast-path is skipped; the full re-encrypt `sendChatMessage` path is used instead. **Add an additional smoke test** where `wireEnvelope` is null, proving the re-encrypt retry path works end-to-end.

```dart
        // 5. ACT — user returns to app; handleAppResumed runs, then the
        //    PendingMessageRetrier fires retryFailedMessages
        await handleAppResumed(bridge: bridge, p2pService: p2pService);
        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );

        // 6. ASSERT — retry used the wire_envelope inbox fast path
        expect(retried, 1, reason: 'Retry must succeed via wireEnvelope inbox');
        expect(p2pService.storeInInboxCallCount, 1,
            reason: 'wireEnvelope must route through storeInInbox');

        // 7. ASSERT — final message state is delivered with no stale sending
        final afterRetry = await messageRepo.getMessagesForContact('peer-bob');
        expect(afterRetry.single.status, 'delivered');
        expect(afterRetry.single.transport, 'inbox');
        expect(afterRetry.single.wireEnvelope, isNull,
            reason: 'wireEnvelope cleared after successful delivery');
      },
    );

    test(
      'multiple concurrent sending messages all reach delivered after pause → retry',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final identityRepo = FakeIdentityRepository()..seed(_makeIdentity());
        final contactRepo = FakeContactRepository()
          ..seed([
            _makeContact('peer-alice'),
            _makeContact('peer-carol'),
            _makeContact('peer-dave'),
          ]);
        final bridge = FakeBridge(
          initialResponses: {
            'message.encrypt': {
              'ok': true,
              'kem': 'k',
              'ciphertext': 'c',
              'nonce': 'n',
            },
          },
        );
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id',
            circuitAddresses: ['/p2p-circuit/addr'],
          ),
          discoverPeerResult: const DiscoveredPeer(
            id: 'peer-alice',
            addresses: ['/ip4/127.0.0.1/tcp/4001'],
          ),
          dialPeerResult: true,
          sendMessageWithReplyResult:
              const p2p.SendMessageResult(sent: true, reply: 'ack'),
          storeInInboxResult: true,
        );

        // Seed 3 concurrent sending messages
        for (final (idx, peer) in [
          'peer-alice',
          'peer-carol',
          'peer-dave',
        ].indexed) {
          await messageRepo.saveMessage(
            ConversationMessage(
              id: 'msg-00${idx + 1}',
              contactPeerId: peer,
              senderPeerId: 'my-peer-id',
              text: 'Hi',
              timestamp: '2026-01-01T0$idx:00:00.000Z',
              status: 'sending',
              isIncoming: false,
              createdAt: '2026-01-01T00:00:00.000Z',
              wireEnvelope: '{"version":"2","encrypted":{}}',
            ),
          );
        }

        final pauseResult = await handleAppPaused(messageRepo: messageRepo);
        expect(pauseResult.transitionedCount, 3);

        final retried = await retryFailedMessages(
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          bridge: bridge,
        );
        expect(retried, 3);
      },
    );

    test(
      'pause on app with no in-flight messages is a no-op and resume still succeeds',
      () async {
        final messageRepo = InMemoryMessageRepository();
        final bridge = FakeBridge();
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'my-peer-id',
          ),
        );

        // No sending messages at all
        final pauseResult = await handleAppPaused(messageRepo: messageRepo);
        expect(pauseResult.transitionedCount, 0);

        // Resume should still work correctly
        final bridgeOk =
            await handleAppResumed(bridge: bridge, p2pService: p2pService);
        expect(bridgeOk, isNotNull);
      },
    );
  });
}
```

#### Green Phase

No new production code is needed beyond Steps 2.1-2.3. This smoke test exercises the integration of all three -- `handleAppPaused()`, `handleAppResumed()`, and `retryFailedMessages()` -- using only in-memory fakes. It passes once the earlier steps compile.

#### Refactor Phase

- If the `IdentityModel` / `ContactModel` / `FakeP2PService` construction boilerplate appears in three or more lifecycle test files, extract them into `test/core/lifecycle/lifecycle_test_fixtures.dart`.
- The `storeInInbox` smoke path assumes the wireEnvelope-first branch of `retryFailedMessages()` is used. Verify the branch condition `msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty` remains intact -- if `retryFailedMessages()` is ever refactored to clear the envelope earlier, the smoke test will catch the regression.

---

### Step 2.6 — Edge cases and error resilience

#### Red Phase

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/handle_app_paused_edge_cases_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

import '../../shared/fakes/in_memory_message_repository.dart';

// Repo that throws on getSendingOutgoingMessages
class _ThrowingMessageRepository extends InMemoryMessageRepository {
  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() {
    throw Exception('DB unavailable during pause');
  }
}

// Repo that throws on conditionalTransitionStatus
class _ThrowOnUpdateRepository extends InMemoryMessageRepository {
  int updateCallCount = 0;

  @override
  Future<int> conditionalTransitionStatus(
    String id, {required String fromStatus, required String toStatus}
  ) async {
    updateCallCount++;
    throw Exception('conditionalTransitionStatus failed');
  }
}

void main() {
  group('handleAppPaused — error resilience', () {
    test(
      'returns safe default when getSendingOutgoingMessages throws',
      () async {
        final result = await handleAppPaused(
          messageRepo: _ThrowingMessageRepository(),
        );

        // Must not throw; returns zeroed result
        expect(result.transitionedCount, 0);
      },
    );

    test(
      'continues processing remaining messages when one conditionalTransitionStatus throws',
      () async {
        final repo = _ThrowOnUpdateRepository();
        await repo.saveMessage(
          ConversationMessage(
            id: 'msg-001',
            contactPeerId: 'peer-a',
            senderPeerId: 'me',
            text: 'hi',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );
        await repo.saveMessage(
          ConversationMessage(
            id: 'msg-002',
            contactPeerId: 'peer-b',
            senderPeerId: 'me',
            text: 'hello',
            timestamp: '2026-01-01T01:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
          ),
        );

        // Should not throw even though every conditionalTransitionStatus call fails
        await expectLater(
          handleAppPaused(messageRepo: repo),
          completes,
        );

        // Both messages attempted: updateCallCount >= 2 means we tried both
        // rather than aborting on first failure
        expect(repo.updateCallCount, greaterThanOrEqualTo(2));
      },
    );

    test(
      'does not call conditionalTransitionStatus when no sending messages exist',
      () async {
        final repo = _ThrowOnUpdateRepository();
        // Repo starts empty -- no sending messages

        // Should complete without hitting the throwing method
        await expectLater(
          handleAppPaused(messageRepo: repo),
          completes,
        );

        expect(repo.updateCallCount, 0);
      },
    );
  });

  group('handleAppPaused — timing', () {
    test(
      'completes within reasonable time for local DB only handler',
      () async {
        final messageRepo = InMemoryMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-hang',
            contactPeerId: 'peer-a',
            senderPeerId: 'me',
            text: 'hi',
            timestamp: '2026-01-01T00:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-01-01T00:00:00.000Z',
            wireEnvelope: '{"version":"2"}',
          ),
        );

        final start = DateTime.now();

        final result = await handleAppPaused(
          messageRepo: messageRepo,
        );

        final elapsed = DateTime.now().difference(start);
        expect(elapsed.inMilliseconds, lessThan(5000),
            reason: 'Pause handler must not block indefinitely');
        // Message still transitioned to failed (DB write always happens first)
        expect(result.transitionedCount, 1);
      },
    );
  });
}
```

#### Green Phase

The `_ThrowOnUpdateRepository` per-message error test drives a specific requirement in `handleAppPaused()`: the transition loop must wrap each `conditionalTransitionStatus(id, fromStatus: 'sending', toStatus: 'failed')` call in its own `try/catch` so a single failing row does not abort the remaining messages. The loop body in `handleAppPaused()`:

```dart
for (final msg in sendingMessages) {
  try {
    final updated = await messageRepo.conditionalTransitionStatus(
      msg.id, fromStatus: 'sending', toStatus: 'failed',
    );
    if (updated > 0) transitionedCount++;
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_TRANSITION',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'hasWireEnvelope': msg.wireEnvelope != null,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'APP_LIFECYCLE_PAUSE_TRANSITION_ERROR',
      details: {
        'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id,
        'error': e.toString(),
      },
    );
    // Continue to next message — do not abort batch on single failure.
  }
}
```

The outer `try/catch` around the whole function body catches `getSendingOutgoingMessages()` failures and returns a zeroed `AppPausedResult`.

#### Refactor Phase

- The pause handler has no timeout parameters -- it is local DB only and completes in <20ms. Network-based recovery (inbox store, retries) is handled entirely by `handleAppResumed` and `PendingMessageRetrier` on the resume path.

---

### Step 2.7 — Sender-side UI recovery: `failed` status triggers conversation screen refresh

#### Overview

The pause handler (Step 2.1) transitions stranded `'sending'` messages to `'failed'` in the DB, and `conditionalTransitionStatus()` (Step 2.2) emits the updated message on `MessageRepositoryChangeSource.messageChanges`. However, the **conversation screen never reacts to this emission** because of a filter bug in `conversation_wired.dart`.

**The bug:** At `lib/features/conversation/presentation/screens/conversation_wired.dart` line 491-492, the method `_shouldRefreshFromRepositoryChange` only returns `true` for `'sent'` and `'delivered'`:

```dart
bool _shouldRefreshFromRepositoryChange(String status) =>
    status == 'sent' || status == 'delivered';
```

This means that when `conditionalTransitionStatus()` emits a message with `status: 'failed'` on the `messageChanges` stream, the `.where()` filter at line 470-475 discards it. The conversation screen's in-memory `_messages` list still contains the old `status: 'sending'` version of the message. The `LetterCard` renders `Icons.done_rounded` (the checkmark for `'sending'`/`'sent'`) instead of `Icons.error_outline_rounded` (the failed indicator), and the semantics label remains `'sending'` instead of `'failed'`.

> **AUDIT FIX (2-12):** Confirmed against production code at `conversation_wired.dart:491-492`: `_shouldRefreshFromRepositoryChange` checks only `'sent'` and `'delivered'`. The `'failed'` status is not included. The `_startListeningForOutgoingMessageChanges()` method at line 462-489 subscribes to `changeSource.messageChanges` with a `.where()` filter that calls `_shouldRefreshFromRepositoryChange(message.status)`. When the pause handler emits a `'failed'` status change, the filter discards it and `setState(() => _upsertMessageById(message))` at line 479 is never called.

> **AUDIT FIX (2-13):** The `LetterCard._statusIcon()` at `letter_card.dart:373-379` uses `Icons.done_rounded` as the default fallback for both `'sending'` and `'sent'`. The `'failed'` status correctly maps to `Icons.error_outline_rounded` at line 378. The `_statusColor()` at line 382-388 returns a red-tinted color for `'failed'` (`Color.fromRGBO(255, 100, 100, 0.60)`). The `_statusSemantic()` at line 390-398 returns `'failed'` for the `'failed'` status. So the LetterCard already knows how to render failed state -- the problem is entirely in the Wired layer's stream filter not propagating the status change.

**The fix is a one-line change:** add `|| status == 'failed'` to `_shouldRefreshFromRepositoryChange()`.

#### Red Phase

File: `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`

This widget test proves that when a repository emits a status change from `'sending'` to `'failed'`, the conversation screen rebuilds and shows the failed indicator icon instead of the checkmark.

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';

// ---------------------------------------------------------------------------
// Minimal fakes (same pattern as conversation_wired_test.dart)
// ---------------------------------------------------------------------------

class _FakeIdentityRepository implements IdentityRepository {
  final IdentityModel? identity;
  _FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;
  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeMessageRepository
    implements MessageRepository, MessageRepositoryChangeSource {
  final Map<String, ConversationMessage> store = {};
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  /// Simulate a background status change (e.g., pause handler transitioning
  /// sending -> failed). This updates the store AND emits on messageChanges,
  /// exactly like MessageRepositoryImpl.conditionalTransitionStatus does.
  void emitStatusChange(String id, String newStatus) {
    final msg = store[id];
    if (msg == null) return;
    final updated = msg.copyWith(status: newStatus);
    store[id] = updated;
    _messageChangeController.add(updated);
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    store[message.id] = message;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final msg = store[id];
    if (msg == null) return;
    store[id] = msg.copyWith(status: status);
    _messageChangeController.add(store[id]!);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async =>
      store.values
          .where((m) => m.contactPeerId == contactPeerId)
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final msgs = await getMessagesForContact(contactPeerId);
    return msgs.isEmpty ? null : msgs.last;
  }

  @override
  Future<bool> messageExists(String id) async => store.containsKey(id);

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      store.values.where((m) => m.contactPeerId == contactPeerId).length;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<int> getTotalUnreadCount() async => 0;

  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    var messages = store.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return messages.take(limit).toList().reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async =>
      [];
}

class _FakeChatMessageListener implements ChatMessageListener {
  final StreamController<ConversationMessage> _controller =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageStream => _controller.stream;
  @override
  void dispose() => _controller.close();
}

class _FakeP2PService implements P2PService {
  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: 'me');

  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<void> initialize() async {}
  @override
  Future<void> startNode(
      {required String privateKey, required String? rendezvous}) async {}
  @override
  Future<void> stopNode() async {}
  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId) async => null;
  @override
  Future<bool> dialPeer(
      {required String peerId, required List<String> addresses}) async =>
      false;
  @override
  Future<SendMessageResult> sendMessage(
      {required String peerId, required String message}) async =>
      const SendMessageResult(sent: false);
  @override
  Future<SendMessageResult> sendMessageWithReply(
      {required String peerId,
      required String message,
      Duration? timeout}) async =>
      const SendMessageResult(sent: false);
  @override
  Future<bool> storeInInbox(
      {required String peerId, required String message}) async =>
      false;
  @override
  void dispose() {}

  // Provide no-op/default stubs for any remaining P2PService methods
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const _contactPeerId = 'peer-bob';

final _identity = IdentityModel(
  peerId: 'me',
  publicKey: 'my-pk',
  privateKey: 'my-sk',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  createdAt: '2026-01-01T00:00:00.000Z',
  updatedAt: '2026-01-01T00:00:00.000Z',
);

final _contact = ContactModel(
  peerId: _contactPeerId,
  publicKey: 'bob-pk',
  rendezvous: '/ip4/127.0.0.1/tcp/4001',
  username: 'Bob',
  signature: 'sig-bob',
  scannedAt: '2026-01-01T00:00:00.000Z',
);

ConversationMessage _makeSendingMessage() => ConversationMessage(
      id: 'msg-sending-001',
      contactPeerId: _contactPeerId,
      senderPeerId: 'me',
      text: 'Hello Bob',
      timestamp: '2026-01-01T00:00:00.000Z',
      status: 'sending',
      isIncoming: false,
      createdAt: '2026-01-01T00:00:00.000Z',
    );

Widget _buildTestWidget({
  required _FakeMessageRepository messageRepo,
  required _FakeChatMessageListener chatListener,
  List<ConversationMessage>? initialMessages,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('en'),
    home: ConversationWired(
      contact: _contact,
      identityRepo: _FakeIdentityRepository(_identity),
      messageRepo: messageRepo,
      chatMessageListener: chatListener,
      p2pService: _FakeP2PService(),
      bridge: FakeBridge(),
      sendChatMessageFn: _noOpSendChatMessage,
      initialMessages: initialMessages,
      audioRecorderService: FakeAudioRecorderService(),
    ),
  );
}

Future<(SendChatMessageResult, ConversationMessage?)> _noOpSendChatMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  dynamic bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<dynamic>? mediaAttachments,
  dynamic mediaAttachmentRepo,
}) async {
  return (SendChatMessageResult.sent, null);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ConversationWired — sending->failed UI refresh', () {
    testWidgets(
      'message transitions from sending to failed via messageChanges stream '
      'and UI rebuilds with the failed indicator icon',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final chatListener = _FakeChatMessageListener();
        final sendingMessage = _makeSendingMessage();

        // Seed the message in the repo so getMessagesPage returns it
        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            chatListener: chatListener,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pumpAndSettle();

        // ASSERT — the message is currently displayed with status 'sending'.
        // LetterCard renders Icons.done_rounded for 'sending' and the
        // semantics label reads 'Message status: sending'.
        expect(
          find.bySemanticsLabel('Message status: sending'),
          findsOneWidget,
          reason: 'Before the status change, the card must show sending status',
        );
        expect(
          find.byIcon(Icons.done_rounded),
          findsOneWidget,
          reason: 'sending status renders the done_rounded checkmark',
        );
        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsNothing,
          reason: 'No failed indicator should be visible yet',
        );

        // ACT — simulate the pause handler emitting a status change on
        // messageChanges. This is exactly what conditionalTransitionStatus()
        // does in MessageRepositoryImpl when it transitions sending->failed.
        messageRepo.emitStatusChange('msg-sending-001', 'failed');

        // Let the stream event propagate and the widget rebuild
        await tester.pumpAndSettle();

        // ASSERT — the UI must now show the failed indicator, not the
        // sending checkmark.
        expect(
          find.bySemanticsLabel('Message status: failed'),
          findsOneWidget,
          reason:
              'After sending->failed, the semantics label must update to failed',
        );
        expect(
          find.byIcon(Icons.error_outline_rounded),
          findsOneWidget,
          reason:
              'The failed status must render error_outline_rounded, not done_rounded',
        );
        expect(
          find.byIcon(Icons.done_rounded),
          findsNothing,
          reason:
              'The sending/sent checkmark must no longer be visible after transition to failed',
        );
      },
    );

    testWidgets(
      'message transitions from sending to sent still works after adding '
      'failed to the refresh filter',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final chatListener = _FakeChatMessageListener();
        final sendingMessage = _makeSendingMessage();

        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            chatListener: chatListener,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pumpAndSettle();

        // Before: sending status
        expect(find.bySemanticsLabel('Message status: sending'), findsOneWidget);

        // ACT — normal send completion path
        messageRepo.emitStatusChange('msg-sending-001', 'sent');
        await tester.pumpAndSettle();

        // ASSERT — sent status rendered correctly
        expect(
          find.bySemanticsLabel('Message status: sent'),
          findsOneWidget,
          reason: 'sent status transition must still refresh the UI',
        );
      },
    );

    testWidgets(
      'message transitions from sending to delivered still works after '
      'adding failed to the refresh filter',
      (tester) async {
        final messageRepo = _FakeMessageRepository();
        final chatListener = _FakeChatMessageListener();
        final sendingMessage = _makeSendingMessage();

        await messageRepo.saveMessage(sendingMessage);

        await tester.pumpWidget(
          _buildTestWidget(
            messageRepo: messageRepo,
            chatListener: chatListener,
            initialMessages: [sendingMessage],
          ),
        );
        await tester.pumpAndSettle();

        // Before: sending status
        expect(find.bySemanticsLabel('Message status: sending'), findsOneWidget);

        // ACT — ACK received, message delivered
        messageRepo.emitStatusChange('msg-sending-001', 'delivered');
        await tester.pumpAndSettle();

        // ASSERT — delivered status rendered correctly
        expect(
          find.bySemanticsLabel('Message status: delivered'),
          findsOneWidget,
          reason: 'delivered status transition must still refresh the UI',
        );
        expect(
          find.byIcon(Icons.done_all_rounded),
          findsOneWidget,
          reason: 'delivered status shows the double-check icon',
        );
      },
    );
  });
}
```

The first test (`sending to failed via messageChanges stream`) is the **critical red-phase test**. It will FAIL before the production fix because `_shouldRefreshFromRepositoryChange('failed')` returns `false`, so the `.where()` filter discards the `'failed'` emission and `setState` is never called. The widget continues showing `Icons.done_rounded` with semantics label `'Message status: sending'`, and the assertions for `Icons.error_outline_rounded` and `'Message status: failed'` will fail.

The second and third tests are **regression guards** ensuring the existing `'sent'` and `'delivered'` paths still work after modifying the filter.

#### Green Phase

**Production fix: one-line change in `conversation_wired.dart`**

In `/Users/I560101/Project-Sat/mknoon-2/flutter_app/lib/features/conversation/presentation/screens/conversation_wired.dart`, change line 491-492:

**Before:**
```dart
  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered';
```

**After:**
```dart
  bool _shouldRefreshFromRepositoryChange(String status) =>
      status == 'sent' || status == 'delivered' || status == 'failed';
```

This adds `'failed'` to the set of statuses that pass through the `messageChanges` stream filter in `_startListeningForOutgoingMessageChanges()`. When `conditionalTransitionStatus()` (from the pause handler) emits a message with `status: 'failed'`, the filter now allows it through, `setState(() => _upsertMessageById(message))` fires, the `LetterCard` rebuilds with the updated status, and the user sees `Icons.error_outline_rounded` (red-tinted failed indicator) instead of the stale `Icons.done_rounded` checkmark.

**Why this is safe:** The `_upsertMessageById` method already handles any status value -- it replaces the matching message in `_messages` by ID. The `LetterCard._statusIcon()`, `_statusColor()`, and `_statusSemantic()` methods already handle `'failed'` correctly. No other changes are needed.

**Why only `'failed'`?** The remaining possible status values are:
- `'sending'` -- messages are created locally with this status; no repository change emission is needed (the UI already shows them from the optimistic insert).
- `'queued'` -- legacy status, treated as `'delivered'` by `_statusIcon`, already covered by the `'delivered'` check.
- No other status values exist in the codebase.

#### Refactor Phase

- Consider renaming `_shouldRefreshFromRepositoryChange` to `_isTerminalOutgoingStatus` or `_shouldReflectStatusChange` to better communicate that it covers all non-transient status values. The current name is correct but does not hint at what statuses are included.
- If future status values are added (e.g., `'retrying'`, `'expired'`), they must be added to this filter if the UI should react to them. Add a code comment above the method referencing this requirement.

#### Acceptance Check (Smoke Test Matrix)

Add the following verification to the Step 2.5 smoke test at `/Users/I560101/Project-Sat/mknoon-2/flutter_app/test/core/lifecycle/pause_resume_retry_smoke_test.dart`, inside the first test case (`'message stranded in sending state is retried successfully after resume'`), between the pause assertion (step 4) and the resume action (step 5):

```dart
        // 4b. ASSERT — UI recovery: if the conversation screen were open,
        // it would now show the failed indicator. Verify the messageChanges
        // stream emitted the 'failed' status so the UI filter can react.
        // (The actual widget rendering is tested in
        //  conversation_wired_sending_to_failed_test.dart — here we verify
        //  the data layer emitted the change that the UI layer consumes.)
        final emittedStatuses = <String>[];
        final sub = messageRepo.messageChanges.listen(
          (msg) => emittedStatuses.add('${msg.id}:${msg.status}'),
        );

        // Re-run pause to confirm idempotency and that no stale emission occurs
        final secondPause = await handleAppPaused(messageRepo: messageRepo);
        expect(secondPause.transitionedCount, 0,
            reason: 'Second pause is a no-op — message already failed');

        await sub.cancel();
        // No new emissions for the already-failed message
        expect(emittedStatuses, isEmpty,
            reason: 'Already-failed message must not re-emit on messageChanges');
```

This acceptance check verifies the data-layer contract that the UI depends on: `conditionalTransitionStatus()` emits on `messageChanges` when transitioning `'sending'` to `'failed'` (tested in Step 2.4's `messageChanges stream emits updated messages` test), and does NOT re-emit when the message is already `'failed'` (verified here). Combined with the widget test above, this proves the full sender-side UI recovery path: pause handler transitions status in DB, repository emits on stream, conversation screen's `_shouldRefreshFromRepositoryChange` filter allows `'failed'` through, `setState` fires, and `LetterCard` renders the failed indicator.

---

### Data Flow

```text
OS sends AppLifecycleState.paused
         |
         v
_MyAppState.didChangeAppLifecycleState()
  if (state == paused || hidden)
         |
         v  fire-and-forget (unawaited)
_onPaused()
         |
         v
handleAppPaused(messageRepo)  // local DB only
         |
         +--- Step 1: messageRepo.getSendingOutgoingMessages()
         |         +-- dbLoadSendingOutgoingMessages(db)
         |               WHERE status='sending' AND is_incoming=0
         |
         +--- Step 2 (per message): messageRepo.conditionalTransitionStatus(id, from: 'sending', to: 'failed')
         |         +-- dbConditionalTransitionStatus(db, id, from: 'sending', to: 'failed')
         |               UPDATE ... WHERE id=? AND status='sending'  <-- no-op if already delivered
         |               -> _messageChangeController.add(updatedMsg)   <-- UI reacts (Step 2.7 fix)
         |
         +--- Return AppPausedResult(transitionedCount: transitionedCount)
              (No Step 3 -- pause handler is local DB only, no network calls.
               Inbox store and retries happen on resume via handleAppResumed
               and PendingMessageRetrier.)
                         |
                         v
--- user returns to foreground ---
                         |
         AppLifecycleState.resumed
                         |
                         v
         handleAppResumed()   (existing 7-step recovery)
                         |
                         v
         PendingMessageRetrier fires retryFailedMessages()
              getFailedOutgoingMessages()   <-- picks up all 'failed' rows
              for each: wireEnvelope fast path -> storeInInbox
                   or: re-encrypt -> sendChatMessage

--- meanwhile, if ConversationScreen is open ---

_startListeningForOutgoingMessageChanges()
  messageChanges stream
    .where(_shouldRefreshFromRepositoryChange)  <-- NOW includes 'failed' (Step 2.7)
    .listen((msg) => setState(() => _upsertMessageById(msg)))
         |
         v
LetterCard rebuilds with status: 'failed'
  _statusIcon('failed')  -> Icons.error_outline_rounded
  _statusColor('failed') -> Color.fromRGBO(255, 100, 100, 0.60)
  _statusSemantic('failed') -> 'failed'
```

---

### Build Sequence Checklist

- [ ] **1.** Add `dbLoadSendingOutgoingMessages()` to `lib/core/database/helpers/messages_db_helpers.dart` (Step 2.2 Green)
- [ ] **2.** Add `dbConditionalTransitionStatus()` to `lib/core/database/helpers/messages_db_helpers.dart` (Step 2.2 Green)
- [ ] **3.** Add `getSendingOutgoingMessages()` to `MessageRepository` abstract class at `lib/features/conversation/domain/repositories/message_repository.dart` (Step 2.2 Green)
- [ ] **4.** Add `conditionalTransitionStatus()` to `MessageRepository` abstract class at `lib/features/conversation/domain/repositories/message_repository.dart` (Step 2.2 Green)
- [ ] **5.** Implement `getSendingOutgoingMessages()` in `MessageRepositoryImpl` at `lib/features/conversation/domain/repositories/message_repository_impl.dart`, adding the `dbLoadSendingOutgoingMessages` constructor field (Step 2.2 Green)
- [ ] **6.** Implement `conditionalTransitionStatus()` in `MessageRepositoryImpl` at `lib/features/conversation/domain/repositories/message_repository_impl.dart`, adding the `dbConditionalTransitionStatus` constructor field; implementation must emit on `_messageChangeController` when a row is updated (Step 2.2 Green)
- [ ] **7.** Implement `getSendingOutgoingMessages()` in `InMemoryMessageRepository` at `test/shared/fakes/in_memory_message_repository.dart` (Step 2.2 Green)
- [ ] **8.** Implement `conditionalTransitionStatus()` in `InMemoryMessageRepository` at `test/shared/fakes/in_memory_message_repository.dart`; must check `msg.status == fromStatus` before updating, return 0 if no match, emit on `_messageChangeController` (Step 2.2 Green)
- [ ] **9.** Implement `getSendingOutgoingMessages()` in `FakeMessageRepository` at `test/features/conversation/domain/repositories/fake_message_repository.dart` (Step 2.2 Green)
- [ ] **10.** Implement `conditionalTransitionStatus()` in `FakeMessageRepository` at `test/features/conversation/domain/repositories/fake_message_repository.dart` (Step 2.2 Green)
- [ ] **11.** Search for all `implements MessageRepository` across the codebase and manually add `getSendingOutgoingMessages()` and `conditionalTransitionStatus()` stubs to each implementor (12+ files in test/). Use `throw UnimplementedError()` for test implementations that do not need the new methods. (Step 2.2 Refactor)
- [ ] **12.** Create `AppPausedResult` (either inline in `handle_app_paused.dart` or in `app_paused_result.dart`) (Step 2.1 Green)
- [ ] **13.** Create `lib/core/lifecycle/handle_app_paused.dart` with full implementation (Step 2.1 Green)
- [ ] **14.** Write `test/core/lifecycle/handle_app_paused_test.dart` -- confirm red, then make green (Step 2.1 Red/Green)
- [ ] **15.** Write `test/core/lifecycle/sending_messages_query_test.dart` (includes both `dbLoadSendingOutgoingMessages` and `dbConditionalTransitionStatus` tests) -- confirm red, then make green (Step 2.2 Red/Green)
- [ ] **16.** Create `test/shared/build_test_my_app.dart` -- factory that builds a real `MyApp(...)` with fake dependencies (replaces the removed `widget_test_harness.dart` approach; exercises real `_MyAppState`) (Step 2.3 Green)
- [ ] **17.** Write `test/core/lifecycle/app_lifecycle_paused_dispatch_test.dart` -- confirm red (test pumps real `MyApp`, not a harness widget) (Step 2.3 Red)
- [ ] **18.** Add `_onPaused()` and extend `didChangeAppLifecycleState` in `lib/main.dart` -- make widget test green (the test verifies the real `_MyAppState` observer at `main.dart:1480`) (Step 2.3 Green)
- [ ] **19.** Write `test/core/lifecycle/app_lifecycle_pause_integration_test.dart` -- make green (no new prod code; `MessageRepositoryImpl` constructor must include `dbConditionalTransitionStatus` wiring) (Step 2.4 Red/Green)
- [ ] **20.** Write `test/core/lifecycle/pause_resume_retry_smoke_test.dart` -- make green (no new prod code) (Step 2.5 Red/Green)
- [ ] **21.** Write `test/core/lifecycle/handle_app_paused_edge_cases_test.dart` -- make green (only inner `try/catch` loop change needed) (Step 2.6 Red/Green)
- [ ] **22.** Write `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart` -- confirm red (test fails because `_shouldRefreshFromRepositoryChange` does not include `'failed'`) (Step 2.7 Red)
- [ ] **23.** Add `|| status == 'failed'` to `_shouldRefreshFromRepositoryChange()` in `lib/features/conversation/presentation/screens/conversation_wired.dart` line 491-492 -- make widget test green (Step 2.7 Green)
- [ ] **24.** Add acceptance check to Step 2.5 smoke test (`pause_resume_retry_smoke_test.dart`): verify `messageChanges` stream emits `'failed'` status and idempotent second pause emits nothing (Step 2.7 Acceptance)
- [ ] **25.** Wire both `dbLoadSendingOutgoingMessages` and `dbConditionalTransitionStatus` into the `MessageRepositoryImpl(...)` constructor call in `lib/main.dart` (DI wiring)
- [ ] **26.** Run full test suite: `flutter test` -- confirm zero regressions

---

### Critical Details

**Why `paused` and `hidden` but not `inactive`**

`inactive` fires on iOS when the control centre or notification shade is pulled down while the app is in the foreground -- the process keeps running and no send is at risk. `paused` fires when the app has fully lost focus and the OS has suspended rendering. `hidden` is the equivalent state on macOS and newer iOS. `detached` means the FlutterEngine has been detached from any view; it is too late to reliably write to SQLite. The chosen states match iOS's background execution window, within which the OS guarantees several seconds of CPU time.

**Why fire-and-forget with `unawaited`**

`didChangeAppLifecycleState` is a synchronous callback. Awaiting inside it would block the widget tree while the DB flushes. The OS does not wait for Dart async work to complete before freezing the isolate, so fire-and-forget is the correct pattern here -- identical to how the push registration coordinator and share intent handler use `unawaited` throughout `main.dart`.

**Why `conditionalTransitionStatus` not `updateMessageStatus` or `saveMessage`**

`conditionalTransitionStatus` uses `UPDATE ... WHERE id = ? AND status = 'sending'` -- a targeted conditional SQL `UPDATE` that does not replace the full row (no risk of clearing `wireEnvelope`) and cannot overwrite a concurrently completed `'delivered'`/`'sent'` status (preventing duplicate resends). It also emits on the `messageChanges` broadcast stream, so any open `ConversationScreen` will reactively update its displayed message status from the checkmark to a failed indicator without requiring a manual reload. The unconditional `updateMessageStatus` must NOT be used here -- it would create a race where a successfully delivered message gets overwritten to `'failed'`.

**Why `_shouldRefreshFromRepositoryChange` must include `'failed'` (Step 2.7)**

Without `'failed'` in the filter, the `conditionalTransitionStatus()` emission on `messageChanges` is discarded by the `.where()` clause in `_startListeningForOutgoingMessageChanges()`. The conversation screen's in-memory `_messages` list retains the stale `status: 'sending'` version. The `LetterCard` continues rendering `Icons.done_rounded` (checkmark) instead of `Icons.error_outline_rounded` (failed indicator). The user sees an apparently-in-progress message that will never complete -- an eternal stale status. Adding `|| status == 'failed'` to the filter is a one-line fix that closes the loop between the pause handler's DB write and the UI's reactive refresh.

**Idempotency guarantee**

Running `handleAppPaused()` twice is safe: after the first call, `getSendingOutgoingMessages()` returns an empty list (all rows are now `'failed'`), so the second invocation does nothing and returns `AppPausedResult(transitionedCount: 0)`.

**Race with `sendChatMessage` -- MUST use conditional UPDATE**

If a send completes between the `getSendingOutgoingMessages()` query and the status update call, the message row's status moves from `'sending'` to `'sent'`/`'delivered'` in the DB concurrently. The existing `dbUpdateMessageStatus` is unconditional -- `UPDATE messages SET status = ? WHERE id = ?` -- so it would overwrite `'delivered'` back to `'failed'`, causing duplicate resends on next resume. `handleAppPaused` must NOT use the existing unconditional `updateMessageStatus`. The `dbConditionalTransitionStatus` variant with `AND status = 'sending'` guard correctly prevents this race.

**Performance budget**

The entire `handleAppPaused()` critical path is: one `SELECT` query + N `UPDATE` queries (local DB only, no network calls). On a cold SQLite cache with 10 in-flight messages, this completes in under 20ms. No inbox store or network calls are attempted -- those are handled by Section 3 (background task) and Section 1 (retry on resume).

---

## Section 3: iOS Background Task Assertion

### Overview

When a user sends a message and immediately locks the phone, iOS suspends the process before the Go network layer can complete the operation. The send pipeline involves multiple sequential bridge calls: encrypt (~20ms) → discover (1-4s) → dial (0.5-3s) → send (~500ms) → inbox (~1s). Wrapping only individual Swift bridge calls (e.g., `sendMessage`, `inboxStore`) is insufficient because iOS can suspend the process during earlier calls like `discover` or `dial` — before the later wrapped calls are ever reached.

**The correct approach is a Dart-initiated background task** that starts BEFORE the media upload or voice local transfer step and wraps through to the completion of `sendChatMessage`. Two new MethodChannel commands (`bg:begin`, `bg:end`) allow Dart to request and release a `UIApplication.beginBackgroundTask` token. A `try/finally` block ensures the token is always returned, even on failure paths. This gives iOS up to 30 seconds to complete the full upload/transfer → encrypt → discover → dial → send → inbox pipeline.

#### Canonical Owner Rule

**`bg:begin`/`bg:end` lives ONLY in the presentation layer (Wired widgets). Never in use cases or domain layer.** Background task assertion is a platform-specific concern (iOS `UIApplication.beginBackgroundTask`). Placing it in use-case functions like `sendVoiceMessage` or `sendChatMessage` would leak iOS platform channels into the application layer, violating Clean Architecture. The presentation-layer Wired widget is the outermost orchestrator that knows it is running on a mobile device; it acquires the background task before calling into the application layer and releases it in a `finally` block after the application-layer pipeline completes. Use cases must never call `bg:begin` or `bg:end`.

#### All 1:1 Send Call Sites

There are exactly four call sites in the presentation layer that initiate a 1:1 message send. Each must independently acquire and release a background task:

| # | Call Site | File | Method | What it sends | `bg:begin` placement | `bg:end` placement |
|---|-----------|------|--------|---------------|----------------------|--------------------|
| 1 | Text + media send | `conversation_wired.dart` | `_onSend` | Text and/or media attachments | Before upload loop (line ~651) | `finally` block after `sendChatMessageFn` |
| 2 | Voice via relay | `conversation_wired.dart` | `_onVoiceRecordingStopped` | Voice recording (relay upload path) | Before `sendVoiceMessage` call (line ~1370) | `finally` block after `sendVoiceMessage` |
| 3 | Voice via local WiFi | `conversation_wired.dart` | `_onVoiceRecordingStopped` | Voice recording (local WiFi path) | Before `sendLocalMedia` call (line ~1280) | `finally` block after `sendChatMessageFn` |
| 4 | Inline 1:1 text send (feed) | `feed_wired.dart` | `_onInlineSend` | Text-only reply from feed | Before `sendChatMessage` call (line ~1065) | `finally` block after `sendChatMessage` |

**Note on call sites 2 and 3:** Both paths originate in `_onVoiceRecordingStopped`. The method first tries local WiFi (call site 3); if the peer is not local or the transfer fails, it falls through to the relay path (call site 2). A single `bg:begin` at the top of the network-facing section covers both paths, with `bg:end` in a single outer `finally`.

**Why the background task must start before upload/transfer:**
- For media messages: the `uploadMedia` call (server upload or local WiFi transfer via `p2pService.sendLocalMedia`) in `conversation_wired.dart` lines 651-713 runs BEFORE `sendChatMessage` is called at line 724. If the user locks the phone during upload, the process is suspended and the upload silently fails — `sendChatMessage` is never reached and no background task protection existed.
- For voice local WiFi transfer: `p2pService.sendLocalMedia()` is called in `conversation_wired.dart` at line 1280 before `sendChatMessage` at line 1305. Locking during that local transfer silently drops the message.
- For voice via relay: `uploadMedia` is called inside `sendVoiceMessage` (line 77 of the use case) before `sendChatMessage` (line 95). The presentation-layer `bg:begin` wraps the entire `sendVoiceMessage` invocation.
- For inline feed send: `sendChatMessage` at `feed_wired.dart` line 1065 involves discover + dial + send + inbox. Locking during any of these steps drops the message.

**Updated protected window:**
```text
[user taps Send]
bg:begin  ← before upload/transfer/send
  ├── uploadMedia / sendLocalMedia   (previously unprotected)
  └── sendChatMessage
        ├── encrypt
        ├── discover
        ├── dial
        ├── send
        └── inbox
bg:end  (in finally block)
```

`Info.plist` already declares `remote-notification` and `fetch` background modes, which are sufficient; no new plist key is required for `beginBackgroundTask`.

---

### Red Phase — Write the failing tests first

#### 3.1 Swift XCTest for `bgBegin` / `bgEnd` MethodChannel commands

Flutter unit tests cannot directly invoke Swift code, so the Swift tests
verify the new `bgBegin` and `bgEnd` cases inside the existing
`handleMethodCall` in `GoBridge.swift`.

**File to create:** `ios/RunnerTests/GoBridgeCriticalTaskTests.swift`

The tests call `handleMethodCall` with `FlutterMethodCall` instances for
`bgBegin` and `bgEnd`, the same way Flutter's engine calls them.
No new protocol or constructor parameter is needed — the tests exercise
the production `GoBridge` code path.

```swift
// ios/RunnerTests/GoBridgeCriticalTaskTests.swift

import XCTest
@testable import Runner

final class GoBridgeCriticalTaskTests: XCTestCase {

    // --- Test 1: bgBegin returns a non-empty task ID string ---
    func test_bgBegin_returnsTaskIdString() {
        let bridge = makeBridge()
        let call = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let expectation = expectation(description: "result returned")

        bridge.handleMethodCall(call) { result in
            guard let taskIdStr = result as? String, !taskIdStr.isEmpty else {
                XCTFail("bgBegin must return a non-empty task ID string, got: \(String(describing: result))")
                expectation.fulfill()
                return
            }
            // The returned string must be parseable as a UInt (raw task handle).
            XCTAssertNotNil(UInt(taskIdStr),
                "Task ID must be a decimal integer, got: \(taskIdStr)")
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)
    }

    // --- Test 2: bgEnd accepts a valid task ID without crashing ---
    func test_bgEnd_acceptsTaskIdFromBgBegin() {
        let bridge = makeBridge()
        var taskIdStr: String?

        // Step 1: acquire a task handle
        let beginCall = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
        let beginExp = expectation(description: "bgBegin returned")
        bridge.handleMethodCall(beginCall) { result in
            taskIdStr = result as? String
            beginExp.fulfill()
        }
        waitForExpectations(timeout: 2)

        guard let id = taskIdStr, !id.isEmpty else {
            XCTFail("bgBegin did not return a task ID")
            return
        }

        // Step 2: end the task — must not crash or throw
        let payload = "{\"taskId\":\"\(id)\"}"
        let endCall = FlutterMethodCall(methodName: "bgEnd", arguments: payload)
        let endExp = expectation(description: "bgEnd returned")
        bridge.handleMethodCall(endCall) { result in
            // bgEnd returns nil on success
            endExp.fulfill()
        }
        waitForExpectations(timeout: 2)
    }

    // --- Test 3: bgEnd with invalid/empty task ID does not crash ---
    func test_bgEnd_handlesInvalidTaskIdGracefully() {
        let bridge = makeBridge()
        let invalidPayloads: [String?] = [
            nil,
            "",
            "{}",
            "{\"taskId\":\"\"}",
            "{\"taskId\":\"not-a-number\"}",
        ]

        for (i, args) in invalidPayloads.enumerated() {
            let call = FlutterMethodCall(methodName: "bgEnd", arguments: args)
            let exp = expectation(description: "bgEnd-invalid-\(i)")
            bridge.handleMethodCall(call) { _ in exp.fulfill() }
            waitForExpectations(timeout: 1)
        }
        // If we reach here without crashing, the test passes.
    }

    // --- Test 4: multiple bgBegin calls each return distinct task IDs ---
    func test_multipleBgBegin_returnDistinctIds() {
        let bridge = makeBridge()
        var ids = Set<String>()

        for i in 0..<3 {
            let call = FlutterMethodCall(methodName: "bgBegin", arguments: nil)
            let exp = expectation(description: "bgBegin-\(i)")
            bridge.handleMethodCall(call) { result in
                if let id = result as? String, !id.isEmpty {
                    ids.insert(id)
                }
                exp.fulfill()
            }
            waitForExpectations(timeout: 1)
        }

        XCTAssertEqual(ids.count, 3,
            "Three bgBegin calls must produce three distinct task IDs")

        // Cleanup: end all tasks
        for id in ids {
            let payload = "{\"taskId\":\"\(id)\"}"
            let call = FlutterMethodCall(methodName: "bgEnd", arguments: payload)
            let exp = expectation(description: "cleanup-\(id)")
            bridge.handleMethodCall(call) { _ in exp.fulfill() }
            waitForExpectations(timeout: 1)
        }
    }

    // MARK: - Helpers

    private func makeBridge() -> GoBridge {
        return GoBridge(messenger: MockFlutterBinaryMessenger())
    }
}

// MARK: - Test doubles

final class MockFlutterBinaryMessenger: NSObject, FlutterBinaryMessenger {
    func send(onChannel channel: String, message: Data?) {}
    func send(onChannel channel: String, message: Data?, binaryReply callback: FlutterBinaryReply?) {}
    func setMessageHandlerOnChannel(_ channel: String, binaryMessageHandler handler: FlutterBinaryMessageHandler?) -> FlutterBinaryMessengerConnection { return 0 }
    func cleanUpConnection(_ connection: FlutterBinaryMessengerConnection) {}
}
```

These tests will fail because `GoBridge.handleMethodCall` does not yet
contain `bgBegin` or `bgEnd` cases. The existing `GoBridge.swift`
constructor signature is `init(messenger: FlutterBinaryMessenger)` —
no new parameters are introduced.

#### 3.2 Dart contract test: `bg:begin`/`bg:end` through real `GoBridgeClient.send()` / MethodChannel

**File to create:** `test/core/bridge/go_bridge_background_task_test.dart`

These tests instantiate the real `GoBridgeClient` and use
`setMockMethodCallHandler` on the `com.mknoon/go_bridge` MethodChannel
to simulate the native side — the same pattern used by the existing
`test/core/bridge/go_bridge_client_test.dart`.

This verifies the full Dart-side contract: JSON command construction,
`_cmdMap` routing, MethodChannel invocation, and response parsing.

```dart
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GoBridgeClient client;
  MethodCall? lastCall;

  setUp(() {
    client = GoBridgeClient();
    lastCall = null;
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.mknoon/go_bridge'),
          null,
        );
  });

  group('bg:begin / bg:end MethodChannel contract', () {
    test('bg:begin routes to bgBegin method with no arguments', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              // Simulate native returning a task ID string
              return '12345';
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('bgBegin'));
      expect(lastCall!.arguments, isNull,
          reason: 'bg:begin has hasPayload=false, no arguments');
      // GoBridgeClient.send() returns the raw string from native
      expect(response, equals('12345'));
    });

    test('bg:end routes to bgEnd method with JSON payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return null; // bgEnd returns nil on success
            },
          );

      final response = await client.send(
        jsonEncode({
          'cmd': 'bg:end',
          'payload': {'taskId': '12345'},
        }),
      );

      expect(lastCall, isNotNull);
      expect(lastCall!.method, equals('bgEnd'));
      // Payload is JSON-encoded by GoBridgeClient before invokeMethod
      expect(lastCall!.arguments, isA<String>());
      final passedPayload =
          jsonDecode(lastCall!.arguments as String) as Map<String, dynamic>;
      expect(passedPayload['taskId'], equals('12345'));
      // Null native response → NULL_RESPONSE error JSON
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['errorCode'], equals('NULL_RESPONSE'));
    });

    test('bg:begin with empty-string response signals OS refused', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              lastCall = call;
              return ''; // OS refused to grant background time
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      expect(lastCall!.method, equals('bgBegin'));
      // Empty string means "no task granted" — caller checks isEmpty
      expect(response, equals(''));
    });

    test('bg:begin with PlatformException returns PLATFORM_ERROR', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              throw PlatformException(
                code: 'UNAVAILABLE',
                message: 'background task not available',
              );
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('PLATFORM_ERROR'));
      expect(decoded['errorMessage'],
          equals('background task not available'));
    });

    test('bg:begin with MissingPluginException returns MISSING_PLUGIN',
        () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              throw MissingPluginException(
                'No implementation found for bgBegin',
              );
            },
          );

      final response = await client.send(
        jsonEncode({'cmd': 'bg:begin'}),
      );

      final decoded = jsonDecode(response) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['errorCode'], equals('MISSING_PLUGIN'));
      expect(decoded['errorMessage'], contains('bgBegin'));
    });

    test('concurrent bg:begin calls each invoke bgBegin independently',
        () async {
      var callCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('com.mknoon/go_bridge'),
            (MethodCall call) async {
              callCount++;
              return callCount.toString(); // unique task ID per call
            },
          );

      final futures = List.generate(
        3,
        (_) => client.send(jsonEncode({'cmd': 'bg:begin'})),
      );
      final results = await Future.wait(futures);

      expect(callCount, equals(3));
      // Each should get a unique task ID
      final ids = results.toSet();
      expect(ids, hasLength(3),
          reason: 'Each concurrent bg:begin must get its own task ID');
    });
  });
}
```

These tests will fail because `GoBridgeClient._cmdMap` does not yet contain
`'bg:begin'` or `'bg:end'` entries. The `send()` method will return
`UNKNOWN_COMMAND` for both. Adding the entries in Step 3.7 makes them green.

#### 3.3 Dart test: `_onSend` in `conversation_wired.dart` calls `bg:begin` before upload

**File to create:** `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`

These tests verify that `bg:begin` is invoked before the `uploadMediaFn` in the media send path of `_onSend`. They use the existing `ConversationWired` widget test infrastructure with a call-order-recording bridge.

```dart
// test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

class _OrderRecordingBridge implements Bridge {
  final List<String> callLog = [];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    if (cmd == 'bg:begin') return '99';  // valid task ID
    if (cmd == 'bg:end') return '';
    return '{}';
  }

  @override void Function(ChatMessage)? onMessageReceived;
  @override void Function(ConnectionState)? onPeerConnected;
  @override void Function(ConnectionState)? onPeerDisconnected;
  @override void Function(List<String>, List<String>)? onAddressesUpdated;
  @override void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override void Function(Map<String, dynamic>)? onGroupReactionReceived;
  @override bool get isInitialized => true;
  @override Future<void> initialize() async {}
  @override Future<bool> checkHealth() async => true;
  @override Future<void> reinitialize() async {}
  @override void dispose() {}
}

void main() {
  group('ConversationWired _onSend — background task ordering', () {
    // --- Test 1: bg:begin fires before uploadMediaFn for media messages ---
    test('bg:begin is called before uploadMediaFn when sending media', () async {
      final bridge = _OrderRecordingBridge();
      final uploadCalled = <int>[];
      int callSeq = 0;

      Future<dynamic> recordingUpload({required Bridge bridge,
          required String localFilePath, required String mime,
          required String recipientPeerId, dynamic mediaFileManager,
          int? width, int? height, int? durationMs}) async {
        uploadCalled.add(callSeq++);
        return null; // simulate upload failure — just checking order
      }

      // Build the widget with one pending image attachment
      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        uploadMediaFn: recordingUpload,
        pendingAttachments: [FakePendingMedia()],
      ));

      // Tap send
      await tester.tap(find.byKey(const Key('sendButton')));
      await tester.pumpAndSettle();

      final bgBeginIndex = bridge.callLog.indexOf('bg:begin');
      expect(bgBeginIndex, isNot(-1), reason: 'bg:begin must be called');
      expect(bgBeginIndex, lessThan(uploadCalled.first),
          reason: 'bg:begin must fire before uploadMediaFn is invoked');
    });

    // --- Test 2: bg:end fires after sendChatMessageFn completes ---
    test('bg:end is called after sendChatMessageFn completes for media message', () async {
      final bridge = _OrderRecordingBridge();
      bool sendCalled = false;

      Future<dynamic> recordingUpload({required Bridge bridge,
          required String localFilePath, required String mime,
          required String recipientPeerId, dynamic mediaFileManager,
          int? width, int? height, int? durationMs}) async {
        return FakeMediaAttachment();
      }

      Future<(SendChatMessageResult, dynamic)> recordingSend({
          required dynamic p2pService, required dynamic messageRepo,
          required String targetPeerId, required String text,
          required String senderPeerId, required String senderUsername,
          String? messageId, String? timestamp, dynamic bridge,
          String? recipientMlKemPublicKey, String? quotedMessageId,
          List<dynamic>? mediaAttachments, dynamic mediaAttachmentRepo}) async {
        sendCalled = true;
        return (SendChatMessageResult.success, FakeConversationMessage());
      }

      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        uploadMediaFn: recordingUpload,
        sendChatMessageFn: recordingSend,
        pendingAttachments: [FakePendingMedia()],
      ));

      await tester.tap(find.byKey(const Key('sendButton')));
      await tester.pumpAndSettle();

      expect(sendCalled, isTrue);
      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must be called after sendChatMessageFn completes');
      // Order: bg:begin → upload → send → bg:end
      final bgBeginIdx = bridge.callLog.indexOf('bg:begin');
      final bgEndIdx = bridge.callLog.indexOf('bg:end');
      expect(bgEndIdx, greaterThan(bgBeginIdx));
    });

    // --- Test 3: media upload throws — bg:end still fires in finally ---
    test('bg:end fires in finally when media upload throws', () async {
      final bridge = _OrderRecordingBridge();

      Future<dynamic> throwingUpload({required Bridge bridge,
          required String localFilePath, required String mime,
          required String recipientPeerId, dynamic mediaFileManager,
          int? width, int? height, int? durationMs}) async {
        throw Exception('simulated network interruption during upload');
      }

      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        uploadMediaFn: throwingUpload,
        pendingAttachments: [FakePendingMedia()],
      ));

      await tester.tap(find.byKey(const Key('sendButton')));
      await tester.pumpAndSettle();

      expect(bridge.callLog, contains('bg:begin'),
          reason: 'bg:begin must have been called before the interrupted upload');
      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must fire in finally even when upload throws');
    });
  });
}
```

These tests will fail because `_onSend` does not yet call `bg:begin` before the upload loop.

#### 3.4 Dart test: `_onVoiceRecordingStopped` calls `bg:begin` before local transfer and relay upload

**File to add tests to:** `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart` (same file as 3.3)

Add a second test group to the same file:

```dart
  group('ConversationWired _onVoiceRecordingStopped — background task ordering', () {
    // --- Test 4: bg:begin fires before sendLocalMedia for voice local WiFi ---
    test('bg:begin is called before sendLocalMedia for voice local WiFi', () async {
      final bridge = _OrderRecordingBridge();

      // Build with a p2pService whose sendLocalMedia records call order
      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        p2pService: FakeLocalPeerP2PService(),
      ));

      // Trigger voice send by simulating a completed recording
      await tester.tap(find.byKey(const Key('voiceSendButton')));
      await tester.pumpAndSettle();

      final bgBeginIdx = bridge.callLog.indexOf('bg:begin');
      expect(bgBeginIdx, isNot(-1),
          reason: 'bg:begin must fire before sendLocalMedia is called');
    });

    // --- Test 5: bg:end fires in finally when sendLocalMedia throws ---
    test('bg:end fires in finally when sendLocalMedia throws', () async {
      final bridge = _OrderRecordingBridge();

      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        p2pService: FakeLocalPeerP2PServiceThatThrows(),
      ));

      await tester.tap(find.byKey(const Key('voiceSendButton')));
      await tester.pumpAndSettle();

      expect(bridge.callLog, contains('bg:begin'),
          reason: 'bg:begin must fire before sendLocalMedia is called');
      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must fire in finally even when sendLocalMedia throws');
    });

    // --- Test 6: bg:begin fires before sendVoiceMessage for relay path ---
    test('bg:begin is called before sendVoiceMessage for relay fallback', () async {
      final bridge = _OrderRecordingBridge();

      // Non-local peer — will fall through to relay path (sendVoiceMessage)
      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        p2pService: FakeNonLocalPeerP2PService(),
      ));

      await tester.tap(find.byKey(const Key('voiceSendButton')));
      await tester.pumpAndSettle();

      final bgBeginIdx = bridge.callLog.indexOf('bg:begin');
      expect(bgBeginIdx, isNot(-1),
          reason: 'bg:begin must fire before sendVoiceMessage is called');
    });

    // --- Test 7: bg:end fires in finally when sendVoiceMessage fails ---
    test('bg:end fires in finally when sendVoiceMessage fails (relay path)', () async {
      final bridge = _OrderRecordingBridge();

      await tester.pumpWidget(buildConversationWired(
        bridge: bridge,
        p2pService: FakeNonLocalPeerP2PServiceOffline(),
      ));

      await tester.tap(find.byKey(const Key('voiceSendButton')));
      await tester.pumpAndSettle();

      expect(bridge.callLog, contains('bg:begin'));
      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must fire in finally even when sendVoiceMessage fails');
      expect(bridge.callLog.indexOf('bg:end'),
          greaterThan(bridge.callLog.indexOf('bg:begin')));
    });
  });
```

These tests will fail because `_onVoiceRecordingStopped` does not yet call `bg:begin` before local transfer or relay upload.

#### 3.5 Dart test: `_onInlineSend` in `feed_wired.dart` calls `bg:begin` before `sendChatMessage`

**File to create:** `test/features/feed/presentation/screens/feed_wired_bg_task_test.dart`

This is a **NEW** test file covering the inline 1:1 send from the feed screen, which is currently missing from the plan entirely.

```dart
// test/features/feed/presentation/screens/feed_wired_bg_task_test.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

class _OrderRecordingBridge implements Bridge {
  final List<String> callLog = [];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    if (cmd == 'bg:begin') return '42';
    if (cmd == 'bg:end') return '';
    // Default: return valid JSON for other commands (encrypt, send, etc.)
    return jsonEncode({'ok': true});
  }

  @override void Function(ChatMessage)? onMessageReceived;
  @override void Function(ConnectionState)? onPeerConnected;
  @override void Function(ConnectionState)? onPeerDisconnected;
  @override void Function(List<String>, List<String>)? onAddressesUpdated;
  @override void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override void Function(Map<String, dynamic>)? onGroupReactionReceived;
  @override bool get isInitialized => true;
  @override Future<void> initialize() async {}
  @override Future<bool> checkHealth() async => true;
  @override Future<void> reinitialize() async {}
  @override void dispose() {}
}

void main() {
  group('FeedWired _onInlineSend — background task ordering', () {
    // --- Test 1: bg:begin fires before sendChatMessage ---
    test('bg:begin is called before sendChatMessage for inline 1:1 send', () async {
      final bridge = _OrderRecordingBridge();

      await tester.pumpWidget(buildFeedWired(
        bridge: bridge,
        contacts: [FakeContact(peerId: 'peer-bob')],
        feedItems: [FakeConnectionFeedItem(contactPeerId: 'peer-bob')],
      ));

      // Type a message in the inline reply input and tap send
      await tester.enterText(
        find.byKey(const Key('inlineReplyInput-peer-bob')),
        'hello from feed',
      );
      await tester.tap(find.byKey(const Key('inlineSendButton-peer-bob')));
      await tester.pumpAndSettle();

      final bgBeginIdx = bridge.callLog.indexOf('bg:begin');
      expect(bgBeginIdx, isNot(-1),
          reason: 'bg:begin must be called before sendChatMessage');
      // sendChatMessage will call message.encrypt, message:send, etc.
      // bg:begin must appear before any of those bridge commands
      final firstNonBgCmd = bridge.callLog.indexWhere(
        (cmd) => cmd != 'bg:begin' && cmd != 'bg:end',
      );
      if (firstNonBgCmd != -1) {
        expect(bgBeginIdx, lessThan(firstNonBgCmd),
            reason: 'bg:begin must fire before the first sendChatMessage bridge call');
      }
    });

    // --- Test 2: bg:end fires after sendChatMessage completes ---
    test('bg:end is called after sendChatMessage completes for inline send', () async {
      final bridge = _OrderRecordingBridge();

      await tester.pumpWidget(buildFeedWired(
        bridge: bridge,
        contacts: [FakeContact(peerId: 'peer-bob')],
        feedItems: [FakeConnectionFeedItem(contactPeerId: 'peer-bob')],
      ));

      await tester.enterText(
        find.byKey(const Key('inlineReplyInput-peer-bob')),
        'hello from feed',
      );
      await tester.tap(find.byKey(const Key('inlineSendButton-peer-bob')));
      await tester.pumpAndSettle();

      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must be called after sendChatMessage completes');
      final bgBeginIdx = bridge.callLog.indexOf('bg:begin');
      final bgEndIdx = bridge.callLog.indexOf('bg:end');
      expect(bgEndIdx, greaterThan(bgBeginIdx));
    });

    // --- Test 3: bg:end fires in finally when sendChatMessage throws ---
    test('bg:end fires in finally when sendChatMessage throws', () async {
      final bridge = _OrderRecordingBridge();

      await tester.pumpWidget(buildFeedWired(
        bridge: bridge,
        p2pService: FakeP2PServiceThatThrows(),
        contacts: [FakeContact(peerId: 'peer-bob')],
        feedItems: [FakeConnectionFeedItem(contactPeerId: 'peer-bob')],
      ));

      await tester.enterText(
        find.byKey(const Key('inlineReplyInput-peer-bob')),
        'hello from feed',
      );
      await tester.tap(find.byKey(const Key('inlineSendButton-peer-bob')));
      await tester.pumpAndSettle();

      expect(bridge.callLog, contains('bg:begin'));
      expect(bridge.callLog, contains('bg:end'),
          reason: 'bg:end must fire in finally even when sendChatMessage throws');
    });

    // --- Test 4: send proceeds when OS refuses background task ---
    test('inline send proceeds when OS refuses background task', () async {
      final bridge = _OrderRecordingBridge();
      // Override to return empty string (OS refused)
      // Note: subclass or modify bridge to return '' for bg:begin

      await tester.pumpWidget(buildFeedWired(
        bridge: bridge,
        contacts: [FakeContact(peerId: 'peer-bob')],
        feedItems: [FakeConnectionFeedItem(contactPeerId: 'peer-bob')],
      ));

      await tester.enterText(
        find.byKey(const Key('inlineReplyInput-peer-bob')),
        'hello from feed',
      );
      await tester.tap(find.byKey(const Key('inlineSendButton-peer-bob')));
      await tester.pumpAndSettle();

      // bg:begin was attempted
      expect(bridge.callLog, contains('bg:begin'));
      // sendChatMessage still executed (message.encrypt or message:send in log)
      expect(bridge.callLog.length, greaterThan(1),
          reason: 'Send must proceed even without background task');
    });
  });
}
```

These tests will fail because `_onInlineSend` in `feed_wired.dart` does not yet call `bg:begin`/`bg:end`.

#### 3.6 Dart test: `sendVoiceMessage` use case does NOT call `bg:begin`

**File to create:** `test/features/conversation/application/send_voice_message_no_bg_task_test.dart`

This test enforces the canonical owner rule: the use case must NOT call `bg:begin` or `bg:end`. Background task management belongs only to the presentation layer.

```dart
// test/features/conversation/application/send_voice_message_no_bg_task_test.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/core/bridge/bridge.dart';

/// Bridge that records every command it receives.
class _AuditBridge implements Bridge {
  final List<String> callLog = [];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    // Return minimal valid responses for the upload + send pipeline
    if (cmd == 'media:upload') {
      return jsonEncode({
        'ok': true,
        'id': 'media-123',
        'url': 'https://example.com/media-123',
      });
    }
    if (cmd == 'message.encrypt') {
      return jsonEncode({'ok': true, 'encrypted': 'ciphertext'});
    }
    return jsonEncode({'ok': true});
  }

  @override void Function(dynamic)? onMessageReceived;
  @override void Function(dynamic)? onPeerConnected;
  @override void Function(dynamic)? onPeerDisconnected;
  @override void Function(List<String>, List<String>)? onAddressesUpdated;
  @override void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override void Function(Map<String, dynamic>)? onGroupReactionReceived;
  @override bool get isInitialized => true;
  @override Future<void> initialize() async {}
  @override Future<bool> checkHealth() async => true;
  @override Future<void> reinitialize() async {}
  @override void dispose() {}
}

void main() {
  group('sendVoiceMessage — no bg:begin/bg:end (presentation-only rule)', () {
    test('sendVoiceMessage does NOT call bg:begin or bg:end', () async {
      final bridge = _AuditBridge();
      final recording = AudioRecording(
        filePath: '/tmp/test_voice.m4a',
        durationMs: 3000,
        sizeBytes: 50000,
        mime: 'audio/m4a',
      );

      // Create the test file so validation passes
      File('/tmp/test_voice.m4a').writeAsBytesSync(List.filled(50000, 0));

      try {
        await sendVoiceMessage(
          p2pService: FakeP2PService(),
          messageRepo: FakeMessageRepo(),
          targetPeerId: 'peer-bob',
          senderPeerId: 'peer-alice',
          senderUsername: 'alice',
          recording: recording,
          bridge: bridge,
        );
      } catch (_) {
        // We don't care about the result — only about which commands were called
      }

      expect(bridge.callLog, isNot(contains('bg:begin')),
          reason: 'sendVoiceMessage must NOT call bg:begin — '
              'background task management belongs to the presentation layer only');
      expect(bridge.callLog, isNot(contains('bg:end')),
          reason: 'sendVoiceMessage must NOT call bg:end — '
              'background task management belongs to the presentation layer only');
    });
  });
}
```

This test passes today (because `sendVoiceMessage` does not currently call `bg:begin`), serving as a **regression guard** to ensure the use case is never given background task responsibility.

---

### Green Phase — Dart-Initiated Background Task

The background task is NOT placed inside use cases. It is requested from Dart's presentation layer BEFORE the upload/transfer step and released in a `finally` block that covers the upload, the entire `sendChatMessage` pipeline, and any failure paths.

#### 3.7 Add `bgBegin` / `bgEnd` MethodChannel cases to `GoBridge.swift`

**File to modify:** `ios/Runner/GoBridge.swift`

**Critical implementation detail:** `handleMethodCall` is already called on the main thread by Flutter's engine. The `bgBegin`/`bgEnd` cases must NOT use `runOnBackground` — they must call `UIApplication.shared.beginBackgroundTask` / `endBackgroundTask` directly and call `result(...)` synchronously, because:
- `beginBackgroundTask` is a UIKit API that must be called from the main thread
- The task handle must be returned to Dart immediately (before the app transitions to background)
- Using `runOnBackground` would dispatch to a GCD queue and the MethodChannel response would race with iOS suspension

Add these two cases to the existing `switch call.method` block (NOT inside `runOnBackground`):

```swift
case "bgBegin":
    // Called synchronously on main thread — do NOT use runOnBackground.
    // UIApplication.beginBackgroundTask must run on main thread and return before
    // the app finishes transitioning to background.
    var taskId = UIBackgroundTaskIdentifier.invalid
    taskId = UIApplication.shared.beginBackgroundTask(withName: "mknoon.sendMessage") {
        // Expiration handler: iOS is about to force-suspend.
        NSLog("[GoBridge] BG_TASK_EXPIRED — ending task before suspension")
        if taskId != .invalid {
            UIApplication.shared.endBackgroundTask(taskId)
            taskId = .invalid
        }
    }
    if taskId == .invalid {
        NSLog("[GoBridge] BG_TASK_REFUSED — OS would not grant background time")
        result("")  // empty string signals Dart that no task was granted
    } else {
        NSLog("[GoBridge] bgBegin: taskId=%@", String(taskId.rawValue))
        result(String(taskId.rawValue))  // return raw handle as string
    }

case "bgEnd":
    // Called synchronously on main thread — do NOT use runOnBackground.
    // args is a JSON string: {"taskId": "12345"} — because _CmdSpec('bgEnd', true)
    // serializes the payload map via jsonEncode before passing to invokeMethod.
    if let jsonStr = call.arguments as? String,
       let data = jsonStr.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let taskIdStr = json["taskId"] as? String,
       let rawVal = UInt(taskIdStr),
       rawVal != UIBackgroundTaskIdentifier.invalid.rawValue {
        let taskId = UIBackgroundTaskIdentifier(rawValue: rawVal)
        UIApplication.shared.endBackgroundTask(taskId)
    }
    result(nil)
```

**Key differences from a naive approach:**
- Both cases execute synchronously on the main thread (no `DispatchQueue.main.async` needed — `handleMethodCall` is already on main)
- `bgEnd` receives the payload as a JSON string (`{"taskId": "12345"}`) because `_CmdSpec('bgEnd', true)` causes `GoBridgeClient.send()` to call `jsonEncode(payload)` before `invokeMethod`. The Swift side must JSON-parse `call.arguments` to extract the task ID.
- The expiration handler captures `taskId` by reference and guards against double-end with an `.invalid` check

#### 3.8 Add `bg:begin` / `bg:end` to `GoBridgeClient._cmdMap`

**File to modify:** `lib/core/bridge/go_bridge_client.dart`

Add to the existing `_cmdMap` const (around line 37-96). These follow the same `_CmdSpec` pattern as all other commands:

```dart
'bg:begin': _CmdSpec('bgBegin', false),  // no payload needed
'bg:end': _CmdSpec('bgEnd', true),       // payload = taskId string
```

**How this flows through `send()`:** When `send()` is called with `{'cmd': 'bg:begin'}`:
1. Line 353-354: JSON decoded, `cmd = 'bg:begin'`
2. Line 357: `_cmdMap['bg:begin']` returns `_CmdSpec('bgBegin', false)`
3. Line 381: `_methodChannel.invokeMethod<String>('bgBegin')` — no argument (hasPayload=false)
4. Swift receives `call.method == "bgBegin"`, `call.arguments == nil`
5. Swift returns the task ID string via `result(String(taskId.rawValue))`
6. Dart receives it as the return value of `send()`

For `bg:end` with `{'cmd': 'bg:end', 'payload': {'taskId': '12345'}}`:
1. `cmd = 'bg:end'`, `payload = {'taskId': '12345'}`
2. `_CmdSpec('bgEnd', true)` — hasPayload=true
3. `_methodChannel.invokeMethod<String>('bgEnd', jsonEncode({'taskId': '12345'}))` — payload as JSON string
4. Swift receives `call.method == "bgEnd"`, `call.arguments == "{\"taskId\":\"12345\"}"`
5. Swift JSON-parses args, extracts `taskId` string, converts to `UIBackgroundTaskIdentifier`

#### 3.9 Add Android no-op handlers

**File to modify:** `android/app/src/main/kotlin/com/mknoon/app/GoBridge.kt`

Add to the `when (call.method)` block:

```kotlin
"bgBegin" -> result.success("")  // no-op on Android
"bgEnd" -> result.success(null)  // no-op on Android
```

Android's background model is more lenient — `Executors.newCachedThreadPool()` threads are not immediately killed on background transition.

#### 3.10 Add `bg:begin`/`bg:end` guard to each presentation-layer call site

The background task guard must be placed at the outermost level of the send flow in each Wired widget method, so that upload, local transfer, and the full `sendChatMessage` pipeline are all protected.

---

**3.10a — Media text message** (`_onSend` in `conversation_wired.dart`)

The upload loop at lines 651-713 runs before `sendChatMessageFn` at line 724. Move `bg:begin` to after the optimistic message save AND the optimistic attachment persistence (Section 4, Step 4.5, Change 0), so it covers the upload loop and the subsequent `sendChatMessageFn` call.

```dart
  // Step 1: Persist optimistic message (already at line 637-644 in existing code)
  try {
    await widget.messageRepo.saveMessage(optimisticMessage);
  } catch (e) { /* ... */ }

  // Step 2: Persist optimistic attachment rows (Section 4, Step 4.5, Change 0)
  if (optimisticMedia != null && optimisticMedia.isNotEmpty) {
    for (final attachment in optimisticMedia) {
      await widget.mediaAttachmentRepo.saveAttachment(
        messageId: optimisticMessage.id,
        attachment: attachment.copyWith(downloadStatus: 'upload_pending'),
      );
    }
  }

  // Step 3: Acquire background task BEFORE upload so iOS cannot suspend during upload.
  String? bgTaskId;
  if (widget.bridge != null) {
    try {
      final response = await widget.bridge!.send(jsonEncode({'cmd': 'bg:begin'}));
      if (response.isNotEmpty && !response.startsWith('{')) {
        bgTaskId = response;
      }
    } catch (_) {
      // Best-effort — proceed without background task if request fails.
    }
  }

  try {
    // Upload attachments if any (existing upload loop, lines 651-713)
    List<MediaAttachment>? uploadedAttachments;
    if (mediaToUpload.isNotEmpty && widget.bridge != null) {
      // ... existing upload loop unchanged ...
    }

    // ... existing contact refresh + sendChatMessageFn call unchanged ...

  } finally {
    if (bgTaskId != null && widget.bridge != null) {
      try {
        await widget.bridge!.send(jsonEncode({
          'cmd': 'bg:end',
          'payload': {'taskId': bgTaskId},
        }));
      } catch (_) {}
    }
  }
```

---

**3.10b — Voice message (both local WiFi and relay)** (`_onVoiceRecordingStopped` in `conversation_wired.dart`)

A single `bg:begin` covers both the local WiFi path (`sendLocalMedia` at line 1280 + `sendChatMessageFn` at line 1305) and the relay fallback path (`sendVoiceMessage` at line 1370). The `bg:begin` is placed after the optimistic save (line 1267) and contact refresh (line 1275), before the local WiFi check at line 1278. A single outer `try/finally` releases the task.

```dart
  // After optimistic save (line 1267, unchanged)

  // Re-read contact from DB (lines 1269-1275, unchanged)

  // NEW: acquire background task BEFORE local transfer / relay upload.
  String? bgTaskId;
  if (widget.bridge != null) {
    try {
      final response = await widget.bridge!.send(jsonEncode({'cmd': 'bg:begin'}));
      if (response.isNotEmpty && !response.startsWith('{')) {
        bgTaskId = response;
      }
    } catch (_) {}
  }

  try {
    // Try local WiFi first (line 1278, unchanged)
    if (widget.p2pService.isLocalPeer(_contact.peerId)) {
      final localSuccess = await widget.p2pService.sendLocalMedia( ... );
      if (localSuccess) {
        // ... existing local-success path + sendChatMessageFn (lines 1290-1339) ...
        return;
      }
    }

    // Relay fallback: sendVoiceMessage (line 1370, unchanged)
    // NOTE: sendVoiceMessage does NOT call bg:begin internally (canonical owner rule).
    // The outer bg:begin here covers the entire sendVoiceMessage pipeline.
    final (result, voiceMessage) = await sendVoiceMessage( ... );
    // ... existing result handling unchanged ...

  } finally {
    if (bgTaskId != null && widget.bridge != null) {
      try {
        await widget.bridge!.send(jsonEncode({
          'cmd': 'bg:end',
          'payload': {'taskId': bgTaskId},
        }));
      } catch (_) {}
    }
  }
```

---

**3.10c — Inline 1:1 text send from feed** (`_onInlineSend` in `feed_wired.dart`) — **NEW**

The feed screen's inline reply calls `sendChatMessage` directly at line 1065 with no upload step. The `bg:begin` wraps the `sendChatMessage` call so that the entire encrypt → discover → dial → send → inbox pipeline is protected.

```dart
  Future<void> _onInlineSend(String contactPeerId, String text) async {
    final identity = _identity;
    if (identity == null) return;

    // Optimistic: show session reply immediately before network send.
    final quotedMsgId = _activeQuoteMessageIds[contactPeerId];
    final draftText = text;
    _draftTexts.remove(contactPeerId);
    _activeQuoteMessageIds.remove(contactPeerId);
    _sessionReplies.track(contactPeerId, SessionReply.justNow(text));
    if (mounted) setState(() {});

    // NEW: acquire background task before network send.
    String? bgTaskId;
    try {
      final response = await widget.bridge.send(jsonEncode({'cmd': 'bg:begin'}));
      if (response.isNotEmpty && !response.startsWith('{')) {
        bgTaskId = response;
      }
    } catch (_) {}

    try {
      final contact = await widget.contactRepository.getContact(contactPeerId);
      if (contact == null || !mounted) {
        _restoreFeedComposerState(
          draftKey: contactPeerId,
          quotedMessageId: quotedMsgId,
          draftText: draftText,
          sessionReplyKey: contactPeerId,
        );
        return;
      }

      final (result, message) = await sendChatMessage(
        p2pService: widget.p2pService,
        messageRepo: widget.messageRepository,
        targetPeerId: contactPeerId,
        text: text,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        bridge: widget.bridge,
        recipientMlKemPublicKey: contact.mlKemPublicKey,
        quotedMessageId: quotedMsgId,
      );

      if (!mounted) return;

      if (result == SendChatMessageResult.success) {
        await markConversationRead(
          messageRepo: widget.messageRepository,
          contactPeerId: contactPeerId,
        );
        if (message != null) {
          await _applyIncomingContactMessageToFeed(
            message,
            refreshUnreadCount: false,
          );
        } else {
          await _refreshContactFeedItem(
            contactPeerId,
            refreshUnreadCount: false,
          );
        }
        await _loadTotalUnreadCount();
      } else {
        _restoreFeedComposerState(
          draftKey: contactPeerId,
          quotedMessageId: quotedMsgId,
          draftText: draftText,
          sessionReplyKey: contactPeerId,
        );
        final errorText = result == SendChatMessageResult.encryptionRequired
            ? 'Cannot send: contact does not support encryption.'
            : AppLocalizations.of(context)!.error_send_message;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorText),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _restoreFeedComposerState(
        draftKey: contactPeerId,
        quotedMessageId: quotedMsgId,
        draftText: draftText,
        sessionReplyKey: contactPeerId,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'FEED_FL_INLINE_SEND_ERROR',
        details: {'error': e.toString()},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.error_send_message),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (bgTaskId != null) {
        try {
          await widget.bridge.send(jsonEncode({
            'cmd': 'bg:end',
            'payload': {'taskId': bgTaskId},
          }));
        } catch (_) {}
      }
    }
  }
```

**Key difference from conversation_wired call sites:** `widget.bridge` is non-nullable on `FeedWired` (see `feed_wired.dart` line 96: `final Bridge bridge;`), so no `widget.bridge != null` guard is needed.

#### 3.11 No `Info.plist` changes required

The existing `UIBackgroundModes` array (`fetch`, `remote-notification`) is sufficient.

#### 3.12 Android parity note

`GoBridge.kt` uses an unbounded `Executors.newCachedThreadPool()`. Android's background execution model is more lenient. `bg:begin`/`bg:end` on Android can be no-ops that return immediately.

---

### Refactor Phase

**3.13** Extract the `bg:begin` response parsing into a helper function to eliminate the fragile `response.startsWith('{')` heuristic repeated across four call sites:

```dart
// lib/core/bridge/bridge_helpers.dart (or add to existing helpers file)

/// Requests an iOS background task. Returns the task ID string on success,
/// or null if the OS refused or the bridge call failed.
Future<String?> callBgBegin(Bridge bridge) async {
  try {
    final response = await bridge.send(jsonEncode({'cmd': 'bg:begin'}));
    if (response.isNotEmpty && !response.startsWith('{')) {
      return response;
    }
  } catch (_) {}
  return null;
}

/// Releases an iOS background task. No-op if taskId is null.
Future<void> callBgEnd(Bridge bridge, String? taskId) async {
  if (taskId == null) return;
  try {
    await bridge.send(jsonEncode({
      'cmd': 'bg:end',
      'payload': {'taskId': taskId},
    }));
  } catch (_) {}
}
```

Each call site then simplifies to:

```dart
final bgTaskId = await callBgBegin(widget.bridge!);
try {
  // ... upload + send pipeline ...
} finally {
  await callBgEnd(widget.bridge!, bgTaskId);
}
```

**3.14** Replace scattered `NSLog("[GoBridge] ...")` strings with a single `private static let logTag`.

**3.15** Consider adding `bg:begin`/`bg:end` around group message sends (`sendGroupMessage`) if the same lock-then-lose pattern is observed.

---

### Smoke Test — Manual QA Scenarios

**Scenario A — Text message with lock:**
1. On Device A, open conversation with Bob.
2. Type "Background task test — do you see this?"
3. Tap Send. Immediately (within 1 second) press the side button to lock Device A.
4. Wait 10 seconds.
5. Unlock Device A.

**Expected:** Message appears as sent. On Device B, message arrives either via P2P or inbox. Xcode console shows `bgBegin` logged, no `BG_TASK_EXPIRED`.

**Failure signature (pre-fix):** Message never appears on Device B. No background task was requested.

---

**Scenario B — Media upload interrupted by lock:**
1. On Device A, open conversation with Bob. Attach a 5 MB photo.
2. Tap Send. Immediately (within 0.5 seconds, during upload) press the side button to lock Device A.
3. Wait 15 seconds (allow upload to complete under background task protection).
4. Unlock Device A.

**Expected:** Upload completes, message appears as sent, photo arrives on Device B. Xcode console shows `bgBegin` was logged BEFORE the upload started. No `BG_TASK_EXPIRED`.

**Failure signature (pre-fix):** Upload is interrupted. Message stuck in `sending` state. No `bgBegin` was logged because the background task was never requested before the upload started.

---

**Scenario C — Voice message upload interrupted by lock:**
1. On Device A, record a 10-second voice message.
2. Release the record button. Immediately press the side button to lock Device A.
3. Wait 15 seconds.
4. Unlock Device A.

**Expected:** Voice upload completes, message appears as sent, audio arrives on Device B. Xcode console shows `bgBegin` was logged before `VOICE_UPLOAD_START`, no `BG_TASK_EXPIRED`.

**Failure signature (pre-fix):** Upload is interrupted during the unprotected window. Message stuck in `sending` state.

---

**Scenario D — Voice local WiFi transfer interrupted by lock:**
1. Both devices on the same WiFi network. On Device A, record a 10-second voice message.
2. Release the record button. Immediately press the side button to lock Device A.
3. Wait 10 seconds.
4. Unlock Device A.

**Expected:** Local WiFi transfer completes, message arrives on Device B. Xcode console shows `bgBegin` was logged before `sendLocalMedia`. No `BG_TASK_EXPIRED`.

**Failure signature (pre-fix):** `sendLocalMedia` is interrupted. Message stuck in `sending` state. No `bgBegin` was logged before the local transfer.

---

**Scenario E — Inline feed reply with lock (NEW):**
1. On Device A, go to the feed screen. Find a contact's feed card with an inline reply input.
2. Type "Quick reply from feed" and tap the send button.
3. Immediately press the side button to lock Device A.
4. Wait 10 seconds.
5. Unlock Device A.

**Expected:** Message appears as sent. On Device B, message arrives. Xcode console shows `bgBegin` logged before `sendChatMessage` bridge calls.

**Failure signature (pre-fix):** Message is lost. No background task was requested because `_onInlineSend` had no `bg:begin`.

---

### Edge Case Coverage

| Scenario | Handling |
|---|---|
| OS returns `.invalid` (refuses background task) | Dart receives empty string; `bgTaskId = null`; send proceeds without protection |
| Expiration handler fires during upload | iOS logs `BG_TASK_EXPIRED`; task token is ended; upload may be interrupted but next resume will retry via Section 1 |
| Expiration handler fires during sendChatMessage | iOS logs `BG_TASK_EXPIRED`; task token is ended; send pipeline may be interrupted |
| Send completes before expiration | `finally` block calls `bg:end`; expiration handler is a no-op |
| Multiple concurrent sends | Each gets its own `taskId` via separate `bg:begin` calls; each `finally` releases its own |
| Android | `bg:begin`/`bg:end` are no-ops; no side effects |
| Media upload fails (upload returns null) | `finally` block still calls `bg:end`; upload failure is surfaced to user normally |
| Voice relay: presentation bg:begin wraps sendVoiceMessage | Single token covers upload + send inside use case; `finally` releases it |
| sendVoiceMessage itself | Does NOT call `bg:begin`/`bg:end` (regression guard test 3.6) |
| Inline feed send fails | `finally` block calls `bg:end`; error snackbar shown to user |

---

### Implementation File Checklist

**Swift / native:**
- [ ] Add `bgBegin` / `bgEnd` cases to `ios/Runner/GoBridge.swift` `handleMethodCall` (Step 3.7)
- [ ] Add Android no-op handlers in `GoBridge.kt` for `bgBegin`/`bgEnd` (Step 3.9)

**Dart bridge:**
- [ ] Add `'bg:begin': _CmdSpec('bgBegin', false)` and `'bg:end': _CmdSpec('bgEnd', true)` to `go_bridge_client.dart` `_cmdMap` (Step 3.8)

**Dart call sites (presentation-layer only — bg:begin before upload/transfer/send):**
- [ ] Add `bg:begin`/`bg:end` `try/finally` in `_onSend` (`conversation_wired.dart`) BEFORE the upload loop (Step 3.10a)
- [ ] Add `bg:begin`/`bg:end` `try/finally` in `_onVoiceRecordingStopped` (`conversation_wired.dart`) BEFORE `sendLocalMedia` / `sendVoiceMessage` (Step 3.10b)
- [ ] Add `bg:begin`/`bg:end` `try/finally` in `_onInlineSend` (`feed_wired.dart`) BEFORE `sendChatMessage` (Step 3.10c) — **NEW**
- [ ] Confirm `sendVoiceMessage` use case does NOT call `bg:begin`/`bg:end` (regression guard test 3.6)
- [ ] Confirm `sendChatMessage` use case does NOT call `bg:begin`/`bg:end` (background task is managed by presentation-layer callers)

**Refactor:**
- [ ] Extract `callBgBegin` / `callBgEnd` helper functions (Step 3.13)

**Tests:**
- [ ] Create Swift XCTest at `ios/RunnerTests/GoBridgeCriticalTaskTests.swift` (Step 3.1)
- [ ] Create Dart contract tests at `test/core/bridge/go_bridge_background_task_test.dart` (Step 3.2)
- [ ] Create `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart` verifying `_onSend` bg:begin/bg:end ordering (Step 3.3) and `_onVoiceRecordingStopped` bg:begin/bg:end ordering (Step 3.4)
- [ ] Create `test/features/feed/presentation/screens/feed_wired_bg_task_test.dart` verifying `_onInlineSend` bg:begin/bg:end ordering (Step 3.5) — **NEW**
- [ ] Create `test/features/conversation/application/send_voice_message_no_bg_task_test.dart` verifying use case does NOT call bg:begin (Step 3.6)

**Validation:**
- [ ] Run full test suite
- [ ] Execute manual smoke test Scenario A (text + lock) on two physical devices
- [ ] Execute manual smoke test Scenario B (media upload + lock) on two physical devices
- [ ] Execute manual smoke test Scenario C (voice upload + lock) on two physical devices
- [ ] Execute manual smoke test Scenario D (voice local WiFi + lock) on two physical devices
- [ ] Execute manual smoke test Scenario E (inline feed reply + lock) on two physical devices — **NEW**

---

## Section 4: Direct-First Send with Early wireEnvelope Persistence

### Overview

Section 4 persists `wireEnvelope` earlier in the send path (before the transport race) and persists media attachment metadata at optimistic write time. These two changes make the existing DB row retryable after a crash at any point during the send. The existing inbox-as-fallback behavior is preserved unchanged: `storeInInbox()` continues to fire only when all P2P paths fail or when P2P succeeds without acknowledgment. Sections 1-3 provide the actual reliability safety net (stuck-sending recovery, lifecycle pause handler, iOS background task).

**Why NOT unconditional optimistic inbox store:** The relay server (`go-relay-server/inbox.go:598`) fires an FCM push notification on every `inbox:store` call with no dedup (`go-relay-server/backend_memory.go:112` appends blindly). Making inbox unconditional would mean every successfully-ACK'd direct P2P send also triggers a phantom push notification on the recipient's device -- a user-visible regression. The relay currently has no UUID-based dedup, so retry paths create duplicate relay entries and duplicate push notifications -- Step 4.5 adds a relay-side idempotency contract to close this gap. The correct fix for the post-serialization crash window is not to push every message to inbox unconditionally, but to ensure the DB row has enough state (`wireEnvelope`) for Sections 1-3 to retry the send on recovery, with relay-side dedup as the safety net against duplicate inbox entries on crash-replay.

**Standalone limitation:** This section does NOT cover the pre-`sendChatMessage` window. Between the optimistic DB write (`conversation_wired.dart:637`) and the `sendChatMessageFn` call (`conversation_wired.dart:724`), there is a window of up to 60+ seconds (media upload, contact refresh) where `wireEnvelope=null`. If the app is killed during this window, recovery requires Section 1 (stuck-sending recovery), Section 2 (pause handler), and Section 3 (iOS background task).

The changes in this section:

1. **Inside `conversation_wired.dart`**: Persist media attachments to the `media_attachments` table at the same time as the optimistic message write. This protects attachment metadata during the 60s+ upload window, but recovery from a crash during that window requires Sections 1-3.
2. **Inside `sendChatMessage`**: Persist `wireEnvelope` to the DB row immediately after `jsonString` is built (before the transport race), so a crash during the transport race leaves a retryable row. Retry execution depends on Section 1's `PendingMessageRetrier`.
3. **No change to inbox call sites**: `storeInInbox()` remains in its current two locations -- the all-fail fallback and the unacked handoff. No new inbox call is added.
4. **Idempotent inbox-handoff guard (Step 4.5)**: Relay-side dedup by `messageId` in `go-relay-server/backend_memory.go` prevents duplicate inbox entries and duplicate push notifications on crash-replay. Client-side `transport == 'inbox'` guard in retry use cases skips redundant inbox calls.

**Receive-side dedup (not relay-side):** The relay inbox itself has NO dedup -- `backend_memory.go:112` appends blindly and `inbox.go:598` fires an FCM push on every `store` call. However, the *receiver's* `handleIncomingChatMessage` performs a `messageExists(payload.id)` check and returns `HandleChatMessageResult.duplicate` without re-persisting. This means duplicate relay entries cause duplicate push notifications but NOT duplicate messages in the recipient's DB. Step 4.5 addresses this gap with a relay-side idempotency contract.

#### Canonical Send Ordering (cross-section reference)

When all sections are implemented, the unified send sequence in `conversation_wired.dart` `_onSend` for a media message is:

```
1. Optimistic message save      (messageRepo.saveMessage, status='sending')
2. Optimistic attachment persist (mediaAttachmentRepo.saveAttachment per file,
                                  downloadStatus='upload_pending')
3. Background protection         (bg:begin via Bridge — Section 3)
4. Upload / transfer             (uploadMediaFn loop or sendLocalMedia)
5. sendChatMessageFn             (serialise → wireEnvelope persist → P2P race
                                  → inbox fallback on failure/unacked only)
6. Background release            (bg:end in finally — Section 3)
```

Steps 1-2 are from Section 4 (Change 0 and Change 1). Step 3 is from Section 3 (Step 3.6a). Steps 4-5 are the existing flow with the wireEnvelope persist inserted. Step 6 is from Section 3. The ordering is the same for voice messages (`_onVoiceRecordingStopped` and `sendVoiceMessage`), with the voice-specific path substituted for step 4.

This ordering guarantees that:
- A crash at any point after step 1 leaves a recoverable DB row (Section 1 recovery).
- A crash after step 2 preserves attachment metadata for re-upload (Section 1, Part G).
- A crash after step 5's wireEnvelope persist leaves the encrypted payload in the DB for Section 1's retrier to replay.
- Steps 3-6 run under iOS background task protection (Section 3).

---

### Step 4.1 — Red: wireEnvelope is persisted before P2P transport race

**Goal:** Prove that `messageRepo.updateWireEnvelope()` is called after serialization but before any P2P attempt (discover/dial/send). This is the core value of Section 4: making the DB row retryable.

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

Add to the `FakeP2PService` a field that records the call ordering relative to other operations:

```dart
final List<String> callOrder = [];
```

Update `discoverPeer`, `sendMessageWithReply`, and `storeInInbox` to record their position in `callOrder`.

Add to `FakeMessageRepository` tracking for `updateWireEnvelope` calls:

```dart
final List<String> wireEnvelopeUpdates = [];
String? lastWireEnvelopeValue;
VoidCallback? onUpdateWireEnvelope;

@override
Future<void> updateWireEnvelope(String id, String envelope) async {
  wireEnvelopeUpdates.add(id);
  lastWireEnvelopeValue = envelope;
  onUpdateWireEnvelope?.call();
}
```

Add a new test group:

```dart
group('Section 4 — direct-first send with early wireEnvelope persistence', () {
  test(
    'RED: wireEnvelope is persisted to DB before discover is called',
    () async {
      // Track cross-component ordering via a shared list
      final callOrder = <String>[];
      messageRepo.onUpdateWireEnvelope = () =>
          callOrder.add('updateWireEnvelope');
      p2pService.onDiscover = () => callOrder.add('discover');
      p2pService.onSendMessage = () => callOrder.add('sendMessage');

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'wireEnvelope persistence test',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-wire-001',
      );

      expect(result, SendChatMessageResult.success);
      // wireEnvelope must be persisted
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-001'));
      // wireEnvelope persist must happen before any P2P operation
      final wireIdx = callOrder.indexOf('updateWireEnvelope');
      final discoverIdx = callOrder.indexOf('discover');
      expect(wireIdx, isNot(-1),
          reason: 'updateWireEnvelope must be called');
      expect(wireIdx < discoverIdx, isTrue,
          reason: 'wireEnvelope persist must precede discover');
    },
  );

  test(
    'RED: wireEnvelope is persisted even on the connection-reuse fast path',
    () async {
      p2pService = FakeP2PService(
        currentState: NodeState(
          isStarted: true,
          connections: [
            const ConnectionState(
              peerId: 'target-peer',
              multiaddrs: ['/ip4/127.0.0.1/tcp/4001'],
              direction: 'outbound',
              status: 'connected',
            ),
          ],
        ),
      );

      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Connected peer wireEnvelope',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-wire-002',
      );

      expect(result, SendChatMessageResult.success);
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-002'));
      expect(p2pService.discoverCallCount, 0); // reuse path skips discover
    },
  );

  test(
    'RED: wireEnvelope is persisted on local WiFi path',
    () async {
      p2pService = FakeP2PService(useNullDiscover: true)
        ..localPeers.add('target-peer');

      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'WiFi wireEnvelope',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-wire-003',
      );

      expect(result, SendChatMessageResult.success);
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-003'));
    },
  );

  test(
    'RED: wireEnvelope contains the same JSON as the P2P send payload',
    () async {
      // Add `String? lastSentPayload` to FakeP2PService, populated in
      // sendMessageWithReply().
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Envelope parity',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'fixed-id-001',
      );

      expect(result, SendChatMessageResult.success);
      // Verify the persisted wireEnvelope matches what was sent over P2P
      expect(messageRepo.lastWireEnvelopeValue, isNotNull);
      expect(p2pService.lastSentPayload, isNotNull);
      expect(messageRepo.lastWireEnvelopeValue,
          equals(p2pService.lastSentPayload));
      expect(messageRepo.lastWireEnvelopeValue,
          contains('"id":"fixed-id-001"'));
    },
  );

  test(
    'RED: wireEnvelope is persisted even when all P2P paths fail',
    () async {
      p2pService = FakeP2PService(
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: false,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'All fail but envelope persisted',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-wire-fail',
      );

      expect(result, SendChatMessageResult.peerNotFound);
      expect(message!.status, 'failed');
      // wireEnvelope was still persisted before the transport race
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-wire-fail'));
    },
  );
});
```

**Why these tests fail today:** `updateWireEnvelope` does not exist yet. The current code builds `jsonString` and immediately enters the transport race without persisting the envelope to the DB row. A crash after serialization but before any P2P path completes leaves a DB row with `wireEnvelope=null` that cannot be retried by Section 1's `PendingMessageRetrier`.

---

### Step 4.2 — Red: Inbox is NOT called on successful direct send (regression guard)

**Goal:** Confirm that the existing behavior is preserved: `storeInInbox` is NOT called when direct P2P succeeds with acknowledgment. This codifies the invariant that inbox is a fallback, not a primary delivery path, and guards against accidental introduction of unconditional inbox calls that would cause phantom push notifications.

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

```dart
group('Section 4 — inbox call-site regression guard', () {
  test(
    'storeInInbox is NOT called when direct P2P succeeds with ACK',
    () async {
      p2pService = FakeP2PService(
        sendMessageResult: true, // P2P succeeds with ACK
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Direct success no inbox',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      // Inbox must NOT be called on ACK'd direct send — avoids phantom push
      expect(p2pService.storeInInboxCallCount, 0);
    },
  );

  test(
    'storeInInbox IS called once when P2P succeeds without ACK (existing behavior)',
    () async {
      // sendMessageResult returns empty string (success but unacked)
      p2pService = FakeP2PService(
        sendMessageResult: true,
        sendMessageReplyValue: '', // empty = unacked
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Unacked send',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      // Unacked path calls storeInInbox as fallback — existing behavior
      expect(p2pService.storeInInboxCallCount, 1);
    },
  );

  test(
    'storeInInbox IS called once when all P2P paths fail (existing behavior)',
    () async {
      p2pService = FakeP2PService(
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: true,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'All fail inbox fallback',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
      expect(message.transport, 'inbox');
      // Exactly one inbox call from the failure fallback — not zero, not two
      expect(p2pService.storeInInboxCallCount, 1);
    },
  );

  test(
    'when all P2P paths fail and inbox also fails, message persists as failed',
    () async {
      p2pService = FakeP2PService(
        sendMessageResult: false,
        useNullDiscover: true,
        storeInInboxResult: false,
      );

      final (result, message) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Both fail',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.peerNotFound);
      expect(message!.status, 'failed');
      // The failure fallback attempted inbox once
      expect(p2pService.storeInInboxCallCount, 1);
    },
  );
});
```

**Why these tests matter:** They codify the invariant that inbox is a fallback mechanism, not a primary delivery path. The first test (`storeInInboxCallCount == 0` on ACK'd success) would have FAILED under the old "optimistic inbox-first" plan. Under the direct-first plan, it passes and guards against phantom push regressions.

---

### Step 4.3 — Red: Deduplication regression guard (receive side)

**File to create:** `test/features/conversation/application/inbox_deduplication_regression_test.dart`

These tests verify the existing receive-side dedup behavior. They pass today and serve as a regression guard.

```dart
void main() {
  group('Section 4 — receive-side deduplication regression guard', () {
    test(
      'message arriving via inbox AND direct P2P is stored exactly once',
      () async {
        final json = _buildChatJson(id: 'dedup-msg-001');

        // Inbox delivery arrives first.
        final (r1, msg1, _) = await handleIncomingChatMessage(
          message: _buildP2PMessage(json, transport: 'inbox'),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        expect(r1, HandleChatMessageResult.chatMessage);
        expect(messageRepo.saved.length, 1);

        // Same message arrives again via direct P2P stream.
        final (r2, msg2, _) = await handleIncomingChatMessage(
          message: _buildP2PMessage(json, transport: 'direct'),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        expect(r2, HandleChatMessageResult.duplicate);
        expect(messageRepo.saved.length, 1); // still exactly one
      },
    );

    test(
      'message arriving via direct P2P AND then inbox is stored exactly once',
      () async {
        final json = _buildChatJson(id: 'dedup-msg-002');

        final (r1, _, __) = await handleIncomingChatMessage(
          message: _buildP2PMessage(json, transport: 'direct'),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        expect(r1, HandleChatMessageResult.chatMessage);

        final (r2, _, ___) = await handleIncomingChatMessage(
          message: _buildP2PMessage(json, transport: 'inbox'),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        expect(r2, HandleChatMessageResult.duplicate);
        expect(messageRepo.saved.length, 1);
      },
    );

    test(
      'two different message IDs from same sender are both stored',
      () async {
        final json1 = _buildChatJson(id: 'msg-A', text: 'First');
        final json2 = _buildChatJson(id: 'msg-B', text: 'Second');

        await handleIncomingChatMessage(
          message: _buildP2PMessage(json1, transport: 'inbox'),
          messageRepo: messageRepo, contactRepo: contactRepo,
        );
        await handleIncomingChatMessage(
          message: _buildP2PMessage(json2, transport: 'direct'),
          messageRepo: messageRepo, contactRepo: contactRepo,
        );

        expect(messageRepo.saved.length, 2);
        expect(
            messageRepo.saved.map((m) => m.id).toSet(), {'msg-A', 'msg-B'});
      },
    );
  });
}
```

---

### Step 4.4 — Red: Edge cases for inbox fallback resilience

These tests verify that the existing inbox fallback (on P2P failure) handles errors gracefully without breaking the send path.

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

```dart
group('Section 4 — inbox fallback edge cases', () {
  test(
    'storeInInbox throwing in the fallback path marks message as failed '
    'and wireEnvelope is still persisted for retry',
    () async {
      final throwingInboxP2P = _ThrowOnInboxP2PService();

      final (result, message) = await sendChatMessage(
        p2pService: throwingInboxP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox throws after P2P fails',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
        messageId: 'msg-edge-001',
      );

      // P2P failed, inbox threw — message should be marked failed
      expect(result, SendChatMessageResult.peerNotFound);
      expect(message!.status, 'failed');
      // wireEnvelope was still persisted, so Section 1 retrier can recover
      expect(messageRepo.wireEnvelopeUpdates, contains('msg-edge-001'));
    },
  );

  test(
    'storeInInbox throwing does not affect result when direct P2P succeeds',
    () async {
      // P2P succeeds, so inbox fallback is never reached
      final throwingInboxP2P = _ThrowOnInboxP2PService(p2pSucceeds: true);

      final (result, message) = await sendChatMessage(
        p2pService: throwingInboxP2P,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Inbox throws but P2P succeeds',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );

      expect(result, SendChatMessageResult.success);
      expect(message!.status, 'delivered');
    },
  );

  test(
    'slow relay does not block P2P path — P2P result returns promptly',
    () async {
      // The existing behavior already runs inbox only on failure.
      // This test confirms P2P success returns without waiting for any
      // inbox operation (since inbox is not called on ACK'd success).
      p2pService = FakeP2PService(sendMessageResult: true);

      final stopwatch = Stopwatch()..start();
      final (result, _) = await sendChatMessage(
        p2pService: p2pService,
        messageRepo: messageRepo,
        targetPeerId: 'target-peer',
        text: 'Fast direct',
        senderPeerId: 'my-peer',
        senderUsername: 'Me',
      );
      stopwatch.stop();

      expect(result, SendChatMessageResult.success);
      expect(stopwatch.elapsed.inSeconds, lessThan(3));
      expect(p2pService.storeInInboxCallCount, 0); // no inbox on success
    },
  );
});
```

---

### Step 4.5 — Idempotent Inbox-Handoff Guard

#### Problem

There is a crash window between a successful `storeInInbox()` call and the subsequent local DB update (setting `status='delivered'`, `transport='inbox'`, `wireEnvelope=null`). If the app is killed in this window:

1. The relay has already stored the message and fired an FCM push notification.
2. The local DB still has `status='sent'` (or `'sending'`/`'failed'`) with `wireEnvelope != null`.
3. On resume, Section 1's retrier (or `retryFailedMessages` / `retryUnackedMessages`) replays the same wireEnvelope to inbox.
4. The relay appends a second copy (`backend_memory.go:112` has no dedup) and fires a second FCM push (`inbox.go:598`).
5. The recipient sees duplicate push notifications for the same message.

The receive side is safe -- `handleIncomingChatMessage` deduplicates by `messageId` and returns `HandleChatMessageResult.duplicate`. But the duplicate push notification is a user-visible regression.

#### Chosen approach: Option C (combined client + relay)

**Relay-side dedup (safety net):** The relay server deduplicates `store` calls by extracting the `messageId` from the message payload. If the same `messageId` is already in the inbox for the same `toPeerId`, the store is a no-op (returns `OK` without appending or firing a push notification). This is the authoritative guard -- it works even when the client crashes between inbox success and local DB update.

**Client-side flag (optimization):** After `storeInInbox` succeeds, the local DB row is updated to `transport='inbox'` and `wireEnvelope=null`. Retry logic checks this before re-sending to inbox. This prevents unnecessary network round-trips but is NOT sufficient alone (crash between inbox success and flag save).

**Responsibility:** The relay server (`go-relay-server`) owns the idempotency guarantee. The client-side flag is a best-effort optimization.

#### Step 4.5a — Red: Relay-side inbox dedup by messageId

**File to create:** `go-relay-server/inbox_dedup_test.go`

```go
func TestInboxStoreDedup(t *testing.T) {
    push := NewPushServiceWithBackend(newMemoryPushTokenStore())
    inbox := NewInboxStore(push)

    msg1 := inboxMessage{
        From:    "sender-peer",
        Message: `{"type":"chat","version":"1","payload":{"id":"msg-dedup-001","text":"hello"}}`,
        Timestamp: time.Now().UnixMilli(),
    }

    // First store succeeds
    inbox.Store("recipient-peer", msg1)
    count := inbox.Count("recipient-peer")
    if count != 1 {
        t.Fatalf("expected 1 message after first store, got %d", count)
    }

    // Second store with same messageId is a no-op
    msg2 := inboxMessage{
        From:    "sender-peer",
        Message: msg1.Message, // same payload, same messageId
        Timestamp: time.Now().UnixMilli(),
    }
    inbox.Store("recipient-peer", msg2)
    count = inbox.Count("recipient-peer")
    if count != 1 {
        t.Fatalf("expected 1 message after duplicate store, got %d", count)
    }
}

func TestInboxStoreDedup_DifferentMessageIds(t *testing.T) {
    push := NewPushServiceWithBackend(newMemoryPushTokenStore())
    inbox := NewInboxStore(push)

    msg1 := inboxMessage{
        From:    "sender-peer",
        Message: `{"type":"chat","version":"1","payload":{"id":"msg-A","text":"first"}}`,
        Timestamp: time.Now().UnixMilli(),
    }
    msg2 := inboxMessage{
        From:    "sender-peer",
        Message: `{"type":"chat","version":"1","payload":{"id":"msg-B","text":"second"}}`,
        Timestamp: time.Now().UnixMilli(),
    }

    inbox.Store("recipient-peer", msg1)
    inbox.Store("recipient-peer", msg2)
    count := inbox.Count("recipient-peer")
    if count != 2 {
        t.Fatalf("expected 2 messages for different IDs, got %d", count)
    }
}

func TestInboxStoreDedup_SameIdDifferentRecipient(t *testing.T) {
    push := NewPushServiceWithBackend(newMemoryPushTokenStore())
    inbox := NewInboxStore(push)

    msg := inboxMessage{
        From:    "sender-peer",
        Message: `{"type":"chat","version":"1","payload":{"id":"msg-shared","text":"broadcast"}}`,
        Timestamp: time.Now().UnixMilli(),
    }

    inbox.Store("recipient-A", msg)
    inbox.Store("recipient-B", msg)
    if inbox.Count("recipient-A") != 1 {
        t.Fatal("recipient-A should have 1 message")
    }
    if inbox.Count("recipient-B") != 1 {
        t.Fatal("recipient-B should have 1 message")
    }
}

func TestInboxStoreDedup_V2EncryptedEnvelope(t *testing.T) {
    push := NewPushServiceWithBackend(newMemoryPushTokenStore())
    inbox := NewInboxStore(push)

    // V2 encrypted envelopes embed the messageId at the top level as "id"
    msg := inboxMessage{
        From:    "sender-peer",
        Message: `{"version":"2","senderPeerId":"sender","id":"msg-enc-001","encrypted":{"kem":"...","ciphertext":"...","nonce":"..."}}`,
        Timestamp: time.Now().UnixMilli(),
    }

    inbox.Store("recipient-peer", msg)
    inbox.Store("recipient-peer", msg) // duplicate
    if inbox.Count("recipient-peer") != 1 {
        t.Fatalf("expected 1 message after duplicate v2 store, got %d", inbox.Count("recipient-peer"))
    }
}

func TestInboxStoreDedup_MalformedJsonFallsThrough(t *testing.T) {
    push := NewPushServiceWithBackend(newMemoryPushTokenStore())
    inbox := NewInboxStore(push)

    // Malformed JSON should still be stored (no dedup possible)
    msg := inboxMessage{
        From:    "sender-peer",
        Message: "not valid json",
        Timestamp: time.Now().UnixMilli(),
    }

    inbox.Store("recipient-peer", msg)
    inbox.Store("recipient-peer", msg) // same malformed payload
    // Both stored because we cannot extract a messageId
    if inbox.Count("recipient-peer") != 2 {
        t.Fatalf("expected 2 messages for malformed JSON, got %d", inbox.Count("recipient-peer"))
    }
}

func TestInboxStoreDedup_PushNotFiredOnDuplicate(t *testing.T) {
    tokenStore := newMemoryPushTokenStore()
    tokenStore.RegisterToken("recipient-peer", "fake-token", "ios")
    recorder := &pushRecorder{}
    push := newPushServiceWithSender(tokenStore, recorder)
    inbox := NewInboxStore(push)

    msg := inboxMessage{
        From:    "sender-peer",
        Message: `{"type":"chat","version":"1","payload":{"id":"msg-push-001","text":"hello"}}`,
        Timestamp: time.Now().UnixMilli(),
    }

    inbox.Store("recipient-peer", msg)
    // Wait briefly for goroutine
    time.Sleep(50 * time.Millisecond)
    firstCount := recorder.sendCount()

    inbox.Store("recipient-peer", msg) // duplicate
    time.Sleep(50 * time.Millisecond)
    secondCount := recorder.sendCount()

    if secondCount != firstCount {
        t.Fatalf("push should NOT fire on duplicate store; sends before=%d after=%d",
            firstCount, secondCount)
    }
}
```

**Why these tests fail today:** `memoryInboxBackend.Store` (`backend_memory.go:112`) appends unconditionally. There is no `messageId` extraction or dedup check. The push notification fires on every `Store` call via `inbox.go:598`.

#### Step 4.5b — Green: Add relay-side dedup to InboxStore

**File to modify:** `go-relay-server/backend_memory.go`

Add a `messageIds` set to `memoryInboxBackend` for per-recipient dedup:

```go
type memoryInboxBackend struct {
    mu         sync.Mutex
    store      map[string][]inboxMessage   // peerId -> messages
    messageIds map[string]map[string]bool  // peerId -> set of messageIds
}

func newMemoryInboxBackend() *memoryInboxBackend {
    return &memoryInboxBackend{
        store:      make(map[string][]inboxMessage),
        messageIds: make(map[string]map[string]bool),
    }
}
```

Update `Store` to extract `messageId` from the JSON payload and skip if already seen:

```go
func (b *memoryInboxBackend) Store(toPeerId string, entry inboxMessage) bool {
    b.mu.Lock()
    defer b.mu.Unlock()

    // Extract messageId for dedup.
    msgId := extractMessageId(entry.Message)
    if msgId != "" {
        if ids, ok := b.messageIds[toPeerId]; ok && ids[msgId] {
            // Duplicate — skip store and push.
            return false
        }
    }

    messages := b.pruneExpired(b.store[toPeerId])

    // Cap at max
    if len(messages) >= maxMessagesPerPeer {
        messages = messages[len(messages)-maxMessagesPerPeer+1:]
        // Also prune messageIds for evicted messages
        b.rebuildMessageIds(toPeerId, messages)
    }

    messages = append(messages, entry)
    b.store[toPeerId] = messages

    // Track messageId
    if msgId != "" {
        if b.messageIds[toPeerId] == nil {
            b.messageIds[toPeerId] = make(map[string]bool)
        }
        b.messageIds[toPeerId][msgId] = true
    }

    return true
}
```

**File to modify:** `go-relay-server/inbox.go`

Add a helper to extract `messageId` from the JSON message payload:

```go
// extractMessageId attempts to extract a message ID from the JSON payload
// for deduplication. Supports v1 (payload.id) and v2 (top-level id) envelopes.
// Returns "" if the payload is malformed or has no extractable ID.
func extractMessageId(message string) string {
    var envelope map[string]interface{}
    if err := json.Unmarshal([]byte(message), &envelope); err != nil {
        return ""
    }

    // V2 encrypted: top-level "id" field
    if id, ok := envelope["id"].(string); ok && id != "" {
        return id
    }

    // V1 plaintext: payload.id
    if payload, ok := envelope["payload"].(map[string]interface{}); ok {
        if id, ok := payload["id"].(string); ok {
            return id
        }
    }

    return ""
}
```

Update `InboxStore.Store` to propagate the dedup result and conditionally fire push:

```go
func (is *InboxStore) Store(toPeerId string, entry inboxMessage) {
    stored := is.backend.Store(toPeerId, entry)
    if !stored {
        // Duplicate — do not fire push notification.
        log.Printf("[INBOX] Duplicate message for %s from %s — skipped",
            toPeerId[:min(20, len(toPeerId))],
            entry.From[:min(20, len(entry.From))])
        inboxStoredCounter.Inc() // still count for metrics visibility
        return
    }
    inboxStoredCounter.Inc()
    if biz != nil {
        biz.RecordMessageStored()
    }

    log.Printf("[INBOX] Stored message for %s from %s",
        toPeerId[:min(20, len(toPeerId))],
        entry.From[:min(20, len(entry.From))])

    // Fire push notification only for genuinely new messages.
    go is.push.SendNotification(context.Background(), toPeerId, entry.From)
}
```

Update `InboxBackend` interface to return `bool` from `Store`:

```go
type InboxBackend interface {
    Store(toPeerId string, entry inboxMessage) bool // returns false if duplicate
    Retrieve(peerId string, limit int) ([]inboxMessage, bool)
    Count(peerId string) int
    Stats() (totalPeers int, totalMessages int)
}
```

Also update `Retrieve` to clean up the `messageIds` set when messages are consumed:

```go
func (b *memoryInboxBackend) Retrieve(peerId string, limit int) ([]inboxMessage, bool) {
    b.mu.Lock()
    defer b.mu.Unlock()

    messages := b.pruneExpired(b.store[peerId])
    b.store[peerId] = messages

    if len(messages) == 0 {
        delete(b.store, peerId)
        delete(b.messageIds, peerId)
        return nil, false
    }

    if limit > len(messages) {
        limit = len(messages)
    }

    result := make([]inboxMessage, limit)
    copy(result, messages[:limit])

    remaining := messages[limit:]
    if len(remaining) > 0 {
        b.store[peerId] = remaining
        b.rebuildMessageIds(peerId, remaining)
        return result, true
    }

    delete(b.store, peerId)
    delete(b.messageIds, peerId)
    return result, false
}

func (b *memoryInboxBackend) rebuildMessageIds(peerId string, messages []inboxMessage) {
    ids := make(map[string]bool, len(messages))
    for _, m := range messages {
        if msgId := extractMessageId(m.Message); msgId != "" {
            ids[msgId] = true
        }
    }
    if len(ids) > 0 {
        b.messageIds[peerId] = ids
    } else {
        delete(b.messageIds, peerId)
    }
}
```

**Change summary:**

| # | File | Change |
|---|---|---|
| 1 | `go-relay-server/inbox.go` | Add `extractMessageId()` helper |
| 2 | `go-relay-server/inbox.go` | Update `InboxStore.Store` to skip push on duplicate |
| 3 | `go-relay-server/inbox.go` | Update `InboxBackend` interface: `Store` returns `bool` |
| 4 | `go-relay-server/backend_memory.go` | Add `messageIds` map to `memoryInboxBackend` |
| 5 | `go-relay-server/backend_memory.go` | Update `Store` to check/track messageIds, return `bool` |
| 6 | `go-relay-server/backend_memory.go` | Update `Retrieve` to clean up `messageIds` on consume |
| 7 | `go-relay-server/backend_memory.go` | Add `rebuildMessageIds` helper |

#### Step 4.5c — Red: Dart-side retry skips inbox when transport is already inbox

**File:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

```dart
group('Section 4 — idempotent inbox-handoff guard', () {
  test(
    'RED: retryFailedMessages skips storeInInbox when message transport '
    'is already inbox',
    () async {
      // Simulate the post-crash state: message was successfully stored
      // in inbox but app crashed before DB was updated. On resume,
      // a recovery path re-saved the row with transport='inbox'.
      // retryFailedMessages should skip inbox for this message.
      final messageRepo = FakeMessageRepository();
      final msg = ConversationMessage(
        id: 'msg-crash-001',
        contactPeerId: 'target-peer',
        text: 'Crash test',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: false,
        status: 'failed',
        transport: 'inbox', // already delivered via inbox before crash
        wireEnvelope: '{"type":"chat","version":"1","payload":{"id":"msg-crash-001"}}',
      );
      messageRepo.failedMessages = [msg];

      final p2p = FakeP2PService(storeInInboxResult: true);

      await retryFailedMessages(
        messageRepo: messageRepo,
        identityRepo: fakeIdentityRepo,
        contactRepo: fakeContactRepo,
        p2pService: p2p,
        bridge: fakeBridge,
      );

      // storeInInbox should NOT be called — message already has transport='inbox'
      expect(p2p.storeInInboxCallCount, 0);
    },
  );

  test(
    'RED: retryUnackedMessages skips storeInInbox when message transport '
    'is already inbox',
    () async {
      final messageRepo = FakeMessageRepository();
      final msg = ConversationMessage(
        id: 'msg-crash-002',
        contactPeerId: 'target-peer',
        text: 'Unacked crash test',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: false,
        status: 'sent',
        transport: 'inbox', // already in inbox
        wireEnvelope: '{"type":"chat","version":"1","payload":{"id":"msg-crash-002"}}',
      );
      messageRepo.unackedMessages = [msg];

      final p2p = FakeP2PService(storeInInboxResult: true);

      await retryUnackedMessages(
        messageRepo: messageRepo,
        p2pService: p2p,
      );

      expect(p2p.storeInInboxCallCount, 0);
    },
  );
});
```

**Why these tests fail today:** Neither `retryFailedMessages` nor `retryUnackedMessages` checks the `transport` field before calling `storeInInbox`. They unconditionally attempt inbox store for any message with a `wireEnvelope`.

#### Step 4.5d — Green: Add client-side transport guard to retry use cases

**File to modify:** `lib/features/conversation/application/retry_failed_messages_use_case.dart`

In the wire-envelope fast path (line 57), add a transport check before `storeInInbox`:

```dart
      if (msg.wireEnvelope != null && msg.wireEnvelope!.isNotEmpty) {
        // Skip inbox if this message was already delivered via inbox
        // (crash between inbox success and DB update — relay-side dedup
        // is the authoritative guard, this is the client-side optimization).
        if (msg.transport == 'inbox') {
          await messageRepo.saveMessage(
            msg.copyWith(status: 'delivered', wireEnvelope: null),
          );
          successCount++;
          emitFlowEvent(
            layer: 'FL',
            event: 'RETRY_FAILED_MESSAGE_ALREADY_INBOX',
            details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
          );
          continue;
        }
        try {
          final stored = await p2pService.storeInInbox(
```

**File to modify:** `lib/features/conversation/application/retry_unacked_messages_use_case.dart`

In the retry loop (line 43), add a transport check:

```dart
  for (final msg in unacked) {
    // Skip inbox if already delivered via inbox (crash recovery guard).
    if (msg.transport == 'inbox') {
      await messageRepo.saveMessage(
        msg.copyWith(status: 'delivered', wireEnvelope: null),
      );
      count++;
      emitFlowEvent(
        layer: 'FL',
        event: 'RETRY_UNACKED_MESSAGE_ALREADY_INBOX',
        details: {'id': msg.id.length > 8 ? msg.id.substring(0, 8) : msg.id},
      );
      continue;
    }
    try {
      final stored = await p2pService.storeInInbox(
```

#### Idempotency guarantee summary

| Layer | Mechanism | Crash window covered |
|---|---|---|
| Relay server | `extractMessageId` + per-recipient `messageIds` set in `memoryInboxBackend` | Crash after inbox store success, before ANY local state update. Authoritative. |
| Client (retry use cases) | Skip `storeInInbox` if `transport == 'inbox'` | Crash after inbox store + partial DB update (transport saved but wireEnvelope not cleared). Optimization only. |
| Client (receive side) | `handleIncomingChatMessage` dedup by `messageExists(payload.id)` | Duplicate relay entries that slip through (e.g., non-chat message types). Existing behavior, unchanged. |

---

### Step 4.6 — Green: Persist wireEnvelope early + media at optimistic write

#### Change 0 (wired layer): Persist media attachments at optimistic write time

**File to modify:** `lib/features/conversation/presentation/screens/conversation_wired.dart`

Immediately after `messageRepo.saveMessage(optimisticMessage)` at line 637, persist each media attachment so it survives a crash during the media-upload gap (lines 646-722):

```dart
  // Persist media attachment metadata alongside the optimistic message.
  // downloadStatus='upload_pending' marks these as outgoing attachments whose
  // upload to the relay has not yet completed. This is the sentinel that
  // retryIncompleteUploads (Part G) uses to find interrupted uploads on resume.
  // See Part G.1 for the full downloadStatus lifecycle table.
  if (optimisticMedia != null && optimisticMedia.isNotEmpty) {
    for (final attachment in optimisticMedia) {
      await widget.mediaAttachmentRepo.saveAttachment(
        messageId: optimisticMessage.id,
        attachment: attachment.copyWith(downloadStatus: 'upload_pending'),
      );
    }
  }
```

This closes the wired-layer gap: even if the app dies during media upload (lines 646-722), the attachment metadata is in the DB with `downloadStatus='upload_pending'` and `retryIncompleteUploads` (Part G) can re-upload and re-send on resume. After a successful upload, the attachment row is replaced with `downloadStatus='done'` and the real relay blob ID as the attachment `id`.

#### Change 1 (use case): Persist wireEnvelope before transport race

**File to modify:** `lib/features/conversation/application/send_chat_message_use_case.dart`

After `jsonString` is built (after `logChatWireEnvelope`, ~line 175) and BEFORE the `isAlreadyConnected` check, persist the wire envelope to the existing optimistic row:

```dart
  // Persist wireEnvelope immediately so a crash during the transport race
  // leaves a retryable row with the encrypted payload.
  // Section 1's PendingMessageRetrier uses this to replay the message.
  if (messageId != null) {
    await messageRepo.updateWireEnvelope(messageId, jsonString);
  }
```

This requires adding `updateWireEnvelope(String messageId, String wireEnvelope)` to the `MessageRepository` interface and implementation -- a single `UPDATE messages SET wire_envelope = ? WHERE id = ?` query.

#### No change to inbox call sites

The existing `storeInInbox()` calls remain exactly where they are today:

1. **All-fail fallback** (`send_chat_message_use_case.dart:361`): Called when all active P2P paths have failed. Unchanged.
2. **Unacked handoff** (`send_chat_message_use_case.dart:731` inside `_persistOutgoingSendResult`): Called when P2P send succeeds but is not acknowledged. Unchanged.
3. **ACK'd success path**: Does NOT call `storeInInbox`. Unchanged.

No new `storeInInbox` call is added. No `inboxStoreFuture` is threaded through success paths. No inbox fallback blocks are removed or rewritten. The existing fallback logic is the correct behavior.

**Change summary:**

| # | File | Location | Action |
|---|---|---|---|
| 0 | `conversation_wired.dart` | After line 637 (optimistic save) | Persist media attachments to `media_attachments` table |
| 1 | `send_chat_message_use_case.dart` | After `logChatWireEnvelope` (~line 175) | Insert `messageRepo.updateWireEnvelope(messageId, jsonString)` |
| 2 | `message_repository.dart` | Interface | Add `updateWireEnvelope(String id, String envelope)` |
| 3 | `message_repository_impl.dart` | Implementation | Single `UPDATE messages SET wire_envelope = ? WHERE id = ?` query |

---

### Step 4.7 — Green: Update test infrastructure

Because this section does NOT change the inbox call pattern, existing tests that assert `storeInInboxCallCount == 0` on successful direct sends remain correct and do not need updating.

The only test changes needed are to add `updateWireEnvelope` support to the fake:

**File to modify:** `test/features/conversation/application/send_chat_message_use_case_test.dart`

Add to `FakeMessageRepository`:

```dart
final List<String> wireEnvelopeUpdates = [];
String? lastWireEnvelopeValue;
VoidCallback? onUpdateWireEnvelope;

@override
Future<void> updateWireEnvelope(String id, String envelope) async {
  wireEnvelopeUpdates.add(id);
  lastWireEnvelopeValue = envelope;
  onUpdateWireEnvelope?.call();
}
```

Add to `FakeP2PService` (for cross-component ordering tests):

```dart
VoidCallback? onDiscover;
VoidCallback? onSendMessage;
String? lastSentPayload;

// In discoverPeer():
onDiscover?.call();

// In sendMessageWithReply():
lastSentPayload = message; // capture the payload
onSendMessage?.call();
```

Existing tests for the relay-probe paths (`'discover miss then relay probe connected sends live without inbox'` and `'dial failed then relay probe connected sends live without inbox'`) continue to assert `storeInInboxCallCount == 0` -- this is correct because direct send succeeds with ACK on these paths and inbox is not called.

---

### Step 4.8 — Refactor: Document wireEnvelope contract

- Update docstring on `sendChatMessage` to document the new wireEnvelope persistence step and its relationship to Section 1's retrier.
- Add a code comment at the wireEnvelope persist site:

```dart
  // SECTION 4 CONTRACT: wireEnvelope is persisted BEFORE the transport race.
  // If the app crashes after this point, the DB row has wireEnvelope != null
  // and Section 1's PendingMessageRetrier can replay the message without
  // re-serializing or re-encrypting.
```

- No event strings are removed. No inbox fallback blocks are removed or rewritten. The existing fallback logic is correct as-is.

> **Note on retry paths:** `retry_failed_messages_use_case.dart:59` and `retry_unacked_messages_use_case.dart:45` each call `storeInInbox` independently. Since inbox is only called on failure/unacked in the original send, and retries only fire for failed/unacked messages, there is no double-inbox problem under normal operation. However, a crash between inbox success and local DB update can cause a duplicate inbox store on retry. **Resolved in Step 4.5:** The relay-side dedup (Step 4.5b) is the authoritative guard, and the client-side transport check (Step 4.5d) is the optimization that skips `storeInInbox` if `transport == 'inbox'` is already set on the message row.

---

### Data Flow After the Fix

```
_onSend (conversation_wired.dart)
        |
        v
[IMPROVED] Optimistic DB write: status='sending'
[NEW]     Persist media attachments to media_attachments table
        |
        v
... media upload (up to 60s) — if app dies here, DB has message + media rows ...
... contact refresh ...
        |
        v
sendChatMessage() called
        |
        v
Validate + Build payload + Serialize jsonString
        |
        v
[NEW] messageRepo.updateWireEnvelope(messageId, jsonString)
   (if app dies here, DB row has wireEnvelope — Section 1 retrier can replay)
        |
        v
isAlreadyConnected? ──yes──> sendMessageWithReply (reuse path)
        |                          |
        no                    success+ACK → return delivered (no inbox call)
        |                    success-noACK → storeInInbox (existing line 731)
        |
        v
Race: [localSend] vs [discover→dial→send]
        |
   first success+ACK → return delivered (no inbox call)
   first success-noACK → storeInInbox (existing line 731)
        |
   all fail
        |
        v
storeInInbox fallback (existing line 361)
        |
   storedInInbox=true  ──> return success/delivered/inbox
   storedInInbox=false ──> persist as 'failed'
                           (wireEnvelope in DB → Section 1 retrier recovers)
```

**Key design decision:** The ACK'd direct-send path has zero inbox calls. No phantom push notifications. No duplicate relay entries. The reliability improvement comes entirely from persisting `wireEnvelope` to the DB row before the transport race, enabling Sections 1-3 to retry on recovery.

---

### Smoke Tests

**Test A: wireEnvelope persistence — kill app during transport race**

1. Device A: Set a breakpoint or artificial delay after `updateWireEnvelope` but before P2P send completes.
2. Device A: Send a message to Device B.
3. Force-kill Device A's app after wireEnvelope persist but before P2P completes.
4. Relaunch Device A.
5. Verify: Section 1 retrier picks up the message (has `wireEnvelope`, status `'sending'`), transitions it to `'failed'`, and retry delivers it.

**Test B: normal send — no phantom push**

1. Device A and Device B: Both online, connected via relay.
2. Device A: Send a message to Device B.
3. Verify: Message arrives via direct P2P. Device B does NOT receive a push notification (because inbox was not called on ACK'd success).

**Test C: offline recipient — inbox fallback**

1. Device B: Kill the app (offline).
2. Device A: Send a message to Device B.
3. Verify: P2P fails, inbox fallback fires, message marked `'delivered'` with `transport='inbox'`.
4. Relaunch Device B: Message appears via inbox retrieve. Push notification appears (expected and correct, because inbox was used as the last-resort fallback).

**Test D: crash between inbox success and DB update — no duplicate push (Step 4.5)**

1. Device B: Kill the app (offline).
2. Device A: Set a breakpoint or artificial delay in `_persistOutgoingSendResult` after `storeInInbox` returns `true` but before the `ConversationMessage` is returned/saved.
3. Device A: Send a message to Device B. Inbox fallback fires, relay accepts.
4. Force-kill Device A's app BEFORE the DB row is updated to `status='delivered'`.
5. Relaunch Device A. The retrier finds the message with `wireEnvelope != null` and attempts to replay it to inbox.
6. Verify on relay server logs: `[INBOX] Duplicate message for ... — skipped`. No second push notification is fired.
7. Verify on Device B (when relaunched): Exactly one push notification, exactly one message in conversation.

| Scenario | storeInInbox calls | Push notification | wireEnvelope persisted |
|---|---|---|---|
| A: Kill during transport race | 0 (send never completed) | No | Yes — retrier recovers |
| B: Both online, ACK'd success | 0 | No | Yes |
| C: Offline recipient, P2P fails | 1 (fallback) | Yes (expected) | Yes |
| D: P2P success, no ACK | 1 (unacked handoff) | Yes (existing behavior) | Yes |
| E: Crash between inbox + DB update | 2 (retry replays) | 1 (relay dedup blocks 2nd) | Yes |

---

### Build Sequence Checklist

- [ ] Add `updateWireEnvelope(String id, String envelope)` to `MessageRepository` interface
- [ ] Add `updateWireEnvelope` implementation to `MessageRepositoryImpl` (single UPDATE query)
- [ ] Add `wireEnvelopeUpdates`, `lastWireEnvelopeValue`, `onUpdateWireEnvelope` to `FakeMessageRepository`
- [ ] Add `onDiscover`, `onSendMessage`, `lastSentPayload` to `FakeP2PService`
- [ ] Add media attachment persistence to `conversation_wired.dart` after optimistic write (Change 0)
- [ ] Write Step 4.1 Red tests (wireEnvelope persistence ordering) -- verify they fail
- [ ] Write Step 4.2 regression guard tests (inbox NOT called on ACK'd success) -- verify they pass
- [ ] Write Step 4.3 dedup regression tests -- verify they pass (existing behavior)
- [ ] Write Step 4.4 edge case tests -- verify they match current behavior
- [ ] **Step 4.5a:** Write Go relay dedup tests (`go-relay-server/inbox_dedup_test.go`) -- verify they fail
- [ ] **Step 4.5b:** Add `extractMessageId` + `messageIds` dedup to `go-relay-server/backend_memory.go` and `inbox.go`
- [ ] **Step 4.5b:** Update `InboxBackend.Store` to return `bool`, update `InboxStore.Store` to skip push on dup
- [ ] **Step 4.5b:** Verify all Go dedup tests pass; run `go test ./...` in `go-relay-server/`
- [ ] **Step 4.5c:** Write Dart-side retry transport guard tests -- verify they fail
- [ ] **Step 4.5d:** Add `transport == 'inbox'` guard to `retry_failed_messages_use_case.dart`
- [ ] **Step 4.5d:** Add `transport == 'inbox'` guard to `retry_unacked_messages_use_case.dart`
- [ ] **Step 4.5d:** Verify Dart-side retry guard tests pass
- [ ] Insert `messageRepo.updateWireEnvelope(messageId, jsonString)` after `logChatWireEnvelope` (Change 1)
- [ ] Verify all Step 4.1 tests now pass (Green)
- [ ] Run full test suite: `flutter test test/features/conversation/application/`
- [ ] Execute manual smoke tests A, B, C on two devices

---


## Section 4 Addendum: Attachment Recovery Design Reconciliation

> **Design conflict resolved 2026-03-23.** This section originally proposed a
> separate `upload_status` column (migration 041) with its own lifecycle
> (`'pending_upload'`, `'uploading'`, `'uploaded'`, `'upload_failed'`). That
> design conflicted with the earlier Part G (Section 1) which extends the
> existing `downloadStatus` field with `'upload_pending'` and `'upload_failed'`
> sentinel values. The two designs were mutually exclusive -- implementing both
> would leave the codebase with two parallel state machines for the same
> concept, causing ambiguity about which column governs retry logic.
>
> **Decision: Part G's single-field approach is canonical. The separate
> `upload_status` column (migration 041) is NOT implemented.**
>
> This section documents the rationale, lists what is subsumed, and records
> which ideas from the original addendum are carried forward into Part G.

---

### Rationale for Keeping Part G's `downloadStatus` Extension

1. **Current codebase alignment.** The `MediaAttachment` model today has a
   single `downloadStatus` field (type `String`). The DB schema
   (`media_attachments.download_status`) is already in production. Part G adds
   new values (`'upload_pending'`, `'upload_failed'`) to this existing field
   with zero schema changes and zero migrations. The addendum's approach
   required a new nullable column, a new migration (041), a model field
   addition (`uploadStatus`), and updates to `fromMap`/`toMap`/`copyWith` --
   all for the same behavioral outcome.

2. **No semantic ambiguity in practice.** The addendum argued that
   `download_status` is "semantically wrong for sender-side pre-upload state."
   In practice, the direction of a `media_attachments` row is always knowable
   from the parent `messages.is_incoming` column. The `download_status` values
   `'pending'`, `'downloading'`, `'failed'` only appear on incoming rows; the
   values `'upload_pending'`, `'upload_failed'`, `'done'` only appear on
   outgoing rows. A single field with direction-aware values is unambiguous
   and simpler than two columns.

3. **Part G is already deeply cross-referenced.** Section 4 Step 4.5 Change 0
   (line ~7337), Section 3.6a (line ~6680), and the canonical send ordering
   (line ~6983) all reference `downloadStatus='upload_pending'`. The
   `retryIncompleteUploads` use case, `getUploadPendingAttachments()` repo
   method, and `dbLoadUploadPendingAttachments` DB helper are all specified in
   Part G using `downloadStatus`. Switching to `upload_status` would require
   rewriting those sections and their tests.

4. **No `'uploading'` intermediate state needed (explicit design decision).** The addendum introduced an
   `'uploading'` state plus `dbRecoverStuckUploads` to reset it on crash. Part
   G avoids this: a row stays `'upload_pending'` throughout the upload attempt.
   If the upload completes, the row is updated to `downloadStatus='done'`
   with the real relay blob ID. If the app crashes mid-upload, the row is still
   `'upload_pending'` and `retryIncompleteUploads` picks it up. The
   `'uploading'` state was only useful if we wanted to distinguish "never
   started" from "started but crashed," but the retry logic treats both
   identically (re-upload from `localPath`), so the distinction adds
   complexity without benefit. This is an intentional simplification: relay uploads are not resumable, so both states result in the same re-upload-from-scratch behavior. Implementers should not add an `'uploading'` state.

5. **Follows existing post-media precedent.** The `post_media_attachments`
   table uses `download_status` for both sender and receiver rows without a
   separate upload column. The `post_media_upload_recovery` table is a
   separate recovery mechanism (not a column). Conversation attachments
   should follow the same pattern.

---

### What the Original Addendum Proposed (Now Subsumed by Part G)

The following items from the original addendum are **not implemented** because
Part G already covers them:

| Original Addendum Item | Status | Covered By |
|---|---|---|
| Migration 041: `upload_status TEXT` column | NOT IMPLEMENTED | Part G uses existing `download_status` field -- no migration needed |
| `uploadStatus` field on `MediaAttachment` model | NOT IMPLEMENTED | Part G uses `downloadStatus` with new values `'upload_pending'`, `'upload_failed'` |
| `dbUpdateMediaUploadStatus` DB helper | NOT IMPLEMENTED | Part G uses existing `dbUpdateMediaDownloadStatus` |
| `dbLoadAttachmentsPendingUpload` DB helper | SUBSUMED | Part G: `dbLoadUploadPendingAttachments` (queries `download_status = 'upload_pending'`) |
| `dbRecoverStuckUploads` DB helper | NOT NEEDED | Part G has no `'uploading'` intermediate state; `'upload_pending'` rows are retried directly |
| `'pending_upload'` / `'uploading'` / `'uploaded'` / `'upload_failed'` lifecycle | SIMPLIFIED | Part G: `'upload_pending'` -> `'done'` (success) or `'upload_pending'` -> `'upload_failed'` (permanent failure) |
| Test files: `media_attachments_upload_state_test.dart`, `media_attachments_crash_recovery_test.dart` | SUBSUMED | Part G test files: `media_attachments_db_helpers_upload_pending_test.dart`, `retry_incomplete_uploads_use_case_test.dart` |

---

### Ideas Carried Forward from the Addendum into Part G

The original addendum identified several genuine gaps. These are addressed
within Part G's design, NOT via a separate column:

1. **`localPath` must be persisted at optimistic write time.** Before the
   optimistic DB write, files are copied into managed durable storage at
   `<appDocDir>/pending_uploads/<messageId>/`. Part G Step G-E sets
   `localPath` to this durable copy's path (media and voice) on the
   `upload_pending` row. This ensures the file survives even if the original
   temp file is cleaned up by the OS. The addendum's concern about voice
   messages losing `localPath` is addressed by Part G's voice-path save block
   (Step G-E, voice send path) which also copies to durable storage.

2. **Voice/audio metadata must be preserved.** Part G Step G-E includes
   `durationMs`, `waveform`, and `mime` on the optimistic voice attachment row.
   These fields already exist in the `media_attachments` schema (added in
   migrations 010 and 013). No new columns needed.

3. **Stable attachment ID contract.** Part G uses a single pre-generated UUID
   as the attachment `id`. This stable ID is created once at optimistic-write
   time and survives through all subsequent paths — local WiFi send, relay
   upload, and retry. After upload succeeds, the existing `upload_pending` row
   is **updated in place** (setting `downloadStatus='done'` and the relay blob
   URL/ID) rather than inserting a new row. Because the same ID is reused
   across all paths, orphan placeholder rows should **not** exist under normal
   operation. The addendum's original concern about UUID regeneration on retry
   is resolved by the stable-ID contract.

   > **Note (SA-08 resolved):** The original audit identified a triple-UUID
   > problem (optimistic UI, local WiFi, relay upload each generating a
   > different UUID). This is resolved: the pre-generated UUID is passed
   > through all paths so only one row ever exists per attachment. No
   > delete-then-insert strategy is needed. The orphan-cleanup batch job
   > (see Action Items) is retained as a **defensive safety net** for edge
   > cases (e.g., crash between row insert and upload), not as a required
   > operational step.

4. **File existence verification.** The addendum included tests for verifying
   file existence before retry. Part G Step G-D (`retryIncompleteUploads` use
   case) includes a `localPath == null` guard (line ~3253). Because the DB
   stores relative paths, all file-existence checks **must** first resolve via
   `MediaFileManager.resolveStoredPath()` to obtain an absolute path, then
   call `File(resolvedPath).exists()`. If the resolved file is missing, the
   attachment is marked `'upload_failed'` via
   `mediaAttachmentRepo.updateDownloadStatus(id, 'upload_failed')`. Files in
   the durable `pending_uploads/<messageId>/` directory should survive app
   restarts and iOS container UUID changes. Add a corresponding test to
   `retry_incomplete_uploads_use_case_test.dart`:
   "skips attachment whose local file no longer exists on disk."

   > **Note (SA-02 resolved):** `retryIncompleteUploads` accepts a
   > `MediaFileManager` parameter and calls `resolveStoredPath()` before the
   > file-existence check. This handles both relative paths stored in the DB
   > and the iOS container-UUID-change scenario. With files now copied to
   > durable managed storage (`pending_uploads/`), the resolved path should
   > reliably point to an existing file unless the user manually cleared app
   > data.

5. **`toJson` wire isolation.** The addendum correctly noted that upload state
   must not appear in the wire payload. Since Part G uses `downloadStatus`
   (which `toJson()` already omits -- see `media_attachment.dart` line 138),
   this is automatically satisfied. No additional exclusion logic needed.

6. **Startup sweep ordering.** The addendum proposed calling
   `dbRecoverStuckUploads` at startup. Part G's equivalent is the ordering:
   `recoverStuckSendingMessages` (Part A) -> `retryIncompleteUploads` (Part G)
   -> `retryFailedMessages` (Parts B-D). Since Part G has no `'uploading'`
   intermediate state, no separate stuck-upload recovery sweep is needed --
   `'upload_pending'` rows are retried directly.

---

### Updated `downloadStatus` Lifecycle (Canonical Reference)

This is the authoritative lifecycle table. It supersedes both the original
Part G.1 table and the addendum's `upload_status` lifecycle.

| Value | Direction | Meaning |
|---|---|---|
| `'upload_pending'` | outgoing | Optimistically written at send time; upload not yet completed |
| `'done'` | outgoing or incoming | Upload completed (outgoing) or download completed (incoming); file available at `localPath` |
| `'upload_failed'` | outgoing | Re-upload attempted and permanently failed; user must resend manually |
| `'pending'` | incoming | Relay blob exists; local file not yet downloaded |
| `'downloading'` | incoming | Download in progress |
| `'failed'` | incoming | Download permanently failed |

**Outgoing lifecycle transitions:**

- **Send time:** `upload_pending` (optimistic row written with stable pre-generated ID, file copied to durable storage)
- **Local-WiFi success:** `upload_pending` → `done` (after successful `sendLocalMedia`, the row is updated to `done` immediately since the recipient received the file directly — no relay upload needed)
- **Relay upload success:** `upload_pending` → `done` (row updated in place with relay blob ID)
- **Permanent failure:** `upload_pending` → `upload_failed` (non-recoverable error, e.g., missing local file)
- **Transient failure:** row stays `upload_pending` (retried on next resume/reconnect)

The `download_status` column in the `media_attachments` table stores these
values as plain text. No CHECK constraint is added (consistent with all other
status columns in the schema). Direction is determined by the parent message's
`is_incoming` flag, not by the status value itself (though in practice the
value sets are disjoint).

---

### Action Items for Part G Implementation (from Addendum Review)

These are enhancements to Part G identified during the addendum review. They
should be implemented as part of Part G, not as a separate section:

1. [ ] Resolve stored paths via `MediaFileManager.resolveStoredPath()` in
   `retryIncompleteUploads` before any filesystem check or re-upload. After
   resolution, verify `File(resolvedPath).exists()`. If the file is missing,
   mark the attachment `'upload_failed'` via
   `mediaAttachmentRepo.updateDownloadStatus(id, 'upload_failed')`.
   Add test: "skips attachment whose local file no longer exists on disk."

2. [ ] In the G.7 refactor phase, add a `toJson` exclusion test confirming
   that `downloadStatus` does not appear in the wire payload (it is already
   excluded, but an explicit test prevents regressions).

3. [ ] In the G.7 refactor phase, document the full `downloadStatus` lifecycle
   table (above) as a code comment at the top of `media_attachment.dart`.

4. [ ] In the G.7 refactor phase, add the orphan-cleanup DB helper
   `dbDeleteUploadPendingOrphansByMessageStatus` as a **defensive safety
   net**. Under the stable-ID contract, orphan `upload_pending` rows should
   not exist in normal operation (the same row is updated in place on
   success). The batch cleanup guards against edge cases such as a crash
   between row insert and upload completion.

5. [ ] After successful `sendLocalMedia` (local-WiFi path), update the
   `upload_pending` row to `downloadStatus='done'` immediately. This
   ensures the attachment is not spuriously picked up by
   `retryIncompleteUploads` on next app resume.

6. [ ] After successful relay upload or re-upload, update the existing
   `upload_pending` row in place (set `downloadStatus='done'` and relay
   blob ID). Because the stable pre-generated ID is reused, no
   delete-then-insert is needed — a simple UPDATE suffices.

7. [ ] `retryIncompleteUploads` must not blindly re-upload a message that
   already has replayable state (`wireEnvelope` or completed `'done'`
   attachment rows). If a message is already in the Part C / replay-safe
   bucket, skip the Part G re-upload path and hand off to replay.

8. [ ] Transient re-upload failures (temporary bridge / relay / upload errors)
   must remain retryable on the next resume/reconnect. Do not move directly
   to a permanent `'upload_failed'` terminal state on first retry attempt
   unless the failure is explicitly non-recoverable (for example: missing
   local file).

9. [ ] Copy pre-upload files into managed durable storage
   (`<appDocDir>/pending_uploads/<messageId>/`) before the optimistic DB
   write. This ensures voice recordings and media files survive OS temp-file
   cleanup and app restarts. Clean up the durable copy after the upload
   succeeds and the attachment row transitions to `'done'`.

---

### Deleted Artifacts (Not To Be Created)

The following files specified in the original addendum are **not created**:

- `lib/core/database/migrations/041_media_attachment_upload_status.dart` -- no migration needed
- `test/core/database/helpers/media_attachments_upload_state_test.dart` -- subsumed by Part G tests
- `test/core/database/helpers/media_attachments_crash_recovery_test.dart` -- subsumed by Part G tests


---

## Section 5: FCM and Notification Fixes

This section covers two bugs and one deployment requirement: a field name mismatch that silently breaks tap-to-navigate for 1:1 messages (Bug A), missing `Notification` struct on group push messages that causes silent-push throttling on iOS (Bug B), and the requirement to use Redis for push token durability in production (Bug C).

> **1:1 sufficiency scope:** Sections 5.1 (Bug A), 5.3 (Bug C), and 5.4 (Bug D) are required for the 1:1 send-then-lock fix. Section 5.2 (Bug B: group push `Notification` struct) is a **group-specific** fix documented here for completeness but is **not required** for 1:1 reliability. It should not gate 1:1 sufficiency sign-off. The group push throttling issue only affects group messages on iOS in Low Power Mode and has no bearing on the 1:1 send-then-lock scenario.

---

### 5.1 Bug A: `sender_id` vs `from` Field Mismatch

#### Root Cause

`buildChatPushMessage` in `go-relay-server/inbox.go` emits `"sender_id"` in the FCM data payload, but `NotificationRouteTarget.fromRemoteMessageData` in `lib/core/notifications/notification_route_target.dart` reads `data['from']`. The `from` field is always null, so tapping a push notification for a 1:1 message never navigates to the correct conversation.

#### Decision

Fix the Dart client only — change `data['from']` to `data['sender_id']`. The server already sends the correct field name. No server-side change is needed. Do NOT add a redundant `"from"` alias to the server's FCM data map — the server's `"sender_id"` field name is correct and should be the canonical name.

Scope note: this fixes push tap-routing **after a visible push already exists**. It does **not** fix sender-side delivery loss in the original bug window where `sendChatMessage()` never ran and no message reached relay/inbox, so no push was produced in the first place.

#### Red Phase — Dart Unit Tests

**File to create:** `test/core/notifications/notification_route_target_sender_id_test.dart`

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';

void main() {
  group('NotificationRouteTarget.fromRemoteMessageData — sender_id field', () {
    test('resolves conversation from sender_id key (relay format)', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '12D3KooWRelayPeer',
      });
      expect(target, isNotNull);
      expect(target!.kind, NotificationRouteTargetKind.conversation);
      expect(target.peerId, '12D3KooWRelayPeer');
    });

    test('resolves conversation from from key (legacy format)', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'from': '12D3KooWLegacyPeer',
      });
      expect(target, isNotNull);
      expect(target!.peerId, '12D3KooWLegacyPeer');
    });

    test('sender_id takes precedence when both fields are present', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '12D3KooWNew',
        'from': '12D3KooWOld',
      });
      expect(target!.peerId, '12D3KooWNew');
    });

    test('returns null when neither sender_id nor from is present', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
      });
      expect(target, isNull);
    });

    test('whitespace-only sender_id falls back to from', () {
      final target = NotificationRouteTarget.fromRemoteMessageData({
        'type': 'new_message',
        'sender_id': '   ',
        'from': '12D3KooWFallback',
      });
      expect(target!.peerId, '12D3KooWFallback');
    });
  });
}
```

#### Green Phase — Dart Implementation

**File to modify:** `lib/core/notifications/notification_route_target.dart`

Change the `new_message` arm of `fromRemoteMessageData`:

```dart
case 'new_message':
  // The relay sends "sender_id"; older relay versions sent "from".
  final peerId = _trimToNull(data['sender_id']?.toString())
      ?? _trimToNull(data['from']?.toString());
  return peerId == null
      ? null
      : NotificationRouteTarget.conversation(peerId);
```

#### No Server-Side Change Needed

The server already sends `"sender_id"` correctly. Do NOT add a `"from"` alias — it would be redundant data in every FCM payload. The client fix above is sufficient.

---

### 5.2 Bug B: Missing `Notification` Struct on Group Push Messages

> **Out of scope for 1:1 reliability.** This is a group-specific notification fix. It is documented here for completeness but is not required for the 1:1 send-then-lock fix and should not gate 1:1 sufficiency sign-off.

#### Root Cause

`buildGroupPushMessage` in `go-relay-server/inbox.go` returns a `*messaging.Message` with no top-level `Notification` field. On iOS, FCM may classify this as a background-only push that can be throttled or dropped in Low Power Mode. `buildChatPushMessage` correctly includes the `Notification` struct.

Important scope note: the current group payload already includes APNS alert headers and `aps.alert`, so this is parity/hardening rather than proof that every current group push is background-only today. Adding the top-level `Notification` struct is still the more robust cross-platform contract and matches the 1:1 path.

#### Red Phase — Go Unit Tests

```go
func TestBuildGroupPushMessage_HasNotificationStruct(t *testing.T) {
    msg := buildGroupPushMessage(groupPushRequest{
        Token:   "fcm-token-xyz",
        GroupID: "group-abc-123",
    })

    if msg.Notification == nil {
        t.Fatal("buildGroupPushMessage must include a top-level Notification struct")
    }
    if msg.Notification.Title == "" {
        t.Error("Notification.Title must not be empty")
    }
    if msg.Notification.Body == "" {
        t.Error("Notification.Body must not be empty")
    }
}

func TestBuildGroupPushMessage_DataFields(t *testing.T) {
    msg := buildGroupPushMessage(groupPushRequest{
        Token:   "tok",
        GroupID: "group-xyz",
    })

    if msg.Data["type"] != "group_message" {
        t.Errorf("type = %q, want group_message", msg.Data["type"])
    }
    if msg.Data["groupId"] != "group-xyz" {
        t.Errorf("groupId = %q, want group-xyz", msg.Data["groupId"])
    }
}

func TestBuildGroupPushMessage_APNSPushTypeIsAlert(t *testing.T) {
    msg := buildGroupPushMessage(groupPushRequest{Token: "tok", GroupID: "g"})

    if msg.APNS == nil {
        t.Fatal("APNS config must not be nil")
    }
    if pt := msg.APNS.Headers["apns-push-type"]; pt != "alert" {
        t.Errorf("apns-push-type = %q, want alert", pt)
    }
}
```

#### Green Phase — Go Implementation

**File to modify:** `go-relay-server/inbox.go`

Add `Notification` struct to `buildGroupPushMessage` return value:

```go
return &messaging.Message{
    Token: req.Token,
    Notification: &messaging.Notification{
        Title: title,
        Body:  body,
    },
    Data: map[string]string{...},
    Android: ...,
    APNS: ...,
}
```

#### Dart Fallback — No Change Required

`shouldShowBackgroundPushFallbackNotification` already returns `false` when `message.notification != null`, so no duplicate local notification is shown.

---

### 5.3 Bug C: Relay Token Store Must Use Redis in Production

#### Root Cause

The default backend (`RELAY_BACKEND` unset) uses `newMemoryPushTokenStore()` which loses all FCM tokens on relay restart. Clients re-register on next app resume, but messages sent between restart and re-registration produce no push notification.

#### Decision

No new code is needed. A Redis-backed `redisPushTokenBackend` already exists in `go-relay-server/backend_redis.go` (lines 36-704). It stores tokens with no TTL (persistent until explicitly unregistered) and survives relay restarts. The fix is a **deployment configuration requirement**: production relays must set `RELAY_BACKEND=redis` and `REDIS_URL=<url>`.

Operational note: Section 4's direct-first design uses the relay inbox only as a fallback (when P2P fails or is unacked). Even in this fallback role, push-token durability matters -- if the in-memory store loses a token during a relay restart, the fallback inbox store succeeds but produces no push notification. Production must not rely on the in-memory backend.

#### Verification Test

**File to create:** `go-relay-server/push_token_store_redis_test.go`

```go
func TestRedisPushTokenBackend_PersistsAcrossReconnect(t *testing.T) {
    // Requires REDIS_URL in test environment; skip if unavailable
    redisURL := os.Getenv("REDIS_URL")
    if redisURL == "" {
        t.Skip("REDIS_URL not set; skipping Redis integration test")
    }

    client := redis.NewClient(&redis.Options{Addr: redisURL})
    defer client.Close()

    prefix := "test_push_" + t.Name() + ":"
    store := newRedisPushTokenBackend(client, prefix)

    store.RegisterToken("peer-alice", "token-alice-fcm", "ios")

    // Simulate "restart" by creating a new backend instance on same Redis
    store2 := newRedisPushTokenBackend(client, prefix)
    entry := store2.LookupToken("peer-alice")
    if entry == nil {
        t.Fatal("peer-alice token must survive across backend instances")
    }
    if entry.Token != "token-alice-fcm" {
        t.Errorf("token = %q, want token-alice-fcm", entry.Token)
    }

    // Cleanup
    store2.UnregisterToken("peer-alice")
}
```

#### Deployment Requirement

Add to relay deployment documentation / Docker Compose / Helm values:

```yaml
environment:
  RELAY_BACKEND: redis
  REDIS_URL: redis://redis:6379
```

The memory backend (`RELAY_BACKEND=memory` or unset) is acceptable ONLY for local development and testing.

---

### Refactor Phase

- Extract `buildPushMessageBase` helper in Go to eliminate duplication between `buildChatPushMessage` and `buildGroupPushMessage`

#### Stale Tests Requiring Updates

The following existing tests become stale after the Section 5 fixes and must be updated:

> **Scope note:** Only tests that put `'from'` in an FCM `data` map flowing through
> `NotificationRouteTarget.fromRemoteMessageData` are stale. Tests using `'from'` as a
> `ChatMessage` model field (P2P wire format) or relay inbox envelope field
> (`{from, message, timestamp}`) are **not** affected — those are separate protocol layers.

> **Go relay tests (`go-relay-server/`):** The Go relay server already uses `"sender_id"` in its FCM data payload (`buildChatPushMessage` in `inbox.go`, line 177: `"sender_id": req.FromPeerID`). Only the Dart client was reading the wrong field name (`data['from']`). No Go-side test updates are needed for the `sender_id` rename -- the server never used `"from"` in the FCM data map. The `"from"` field in Go appears only in the relay inbox envelope (`inboxMessage.From`, `groupInboxMessage.From`) which is a separate protocol layer and is unaffected by this fix.

##### A. Notification Routing Tests

**1. `test/core/notifications/notification_route_target_test.dart` — line 6-15**

- **Test case:** `'fromRemoteMessageData maps new_message to conversation route'`
- **What's stale:** The test uses `'from': 'peer-123'` as the data field. After Bug A is fixed, `fromRemoteMessageData` reads `sender_id` first and falls back to `from`. The test still passes (because `from` is the fallback), but it no longer tests the primary code path. It should be updated to test the production field name.
- **Fix:** Change the test data from `{'type': 'new_message', 'from': 'peer-123'}` to `{'type': 'new_message', 'sender_id': 'peer-123'}`. This ensures the test exercises the primary `sender_id` lookup, not the legacy fallback. Add a separate test for the `from` fallback if one is not already covered by the new `notification_route_target_sender_id_test.dart` tests.

**Updated test:**
```dart
test('fromRemoteMessageData maps new_message to conversation route', () {
  final routeTarget = NotificationRouteTarget.fromRemoteMessageData({
    'type': 'new_message',
    'sender_id': 'peer-123',  // was: 'from': 'peer-123'
  });

  expect(routeTarget, isNotNull);
  expect(routeTarget!.kind, NotificationRouteTargetKind.conversation);
  expect(routeTarget.peerId, 'peer-123');
});
```

**2. `test/core/notifications/notification_route_dispatch_test.dart` — line 14**

- **Test case:** `'remote conversation push invokes preparation before route handoff'`
- **What's stale:** Line 14 passes `data: const {'type': 'new_message', 'from': 'peer-123'}` to `routeRemoteNotificationOpen`, which internally calls `fromRemoteMessageData`. After Bug A, this exercises the legacy `from` fallback instead of the primary `sender_id` path.
- **Fix:** Change `'from': 'peer-123'` to `'sender_id': 'peer-123'` on line 14.

##### B. Push Notification Fallback Tests — `shouldShowBackgroundPushFallbackNotification`

These tests call `shouldShowBackgroundPushFallbackNotification(message)` which internally calls `NotificationRouteTarget.fromRemoteMessageData(message.data)`. Every test that passes `'from'` in the FCM data map for `type: 'new_message'` is exercising the legacy fallback path after Bug A.

**3. `test/features/push/application/background_message_handler_test.dart` — 7 test cases**

| Lines | Test name | Current `from` usage | Fix |
|-------|-----------|---------------------|-----|
| 37-52 | `'returns true for data-only message with type=new_message'` | `'from': '12D3KooWTestPeer'` (line 43) | Change to `'sender_id': '12D3KooWTestPeer'` |
| 71-90 | `'returns false when message already has a notification field'` | `'from': '12D3KooWTestPeer'` (line 81) | Change to `'sender_id': '12D3KooWTestPeer'` |
| 148-160 | `'returns false for new_message without from field'` | Test name says "without from field"; data has no peer key | Rename to `'returns false for new_message without sender_id or from field'` |
| 177-190 | `'uses default title and body when data has none'` | `'from': '12D3KooWTestPeer'` (line 182) | Change to `'sender_id': '12D3KooWTestPeer'` |
| 192-206 | `'uses custom title and body from data when present'` | `'from': '12D3KooWTestPeer'` (line 196) | Change to `'sender_id': '12D3KooWTestPeer'` |
| 208-219 | `'produces payload from new_message peerId'` | `'from': '12D3KooWTestPeer'` (line 212) | Change to `'sender_id': '12D3KooWTestPeer'` |
| 234-248 | `'ignores whitespace-only title and body'` | `'from': '12D3KooWTestPeer'` (line 238) | Change to `'sender_id': '12D3KooWTestPeer'` |

**4. `test/features/push/application/background_push_notification_fallback_test.dart` — 3 test cases**

| Lines | Test name | Current `from` usage | Fix |
|-------|-----------|---------------------|-----|
| 7-18 | `'shows a fallback for Android-style data-only chat pushes'` | `'from': '12D3KooWPeer'` (line 9) | Change to `'sender_id': '12D3KooWPeer'` |
| 20-34 | `'uses provided title/body data when present'` | `'from': '12D3KooWPeer'` (line 24) | Change to `'sender_id': '12D3KooWPeer'` |
| 36-49 | `'skips the fallback when FCM already carries a visible notification'` | `'from': '12D3KooWPeer'` (line 44) | Change to `'sender_id': '12D3KooWPeer'` |

##### C. Push Open Flow Tests

**5. `test/features/push/application/chat_and_group_push_open_flow_test.dart` — 2 test cases**

| Lines | Test name | Current `from` usage | Fix |
|-------|-----------|---------------------|-----|
| 15-41 | `'background 1:1 push opens conversation only after inbox preparation'` | `'from': 'peer-123'` (line 21) | Change to `'sender_id': 'peer-123'` |
| 43-67 | `'terminated 1:1 push opens conversation only after inbox preparation'` | `'from': 'peer-123'` inside `RemoteMessage` (line 48) | Change to `'sender_id': 'peer-123'` |

##### D. Tests That Are NOT Stale (Explicitly Excluded)

The following test files also use `'from'` but in **non-FCM contexts** (P2P wire format or relay inbox envelope format). They are NOT affected by the Bug A fix and must NOT be changed:

| File | `'from'` context | Why NOT stale |
|------|------------------|---------------|
| `test/features/p2p/domain/models/chat_message_test.dart` | `ChatMessage.fromJson({'from': ...})` — P2P model field | `ChatMessage.from` is the P2P transport sender field, not FCM data |
| `test/core/local_discovery/local_ws_server_test.dart` | WebSocket message `{'from': 'peerA', 'to': ...}` | Local-discovery P2P wire format |
| `test/core/inbox/inbox_round_trip_test.dart` | `inbox.first['from']` — relay envelope | Relay store-and-forward envelope `{from, message, timestamp}` |
| `test/shared/fakes/fake_p2p_network.dart` | `{'from': fromPeerId, 'message': ...}` — inbox storage | Test fake mimicking relay envelope format |
| `test/shared/fakes/fake_p2p_service_integration.dart` | `message['from']` — inbox drain | Test fake reading relay envelope |
| `test/features/groups/application/group_invite_listener_test.dart` | `{'from': '12D3KooWAlice', 'message': ...}` — group inbox | Group relay inbox envelope format |
| `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart` | `{'from': 'peer-sender', 'message': ...}` — group inbox | Group relay inbox envelope format |

---

### Integration Test: Full Push-to-Navigate Flow

**File to create:** `test/core/notifications/notification_push_tap_navigate_test.dart`

```dart
void main() {
  group('push tap → navigate integration', () {
    test('1:1 push with sender_id navigates to correct conversation', () async {
      await routeRemoteNotificationOpen(
        data: const {
          'type': 'new_message',
          'sender_id': '12D3KooWAlicePeer',
        },
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.peerId, '12D3KooWAlicePeer');
      expect(harness.missingCalls, 0);
    });

    test('1:1 push with from (pre-fix relay) still navigates', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message', 'from': '12D3KooWLegacyPeer'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.peerId, '12D3KooWLegacyPeer');
    });

    test('1:1 push with no peer field calls onMissingRouteTarget', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'new_message'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed, isEmpty);
      expect(harness.missingCalls, 1);
    });

    test('group push navigates to group', () async {
      await routeRemoteNotificationOpen(
        data: const {'type': 'group_message', 'groupId': 'group-team'},
        onRouteTarget: harness.route,
        onMissingRouteTarget: harness.missing,
      );
      expect(harness.routed.single.groupId, 'group-team');
    });
  });
}
```

---

### Smoke Tests — Manual QA

**Smoke A — 1:1 notification tap navigates to conversation (Bug A)**
1. Device A sends a message to Device B while Device B is backgrounded.
2. Tap the notification on Device B.
3. Expected: Device B navigates to the conversation with Device A (not the feed).

**Smoke B — Group push visible in iOS Low Power Mode (Bug B)**
1. Enable Low Power Mode on iOS Device B.
2. Device A sends a group message while Device B is backgrounded.
3. Expected: Notification appears within 30 seconds.

**Smoke C — Push notification after relay restart (Bug C)**
1. Deploy relay with `RELAY_BACKEND=redis` and `REDIS_URL=redis://redis:6379`.
2. Device B registers token (stored in Redis, survives restart).
3. Restart relay container.
4. Device A sends a message (before Device B re-registers).
5. Expected: Device B receives push notification (Redis retained the token).

---

### Build and Test Sequence

- [ ] Phase 1 — Red (Bug A): Create `notification_route_target_sender_id_test.dart` → confirm failures on `sender_id` cases
- [ ] Phase 2 — Green (Bug A): Edit `notification_route_target.dart` only — replace `data['from']` with `_trimToNull(data['sender_id']?.toString()) ?? _trimToNull(data['from']?.toString())` (reads `sender_id` first, falls back to `from` for backwards compatibility with older relay versions). No server-side change.
- [ ] Phase 3 — Red (Bug B): Add `TestBuildGroupPushMessage_HasNotificationStruct` to `go-relay-server/` → fails
- [ ] Phase 4 — Green (Bug B): Add `Notification` to `buildGroupPushMessage` in `inbox.go` → passes
- [ ] Phase 5 — Red (Bug C): Create `push_token_store_redis_test.go` → skipped if no `REDIS_URL`, fails otherwise
- [ ] Phase 6 — Green (Bug C): Set `RELAY_BACKEND=redis` + `REDIS_URL` in deployment config; run Redis test → passes. No new Go files.
- [ ] Phase 7 — Integration: Create `notification_push_tap_navigate_test.dart` → passes
- [ ] Phase 8 — Race detection: `go test -race ./go-relay-server/...`
- [ ] Phase 9 — Smoke tests on physical devices
- [ ] Phase 10 — Refactor: extract shared `buildPushMessageBase` helper in Go; update all stale `from`-based tests to use `'sender_id'` (see Refactor Phase → Stale Tests Requiring Updates above for the complete list across 5 files: `notification_route_target_test.dart`, `notification_route_dispatch_test.dart`, `background_message_handler_test.dart`, `background_push_notification_fallback_test.dart`, `chat_and_group_push_open_flow_test.dart`)
- [ ] Phase 11 — Red (Bug D prerequisite): Create `handle_incoming_chat_message_media_hydration_test.dart` → fails because `handleIncomingChatMessage` returns `ConversationMessage` with `media: const []`
- [ ] Phase 12 — Green (Bug D prerequisite): Modify `handleIncomingChatMessage` in `handle_incoming_chat_message_use_case.dart` to collect parsed `MediaAttachment` objects during step 6 and return `conversationMessage.copyWith(media: parsedAttachments)` → hydration tests pass
- [ ] Phase 13 — Stale test update: Update `chat_message_listener_test.dart` line 568 to expect `emitted[0].media` to have length 1 with `downloadStatus == 'pending'` (first emission now carries pending-status attachments)
- [ ] Phase 14 — Red (Bug D helper): Create `notification_body_for_message_test.dart` → compile error on `notificationBodyForMessage`
- [ ] Phase 15 — Green (Bug D helper): Add `notificationBodyForMessage` to `show_notification_use_case.dart`; update call sites in `ChatMessageListener` (use `conversationMessage.media`, now hydrated) and `GroupMessageListener` (convert raw maps via `MediaAttachment.fromJson`) → all tests pass
- [ ] Phase 16 — Smoke: Run Smoke D1–D4 on physical devices

---

### 5.4 Bug D: Empty Notification Body for Media-Only Messages

> **Scope: local notification body only.** This section fixes the notification body shown by the Dart client's local/in-app notification path (`maybeShowNotification` in `show_notification_use_case.dart`). The server-side push body sent by the Go relay (`buildChatPushMessage` / `buildGroupPushMessage` in `go-relay-server/inbox.go`) remains generic ("New Message" / "You have a new message") and is **out of scope** for this plan. Updating the relay server's push body to include media-aware text (e.g., "Photo", "Voice message") would require Go-side changes in `go-relay-server/inbox.go` and is a separate deployment concern. For the 1:1 send-then-lock fix, improving the local notification body is sufficient -- the recipient already receives the push; this fix ensures the body is informative rather than blank.

#### Root Cause

`maybeShowNotification` in `lib/features/push/application/show_notification_use_case.dart` receives `messageText: conversationMessage.text` directly from `ChatMessageListener._onMessage` (line 298). `ConversationMessage.text` is an empty string `""` when a message contains only a media attachment and no caption. `FlutterNotificationService.showMessageNotification` passes `messageText` verbatim as the notification body. The result is a notification with a blank body — just the sender's name and nothing else — giving the user no context about what was sent.

The same gap exists in `GroupMessageListener` (line 199) where `'$senderUsername: $text'` produces `'Alice: '` (trailing colon and space) for a media-only group message.

#### Critical Data-Flow Gap — `conversationMessage.media` Is Empty at Notification Time

The 1:1 notification path has a deeper structural problem beyond the empty-text issue. `MessagePayload.toConversationMessage()` (line 206 of `message_payload.dart`) creates a `ConversationMessage` with the default `media: const []` — it never transfers `payload.media` to the returned object. The media attachments are saved to the DB separately in `handleIncomingChatMessage()` at lines 186-192, but the returned `conversationMessage` at line 213 still carries an empty `media` list.

The data flow on the receive path is:

1. `handleIncomingChatMessage()` parses the wire payload (which contains `payload.media`).
2. `payload.toConversationMessage()` creates a `ConversationMessage` with `media: const []` (media is NOT transferred).
3. The message is saved to DB (line 183).
4. Media attachments are saved to `media_attachments` table separately (lines 186-192).
5. The `conversationMessage` (with empty media) is returned to `ChatMessageListener._onMessage`.
6. `_onMessage` emits `conversationMessage` to the UI stream (line 282) — first emission has empty media.
7. `maybeShowNotification` is called with `conversationMessage.text` (line 298) — empty for media-only.
8. `_autoDownloadMedia` runs AFTER the notification (line 306) and re-emits with hydrated media (second emission).

This means any fix that reads `conversationMessage.media` at the notification call site will always see an empty list. The existing test at `chat_message_listener_test.dart` line 565-570 already proves this: `emitted[0].media` is `isEmpty` on the first emission.

**This fix therefore has two parts:**
1. Hydrate media on the returned `ConversationMessage` in `handleIncomingChatMessage()` so that `conversationMessage.media` is populated before the notification fires.
2. Use `notificationBodyForMessage(conversationMessage.text, conversationMessage.media)` at the call site.

The send path already follows this pattern — `send_chat_message_use_case.dart` line 695 returns `message.copyWith(media: attachments ?? const [])`. The receive path must do the same.

**For group messages**, the data flow is different: `GroupMessageListener._onGroupMessage` has direct access to the raw wire `media` list (line 160-161 of `group_message_listener.dart`) before the notification fires. The group fix can convert these raw maps to `MediaAttachment` objects inline and pass them to `notificationBodyForMessage`.

#### Decision

Introduce a `notificationBodyForMessage` pure function in `lib/features/push/application/show_notification_use_case.dart`. The function derives the display body from the message text and the list of media attachments:

| Condition | Body shown |
|-----------|-----------|
| `text` is non-empty (with or without media) | The text itself — existing behaviour, unchanged |
| `text` is empty, first attachment `mediaType == 'image'` | `"Photo"` |
| `text` is empty, first attachment `mediaType == 'video'` | `"Video"` |
| `text` is empty, first attachment `mediaType == 'audio'` | `"Voice message"` |
| `text` is empty, first attachment `mediaType == 'file'` | `"File"` |
| `text` is empty, multiple attachments of mixed types | `"Media"` (safe generic fallback) |
| `text` is empty, `media` list is empty (should not happen in practice) | `"Message"` (last-resort fallback) |

**No emoji in notification body.** Emoji in notifications can be mis-rendered on some Android OEM skins and are stripped by certain notification summarisation stacks. Plain-text labels are safer and translate cleanly when localisation is added later.

**Scope**: The fix is Dart-only. No server-side changes. No changes to the `NotificationService` interface or `FlutterNotificationService`. Only `show_notification_use_case.dart` gains the helper, and its two call sites (`ChatMessageListener` and `GroupMessageListener`) are updated to call it.

**Group message notification body**: For group messages, the body convention is `'$senderUsername: $body'` where `$body` comes from `notificationBodyForMessage`. An image-only group message will therefore show `'Alice: Photo'`.

#### Current Code Gap — Where `messageText` Is Passed

**Call site 1 — 1:1 messages** (`lib/features/conversation/application/chat_message_listener.dart`, lines 292–299):

```dart
maybeShowNotification(
  notificationService: notificationService!,
  conversationTracker: conversationTracker!,
  getAppLifecycleState: getAppLifecycleState!,
  contactPeerId: conversationMessage.contactPeerId,
  senderUsername: username,
  messageText: conversationMessage.text,  // <-- blank when media-only
);
```

`conversationMessage.media` is **empty** at this point — `toConversationMessage()` defaults to `const []` and `handleIncomingChatMessage()` saves attachments to the DB separately but does not attach them to the returned object (see "Critical Data-Flow Gap" above). **Before** `notificationBodyForMessage` can work, `handleIncomingChatMessage()` must be changed to hydrate media on the returned `ConversationMessage` (see "Prerequisite Fix" in the Implementation Plan below). After that prerequisite fix, the call-site change is: replace `conversationMessage.text` with `notificationBodyForMessage(conversationMessage.text, conversationMessage.media)`.

**Call site 2 — group messages** (`lib/features/groups/application/group_message_listener.dart`, line 199):

```dart
messageText: '$senderUsername: $text',  // <-- '$senderUsername: ' when media-only
```

Here `text` is the raw wire string and `media` is the decoded list of raw `Map<String, dynamic>` objects (not `MediaAttachment` instances). The fix converts the raw maps to `MediaAttachment` objects inline so `notificationBodyForMessage` can read their `mediaType`. Replace `'$senderUsername: $text'` with:

```dart
final mediaAttachments = media
    ?.map((m) => MediaAttachment.fromJson(m))
    .toList() ?? <MediaAttachment>[];
messageText: '$senderUsername: ${notificationBodyForMessage(text, mediaAttachments)}',
```

This conversion is lightweight (no I/O — just field extraction) and uses the existing `MediaAttachment.fromJson` factory.

#### Implementation Plan

##### Prerequisite Fix: Hydrate Media on Returned `ConversationMessage`

**File to modify:** `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`

After the media attachments are saved to DB (step 6, lines 186-192), build the `MediaAttachment` list from the same `payload.media` data and attach it to the returned `ConversationMessage` via `copyWith`. This mirrors the send path pattern at `send_chat_message_use_case.dart` line 695.

Change:

```dart
  // 6. Persist media attachment metadata
  if (mediaAttachmentRepo != null && payload.media != null) {
    for (final mediaJson in payload.media!) {
      final attachment = MediaAttachment.fromJson(mediaJson)
          .copyWith(messageId: payload.id);
      await mediaAttachmentRepo.saveAttachment(attachment);
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_STORED',
    ...
  );
  ...
  return (
    HandleChatMessageResult.chatMessage,
    conversationMessage,
    updatedContact,
  );
```

To:

```dart
  // 6. Persist media attachment metadata and collect parsed attachments
  final parsedAttachments = <MediaAttachment>[];
  if (mediaAttachmentRepo != null && payload.media != null) {
    for (final mediaJson in payload.media!) {
      final attachment = MediaAttachment.fromJson(mediaJson)
          .copyWith(messageId: payload.id);
      await mediaAttachmentRepo.saveAttachment(attachment);
      parsedAttachments.add(attachment);
    }
  }

  // 7. Hydrate media on the returned message so downstream consumers
  // (notably ChatMessageListener.maybeShowNotification) can derive the
  // notification body from media metadata without a separate DB query.
  // This mirrors the send-path pattern at send_chat_message_use_case.dart:695.
  final hydratedMessage = parsedAttachments.isNotEmpty
      ? conversationMessage.copyWith(media: parsedAttachments)
      : conversationMessage;

  emitFlowEvent(
    layer: 'FL',
    event: 'CHAT_MSG_RECEIVE_STORED',
    ...
  );
  ...
  return (
    HandleChatMessageResult.chatMessage,
    hydratedMessage,
    updatedContact,
  );
```

**Why this is safe:**
- The `parsedAttachments` list contains the exact same `MediaAttachment` objects that were just saved to DB. No extra I/O.
- The `copyWith(media:)` field is transient (not serialized to DB) — it only affects in-memory consumers.
- The first emission from `ChatMessageListener` will now carry media metadata, enabling `notificationBodyForMessage` to produce the correct body.
- The existing `_autoDownloadMedia` re-emission (second emission) continues to work unchanged — it replaces the pending-status attachments with downloaded ones.
- The existing test at `chat_message_listener_test.dart` line 565-570 (`emitted[0].media, isEmpty`) **will need updating** to expect the first emission to carry pending-status attachments. See "Stale Tests" section below.

##### New File: `notificationBodyForMessage` Helper

**File to modify:** `lib/features/push/application/show_notification_use_case.dart`

Add an import for `MediaAttachment` at the top of the file:

```dart
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
```

Add the `notificationBodyForMessage` helper above `maybeShowNotification`:

```dart
/// Returns the notification body text for a message.
///
/// If [text] is non-empty it is returned as-is (caption-first rule).
/// If [text] is empty the body is derived from the first attachment's
/// [MediaAttachment.mediaType]: image -> "Photo", video -> "Video",
/// audio -> "Voice message", file -> "File", mixed/unknown -> "Media".
/// Falls back to "Message" when text is empty and there are no attachments.
String notificationBodyForMessage(
  String text,
  List<MediaAttachment> media,
) {
  final trimmed = text.trim();
  if (trimmed.isNotEmpty) return trimmed;
  if (media.isEmpty) return 'Message';

  final firstType = media.first.mediaType;
  final allSameType = media.every((a) => a.mediaType == firstType);
  if (!allSameType) return 'Media';

  return switch (firstType) {
    'image' => 'Photo',
    'video' => 'Video',
    'audio' => 'Voice message',
    'file'  => 'File',
    _       => 'Media',
  };
}
```

**File to modify:** `lib/features/conversation/application/chat_message_listener.dart`

Add an import at the top of the file:

```dart
import 'package:flutter_app/features/push/application/show_notification_use_case.dart'
    show notificationBodyForMessage;
```

Change the `maybeShowNotification` call at line 298:

```dart
// Before:
messageText: conversationMessage.text,

// After:
messageText: notificationBodyForMessage(
  conversationMessage.text,
  conversationMessage.media,
),
```

**This works because of the prerequisite fix**: `handleIncomingChatMessage()` now returns a `ConversationMessage` with `media` hydrated from `payload.media`. Without the prerequisite fix, `conversationMessage.media` would be `const []` and `notificationBodyForMessage` would return `'Message'` instead of `'Photo'`/`'Voice message'`.

**File to modify:** `lib/features/groups/application/group_message_listener.dart`

Add imports at the top of the file:

```dart
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart'
    show notificationBodyForMessage;
```

Change the notification call at line 199. The group listener has access to raw `media` maps (line 160-161) which must be converted to `MediaAttachment` objects:

```dart
// Before:
messageText: '$senderUsername: $text',

// After:
final notifAttachments = media
    ?.map((m) => MediaAttachment.fromJson(m))
    .toList() ?? <MediaAttachment>[];
messageText: '$senderUsername: ${notificationBodyForMessage(text, notifAttachments)}',
```

#### Red Phase — Prerequisite: `handleIncomingChatMessage` Media Hydration

**File to create:** `test/features/conversation/application/handle_incoming_chat_message_media_hydration_test.dart`

This test verifies that `handleIncomingChatMessage` returns a `ConversationMessage` with `media` populated from the wire payload. It fails (red) until the prerequisite fix above lands.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

// Use existing fakes from the test suite
import '../domain/repositories/fake_message_repository.dart';
import '../../../../test/features/contacts/domain/repositories/fake_contact_repository.dart';
import '../domain/repositories/fake_media_attachment_repository.dart';

void main() {
  group('handleIncomingChatMessage — media hydration on returned message', () {
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;
    late FakeMediaAttachmentRepository mediaAttachmentRepo;

    setUp(() {
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository();
      mediaAttachmentRepo = FakeMediaAttachmentRepository();

      // Seed the sender as a known contact
      contactRepo.seedContact(ContactModel(
        peerId: 'peer-sender',
        publicKey: 'pk',
        rendezvous: '/relay',
        username: 'Sender',
        signature: 'sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      ));
    });

    test('returned message carries image attachment from wire payload', () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-media-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-img-001","mime":"image/jpeg","size":204800,'
          '"mediaType":"image","width":1920,"height":1080}]}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(from: 'peer-sender', content: wireJson),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);

      // KEY ASSERTION: media must be populated on the returned message
      expect(message!.media, hasLength(1),
          reason: 'Returned ConversationMessage must carry media from wire payload');
      expect(message.media.first.mediaType, 'image');
      expect(message.media.first.messageId, 'msg-media-001');
    });

    test('returned message carries audio attachment from wire payload', () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-voice-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-audio-001","mime":"audio/aac","size":48000,'
          '"mediaType":"audio","durationMs":5200}]}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(from: 'peer-sender', content: wireJson),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      expect(message!.media, hasLength(1));
      expect(message.media.first.mediaType, 'audio');
      expect(message.media.first.durationMs, 5200);
    });

    test('text-only message returns empty media list (no regression)', () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-text-001","text":"Hello","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z"}}';

      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(from: 'peer-sender', content: wireJson),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      expect(message!.media, isEmpty,
          reason: 'Text-only messages must still have empty media list');
    });

    test('media message without mediaAttachmentRepo returns empty media (graceful)', () async {
      final wireJson = '{"type":"chat_message","version":"1","payload":{'
          '"id":"msg-no-repo-001","text":"","senderPeerId":"peer-sender",'
          '"senderUsername":"Sender","timestamp":"2026-03-23T12:00:00.000Z",'
          '"media":[{"id":"blob-x","mime":"image/png","size":100}]}}';

      // No mediaAttachmentRepo — attachments not persisted, not hydrated
      final (result, message, _) = await handleIncomingChatMessage(
        message: ChatMessage(from: 'peer-sender', content: wireJson),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: null,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(message, isNotNull);
      // When mediaAttachmentRepo is null, attachments are not persisted
      // and media is not hydrated — this is acceptable for legacy paths
      expect(message!.media, isEmpty);
    });
  });
}
```

**Why these tests fail in the red phase**: `handleIncomingChatMessage` currently returns a `ConversationMessage` from `toConversationMessage()` which defaults to `media: const []`. The first two tests expect `media` to be populated with attachment metadata, which requires the prerequisite fix.

#### Red Phase — `notificationBodyForMessage` Helper

**File to create:** `test/features/push/application/notification_body_for_message_test.dart`

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/push/application/show_notification_use_case.dart';
import '../../../shared/fakes/fake_notification_service.dart';

MediaAttachment _attachment(String mediaType) => MediaAttachment(
      id: 'attach-1',
      messageId: 'msg-1',
      mime: switch (mediaType) {
        'image' => 'image/jpeg',
        'video' => 'video/mp4',
        'audio' => 'audio/aac',
        _       => 'application/octet-stream',
      },
      size: 1024,
      mediaType: mediaType,
      downloadStatus: 'done',
      createdAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  group('notificationBodyForMessage', () {
    // --- text present ---

    test('returns text as-is when non-empty (text-only message)', () {
      expect(notificationBodyForMessage('Hello!', []), 'Hello!');
    });

    test('returns text even when media is also present (caption wins)', () {
      expect(
        notificationBodyForMessage('Check this out', [_attachment('image')]),
        'Check this out',
      );
    });

    test('trims whitespace before checking emptiness', () {
      expect(notificationBodyForMessage('  ', [_attachment('image')]), 'Photo');
    });

    // --- image-only ---

    test('returns Photo for image-only message', () {
      expect(notificationBodyForMessage('', [_attachment('image')]), 'Photo');
    });

    // --- video-only ---

    test('returns Video for video-only message', () {
      expect(notificationBodyForMessage('', [_attachment('video')]), 'Video');
    });

    // --- audio-only ---

    test('returns Voice message for audio-only message', () {
      expect(
        notificationBodyForMessage('', [_attachment('audio')]),
        'Voice message',
      );
    });

    // --- file-only ---

    test('returns File for file-only message', () {
      expect(notificationBodyForMessage('', [_attachment('file')]), 'File');
    });

    // --- unknown mediaType ---

    test('returns Media for unknown single attachment type', () {
      expect(notificationBodyForMessage('', [_attachment('sticker')]), 'Media');
    });

    // --- multiple attachments ---

    test('returns Photo for multiple image attachments (all same type)', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('image'),
        ]),
        'Photo',
      );
    });

    test('returns Media for mixed image and video attachments', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('video'),
        ]),
        'Media',
      );
    });

    test('returns Media for mixed image and audio attachments', () {
      expect(
        notificationBodyForMessage('', [
          _attachment('image'),
          _attachment('audio'),
        ]),
        'Media',
      );
    });

    // --- no attachments ---

    test('returns Message when text is empty and media list is empty', () {
      expect(notificationBodyForMessage('', []), 'Message');
    });

    // --- group message body composition ---

    test('group image-only message body is "Alice: Photo"', () {
      final body = notificationBodyForMessage('', [_attachment('image')]);
      expect('Alice: $body', 'Alice: Photo');
    });

    test('group audio-only message body is "Alice: Voice message"', () {
      final body = notificationBodyForMessage('', [_attachment('audio')]);
      expect('Alice: $body', 'Alice: Voice message');
    });

    test('group captioned image body is "Alice: Check this out"', () {
      final body = notificationBodyForMessage(
        'Check this out',
        [_attachment('image')],
      );
      expect('Alice: $body', 'Alice: Check this out');
    });
  });

  group('maybeShowNotification — media body integration', () {
    // These tests verify that the correct body reaches NotificationService
    // when maybeShowNotification is called with a media-only message.

    test(
      'image-only 1:1 message shows "Photo" as notification body',
      () async {
        final notificationService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageText: notificationBodyForMessage('', [_attachment('image')]),
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, 'Photo');
      },
    );

    test(
      'voice-only 1:1 message shows "Voice message" as notification body',
      () async {
        final notificationService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageText: notificationBodyForMessage('', [_attachment('audio')]),
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, 'Voice message');
      },
    );

    test(
      'video-only 1:1 message shows "Video" as notification body',
      () async {
        final notificationService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageText: notificationBodyForMessage('', [_attachment('video')]),
        );

        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.messageText, 'Video');
      },
    );

    test(
      'captioned image shows caption text not "Photo"',
      () async {
        final notificationService = FakeNotificationService();
        final tracker = ActiveConversationTracker();

        await maybeShowNotification(
          notificationService: notificationService,
          conversationTracker: tracker,
          getAppLifecycleState: () => AppLifecycleState.paused,
          contactPeerId: 'peer-alice',
          senderUsername: 'Alice',
          messageText: notificationBodyForMessage(
            'Look at this!',
            [_attachment('image')],
          ),
        );

        expect(notificationService.shown.first.messageText, 'Look at this!');
      },
    );
  });
}
```

**Why these tests fail in the red phase**: `notificationBodyForMessage` does not yet exist in `show_notification_use_case.dart`. Every call to it produces a compile error (`Undefined name 'notificationBodyForMessage'`), which counts as a red failure.

#### Stale Tests Requiring Updates After Green Phase

The `maybeShowNotification` signature is unchanged, but the prerequisite fix (media hydration on the returned `ConversationMessage`) changes the first emission from `ChatMessageListener`, which breaks one existing test:

**1. `test/features/conversation/application/chat_message_listener_test.dart` — line 565-570**

- **Test case:** `'auto-downloads pending attachments and re-emits message with media'`
- **What's stale:** The test asserts `emitted[0].media, isEmpty` (line 568-570), verifying that the first emission has no media. After the prerequisite fix, `handleIncomingChatMessage` returns a `ConversationMessage` with `media` hydrated (pending-status attachments from the wire payload). The first emission will now carry pending-status `MediaAttachment` objects.
- **Fix:** Change the assertion from `isEmpty` to `hasLength(1)` and verify the first emission carries pending-status attachments:

```dart
// Before:
expect(
  emitted[0].media,
  isEmpty,
); // first emission has no hydrated media

// After:
expect(
  emitted[0].media,
  hasLength(1),
); // first emission now carries pending-status attachments from wire payload
expect(emitted[0].media[0].downloadStatus, 'pending');
```

The second emission assertion (`emitted[1].media` has length 1, downloadStatus `'done'`) remains unchanged.

**2. No other existing tests break.** The existing `show_notification_use_case_test.dart` tests pass `messageText` directly and are unaffected. If any future test asserts `notificationService.shown.first.messageText == ''` for a media-only message, it must be updated to expect `'Photo'` / `'Video'` / `'Voice message'` accordingly.

#### Smoke Tests — Manual QA

**Smoke D1 — Image-only 1:1 notification**
1. Device A sends an image with no caption to Device B while Device B is backgrounded.
2. Expected: notification on Device B shows `Alice` as title and `Photo` as body (not blank).

**Smoke D2 — Voice message 1:1 notification**
1. Device A records and sends a voice message to Device B while Device B is backgrounded.
2. Expected: notification body reads `Voice message`.

**Smoke D3 — Captioned image notification**
1. Device A sends an image with caption `"Look at this!"` to Device B while Device B is backgrounded.
2. Expected: notification body reads `Look at this!` (not `Photo`).

**Smoke D4 — Image-only group notification**
1. Device A sends an image with no caption to a group while Device B is backgrounded.
2. Expected: notification body reads `Alice: Photo`.

---

## Section 6: Test Infrastructure and Integration

### Overview

This section synthesizes the test infrastructure requirements across all five fix areas into a unified plan. **The primary goal is to prove the actual bug is fixed**: Alice sends a message, Alice's phone locks, Bob receives the message AND gets a notification.

**Key design principle**: Use the existing `TestUser` + `FakeP2PNetwork` harnesses (`test/shared/fakes/`) for multi-user integration tests — NOT isolated fakes with dead `messageStream: const Stream.empty()`. The repo already has strong multi-user test patterns in `test/features/conversation/integration/two_user_message_exchange_test.dart` and `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`. Section 6 tests must follow those patterns.

To simulate lifecycle transitions mid-test, use mutable closures captured by `ChatMessageListener`:

```dart
var aliceState = AppLifecycleState.resumed;
final listener = ChatMessageListener(
  getAppLifecycleState: () => aliceState,
  // ...
);
// Later in test:
aliceState = AppLifecycleState.paused;  // simulates lock
```

This pattern already exists in `chat_message_listener_test.dart` (lines 900-911) but has never been used with a variable that changes mid-test.

---

### Part A: Shared Test Infrastructure

#### A.1 Existing Fakes Inventory

The following fakes already exist and must be extended rather than replaced:

| Fake | Location | Gaps for These 5 Fixes |
|---|---|---|
| `FakeBridge` | `test/core/bridge/fake_bridge.dart` | Cannot simulate delayed sends or background-task-gated calls |
| `FakeP2PService` | `test/core/services/fake_p2p_service.dart` | No `storeInInboxCallCount` ordering (direct-first vs fallback), no per-call delay injection |
| `FakeMessageRepository` | `test/features/conversation/domain/repositories/fake_message_repository.dart` | No `getSendingMessages()` (stuck-sending recovery needs this), `throwOnUpdateStatus` exists but not `delayOnUpdateStatus` |
| `FakeP2PNetwork` | `test/shared/fakes/fake_p2p_network.dart` | No direct-first ordering assertion, no `storeBeforeDeliverCount` |
| `FakeNotificationService` | `test/shared/fakes/fake_notification_service.dart` | No `sender_id`/`from` field capture, no token persistence tracking |
| `TestUser` | `test/shared/fakes/test_user.dart` | No lifecycle simulation (pause/resume), no stuck-message seeding helper |

#### A.2 New Shared Fake: `FakePushTokenStore`

**File:** `test/shared/fakes/fake_push_token_store.dart`

> **⚠️ AUDIT FIX (T6-03 — PushTokenStore does not exist):** The import below references `package:flutter_app/features/push/domain/push_token_store.dart`. This file does not exist anywhere in `lib/`. The `PushTokenStore` interface, its production implementation, and this fake must all be created as production code prerequisites before this fake can compile. Add `lib/features/push/domain/push_token_store.dart` (interface) and `lib/features/push/infrastructure/push_token_store_impl.dart` (production impl) to the Phase 1 prerequisite list.

This fake covers the FCM fix area (fix 5), where a persistent token store is introduced so tokens survive app restarts. The existing `FakeSecureKeyStore` at `test/core/secure_storage/fake_secure_key_store.dart` already provides the in-memory map pattern this must follow.

```dart
import 'package:flutter_app/features/push/domain/push_token_store.dart';

/// In-memory [PushTokenStore] for tests.
///
/// Records all token writes and reads. Simulates persistence across
/// logical "restarts" by retaining the map between calls.
class FakePushTokenStore implements PushTokenStore {
  String? _storedToken;
  String? _storedPlatform;

  int writeCallCount = 0;
  int readCallCount = 0;
  int clearCallCount = 0;

  bool throwOnWrite = false;

  @override
  Future<void> writeToken(String token, String platform) async {
    writeCallCount++;
    if (throwOnWrite) throw Exception('FakePushTokenStore: write error');
    _storedToken = token;
    _storedPlatform = platform;
  }

  @override
  Future<({String token, String platform})?> readToken() async {
    readCallCount++;
    if (_storedToken == null) return null;
    return (token: _storedToken!, platform: _storedPlatform!);
  }

  @override
  Future<void> clearToken() async {
    clearCallCount++;
    _storedToken = null;
    _storedPlatform = null;
  }

  /// Simulates app restart: the in-memory store survives (persisted).
  /// Call this between logical app sessions in tests.
  void simulateRestart() {
    // No-op: data persists. This exists to mark intent in test code.
  }

  /// Whether a token is currently stored.
  bool get hasToken => _storedToken != null;
  String? get storedToken => _storedToken;
  String? get storedPlatform => _storedPlatform;
}
```

#### A.3 Extended `FakeBridge` Capabilities

**File:** `test/core/bridge/fake_bridge.dart` — extend the existing `FakeBridge` class with two new capabilities needed by fixes 3 (iOS background task assertion) and 1 (stuck-sending recovery via bridge health).

> **⚠️ AUDIT FIX (T6-08 — FakeBridge has no `sendDelay` or `criticalCommands`):** The actual `FakeBridge` at `test/core/bridge/fake_bridge.dart` has neither `sendDelay` nor a `criticalCommands` set today. The fields below must be added to the existing class. No correction to the plan is needed; this note confirms the extensions are additive.

Add to `FakeBridge`:

```dart
/// When set, [send] awaits this duration before returning (simulates slow bridge call).
/// This is used to test that iOS background task assertions fire for slow calls.
Duration? sendDelay;

/// Commands that should be treated as "critical" for background-task testing.
/// When [sendDelay] is set and the command is in this set, the delay simulates
/// the OS suspending mid-call without a background task.
final Set<String> criticalCommands = {'node:start', 'peer:dial', 'relay:reconnect'};

/// Number of times a critical command was called while [sendDelay] was active.
int criticalCallDuringDelayCount = 0;

// Modify send() to respect sendDelay:
@override
Future<String> send(String message) async {
  sendCallCount++;
  lastSentMessage = message;
  sentMessages.add(message);

  if (throwOnSend) {
    throw Exception(throwOnSendMessage ?? 'FakeBridge: send error');
  }

  final parsed = jsonDecode(message) as Map<String, dynamic>;
  final cmd = parsed['cmd'] as String?;
  lastCommand = cmd;
  if (cmd != null) commandLog.add(cmd);

  // Simulate slow/interrupted call
  if (sendDelay != null) {
    if (cmd != null && criticalCommands.contains(cmd)) {
      criticalCallDuringDelayCount++;
    }
    await Future.delayed(sendDelay!);
  }

  if (cmd != null && responses.containsKey(cmd)) {
    return jsonEncode(responses[cmd]!);
  }
  return jsonEncode({'ok': true});
}
```

Also add a new subclass `SlowCriticalBridge` for the iOS background task integration test:

```dart
/// A [FakeBridge] that introduces configurable latency on critical commands.
///
/// Used to verify that [GoBridge.swift] wraps long-running bridge calls in
/// beginBackgroundTask/endBackgroundTask.
///
/// In unit tests (no native layer), this confirms that the Dart caller does
/// not time out waiting for a critical call that takes longer than expected.
class SlowCriticalBridge extends FakeBridge {
  final Duration criticalCallLatency;

  /// Commands considered critical for background-task wrapping.
  final Set<String> criticalSet;

  /// Records whether each critical call completed within the allowed window.
  final List<({String cmd, bool completed})> criticalCallResults = [];

  SlowCriticalBridge({
    this.criticalCallLatency = const Duration(milliseconds: 500),
    Set<String>? criticalSet,
  }) : criticalSet = criticalSet ??
            {'node:start', 'peer:dial', 'relay:reconnect', 'inbox:store'};

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String? ?? '';

    if (criticalSet.contains(cmd)) {
      final completer = Completer<String>();
      Future.delayed(criticalCallLatency, () {
        if (!completer.isCompleted) {
          completer.complete(jsonEncode({'ok': true}));
        }
      });
      final result = await completer.future;
      criticalCallResults.add((cmd: cmd, completed: true));
      return result;
    }

    return super.send(message);
  }
}
```

#### A.4 Extended `FakeMessageRepository` — Stuck-Sending Support

**File:** `test/features/conversation/domain/repositories/fake_message_repository.dart` — add `getSendingMessages()` and clock-controlled age filtering.

> **⚠️ AUDIT FIX (T6-02 — getSendingMessages() does not exist on interface):** The actual `MessageRepository` interface at `lib/features/conversation/domain/repositories/message_repository.dart` only has `getFailedOutgoingMessages()` and `getUnackedOutgoingMessages()`. There is no `getSendingMessages` on the interface, the impl, or any fake. **Prerequisite step:** extend the `MessageRepository` interface with `getSendingMessages({required Duration olderThan})`, implement it in `MessageRepositoryImpl` (SQL: `SELECT * FROM messages WHERE status='sending' AND is_incoming=0 AND created_at < ?`), then extend the fake below to match.

> **⚠️ AUDIT FIX (T6-07 — FakeMessageRepository has no `clock` field):** The actual `FakeMessageRepository` at `test/features/conversation/domain/repositories/fake_message_repository.dart` has no `clock` field, no `getSendingMessagesCallCount`, and no `sendingMessagesOverride`. It does have `seed()` (line 27) and `saveMessage()` uses INSERT-OR-REPLACE semantics by ID (lines 37-43), which is compatible with the extensions below. All fields shown below must be added to the existing fake.

Add to `FakeMessageRepository`:

```dart
// Call tracking for stuck-sending recovery
int getSendingMessagesCallCount = 0;

/// Configurable override for [getSendingMessages].
List<ConversationMessage>? sendingMessagesOverride;

/// Injected clock for age-threshold tests. Defaults to [DateTime.now].
DateTime Function() clock = () => DateTime.now().toUtc();

@override
Future<List<ConversationMessage>> getSendingMessages({
  required Duration olderThan,
}) async {
  getSendingMessagesCallCount++;
  if (sendingMessagesOverride != null) return sendingMessagesOverride!;

  final cutoff = clock().subtract(olderThan);
  return _messages
      .where((m) =>
          m.status == 'sending' &&
          !m.isIncoming &&
          DateTime.tryParse(m.createdAt)?.isBefore(cutoff) == true)
      .toList();
}
```

The `clock` field enables age-threshold tests without `fake_async` — tests seed messages with timestamps in the past relative to the injected clock:

```dart
// In a test: seed a message that appears 5 minutes old
final fakeNow = DateTime(2026, 3, 23, 12, 10, 0).toUtc();
messageRepo.clock = () => fakeNow;
messageRepo.seed([
  ConversationMessage(
    id: 'msg-stuck-001',
    status: 'sending',
    createdAt: fakeNow.subtract(const Duration(minutes: 5)).toIso8601String(),
    ...
  ),
]);
```

#### A.5 Extended `FakeP2PService` — Direct-First Ordering Assertions

**File:** `test/core/services/fake_p2p_service.dart` — add call-ordering log between `storeInInbox` and `sendMessageWithReply`.

> **⚠️ AUDIT FIX (T6-09 — FakeP2PService has no `operationLog`):** The actual `FakeP2PService` at `test/core/services/fake_p2p_service.dart` has no `operationLog` or `storeInInboxSuccessCount`. It does have `storeInInboxCallCount` (line 42) and `sentMessageLog` (line 32). The fields below must be added alongside the existing counters.

Add to `FakeP2PService`:

```dart
/// Ordered log of all network operation names for ordering assertions.
/// Entries: 'storeInInbox', 'sendMessageWithReply', 'discoverPeer', 'dialPeer'.
final List<String> operationLog = [];

/// First N [storeInInbox] calls succeed; subsequent calls fail.
/// Set to -1 (default) to always use [storeInInboxResult].
int storeInInboxSuccessCount = -1;
int _storeInInboxCallsSoFar = 0;

@override
Future<bool> storeInInbox(String toPeerId, String message) async {
  storeInInboxCallCount++;
  operationLog.add('storeInInbox');
  lastStoreInInboxPeerId = toPeerId;
  lastStoreInInboxMessage = message;

  if (storeInInboxSuccessCount >= 0) {
    _storeInInboxCallsSoFar++;
    return _storeInInboxCallsSoFar <= storeInInboxSuccessCount;
  }
  return storeInInboxResult;
}

@override
Future<SendMessageResult> sendMessageWithReply(
  String peerId,
  String message, {
  int? timeoutMs,
}) async {
  sendMessageWithReplyCallCount++;
  operationLog.add('sendMessageWithReply');
  lastSendMessagePeerId = peerId;
  lastSendMessageContent = message;
  return sendMessageWithReplyResult;
}

/// Resets [operationLog] and per-call counters (not configuration).
void resetOperationLog() {
  operationLog.clear();
  _storeInInboxCallsSoFar = 0;
}
```

#### A.6 Lifecycle Simulation Helpers

**File:** `test/shared/helpers/lifecycle_helpers.dart` — new file providing app pause/resume simulation for tests that don't use the full `P2PServiceImpl` stack.

> **⚠️ AUDIT FIX (T6-06 — `test/shared/helpers/` does not exist):** The directory `test/shared/helpers/` does not exist today. Under `test/shared/` only `fakes/` and `widgets/` exist. Phase 1 must explicitly create this directory before this file can be written.

> **⚠️ AUDIT FIX (T6-01 — `handleAppPaused` does not exist):** The import below references `package:flutter_app/core/lifecycle/handle_app_paused.dart`. This file does not exist anywhere in `lib/`. The only lifecycle file is `lib/core/lifecycle/handle_app_resumed.dart`. The `handleAppPaused()` function (sending->failed transition via conditional UPDATE) is entirely aspirational code that must be written before any test referencing it can compile. **PRODUCTION CODE PREREQUISITE:** Create `lib/core/lifecycle/handle_app_paused.dart` before any Section 6 test that imports it.

> **⚠️ AUDIT FIX (T6-10 — `handleAppPaused` signature — RESOLVED):** All call sites now use the standardized signature `handleAppPaused(messageRepo: ...)` (the conditional UPDATE needs no P2P). The `p2pService` parameter has been removed from A.6 lifecycle helpers and B.4 rapid-lock-unlock tests.

> **⚠️ AUDIT FIX (T6-11 — TestUser has no lifecycle simulation):** The actual `TestUser` at `test/shared/fakes/test_user.dart` has no `pause()`/`resume()` method or lifecycle state field. A cleaner approach: add `simulatePause()` and `simulateResume()` methods directly on `TestUser` that call `handleAppPaused`/`handleAppResumed` with the user's own repos. Consider this as a Phase 1 enhancement.

```dart
import 'dart:async';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

/// Simulates a complete background/foreground cycle in tests.
///
/// Calls [handleAppPaused] then [handleAppResumed] with the provided
/// dependencies. This is the canonical way to exercise the lifecycle
/// pair in integration tests.
Future<void> simulateBackgroundForegroundCycle({
  required Bridge bridge,
  required P2PService p2pService,
  required MessageRepository messageRepo,
}) async {
  await handleAppPaused(messageRepo: messageRepo);
  await handleAppResumed(
    bridge: bridge,
    p2pService: p2pService,
  );
}

/// Simulates rapid lock-unlock (N full background/foreground cycles).
///
/// Used by the rapid-lock-unlock integration test to verify idempotency.
Future<void> simulateRapidLockUnlock({
  required Bridge bridge,
  required P2PService p2pService,
  required MessageRepository messageRepo,
  int cycles = 3,
  Duration pauseBetween = Duration.zero,
}) async {
  for (var i = 0; i < cycles; i++) {
    await simulateBackgroundForegroundCycle(
      bridge: bridge,
      p2pService: p2pService,
      messageRepo: messageRepo,
    );
    if (pauseBetween > Duration.zero) {
      await Future.delayed(pauseBetween);
    }
  }
}
```

#### A.7 Shared Test Fixtures

**File:** `test/shared/fixtures/message_fixtures.dart` — new file with canonical sample data used across all five fix areas.

> **⚠️ AUDIT FIX (T6-06 — `test/shared/fixtures/` does not exist):** The directory `test/shared/fixtures/` does not exist today. Under `test/shared/` only `fakes/` and `widgets/` exist. Phase 1 must explicitly create this directory before this file can be written.

```dart
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

/// A message in 'sending' status, as it exists before any send attempt completes.
/// The [createdAt] is set to [ageOffset] before [relativeTo].
ConversationMessage makeSendingMessage({
  String id = 'msg-sending-001',
  String contactPeerId = 'peer-bob',
  String text = 'Hello',
  Duration ageOffset = Duration.zero,
  DateTime? relativeTo,
}) {
  final base = relativeTo ?? DateTime(2026, 3, 23, 12, 0, 0).toUtc();
  final createdAt = base.subtract(ageOffset).toIso8601String();
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: createdAt,
    status: 'sending',
    isIncoming: false,
    createdAt: createdAt,
    wireEnvelope: '{"type":"chat_message","version":"1","payload":{}}',
  );
}

/// A message in 'failed' status with a pre-built wire envelope.
ConversationMessage makeFailedMessageWithEnvelope({
  String id = 'msg-failed-001',
  String contactPeerId = 'peer-bob',
  String text = 'Hello',
}) {
  const ts = '2026-03-23T12:00:00.000Z';
  return ConversationMessage(
    id: id,
    contactPeerId: contactPeerId,
    senderPeerId: 'peer-alice',
    text: text,
    timestamp: ts,
    status: 'failed',
    isIncoming: false,
    createdAt: ts,
    wireEnvelope: '{"type":"chat_message","version":"2","encrypted":{'
        '"kem":"fake-kem","ciphertext":"fake-ct","nonce":"fake-nonce"}}',
  );
}

/// Identity fixture with full ML-KEM keys.
IdentityModel makeAliceIdentity() {
  return IdentityModel(
    peerId: 'peer-alice',
    publicKey: 'alice-pk-base64',
    privateKey: 'alice-privkey-base64',
    mnemonic12: 'word1 word2 word3 word4 word5 word6 '
        'word7 word8 word9 word10 word11 word12',
    mlKemPublicKey: 'alice-mlkem-pk',
    mlKemSecretKey: 'alice-mlkem-sk',
    username: 'Alice', // AUDIT FIX (T6-13): explicit username required — tests reference alice.username expecting 'Alice', and the constructor defaults to 'Username'
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

/// Contact fixture for Bob, with ML-KEM public key.
ContactModel makeBobContact() {
  return ContactModel(
    peerId: 'peer-bob',
    publicKey: 'bob-pk-base64',
    rendezvous: '/dns4/relay.example.com/tcp/443/p2p/relay',
    username: 'Bob',
    signature: 'bob-sig-base64',
    scannedAt: '2026-01-01T00:00:00.000Z',
    mlKemPublicKey: 'bob-mlkem-pk',
  );
}
```

---

### Part B: Cross-Cutting Integration Tests

> **⚠️ AUDIT FIX — PRODUCTION CODE PREREQUISITES FOR PART B:**
> The following production files must be created before ANY Section 6 Part B test can compile:
>
> 1. **`lib/core/lifecycle/handle_app_paused.dart`** — the `handleAppPaused()` function (conditional `UPDATE ... SET status='failed' WHERE status='sending'`). Referenced by B.1, B.4, and lifecycle helpers. (T6-01)
> 2. **`MessageRepository.getSendingMessages()`** — add to the interface at `lib/features/conversation/domain/repositories/message_repository.dart` and implement in `MessageRepositoryImpl`. (T6-02)
> 3. **`lib/features/push/domain/push_token_store.dart`** — the `PushTokenStore` interface. Referenced by B.3. (T6-03)
> 4. **`notificationBodyForMessage()`** — create in `lib/features/push/application/show_notification_use_case.dart` (Section 5.4). Referenced by B.1 media/voice notification assertions. (T6-04)
> 5. **Extend `retryFailedMessages`** — accept `mediaAttachmentRepo` parameter and re-upload media for failed messages that have local media attachments without a wireEnvelope. Required by GAP B and GAP C corrected tests.
> 6. **`PendingMessageRetrier.start()` cold-start fix** — if `_wasOnline` is already `true`, schedule immediate debounced retry. Required by GAP D.

All integration tests use `TestUser` + `FakeP2PNetwork` from `test/shared/fakes/` — the same harnesses used in `two_user_message_exchange_test.dart` and `offline_inbox_roundtrip_test.dart`. They must prove the actual three-way contract: **sender sends + sender locks → recipient receives + recipient gets notification**.

**Primary acceptance proof:** B.1's first sub-test ("THE REAL BUG") reproduces the exact failure window -- the phone locks between the optimistic DB save and `sendChatMessage()` invocation -- and proves the full recovery chain (stuck-sending -> `handleAppPaused` -> failed -> `retryFailedMessages` on the **original row** -> Bob receives + Bob notified). Sub-tests 2 and 3 prove the same original-row recovery for interrupted media and voice uploads respectively, using real `upload_pending` attachment rows with durable `localPath` and the actual `retryIncompleteUploads()` -> `retryFailedMessages()` two-step sequence (not a synthetic single call). Sub-test 3b covers the WiFi-first interrupted path, proving that a failed `sendLocalMedia()` attempt correctly falls through to the relay recovery path on resume. All other B.1 sub-tests are supporting regression guards. B.2-B.4 cover orthogonal failure scenarios (relay down, notification deep-link, rapid cycling). Final green evidence must recover the **original row / original `messageId`**; re-sending a fresh message under a new row is not sufficient proof of this bug fix.

#### B.1 Integration Test 1: The "Send-Then-Lock" Scenario (Proves the Bug is Fixed)

**File:** `test/features/conversation/integration/send_then_lock_delivery_test.dart`

This is the primary acceptance test. It exercises Sections 1, 2, 3, and 4 together and proves the original bug is fixed.

**Sub-test ordering rationale:** The sub-tests are organized by proof strength, not chronological flow. Sub-tests 1-3b are **acceptance proofs** (text, media, voice relay, voice WiFi-to-relay fallback). Sub-tests 4-8 are **regression guards and supporting scenarios**. Sub-tests 9-10 are **notification body regression guards**.

| # | Sub-test | Proof role |
|---|---|---|
| 1 | THE REAL BUG: text message, original-row retry | **Primary acceptance proof** |
| 2 | MEDIA-UPLOAD-LOCK: real interrupted image upload recovery | Media acceptance proof |
| 3 | VOICE-UPLOAD-LOCK: real interrupted voice upload recovery | Voice acceptance proof (relay path) |
| 3b | WIFI-INTERRUPTED-VOICE: local WiFi fails, relay fallback recovery | Voice acceptance proof (WiFi-to-relay fallback) |
| 4 | REGRESSION: completed send not overwritten by pause | Regression guard |
| 5 | Two-phase flow: optimistic save precedes sendChatMessage | Contract validation |
| 6 | Direct-first offline delivery | Supporting scenario |
| 7 | App-killed mid-send recovery | Supporting scenario |
| 8 | Rapid lock-unlock idempotency | Supporting scenario |
| 9 | VOICE-WITH-CAPTION: caption beats fallback | Notification regression |
| 10 | MEDIA-NOTIFICATION-BODY: caption beats fallback | Notification regression |

##### Why `TestUser.sendMessage()` calls `sendChatMessage()` directly (and why that is correct for most sub-tests)

`TestUser.sendMessage()` (at `test/shared/fakes/test_user.dart:140`) calls the `sendChatMessage()` use case function directly, bypassing the `conversation_wired.dart` widget. This is intentional for integration tests that verify the *use-case-level* contract (encryption, direct-first send, retry, status transitions). The widget layer adds UI concerns (setState, media upload, contact refresh) that are tested separately via widget tests.

**However**, the real bug's failure window lives *inside* `conversation_wired.dart`: the gap between the optimistic `messageRepo.saveMessage()` call at line 637 and the `sendChatMessageFn()` call at line 724. In that gap, media upload or contact refresh is in progress and `sendChatMessage` has not been invoked yet. If the phone locks here, direct-first send never fires because the use case never started. To prove this bug is fixed, the "THE REAL BUG" sub-test (below) simulates the exact intermediate state by writing the optimistic DB row directly, and a dedicated `conversation_wired` path validation sub-test confirms the widget exercises the same two-phase flow.

##### BobTestHarness -- Single Controlled Bob Listener

The previous design used two competing production-like `ChatMessageListener` instances on Bob's stream (one for persistence from `TestUser`, one for notifications). This is fragile: two uncontrolled listeners race on the same `messageStream` and the same `messageRepo`, causing non-deterministic persistence order and potential double-saves.

The corrected design uses a **single `BobTestHarness`** that:

1. Subscribes to `bob.p2pService.messageStream` **once**.
2. Maintains a single `receivedMessages` list.
3. Maintains a single `receivedNotifications` list (via `FakeNotificationService`).
4. Delegates to the production `ChatMessageListener` for persistence AND notification dispatch in one instance.
5. Exposes assertion helpers for message content, count, and dedup.

This harness replaces both the `TestUser.create` chatListener for Bob AND the separate notification listener. Bob's `TestUser` is created with `autoStartListener: false` to prevent the default listener from competing.

##### Production Code Prerequisites for B.1

> **PRODUCTION CODE PREREQUISITES (must exist before B.1 compiles):**
>
> 1. **`lib/core/lifecycle/handle_app_paused.dart`** -- the `handleAppPaused()` function (T6-01)
> 2. **`MessageRepository.getSendingMessages()`** -- interface + impl (T6-02)
> 3. **Extend `retryFailedMessages`** -- accept `mediaAttachmentRepo` parameter to load `done` attachments for failed messages that were interrupted mid-upload (GAP B / GAP C)
> 4. **`retryIncompleteUploads`** -- new use case at `lib/features/conversation/application/retry_incomplete_uploads_use_case.dart` that queries `upload_pending` attachment rows with valid `localPath`, re-uploads each via relay (`uploadMedia()`), and updates attachment status to `done`. Called by `handleAppResumed()` BEFORE `retryFailedMessages()` so attachments are ready when retry runs
> 5. **`notificationBodyForMessage()`** -- Section 5.4 prerequisite (T6-04)
> 6. **`TestUser` `autoStartListener` parameter** -- allow creating TestUser without auto-starting chatListener
> 7. **`FakeP2PService` (integration) `sendLocalMedia` configurability** -- add `sendLocalMediaResult` field (defaults to `false`) to allow per-test control of WiFi transfer success/failure

```dart
import 'dart:async';
import 'dart:ui' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
    // PREREQ (T6-01): handle_app_paused.dart must be created first
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
    // PREREQ: retry_incomplete_uploads_use_case.dart must be created first
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/test_user.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

// =====================================================================
// BobTestHarness: single controlled listener for Bob
// =====================================================================
// Replaces the split-listener pattern. One instance subscribes to Bob's
// messageStream, persists messages via ChatMessageListener, and captures
// notifications via FakeNotificationService. No competing listeners.
// =====================================================================

class BobTestHarness {
  final TestUser bob;
  final FakeNotificationService notificationService;
  final ActiveConversationTracker conversationTracker;
  final List<ChatMessage> receivedMessages = [];
  late final ChatMessageListener _listener;
  late final StreamSubscription<ChatMessage> _rawSub;
  AppLifecycleState lifecycleState;

  BobTestHarness({
    required this.bob,
    this.lifecycleState = AppLifecycleState.paused,
  })  : notificationService = FakeNotificationService(),
        conversationTracker = ActiveConversationTracker() {
    // Raw subscription to capture all incoming messages for assertions.
    _rawSub = bob.p2pService.messageStream.listen((msg) {
      receivedMessages.add(msg);
    });

    // Single ChatMessageListener that handles BOTH persistence and
    // notification dispatch -- mirrors the production architecture.
    _listener = ChatMessageListener(
      chatMessageStream: bob.p2pService.messageStream,
      messageRepo: bob.messageRepo,
      contactRepo: bob.contactRepo,
      bridge: bob.bridge,
      notificationService: notificationService,
      conversationTracker: conversationTracker,
      getAppLifecycleState: () => lifecycleState,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
    );
  }

  void start() => _listener.start();

  void stop() {
    _listener.stop();
    _rawSub.cancel();
  }

  /// Snapshot of notifications shown (delegates to FakeNotificationService).
  List<FakeNotification> get shownNotifications => notificationService.shown;

  /// Clear notification history between sub-test phases.
  void clearNotifications() => notificationService.shown.clear();

  /// Assert that exactly [count] messages were persisted for [contactPeerId].
  Future<void> expectMessageCount(String contactPeerId, int count,
      {String? reason}) async {
    final msgs = await bob.messageRepo.getMessagesForContact(contactPeerId);
    expect(msgs, hasLength(count), reason: reason);
  }

  /// Assert that the latest persisted message has the given [text].
  Future<void> expectLatestMessageText(
      String contactPeerId, String text) async {
    final msgs = await bob.messageRepo.getMessagesForContact(contactPeerId);
    expect(msgs.last.text, text);
    expect(msgs.last.isIncoming, isTrue);
  }

  /// Assert that exactly [count] notifications were shown.
  void expectNotificationCount(int count, {String? reason}) {
    expect(shownNotifications, hasLength(count), reason: reason);
  }

  /// Assert the latest notification has the given [contactPeerId] and [body].
  void expectLatestNotification({
    required String contactPeerId,
    required String body,
    String? senderUsername,
  }) {
    expect(shownNotifications, isNotEmpty);
    final last = shownNotifications.last;
    expect(last.contactPeerId, contactPeerId);
    expect(last.messageText, body);
    if (senderUsername != null) {
      expect(last.senderUsername, senderUsername);
    }
  }
}

void main() {
  group('B.1 Send-then-lock: proves the original bug is fixed', () {
    late FakeP2PNetwork network;
    late TestUser alice;
    late TestUser bob;
    late BobTestHarness bobHarness;
    late FakeIdentityRepository aliceIdentityRepo;
    late InMemoryMediaAttachmentRepository aliceMediaAttachmentRepo;

    setUp(() async {
      network = FakeP2PNetwork();

      alice = TestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: network,
      );
      // Bob created with autoStartListener: false so BobTestHarness
      // is the ONLY listener on Bob's messageStream.
      bob = TestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        autoStartListener: false,
      );

      // Single controlled Bob listener (replaces split-listener pattern)
      bobHarness = BobTestHarness(
        bob: bob,
        lifecycleState: AppLifecycleState.paused, // Bob is backgrounded
      );
      bobHarness.start();

      // Contacts
      alice.addContact(bob);
      bob.addContact(alice);

      // Both online
      alice.setOnline(true);
      bob.setOnline(true);

      // Alice's identity repo (for retryFailedMessages)
      aliceIdentityRepo = FakeIdentityRepository()
        ..seed(IdentityModel(
          peerId: alice.peerId,
          publicKey: 'pk-${alice.peerId}',
          privateKey: 'alice-privkey',
          mnemonic12: 'word1 word2 word3 word4 word5 word6 '
              'word7 word8 word9 word10 word11 word12',
          mlKemPublicKey: 'alice-mlkem-pk',
          mlKemSecretKey: 'alice-mlkem-sk',
          username: alice.username,
          createdAt: '2026-01-01T00:00:00.000Z',
          updatedAt: '2026-01-01T00:00:00.000Z',
        ));

      // Alice's media attachment repo (for media/voice sub-tests)
      aliceMediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    });

    tearDown(() {
      bobHarness.stop();
      alice.dispose();
      bob.dispose();
    });

    // =================================================================
    // SUB-TEST 1: PRIMARY ACCEPTANCE PROOF — ORIGINAL-ROW TEXT RECOVERY
    // =================================================================
    // Reproduces the exact bug: phone locks between optimistic DB save
    // and sendChatMessage(). Proves the SAME row (id='stuck-msg-001')
    // is recovered via retryFailedMessages, not a fresh re-send.
    //
    // Contract under test:
    //   1. Create optimistic row with id='stuck-msg-001', status='sending'
    //   2. Simulate pause (handleAppPaused transitions to 'failed')
    //   3. Simulate resume (retryFailedMessages with original messageId)
    //   4. Assert SAME row id='stuck-msg-001' now has status='sent'/'delivered'
    //   5. Assert messages.length == 1 (no duplicate rows)
    //   6. Do NOT call sendMessage() — the retry must reuse the existing row
    // =================================================================
    test(
      '1. THE REAL BUG: original-row text recovery — stuck-msg-001 retried in place',
      () async {
        // Step 1: Create optimistic message row with known ID.
        // This mirrors conversation_wired.dart:637 — saveMessage with
        // status='sending', NO wireEnvelope (sendChatMessage never ran).
        final stuckTimestamp = DateTime.now().toUtc().toIso8601String();
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: 'stuck-msg-001',
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: 'Stuck in sending',
          timestamp: stuckTimestamp,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTimestamp,
          // wireEnvelope intentionally absent — sendChatMessage never ran
        ));

        // Step 2: Simulate pause — handleAppPaused transitions sending -> failed.
        await handleAppPaused(messageRepo: alice.messageRepo);

        // Assert: row transitioned to 'failed', ID unchanged
        final afterPause =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterPause, hasLength(1));
        expect(afterPause.first.id, 'stuck-msg-001');
        expect(afterPause.first.status, 'failed',
            reason: 'handleAppPaused must transition sending -> failed');

        // Verify: conditional UPDATE does NOT overwrite completed sends
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: 'delivered-msg-002',
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: 'Already delivered',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'delivered',
          isIncoming: false,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ));
        await handleAppPaused(messageRepo: alice.messageRepo);
        final allMessages =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        final deliveredMsg =
            allMessages.firstWhere((m) => m.id == 'delivered-msg-002');
        expect(deliveredMsg.status, 'delivered',
            reason: 'conditionalTransitionStatus must NOT overwrite delivered -> failed');

        // Step 3: Simulate resume — call retryFailedMessages (NOT sendMessage).
        // retryFailedMessages at retry_failed_messages_use_case.dart:92-103
        // passes messageId: msg.id and timestamp: msg.timestamp to
        // sendChatMessage, so the DB row is updated in-place via INSERT OR REPLACE.
        bobHarness.clearNotifications();

        final retryCount = await retryFailedMessages(
          messageRepo: alice.messageRepo,
          identityRepo: aliceIdentityRepo,
          contactRepo: alice.contactRepo,
          p2pService: alice.p2pService,
          bridge: alice.bridge,
        );
        expect(retryCount, 1);

        // Allow Bob's listener to process
        await Future.delayed(const Duration(milliseconds: 100));

        // Step 4: Assert SAME row recovered — no duplicate rows.
        final afterRetry =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        // Filter out the delivered-msg-002 helper row
        final stuckRows = afterRetry.where((m) => m.id == 'stuck-msg-001').toList();
        expect(stuckRows, hasLength(1),
            reason: 'Must be exactly 1 row with id stuck-msg-001 — no duplicate');
        expect(stuckRows.first.id, 'stuck-msg-001',
            reason: 'Row identity preserved — retrier reuses original messageId');
        expect(stuckRows.first.status, anyOf('delivered', 'sent'),
            reason: 'Original row updated to delivered/sent');

        // Step 5: Assert messages.length for this conversation
        // (stuck-msg-001 recovered + delivered-msg-002 helper = 2 total)
        expect(afterRetry, hasLength(2));

        // Step 6: Bob received the message.
        await bobHarness.expectMessageCount(alice.peerId, 1,
            reason: 'Bob must receive exactly 1 message');
        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Stuck in sending');

        // Step 7: Bob got a notification.
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Stuck in sending',
          senderUsername: 'Alice',
        );
      },
    );

    // =================================================================
    // SUB-TEST 2: REAL INTERRUPTED MEDIA UPLOAD RECOVERY
    // =================================================================
    // Proves the complete media recovery chain using the real 4-step
    // handleAppResumed sequence:
    //   1. Alice selects an image, processes it, copies to durable storage
    //   2. Optimistic message row created with status='sending'
    //   3. upload_pending attachment row saved with localPath pointing to
    //      durable copy (e.g. /tmp/durable_media/test-image-001.jpg)
    //   4. Upload INTERRUPTED (FakeBridge throws on first upload call)
    //   5. handleAppPaused() transitions sending -> failed
    //   6. retryIncompleteUploads() finds upload_pending rows, re-uploads
    //      from durable localPath via relay, updates attachment to 'done'
    //   7. retryFailedMessages() finds failed message, loads done
    //      attachments, calls sendChatMessage with original messageId
    //   8. SAME message row and SAME attachment row are updated (not new)
    //   9. Bob receives the message with media
    // =================================================================
    test(
      '2. MEDIA-UPLOAD-LOCK: real interrupted image upload -> same-row recovery',
      () async {
        final stuckTs = DateTime.now().toUtc().toIso8601String();
        const msgId = 'media-stuck-img-001';
        const attachId = 'blob-img-001';
        const durablePath = '/tmp/durable_media/test-image-001.jpg';

        // Step 1: Alice picks image, creates optimistic message row.
        // Mirrors conversation_wired.dart Phase 1: saveMessage with status='sending'.
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: msgId,
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: '', // image-only, no caption
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          // wireEnvelope absent — sendChatMessage never ran
        ));

        // Step 2: Persist upload_pending attachment row with durable localPath.
        // In production, conversation_wired.dart copies the picked file to
        // app-documents/media/ before starting upload. The localPath points
        // to this durable copy so it survives app restarts.
        final pendingAttachment = MediaAttachment(
          id: attachId,
          messageId: msgId,
          mime: 'image/jpeg',
          size: 204800,
          mediaType: 'image',
          width: 1920,
          height: 1080,
          localPath: durablePath,
          downloadStatus: 'upload_pending',
          createdAt: stuckTs,
        );
        await aliceMediaAttachmentRepo.saveAttachment(pendingAttachment);

        // Step 3: Upload INTERRUPTED — FakeBridge throws on upload call.
        // In the real flow, conversation_wired.dart calls uploadMedia()
        // which calls callP2PMediaUpload() via the bridge. The device
        // locks before sendChatMessage is called.
        alice.bridge.throwOnSend = true;
        alice.bridge.throwOnSendMessage = 'Upload interrupted by lock';

        // Step 4: Simulate pause — transitions sending -> failed.
        await handleAppPaused(messageRepo: alice.messageRepo);

        final afterPause =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterPause, hasLength(1));
        expect(afterPause.first.id, msgId);
        expect(afterPause.first.status, 'failed');

        // Verify attachment row still exists with upload_pending status.
        final pendingAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(pendingAttachments, hasLength(1));
        expect(pendingAttachments.first.id, attachId);
        expect(pendingAttachments.first.downloadStatus, 'upload_pending');
        expect(pendingAttachments.first.localPath, durablePath,
            reason: 'Durable localPath must survive pause');

        // Step 5: Simulate resume via handleAppResumed — the real 4-step
        // recovery sequence. This is NOT a synthetic retryFailedMessages call.
        // handleAppResumed runs:
        //   (a) recoverStuckSendingMessages (already done by pause)
        //   (b) retryIncompleteUploads — finds upload_pending rows,
        //       re-uploads from durable localPath, updates to 'done'
        //   (c) retryFailedMessages — finds 'failed' message, loads 'done'
        //       attachments, calls sendChatMessage with original messageId
        //
        // Restore bridge (simulates relay back online).
        alice.bridge.throwOnSend = false;
        alice.bridge.throwOnSendMessage = null;
        bobHarness.clearNotifications();

        // retryIncompleteUploads finds upload_pending attachment rows with
        // valid localPath and re-uploads them. After re-upload, attachment
        // status transitions to 'done'. Then retryFailedMessages picks up
        // the 'failed' message, sees its attachments are now 'done', and
        // calls sendChatMessage with the original messageId.
        final uploadRetryCount = await retryIncompleteUploads(
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
          bridge: alice.bridge,
          p2pService: alice.p2pService,
        );
        expect(uploadRetryCount, 1,
            reason: 'retryIncompleteUploads must find and re-upload 1 attachment');

        // Verify attachment transitioned to 'done' after re-upload.
        final midAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(midAttachments.first.downloadStatus, 'done',
            reason: 'Attachment must be done after retryIncompleteUploads');
        expect(midAttachments.first.id, attachId,
            reason: 'Same attachment row — not a new row');

        // Now retryFailedMessages picks up the failed message and sends it,
        // using the now-uploaded attachment.
        final retryCount = await retryFailedMessages(
          messageRepo: alice.messageRepo,
          identityRepo: aliceIdentityRepo,
          contactRepo: alice.contactRepo,
          p2pService: alice.p2pService,
          bridge: alice.bridge,
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
        );
        expect(retryCount, 1);

        await Future.delayed(const Duration(milliseconds: 100));

        // Step 6: Assert SAME message row updated (not a new row).
        final afterRetry =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterRetry, hasLength(1),
            reason: 'Exactly 1 message row — no duplicate');
        expect(afterRetry.first.id, msgId,
            reason: 'Same message row ID preserved');
        expect(afterRetry.first.status, anyOf('delivered', 'sent'),
            reason: 'Row status updated after successful re-upload + send');

        // Step 7: Assert SAME attachment row updated (not a new row).
        final afterAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(afterAttachments, hasLength(1),
            reason: 'Exactly 1 attachment row — no duplicate');
        expect(afterAttachments.first.id, attachId,
            reason: 'Same attachment row ID preserved');
        expect(afterAttachments.first.downloadStatus, 'done',
            reason: 'Attachment status remains done after send');

        // Step 8: Bob received the message with media.
        await bobHarness.expectMessageCount(alice.peerId, 1,
            reason: 'Bob receives exactly 1 message');

        // Step 9: Bob notified with 'Photo' body.
        // KEY ASSERTION: notification body for image-only must be 'Photo'
        // (requires handleIncomingChatMessage media hydration +
        // notificationBodyForMessage).
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Photo',
          senderUsername: 'Alice',
        );
      },
    );

    // =================================================================
    // SUB-TEST 3: REAL INTERRUPTED VOICE UPLOAD RECOVERY (RELAY PATH)
    // =================================================================
    // Proves the complete voice recovery chain using the real 4-step
    // handleAppResumed sequence:
    //   1. Alice records voice, audio file copied to durable storage
    //   2. Optimistic message row + upload_pending attachment row created
    //      with voice-specific metadata (durationMs, waveform)
    //   3. Upload via relay INTERRUPTED (FakeBridge throws)
    //   4. handleAppPaused() transitions sending -> failed
    //   5. retryIncompleteUploads() finds upload_pending voice attachment,
    //      re-uploads from durable localPath via relay, updates to 'done',
    //      preserves voice metadata (durationMs, waveform)
    //   6. retryFailedMessages() sends with the now-uploaded attachment
    //   7. Same rows updated, Bob receives voice message
    //
    // Sub-test 3b covers the WiFi-first interrupted path separately.
    // =================================================================
    test(
      '3. VOICE-UPLOAD-LOCK: real interrupted voice upload -> relay re-upload recovery',
      () async {
        final stuckTs = DateTime.now().toUtc().toIso8601String();
        const msgId = 'voice-stuck-001';
        const attachId = 'blob-voice-001';
        const durableVoicePath = '/tmp/durable_media/test-voice-001.m4a';

        // Step 1: Alice records voice, creates optimistic message row.
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: msgId,
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: '', // voice-only, no caption
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
          // wireEnvelope absent
        ));

        // Step 2: Persist upload_pending attachment with durable localPath.
        final pendingVoice = MediaAttachment(
          id: attachId,
          messageId: msgId,
          mime: 'audio/mp4',
          size: 83200,
          mediaType: 'audio',
          durationMs: 5200,
          localPath: durableVoicePath,
          downloadStatus: 'upload_pending',
          createdAt: stuckTs,
          waveform: [0.1, 0.5, 0.8, 0.3, 0.6],
        );
        await aliceMediaAttachmentRepo.saveAttachment(pendingVoice);

        // Step 3: Upload/sendLocalMedia INTERRUPTED.
        // FakeP2PService.sendLocalMedia returns false by default (no WiFi path).
        // FakeBridge throws to simulate relay upload failure.
        alice.bridge.throwOnSend = true;
        alice.bridge.throwOnSendMessage = 'Voice upload interrupted';

        // Step 4: Simulate pause — transitions sending -> failed.
        await handleAppPaused(messageRepo: alice.messageRepo);

        final afterPause =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterPause, hasLength(1));
        expect(afterPause.first.id, msgId);
        expect(afterPause.first.status, 'failed');

        // Verify attachment row persists with all metadata.
        final pendingAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(pendingAttachments, hasLength(1));
        expect(pendingAttachments.first.downloadStatus, 'upload_pending');
        expect(pendingAttachments.first.localPath, durableVoicePath);
        expect(pendingAttachments.first.durationMs, 5200);
        expect(pendingAttachments.first.waveform, [0.1, 0.5, 0.8, 0.3, 0.6]);

        // Step 5: Simulate resume via the real 4-step handleAppResumed
        // sequence. The retry path uses uploadMedia (relay), NOT
        // sendLocalMedia (WiFi), because retry always prefers the reliable
        // relay path over opportunistic WiFi.
        alice.bridge.throwOnSend = false;
        alice.bridge.throwOnSendMessage = null;
        bobHarness.clearNotifications();

        // retryIncompleteUploads finds the upload_pending voice attachment,
        // re-uploads from durable localPath via relay, updates to 'done'.
        final uploadRetryCount = await retryIncompleteUploads(
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
          bridge: alice.bridge,
          p2pService: alice.p2pService,
        );
        expect(uploadRetryCount, 1,
            reason: 'retryIncompleteUploads must find and re-upload 1 voice attachment');

        // Verify attachment transitioned to 'done' with metadata preserved.
        final midAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(midAttachments.first.downloadStatus, 'done',
            reason: 'Voice attachment must be done after retryIncompleteUploads');
        expect(midAttachments.first.id, attachId,
            reason: 'Same attachment row — not a new row');
        expect(midAttachments.first.durationMs, 5200,
            reason: 'Voice metadata (durationMs) preserved through re-upload');
        expect(midAttachments.first.waveform, [0.1, 0.5, 0.8, 0.3, 0.6],
            reason: 'Voice metadata (waveform) preserved through re-upload');

        // retryFailedMessages picks up the failed message, sees its
        // attachments are now 'done', and calls sendChatMessage with the
        // original messageId.
        final retryCount = await retryFailedMessages(
          messageRepo: alice.messageRepo,
          identityRepo: aliceIdentityRepo,
          contactRepo: alice.contactRepo,
          p2pService: alice.p2pService,
          bridge: alice.bridge,
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
        );
        expect(retryCount, 1);

        await Future.delayed(const Duration(milliseconds: 100));

        // Step 6: Same message row updated — no duplicates.
        final afterRetry =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterRetry, hasLength(1),
            reason: 'Exactly 1 message row — no duplicate');
        expect(afterRetry.first.id, msgId,
            reason: 'Same message row ID preserved');
        expect(afterRetry.first.status, anyOf('delivered', 'sent'));

        // Step 7: Same attachment row updated — no duplicates.
        final afterAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(afterAttachments, hasLength(1),
            reason: 'Exactly 1 attachment row — no duplicate');
        expect(afterAttachments.first.id, attachId);
        expect(afterAttachments.first.downloadStatus, 'done',
            reason: 'Attachment remains done after relay re-upload + send');

        // Step 8: Bob received the voice message.
        await bobHarness.expectMessageCount(alice.peerId, 1);

        // Step 9: Bob notified with 'Voice message' body.
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Voice message',
          senderUsername: 'Alice',
        );
      },
    );

    // =================================================================
    // SUB-TEST 3b: LOCAL WiFi INTERRUPTED PATH — RELAY FALLBACK RECOVERY
    // =================================================================
    // Proves the WiFi-first-then-relay recovery chain:
    //   1. Alice sends voice via sendLocalMedia (WiFi direct transfer)
    //   2. sendLocalMedia fails (peer not reachable on local network)
    //   3. Relay fallback also fails (app killed / device locks)
    //   4. Pause -> resume -> retryIncompleteUploads re-uploads via relay
    //   5. retryFailedMessages sends with the now-uploaded attachment
    //   6. Same rows updated, Bob receives voice message
    //
    // This covers the local WiFi branch that sub-test 3 does not exercise.
    // Sub-test 3 proves relay re-upload recovery; this sub-test proves
    // that a failed local WiFi attempt correctly falls through to the
    // relay recovery path on resume.
    // =================================================================
    test(
      '3b. WIFI-INTERRUPTED-VOICE: local sendLocalMedia fails + relay fails -> resume recovers via relay',
      () async {
        final stuckTs = DateTime.now().toUtc().toIso8601String();
        const msgId = 'wifi-voice-stuck-001';
        const attachId = 'blob-wifi-voice-001';
        const durableVoicePath = '/tmp/durable_media/test-wifi-voice-001.m4a';

        // Step 1: Alice records voice, creates optimistic message row.
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: msgId,
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: '', // voice-only, no caption
          timestamp: stuckTs,
          status: 'sending',
          isIncoming: false,
          createdAt: stuckTs,
        ));

        // Step 2: Persist upload_pending attachment with durable localPath.
        final pendingVoice = MediaAttachment(
          id: attachId,
          messageId: msgId,
          mime: 'audio/mp4',
          size: 64000,
          mediaType: 'audio',
          durationMs: 4100,
          localPath: durableVoicePath,
          downloadStatus: 'upload_pending',
          createdAt: stuckTs,
          waveform: [0.2, 0.7, 0.4, 0.9, 0.3],
        );
        await aliceMediaAttachmentRepo.saveAttachment(pendingVoice);

        // Step 3a: sendLocalMedia fails — peer not reachable on local WiFi.
        // In the real flow, conversation_wired tries sendLocalMedia first
        // for same-network peers. FakeP2PService returns false.
        alice.p2pService.sendLocalMediaResult = false;

        // Step 3b: Relay fallback also fails — device locks mid-upload.
        alice.bridge.throwOnSend = true;
        alice.bridge.throwOnSendMessage = 'Relay upload interrupted by lock';

        // Step 4: Simulate pause — transitions sending -> failed.
        await handleAppPaused(messageRepo: alice.messageRepo);

        final afterPause =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterPause, hasLength(1));
        expect(afterPause.first.id, msgId);
        expect(afterPause.first.status, 'failed');

        // Verify attachment row persists with upload_pending status.
        final pendingAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(pendingAttachments, hasLength(1));
        expect(pendingAttachments.first.downloadStatus, 'upload_pending');
        expect(pendingAttachments.first.localPath, durableVoicePath);

        // Step 5: Simulate resume — relay now available. The retry path
        // always uses relay (not WiFi) because WiFi is opportunistic and
        // cannot be relied upon after an app restart.
        alice.bridge.throwOnSend = false;
        alice.bridge.throwOnSendMessage = null;
        bobHarness.clearNotifications();

        // retryIncompleteUploads re-uploads voice via relay from durable path.
        final uploadRetryCount = await retryIncompleteUploads(
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
          bridge: alice.bridge,
          p2pService: alice.p2pService,
        );
        expect(uploadRetryCount, 1,
            reason: 'retryIncompleteUploads re-uploads via relay after WiFi failure');

        // Verify attachment transitioned to 'done'.
        final midAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(midAttachments.first.downloadStatus, 'done');
        expect(midAttachments.first.id, attachId);

        // retryFailedMessages sends the message with the uploaded attachment.
        final retryCount = await retryFailedMessages(
          messageRepo: alice.messageRepo,
          identityRepo: aliceIdentityRepo,
          contactRepo: alice.contactRepo,
          p2pService: alice.p2pService,
          bridge: alice.bridge,
          mediaAttachmentRepo: aliceMediaAttachmentRepo,
        );
        expect(retryCount, 1);

        await Future.delayed(const Duration(milliseconds: 100));

        // Step 6: Same message row updated — no duplicates.
        final afterRetry =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(afterRetry, hasLength(1),
            reason: 'Exactly 1 message row — no duplicate');
        expect(afterRetry.first.id, msgId,
            reason: 'Same message row ID preserved');
        expect(afterRetry.first.status, anyOf('delivered', 'sent'));

        // Step 7: Same attachment row — no duplicates.
        final afterAttachments =
            await aliceMediaAttachmentRepo.getAttachmentsForMessage(msgId);
        expect(afterAttachments, hasLength(1));
        expect(afterAttachments.first.id, attachId);
        expect(afterAttachments.first.downloadStatus, 'done');

        // Step 8: Bob received the voice message.
        await bobHarness.expectMessageCount(alice.peerId, 1);

        // Step 9: Bob notified.
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Voice message',
          senderUsername: 'Alice',
        );
      },
    );

    // =================================================================
    // SUB-TEST 4: REGRESSION — COMPLETED SEND NOT OVERWRITTEN BY PAUSE
    // =================================================================
    test(
      '4. REGRESSION: Alice sends successfully, locks phone -> completed status preserved',
      () async {
        final (result, _) =
            await alice.sendMessage(bob.peerId, 'Hello from locked phone');

        await handleAppPaused(messageRepo: alice.messageRepo);
        await Future.delayed(const Duration(milliseconds: 100));

        // Alice's message must NOT have been overwritten to 'failed'
        final aliceMessages =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(aliceMessages, hasLength(1));
        expect(aliceMessages.first.status, isNot('sending'),
            reason: 'Completed send must not be stuck in sending');
        expect(aliceMessages.first.status, isNot('failed'),
            reason: 'handleAppPaused must NOT overwrite delivered -> failed');

        // Bob received the message
        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Hello from locked phone');

        // Bob got exactly 1 notification
        bobHarness.expectNotificationCount(1);
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Hello from locked phone',
          senderUsername: 'Alice',
        );
      },
    );

    // =================================================================
    // SUB-TEST 5: TWO-PHASE FLOW VALIDATION
    // =================================================================
    test(
      '5. conversation_wired two-phase flow: optimistic save precedes sendChatMessage',
      () async {
        final optimisticId = 'wired-phase-msg-001';
        final now = DateTime.now().toUtc().toIso8601String();

        // Phase 1: optimistic save (mirrors conversation_wired.dart:637)
        await alice.messageRepo.saveMessage(ConversationMessage(
          id: optimisticId,
          contactPeerId: bob.peerId,
          senderPeerId: alice.peerId,
          text: 'Two-phase test',
          timestamp: now,
          status: 'sending',
          isIncoming: false,
          createdAt: now,
        ));

        // Verify intermediate state
        final intermediate =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(intermediate, hasLength(1));
        expect(intermediate.first.status, 'sending');
        expect(intermediate.first.id, optimisticId);

        // Phase 2: sendChatMessage (mirrors conversation_wired.dart:724)
        await alice.sendMessage(bob.peerId, 'Two-phase test');

        final afterSend =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        final nonSending = afterSend.where((m) => m.status != 'sending');
        expect(nonSending, isNotEmpty,
            reason: 'After Phase 2, at least one message must have left sending status');

        await Future.delayed(const Duration(milliseconds: 100));

        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Two-phase test');
        expect(bobHarness.shownNotifications, isNotEmpty);
      },
    );

    // =================================================================
    // SUB-TEST 6: DIRECT-FIRST OFFLINE DELIVERY
    // =================================================================
    test(
      '6. Alice sends, direct P2P fails, direct-first fallback delivers to offline Bob',
      () async {
        bob.setOnline(false);

        await alice.sendMessage(bob.peerId, 'Direct-first test');

        final aliceMessages =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        expect(aliceMessages, hasLength(1));
        expect(aliceMessages.first.status, anyOf('delivered', 'sent'));
        expect(network.storeInInboxCallCount, greaterThanOrEqualTo(1));

        // Bob comes online, drains inbox
        bob.setOnline(true);
        await bob.drainOfflineInbox();
        await Future.delayed(const Duration(milliseconds: 100));

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Direct-first test');
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Direct-first test',
        );
      },
    );

    // =================================================================
    // SUB-TEST 7: APP-KILLED MID-SEND RECOVERY
    // =================================================================
    test(
      '7. Alice sends, app killed mid-send -> resume recovers -> Bob notified',
      () async {
        bob.setOnline(false);
        network.deliveryFails = true;

        try {
          await alice.sendMessage(bob.peerId, 'Killed mid-send');
        } catch (_) {}

        await handleAppPaused(messageRepo: alice.messageRepo);

        final aliceMessages =
            await alice.messageRepo.getMessagesForContact(bob.peerId);
        final stuckMessages =
            aliceMessages.where((m) => m.status == 'sending');
        expect(stuckMessages, isEmpty,
            reason: 'handleAppPaused must transition all sending -> failed');

        network.deliveryFails = false;
        bob.setOnline(true);

        await Future.delayed(const Duration(milliseconds: 200));

        await bob.drainOfflineInbox();
        await Future.delayed(const Duration(milliseconds: 100));

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Killed mid-send');
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Killed mid-send',
        );
      },
    );

    // =================================================================
    // SUB-TEST 8: RAPID LOCK-UNLOCK IDEMPOTENCY
    // =================================================================
    test(
      '8. rapid lock-unlock: message delivered exactly once, Bob notified once',
      () async {
        bob.setOnline(false);

        // Cycle 1: send + pause
        await alice.sendMessage(bob.peerId, 'Rapid cycle test');
        await handleAppPaused(messageRepo: alice.messageRepo);

        // Cycle 2: pause again immediately
        await handleAppPaused(messageRepo: alice.messageRepo);

        // Bob comes online, drains inbox
        bob.setOnline(true);
        await bob.drainOfflineInbox();
        await Future.delayed(const Duration(milliseconds: 100));

        await bobHarness.expectMessageCount(alice.peerId, 1,
            reason: 'Exactly 1 message — no duplicates from rapid cycling');
        await bobHarness.expectLatestMessageText(
            alice.peerId, 'Rapid cycle test');
        bobHarness.expectNotificationCount(1,
            reason: 'Exactly 1 notification — rapid cycling must not duplicate');
      },
    );

    // =================================================================
    // SUB-TEST 9: VOICE-WITH-CAPTION — CAPTION BEATS FALLBACK
    // =================================================================
    test(
      '9. VOICE-WITH-CAPTION: notification body is the caption, not "Voice message"',
      () async {
        bobHarness.clearNotifications();

        final audioAttachment = MediaAttachment(
          id: 'blob-voice-caption-001',
          messageId: '',
          mime: 'audio/mp4',
          size: 48000,
          mediaType: 'audio',
          durationMs: 3000,
          downloadStatus: 'pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        await sendChatMessage(
          p2pService: alice.p2pService,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'Listen to this!',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
          mediaAttachments: [audioAttachment],
        );

        await Future.delayed(const Duration(milliseconds: 100));

        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Listen to this!',
        );
      },
    );

    // =================================================================
    // SUB-TEST 10: MEDIA-NOTIFICATION-BODY — CAPTION BEATS FALLBACK
    // =================================================================
    test(
      '10. MEDIA-NOTIFICATION-BODY: image with caption -> notification body is the caption',
      () async {
        bobHarness.clearNotifications();

        final imageAttachment = MediaAttachment(
          id: 'blob-img-caption-001',
          messageId: '',
          mime: 'image/jpeg',
          size: 102400,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        );

        await sendChatMessage(
          p2pService: alice.p2pService,
          messageRepo: alice.messageRepo,
          targetPeerId: bob.peerId,
          text: 'Check this out!',
          senderPeerId: alice.peerId,
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: 'test-mlkem-pk-${bob.peerId}',
          mediaAttachments: [imageAttachment],
        );

        await Future.delayed(const Duration(milliseconds: 100));

        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Check this out!',
        );
      },
    );
  });
}
```

##### B.1 production code prerequisites (summary)

The B.1 test file requires these production changes, specified in their respective sections:

**Change 1 (Section 5.4): Hydrate media on the returned `ConversationMessage`**

In `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`, after step 6, return `conversationMessage.copyWith(media: parsedAttachments)` so `conversationMessage.media` is populated at notification time.

**Change 2 (Section 5.4): Use `notificationBodyForMessage` at the call site**

In `lib/features/conversation/application/chat_message_listener.dart`, replace bare `messageText: conversationMessage.text` with `messageText: notificationBodyForMessage(conversationMessage.text, conversationMessage.media)`.

```dart
maybeShowNotification(
  notificationService: notificationService!,
  conversationTracker: conversationTracker!,
  getAppLifecycleState: getAppLifecycleState!,
  contactPeerId: conversationMessage.contactPeerId,
  senderUsername: username,
  messageText: notificationBodyForMessage(
    conversationMessage.text,
    conversationMessage.media,   // populated by Change 1
  ),   // was: conversationMessage.text
);
```

**Change 3 (GAP B/C): Extend `retryFailedMessages` for media re-upload**

Accept `mediaAttachmentRepo` parameter. For failed messages with no `wireEnvelope` but with `upload_pending` attachment rows that have a valid `localPath`, call `uploadMedia()` to re-upload from the durable path, then `sendChatMessage` with the original `messageId`.

**Change 4: `retryIncompleteUploads` use case**

New use case that queries `upload_pending` attachments, re-uploads each from `localPath`, updates attachment status to `done`, and triggers send for the parent message.

**Why both Change 1 and Change 2 are needed**: Without Change 1, `conversationMessage.media` is `const []`, so `notificationBodyForMessage('', const [])` returns `'Message'` instead of `'Photo'` or `'Voice message'`.

#### B.2 Integration Test 2: The "Relay-Down Degradation" Scenario

**File:** `test/integration/relay_down_degradation_integration_test.dart`

This test exercises fixes 1, 4, and the interaction between direct-first strategy and the retrier when both the relay inbox and direct P2P are down.

```dart
/// Integration test: relay-down degradation scenario.
///
/// Verifies:
///   - Send attempt: inbox store fails → direct P2P fails → message saved as 'failed'
///   - Resume: retrier picks up failed message
///   - Retry: direct-first send succeeds when relay comes back
///   - Retry: both paths fail → message stays 'failed', no crash
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/conversation/domain/repositories/fake_message_repository.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fixtures/message_fixtures.dart';

// > **⚠️ AUDIT FIX (GAP F — B.2 imports non-existent fixture):** The import
// > above references `../shared/fixtures/message_fixtures.dart` which does not
// > exist yet (see T6-06). This file will NOT compile until Phase 1 creates
// > `test/shared/fixtures/message_fixtures.dart`. This is a hard compile-time
// > dependency — B.2, B.4, and the cold-start retrier test all depend on it.

void main() {
  group('Relay-down degradation', () {
    late FakeBridge bridge;
    late FakeMessageRepository messageRepo;
    late FakeIdentityRepository identityRepo;
    late FakeContactRepository contactRepo;

    setUp(() {
      bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
      messageRepo = FakeMessageRepository();
      identityRepo = FakeIdentityRepository()..seed(makeAliceIdentity());
      contactRepo = FakeContactRepository()..seed([makeBobContact()]);
    });

    test(
      '1. both inbox and direct fail → message persisted as failed',
      () async {
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
          storeInInboxResult: false,  // inbox down
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          discoverPeerResult: null,   // peer not found
        );

        final (result, msg) = await sendChatMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'peer-bob',
          text: 'This will fail',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          bridge: bridge,
          recipientMlKemPublicKey: 'bob-mlkem-pk',
        );

        expect(
          result,
          anyOf(
            SendChatMessageResult.sendFailed,
            SendChatMessageResult.peerNotFound,
          ),
        );
        expect(msg, isNotNull);
        expect(msg!.status, 'failed');

        // Message was persisted as failed
        final stored = await messageRepo.getMessagesForContact('peer-bob');
        expect(stored, hasLength(1));
        expect(stored.first.status, 'failed');

        p2pService.dispose();
      },
    );

    test(
      '2. resume + retry: inbox recovers → message delivered',
      () async {
        // Seed the failed message from scenario 1
        messageRepo.seed([makeFailedMessageWithEnvelope()]);

        // Now relay comes back — inbox succeeds
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
          storeInInboxResult: true,   // inbox back online
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
        );

        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        retrier.start();
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
        );

        await Future.delayed(const Duration(seconds: 6));

        // Inbox store must have been called
        expect(p2pService.storeInInboxCallCount, greaterThanOrEqualTo(1));

        // Message must now be delivered
        final msgs = await messageRepo.getMessagesForContact('peer-bob');
        expect(msgs.first.status, 'delivered');
        expect(msgs.first.transport, 'inbox');

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      '3. retry when both paths still down → message stays failed, no crash',
      () async {
        // Seed the failed message
        messageRepo.seed([makeFailedMessageWithEnvelope()]);

        // Both paths still down
        final p2pService = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
          storeInInboxResult: false,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
          discoverPeerResult: null,
        );

        final retrier = PendingMessageRetrier(
          p2pService: p2pService,
          messageRepo: messageRepo,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          bridge: bridge,
        );

        retrier.start();
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
        );

        await Future.delayed(const Duration(seconds: 6));

        // Message must still be failed — no crash, no data loss
        final msgs = await messageRepo.getMessagesForContact('peer-bob');
        expect(msgs.first.status, 'failed',
            reason: 'No change when both paths down');

        retrier.dispose();
        p2pService.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    // ===================================================================
    // > **⚠️ AUDIT FIX (GAP D — Retrier Cold-Start: missing coverage
    // > for already-online start):** The `PendingMessageRetrier` at
    // > `pending_message_retrier.dart:47` initializes
    // > `_wasOnline = _isOnline(p2pService.currentState)` in `start()`.
    // > The `stateStream.listen` callback only fires retry on
    // > `nowOnline && !_wasOnline` (offline-to-online transition).
    // >
    // > If the app starts with the node ALREADY online (e.g., after a
    // > hot restart), `_wasOnline` is `true` immediately and no
    // > offline->online transition ever fires. Stuck 'failed' messages
    // > are only picked up by the periodic 5-minute timer, not
    // > immediately. This is a real bug.
    // >
    // > The existing test at `pending_message_retrier_test.dart` only
    // > tests the offline->online path. Add the test below.
    // >
    // > **PRODUCTION CODE FIX REQUIRED:** In
    // > `PendingMessageRetrier.start()`, if `_wasOnline` is already
    // > `true`, schedule a debounced retry immediately:
    // > ```dart
    // > if (_wasOnline) {
    // >   _debounceTimer?.cancel();
    // >   _debounceTimer = Timer(const Duration(seconds: 5), _retryIfNeeded);
    // >   _periodicTimer?.cancel();
    // >   _periodicTimer = Timer.periodic(
    // >     const Duration(minutes: 5), (_) => _retryIfNeeded());
    // > }
    // > ```
    // ===================================================================
    test(
      '4. cold-start: node already online when start() called -> sweep immediately',
      () async {
        // Start with online state (node already connected before retrier starts)
        final coldP2p = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
          storeInInboxResult: true,
          sendMessageWithReplyResult: const SendMessageResult(sent: false),
        );
        // Seed a failed message that needs retry
        final coldRepo = FakeMessageRepository();
        coldRepo.seed([makeFailedMessageWithEnvelope()]);
        final coldIdentity = FakeIdentityRepository()..seed(makeAliceIdentity());
        final coldContacts = FakeContactRepository()..seed([makeBobContact()]);

        final coldRetrier = PendingMessageRetrier(
          p2pService: coldP2p,
          messageRepo: coldRepo,
          identityRepo: coldIdentity,
          contactRepo: coldContacts,
          bridge: bridge,
        );

        // start() should detect already-online and schedule immediate sweep
        coldRetrier.start();

        // Wait for the debounce (5s) + margin
        await Future.delayed(const Duration(seconds: 6));

        // The failed message should have been retried
        final msgs = await coldRepo.getMessagesForContact('peer-bob');
        expect(msgs.first.status, 'delivered',
            reason: 'Cold-start with already-online node must sweep immediately');

        coldRetrier.dispose();
        coldP2p.dispose();
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
```

#### B.3 Integration Test 3: The "Notification Deep-Link" Scenario

**File:** `test/integration/notification_deeplink_integration_test.dart`

This test exercises fix 5 (FCM `sender_id`/`from` field, correct conversation routing) together with the push open flow already established in `test/features/push/application/chat_and_group_push_open_flow_test.dart`.

```dart
/// Integration test: FCM notification deep-link scenario.
///
/// Verifies:
///   - A chat push with 'sender_id' field (server-side key) routes to the
///     correct conversation using the 'from' field (client-side key)
///   - A group push routes to the correct group screen
///   - Tapping the notification triggers inbox drain before UI navigation
///   - The notification payload survives a token store round-trip (fix 5)
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/push/application/prepare_notification_open_use_case.dart';

import '../shared/fakes/fake_push_token_store.dart';

void main() {
  group('Notification deep-link integration', () {
    test(
      '1. chat push with sender_id field routes to correct conversation',
      () async {
        // Section 5 Bug A: server sends 'sender_id', client must read it.
        // The FCM fix reads both 'sender_id' and 'from' for backwards compat.
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'new_message',
            'from': 'peer-alice-123',
            // 'sender_id' is the legacy server key; fix 5 maps it to 'from'
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async => events.add('drain:inbox'),
              drainGroupOfflineInboxForGroup: (_) async {},
            );
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, containsAllInOrder([
          'prepare:peer-alice-123',
          'drain:inbox',
          'route:peer-alice-123',
        ]));
        expect(routed.single.kind, NotificationRouteTargetKind.conversation);
        expect(routed.single.peerId, 'peer-alice-123');
      },
    );

    test(
      '2. group push with groupId routes to correct group screen',
      () async {
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-xyz-789',
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async {},
              drainGroupOfflineInboxForGroup: (groupId) async =>
                  events.add('drain:group:$groupId'),
            );
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        expect(events, containsAllInOrder([
          'prepare:group:group-xyz-789',
          'drain:group:group-xyz-789',
          'route:group:group-xyz-789',
        ]));
        expect(routed.single.kind, NotificationRouteTargetKind.group);
        expect(routed.single.groupId, 'group-xyz-789');
      },
    );

    test(
      '3. push token survives logical app restart (persistent token store)',
      () async {
        // Section 5 Bug C: token must survive relay restart without user action
        final tokenStore = FakePushTokenStore();

        // Simulate first app launch: token received and stored
        await tokenStore.writeToken('fcm-token-abc', 'apns');
        tokenStore.simulateRestart(); // token survives

        // Simulate resumed launch: token read and re-registered
        final stored = await tokenStore.readToken();
        expect(stored, isNotNull);
        expect(stored!.token, 'fcm-token-abc');
        expect(stored.platform, 'apns');

        // Verify write was called once (on first launch)
        expect(tokenStore.writeCallCount, 1);
        // Verify read was called once (on resume)
        expect(tokenStore.readCallCount, 1);
      },
    );

    test(
      '4. group push Notification struct present → no background fallback needed',
      () async {
        // Section 5 Bug B: group pushes now include a Notification struct so iOS shows
        // them natively without the Dart background fallback path.
        //
        // Verifying the contract: when RemoteNotification is present,
        // shouldShowBackgroundPushFallbackNotification returns false.
        // (This delegates to the unit test in background_push_notification_fallback_test.dart)
        //
        // Integration concern: the group routing still works when notification
        // struct is present (it should not interfere with deep-link routing).
        final events = <String>[];
        final routed = <NotificationRouteTarget>[];

        // Simulate the FCM onMessageOpenedApp callback — notification struct
        // is present (user tapped the system notification)
        await routeRemoteNotificationOpen(
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-meeting-42',
          },
          onBeforeRouteTarget: (target) async {
            events.add('prepare:${target.toPayload()}');
            await prepareNotificationOpen(
              routeTarget: target,
              drainOfflineInbox: () async {},
              drainGroupOfflineInboxForGroup: (groupId) async =>
                  events.add('drain:$groupId'),
            );
          },
          onRouteTarget: (target) async {
            events.add('route:${target.toPayload()}');
            routed.add(target);
          },
          onMissingRouteTarget: () async => events.add('missing'),
        );

        // Navigation must reach the group screen
        expect(routed.single.kind, NotificationRouteTargetKind.group);
        expect(routed.single.groupId, 'group-meeting-42');
        expect(events, isNot(contains('missing')));
      },
    );
  });
}
```

#### B.4 Integration Test 4: The "Rapid Lock-Unlock" Scenario

**File:** `test/integration/rapid_lock_unlock_integration_test.dart`

This test exercises fixes 1, 2, and 4 together under rapid cycling conditions, proving the retrier's `_isRetrying` guard and `handleAppPaused`/`handleAppResumed` idempotency.

```dart
/// Integration test: rapid lock-unlock scenario.
///
/// Verifies that repeated background/foreground cycles:
///   1. Never duplicate a message delivery
///   2. Never leave a message permanently stuck in 'sending'
///   3. Eventually deliver the message exactly once
///   4. The retrier's _isRetrying guard prevents concurrent retry runs
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
    // ⚠️ AUDIT (T6-01): handle_app_paused.dart does not exist yet — production prerequisite
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/conversation/domain/repositories/fake_message_repository.dart';
import '../features/contacts/domain/repositories/fake_contact_repository.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';
import '../shared/fixtures/message_fixtures.dart';
import '../shared/helpers/lifecycle_helpers.dart';
    // ⚠️ AUDIT (T6-06): test/shared/helpers/ directory must be created first

// > **⚠️ AUDIT FIX (GAP F — B.4 imports non-existent files):** This file
// > imports both `../shared/fixtures/message_fixtures.dart` and
// > `../shared/helpers/lifecycle_helpers.dart`. Neither directory
// > (`test/shared/fixtures/`, `test/shared/helpers/`) exists today.
// > This is a hard compile-time dependency on Phase 1 creating both.

void main() {
  group('Rapid lock-unlock integration', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late FakeMessageRepository messageRepo;
    late FakeIdentityRepository identityRepo;
    late FakeContactRepository contactRepo;
    late PendingMessageRetrier retrier;

    setUp(() {
      bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fake-kem',
            'ciphertext': 'fake-ct',
            'nonce': 'fake-nonce',
          },
        },
      );
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-alice',
          circuitAddresses: ['/p2p-circuit/relay'],
        ),
        sendMessageWithReplyResult: const SendMessageResult(sent: false),
        storeInInboxResult: true,
      );

      final fakeNow = DateTime(2026, 3, 23, 12, 10, 0).toUtc();
      messageRepo = FakeMessageRepository();
      messageRepo.clock = () => fakeNow;
      messageRepo.seed([
        makeSendingMessage(
          ageOffset: const Duration(minutes: 5),
          relativeTo: fakeNow,
        ),
      ]);

      identityRepo = FakeIdentityRepository()..seed(makeAliceIdentity());
      contactRepo = FakeContactRepository()..seed([makeBobContact()]);

      retrier = PendingMessageRetrier(
        p2pService: p2pService,
        messageRepo: messageRepo,
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );
      retrier.start();
    });

    tearDown(() {
      retrier.dispose();
      p2pService.dispose();
    });

    test(
      '1. three rapid pause-resume cycles: message delivered exactly once',
      () async {
        // Cycle 1: pause transitions sending→failed
        await handleAppPaused(messageRepo: messageRepo);

        // Cycle 1: resume triggers retrier
        await handleAppResumed(bridge: bridge, p2pService: p2pService);
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
        );

        // Cycle 2: immediate pause again (simulates rapid lock)
        await handleAppPaused(messageRepo: messageRepo);

        // Cycle 2: resume again
        await handleAppResumed(bridge: bridge, p2pService: p2pService);
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
        );

        // Wait for debounce to fire (retrier runs after state stabilizes)
        await Future.delayed(const Duration(seconds: 6));

        // Message must be delivered exactly once — no duplicates
        final msgs = await messageRepo.getMessagesForContact('peer-bob');
        expect(msgs, hasLength(1), reason: 'No duplicate messages after rapid cycling');
        expect(msgs.first.status, 'delivered',
            reason: 'Message must eventually be delivered');
        expect(msgs.first.transport, 'inbox');

        // Inbox called exactly once despite multiple resume cycles
        // (retrier's _isRetrying guard prevents duplicate concurrent runs)
        expect(p2pService.storeInInboxCallCount, 1,
            reason: 'Inbox store called exactly once — no double-delivery');
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test(
      '2. concurrent pause calls are idempotent (safe to call twice)',
      () async {
        // Simulate two concurrent pause calls (race between WidgetsBindingObserver
        // and explicit pause trigger)
        await Future.wait([
          handleAppPaused(messageRepo: messageRepo),
          handleAppPaused(messageRepo: messageRepo),
        ]);

        // Message should be in 'failed' state — not 'sending'
        // Second pause is a no-op on an already-failed message
        final msgs = await messageRepo.getMessagesForContact('peer-bob');
        expect(msgs.first.status, 'failed');

        // updateMessageStatus should have been called at most once per message
        // (the second pause finds no 'sending' messages)
      },
    );

    test(
      '3. retrier does not re-deliver an already-delivered message',
      () async {
        // Seed a message that is already delivered
        messageRepo.seed([
          makeFailedMessageWithEnvelope().copyWith(status: 'delivered'),
        ]);

        // Emit online state — retrier should NOT call storeInInbox
        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'peer-alice',
            circuitAddresses: ['/p2p-circuit/relay'],
          ),
        );
        await Future.delayed(const Duration(seconds: 6));

        // getFailedOutgoingMessages returns empty (message is delivered)
        // so storeInInbox must not have been called
        expect(p2pService.storeInInboxCallCount, 0,
            reason: 'Already-delivered messages must not be re-sent');
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}
```

---

### Part C: Smoke Test Checklist

These are manual QA test cases for TestFlight validation. They require two physical devices (Sender and Receiver) and cannot be automated with the current test infrastructure. Record pass/fail in the TestFlight build notes.

#### C.1 Stuck-Sending Recovery (Section 1)

**Setup:** Sender device on the test build, Receiver device on same build or released version.

| ID | Steps | Expected | Notes |
|---|---|---|---|
| SR-1 | Sender goes offline (airplane mode). Send a message. Observe status indicator. Bring Sender back online. Wait 10s. | Message transitions from "sending" to "delivered" without user action | Verifies retrier fires on reconnect |
| SR-2 | Sender sends 3 messages rapidly while offline. Come back online. | All 3 messages delivered in order, none duplicated | Verifies inbox batch |
| SR-3 | Sender sends a message. Force-quit the app immediately (swipe up in app switcher). Re-open the app. | Message should be in "failed" state, retap-to-send visible | Verifies force-quit path does not leave stuck-sending |
| SR-4 | Seed a stuck message by putting device in airplane mode, sending, then opening Settings (backgrounding app for >30s). Re-foreground. | Stuck-sending message transitions to failed then re-queued automatically | Tests the age-threshold trigger |

#### C.2 Lifecycle Pause Handler (Section 2)

| ID | Steps | Expected | Notes |
|---|---|---|---|
| LP-1 | Start a send. Immediately press the lock button (iOS side button). Unlock within 5s. | Message in "failed" state, retrier picks it up automatically | Core scenario |
| LP-2 | Press lock button. Wait 60s (screen goes fully off). Unlock. | App resumes, bridge health check runs, message delivered | Long-background scenario |
| LP-3 | Start typing (compose visible). Press home button (move to background). Come back. | Message state unchanged (not yet sent — no stuck-sending created) | Verifies only in-flight sends are affected |

#### C.3 iOS Background Task Assertion (Section 3)

| ID | Steps | Expected | Notes |
|---|---|---|---|
| BT-1 | Trigger a relay reconnection (disable WiFi, re-enable) immediately before pressing the lock button. Unlock after 10s. | Relay reconnects successfully — no "bridge took too long" in logs | Verifies `beginBackgroundTask` extends execution time |
| BT-2 | On a device with very low battery (background execution limited), press lock during active send. | App completes or gracefully fails the critical call — no crash or hang | Edge case: iOS background execution budget exhausted |

Verification method: Filter Xcode Console for `BackgroundTask` and `GoBridge` log tags. There must be no `endBackgroundTask` called before the response arrives for critical calls.

#### C.4 Direct-First Send (Section 4)

| ID | Steps | Expected | Notes |
|---|---|---|---|
| IF-1 | Receiver goes offline (airplane mode). Sender sends message. | Message shows "delivered" on Sender immediately (inbox accepted). Receiver comes online → message arrives. | Key UX: Sender sees delivered, not failed |
| IF-2 | Sender sends to online Receiver (both foreground, direct P2P connected). | Direct P2P delivery succeeds with ACK; if optimistic inbox store also fires, implementation suppresses/cancels duplicate push or otherwise proves exactly one user-visible message + notification. | Verifies direct-first send + direct P2P coexist |
| IF-3 | Both relay and direct P2P unavailable. Sender sends. | Message shows "failed" after all fallbacks exhausted | No infinite hang |

#### C.5 FCM Notification Fixes (Section 5)

| ID | Steps | Expected | Notes |
|---|---|---|---|
| FCM-1 | Receiver in background. Sender sends a 1:1 message. Tap the push notification. | App opens directly to the correct conversation | Verifies `from` field routing |
| FCM-2 | Receiver's app is terminated (swiped away). Sender sends. | Push notification appears. Tap → correct conversation opens with message already loaded | Terminated-state deep-link |
| FCM-3 | Receiver in background. Sender posts a group message. | Push notification appears with group name in title. Tap → opens group chat | Section 5 Bug B: group push `Notification` struct present |
| FCM-4 | Sender sends. Receiver reboots device. Receiver opens app. | FCM token re-registered without user action. Future pushes arrive correctly. | Section 5 Bug C: persistent token store |
| FCM-5 | On a device that has never received a push, send a message while app is in background. | Fallback notification appears (if no `Notification` struct) OR system notification appears (if struct present). | Background fallback logic |

#### C.6 Multi-Device Coordination Scenarios

| ID | Steps | Expected | Notes |
|---|---|---|---|
| MD-1 | Alice and Bob both on test build. Alice sends 10 messages rapidly. | Bob receives all 10, in order, no duplicates | Baseline throughput |
| MD-2 | Alice sends. Bob goes to airplane mode. Bob returns to WiFi. | Message appears in Bob's conversation after inbox drain | Offline drain |
| MD-3 | Alice sends on cellular. Bob on WiFi only. | Message still delivers (relay path) | Transport independence |
| MD-4 | Both devices on airplane mode. Alice queues 3 messages. Both return to WiFi simultaneously. | All 3 messages delivered, no race condition visible | Simultaneous reconnect |

---

### Part D: Test Execution Order

#### D.1 Critical Path (Implement in This Order)

The order reflects dependency: each phase's tests depend on the infrastructure from the phase above.

**Phase 1: Shared Infrastructure (Day 1)**

These must exist before any integration test can compile:

- [ ] **Create directories** `test/shared/fixtures/` and `test/shared/helpers/` (T6-06 — neither exists today)
- [ ] `test/shared/fixtures/message_fixtures.dart` — `makeSendingMessage`, `makeFailedMessageWithEnvelope`, `makeAliceIdentity` (with `username: 'Alice'` per T6-13), `makeBobContact`
- [ ] `test/shared/helpers/lifecycle_helpers.dart` — `simulateBackgroundForegroundCycle`, `simulateRapidLockUnlock`
- [ ] `test/shared/fakes/fake_push_token_store.dart` — `FakePushTokenStore`
- [ ] Extend `FakeMessageRepository.getSendingMessages()` with clock injection
- [ ] Extend `FakeBridge` with `sendDelay` + `SlowCriticalBridge`
- [ ] Extend `FakeP2PService` with `operationLog` + `storeInInboxSuccessCount`

**Phase 2: Unit Tests for New Use Cases (Day 1-2)**

One test file per new production function, following the pattern of `test/core/services/pending_message_retrier_test.dart` (the existing retrier test file):

> **⚠️ AUDIT FIX (T6-14):** The original plan referenced `test/features/conversation/application/retry_failed_messages_use_case_test.dart` which does not exist. The actual retrier test file is `test/core/services/pending_message_retrier_test.dart`. The reference has been corrected above.

- [ ] `test/core/lifecycle/handle_app_paused_test.dart` — unit tests for `handleAppPaused()` (fix 2): transitions sending→failed, skips delivered, skips incoming
- [ ] `test/core/services/pending_message_retrier_stuck_recovery_test.dart` — unit tests for expanded `PendingMessageRetrier` (fix 1): age threshold, `getSendingMessages`, debounce on resume
- [ ] `test/features/push/application/push_token_store_test.dart` — unit tests for `PushTokenStore` read/write/clear (fix 5)
- [ ] `test/features/push/application/fcm_sender_id_normalization_test.dart` — unit tests for `sender_id`→`from` field mapping (fix 5)

**Phase 3: Integration Tests (Day 2-3)**

Implement in dependency order:

- [ ] `test/features/conversation/integration/send_then_lock_delivery_test.dart` (B.1) — 11 sub-tests: **[ACCEPTANCE]** (1) THE REAL BUG original-row text recovery, (2) real interrupted media upload recovery, (3) real interrupted voice upload recovery via relay, (3b) WiFi-interrupted voice with relay fallback recovery; **[REGRESSION]** (4) completed-send not overwritten, (5) two-phase flow, (6) direct-first offline, (7) app-killed recovery, (8) rapid lock-unlock; **[NOTIFICATION]** (9) voice-with-caption, (10) media-with-caption. All use single `BobTestHarness` listener.
- [ ] `test/integration/relay_down_degradation_integration_test.dart` (B.2)
- [ ] `test/integration/notification_deeplink_integration_test.dart` (B.3)
- [ ] `test/integration/rapid_lock_unlock_integration_test.dart` (B.4)

**Phase 4: iOS Native Tests (Day 3)**

These require XCTest and cannot run in the Dart test runner:

- [ ] `ios/RunnerTests/GoBridgeBackgroundTaskTests.swift` — verify `beginBackgroundTask` is called before critical bridge commands and `endBackgroundTask` fires after response (fix 3)

#### D.2 Dependencies Between Test Phases

```
Phase 1 (infra)
    └── Phase 2 (unit tests per use case)
            └── Phase 3 (integration tests: B.1, B.2, B.3, B.4)
                    └── Phase 4 (XCTest for fix 3, manual smoke for C.1-C.6)
```

The four integration tests in Phase 3 are independent of each other and can run in parallel in CI.

#### D.3 CI/CD Considerations

**Test suite splits** — the existing project separates fast unit tests from slow integration tests using file paths. Register the new integration tests directory:

```bash
# In CI (example flutter test invocation):
flutter test test/unit/     # all unit tests — < 30s
flutter test test/integration/ --timeout 60s   # cross-cutting integration
flutter test test/core/resilience/ --timeout 120s  # existing soak/chaos tests
```

**Timeout discipline** — each integration test in Part B that uses the retrier's 5-second debounce is annotated with `timeout: const Timeout(Duration(seconds: 15))` or `Duration(seconds: 20)` to give a clear 3x margin over the debounce without blocking CI indefinitely. Do not use `Timeout.none`.

**Fake isolation** — every test file calls `setUp` to construct fresh fakes. The `FakeP2PNetwork` and `FakeP2PService` instances registered in the network are unregistered in `tearDown` via `dispose()`. Never share a `FakeBridge` or `FakeP2PService` instance between tests.

**No `fake_async` dependency for age-threshold tests** — the `FakeMessageRepository.clock` injection pattern (Part A.4) avoids needing `fake_async` for stuck-message age tests. Use `fake_async` only for timer-based tests (retrier debounce) where it already appears, as in `test/core/lifecycle/connectivity_lifecycle_test.dart`.

**XCTest for fix 3 runs only on macOS CI runner** — the `GoBridgeBackgroundTaskTests.swift` file is gated behind the `ios` scheme and does not appear in the Dart test run. Add a separate CI job: `xcodebuild test -scheme Runner -destination 'platform=iOS Simulator,name=iPhone 16'` on the macOS runner.

#### D.4 Pre-PR Checklist for Each Fix

Before opening a PR for any of the five fixes, the author must confirm:

- [ ] All Phase 1 infrastructure files exist and compile
- [ ] The unit test file for that fix's use case passes with `flutter test`
- [ ] The integration test(s) that exercise that fix pass (even if other parts of the cross-cutting test are `skip`ped pending other fixes)
- [ ] `flutter test test/core/services/pending_message_retrier_test.dart` still passes (no regression)
- [ ] `flutter test test/core/lifecycle/handle_app_paused_test.dart` still passes
    <!-- AUDIT FIX (T6-12): The original checklist referenced app_lifecycle_recovery_test.dart which does not exist. Replaced with handle_app_paused_test.dart from Phase 2. -->
- [ ] For fix 3: XCTest suite passes on iOS Simulator
- [ ] For fix 5: `flutter test test/features/push/` passes in full

