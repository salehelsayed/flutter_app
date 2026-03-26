import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

void main() {
  // In-memory store for testing
  late Map<String, Map<String, Object?>> store;
  late int dbLoadMessageCallCount;
  late MessageRepositoryImpl repo;

  setUp(() {
    store = {};
    dbLoadMessageCallCount = 0;

    repo = MessageRepositoryImpl(
      dbInsertMessage: (row) async {
        store[row['id'] as String] = Map.from(row);
      },
      dbLoadMessagesForContact: (contactPeerId) async {
        return store.values
            .where((row) => row['contact_peer_id'] == contactPeerId)
            .toList()
          ..sort((a, b) => (a['timestamp'] as String)
              .compareTo(b['timestamp'] as String));
      },
      dbLoadLatestMessageForContact: (contactPeerId) async {
        final rows = store.values
            .where((row) => row['contact_peer_id'] == contactPeerId)
            .toList()
          ..sort((a, b) => (b['timestamp'] as String)
              .compareTo(a['timestamp'] as String));
        return rows.isNotEmpty ? rows.first : null;
      },
      dbUpdateMessageStatus: (id, status) async {
        if (!store.containsKey(id)) {
          return 0;
        }
        store[id]!['status'] = status;
        return 1;
      },
      dbLoadMessage: (id) async {
        dbLoadMessageCallCount++;
        return store[id];
      },
      dbCountMessagesForContact: (contactPeerId) async {
        return store.values
            .where((row) => row['contact_peer_id'] == contactPeerId)
            .length;
      },
      dbMarkConversationAsRead: (contactPeerId) async {
        var count = 0;
        final now = DateTime.now().toUtc().toIso8601String();
        for (final row in store.values) {
          if (row['contact_peer_id'] == contactPeerId &&
              row['is_incoming'] == 1 &&
              row['read_at'] == null) {
            row['read_at'] = now;
            count++;
          }
        }
        return count;
      },
      dbCountUnreadForContact: (contactPeerId) async {
        return store.values
            .where((row) =>
                row['contact_peer_id'] == contactPeerId &&
                row['is_incoming'] == 1 &&
                row['read_at'] == null)
            .length;
      },
      dbCountTotalUnread: () async {
        return store.values
            .where((row) =>
                row['is_incoming'] == 1 && row['read_at'] == null)
            .length;
      },
      dbCountTotalUnreadExcludingArchived: () async {
        return store.values
            .where((row) =>
                row['is_incoming'] == 1 && row['read_at'] == null)
            .length;
      },
      dbDeleteMessagesForContact: (contactPeerId) async {
        final keysToRemove = store.entries
            .where((e) => e.value['contact_peer_id'] == contactPeerId)
            .map((e) => e.key)
            .toList();
        for (final key in keysToRemove) {
          store.remove(key);
        }
        return keysToRemove.length;
      },
      dbLoadMessagesPage: (contactPeerId, {limit = 50, beforeTimestamp}) async {
        var rows = store.values
            .where((row) => row['contact_peer_id'] == contactPeerId)
            .toList();
        if (beforeTimestamp != null) {
          rows = rows.where((row) => (row['timestamp'] as String).compareTo(beforeTimestamp) < 0).toList();
        }
        rows.sort((a, b) => (b['timestamp'] as String).compareTo(a['timestamp'] as String));
        final page = rows.take(limit).toList();
        return page.reversed.toList();
      },
      dbLoadFailedOutgoingMessages: () async {
        return store.values
            .where((row) =>
                row['status'] == 'failed' && row['is_incoming'] == 0)
            .toList()
          ..sort((a, b) => (a['timestamp'] as String)
              .compareTo(b['timestamp'] as String));
      },
      dbLoadUnackedOutgoingMessages: ({required olderThan, limit = 50}) async {
        return store.values
            .where((row) =>
                row['status'] == 'sent' &&
                row['is_incoming'] == 0 &&
                row['wire_envelope'] != null &&
                (row['timestamp'] as String)
                        .compareTo(olderThan.toUtc().toIso8601String()) <
                    0)
            .take(limit)
            .toList()
          ..sort((a, b) => (a['timestamp'] as String)
              .compareTo(b['timestamp'] as String));
      },
      dbLoadConversationThreadSummaries: (contactPeerIds) async {
        final summaries = <Map<String, Object?>>[];
        for (final contactPeerId in contactPeerIds) {
          final rows = store.values
              .where((row) => row['contact_peer_id'] == contactPeerId)
              .toList()
            ..sort((a, b) {
              final timestampOrder = (b['timestamp'] as String)
                  .compareTo(a['timestamp'] as String);
              if (timestampOrder != 0) return timestampOrder;
              final createdAtA = a['created_at'] as String? ?? '';
              final createdAtB = b['created_at'] as String? ?? '';
              return createdAtB.compareTo(createdAtA);
            });
          final latest = rows.isEmpty ? null : rows.first;
          summaries.add({
            'contact_peer_id': contactPeerId,
            'message_count': rows.length,
            'unread_count': rows
                .where((row) =>
                    row['is_incoming'] == 1 && row['read_at'] == null)
                .length,
            'latest_id': latest?['id'],
            'latest_contact_peer_id': latest?['contact_peer_id'],
            'latest_sender_peer_id': latest?['sender_peer_id'],
            'latest_text': latest?['text'],
            'latest_timestamp': latest?['timestamp'],
            'latest_status': latest?['status'],
            'latest_is_incoming': latest?['is_incoming'],
            'latest_created_at': latest?['created_at'],
            'latest_read_at': latest?['read_at'],
            'latest_quoted_message_id': latest?['quoted_message_id'],
            'latest_transport': latest?['transport'],
            'latest_wire_envelope': latest?['wire_envelope'],
          });
        }
        return summaries;
      },
      dbRecoverStuckSendingMessages: ({required DateTime olderThan, int limit = 50}) async => 0,
      dbUpdateWireEnvelope: (id, wireEnvelope) async {},
      dbLoadStuckSendingOutgoingMessages: ({required DateTime olderThan, int limit = 50}) async => [],
      dbLoadSendingOutgoingMessages: () async => [],
      dbConditionalTransitionStatus: (
        id, {
        required fromStatus,
        required toStatus,
      }) async {
        final row = store[id];
        if (row == null || row['status'] != fromStatus) {
          return 0;
        }
        row['status'] = toStatus;
        return 1;
      },
    );
  });

  ConversationMessage makeMessage({
    String id = 'msg-1',
    String contactPeerId = 'contact-peer',
    String senderPeerId = 'sender-peer',
    String text = 'Hello',
    String timestamp = '2026-02-09T10:00:00.000Z',
    String status = 'sent',
    bool isIncoming = false,
    String createdAt = '2026-02-09T10:00:01.000Z',
    String? readAt,
    String? quotedMessageId,
    String? transport,
    String? wireEnvelope,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: createdAt,
      readAt: readAt,
      quotedMessageId: quotedMessageId,
      transport: transport,
      wireEnvelope: wireEnvelope,
    );
  }

  void expectMessageShape(
    ConversationMessage actual,
    ConversationMessage expected,
  ) {
    expect(actual.id, expected.id);
    expect(actual.contactPeerId, expected.contactPeerId);
    expect(actual.senderPeerId, expected.senderPeerId);
    expect(actual.text, expected.text);
    expect(actual.timestamp, expected.timestamp);
    expect(actual.status, expected.status);
    expect(actual.isIncoming, expected.isIncoming);
    expect(actual.createdAt, expected.createdAt);
    expect(actual.readAt, expected.readAt);
    expect(actual.quotedMessageId, expected.quotedMessageId);
    expect(actual.transport, expected.transport);
    expect(actual.wireEnvelope, expected.wireEnvelope);
  }

  group('MessageRepositoryImpl', () {
    test('saveMessage persists to store', () async {
      final msg = makeMessage();
      await repo.saveMessage(msg);

      expect(store.containsKey('msg-1'), true);
      expect(store['msg-1']!['text'], 'Hello');
    });

    test('getMessagesForContact returns empty list when no messages', () async {
      final result = await repo.getMessagesForContact('nonexistent');
      expect(result, isEmpty);
    });

    test('getMessagesForContact returns messages ordered by timestamp', () async {
      await repo.saveMessage(makeMessage(
        id: 'msg-2',
        timestamp: '2026-02-09T11:00:00.000Z',
      ));
      await repo.saveMessage(makeMessage(
        id: 'msg-1',
        timestamp: '2026-02-09T10:00:00.000Z',
      ));
      await repo.saveMessage(makeMessage(
        id: 'msg-3',
        timestamp: '2026-02-09T12:00:00.000Z',
      ));

      final messages = await repo.getMessagesForContact('contact-peer');
      expect(messages.length, 3);
      expect(messages[0].id, 'msg-1');
      expect(messages[1].id, 'msg-2');
      expect(messages[2].id, 'msg-3');
    });

    test('getMessagesForContact filters by contactPeerId', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', contactPeerId: 'peer-A'));
      await repo.saveMessage(makeMessage(id: 'msg-2', contactPeerId: 'peer-B'));

      final messagesA = await repo.getMessagesForContact('peer-A');
      expect(messagesA.length, 1);
      expect(messagesA[0].id, 'msg-1');

      final messagesB = await repo.getMessagesForContact('peer-B');
      expect(messagesB.length, 1);
      expect(messagesB[0].id, 'msg-2');
    });

    test('getLatestMessageForContact returns most recent', () async {
      await repo.saveMessage(makeMessage(
        id: 'msg-1',
        timestamp: '2026-02-09T10:00:00.000Z',
      ));
      await repo.saveMessage(makeMessage(
        id: 'msg-2',
        timestamp: '2026-02-09T12:00:00.000Z',
      ));

      final latest = await repo.getLatestMessageForContact('contact-peer');
      expect(latest, isNotNull);
      expect(latest!.id, 'msg-2');
    });

    test('getLatestMessageForContact returns null when none exist', () async {
      final latest = await repo.getLatestMessageForContact('nonexistent');
      expect(latest, isNull);
    });

    test('getConversationThreadSummaries returns counts and latest rows', () async {
      await repo.saveMessage(makeMessage(
        id: 'msg-1',
        contactPeerId: 'peer-A',
        text: 'older',
        timestamp: '2026-02-09T10:00:00.000Z',
        isIncoming: true,
      ));
      await repo.saveMessage(makeMessage(
        id: 'msg-2',
        contactPeerId: 'peer-A',
        text: 'newer',
        timestamp: '2026-02-09T11:00:00.000Z',
        isIncoming: true,
      ));

      final summaries = await repo.getConversationThreadSummaries([
        'peer-A',
        'peer-B',
      ]);

      expect(summaries['peer-A']!.messageCount, 2);
      expect(summaries['peer-A']!.unreadCount, 2);
      expect(summaries['peer-A']!.latestMessage!.id, 'msg-2');
      expect(summaries['peer-B']!.messageCount, 0);
      expect(summaries['peer-B']!.latestMessage, isNull);
    });

    test('updateMessageStatus changes status', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', status: 'sent'));
      await repo.updateMessageStatus('msg-1', 'delivered');

      expect(store['msg-1']!['status'], 'delivered');
    });

    test(
      'updateMessageStatus emits updated message exactly once without reloading cached row',
      () async {
        final original = makeMessage(
          id: 'msg-update-stream',
          text: 'Needs ACK',
          timestamp: '2026-02-09T10:02:00.000Z',
          status: 'sent',
          createdAt: '2026-02-09T10:02:01.000Z',
          quotedMessageId: 'quoted-123',
          transport: 'relay',
          wireEnvelope: '{"type":"chat_message"}',
        );
        await repo.saveMessage(original);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.updateMessageStatus(original.id, 'delivered');
        await Future<void>.delayed(Duration.zero);

        expect(dbLoadMessageCallCount, 0);
        expect(emitted, hasLength(1));
        expectMessageShape(
          emitted.single,
          original.copyWith(status: 'delivered'),
        );
        expect(store[original.id]!['status'], 'delivered');
      },
    );

    test(
      'updateMessageStatus does not emit stale cached message when the row no longer exists',
      () async {
        final original = makeMessage(
          id: 'msg-update-missing-row',
          text: 'Missing row',
          status: 'sending',
        );
        await repo.saveMessage(original);
        store.remove(original.id);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        await repo.updateMessageStatus(original.id, 'failed');
        await Future<void>.delayed(Duration.zero);

        expect(dbLoadMessageCallCount, 0);
        expect(emitted, isEmpty);
      },
    );

    test(
      'conditionalTransitionStatus emits updated message exactly once without reloading cached row',
      () async {
        final original = makeMessage(
          id: 'msg-conditional-stream',
          text: 'Pause me',
          timestamp: '2026-02-09T10:03:00.000Z',
          status: 'sending',
          createdAt: '2026-02-09T10:03:01.000Z',
          transport: 'direct',
        );
        await repo.saveMessage(original);
        dbLoadMessageCallCount = 0;

        final emitted = <ConversationMessage>[];
        final sub = repo.messageChanges.listen(emitted.add);
        addTearDown(sub.cancel);

        final updated = await repo.conditionalTransitionStatus(
          original.id,
          fromStatus: 'sending',
          toStatus: 'failed',
        );
        await Future<void>.delayed(Duration.zero);

        expect(updated, 1);
        expect(dbLoadMessageCallCount, 0);
        expect(emitted, hasLength(1));
        expectMessageShape(
          emitted.single,
          original.copyWith(status: 'failed'),
        );
      },
    );

    test('messageExists returns true for existing message', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1'));
      expect(await repo.messageExists('msg-1'), true);
    });

    test('messageExists returns false for non-existing message', () async {
      expect(await repo.messageExists('nonexistent'), false);
    });

    test('getMessagesPage returns most recent page', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.saveMessage(makeMessage(
          id: 'msg-$i',
          timestamp: '2026-02-09T${10 + i}:00:00.000Z',
        ));
      }

      final page = await repo.getMessagesPage('contact-peer', limit: 3);
      expect(page.length, 3);
      expect(page[0].id, 'msg-3');
      expect(page[1].id, 'msg-4');
      expect(page[2].id, 'msg-5');
    });

    test('getMessagesPage returns older page with cursor', () async {
      for (var i = 1; i <= 5; i++) {
        await repo.saveMessage(makeMessage(
          id: 'msg-$i',
          timestamp: '2026-02-09T${10 + i}:00:00.000Z',
        ));
      }

      final page = await repo.getMessagesPage(
        'contact-peer',
        limit: 3,
        beforeTimestamp: '2026-02-09T13:00:00.000Z',
      );
      expect(page.length, 2);
      expect(page[0].id, 'msg-1');
      expect(page[1].id, 'msg-2');
    });
  });
}
