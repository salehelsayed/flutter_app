import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';

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
  Future<bool> messageExists(String id) async =>
      existingIds.contains(id) || saved.any((m) => m.id == id);

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
      String contactPeerId) async =>
      [];

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
      String contactPeerId) async =>
      null;

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
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async =>
      [];

  @override
  Future<List<ConversationMessage>> getFailedOutgoingMessages() async => [];
}

class _FakeMediaAttachmentRepo implements MediaAttachmentRepository {
  final Map<String, List<MediaAttachment>> _store = {};
  final List<(String, String)> downloadStatusUpdates = [];
  final List<(String, String)> localPathUpdates = [];

  void seedAttachments(String messageId, List<MediaAttachment> attachments) {
    _store[messageId] = attachments;
  }

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    final list = _store.putIfAbsent(attachment.messageId, () => []);
    list.add(attachment);
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
      String messageId) async =>
      _store[messageId] ?? [];

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
      List<String> messageIds) async {
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
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];
}

class _FakeBridge implements Bridge {
  Map<String, dynamic> downloadResponse = {'ok': true};
  int downloadCallCount = 0;

  @override
  Future<String> send(String message) async {
    downloadCallCount++;
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
}

class _FakeMediaFileManager extends MediaFileManager {
  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final ext = mime.split('/').last;
    return '/tmp/test_media/$contactPeerId/$blobId.$ext';
  }

  @override
  Future<void> deleteMediaForContact(String contactPeerId) async {}

  @override
  Future<void> deleteFile(String localPath) async {}
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
}

// -- Helpers --

ContactModel _makeContact(String peerId, {bool isBlocked = false, bool isArchived = false}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Alice',
    signature: 'sig-$peerId',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    isBlocked: isBlocked,
    isArchived: isArchived,
  );
}

ChatMessage _makeChatMessage({
  required String from,
  String text = 'Hello',
  String id = 'msg-test-001',
  List<Map<String, dynamic>>? media,
}) {
  final payload = <String, dynamic>{
    'id': id,
    'text': text,
    'senderPeerId': from,
    'senderUsername': 'Alice',
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
  );
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
      );
    }

    test('transport from ChatMessage flows through to ConversationMessage',
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
    });

    test('auto-downloads pending attachments and re-emits message with media', () async {
      final senderPeerId = 'sender-peer-001';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // No need to pre-seed — handleIncomingChatMessage persists media from wire JSON
      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        media: _testMediaJson,
      ));

      // Wait for message processing + auto-download
      await Future.delayed(const Duration(milliseconds: 200));

      // Should get 2 emissions: initial (no media) + re-emit (with media)
      expect(emitted.length, 2);
      expect(emitted[0].media, isEmpty); // first emission has no hydrated media
      expect(emitted[1].media, hasLength(1)); // re-emission has downloaded media
      expect(emitted[1].media[0].downloadStatus, 'done');
      expect(emitted[1].media[0].localPath, isNotNull);

      listener.dispose();
    });

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

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-002',
      ));

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

    test('marks attachment as failed when download fails', () async {
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

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-003',
        media: _testMediaJson,
      ));

      await Future.delayed(const Duration(milliseconds: 200));

      expect(emitted.length, 2);
      // Re-emitted message should have failed status
      expect(emitted[1].media[0].downloadStatus, 'failed');

      listener.dispose();
    });

    test('handles bridge exception during download gracefully', () async {
      final senderPeerId = 'sender-peer-004';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // handleIncomingChatMessage persists media from wire JSON
      final listener = createListener(overrideBridge: _ThrowingBridge());
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-004',
        media: _testMediaJson,
      ));

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

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-005',
      ));

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

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-006',
      ));

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

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-007',
        media: [
          {'id': 'blob-a', 'mime': 'image/jpeg', 'size': 100000, 'mediaType': 'image'},
          {'id': 'blob-b', 'mime': 'image/png', 'size': 200000, 'mediaType': 'image'},
        ],
      ));

      await Future.delayed(const Duration(milliseconds: 300));

      expect(emitted.length, 2);
      expect(emitted[1].media, hasLength(2));
      expect(emitted[1].media[0].downloadStatus, 'done');
      expect(emitted[1].media[1].downloadStatus, 'done');

      // Bridge called twice (once per attachment)
      expect(bridge.downloadCallCount, 2);

      listener.dispose();
    });

    test('text message appears instantly before auto-download completes', () async {
      final senderPeerId = 'sender-peer-008';
      contactRepo.seedContact(_makeContact(senderPeerId));

      // handleIncomingChatMessage persists media from wire JSON
      final listener = createListener();
      listener.start();

      final emitted = <ConversationMessage>[];
      listener.incomingMessageStream.listen(emitted.add);

      chatStreamController.add(_makeChatMessage(
        from: senderPeerId,
        id: 'msg-test-008',
        text: 'Check out this photo!',
        media: _testMediaJson,
      ));

      // First emission should come very quickly (before download)
      await Future.delayed(const Duration(milliseconds: 50));
      expect(emitted.length, greaterThanOrEqualTo(1));
      expect(emitted[0].text, 'Check out this photo!');
      expect(emitted[0].id, 'msg-test-008');

      // Wait for download to complete
      await Future.delayed(const Duration(milliseconds: 250));
      expect(emitted.length, 2);

      listener.dispose();
    });
  });
}
