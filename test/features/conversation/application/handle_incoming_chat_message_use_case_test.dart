import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';

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
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async {
    return _existingMessages.values.any(
      (m) =>
          m.isIncoming &&
          m.contactPeerId == contactPeerId &&
          m.senderPeerId == senderPeerId &&
          m.text == text &&
          m.timestamp == timestamp,
    );
  }

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async {
    return _existingMessages.values.any(
      (m) =>
          m.isIncoming &&
          m.contactPeerId == contactPeerId &&
          m.senderPeerId == senderPeerId &&
          m.dedupKey == dedupKey,
    );
  }

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

  /// 228: lanes passed to [saveAttachment], in call order.
  final savedOwnerLanes = <MediaOwnerLane>[];

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    savedOwnerLanes.add(owner);
    final index = saved.indexWhere((saved) => saved.id == attachment.id);
    if (index == -1) {
      saved.add(attachment);
    } else {
      saved[index] = attachment;
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    return saved.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async => {};

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => [];
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

/// 147: decrypt fails CRYPTOGRAPHICALLY for the primary secret and succeeds only
/// for [ringKey] — exercises the pre-restore ML-KEM ring (P0-B) recovery path.
class _RingFallbackDecryptBridge extends FakeDecryptBridge {
  final String ringKey;
  final String plaintext;
  _RingFallbackDecryptBridge({required this.ringKey, required this.plaintext});

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    if (req['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      final secretKey = (req['payload'] as Map<String, dynamic>)['secretKey'];
      if (secretKey == ringKey) {
        return jsonEncode({'ok': true, 'plaintext': plaintext});
      }
      return jsonEncode({'ok': false, 'errorCode': 'DECRYPT_FAILED'});
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
    List<Map<String, dynamic>>? media,
    String? dedupKey,
    String? timestamp,
  }) {
    return jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': id ?? 'msg-uuid-001',
        'text': text ?? 'Hello from sender!',
        'senderPeerId': senderPeerId,
        'senderUsername': 'Alice',
        'timestamp': timestamp ?? '2026-02-09T15:30:00.000Z',
        if (action != null) 'action': action,
        if (editedAt != null) 'editedAt': editedAt,
        if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
        if (media != null) 'media': media,
        if (dedupKey != null) 'dedupKey': dedupKey,
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
      'FDC-S6: a same-id double-delivery emits CHAT_MSG_DOUBLE_DELIVERY with the '
      'kept+dropped transport legs (instrument point 5)',
      () async {
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        addTearDown(() => debugSetFlowEventSink(null));
        // KEPT copy already durable — it won FIRST over the WS LAN leg ('wifi').
        const existing = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Hello from sender!',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
          transport: 'wifi',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': existing},
        );
        // The SAME id arrives a second time over the libp2p-LAN leg ('direct');
        // the messageId dedup drops it. The soak must see the collision keyed by
        // the (kept=wifi, dropped=direct) leg pair — the only place the LAN
        // double-delivery rate is observable.
        final message = buildP2PMessage(buildValidChatJson());

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'direct',
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
        final dd = flow.firstWhere(
          (e) => e['event'] == 'CHAT_MSG_DOUBLE_DELIVERY',
          orElse: () => <String, dynamic>{},
        );
        expect(
          dd,
          isNotEmpty,
          reason: 'CHAT_MSG_DOUBLE_DELIVERY must fire on a same-id collision',
        );
        final details = dd['details'] as Map<String, dynamic>;
        expect(details['kept'], 'wifi');
        expect(details['dropped'], 'direct');
        expect(details['id'], 'msg-uuid'); // 8-char prefix of 'msg-uuid-001'
      },
    );

    test(
      'returns duplicate when SAME content arrives under a DIFFERENT id (F8 content dedup)',
      () async {
        // An already-durable incoming message under id 'msg-uuid-001'.
        const existing = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Hello from sender!',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': existing},
        );
        // DIFFERENT id, SAME sender + SAME text + SAME timestamp — a divergent-
        // id re-delivery of the same logical message. The id-only gate misses
        // it; without content dedup a 2nd row persists.
        final message = buildP2PMessage(buildValidChatJson(id: 'msg-uuid-002'));

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test(
      'persists a DIFFERENT-content message under a different id (no false dedup)',
      () async {
        const existing = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Hello from sender!',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': existing},
        );
        // Different id AND different text — must NOT be deduped.
        final message = buildP2PMessage(
          buildValidChatJson(
            id: 'msg-uuid-002',
            text: 'A genuinely different message',
          ),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(messageRepo.saved, hasLength(1));
      },
    );

    group('F8 tier-2 (wire-stamped dedupKey)', () {
      ConversationMessage existingIncoming({
        String text = 'Hello from sender!',
        String timestamp = '2026-02-09T15:30:00.000Z',
        bool isIncoming = true,
        String senderPeer = senderPeerId,
        String? dedupKey,
      }) => ConversationMessage(
        id: 'existing-1',
        contactPeerId: senderPeerId,
        senderPeerId: senderPeer,
        text: text,
        timestamp: timestamp,
        status: isIncoming ? 'delivered' : 'sent',
        isIncoming: isIncoming,
        createdAt: '2026-02-09T15:30:01.000Z',
        dedupKey: dedupKey,
      );

      // Case 1 (D1): a forward — divergent id + DIVERGENT timestamp + SAME
      // dedupKey — dedups via the KEY, and the event proves it was tier-2 (not
      // tier-1, which cannot catch a re-minted timestamp).
      test(
        'dedups a forward (divergent id+timestamp, same dedupKey) via DEDUP_KEY not CONTENT',
        () async {
          final flow = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flow.add);
          addTearDown(() => debugSetFlowEventSink(null));
          messageRepo = FakeMessageRepository(
            existingMessages: {
              'existing-1': existingIncoming(dedupKey: 'src-1'),
            },
          );
          final message = buildP2PMessage(
            buildValidChatJson(
              id: 'msg-uuid-002',
              dedupKey: 'src-1',
              timestamp: '2099-01-01T00:00:00.000Z', // T1 ≠ T0
            ),
          );

          final (result, msg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );

          expect(result, HandleChatMessageResult.duplicate);
          expect(msg, isNull);
          expect(messageRepo.saved, isEmpty);
          final events = flow.map((e) => e['event']).toList();
          expect(events, contains('CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY'));
          expect(events, isNot(contains('CHAT_MSG_RECEIVE_DUPLICATE_CONTENT')));
        },
      );

      // Case 2: no false-positive — same text, DIFFERENT dedupKey → persists.
      test(
        'does NOT dedup identical text under a different dedupKey',
        () async {
          messageRepo = FakeMessageRepository(
            existingMessages: {
              'existing-1': existingIncoming(dedupKey: 'src-1'),
            },
          );
          final message = buildP2PMessage(
            buildValidChatJson(
              id: 'msg-uuid-002',
              dedupKey: 'src-2',
              timestamp: '2099-01-01T00:00:00.000Z',
            ),
          );
          final (result, _, __) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );
          expect(result, HandleChatMessageResult.chatMessage);
          expect(messageRepo.saved, hasLength(1));
        },
      );

      // Case 3a: keyless + same timestamp → tier-1 fallback dedups (CONTENT).
      test(
        'keyless arrival still hits tier-1 (same content+timestamp)',
        () async {
          final flow = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flow.add);
          addTearDown(() => debugSetFlowEventSink(null));
          messageRepo = FakeMessageRepository(
            existingMessages: {'existing-1': existingIncoming()},
          );
          final message = buildP2PMessage(
            buildValidChatJson(id: 'msg-uuid-002'),
          );
          final (result, _, __) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );
          expect(result, HandleChatMessageResult.duplicate);
          final events = flow.map((e) => e['event']).toList();
          expect(events, contains('CHAT_MSG_RECEIVE_DUPLICATE_CONTENT'));
          expect(
            events,
            isNot(contains('CHAT_MSG_RECEIVE_DUPLICATE_DEDUP_KEY')),
          );
        },
      );

      // Case 3b: keyless + different timestamp → persists (tier-1 miss).
      test('keyless arrival with a different timestamp persists', () async {
        messageRepo = FakeMessageRepository(
          existingMessages: {'existing-1': existingIncoming()},
        );
        final message = buildP2PMessage(
          buildValidChatJson(
            id: 'msg-uuid-002',
            timestamp: '2099-01-01T00:00:00.000Z',
          ),
        );
        final (result, _, __) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        expect(result, HandleChatMessageResult.chatMessage);
        expect(messageRepo.saved, hasLength(1));
      });

      // Case 4: keyed but UNMATCHED → persists, authoritatively (does NOT fall
      // back to tier-1 even though text+timestamp match the existing row).
      test(
        'keyed-but-unmatched persists even when text+timestamp match tier-1',
        () async {
          messageRepo = FakeMessageRepository(
            existingMessages: {
              'existing-1': existingIncoming(dedupKey: 'src-1'),
            },
          );
          final message = buildP2PMessage(
            buildValidChatJson(id: 'msg-uuid-002', dedupKey: 'src-9'),
          );
          final (result, _, __) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );
          expect(
            result,
            HandleChatMessageResult.chatMessage,
            reason: 'a keyed message is authoritative — no tier-1 fallback',
          );
          expect(messageRepo.saved, hasLength(1));
        },
      );

      // Case 5 (D3): re-mint a receipt for the forward's FRESH id on a tier-2
      // duplicate (so the sender's forward row reaches delivered).
      test('re-mints a delivery receipt for the forward fresh id', () async {
        final receiptIds = <String>[];
        messageRepo = FakeMessageRepository(
          existingMessages: {'existing-1': existingIncoming(dedupKey: 'src-1')},
        );
        final message = buildP2PMessage(
          buildValidChatJson(
            id: 'msg-uuid-002',
            dedupKey: 'src-1',
            timestamp: '2099-01-01T00:00:00.000Z',
          ),
        );
        await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'inbox',
          stagedEntryId: 'relay-1',
          sendDeliveryReceipt: (id) async => receiptIds.add(id),
        );
        expect(receiptIds, ['msg-uuid-002']);
      });

      // Case 6 (D4): my OUTGOING row with the same key must NOT dedup the
      // contact's genuine inbound — the sender_peer_id + is_incoming guards.
      test(
        'does NOT dedup the contact inbound against my own outgoing row',
        () async {
          messageRepo = FakeMessageRepository(
            existingMessages: {
              'existing-1': existingIncoming(
                isIncoming: false,
                senderPeer: 'my-peer',
                dedupKey: 'X',
              ),
            },
          );
          final message = buildP2PMessage(
            buildValidChatJson(
              id: 'inbound-msg-001',
              dedupKey: 'X',
              timestamp: '2099-01-01T00:00:00.000Z',
            ),
          );
          final (result, _, __) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
          );
          expect(result, HandleChatMessageResult.chatMessage);
          expect(messageRepo.saved, hasLength(1));
        },
      );
    });

    test(
      'emits duplicate-content-mismatch telemetry when a non-edit duplicate carries different text',
      () async {
        const messageId = 'msg-uuid-001';
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));
        const existing = ConversationMessage(
          id: messageId,
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'pre-edit',
          timestamp: '2026-02-09T15:29:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:29:00.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {messageId: existing},
        );
        final message = buildP2PMessage(
          buildValidChatJson(id: messageId, text: 'post-edit'),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
        final stored = await messageRepo.getMessage(messageId);
        expect(stored, isNotNull);
        expect(stored!.text, 'pre-edit');
        final mismatchEvent = flowEvents.singleWhere(
          (event) =>
              event['event'] == 'CHAT_MSG_RECEIVE_DUPLICATE_CONTENT_MISMATCH',
        );
        final details = mismatchEvent['details'] as Map<String, dynamic>;
        expect(details['id'], messageId.substring(0, 8));
        expect(details['incomingTextLength'], 'post-edit'.length);
        expect(details['existingTextLength'], 'pre-edit'.length);
        expect(details['existingHasEditedAt'], isFalse);
        expect(jsonEncode(details), isNot(contains('post-edit')));
        expect(jsonEncode(details), isNot(contains('pre-edit')));
      },
    );

    test(
      'duplicate replay repairs failed media attachment without duplicate',
      () async {
        const messageId = 'msg-duplicate-media-repair';
        const attachmentId = 'duplicate-media-attachment';
        final existing = ConversationMessage(
          id: messageId,
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'existing media',
          timestamp: '2026-02-09T15:29:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:29:00.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {messageId: existing},
        );
        final mediaRepo = FakeMediaAttachmentRepository();
        await mediaRepo.saveAttachment(
          owner: MediaOwnerLane.direct,
          const MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 42,
            mediaType: 'image',
            downloadStatus: 'failed',
            createdAt: '2026-02-09T15:29:00.000Z',
          ),
        );
        final message = buildP2PMessage(
          buildValidChatJson(
            id: messageId,
            media: const [
              {
                'id': attachmentId,
                'mime': 'image/jpeg',
                'size': 42,
                'mediaType': 'image',
              },
            ],
          ),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
        final attachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.direct,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, attachmentId);
        expect(attachments.single.downloadStatus, 'pending');
      },
    );

    test('duplicate replay carrying new key/nonce invalidates stale staged '
        'artifacts before reset to pending', () async {
      const messageId = 'msg-duplicate-key-rotation';
      const attachmentId = 'duplicate-key-rotation-attachment';
      final existing = ConversationMessage(
        id: messageId,
        contactPeerId: senderPeerId,
        senderPeerId: senderPeerId,
        text: 'existing media',
        timestamp: '2026-02-09T15:29:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:29:00.000Z',
      );
      messageRepo = FakeMessageRepository(
        existingMessages: {messageId: existing},
      );
      final mediaRepo = FakeMediaAttachmentRepository();
      await mediaRepo.saveAttachment(
        owner: MediaOwnerLane.direct,
        const MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 42,
          mediaType: 'image',
          downloadStatus: 'integrity_failed',
          createdAt: '2026-02-09T15:29:00.000Z',
          encryptionKeyBase64: 'old-key',
          encryptionNonce: 'old-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ),
      );
      final fileManager = FakeMediaFileManager();
      final absolutePath = await fileManager.localPathForAttachment(
        contactPeerId: senderPeerId,
        blobId: attachmentId,
        mime: 'image/jpeg',
      );
      final staleStaged = File('$absolutePath.enc');
      await staleStaged.parent.create(recursive: true);
      await staleStaged.writeAsBytes(List<int>.filled(58, 7), flush: true);
      addTearDown(() {
        if (staleStaged.existsSync()) {
          staleStaged.deleteSync();
        }
      });

      final message = buildP2PMessage(
        buildValidChatJson(
          id: messageId,
          media: const [
            {
              'id': attachmentId,
              'mime': 'image/jpeg',
              'size': 42,
              'mediaType': 'image',
              'encryptionKeyBase64': 'new-key',
              'encryptionNonce': 'new-nonce',
              'encryptionScheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            },
          ],
        ),
      );

      final (result, msg, _) = await handleIncomingChatMessage(
        message: message,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
      );

      expect(result, HandleChatMessageResult.duplicate);
      expect(msg, isNull);
      final attachments = await mediaRepo.getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      expect(attachments, hasLength(1));
      expect(attachments.single.downloadStatus, 'pending');
      expect(attachments.single.encryptionKeyBase64, 'new-key');
      expect(attachments.single.encryptionNonce, 'new-nonce');
      // The stale ciphertext staged under the OLD key must be gone — the
      // new key must never be asked to decrypt old bytes.
      expect(staleStaged.existsSync(), isFalse);
    });

    test(
      'stores a hidden placeholder when edit has no stored original',
      () async {
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

        expect(result, HandleChatMessageResult.editMissingOriginal);
        expect(msg, isNull);
        expect(messageRepo.saved, hasLength(1));
        final placeholder = messageRepo.saved.single;
        expect(placeholder.id, 'msg-uuid-001');
        expect(placeholder.text, 'Edited text');
        expect(placeholder.isHidden, isTrue);
        expect(placeholder.isDeleted, isFalse);
        expect(placeholder.editedAt, '2026-02-09T16:00:00.000Z');
        expect(placeholder.quotedMessageId, 'quoted-001');
      },
    );

    test(
      'materializes a hidden staged edit when the original arrives later',
      () async {
        await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(
              text: 'Edited text',
              action: MessagePayload.actionEdit,
              editedAt: '2026-02-09T16:00:00.000Z',
              quotedMessageId: 'quoted-001',
            ),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        final placeholderCreatedAt = messageRepo.saved.single.createdAt;

        final (result, msg, _) = await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(
              text: 'Original text',
              quotedMessageId: 'quoted-001',
            ),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(msg!.id, 'msg-uuid-001');
        expect(msg.text, 'Edited text');
        expect(msg.isHidden, isFalse);
        expect(msg.isDeleted, isFalse);
        expect(msg.editedAt, '2026-02-09T16:00:00.000Z');
        expect(msg.quotedMessageId, 'quoted-001');
        expect(msg.timestamp, '2026-02-09T15:30:00.000Z');
        expect(msg.createdAt, placeholderCreatedAt);
        expect(messageRepo.saved, hasLength(2));
        expect(messageRepo.saved.last.isHidden, isFalse);
      },
    );

    test(
      'late originals do not resurrect an already deleted incoming row',
      () async {
        const deletedPlaceholder = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: '',
          timestamp: '2026-02-09T16:05:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T16:05:01.000Z',
          deletedAt: '2026-02-09T16:05:00.000Z',
          deletedByPeerId: senderPeerId,
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': deletedPlaceholder},
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(text: 'Original text that should stay deleted'),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.duplicate);
        expect(msg, isNull);
        expect(messageRepo.saved, hasLength(1));
        final stored = messageRepo.saved.single;
        expect(stored.isDeleted, isTrue);
        expect(stored.text, isEmpty);
        expect(stored.timestamp, '2026-02-09T15:30:00.000Z');
        expect(stored.deletedAt, '2026-02-09T16:05:00.000Z');
        expect(stored.deletedByPeerId, senderPeerId);
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

    test(
      'rejects edits when the envelope sender mismatches the payload sender',
      () async {
        const original = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Original text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': original},
        );
        final message = ChatMessage(
          from: 'mismatched-envelope-sender',
          to: 'my-peer',
          content: buildValidChatJson(
            text: 'Edited text',
            action: MessagePayload.actionEdit,
            editedAt: '2026-02-09T16:00:00.000Z',
          ),
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.unauthorized);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
        expect(
          (await messageRepo.getMessage('msg-uuid-001'))!.text,
          'Original text',
        );
      },
    );

    test(
      'rejects edits from a sender who did not author the original row',
      () async {
        const original = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: 'different-author',
          text: 'Original text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': original},
        );
        final message = buildP2PMessage(
          buildValidChatJson(
            text: 'Edited text',
            action: MessagePayload.actionEdit,
            editedAt: '2026-02-09T16:00:00.000Z',
          ),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(result, HandleChatMessageResult.unauthorized);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
        expect(
          (await messageRepo.getMessage('msg-uuid-001'))!.text,
          'Original text',
        );
      },
    );

    test(
      'ignores duplicate and stale edits once a newer edit is already stored',
      () async {
        const original = ConversationMessage(
          id: 'msg-uuid-001',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Newest text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
          editedAt: '2026-02-09T16:00:00.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-uuid-001': original},
        );

        final duplicate = await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(
              text: 'Duplicate newest text',
              action: MessagePayload.actionEdit,
              editedAt: '2026-02-09T16:00:00.000Z',
            ),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );
        final stale = await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(
              text: 'Older text',
              action: MessagePayload.actionEdit,
              editedAt: '2026-02-09T15:59:00.000Z',
            ),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        expect(duplicate.$1, HandleChatMessageResult.ignoredEdit);
        expect(stale.$1, HandleChatMessageResult.ignoredEdit);
        expect(messageRepo.saved, isEmpty);

        final stored = await messageRepo.getMessage('msg-uuid-001');
        expect(stored, isNotNull);
        expect(stored!.text, 'Newest text');
        expect(stored.editedAt, '2026-02-09T16:00:00.000Z');
      },
    );

    test('ignores late edits for messages that are already deleted', () async {
      const original = ConversationMessage(
        id: 'msg-uuid-001',
        contactPeerId: senderPeerId,
        senderPeerId: senderPeerId,
        text: '',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
        deletedAt: '2026-02-09T16:05:00.000Z',
        deletedByPeerId: senderPeerId,
      );
      messageRepo = FakeMessageRepository(
        existingMessages: {'msg-uuid-001': original},
      );

      final (result, msg, _) = await handleIncomingChatMessage(
        message: buildP2PMessage(
          buildValidChatJson(
            text: 'Resurrected text',
            action: MessagePayload.actionEdit,
            editedAt: '2026-02-09T16:06:00.000Z',
          ),
        ),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      expect(result, HandleChatMessageResult.ignoredEdit);
      expect(msg, isNull);
      expect(messageRepo.saved, isEmpty);
      final stored = await messageRepo.getMessage('msg-uuid-001');
      expect(stored, isNotNull);
      expect(stored!.isDeleted, isTrue);
      expect(stored.text, isEmpty);
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

      test('returns decryptionFailed for Go-shaped INTERNAL_ERROR', () async {
        final bridge = FakeDecryptBridge()
          ..decryptResponse = {
            'ok': false,
            'errorCode': 'INTERNAL_ERROR',
            'errorMessage': 'message authentication failed',
          };
        final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: 'own-secret-key',
        );

        expect(result, HandleChatMessageResult.decryptionFailed);
        expect(msg, isNull);
        expect(messageRepo.saved, isEmpty);
      });

      test(
        'returns decryptionDeferred when decrypt fails with BRIDGE_TIMEOUT',
        () async {
          final bridge = FakeDecryptBridge()
            ..decryptResponse = {
              'ok': false,
              'errorCode': 'BRIDGE_TIMEOUT',
              'errorMessage': 'Bridge call timed out after 10s',
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

            expect(result, HandleChatMessageResult.decryptionDeferred);
            expect(msg, isNull);
          });

          expect(messageRepo.saved, isEmpty);
          expect(bridge.decryptCallCount, 1);
          expect(
            lines.any(
              (line) => line.contains('CHAT_MSG_RECEIVE_DECRYPT_DEFERRED'),
            ),
            isTrue,
          );
        },
      );

      test('returns decryptionDeferred when bridge decrypt throws', () async {
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

          expect(result, HandleChatMessageResult.decryptionDeferred);
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
        'BRIDGE_TIMEOUT then successful decrypt on replay stores the message',
        () async {
          // The user story behind P0-A: one slow decrypt must not lose the
          // message. First attempt times out (deferred, nothing saved);
          // the staged-entry replay decrypts fine and commits.
          final bridge = FakeDecryptBridge()
            ..decryptResponse = {
              'ok': false,
              'errorCode': 'BRIDGE_TIMEOUT',
              'errorMessage': 'Bridge call timed out after 10s',
            };
          final message = buildP2PMessage(buildV2EncryptedEnvelopeJson());

          final (firstResult, firstMsg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'own-secret-key',
          );

          expect(firstResult, HandleChatMessageResult.decryptionDeferred);
          expect(firstMsg, isNull);
          expect(messageRepo.saved, isEmpty);

          bridge.decryptResponse = {
            'ok': true,
            'plaintext': jsonEncode({
              'id': 'msg-replay-001',
              'text': 'Recovered after timeout',
              'senderPeerId': senderPeerId,
              'senderUsername': 'Alice',
              'timestamp': '2026-02-09T15:30:00.000Z',
            }),
          };

          final (secondResult, secondMsg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'own-secret-key',
          );

          expect(secondResult, HandleChatMessageResult.chatMessage);
          expect(secondMsg, isNotNull);
          expect(secondMsg!.text, 'Recovered after timeout');
          expect(messageRepo.saved, hasLength(1));
          expect(bridge.decryptCallCount, 2);
        },
      );

      test(
        'rejects edit payloads when encrypted envelope sender mismatches decrypted payload sender',
        () async {
          final bridge = FakeDecryptBridge()
            ..decryptResponse = {
              'ok': true,
              'plaintext': jsonEncode({
                'id': 'msg-uuid-001',
                'text': 'Edited text',
                'senderPeerId': senderPeerId,
                'senderUsername': 'Alice',
                'timestamp': '2026-02-09T15:30:00.000Z',
                'action': 'edit',
                'editedAt': '2026-02-09T16:00:00.000Z',
              }),
            };
          final message = buildP2PMessage(
            buildV2EncryptedEnvelopeJson(senderId: 'different-envelope-sender'),
          );

          final (result, msg, _) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'own-secret-key',
          );

          expect(result, HandleChatMessageResult.unauthorized);
          expect(msg, isNull);
          expect(messageRepo.saved, isEmpty);
        },
      );

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

      final lines = await captureDebugPrintedLines(() async {
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

      // 228: the 1:1 incoming path must persist media under the DIRECT lane —
      // every saveAttachment call carries MediaOwnerLane.direct, never group.
      test('incoming media save passes direct owner', () async {
        final mediaArray = [
          {
            'id': 'blob-owner-direct-001',
            'mime': 'image/jpeg',
            'size': 1000,
            'mediaType': 'image',
          },
        ];
        final message = buildP2PMessage(
          buildChatJsonWithMedia(id: 'msg-owner-lane-001', media: mediaArray),
        );

        final (result, msg, _) = await handleIncomingChatMessage(
          message: message,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        expect(mediaRepo.saved, hasLength(1));
        expect(mediaRepo.saved.single.id, 'blob-owner-direct-001');
        expect(mediaRepo.savedOwnerLanes, hasLength(1));
        expect(
          mediaRepo.savedOwnerLanes.toSet(),
          {MediaOwnerLane.direct},
          reason: 'every 1:1 incoming media save must pass the direct lane',
        );
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

    // ─── 115 Phase 2.4 — delivery-receipt hook + origin-marker contract ───
    // Receipts confirm relay-inbox custody became durable receiver state.
    // They mint ONLY for relay-drain arrivals: the live deferred direct ack
    // ('direct:' staged replays) and doc 114's committed LAN ack ('lan:'
    // staged replays) already gave their senders 'delivered' at the same
    // durable bar — receipts there would be redundant and, worse, would let
    // a quarantined replay flip a sender to 'delivered' for content the
    // receiver never displays.
    group('115 P2 — delivery receipt hook', () {
      test(
        '132 Phase 0 (OFF mode): a skipped mint emits DELIVERY_RECEIPT_MINT_SKIPPED with the reason',
        () async {
          final lines = await captureDebugPrintedLines(() async {
            await handleIncomingChatMessage(
              message: buildP2PMessage(
                buildValidChatJson(id: 'msg-skip-direct-01'),
              ),
              messageRepo: messageRepo,
              contactRepo: contactRepo,
              transport: 'direct',
              stagedEntryId: 'direct:n1',
              sendDeliveryReceipt: (_) async {},
              confirmatoryDirectLanEnabled: false,
            );
          });
          final skip = lines.firstWhere(
            (l) => l.contains('"event":"DELIVERY_RECEIPT_MINT_SKIPPED"'),
            orElse: () => '',
          );
          expect(skip, contains('"reason":"direct"'));
        },
      );

      test(
        '132 Phase 1 (live default): a direct-staged durable message DOES mint a confirmatory receipt',
        () async {
          final receiptIds = <String>[];
          final (result, _, __) = await handleIncomingChatMessage(
            message: buildP2PMessage(
              buildValidChatJson(id: 'msg-phase1-direct-01'),
            ),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'direct',
            stagedEntryId: 'direct:p1',
            sendDeliveryReceipt: (id) async => receiptIds.add(id),
            // no confirmatoryDirectLanEnabled → uses the live const default (true)
          );
          expect(result, HandleChatMessageResult.chatMessage);
          expect(receiptIds, ['msg-phase1-direct-01']);
        },
      );

      test(
        'invokes sendDeliveryReceipt after durable persist of an inbox-originated message, and re-invokes on duplicate receive',
        () async {
          final receiptIds = <String>[];
          var savedWhenInvoked = false;
          Future<void> hook(String messageId) async {
            receiptIds.add(messageId);
            savedWhenInvoked = messageRepo.saved.isNotEmpty;
          }

          final message = buildP2PMessage(buildValidChatJson());

          // First receive (relay drain) → receipt after the repo save.
          final (first, _, __) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-entry-001',
            sendDeliveryReceipt: hook,
          );
          expect(first, HandleChatMessageResult.chatMessage);
          expect(receiptIds, ['msg-uuid-001']);
          expect(
            savedWhenInvoked,
            isTrue,
            reason: 'receipt must fire AFTER the durable persist',
          );

          // Duplicate receive (lost-receipt repair loop) → re-invoked.
          final (second, _, __2) = await handleIncomingChatMessage(
            message: message,
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-entry-001',
            sendDeliveryReceipt: hook,
          );
          expect(second, HandleChatMessageResult.duplicate);
          expect(receiptIds, ['msg-uuid-001', 'msg-uuid-001']);

          // Live-direct origin in OFF mode → NOT called (confirmNonce owns that
          // ack). Distinct content so it is a genuinely new message, not an F8
          // content-duplicate of the relay message saved above.
          final (third, _, __3) = await handleIncomingChatMessage(
            message: buildP2PMessage(
              buildValidChatJson(id: 'msg-live-001', text: 'A live message'),
            ),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'direct',
            stagedEntryId: 'direct:nonce-1',
            sendDeliveryReceipt: hook,
            confirmatoryDirectLanEnabled: false,
          );
          expect(third, HandleChatMessageResult.chatMessage);
          expect(receiptIds, hasLength(2));
        },
      );

      test(
        "OFF-mode origin-marker contract (dark fallback): 'direct:'/'lan:' staged replays skip receipts; relay-drain entries send receipts; quarantined replays never mint",
        () async {
          final receiptIds = <String>[];
          Future<void> hook(String messageId) async {
            receiptIds.add(messageId);
          }

          // 'direct:<nonce>' — in OFF mode the live deferred-ack owns confirmation.
          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-direct-01')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'direct',
            stagedEntryId: 'direct:n1',
            sendDeliveryReceipt: hook,
            confirmatoryDirectLanEnabled: false,
          );
          expect(receiptIds, isEmpty);

          // 'lan:<nonce>' — in OFF mode doc 114's committed-ack owns confirmation.
          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-lan-00001')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'wifi',
            stagedEntryId: 'lan:n1',
            sendDeliveryReceipt: hook,
            confirmatoryDirectLanEnabled: false,
          );
          expect(receiptIds, isEmpty);

          // Relay-drain entry (any other namespace) → receipt.
          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-relay-001')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-uuid-1',
            sendDeliveryReceipt: hook,
          );
          expect(receiptIds, ['msg-relay-001']);

          // Unstaged inbox forward (staging unavailable) — still a relay
          // delivery: receipt.
          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-relay-002')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            sendDeliveryReceipt: hook,
          );
          expect(receiptIds, ['msg-relay-001', 'msg-relay-002']);

          // Live direct with no staging id and no inbox transport → never (OFF).
          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-direct-02')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'direct',
            sendDeliveryReceipt: hook,
            confirmatoryDirectLanEnabled: false,
          );
          expect(receiptIds, ['msg-relay-001', 'msg-relay-002']);

          // Quarantined/retryable replay (decrypt failure) → never reaches a
          // persist, never mints a receipt — the 111 state machine owns it.
          final failBridge = FakeDecryptBridge()
            ..decryptResponse = {'ok': false, 'errorCode': 'DECRYPT_FAILED'};
          final (result, _, __) = await handleIncomingChatMessage(
            message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: failBridge,
            ownMlKemSecretKey: 'own-secret',
            transport: 'inbox',
            stagedEntryId: 'relay-uuid-2',
            sendDeliveryReceipt: hook,
          );
          expect(result, HandleChatMessageResult.decryptionFailed);
          expect(receiptIds, ['msg-relay-001', 'msg-relay-002']);
        },
      );
    });

    // ─── 146 — defer the per-message delivery-receipt SEND off the replay
    // critical path. The mint DECISION stays synchronous + per-message; only
    // the network send is detached (fire-and-forget) so the serial inbox-drain
    // loop (p2p_service_impl `_replayStagedInboxEntries`) — and the screen
    // reload it gates — no longer blocks on receipt round-trips. The receipt is
    // still SENT (never dropped — preserves the 132 confirmatory-receipt fix).
    group('146 — delivery-receipt send is fire-and-forget', () {
      // TC-01: the use case returns even when the receipt send never completes.
      // RED on HEAD: HEAD awaits the send (`:116`) so the call never returns →
      // the .timeout fires. GREEN after the fix detaches the send.
      test(
        'receipt send is fire-and-forget — handleIncomingChatMessage returns '
        'before the receipt send completes',
        () async {
          final neverCompletes = Completer<void>();
          var hookInvocations = 0;

          final (result, msg, _) = await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-fnf-01')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-fnf-1',
            sendDeliveryReceipt: (_) {
              hookInvocations++;
              return neverCompletes.future; // NEVER completes
            },
          ).timeout(const Duration(seconds: 2));

          expect(result, HandleChatMessageResult.chatMessage);
          expect(msg, isNotNull);
          expect(
            hookInvocations,
            1,
            reason: 'the receipt send was started exactly once',
          );
          expect(
            neverCompletes.isCompleted,
            isFalse,
            reason:
                'the handler returned while the receipt send is still pending',
          );
        },
      );

      // TC-02: eventual-send preservation lock. Passes on HEAD (sync fake adds
      // before return); the mutation that drops the send call re-reds. Tracks
      // `hookInvocations` explicitly so the lock proves the hook was actually
      // INVOKED exactly once (not merely that `receiptIds` happened to end up
      // populated by some other path).
      test(
        'deferred delivery receipt is still sent exactly once after persist',
        () async {
          final receiptIds = <String>[];
          var hookInvocations = 0;

          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-eventual-01')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-eventual-1',
            sendDeliveryReceipt: (id) async {
              hookInvocations++;
              receiptIds.add(id);
            },
          );
          await pumpEventQueue();

          expect(
            hookInvocations,
            1,
            reason: 'the receipt send hook was invoked exactly once',
          );
          expect(receiptIds, ['msg-eventual-01']);
        },
      );

      // TC-03: fix-risk lock — the now-unawaited future must keep its error
      // handler. Passes on HEAD (awaited try/catch). Mutation that drops
      // `.catchError` lets the throw escape as an unhandled async error (fails
      // the test zone) AND drops the breadcrumb.
      test(
        'a deferred receipt send that throws is caught and logged, not unhandled',
        () async {
          final flow = <Map<String, dynamic>>[];
          debugSetFlowEventSink(flow.add);
          addTearDown(() => debugSetFlowEventSink(null));

          await handleIncomingChatMessage(
            message: buildP2PMessage(buildValidChatJson(id: 'msg-throw-01')),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            transport: 'inbox',
            stagedEntryId: 'relay-throw-1',
            sendDeliveryReceipt: (_) async {
              throw StateError('boom');
            },
          );
          // The send is detached; its error surfaces on a later microtask.
          // Draining the queue lets the `.catchError` handler run. If the fix
          // dropped the error handler the throw would escape as an unhandled
          // async error and fail this test's zone.
          await pumpEventQueue();

          final events = flow.map((e) => e['event']).toList();
          expect(events, contains('DELIVERY_RECEIPT_HOOK_ERROR'));
        },
      );

      // TC-04: over-detach lock. The load-bearing assertion is that a SKIP path
      // schedules NO send (`receiptIds` stays empty) while still emitting
      // MINT_SKIPPED — the send deferral must never turn a skip into a send, nor
      // drop the skip telemetry. The genuine catchable mutation is "schedule a
      // send despite the skip" → receiptIds non-empty. (This deliberately does
      // NOT try to observe a microtask-deferred decision: a microtask drains
      // before the awaiting test continuation resumes, so MINT_SKIPPED is
      // present at assert-time regardless of where it was emitted.)
      test('mint decision stays synchronous and on-path — a skip emits '
          'MINT_SKIPPED and schedules no send', () async {
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final receiptIds = <String>[];

        await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(id: 'msg-skip-onpath-01'),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: null, // non-inbox, no staged id
          sendDeliveryReceipt: (id) async => receiptIds.add(id),
          confirmatoryDirectLanEnabled: false,
        );

        final events = flow.map((e) => e['event']).toList();
        expect(events, contains('DELIVERY_RECEIPT_MINT_SKIPPED'));
        final skip = flow.firstWhere(
          (e) => e['event'] == 'DELIVERY_RECEIPT_MINT_SKIPPED',
        );
        expect((skip['details'] as Map)['reason'], 'nonInbox');
        expect(receiptIds, isEmpty);
      });

      // TC-05: the duplicate-receive re-mint site (`:342`) is also detached.
      // RED on HEAD: the dup path awaits the send → blocks → .timeout fires.
      test('duplicate-receive re-mint is also fire-and-forget', () async {
        const existing = ConversationMessage(
          id: 'msg-dup-fnf-01',
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Hello from sender!',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        messageRepo = FakeMessageRepository(
          existingMessages: {'msg-dup-fnf-01': existing},
        );
        final neverCompletes = Completer<void>();
        var hookInvocations = 0;

        final (result, _, _) = await handleIncomingChatMessage(
          message: buildP2PMessage(buildValidChatJson(id: 'msg-dup-fnf-01')),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'inbox',
          stagedEntryId: 'relay-dup-1',
          sendDeliveryReceipt: (_) {
            hookInvocations++;
            return neverCompletes.future;
          },
        ).timeout(const Duration(seconds: 2));

        expect(result, HandleChatMessageResult.duplicate);
        expect(hookInvocations, 1);
        expect(neverCompletes.isCompleted, isFalse);
      });

      // TC-06: 132 anti-suppression lock — the confirmatory direct/LAN receipt
      // must be DEFERRED, not dropped. Passes on HEAD (flag default true);
      // mutation that adds a direct:/lan: skip of the send re-reds.
      test('confirmatory direct/LAN receipt is deferred but still sent (not '
          'suppressed)', () async {
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        addTearDown(() => debugSetFlowEventSink(null));
        final receiptIds = <String>[];

        await handleIncomingChatMessage(
          message: buildP2PMessage(
            buildValidChatJson(id: 'msg-direct-defer-01'),
          ),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'direct',
          stagedEntryId: 'direct:abc',
          sendDeliveryReceipt: (id) async => receiptIds.add(id),
          // default confirmatory flag (true)
        );
        await pumpEventQueue();

        expect(receiptIds, ['msg-direct-defer-01']);
        final events = flow.map((e) => e['event']).toList();
        expect(events, isNot(contains('DELIVERY_RECEIPT_MINT_SKIPPED')));
      });

      // TC-08: a SYNCHRONOUSLY-throwing hook (throws before returning a Future)
      // must still be caught — the old `try { await ... } catch` caught sync
      // throws too. A bare `sendDeliveryReceipt(id).catchError(...)` would let a
      // sync throw escape (the `.catchError` is never attached), throwing out of
      // the handler AFTER persist; `Future.sync(() => ...).catchError(...)`
      // restores full coverage.
      test('a receipt hook that throws synchronously is caught and logged, not '
          'unhandled', () async {
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final (result, msg, _) = await handleIncomingChatMessage(
          message: buildP2PMessage(buildValidChatJson(id: 'msg-syncthrow-01')),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          transport: 'inbox',
          stagedEntryId: 'relay-syncthrow-1',
          sendDeliveryReceipt: (_) {
            throw StateError('boom-sync'); // throws BEFORE returning a Future
          },
        );
        await pumpEventQueue();

        // The handler returned cleanly (the sync throw did not escape past the
        // persist) and the breadcrumb was still emitted.
        expect(result, HandleChatMessageResult.chatMessage);
        expect(msg, isNotNull);
        final events = flow.map((e) => e['event']).toList();
        expect(events, contains('DELIVERY_RECEIPT_HOOK_ERROR'));
      });
    });
  });

  // 147: decrypt-prefetch skip seam. The inbox-drain pre-decrypt pass
  // (p2p_service_impl `_predecryptInboxChatEntries`) decrypts a page's chat
  // entries concurrently AHEAD of the serial commit loop and threads the
  // resulting plaintext into the handler as `predecryptedText`. When supplied,
  // the handler must use it verbatim and SKIP its own bridge decrypt; when
  // absent (every live path + the gate-off default) behaviour is byte-identical.
  group('147 predecryptedText skip seam', () {
    String innerPayloadJson({
      required String id,
      required String text,
      String? action,
      String? editedAt,
      String timestamp = '2026-02-09T15:30:00.000Z',
    }) {
      return jsonEncode({
        'id': id,
        'text': text,
        'senderPeerId': senderPeerId,
        'senderUsername': 'Alice',
        'timestamp': timestamp,
        if (action != null) 'action': action,
        if (editedAt != null) 'editedAt': editedAt,
      });
    }

    test('147 TC-A6: uses predecryptedText when provided and does not call the '
        'bridge decrypt', () async {
      // A bridge whose decrypt THROWS if invoked — the only way this test
      // persists a message is by skipping the decrypt entirely.
      final bridge = ThrowingDecryptBridge();
      final (result, stored, _) = await handleIncomingChatMessage(
        message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        ownMlKemSecretKey: 'secret-key',
        predecryptedText: innerPayloadJson(
          id: 'msg-predecrypt-1',
          text: 'hello',
        ),
      );

      expect(result, HandleChatMessageResult.chatMessage);
      expect(stored?.text, 'hello');
      expect(
        bridge.decryptCallCount,
        0,
        reason: 'a supplied predecryptedText must skip the bridge decrypt',
      );
      final persisted = await messageRepo.getMessage('msg-predecrypt-1');
      expect(persisted?.text, 'hello');
    });

    test(
      '147 TC-A3: an edit supplied via predecryptedText materializes over its '
      'already-committed base (causal order base->edit, no missing-original)',
      () async {
        // Bridge decrypt THROWS — both base and edit must land via the supplied
        // plaintext, proving predecryptedText carries edit semantics
        // (action/editedAt) AND that committing the base first lets the edit
        // find its target (no CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL).
        final bridge = ThrowingDecryptBridge();

        final (baseResult, _, _) = await handleIncomingChatMessage(
          message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          ownMlKemSecretKey: 'secret-key',
          predecryptedText: innerPayloadJson(
            id: 'msg-edit-base-1',
            text: 'original',
          ),
        );
        expect(baseResult, HandleChatMessageResult.chatMessage);

        final lines = await captureDebugPrintedLines(() async {
          final (editResult, _, _) = await handleIncomingChatMessage(
            message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
            messageRepo: messageRepo,
            contactRepo: contactRepo,
            bridge: bridge,
            ownMlKemSecretKey: 'secret-key',
            predecryptedText: innerPayloadJson(
              id: 'msg-edit-base-1',
              text: 'edited',
              action: 'edit',
              editedAt: '2026-02-09T15:31:00.000Z',
            ),
          );
          expect(editResult, HandleChatMessageResult.chatMessage);
        });

        final stored = await messageRepo.getMessage('msg-edit-base-1');
        expect(
          stored?.text,
          'edited',
          reason: 'the edit applied over its committed base',
        );
        expect(
          lines.any(
            (l) => l.contains('CHAT_MSG_RECEIVE_EDIT_MISSING_ORIGINAL'),
          ),
          isFalse,
          reason: 'base committed first → the edit must not be orphaned',
        );
        expect(bridge.decryptCallCount, 0);
      },
    );

    test(
      '147: a prefetch that recovers via the ML-KEM ring still emits '
      'MLKEM_RING_FALLBACK_USED (parity with the in-handler decrypt path)',
      () async {
        // Primary secret fails cryptographically; the ring secret succeeds — the
        // same P0-B recovery the in-handler `ok` case breadcrumbs. On a prefetch
        // HIT the handler skips its own decrypt, so the breadcrumb must fire from
        // the prefetch or a future ring-fallback investigation would go blind.
        final bridge = _RingFallbackDecryptBridge(
          ringKey: 'ring-secret',
          plaintext: jsonEncode({
            'id': 'msg-ring-1',
            'text': 'recovered',
            'senderPeerId': senderPeerId,
            'senderUsername': 'Alice',
            'timestamp': '2026-02-09T15:30:00.000Z',
          }),
        );

        String? plaintext;
        final lines = await captureDebugPrintedLines(() async {
          plaintext = await predecryptIncomingChatEnvelope(
            message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
            bridge: bridge,
            ownMlKemSecretKey: 'primary-secret',
            fallbackMlKemSecretKeys: ['ring-secret'],
          );
        });

        expect(plaintext, contains('recovered'));
        expect(
          lines.any((l) => l.contains('MLKEM_RING_FALLBACK_USED')),
          isTrue,
          reason: 'ring recovery during prefetch must still breadcrumb',
        );
      },
    );
  });

  // 147: the production inbox-drain predecrypt wiring must honor the listener's
  // blocked-sender policy — a blocked contact's ciphertext is rejected by the
  // listener BEFORE its own decrypt, so the prefetch must not decrypt it into
  // memory either. predecryptStagedInboxChatEntry checks isBlocked FIRST.
  group('147 predecryptStagedInboxChatEntry blocked-sender policy', () {
    ContactModel contact(String peerId, {required bool isBlocked}) =>
        ContactModel(
          peerId: peerId,
          publicKey: 'pk-$peerId',
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Alice',
          signature: 'sig-$peerId',
          scannedAt: '2026-01-01T00:00:00.000Z',
          isBlocked: isBlocked,
        );

    test('returns null WITHOUT decrypting for a blocked sender', () async {
      final bridge = ThrowingDecryptBridge(); // decrypt throws if reached
      final contactRepo = InMemoryContactRepository()
        ..addTestContact(contact(senderPeerId, isBlocked: true));

      final result = await predecryptStagedInboxChatEntry(
        message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
        contactRepo: contactRepo,
        bridge: bridge,
        loadOwnMlKemSecretKey: () async => 'secret',
        loadOwnMlKemSecretKeyRing: () async => const [],
      );

      expect(result, isNull, reason: 'a blocked sender yields no plaintext');
      expect(
        bridge.decryptCallCount,
        0,
        reason: 'blocked ciphertext must never be decrypted into memory',
      );
    });

    test('decrypts a non-blocked known sender', () async {
      final bridge = FakeDecryptBridge()
        ..decryptResponse = {'ok': true, 'plaintext': 'PLAINTEXT-JSON'};
      final contactRepo = InMemoryContactRepository()
        ..addTestContact(contact(senderPeerId, isBlocked: false));

      final result = await predecryptStagedInboxChatEntry(
        message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
        contactRepo: contactRepo,
        bridge: bridge,
        loadOwnMlKemSecretKey: () async => 'secret',
        loadOwnMlKemSecretKeyRing: () async => const [],
      );

      expect(result, 'PLAINTEXT-JSON');
      expect(bridge.decryptCallCount, greaterThan(0));
    });

    test(
      'returns null without decrypting when the local secret is unavailable',
      () async {
        final bridge = ThrowingDecryptBridge();
        final contactRepo = InMemoryContactRepository()
          ..addTestContact(contact(senderPeerId, isBlocked: false));

        final result = await predecryptStagedInboxChatEntry(
          message: buildP2PMessage(buildV2EncryptedEnvelopeJson()),
          contactRepo: contactRepo,
          bridge: bridge,
          loadOwnMlKemSecretKey: () async => null,
          loadOwnMlKemSecretKeyRing: () async => const [],
        );

        expect(result, isNull);
        expect(bridge.decryptCallCount, 0);
      },
    );
  });
}
