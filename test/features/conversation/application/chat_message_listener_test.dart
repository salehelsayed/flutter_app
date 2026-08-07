import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/durable_notification_tone_lease.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/recording_media_auto_download_decider.dart';
import '../../../shared/fakes/spy_recent_remote_notification_gate.dart';

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

// -- Fakes --

class _FakeContactRepository implements ContactRepository {
  final Map<String, ContactModel> _contacts = {};

  void seedContact(ContactModel contact) {
    _contacts[contact.peerId] = contact;
  }

  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);

  @override
  Future<void> addContact(ContactModel contact) async {
    _contacts[contact.peerId] = contact;
  }

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
      _contacts.values.toList();

  @override
  Future<List<ContactModel>> getArchivedContacts() async => [];

  @override
  Future<void> blockContact(String peerId) async {}

  @override
  Future<void> unblockContact(String peerId) async {}

  @override
  Future<void> dismissIntroBanner(String peerId) async {}

  @override
  Future<void> setIntrosSentAt(String peerId, String timestamp) async {}
}

class _FakeMessageRepository implements MessageRepository {
  final List<ConversationMessage> saved = [];
  final Set<String> existingIds;

  _FakeMessageRepository({this.existingIds = const {}});

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    saved.add(message);
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async {
    for (final message in saved.reversed) {
      if (message.id == id) {
        return message;
      }
    }
    if (!existingIds.contains(id)) {
      return null;
    }
    return ConversationMessage(
      id: id,
      contactPeerId: 'existing-contact',
      senderPeerId: 'existing-sender',
      text: 'existing message',
      timestamp: DateTime.utc(2026, 1, 1).toIso8601String(),
      status: 'delivered',
      isIncoming: true,
      createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
    );
  }

  @override
  Future<bool> messageExists(String id) async =>
      existingIds.contains(id) || saved.any((m) => m.id == id);

  @override
  Future<bool> existsByContent(
    String contactPeerId,
    String senderPeerId,
    String text,
    String timestamp,
  ) async => false;

  @override
  Future<bool> existsByDedupKey(
    String contactPeerId,
    String senderPeerId,
    String dedupKey,
  ) async => false;

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

class _FakeMediaAttachmentRepo implements MediaAttachmentRepository {
  final Map<String, List<MediaAttachment>> _store = {};
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];

