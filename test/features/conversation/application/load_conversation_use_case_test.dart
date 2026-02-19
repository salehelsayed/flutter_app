import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/load_conversation_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final Map<String, List<ConversationMessage>> messagesByContact;

  FakeMessageRepository({this.messagesByContact = const {}});

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async {
    return messagesByContact[contactPeerId] ?? [];
  }

  @override
  Future<void> saveMessage(ConversationMessage message) async {}

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async {
    return null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {}

  @override
  Future<bool> messageExists(String id) async => false;

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async => 0;

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
    final all = messagesByContact[contactPeerId] ?? [];
    var filtered = all;
    if (beforeTimestamp != null) {
      filtered = all.where((m) => m.timestamp.compareTo(beforeTimestamp) < 0).toList();
    }
    filtered.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = filtered.take(limit).toList();
    return page.reversed.toList();
  }

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
}

void main() {
  group('loadConversation', () {
    test('returns empty list when no messages for contact', () async {
      final repo = FakeMessageRepository();

      final result = await loadConversation(
        messageRepo: repo,
        contactPeerId: 'nonexistent-peer',
      );

      expect(result, isEmpty);
    });

    test('returns messages for existing contact', () async {
      final messages = [
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-A',
          senderPeerId: 'contact-A',
          text: 'First message',
          timestamp: '2026-02-09T10:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T10:00:01.000Z',
        ),
        ConversationMessage(
          id: 'msg-2',
          contactPeerId: 'contact-A',
          senderPeerId: 'my-peer',
          text: 'Reply',
          timestamp: '2026-02-09T10:01:00.000Z',
          status: 'sent',
          isIncoming: false,
          createdAt: '2026-02-09T10:01:01.000Z',
        ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      final result = await loadConversation(
        messageRepo: repo,
        contactPeerId: 'contact-A',
      );

      expect(result.length, 2);
      expect(result[0].id, 'msg-1');
      expect(result[1].id, 'msg-2');
    });
  });

  group('loadConversationPage', () {
    test('returns most recent page when no cursor', () async {
      final messages = [
        for (var i = 1; i <= 5; i++)
          ConversationMessage(
            id: 'msg-$i',
            contactPeerId: 'contact-A',
            senderPeerId: 'contact-A',
            text: 'Message $i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T${10 + i}:00:01.000Z',
          ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
      );

      expect(result.length, 3);
      // Most recent 3 in ASC order: msg-3, msg-4, msg-5
      expect(result[0].id, 'msg-3');
      expect(result[1].id, 'msg-4');
      expect(result[2].id, 'msg-5');
    });

    test('returns older page with cursor', () async {
      final messages = [
        for (var i = 1; i <= 5; i++)
          ConversationMessage(
            id: 'msg-$i',
            contactPeerId: 'contact-A',
            senderPeerId: 'contact-A',
            text: 'Message $i',
            timestamp: '2026-02-09T${10 + i}:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-02-09T${10 + i}:00:01.000Z',
          ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      // Before msg-3's timestamp (13:00) → should get msg-1, msg-2
      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
        beforeTimestamp: '2026-02-09T13:00:00.000Z',
      );

      expect(result.length, 2);
      expect(result[0].id, 'msg-1');
      expect(result[1].id, 'msg-2');
    });

    test('returns empty list when no more messages', () async {
      final messages = [
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-A',
          senderPeerId: 'contact-A',
          text: 'Only message',
          timestamp: '2026-02-09T11:00:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T11:00:01.000Z',
        ),
      ];

      final repo = FakeMessageRepository(
        messagesByContact: {'contact-A': messages},
      );

      // Cursor older than all messages
      final result = await loadConversationPage(
        messageRepo: repo,
        contactPeerId: 'contact-A',
        pageSize: 3,
        beforeTimestamp: '2026-02-09T10:00:00.000Z',
      );

      expect(result, isEmpty);
    });
  });
}
