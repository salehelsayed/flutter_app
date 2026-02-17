import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/orbit/application/load_orbit_data_use_case.dart';

// -- Fake Contact Repository --
class FakeContactRepository implements ContactRepository {
  final List<ContactModel> contacts;

  FakeContactRepository({this.contacts = const []});

  @override
  Future<List<ContactModel>> getAllContacts() async => contacts;

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      contacts.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      contacts.where((c) => c.isArchived).toList();

  @override
  Future<ContactModel?> getContact(String peerId) async =>
      contacts.where((c) => c.peerId == peerId).firstOrNull;

  @override
  Future<void> addContact(ContactModel contact) async {}
  @override
  Future<void> deleteContact(String peerId) async {}
  @override
  Future<bool> contactExists(String peerId) async => false;
  @override
  Future<int> getContactCount() async => contacts.length;
  @override
  Future<void> archiveContact(String peerId) async {}
  @override
  Future<void> unarchiveContact(String peerId) async {}
  @override
  Future<void> blockContact(String peerId) async {}
  @override
  Future<void> unblockContact(String peerId) async {}
}

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final Map<String, int> messageCounts;

  FakeMessageRepository({this.messageCounts = const {}});

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      messageCounts[contactPeerId] ?? 0;

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async => null;

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async => 0;

  @override
  Future<void> saveMessage(ConversationMessage message) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async => [];
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<int> markConversationAsRead(String contactPeerId) async => 0;
  @override
  Future<int> getTotalUnreadCount() async => 0;
  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;
  @override
  Future<int> deleteMessagesForContact(String contactPeerId) async => 0;
}

ContactModel _makeContact(String peerId, {bool isArchived = false}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'User-$peerId',
    signature: 'sig-$peerId',
    scannedAt: '2026-01-01T00:00:00.000Z',
    isArchived: isArchived,
    archivedAt: isArchived ? '2026-02-01T00:00:00.000Z' : null,
  );
}

void main() {
  group('loadOrbitData', () {
    test('default excludes archived contacts', () async {
      final contacts = [
        _makeContact('peer-A'),
        _makeContact('peer-B'),
        _makeContact('peer-C', isArchived: true),
      ];

      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
      );

      expect(result.length, 2);
      expect(result.any((f) => f.peerId == 'peer-C'), isFalse);
    });

    test('includeArchived=true returns only archived contacts', () async {
      final contacts = [
        _makeContact('peer-A'),
        _makeContact('peer-B'),
        _makeContact('peer-C', isArchived: true),
      ];

      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(),
        includeArchived: true,
      );

      expect(result.length, 1);
      expect(result[0].peerId, 'peer-C');
    });

    test('sorts by messageCount descending', () async {
      final contacts = [
        _makeContact('peer-A'),
        _makeContact('peer-B'),
      ];

      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: FakeMessageRepository(
          messageCounts: {'peer-A': 5, 'peer-B': 10},
        ),
      );

      expect(result[0].peerId, 'peer-B');
      expect(result[0].messageCount, 10);
      expect(result[1].peerId, 'peer-A');
      expect(result[1].messageCount, 5);
    });

    test('returns empty list when no contacts', () async {
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
      );

      expect(result, isEmpty);
    });
  });
}