  void seedAttachments(String messageId, List<MediaAttachment> attachments) {
    _store[messageId] = attachments;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    // Upsert by id (like the real repo / other fakes), not blind-append, so a
    // re-read returns the latest status and rows don't accumulate duplicates.
    final list = _store.putIfAbsent(attachment.messageId, () => []);
    list.removeWhere((stored) => stored.id == attachment.id);
    list.add(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async =>
      // Return a COPY (like the real repo + the other fakes): the auto-download
      // loop iterates this list while downloadMedia upserts into the repo, so
      // handing out the live backing list causes a concurrent-modification.
      List<MediaAttachment>.of(_store[messageId] ?? const []);

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final atts = _store[id];
      if (atts != null && atts.isNotEmpty) {
        result[id] = atts;
      }
    }
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    localPathUpdates.add((id, localPath));
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    downloadStatusUpdates.add((id, downloadStatus));
  }

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

class _FakeBridge implements Bridge {
  Map<String, dynamic> downloadResponse = {'ok': true};
  int downloadCallCount = 0;
  final List<Map<String, dynamic>> requests = [];

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    requests.add(request);
    if (request['cmd'] == 'media:download') {
      downloadCallCount++;
      if (downloadResponse['ok'] == true) {
        final payload = request['payload'] as Map<String, dynamic>? ?? const {};
        final outputPath = payload['outputPath'] as String?;
        if (outputPath != null) {
          final file = File(outputPath);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(const <int>[1, 2, 3]);
        }
      }
    }
    return jsonEncode(downloadResponse);
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class _FakeDecryptBridge implements Bridge {
  Map<String, dynamic> decryptResponse;
  bool throwOnDecrypt;
  int decryptCallCount = 0;
  final List<Map<String, dynamic>> requests = [];

  _FakeDecryptBridge({Map<String, dynamic>? decryptResponse})
    : decryptResponse = decryptResponse ?? {'ok': true, 'plaintext': '{}'},
      throwOnDecrypt = false;

  @override
  Future<String> send(String message) async {
    final req = jsonDecode(message) as Map<String, dynamic>;
    requests.add(req);
    if (req['cmd'] == 'message.decrypt') {
      decryptCallCount++;
      if (throwOnDecrypt) {
        throw Exception('decrypt exploded');
      }
      return jsonEncode(decryptResponse);
    }
    return jsonEncode({'ok': true});
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

class _FakeMediaFileManager extends MediaFileManager {
  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = mime.split('/').last;
    final path = '/tmp/test_media/$contactPeerId/$blobId.$ext';
    await Directory('/tmp/test_media/$contactPeerId').create(recursive: true);
    return path;
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {}

  @override
  Future<void> deleteFile(
    String localPath, {
    String caller = 'MediaFileManager.deleteFile',
    String reason = 'media_file_delete',
    String? storedPath,
    Map<String, Object?> details = const {},
    bool redactTelemetry = false,
  }) async {}
}

class _ThrowingBridge implements Bridge {
  @override
  Future<String> send(String message) async =>
      throw Exception('Bridge exploded');
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> checkHealth() async => true;
  @override
  Future<void> reinitialize() async {}
  @override
  void dispose() {}
  @override
  bool get isInitialized => true;
  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String> listenAddresses, List<String> circuitAddresses)?
  onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

// -- Helpers --

ContactModel _makeContact(
  String peerId, {
  String username = 'Alice',
  bool isBlocked = false,
  bool isArchived = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    isBlocked: isBlocked,
    isArchived: isArchived,
  );
}

Future<ContactModel?> _noopDownloadProfilePicture({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
}) async => null;

ChatMessage _makeChatMessage({
  required String from,
  String text = 'Hello',
  String id = 'msg-test-001',
  String senderUsername = 'Alice',
  List<Map<String, dynamic>>? media,
  String? confirmNonce,
}) {
  final payload = <String, dynamic>{
    'id': id,
    'text': text,
    'senderPeerId': from,
    'senderUsername': senderUsername,
    'timestamp': DateTime.now().toUtc().toIso8601String(),
  };
  if (media != null) {
    payload['media'] = media;
  }

  final json = jsonEncode({
    'type': 'chat_message',
    'version': '1',
    'payload': payload,
  });

  return ChatMessage(
    from: from,
    to: '',
    content: json,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
    confirmNonce: confirmNonce,
  );
}

ChatMessage _makeV2EncryptedChatMessage({
  required String from,
  String id = 'v2-fixture-message',
  String? confirmNonce,
}) {
  final json = jsonEncode({
    'type': 'chat_message',
    'version': '2',
    'id': id,
    'senderPeerId': from,
    'encrypted': {
      'kem': 'kem-blob',
      'ciphertext': 'cipher-blob',
      'nonce': 'nonce-blob',
    },
  });

  return ChatMessage(
    from: from,
    to: '',
    content: json,
    timestamp: DateTime.now().toUtc().toIso8601String(),
    isIncoming: true,
    confirmNonce: confirmNonce,
  );
}

Future<List<String>> _captureDebugPrintedLines(
  Future<void> Function() action,
) async {
  final lines = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      lines.add(message);
    }
  };

  try {
    await action();
  } finally {
    debugPrint = debugPrintThrottled;
    flowEventLoggingEnabled = previousLogging;
  }

  return lines;
}

const _testMediaJson = [
  {
    'id': 'blob-001',
    'mime': 'image/jpeg',
    'size': 245000,
    'mediaType': 'image',
    'width': 1920,
    'height': 1080,
  },
];

void main() {
  group('ChatMessageListener processIncomingMessage', () {
    late _FakeMessageRepository messageRepo;
    late _FakeContactRepository contactRepo;

    setUp(() {
      messageRepo = _FakeMessageRepository();
      contactRepo = _FakeContactRepository();
    });

    ChatMessageListener createListener({
      Bridge? bridge,
      Future<String?> Function()? getOwnMlKemSecretKey,
      Future<void> Function({
        required String contactPeerId,
        required List<String> messageIds,
      })?
      sendDeliveryReceipt,
    }) {
      return ChatMessageListener(
        chatMessageStream: const Stream<ChatMessage>.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: getOwnMlKemSecretKey,
        downloadProfilePictureFn: _noopDownloadProfilePicture,
        sendDeliveryReceipt: sendDeliveryReceipt,
      );
    }

    test(
      'returns blockedSender for blocked contacts before persistence',
      () async {
        const senderPeerId = 'sender-peer-blocked';
        contactRepo.seedContact(
          _makeContact(senderPeerId, isBlocked: true, username: 'Blocked'),
        );
        final listener = createListener();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(from: senderPeerId, id: 'msg-blocked-001'),
        );

        expect(outcome.state, ChatMessageProcessState.blockedSender);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test(
      'returns missingMlKemSecret for staged v2 chat without local key',
      () async {
        const senderPeerId = 'sender-peer-v2';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final listener = createListener();

        final outcome = await listener.processIncomingMessage(
          _makeV2EncryptedChatMessage(from: senderPeerId),
        );

        expect(outcome.state, ChatMessageProcessState.missingMlKemSecret);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test('147: a prefetch HIT (predecryptedText supplied) skips the listener '
        'ML-KEM key load and persists from the supplied plaintext', () async {
      const senderPeerId = 'sender-peer-predecrypt-hit';
      contactRepo.seedContact(_makeContact(senderPeerId));
      var keyLoads = 0;
      // A decrypt that would FAIL if it ran — so a green `stored` outcome
      // proves the handler used the supplied predecryptedText, not the bridge.
      final bridge = _FakeDecryptBridge(
        decryptResponse: {'ok': false, 'errorCode': 'DECRYPT_FAILED'},
      );
      final listener = createListener(
        bridge: bridge,
        getOwnMlKemSecretKey: () async {
          keyLoads++;
          return 'own-secret-key';
        },
      );

      final inner = jsonEncode({
        'id': 'msg-prefetch-hit-001',
        'text': 'prefetched',
        'senderPeerId': senderPeerId,
        'senderUsername': 'Alice',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });

      final outcome = await listener.processIncomingMessage(
        _makeV2EncryptedChatMessage(
          from: senderPeerId,
          id: 'msg-prefetch-hit-001',
        ).copyWith(predecryptedText: inner),
      );

      expect(outcome.state, ChatMessageProcessState.stored);
      expect(
        keyLoads,
        0,
        reason:
            'a prefetch hit must not load the ML-KEM secret in the listener',
      );
    });

    test(
      'maps decryptionDeferred result to decryptionDeferred state',
      () async {
        const senderPeerId = 'sender-peer-v2-deferred';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final bridge = _FakeDecryptBridge(
          decryptResponse: {
            'ok': false,
            'errorCode': 'BRIDGE_TIMEOUT',
            'errorMessage': 'Bridge call timed out after 10s',
          },
        );
        final listener = createListener(
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'own-secret-key',
        );

        final outcome = await listener.processIncomingMessage(
          _makeV2EncryptedChatMessage(from: senderPeerId),
        );

        expect(outcome.state, ChatMessageProcessState.decryptionDeferred);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test(
      'passes staged entry id to receipt-origin handling for LAN replay (Phase 1: now mints)',
      () async {
        const senderPeerId = 'sender-peer-lan-replay';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final receipts = <List<String>>[];
        final listener = createListener(
          sendDeliveryReceipt:
              ({required contactPeerId, required messageIds}) async {
                expect(contactPeerId, senderPeerId);
                receipts.add(List<String>.from(messageIds));
              },
        );

        final relayOutcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-relay-receipt',
          ).copyWith(transport: 'inbox'),
        );

        expect(relayOutcome.state, ChatMessageProcessState.stored);
        expect(receipts, [
          ['msg-relay-receipt'],
        ]);
        receipts.clear();

        // 132 Phase 1 (LIVE by default): a 'lan:' staged replay now ALSO mints a
        // confirmatory receipt (lost-ack repair). The staged id is still
        // correctly threaded — only the OFF-mode skip is gone.
        final lanOutcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-lan-receipt',
          ).copyWith(transport: 'inbox'),
          stagedEntryId: 'lan:n1',
        );

        expect(lanOutcome.state, ChatMessageProcessState.stored);
        expect(receipts, [
          ['msg-lan-receipt'],
        ]);
      },
    );

    test(
      'migration-blocked account rejects direct chat before persistence',
      () async {
        const senderPeerId = 'sender-peer-migrated-out';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final listener = ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          accountMigrationNetworkGate: ({peerId, required operation}) async =>
              false,
          downloadProfilePictureFn: _noopDownloadProfilePicture,
        );

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(from: senderPeerId, id: 'msg-migrated-out-001'),
        );

        expect(outcome.state, ChatMessageProcessState.accountMigrationBlocked);
        expect(messageRepo.saved, isEmpty);
      },
    );

    test(
      'returns editMissingOriginal when edit has no stored original',
      () async {
        const senderPeerId = 'sender-peer-edit';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final listener = createListener();
        final editPayload = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'msg-edit-missing',
            'text': 'Edited text',
            'senderPeerId': senderPeerId,
            'senderUsername': 'Alice',
            'timestamp': DateTime.now().toUtc().toIso8601String(),
            'action': 'edit',
            'editedAt': '2026-04-01T10:00:00.000Z',
          },
        });

        final outcome = await listener.processIncomingMessage(
          ChatMessage(
            from: senderPeerId,
            to: '',
            content: editPayload,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
          ),
        );

        expect(outcome.state, ChatMessageProcessState.editMissingOriginal);
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.isHidden, isTrue);
      },
    );

    test(
      'suppresses phantom UI on edit-first delivery and emits the edited row when the original arrives later',
      () async {
        const senderPeerId = 'sender-peer-edit-late-original';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final listener = createListener();
        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        final editPayload = jsonEncode({
          'type': 'chat_message',
          'version': '1',
          'payload': {
            'id': 'msg-edit-late-original',
            'text': 'Edited before original',
            'senderPeerId': senderPeerId,
            'senderUsername': 'Alice',
            'timestamp': '2026-04-01T09:59:00.000Z',
            'action': 'edit',
            'editedAt': '2026-04-01T10:00:00.000Z',
          },
        });

        final firstOutcome = await listener.processIncomingMessage(
          ChatMessage(
            from: senderPeerId,
            to: '',
            content: editPayload,
            timestamp: '2026-04-01T10:00:00.000Z',
            isIncoming: true,
          ),
        );

        expect(firstOutcome.state, ChatMessageProcessState.editMissingOriginal);
        expect(emitted, isEmpty);
        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.single.isHidden, isTrue);

        final secondOutcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-edit-late-original',
            text: 'Original text',
          ),
        );

        expect(secondOutcome.state, ChatMessageProcessState.stored);
        expect(emitted, hasLength(1));
        expect(emitted.single.id, 'msg-edit-late-original');
        expect(emitted.single.text, 'Edited before original');
        expect(emitted.single.isHidden, isFalse);
        expect(emitted.single.editedAt, '2026-04-01T10:00:00.000Z');
        expect(messageRepo.saved.last.isHidden, isFalse);
        expect(messageRepo.saved.last.text, 'Edited before original');
      },
    );

    test('confirms stored direct chat nonce with ok=true', () async {
      const senderPeerId = 'sender-peer-confirm-store';
      contactRepo.seedContact(_makeContact(senderPeerId));
      final bridge = _FakeBridge();
      final listener = createListener(bridge: bridge);

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-confirm-store',
          confirmNonce: 'nonce-store',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.stored);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-store', 'ok': true}),
      );
    });

    test('confirms duplicate direct chat nonce with ok=true', () async {
      const senderPeerId = 'sender-peer-confirm-duplicate';
      messageRepo = _FakeMessageRepository(existingIds: {'msg-dup-001'});
      contactRepo.seedContact(_makeContact(senderPeerId));
      final bridge = _FakeBridge();
      final listener = createListener(bridge: bridge);

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-dup-001',
          confirmNonce: 'nonce-dup',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.duplicate);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-dup', 'ok': true}),
      );
    });

    test('confirms ignored edit direct chat nonce with ok=true', () async {
      const senderPeerId = 'sender-peer-confirm-ignored-edit';
      const messageId = 'msg-confirm-ignored-edit';
      const editedAt = '2026-04-01T10:00:00.000Z';
      contactRepo.seedContact(_makeContact(senderPeerId));
      await messageRepo.saveMessage(
        const ConversationMessage(
          id: messageId,
          contactPeerId: senderPeerId,
          senderPeerId: senderPeerId,
          text: 'Already edited',
          timestamp: '2026-04-01T09:59:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-04-01T09:59:00.000Z',
          editedAt: editedAt,
        ),
      );
      final bridge = _FakeBridge();
      final listener = createListener(bridge: bridge);
      final editPayload = jsonEncode({
        'type': 'chat_message',
        'version': '1',
        'payload': {
          'id': messageId,
          'text': 'Already edited',
          'senderPeerId': senderPeerId,
          'senderUsername': 'Alice',
          'timestamp': '2026-04-01T09:59:00.000Z',
          'action': 'edit',
          'editedAt': editedAt,
        },
      });

      final outcome = await listener.processIncomingMessage(
        ChatMessage(
          from: senderPeerId,
          to: '',
          content: editPayload,
          timestamp: '2026-04-01T10:00:01.000Z',
          isIncoming: true,
          confirmNonce: 'nonce-ignored-edit',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.ignoredEdit);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-ignored-edit', 'ok': true}),
      );
    });

    test('confirms blocked sender nonce with ok=true', () async {
      const senderPeerId = 'sender-peer-confirm-blocked';
      contactRepo.seedContact(
        _makeContact(senderPeerId, isBlocked: true, username: 'Blocked'),
      );
      final bridge = _FakeBridge();
      final listener = createListener(bridge: bridge);

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-confirm-blocked',
          confirmNonce: 'nonce-blocked',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.blockedSender);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-blocked', 'ok': true}),
      );
    });

    test(
      'confirms retryable decrypt-missing-key nonce with ok=false',
      () async {
        const senderPeerId = 'sender-peer-confirm-v2';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final bridge = _FakeBridge();
        final listener = createListener(bridge: bridge);

        final outcome = await listener.processIncomingMessage(
          _makeV2EncryptedChatMessage(
            from: senderPeerId,
            confirmNonce: 'nonce-v2',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.missingMlKemSecret);
        final confirmRequests = bridge.requests
            .where((request) => request['cmd'] == 'message:confirm')
            .toList();
        expect(confirmRequests, hasLength(1));
        expect(
          confirmRequests.single['payload'],
          equals({'nonce': 'nonce-v2', 'ok': false}),
        );
      },
    );

    test('confirms direct nonce ok=false for decryptionDeferred', () async {
      const senderPeerId = 'sender-peer-confirm-deferred';
      contactRepo.seedContact(_makeContact(senderPeerId));
      final bridge = _FakeDecryptBridge(
        decryptResponse: {
          'ok': false,
          'errorCode': 'BRIDGE_TIMEOUT',
          'errorMessage': 'Bridge call timed out after 10s',
        },
      );
      final listener = createListener(
        bridge: bridge,
        getOwnMlKemSecretKey: () async => 'own-secret-key',
      );

      final outcome = await listener.processIncomingMessage(
        _makeV2EncryptedChatMessage(
          from: senderPeerId,
          confirmNonce: 'nonce-deferred',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.decryptionDeferred);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-deferred', 'ok': false}),
      );
    });

    test('confirms direct nonce ok=false for decryptionFailed', () async {
      const senderPeerId = 'sender-peer-confirm-failed';
      contactRepo.seedContact(_makeContact(senderPeerId));
      final bridge = _FakeDecryptBridge(
        decryptResponse: {
          'ok': false,
          'errorCode': 'INTERNAL_ERROR',
          'errorMessage': 'message authentication failed',
        },
      );
      final listener = createListener(
        bridge: bridge,
        getOwnMlKemSecretKey: () async => 'own-secret-key',
      );

      final outcome = await listener.processIncomingMessage(
        _makeV2EncryptedChatMessage(
          from: senderPeerId,
          confirmNonce: 'nonce-failed',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.decryptionFailed);
      final confirmRequests = bridge.requests
          .where((request) => request['cmd'] == 'message:confirm')
          .toList();
      expect(confirmRequests, hasLength(1));
      expect(
        confirmRequests.single['payload'],
        equals({'nonce': 'nonce-failed', 'ok': false}),
      );
    });
  });

  group('ChatMessageListener auto-download', () {
    late StreamController<ChatMessage> chatStreamController;
    late _FakeMessageRepository messageRepo;
    late _FakeContactRepository contactRepo;
    late _FakeBridge bridge;
    late _FakeMediaAttachmentRepo mediaRepo;
    late _FakeMediaFileManager fileManager;

    setUp(() {
      chatStreamController = StreamController<ChatMessage>.broadcast();
      messageRepo = _FakeMessageRepository();
      contactRepo = _FakeContactRepository();
      bridge = _FakeBridge();
      mediaRepo = _FakeMediaAttachmentRepo();
      fileManager = _FakeMediaFileManager();
    });

    tearDown(() {
      chatStreamController.close();
    });

    ChatMessageListener createListener({
      Bridge? overrideBridge,
      _FakeMediaAttachmentRepo? overrideMediaRepo,
      MediaFileManager? overrideFileManager,
    }) {
      return ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: overrideBridge ?? bridge,
        mediaAttachmentRepo: overrideMediaRepo ?? mediaRepo,
        mediaFileManager: overrideFileManager ?? fileManager,
        downloadProfilePictureFn: _noopDownloadProfilePicture,
      );
    }

    test(
      'private receive emits only after durable save and never auto-downloads',
      () async {
        const senderPeerId = 'sender-private-media';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final listener = createListener();
        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);
        final inner = jsonEncode({
          'id': 'private-listener-1',
          'text': '',
          'senderPeerId': senderPeerId,
          'senderUsername': 'Alice',
          'timestamp': '2026-07-11T09:00:00.000Z',
          'media': _testMediaJson,
          'privateMedia': {'version': 1, 'mode': 'protected'},
        });

        final outcome = await listener.processIncomingMessage(
          _makeV2EncryptedChatMessage(
            from: senderPeerId,
            id: 'private-listener-1',
          ).copyWith(predecryptedText: inner),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(messageRepo.saved, hasLength(1));
        expect(emitted, hasLength(1));
        expect(emitted.single.id, messageRepo.saved.single.id);
        expect(bridge.downloadCallCount, 0);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);

        listener.dispose();
      },
    );

    test('start is idempotent and does not duplicate processing', () async {
      final senderPeerId = 'sender-peer-start-idempotent';
      contactRepo.seedContact(_makeContact(senderPeerId));

      final listener = createListener();
      listener.start();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(from: senderPeerId, id: 'msg-start-idempotent'),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(messageRepo.saved, hasLength(1));
      expect(emitted, hasLength(1));

      listener.dispose();
    });

    test(
      'stop cancels subscription and ignores later incoming messages',
      () async {
        final senderPeerId = 'sender-peer-stop';
        contactRepo.seedContact(_makeContact(senderPeerId));

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        listener.stop();

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, id: 'msg-after-stop'),
        );

        await Future.delayed(const Duration(milliseconds: 150));

        expect(messageRepo.saved, isEmpty);
        expect(emitted, isEmpty);

        listener.dispose();
      },
    );

    test('rejects blocked sender without persisting or emitting', () async {
      final senderPeerId = 'sender-peer-blocked';
      contactRepo.seedContact(_makeContact(senderPeerId, isBlocked: true));

      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(from: senderPeerId, id: 'msg-blocked'),
      );

      await Future.delayed(const Duration(milliseconds: 150));

      expect(messageRepo.saved, isEmpty);
      expect(emitted, isEmpty);

      listener.dispose();
    });

    test(
      'allows a later incoming message through once the sender is unblocked',
      () async {
        const senderPeerId = 'sender-peer-unblocked';
        contactRepo.seedContact(
          _makeContact(senderPeerId, isBlocked: true, username: 'Bob'),
        );

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, id: 'msg-while-blocked'),
        );

        await Future.delayed(const Duration(milliseconds: 150));

        expect(messageRepo.saved, isEmpty);
        expect(emitted, isEmpty);

        await contactRepo.addContact(
          _makeContact(senderPeerId, username: 'Bob'),
        );

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, id: 'msg-after-unblock'),
        );

        await Future.delayed(const Duration(milliseconds: 150));

        expect(messageRepo.saved.map((message) => message.id), [
          'msg-after-unblock',
        ]);
        expect(emitted.map((message) => message.id), ['msg-after-unblock']);

        listener.dispose();
      },
    );

    test(
      'persists archived sender message but suppresses UI emission',
      () async {
        final senderPeerId = 'sender-peer-archived';
        contactRepo.seedContact(_makeContact(senderPeerId, isArchived: true));

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, id: 'msg-archived'),
        );

        await Future.delayed(const Duration(milliseconds: 150));

        expect(messageRepo.saved, hasLength(1));
        expect(messageRepo.saved.first.id, 'msg-archived');
        expect(emitted, isEmpty);

        listener.dispose();
      },
    );

    test('emits contactUpdatedStream when sender username changes', () async {
      final senderPeerId = 'sender-peer-rename';
      contactRepo.seedContact(
        _makeContact(senderPeerId, username: 'Alice Old'),
      );

      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      final contactUpdates = <ContactModel>[];
      listener.incomingMessageStream.listen(emitted.add);
      listener.contactUpdatedStream.listen(contactUpdates.add);

      chatStreamController.add(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-rename',
          senderUsername: 'Alice New',
        ),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(messageRepo.saved, hasLength(1));
      expect(emitted, hasLength(1));
      expect(contactUpdates, hasLength(1));
      expect(contactUpdates.first.peerId, senderPeerId);
      expect(contactUpdates.first.username, 'Alice New');

      final updated = await contactRepo.getContact(senderPeerId);
      expect(updated, isNotNull);
      expect(updated!.username, 'Alice New');

      listener.dispose();
    });

    test(
      'transport from ChatMessage flows through to ConversationMessage',
      () async {
        final senderPeerId = 'sender-peer-transport';
        contactRepo.seedContact(_makeContact(senderPeerId));

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        // Create a ChatMessage with transport='wifi'
        final chatMsg = _makeChatMessage(
          from: senderPeerId,
          id: 'msg-transport-flow',
        ).copyWith(transport: 'wifi');
        chatStreamController.add(chatMsg);

        await Future.delayed(const Duration(milliseconds: 200));

        expect(emitted.length, greaterThanOrEqualTo(1));
        expect(emitted.first.transport, 'wifi');

        listener.dispose();
      },
    );

    test(
      'auto-downloads pending attachments and re-emits message with media',
      () async {
        final senderPeerId = 'sender-peer-001';
        contactRepo.seedContact(_makeContact(senderPeerId));

        // No need to pre-seed — handleIncomingChatMessage persists media from wire JSON
        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, media: _testMediaJson),
        );

        await _waitUntil(() => emitted.length >= 2);

        // Should get 2 emissions: initial (no media) + re-emit (with media)
        expect(emitted.length, 2);
        expect(
          emitted[0].media,
          hasLength(1),
        ); // first emission now carries pending-status attachments from wire payload
        expect(emitted[0].media[0].downloadStatus, 'pending');
        expect(
          emitted[1].media,
          hasLength(1),
        ); // re-emission has downloaded media
        expect(emitted[1].media[0].downloadStatus, 'done');
        expect(emitted[1].media[0].localPath, isNotNull);

        listener.dispose();
      },
    );

    test('skips already-downloaded attachments', () async {
      final senderPeerId = 'sender-peer-002';
      contactRepo.seedContact(_makeContact(senderPeerId));

      mediaRepo.seedAttachments('msg-test-002', [
        const MediaAttachment(
          id: 'blob-already-done',
          messageId: 'msg-test-002',
          mime: 'image/png',
          size: 100000,
          mediaType: 'image',
          localPath: '/existing/path.png',
          downloadStatus: 'done',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      ]);

      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(from: senderPeerId, id: 'msg-test-002'),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Re-emitted message should have the already-done attachment unchanged
      expect(emitted.length, 2);
      final reEmit = emitted[1];
      expect(reEmit.media[0].downloadStatus, 'done');
      expect(reEmit.media[0].localPath, '/existing/path.png');

      // Bridge should NOT have been called (no download needed)
      expect(bridge.downloadCallCount, 0);

      listener.dispose();
    });

    test(
      'skips relay download for locally-ready persisted attachment metadata',
      () async {
        final senderPeerId = 'sender-peer-local-ready';
        contactRepo.seedContact(_makeContact(senderPeerId));

        mediaRepo.seedAttachments('msg-local-ready', [
          const MediaAttachment(
            id: 'blob-local-ready',
            messageId: 'msg-local-ready',
            mime: 'audio/aac',
            size: 2048,
            mediaType: 'audio',
            localPath: 'media/sender-peer-local-ready/blob-local-ready.m4a',
            downloadStatus: 'done',
            durationMs: 1200,
            waveform: [0.2, 0.5, 0.8],
            createdAt: '2026-02-20T10:00:00.000Z',
          ),
        ]);

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(from: senderPeerId, id: 'msg-local-ready'),
        );

        await Future.delayed(const Duration(milliseconds: 200));

        expect(emitted.length, 2);
        final hydrated = emitted[1].media.single;
        expect(hydrated.downloadStatus, 'done');
        expect(
          hydrated.localPath,
          'media/sender-peer-local-ready/blob-local-ready.m4a',
        );
        expect(bridge.downloadCallCount, 0);

        listener.dispose();
      },
    );

    test(
      'marks attachment terminal download_failed on relay not-found',
      () async {
        final senderPeerId = 'sender-peer-003';
        contactRepo.seedContact(_makeContact(senderPeerId));

        // handleIncomingChatMessage persists media from wire JSON
        bridge.downloadResponse = {
          'ok': false,
          'errorCode': 'NOT_FOUND',
          'errorMessage': 'Blob not found',
        };

        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-test-003',
            media: _testMediaJson,
          ),
        );

        await Future.delayed(const Duration(milliseconds: 200));

        expect(emitted.length, 2);
        // 'Blob not found' is a relay-unavailable response -> honest terminal
        // download_failed, not a retryable failed (INV-DL-4).
        expect(emitted[1].media[0].downloadStatus, 'download_failed');

        listener.dispose();
      },
    );

    test('handles bridge exception during download gracefully', () async {
      final senderPeerId = 'sender-peer-004';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // handleIncomingChatMessage persists media from wire JSON
      final listener = createListener(overrideBridge: _ThrowingBridge());
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-test-004',
          media: _testMediaJson,
        ),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      expect(emitted.length, 2);
      // Re-emitted message should have failed status from catch
      expect(emitted[1].media[0].downloadStatus, 'failed');

      listener.dispose();
    });

    test('does not auto-download when no attachments in repo', () async {
      final senderPeerId = 'sender-peer-005';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // No attachments seeded in mediaRepo

      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(from: senderPeerId, id: 'msg-test-005'),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Only the initial emission — no re-emit since no attachments
      expect(emitted.length, 1);
      expect(bridge.downloadCallCount, 0);

      listener.dispose();
    });

    test('does not auto-download when mediaFileManager is null', () async {
      final senderPeerId = 'sender-peer-006';
      contactRepo.seedContact(_makeContact(senderPeerId));

      mediaRepo.seedAttachments('msg-test-006', [
        const MediaAttachment(
          id: 'blob-no-fm',
          messageId: 'msg-test-006',
          mime: 'image/jpeg',
          size: 245000,
          mediaType: 'image',
          downloadStatus: 'pending',
          createdAt: '2026-02-20T10:00:00.000Z',
        ),
      ]);

      // Create listener without mediaFileManager
      final listener = ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        // mediaFileManager is null
      );
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(from: senderPeerId, id: 'msg-test-006'),
      );

      await Future.delayed(const Duration(milliseconds: 200));

      // Only initial emission — auto-download guard prevents re-emit
      expect(emitted.length, 1);
      expect(bridge.downloadCallCount, 0);

      listener.dispose();
    });

    test('auto-downloads multiple attachments in a single message', () async {
      final senderPeerId = 'sender-peer-007';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // No pre-seeding — handleIncomingChatMessage persists media from wire JSON
      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-test-007',
          media: [
            {
              'id': 'blob-a',
              'mime': 'image/jpeg',
              'size': 100000,
              'mediaType': 'image',
            },
            {
              'id': 'blob-b',
              'mime': 'image/png',
              'size': 200000,
              'mediaType': 'image',
            },
          ],
        ),
      );

      await _waitUntil(
        () =>
            emitted.length >= 2 &&
            bridge.downloadCallCount >= 2 &&
            emitted.last.media.length == 2 &&
            emitted.last.media.every(
              (attachment) => attachment.downloadStatus == 'done',
            ),
      );

      expect(emitted.length, 2);
      expect(emitted[1].media, hasLength(2));
      expect(emitted[1].media[0].downloadStatus, 'done');
      expect(emitted[1].media[1].downloadStatus, 'done');

      // Bridge called twice (once per attachment)
      expect(bridge.downloadCallCount, 2);

      listener.dispose();
    });

    test(
      'text message appears instantly before auto-download completes',
      () async {
        final senderPeerId = 'sender-peer-008';
        contactRepo.seedContact(_makeContact(senderPeerId));

        // handleIncomingChatMessage persists media from wire JSON
        final listener = createListener();
        listener.start();

        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-test-008',
            text: 'Check out this photo!',
            media: _testMediaJson,
          ),
        );

        // First emission should come very quickly (before download)
        await Future.delayed(const Duration(milliseconds: 50));
        expect(emitted.length, greaterThanOrEqualTo(1));
        expect(emitted[0].text, 'Check out this photo!');
        expect(emitted[0].id, 'msg-test-008');

        // Wait for download to complete
        await Future.delayed(const Duration(milliseconds: 250));
        expect(emitted.length, 2);

        listener.dispose();
      },
    );
  });

  group('ChatMessageListener notification integration', () {
    late StreamController<ChatMessage> chatStreamController;
    late _FakeMessageRepository messageRepo;
    late _FakeContactRepository contactRepo;
    late FakeNotificationService notificationService;
    late ActiveConversationTracker tracker;
    late RecentRemoteNotificationGate remoteNotificationGate;

    setUp(() {
      chatStreamController = StreamController<ChatMessage>.broadcast();
      messageRepo = _FakeMessageRepository();
      contactRepo = _FakeContactRepository();
      notificationService = FakeNotificationService();
      tracker = ActiveConversationTracker();
      remoteNotificationGate = RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/chat-listener-notification-test-${DateTime.now().microsecondsSinceEpoch}.json',
      );
    });

    tearDown(() async {
      await chatStreamController.close();
      await remoteNotificationGate.clear();
    });

    ChatMessageListener createListenerWithNotifications({
      AppLifecycleState lifecycleState = AppLifecycleState.paused,
      Bridge? bridge,
      Future<String?> Function()? getOwnMlKemSecretKey,
      RecentRemoteNotificationGate? notificationGate,
      NotificationToneTracker? notificationToneTracker,
      Future<DurableNotificationToneLease> Function()?
      durableNotificationCoordinatorResolver,
      Duration backgroundNotificationDuplicateGuardDelay = Duration.zero,
    }) {
      return ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        getOwnMlKemSecretKey: getOwnMlKemSecretKey,
        notificationService: notificationService,
        conversationTracker: tracker,
        notificationToneTracker: notificationToneTracker,
        durableNotificationCoordinatorResolver:
            durableNotificationCoordinatorResolver,
        getAppLifecycleState: () => lifecycleState,
        remoteNotificationGate: notificationGate ?? remoteNotificationGate,
        backgroundNotificationDuplicateGuardDelay:
            backgroundNotificationDuplicateGuardDelay,
        downloadProfilePictureFn: _noopDownloadProfilePicture,
      );
    }

    test(
      'shows notification for incoming message when app is backgrounded',
      () async {
        final senderPeerId = 'sender-notif-001';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.paused,
        );
        listener.start();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-001',
            text: 'Hey there!',
            senderUsername: 'Bob',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.senderUsername, 'Bob');
        expect(notificationService.shown.first.messageText, 'Hey there!');
        expect(notificationService.shown.first.contactPeerId, senderPeerId);

        listener.dispose();
      },
    );

    test('live direct message commits an exact typed durable claim', () async {
      final senderPeerId = 'sender-durable-claim';
      contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));
      final directory = await Directory.systemTemp.createTemp(
        'chat-listener-durable-claim-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final listener = createListenerWithNotifications(
        durableNotificationCoordinatorResolver: () async =>
            DurableNotificationToneLease(directory: directory),
      );
      listener.start();

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(
          from: senderPeerId,
          id: 'direct-message-claim-1',
          text: 'Claimed once',
          senderUsername: 'Bob',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.stored);
      expect(notificationService.shown, hasLength(1));
      final claim = File(
        '${directory.path}/NotificationServiceDedupe/'
        'new_message-direct-message-claim-1',
      );
      expect(claim.existsSync(), isTrue);
      expect(claim.readAsStringSync(), contains('"state":"committed"'));
      listener.dispose();
    });

    test(
      'private and unsupported notifications use the generic leak-free body',
      () async {
        const senderPeerId = 'sender-private-notification';
        contactRepo.seedContact(
          _makeContact(senderPeerId, username: 'Private sender'),
        );
        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.paused,
        );
        final policies = <Map<String, Object>>[
          {'version': 1, 'mode': 'protected'},
          {'version': 9, 'mode': 'future-mode'},
        ];

        for (var index = 0; index < policies.length; index++) {
          final id = 'private-notification-$index';
          final outcome = await listener.processIncomingMessage(
            _makeV2EncryptedChatMessage(from: senderPeerId, id: id).copyWith(
              predecryptedText: jsonEncode({
                'id': id,
                'text': index == 0 ? '' : 'future private caption',
                'senderPeerId': senderPeerId,
                'senderUsername': 'Private sender',
                'timestamp': '2026-07-11T09:00:0$index.000Z',
                'media': _testMediaJson,
                'privateMedia': policies[index],
              }),
            ),
          );
          expect(outcome.state, ChatMessageProcessState.stored);
        }
        expect(notificationService.shown, hasLength(2));
        for (final shown in notificationService.shown) {
          expect(shown.messageText, 'Private media');
          expect(shown.contactPeerId, senderPeerId);
          for (final forbidden in [
            'protected',
            'future-mode',
            'future private caption',
            'image/jpeg',
          ]) {
            expect(shown.messageText, isNot(contains(forbidden)));
          }
        }

        listener.dispose();
      },
    );

    // 120 G4 — locks `toneTracker: notificationToneTracker` at
    // chat_message_listener.dart:571. Removing that arg makes both messages
    // audible, which this guard catches.
    test(
      'toneTracker is wired: two direct messages, same conversation, in-window → first audible, second silent',
      () async {
        final senderPeerId = 'sender-notif-tone-wired';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));

        // Single fixed clock so both messages fall inside the 30s window.
        final fixedNow = DateTime.utc(2026, 6, 13, 12, 0, 0);
        final toneTracker = NotificationToneTracker(
          clock: () => fixedNow,
          window: const Duration(seconds: 30),
        );

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.paused,
          notificationToneTracker: toneTracker,
        );
        listener.start();

        final firstOutcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-tone-wired-1',
            text: 'First',
            senderUsername: 'Bob',
          ),
        );

        final secondOutcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-tone-wired-2',
            text: 'Second',
            senderUsername: 'Bob',
          ),
        );

        expect(firstOutcome.state, ChatMessageProcessState.stored);
        expect(secondOutcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, hasLength(2));
        expect(notificationService.shown[0].silent, isFalse);
        expect(notificationService.shown[1].silent, isTrue);

        listener.dispose();
      },
    );

    // 120 G4 — locks the live-wins mark closure at
    // chat_message_listener.dart:582-588. Removing it means a live direct
    // notification no longer writes a dedup marker, so a late FCM isolate for
    // the same message double-alerts. This guard catches the missing mark.
    test(
      'markRecentRemoteNotificationAnnouncement is wired: a live direct notification marks the gate',
      () async {
        final senderPeerId = 'sender-notif-mark-wired';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));

        final spyGate = SpyRecentRemoteNotificationGate();
        addTearDown(spyGate.clear);

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.paused,
          notificationGate: spyGate,
        );
        listener.start();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-mark-wired-1',
            text: 'Live direct',
            senderUsername: 'Bob',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, hasLength(1));
        expect(spyGate.markCalls, hasLength(1));
        expect(spyGate.markCalls.single.payload, senderPeerId);
        expect(spyGate.markCalls.single.messageId, 'msg-mark-wired-1');

        listener.dispose();
      },
    );

    test(
      'suppresses local notification when a recent remote push already announced the same conversation',
      () async {
        final senderPeerId = 'sender-notif-remote-push';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));
        final gate = RecentRemoteNotificationGate(
          filePath:
              '${Directory.systemTemp.path}/chat-listener-remote-push-${DateTime.now().microsecondsSinceEpoch}.json',
        );
        addTearDown(gate.clear);
        await gate.markAnnouncement(
          payload: senderPeerId,
          messageId: 'msg-notif-remote-push',
        );

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.paused,
          notificationGate: gate,
          backgroundNotificationDuplicateGuardDelay: Duration.zero,
        );
        listener.start();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-remote-push',
            text: 'Hey there!',
            senderUsername: 'Bob',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, isEmpty);
        expect(messageRepo.saved, hasLength(1));

        listener.dispose();
      },
    );

    test(
      'recovery replay persists the message without showing a local notification',
      () async {
        final senderPeerId = 'sender-notif-replay';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Bob'));

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.resumed,
        );

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-replay',
            text: 'Recovered from inbox',
            senderUsername: 'Bob',
          ),
          suppressNotification: true,
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, isEmpty);
        expect(messageRepo.saved, hasLength(1));

        listener.dispose();
      },
    );

    test(
      'shows notification when app is resumed but not viewing that conversation',
      () async {
        final senderPeerId = 'sender-notif-002';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Alice'));

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.resumed,
        );
        listener.start();

        // User is on feed screen (tracker has no active conversation)
        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-002',
            text: 'Are you there?',
            senderUsername: 'Alice',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, hasLength(1));

        listener.dispose();
      },
    );

    test(
      'suppresses notification when app is resumed and viewing sender conversation',
      () async {
        final senderPeerId = 'sender-notif-003';
        contactRepo.seedContact(
          _makeContact(senderPeerId, username: 'Charlie'),
        );

        tracker.setActive(senderPeerId);

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.resumed,
        );
        listener.start();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-003',
            text: 'Hello',
            senderUsername: 'Charlie',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, isEmpty);
        // But message should still be persisted and emitted
        expect(messageRepo.saved, hasLength(1));

        listener.dispose();
      },
    );

    test('no notification when all notification params are null', () async {
      final senderPeerId = 'sender-notif-004';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // Create listener WITHOUT notification params
      final listener = ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      listener.start();

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(from: senderPeerId, id: 'msg-notif-004'),
      );

      // Message should still be persisted
      expect(outcome.state, ChatMessageProcessState.stored);
      expect(messageRepo.saved, hasLength(1));
      // No notification service was provided, so no notifications
      expect(notificationService.shown, isEmpty);

      listener.dispose();
    });

    test('no notification for blocked sender', () async {
      final senderPeerId = 'sender-notif-005';
      contactRepo.seedContact(_makeContact(senderPeerId, isBlocked: true));

      final listener = createListenerWithNotifications();
      listener.start();

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(from: senderPeerId, id: 'msg-notif-005'),
      );

      // Message rejected — neither persisted nor notification shown
      expect(outcome.state, ChatMessageProcessState.blockedSender);
      expect(messageRepo.saved, isEmpty);
      expect(notificationService.shown, isEmpty);

      listener.dispose();
    });

    test('no notification for archived sender', () async {
      final senderPeerId = 'sender-notif-006';
      contactRepo.seedContact(_makeContact(senderPeerId, isArchived: true));

      final listener = createListenerWithNotifications();
      listener.start();

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(from: senderPeerId, id: 'msg-notif-006'),
      );

      // Message persisted but UI emission suppressed — no notification
      expect(outcome.state, ChatMessageProcessState.stored);
      expect(messageRepo.saved, hasLength(1));
      expect(notificationService.shown, isEmpty);

      listener.dispose();
    });

    test(
      'shows notification when viewing a different conversation (not the sender)',
      () async {
        final senderPeerId = 'sender-notif-007';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Dave'));

        // User is viewing someone else's conversation
        tracker.setActive('some-other-peer');

        final listener = createListenerWithNotifications(
          lifecycleState: AppLifecycleState.resumed,
        );
        listener.start();

        final outcome = await listener.processIncomingMessage(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-notif-007',
            text: 'Hey!',
            senderUsername: 'Dave',
          ),
        );

        expect(outcome.state, ChatMessageProcessState.stored);
        expect(notificationService.shown, hasLength(1));
        expect(notificationService.shown.first.senderUsername, 'Dave');

        listener.dispose();
      },
    );

    test('notification uses sender username from contact repo', () async {
      final senderPeerId = 'sender-notif-008';
      contactRepo.seedContact(_makeContact(senderPeerId, username: 'Eve'));

      final listener = createListenerWithNotifications();
      listener.start();

      final outcome = await listener.processIncomingMessage(
        _makeChatMessage(
          from: senderPeerId,
          id: 'msg-notif-008',
          text: 'Test',
          senderUsername: 'Eve',
        ),
      );

      expect(outcome.state, ChatMessageProcessState.stored);
      expect(notificationService.shown, hasLength(1));
      expect(notificationService.shown.first.senderUsername, 'Eve');

      listener.dispose();
    });

    test(
      'decrypt failure is intentionally ignored without persist emit or notification',
      () async {
        final senderPeerId = 'sender-notif-decrypt-fail';
        contactRepo.seedContact(_makeContact(senderPeerId, username: 'Frank'));
        final bridge = _FakeDecryptBridge(
          decryptResponse: {
            'ok': false,
            'errorCode': 'DECRYPT_FAILED',
            'errorMessage': 'cannot decrypt',
          },
        );

        final listener = createListenerWithNotifications(
          bridge: bridge,
          getOwnMlKemSecretKey: () async => 'own-secret-key',
        );
        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);
        listener.start();

        ChatMessageProcessState? outcomeState;
        final lines = await _captureDebugPrintedLines(() async {
          final outcome = await listener.processIncomingMessage(
            _makeV2EncryptedChatMessage(from: senderPeerId),
          );
          outcomeState = outcome.state;
        });

        expect(outcomeState, ChatMessageProcessState.decryptionFailed);
        expect(messageRepo.saved, isEmpty);
        expect(emitted, isEmpty);
        expect(notificationService.shown, isEmpty);
        expect(bridge.decryptCallCount, 1);
        expect(
          lines.any((line) => line.contains('CHAT_LISTENER_DECRYPT_FAILED')),
          isTrue,
        );

        listener.dispose();
      },
    );
  });

  group('ChatMessageListener 229 auto-download policy', () {
    late StreamController<ChatMessage> chatStreamController;
    late _FakeMessageRepository messageRepo;
    late _FakeContactRepository contactRepo;
    late _FakeBridge bridge;
    late _FakeMediaAttachmentRepo mediaRepo;
    late _FakeMediaFileManager fileManager;

    setUp(() {
      chatStreamController = StreamController<ChatMessage>.broadcast();
      messageRepo = _FakeMessageRepository();
      contactRepo = _FakeContactRepository();
      bridge = _FakeBridge();
      mediaRepo = _FakeMediaAttachmentRepo();
      fileManager = _FakeMediaFileManager();
    });

    tearDown(() {
      chatStreamController.close();
    });

    ChatMessageListener createListener({
      RecordingMediaAutoDownloadDecider? decider,
    }) {
      return ChatMessageListener(
        chatMessageStream: chatStreamController.stream,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        bridge: bridge,
        mediaAttachmentRepo: mediaRepo,
        mediaFileManager: fileManager,
        downloadProfilePictureFn: _noopDownloadProfilePicture,
        autoDownloadDecider: decider,
      );
    }

    test(
      'private and unsupported rows bypass auto-download policy and transfer',
      () async {
        const senderPeerId = 'sender-private-auto-gate';
        contactRepo.seedContact(_makeContact(senderPeerId));
        final allowing = RecordingMediaAutoDownloadDecider();
        final listener = createListener(decider: allowing);
        final emitted = <ConversationMessage>[];
        listener.incomingMessageStream.listen(emitted.add);
        final policies = <Map<String, Object>>[
          {'version': 1, 'mode': 'protected'},
          {'version': 9, 'mode': 'future-mode'},
        ];

        for (var index = 0; index < policies.length; index++) {
          final outcome = await listener.processIncomingMessage(
            _makeV2EncryptedChatMessage(
              from: senderPeerId,
              id: 'private-auto-gate-$index',
            ).copyWith(
              predecryptedText: jsonEncode({
                'id': 'private-auto-gate-$index',
                'text': '',
                'senderPeerId': senderPeerId,
                'senderUsername': 'Alice',
                'timestamp': '2026-07-11T09:00:0$index.000Z',
                'media': _testMediaJson,
                'privateMedia': policies[index],
              }),
            ),
          );
          expect(outcome.state, ChatMessageProcessState.stored);
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(emitted, hasLength(2));
        expect(allowing.requests, isEmpty);
        expect(bridge.downloadCallCount, 0);
        expect(mediaRepo.downloadStatusUpdates, isEmpty);

        listener.dispose();
      },
    );

    test(
      'auto download policy gates direct attachments before transfer',
      () async {
        final senderPeerId = 'sender-peer-policy-gate';
        contactRepo.seedContact(_makeContact(senderPeerId));

        // Denied: the policy is consulted with the full direct context, no
        // transfer happens, and the persisted row stays pending (still
        // reachable through the explicit retry affordance).
        final denying = RecordingMediaAutoDownloadDecider(allow: false);
        final deniedListener = createListener(decider: denying);
        deniedListener.start();
        final emitted = <ConversationMessage>[];
        final sub = deniedListener.incomingMessageStream.listen(emitted.add);

        chatStreamController.add(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-policy-denied',
            media: _testMediaJson,
          ),
        );
        await _waitUntil(
          () => denying.requests.isNotEmpty && emitted.length >= 2,
        );

        expect(
          bridge.downloadCallCount,
          0,
          reason: 'a denied policy decision must run BEFORE any transfer',
        );
        expect(denying.requests, hasLength(1));
        final request = denying.requests.single;
        expect(request.conversationKind, MediaConversationKind.oneToOne);
        expect(request.storageOwner, MediaOwnerLane.direct);
        expect(request.mediaType, 'image');
        expect(request.downloadStatus, 'pending');
        expect(request.userInitiated, isFalse);
        expect(
          mediaRepo.downloadStatusUpdates,
          isEmpty,
          reason: 'a denied attachment must not change persisted state',
        );
        final persisted = await mediaRepo.getAttachmentsForMessage(
          'msg-policy-denied',
          owner: MediaOwnerLane.direct,
        );
        expect(persisted.single.downloadStatus, 'pending');
        expect(emitted.last.media, isNotNull);
        expect(emitted.last.media.single.downloadStatus, 'pending');

        await sub.cancel();
        deniedListener.dispose();

        // Allowed default: exactly one owner-aware download for the eligible
        // attachment, consulted once with the same direct context.
        final allowing = RecordingMediaAutoDownloadDecider();
        final allowedListener = createListener(decider: allowing);
        allowedListener.start();
        final allowedEmitted = <ConversationMessage>[];
        allowedListener.incomingMessageStream.listen(allowedEmitted.add);

        chatStreamController.add(
          _makeChatMessage(
            from: senderPeerId,
            id: 'msg-policy-allowed',
            media: _testMediaJson,
          ),
        );
        await _waitUntil(
          () =>
              allowing.requests.isNotEmpty &&
              bridge.downloadCallCount >= 1 &&
              allowedEmitted.isNotEmpty &&
              allowedEmitted.last.media.isNotEmpty &&
              allowedEmitted.last.media.every(
                (attachment) => attachment.downloadStatus == 'done',
              ),
        );

        expect(bridge.downloadCallCount, 1);
        expect(allowing.requests, hasLength(1));
        expect(
          allowing.requests.single.conversationKind,
          MediaConversationKind.oneToOne,
        );
        expect(allowing.requests.single.storageOwner, MediaOwnerLane.direct);
        expect(allowedEmitted.last.media.single.downloadStatus, 'done');

        allowedListener.dispose();
      },
    );
  });
}
