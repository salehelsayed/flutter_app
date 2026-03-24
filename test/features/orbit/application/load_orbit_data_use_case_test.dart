import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/conversation_thread_summary_repository.dart';
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
  @override
  Future<void> dismissIntroBanner(String peerId) async {}
  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

// -- Fake Message Repository --
class FakeMessageRepository
    implements MessageRepository, ConversationThreadSummaryRepository {
  final Map<String, int> messageCounts;
  final Map<String, ConversationMessage?> latestMessages;
  final Map<String, int> unreadCounts;
  int getConversationThreadSummariesCallCount = 0;
  int getConversationThreadSummaryCallCount = 0;

  FakeMessageRepository({
    this.messageCounts = const {},
    this.latestMessages = const {},
    this.unreadCounts = const {},
  });

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async =>
      messageCounts[contactPeerId] ?? 0;

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async => latestMessages[contactPeerId];

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async =>
      unreadCounts[contactPeerId] ?? 0;

  @override
  Future<void> saveMessage(ConversationMessage message) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async => [];
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
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
  Future<int> recoverStuckSendingMessages({required Duration olderThan}) async => 0;

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

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) async {
    getConversationThreadSummaryCallCount++;
    return ConversationThreadSummary(
      contactPeerId: contactPeerId,
      messageCount: messageCounts[contactPeerId] ?? 0,
      unreadCount: unreadCounts[contactPeerId] ?? 0,
      latestMessage: latestMessages[contactPeerId],
    );
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) async {
    getConversationThreadSummariesCallCount++;
    return {
      for (final contactPeerId in contactPeerIds)
        contactPeerId: ConversationThreadSummary(
          contactPeerId: contactPeerId,
          messageCount: messageCounts[contactPeerId] ?? 0,
          unreadCount: unreadCounts[contactPeerId] ?? 0,
          latestMessage: latestMessages[contactPeerId],
        ),
    };
  }
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

      final repo = FakeMessageRepository();
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: repo,
      );

      expect(result.length, 2);
      expect(result.any((f) => f.peerId == 'peer-C'), isFalse);
      expect(repo.getConversationThreadSummariesCallCount, 1);
    });

    test('includeArchived=true returns only archived contacts', () async {
      final contacts = [
        _makeContact('peer-A'),
        _makeContact('peer-B'),
        _makeContact('peer-C', isArchived: true),
      ];

      final repo = FakeMessageRepository();
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: repo,
        includeArchived: true,
      );

      expect(result.length, 1);
      expect(result[0].peerId, 'peer-C');
      expect(repo.getConversationThreadSummariesCallCount, 1);
    });

    test('sorts by most recent message first', () async {
      final contacts = [_makeContact('peer-A'), _makeContact('peer-B')];

      final msgA = ConversationMessage(
        id: 'msg-a',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'older',
        timestamp: '2026-01-01T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-01-01T00:00:00.000Z',
      );
      final msgB = ConversationMessage(
        id: 'msg-b',
        contactPeerId: 'peer-B',
        senderPeerId: 'peer-B',
        text: 'newer',
        timestamp: '2026-02-01T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-02-01T00:00:00.000Z',
      );

      final repo = FakeMessageRepository(
        messageCounts: {'peer-A': 10, 'peer-B': 5},
        latestMessages: {'peer-A': msgA, 'peer-B': msgB},
      );
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: repo,
      );

      // peer-B has the more recent message, so it comes first
      // even though peer-A has more total messages
      expect(result[0].peerId, 'peer-B');
      expect(result[1].peerId, 'peer-A');
      expect(repo.getConversationThreadSummariesCallCount, 1);
    });

    test('preserves mixed-script latest activity during bulk load', () async {
      final contacts = [
        _makeContact('peer-A'),
        _makeContact('peer-B'),
      ];

      final msgA = ConversationMessage(
        id: 'msg-a',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'مرحبا Hello 123',
        timestamp: '2026-03-01T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-03-01T00:00:00.000Z',
      );
      final msgB = ConversationMessage(
        id: 'msg-b',
        contactPeerId: 'peer-B',
        senderPeerId: 'peer-B',
        text: 'Hello مرحبا 123',
        timestamp: '2026-03-02T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-03-02T00:00:00.000Z',
      );

      final repo = FakeMessageRepository(
        latestMessages: {'peer-A': msgA, 'peer-B': msgB},
      );
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(contacts: contacts),
        messageRepo: repo,
      );

      expect(result[0].peerId, 'peer-B');
      expect(result[0].lastActivity, 'Hello مرحبا 123');
      expect(result[1].peerId, 'peer-A');
      expect(result[1].lastActivity, 'مرحبا Hello 123');
    });

    test('returns empty list when no contacts', () async {
      final repo = FakeMessageRepository();
      final result = await loadOrbitData(
        contactRepo: FakeContactRepository(),
        messageRepo: repo,
      );

      expect(result, isEmpty);
      expect(repo.getConversationThreadSummariesCallCount, 0);
    });

    test('loads a single friend snapshot by peer id', () async {
      final msg = ConversationMessage(
        id: 'msg-a',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'Most recent',
        timestamp: '2026-03-01T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-03-01T00:00:00.000Z',
      );

      final repo = FakeMessageRepository(
        messageCounts: const {'peer-A': 3},
        latestMessages: {'peer-A': msg},
        unreadCounts: const {'peer-A': 2},
      );
      final result = await loadOrbitFriendSnapshot(
        contactRepo: FakeContactRepository(contacts: [_makeContact('peer-A')]),
        messageRepo: repo,
        contactPeerId: 'peer-A',
      );

      expect(result, isNotNull);
      expect(result!.peerId, 'peer-A');
      expect(result.messageCount, 3);
      expect(result.lastActivity, 'Most recent');
      expect(result.unreadCount, 2);
      expect(repo.getConversationThreadSummaryCallCount, 1);
    });

    test('preserves mixed-script latest activity in single snapshot', () async {
      final msg = ConversationMessage(
        id: 'msg-a',
        contactPeerId: 'peer-A',
        senderPeerId: 'peer-A',
        text: 'مرحبا Hello 123',
        timestamp: '2026-03-01T00:00:00.000Z',
        isIncoming: true,
        status: 'delivered',
        createdAt: '2026-03-01T00:00:00.000Z',
      );

      final repo = FakeMessageRepository(
        messageCounts: const {'peer-A': 3},
        latestMessages: {'peer-A': msg},
        unreadCounts: const {'peer-A': 2},
      );
      final result = await loadOrbitFriendSnapshot(
        contactRepo: FakeContactRepository(contacts: [_makeContact('peer-A')]),
        messageRepo: repo,
        contactPeerId: 'peer-A',
      );

      expect(result, isNotNull);
      expect(result!.peerId, 'peer-A');
      expect(result.lastActivity, 'مرحبا Hello 123');
      expect(result.unreadCount, 2);
      expect(repo.getConversationThreadSummaryCallCount, 1);
    });

    test('returns null when a friend snapshot no longer exists', () async {
      final result = await loadOrbitFriendSnapshot(
        contactRepo: FakeContactRepository(),
        messageRepo: FakeMessageRepository(),
        contactPeerId: 'missing-peer',
      );

      expect(result, isNull);
    });
  });
}
