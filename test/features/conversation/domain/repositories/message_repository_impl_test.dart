import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository_impl.dart';

void main() {
  // In-memory store for testing
  late Map<String, Map<String, Object?>> store;
  late MessageRepositoryImpl repo;

  setUp(() {
    store = {};

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
        if (store.containsKey(id)) {
          store[id]!['status'] = status;
        }
      },
      dbLoadMessage: (id) async {
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
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: senderPeerId,
      text: text,
      timestamp: timestamp,
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-02-09T10:00:01.000Z',
    );
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

    test('updateMessageStatus changes status', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1', status: 'sent'));
      await repo.updateMessageStatus('msg-1', 'delivered');

      expect(store['msg-1']!['status'], 'delivered');
    });

    test('messageExists returns true for existing message', () async {
      await repo.saveMessage(makeMessage(id: 'msg-1'));
      expect(await repo.messageExists('msg-1'), true);
    });

    test('messageExists returns false for non-existing message', () async {
      expect(await repo.messageExists('nonexistent'), false);
    });
  });
}
