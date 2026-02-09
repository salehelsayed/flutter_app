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
}
