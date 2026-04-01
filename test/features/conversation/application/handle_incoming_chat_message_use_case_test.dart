import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

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

  @override
  Future<void> archiveContact(String peerId) async {}

  @override
  Future<void> unarchiveContact(String peerId) async {}

  @override
  Future<List<ContactModel>> getActiveContacts() async =>
      _contacts.values.where((c) => !c.isArchived).toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async =>
      _contacts.values.where((c) => c.isArchived).toList();

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
class FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];
  final Set<String> _existingIds;
  final Map<String, ConversationMessage> _existingMessages;

  FakeMessageRepository({
    Set<String> existingIds = const {},
    Map<String, ConversationMessage> existingMessages = const {},
  }) : _existingIds = existingIds.toSet(),
       _existingMessages = Map<String, ConversationMessage>.from(
         existingMessages,
       );

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
    _existingMessages[message.id] = message;
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
  Future<ConversationMessage?> getMessage(String id) async =>
      _existingMessages[id] ??
      (_existingIds.contains(id)
          ? ConversationMessage(
              id: id,
              contactPeerId: 'existing-contact',
              senderPeerId: 'existing-sender',
              text: 'existing text',
              timestamp: '2026-02-09T15:30:00.000Z',
              status: 'delivered',
              isIncoming: true,
              createdAt: '2026-02-09T15:30:01.000Z',
            )
          : null);

  @override
  Future<bool> messageExists(String id) async =>
      _existingIds.contains(id) || _existingMessages.containsKey(id);

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
  Future<int> deleteMessage(String id) async => 0;

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

// -- Fake Media Attachment Repository --
class FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> saved = [];

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    saved.add(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return saved.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async => {};

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => [];
}

class FakeDecryptBridge implements Bridge {
  Map<String, dynamic> decryptResponse = {'ok': true, 'plaintext': '{}'};
  int decryptCallCount = 0;

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      return jsonEncode(decryptResponse);
    }
    return jsonEncode({'ok': true});
  }

  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  void Function(ChatMessage p1)? onMessageReceived;

  @override
  void Function(ConnectionState p1)? onPeerConnected;

  @override
  void Function(ConnectionState p1)? onPeerDisconnected;

  @override
  void Function(List<String> p1, List<String> p2)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class ThrowingDecryptBridge extends FakeDecryptBridge {
  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      throw Exception('decrypt exploded');
    }
    return jsonEncode({'ok': true});
  }
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

