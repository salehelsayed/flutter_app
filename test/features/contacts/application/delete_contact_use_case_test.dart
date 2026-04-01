import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/contacts/application/delete_contact_use_case.dart';

class FakeContactRepository implements ContactRepository {
  final List<String> deletedPeerIds = [];
  bool shouldThrow = false;

  @override
  Future<void> deleteContact(String peerId) async {
    if (shouldThrow) throw Exception('DB error');
    deletedPeerIds.add(peerId);
  }

  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<List<ContactModel>> getAllContacts() async => [];
  @override
  Future<ContactModel?> getContact(String peerId) async => null;
  @override
  Future<int> getContactCount() async => 0;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
  @override
  Future<List<ContactModel>> getActiveContacts() async => [];
  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class FakeMessageRepository implements MessageRepository {
  final List<String> deletedForContact = [];
  bool shouldThrow = false;

  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async {
    if (shouldThrow) throw Exception('DB error');
    deletedForContact.add(contactPeerId);
    return 5; // arbitrary count
  }

  @override
  Future<int> deleteMessage(String id) async => 0;

  @override
  Future<void> saveMessage(ConversationMessage message) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => [];
  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => null;
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
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
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];

  @override
  Future<List<ConversationMessage>> getUnackedOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<int> recoverStuckSendingMessages({
    required Duration olderThan,
  }) async => 0;

  @override
  Future<void> updateWireEnvelope(String id, String envelope) async {}

  @override
  Future<List<ConversationMessage>> getStuckSendingOutgoingMessages({
    required Duration olderThan,
  }) async => [];

  @override
  Future<List<ConversationMessage>> getSendingOutgoingMessages() async => [];

  @override
  Future<int> conditionalTransitionStatus(
    String id, {
    required String fromStatus,
    required String toStatus,
  }) async => 0;
}

void main() {
  group('deleteContactAndMessages use case', () {
    test('deletes messages then contact', () async {
      final contactRepo = FakeContactRepository();
      final messageRepo = FakeMessageRepository();

      await deleteContactAndMessages(
        contactRepo: contactRepo,
        messageRepo: messageRepo,
        peerId: 'peer-1234567890',
      );

      expect(messageRepo.deletedForContact, ['peer-1234567890']);
      expect(contactRepo.deletedPeerIds, ['peer-1234567890']);
    });

    test('rethrows errors from message repository', () async {
      final contactRepo = FakeContactRepository();
      final messageRepo = FakeMessageRepository()..shouldThrow = true;

      expect(
        () => deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });

    test('rethrows errors from contact repository', () async {
      final contactRepo = FakeContactRepository()..shouldThrow = true;
      final messageRepo = FakeMessageRepository();

      expect(
        () => deleteContactAndMessages(
          contactRepo: contactRepo,
          messageRepo: messageRepo,
          peerId: 'peer-1234567890',
        ),
        throwsException,
      );
    });
  });
}
