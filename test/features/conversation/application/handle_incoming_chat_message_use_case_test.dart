import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

// -- Fake Contact Repository --
class FakeContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  FakeContactRepository({Set<String> existingPeerIds = const {}}) {
    for (final peerId in existingPeerIds) {
      _contacts[peerId] = ContactModel(
        peerId: peerId,
        publicKey: 'pk-$peerId',
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Alice',
        signature: 'sig-$peerId',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
      );
    }
  }

  /// Add a contact with a specific username.
  void addTestContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  /// Track upserted contacts for test assertions.
  final List<ContactModel> upserted = [];

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
    upserted.add(contact);
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();

  @override
  Future<void> deleteContact(String peerId) async {
    _contacts.remove(peerId);
  }

  @override
  Future<int> getContactCount() async => _contacts.length;
}

// -- Fake Message Repository --
class FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];
  final Set<String> existingIds;

  FakeMessageRepository({this.existingIds = const {}});

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
  }

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    return saved.where((m) => m.contactPeerId == contactPeerId).toList();
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    return null;
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {}

  @override
  Future<bool> messageExists(String id) async => existingIds.contains(id);

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async => 0;
}

Future<List<String>> capturePrintedLines(Future<void> Function() action) async {
  final printed = <String>[];
  await runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      print: (_, __, ___, line) {
        printed.add(line);
      },
    ),
  );
  return printed;
}

void main() {
  late FakeContactRepository contactRepo;
  late FakeMessageRepository messageRepo;

  const senderPeerId = '12D3KooWSender123';

  ChatMessage buildP2PMessage(String content) {
    return ChatMessage(
      from: senderPeerId,
      to: 'my-peer',
      content: content,
      timestamp: '2026-02-09T15:30:00.000Z',
      isIncoming: true,
    );
  }

  String buildValidChatJson({String? id, String? text}) {
    return jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': id ?? 'msg-uuid-001',
        'text': text ?? 'Hello from sender!',
        'senderPeerId': senderPeerId,
        'senderUsername': 'Alice',
        'timestamp': '2026-02-09T15:30:00.000Z',
      },
    });
  }

  setUp(() {
    contactRepo = FakeContactRepository(existingPeerIds: {senderPeerId});
    messageRepo = FakeMessageRepository();
  });

  group('handleIncomingChatMessage', () {
    test('returns notChatMessage for non-JSON content', () async {
      final message = buildP2PMessage('not json at all');

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.notChatMessage);
      expect(msg, isNull);
    });

    test('returns notChatMessage for wrong type', () async {
      final json = jsonEncode({
        'type': 'contact_request',
        'version': '1',
        'payload': {'foo': 'bar'},
      });
      final message = buildP2PMessage(json);

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.notChatMessage);
      expect(msg, isNull);
    });

    test('returns unknownSender when sender is not a contact', () async {
      contactRepo = FakeContactRepository(existingPeerIds: {});
      final message = buildP2PMessage(buildValidChatJson());

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.unknownSender);
      expect(msg, isNull);
      expect(messageRepo.saved, isEmpty);
    });

    test('returns duplicate when message ID already exists', () async {
      messageRepo = FakeMessageRepository(existingIds: {'msg-uuid-001'});
      final message = buildP2PMessage(buildValidChatJson());

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.duplicate);
      expect(msg, isNull);
      expect(messageRepo.saved, isEmpty);
    });

    test(
      'returns chatMessage and persists valid message from known contact',
      () async {
        final message = buildP2PMessage(buildValidChatJson());

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(msg!.id, 'msg-uuid-001');
        expect(msg.text, 'Hello from sender!');
        expect(msg.senderPeerId, senderPeerId);
        expect(msg.contactPeerId, senderPeerId);
        expect(msg.isIncoming, true);
        expect(msg.status, 'delivered');

        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.id, 'msg-uuid-001');
      },
    );

    test('persisted message has correct fields', () async {
      final message = buildP2PMessage(
        buildValidChatJson(id: 'test-id-42', text: 'Custom text'),
      );

      await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(messageRepo.saved.length, 1);
      final saved = messageRepo.saved.first;
      expect(saved.id, 'test-id-42');
      expect(saved.text, 'Custom text');
      expect(saved.isIncoming, true);
      expect(saved.status, 'delivered');
    });

    test('logs CHAT_IN with delivered status and text preview', () async {
      final message = buildP2PMessage(
        buildValidChatJson(id: 'msg-log-001', text: 'Incoming log text'),
      );

      final lines = await capturePrintedLines(() async {
        await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
      });

      expect(
        lines.any(
          (line) =>
              line.contains('[CHAT_IN]') &&
              line.contains('status=delivered') &&
              line.contains('Incoming log text'),
        ),
        isTrue,
      );
    });

    test(
      'returns updatedContact when senderUsername differs from stored',
      () async {
        // Contact stored as "Alice", but message comes with "Alice2"
        final json = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'msg-name-change-001',
            'text': 'Hi with new name!',
            'senderPeerId': senderPeerId,
            'senderUsername': 'Alice2',
            'timestamp': '2026-02-09T15:30:00.000Z',
          },
        });
        final message = buildP2PMessage(json);

        final (result, msg, updatedContact) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(updatedContact, isNotNull);
        expect(updatedContact!.username, 'Alice2');
        expect(updatedContact.peerId, senderPeerId);

        // Verify the contact was upserted
        expect(contactRepo.upserted.length, 1);
        expect(contactRepo.upserted.first.username, 'Alice2');
      },
    );

    test(
      'returns null updatedContact when senderUsername matches stored',
      () async {
        // Contact stored as "Alice", message also says "Alice"
        final message = buildP2PMessage(buildValidChatJson());

        final (result, msg, updatedContact) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(updatedContact, isNull);

        // No upsert should have happened
        expect(contactRepo.upserted, isEmpty);
      },
    );
  });
}