Future<List<String>> captureDebugPrintedLines(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };

  try {
    await action();
  } finally {
    debugPrint = debugPrintThrottled;
    flowEventLoggingEnabled = previousLogging;
  }

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

  String buildValidChatJson({
    String? id,
    String? text,
    String? action,
    String? editedAt,
    String? quotedMessageId,
  }) {
    return jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': id ?? 'msg-uuid-001',
        'text': text ?? 'Hello from sender!',
        'senderPeerId': senderPeerId,
        'senderUsername': 'Alice',
        'timestamp': '2026-02-09T15:30:00.000Z',
        if (action != null) 'action': action,
        if (editedAt != null) 'editedAt': editedAt,
        if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
      },
    });
  }

  String buildV2EncryptedEnvelopeJson({
    String senderId = senderPeerId,
    String kem = 'kem-blob',
    String ciphertext = 'cipher-blob',
    String nonce = 'nonce-blob',
  }) {
    return jsonEncode({
      'type': 'chat_message',
      'version': '2',
      'senderPeerId': senderId,
      'encrypted': {'kem': kem, 'ciphertext': ciphertext, 'nonce': nonce},
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
      'returns editMissingOriginal when edit has no stored original',
      () async {
        final message = buildP2PMessage(
          buildValidChatJson(
            action: MessagePayload.actionEdit,
            editedAt: '2026-02-09T16:00:00.000Z',
          ),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.editMissingOriginal);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test('applies same-id edit payloads to existing messages', () async {
      const original = ConversationMessage(
        id: 'msg-uuid-001',
        contactPeerId: senderPeerId,
        senderPeerId: senderPeerId,
        text: 'Original text',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
        quotedMessageId: 'quoted-001',
      );
      messageRepo = FakeMessageRepository(
        existingMessages: {'msg-uuid-001': original},
      );
      final message = buildP2PMessage(
        buildValidChatJson(
          text: 'Edited text',
          action: MessagePayload.actionEdit,
          editedAt: '2026-02-09T16:00:00.000Z',
          quotedMessageId: 'quoted-001',
        ),
      );

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(msg, isNotNull);
      expect(msg!.id, original.id);
      expect(msg.text, 'Edited text');
      expect(msg.timestamp, original.timestamp);
      expect(msg.createdAt, original.createdAt);
      expect(msg.quotedMessageId, original.quotedMessageId);
      expect(msg.editedAt, '2026-02-09T16:00:00.000Z');
      expect(messageRepo.saved.single.text, 'Edited text');
    });

    group('v2 encrypted envelopes', () {
      test(
        'returns missingMlKemSecret when v2 envelope lacks bridge/key',
        () async {
          final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

          final (result, msg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );

          expect(result, HandleChatMessageResult.missingMlKemSecret);
          expect(msg, isNull);
          expect(messageRepo.saved, isEmpty);
        },
      );

      test(
        'returns decryptionFailed when bridge decrypt reports failure',
        () async {
          final bridge = FakeDecryptBridge()
            ..decryptResponse = {
              'ok': false,
              'errorCode': 'DECRYPT_FAILED',
              'errorMessage': 'cannot decrypt',
            };
          final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

          final lines = await captureDebugPrintedLines(() async {
            final (result, msg, _) = await handleIncomingChatMessage(
              message: message,
              messageRepo: messageRepo,
              contactRepo: contactRepo,
              bridge: bridge,
              ownMlKemSecretKey: 'own-secret-key',
            );

            expect(result, HandleChatMessageResult.decryptionFailed);
            expect(msg, isNull);
          });

          expect(messageRepo.saved, isEmpty);
          expect(bridge.decryptCallCount, 1);
          expect(
            lines.any(
              (line) => line.contains('CHAT_MSG_RECEIVE_DECRYPT_FAILED'),
            ),
            isTrue,
          );
          expect(
            lines.any((line) => line.contains('CHAT_MSG_RECEIVE_NOT_CHAT')),
            isFalse,
          );
        },
      );

      test('returns decryptionFailed when bridge decrypt throws', () async {
        final bridge = ThrowingDecryptBridge();
        final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

        final lines = await captureDebugPrintedLines(() async {
          final (result, msg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'own-secret-key',
          );

          expect(result, HandleChatMessageResult.decryptionFailed);
          expect(msg, isNull);
        });

        expect(messageRepo.saved, isEmpty);
        expect(bridge.decryptCallCount, 1);
        expect(
          lines.any((line) => line.contains('CHAT_MSG_RECEIVE_DECRYPT_ERROR')),
          isTrue,
        );
        expect(
          lines.any((line) => line.contains('CHAT_MSG_RECEIVE_NOT_CHAT')),
          isFalse,
        );
      });

      test(
        'decrypts v2 envelope and persists message for known contact',
        () async {
          final bridge = FakeDecryptBridge()
            ..decryptResponse = {
              'ok': true,
              'plaintext': jsonEncode({
                'id': 'msg-v2-001',
                'text': 'Hello from encrypted payload',
                'senderPeerId': senderPeerId,
                'senderUsername': 'Alice',
                'timestamp': '2026-02-09T15:30:00.000Z',
              }),
            };
          final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

          final (result, msg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'own-secret-key',
            transport: 'relay',
          );

          expect(result, HandleChatMessageResult.chatMessage);
          expect(msg, isNotNull);
          expect(msg!.id, 'msg-v2-001');
          expect(msg.text, 'Hello from encrypted payload');
          expect(msg.transport, 'relay');
          expect(messageRepo.saved, hasLength(1));
          expect(messageRepo.saved.first.id, 'msg-v2-001');
          expect(bridge.decryptCallCount, 1);
        },
      );
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

    test('strips bidi characters from incoming message text', () async {
      final json = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': 'msg-bidi-001',
          'text': 'Hello\u200Bworld\u202A!',
          'senderPeerId': senderPeerId,
          'senderUsername': 'Alice',
          'timestamp': '2026-02-09T15:30:00.000Z',
        },
      });
      final message = buildP2PMessage(json);

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(msg, isNotNull);
      expect(msg!.text, 'Helloworld!');
      expect(messageRepo.saved.first.text, 'Helloworld!');
    });

    test('strips bidi characters from incoming senderUsername', () async {
      final json = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': 'msg-bidi-002',
          'text': 'Hello!',
          'senderPeerId': senderPeerId,
          'senderUsername': 'Alice\u200B\u202A',
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
      // Username should match stored "Alice" after stripping bidi chars
      expect(updatedContact, isNull);
    });

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

    group('transport tagging', () {
      test('transport passes through to ConversationMessage', () async {
        final message = buildP2PMessage(
          buildValidChatJson(id: 'msg-transport-001'),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'relay',
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(msg!.transport, 'relay');
        expect(messageRepo.saved.first.transport, 'relay');
      });

      test('wifi transport passes through', () async {
        final message = buildP2PMessage(
          buildValidChatJson(id: 'msg-transport-002'),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'wifi',
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg!.transport, 'wifi');
      });

      test('inbox transport passes through', () async {
        final message = buildP2PMessage(
          buildValidChatJson(id: 'msg-transport-003'),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'inbox',
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg!.transport, 'inbox');
      });

      test('null transport works for backward compat', () async {
        final message = buildP2PMessage(
          buildValidChatJson(id: 'msg-transport-004'),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg!.transport, isNull);
        expect(messageRepo.saved.first.transport, isNull);
      });
    });

    test(
      'duplicate rejected even when transport differs (cross-transport dedup)',
      () async {
        messageRepo = FakeMessageRepository(existingIds: {'msg-uuid-001'});
        final message = buildP2PMessage(buildValidChatJson());

        // Same message ID arrives via relay after being delivered via wifi
        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'relay',
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test(
      'still accepts V1 plaintext messages for backward compatibility',
      () async {
        // V1 plaintext message — must still be accepted on the receive path
        // even though the send path now requires V2 encryption
        final message = buildP2PMessage(
          buildValidChatJson(
            id: 'msg-v1-compat-001',
            text: 'Hello from older peer',
          ),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(msg!.id, 'msg-v1-compat-001');
        expect(msg.text, 'Hello from older peer');
        expect(messageRepo.saved.length, 1);
      },
    );

    group('media attachments', () {
      late FakeMediaAttachmentRepository mediaRepo;

      setUp(() {
        mediaRepo = FakeMediaAttachmentRepository();
      });

      String buildChatJsonWithMedia({
        String id = 'msg-media-001',
        String text = 'Check this out',
        List<Map<String, dynamic>>? media,
      }) {
        return jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': id,
            'text': text,
            'senderPeerId': senderPeerId,
            'senderUsername': 'Alice',
            'timestamp': '2026-02-09T15:30:00.000Z',
            if (media != null) 'media': media,
          },
        });
      }

      test('persists media attachments from incoming message', () async {
        final mediaArray = [
          {
            'id': 'blob-001',
            'mime': 'image/jpeg',
            'size': 245000,
            'mediaType': 'image',
            'width': 1920,
            'height': 1080,
          },
          {
            'id': 'blob-002',
            'mime': 'audio/mp3',
            'size': 50000,
            'mediaType': 'audio',
            'durationMs': 30000,
          },
        ];

        final message = buildP2PMessage(
          buildChatJsonWithMedia(media: mediaArray),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);

        // Media should be persisted
        expect(mediaRepo.saved.length, 2);
        expect(mediaRepo.saved[0].id, 'blob-001');
        expect(mediaRepo.saved[0].messageId, 'msg-media-001');
        expect(mediaRepo.saved[0].mime, 'image/jpeg');
        expect(mediaRepo.saved[0].size, 245000);
        expect(mediaRepo.saved[0].width, 1920);
        expect(mediaRepo.saved[0].downloadStatus, 'pending');

        expect(mediaRepo.saved[1].id, 'blob-002');
        expect(mediaRepo.saved[1].messageId, 'msg-media-001');
        expect(mediaRepo.saved[1].mime, 'audio/mp3');
        expect(mediaRepo.saved[1].durationMs, 30000);
      });

      test('does not persist media when payload has no media', () async {
        final message = buildP2PMessage(buildChatJsonWithMedia());

        await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(mediaRepo.saved, isEmpty);
      });

      test('does not crash when mediaAttachmentRepo is null', () async {
        final mediaArray = [
          {
            'id': 'blob-001',
            'mime': 'image/jpeg',
            'size': 1000,
            'mediaType': 'image',
          },
        ];
        final message = buildP2PMessage(
          buildChatJsonWithMedia(media: mediaArray),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: null,
        );

        // Should succeed but just skip media persistence
        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
      });

      test('message is still persisted even with media', () async {
        final mediaArray = [
          {
            'id': 'blob-001',
            'mime': 'image/jpeg',
            'size': 1000,
            'mediaType': 'image',
          },
        ];
        final message = buildP2PMessage(
          buildChatJsonWithMedia(
            id: 'msg-with-media-001',
            text: 'Photo attached',
            media: mediaArray,
          ),
        );

        await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(messageRepo.saved.length, 1);
        expect(messageRepo.saved.first.id, 'msg-with-media-001');
        expect(messageRepo.saved.first.text, 'Photo attached');
      });
    });
  });
}
