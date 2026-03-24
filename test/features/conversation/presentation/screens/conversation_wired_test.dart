import 'dart:io';
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_media_picker.dart';
import '../../domain/repositories/fake_media_attachment_repository.dart';

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;

  FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

class FakeContactRepository implements ContactRepository {
  @override
  Future<void> addContact(ContactModel contact) async {}

  @override
  Future<bool> contactExists(String peerId) async => false;

  @override
  Future<void> deleteContact(String peerId) async {}

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
  Future<List<ContactModel>> getActiveContacts() async => [];

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

class FakeMessageRepository
    implements MessageRepository, MessageRepositoryChangeSource {
  final Map<String, ConversationMessage> store = {};
  int getMessagesPageCalls = 0;
  final StreamController<ConversationMessage> _messageChangeController =
      StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges =>
      _messageChangeController.stream;

  @override
  Future<List<ConversationMessage>> getMessagesForContact(
    String contactPeerId,
  ) async {
    final messages =
        store.values.where((m) => m.contactPeerId == contactPeerId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    final messages = await getMessagesForContact(contactPeerId);
    return messages.isEmpty ? null : messages.last;
  }

  @override
  Future<ConversationMessage?> getMessage(String id) async => store[id];

  @override
  Future<bool> messageExists(String id) async => store.containsKey(id);

  @override
  Future<void> saveMessage(ConversationMessage message) async {
    store[message.id] = message;
    _messageChangeController.add(message);
  }

  @override
  Future<void> updateMessageStatus(String id, String status) async {
    final message = store[id];
    if (message == null) return;
    final updated = message.copyWith(status: status);
    store[id] = updated;
    _messageChangeController.add(updated);
  }

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    return store.values.where((m) => m.contactPeerId == contactPeerId).length;
  }

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
    getMessagesPageCalls++;
    var messages = store.values
        .where((m) => m.contactPeerId == contactPeerId)
        .toList();
    if (beforeTimestamp != null) {
      messages = messages
          .where((m) => m.timestamp.compareTo(beforeTimestamp) < 0)
          .toList();
    }
    messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final page = messages.take(limit).toList();
    return page.reversed.toList();
  }

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

class SlowInitialPageMessageRepository extends FakeMessageRepository {
  final Completer<void> firstPageGate = Completer<void>();

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    await firstPageGate.future;
    return super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
  }
}

class FakeP2PService implements P2PService {
  final bool localPeer;
  final bool localMediaResult;
  int sendLocalMediaCallCount = 0;

  FakeP2PService({this.localPeer = false, this.localMediaResult = false});

  @override
  NodeState get currentState => const NodeState(isStarted: true, peerId: 'me');

  @override
  void dispose() {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => localPeer;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    sendLocalMediaCallCount++;
    return localMediaResult;
  }

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      false;

  @override
  Future<void> warmBackground() async {}

  @override
  String? get lastRecoveryMethod => null;
}

class TrackingLocalMediaP2PService extends FakeP2PService {
  final List<String> callOrder;

  TrackingLocalMediaP2PService({
    required this.callOrder,
    super.localPeer,
    super.localMediaResult,
  });

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async {
    callOrder.add('sendLocalMedia');
    return super.sendLocalMedia(
      peerId: peerId,
      filePath: filePath,
      mime: mime,
      mediaId: mediaId,
      fromPeerId: fromPeerId,
      durationMs: durationMs,
      waveform: waveform,
      filename: filename,
    );
  }
}

void main() {
  ContactModel makeContact() {
    return ContactModel(
      peerId: '12D3KooWContactPeer123',
      publicKey: 'pub',
      rendezvous: '/dns4/relay/tcp/443/p2p/relay',
      username: 'Alice',
      signature: 'sig',
      scannedAt: '2026-02-11T10:00:00.000Z',
    );
  }

  IdentityModel makeIdentity() {
    return IdentityModel(
      peerId: '12D3KooWMyPeer123',
      publicKey: 'pub',
      privateKey: 'priv',
      mnemonic12:
          'one two three four five six seven eight nine ten eleven twelve',
      username: 'Me',
      createdAt: '2026-02-11T09:00:00.000Z',
      updatedAt: '2026-02-11T09:00:00.000Z',
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    required FakeIdentityRepository identityRepo,
    required FakeMessageRepository messageRepo,
    required ChatMessageListener chatListener,
    required SendChatMessageFn sendFn,
    P2PService? p2pService,
    Bridge? bridge,
    UploadMediaFn? uploadMediaFn,
    MediaAttachmentRepository? mediaAttachmentRepo,
    FakeAudioRecorderService? audioRecorderService,
    ImageProcessor? imageProcessor,
    MediaPicker? mediaPicker,
    String? initialText,
    List<File>? initialAttachments,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: makeContact(),
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatMessageListener: chatListener,
          p2pService: p2pService ?? FakeP2PService(),
          bridge: bridge,
          sendChatMessageFn: sendFn,
          uploadMediaFn: uploadMediaFn ?? uploadMedia,
          mediaAttachmentRepo: mediaAttachmentRepo,
          audioRecorderService: audioRecorderService,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
          initialText: initialText,
          initialAttachments: initialAttachments,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    int maxPumps = 20,
    Duration step = const Duration(milliseconds: 100),
  }) async {
    for (var i = 0; i < maxPumps; i++) {
      if (condition()) return;
      await tester.pump(step);
    }
    expect(condition(), isTrue);
  }

  group('ConversationWired optimistic send', () {
    testWidgets('prefills shared text into the composer', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        initialText: 'Shared hello',
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared hello');
    });

    testWidgets('shows both initialText and initialAttachments together', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'conversation_share_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        initialText: 'Shared hello',
        initialAttachments: [attachment],
      );

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared hello');
      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
    });

    testWidgets('shows loading shell until the initial page resolves', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = SlowInitialPageMessageRepository();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-load-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Loaded after delay',
          timestamp: '2026-02-11T10:05:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-11T10:05:00.000Z',
        ),
      );
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      expect(
        find.byKey(const ValueKey('conversation-loading-shell')),
        findsOneWidget,
      );
      expect(find.text('Loaded after delay'), findsNothing);

      messageRepo.firstPageGate.complete();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const ValueKey('conversation-loading-shell')),
        findsNothing,
      );
      expect(find.text('Loaded after delay'), findsOneWidget);
    });

    testWidgets('shows message immediately then transitions to delivered', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;
      String? sentTimestamp;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        sentMessageId = messageId;
        sentTimestamp = timestamp;
        await gate.future;

        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Hello optimistic');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Hello optimistic'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);
      expect(find.byIcon(Icons.done_all_rounded), findsNothing);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(sentMessageId, isNotNull);
      expect(sentTimestamp, isNotNull);
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
    });

    testWidgets('marks optimistic message as failed when send returns null', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        sentMessageId = messageId;
        await gate.future;
        return (SendChatMessageResult.nodeNotRunning, null);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Fail me');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Fail me'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(messageRepo.store[sentMessageId!]!.status, 'failed');
    });

    testWidgets('shows delivered status when inbox fallback returns success', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        sentMessageId = messageId;
        await gate.future;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Inbox delivered');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Inbox delivered'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
    });

    testWidgets('persists upload_pending attachments before upload starts', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final callOrder = <String>[];
      mediaAttachmentRepo.onSaveAttachment = (attachment) =>
          callOrder.add('save:${attachment.downloadStatus}');

      final tempDir = Directory.systemTemp.createTempSync(
        'conv_pending_upload_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/pending.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        mediaAttachmentRepo: mediaAttachmentRepo,
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
            }) async {
              callOrder.add('uploadMedia');
              return MediaAttachment(
                id: 'uploaded-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
            },
        initialAttachments: [attachment],
      );

      await tester.enterText(find.byType(TextField), 'Photo');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpUntil(tester, () => callOrder.contains('uploadMedia'));

      expect(
        callOrder,
        containsAllInOrder(['save:upload_pending', 'uploadMedia']),
      );
      final savedAttachment = mediaAttachmentRepo.allSavedAttachments
          .firstWhere(
            (attachment) => attachment.downloadStatus == 'upload_pending',
          );
      expect(savedAttachment.messageId, isNotEmpty);
      expect(savedAttachment.localPath, attachment.path);
    });

    testWidgets('shows two ticks when inbox delivered message is returned', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      final gate = Completer<void>();
      String? sentMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        sentMessageId = messageId;
        await gate.future;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          transport: 'inbox',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Inbox delivered');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(find.text('Inbox delivered'), findsOneWidget);
      expect(find.byIcon(Icons.done_rounded), findsOneWidget);

      gate.complete();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(messageRepo.store[sentMessageId!]!.status, 'delivered');
      expect(messageRepo.store[sentMessageId!]!.transport, 'inbox');
    });

    testWidgets(
      'guards against rapid duplicate sends and resets after success',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        final gate = Completer<void>();
        var sendCallCount = 0;

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          MediaAttachmentRepository? mediaAttachmentRepo,
        }) async {
          sendCallCount += 1;
          await gate.future;
          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text,
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          );
          await messageRepo.saveMessage(delivered);
          return (SendChatMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
        );

        await tester.enterText(find.byType(TextField), 'First send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.tap(
          find.byIcon(Icons.arrow_upward_rounded),
          warnIfMissed: false,
        );
        await tester.pump();

        expect(sendCallCount, 1);
        expect(find.text('First send'), findsOneWidget);

        gate.complete();
        await tester.pump(const Duration(milliseconds: 50));

        await tester.enterText(find.byType(TextField), 'Second send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(sendCallCount, 2);
      },
    );
  });

  group('ConversationWired media props', () {
    testWidgets('passes onAttach to screen — shows bottom sheet on tap', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      // Tap the attachment button
      await tester.tap(find.byIcon(Icons.add_rounded));
      // Use pump with duration instead of pumpAndSettle because
      // AmbientBackground has a repeating 8s animation that never settles.
      await tester.pump(const Duration(milliseconds: 500));

      // Bottom sheet should show Media Library, Take Photo, and Record Video options
      expect(find.text('Media Library'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Record Video'), findsOneWidget);
    });

    testWidgets('does not show AttachmentPreviewStrip initially', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets(
      'recording ticks update composer without rebuilding header or message list',
      (tester) async {
        final contact = makeContact();
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-rec-1',
            contactPeerId: contact.peerId,
            text: 'Seed message',
            senderPeerId: contact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          audioRecorderService: recorder,
        );

        final headerFinder = find.byType(ConversationHeader);
        final listFinder = find.byKey(const ValueKey('messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = messageRepo.getMessagesPageCalls;

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        recorder.emitDuration(const Duration(seconds: 1));
        recorder.emitAmplitude(0.3);
        await tester.pump();

        expect(find.text('Slide to cancel'), findsOneWidget);
        expect(find.text('0:01'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(messageRepo.getMessagesPageCalls, initialPageLoads);

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'video processing progress updates composer without rebuilding header or message list',
      (tester) async {
        final contact = makeContact();
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-video-1',
            contactPeerId: contact.peerId,
            text: 'Seed message',
            senderPeerId: contact.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaPicker = FakeMediaPicker()
          ..videoResult = XFile('/tmp/test-video.mp4');
        final resultCompleter = Completer<VideoProcessResult>();
        void Function(double progress)? progressCallback;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async => null,
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double)? onProgress,
              }) async {
                progressCallback = onProgress;
                return resultCompleter.future;
              },
        );

        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
        );

        final headerFinder = find.byType(ConversationHeader);
        final listFinder = find.byKey(const ValueKey('messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = messageRepo.getMessagesPageCalls;

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
            .onTap!();
        await tester.pump();

        expect(progressCallback, isNotNull);

        progressCallback!(25);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('25%'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(messageRepo.getMessagesPageCalls, initialPageLoads);

        progressCallback!(60);
        await tester.pump();
        expect(find.text('60%'), findsOneWidget);
        expect(messageRepo.getMessagesPageCalls, initialPageLoads);

        resultCompleter.complete(
          VideoProcessResult(path: '/tmp/processed-video.mp4'),
        );
        await tester.pump();
      },
    );

    testWidgets('video processing failure clears composer processing state', (
      tester,
    ) async {
      final contact = makeContact();
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-video-fail-1',
          contactPeerId: contact.peerId,
          text: 'Seed message',
          senderPeerId: contact.peerId,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'delivered',
          isIncoming: true,
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile('/tmp/test-video.mp4');
      final resultCompleter = Completer<VideoProcessResult>();
      void Function(double progress)? progressCallback;
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo:
            ({
              required path,
              required compress,
              void Function(double)? onProgress,
            }) async {
              progressCallback = onProgress;
              return resultCompleter.future;
            },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        imageProcessor: imageProcessor,
        mediaPicker: mediaPicker,
      );

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
          .onTap!();
      await tester.pump();

      progressCallback!(40);
      await tester.pump();
      expect(find.text('40%'), findsOneWidget);

      resultCompleter.completeError(StateError('video failed'));
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsNothing);
      expect(find.text('40%'), findsNothing);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Record Video'), findsOneWidget);
    });

    testWidgets('text-only send works without bridge or media repos', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      List<MediaAttachment>? passedMedia;
      MediaAttachmentRepository? passedMediaRepo;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        passedMedia = mediaAttachments;
        passedMediaRepo = mediaAttachmentRepo;

        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      await tester.enterText(find.byType(TextField), 'Text only');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 50));

      // No media should be passed for text-only sends
      expect(passedMedia, isNull);
      expect(passedMediaRepo, isNull);
      expect(find.text('Text only'), findsOneWidget);

      // Let scroll animation and post-frame callbacks complete
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('does not send when text is empty and no attachments', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );

      var sendCalled = false;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        sendCalled = true;
        return (SendChatMessageResult.success, null);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      // Tap send without entering text — the tap won't go through because
      // GestureDetector's onTap is null when no text and no attachments
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(sendCalled, false);
      expect(messageRepo.store, isEmpty);
    });

    testWidgets('swipe-to-reply sends quotedMessageId and clears preview', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final incoming = ConversationMessage(
        id: 'incoming-1',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Original incoming',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      String? capturedQuotedMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        capturedQuotedMessageId = quotedMessageId;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
          quotedMessageId: quotedMessageId,
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
      );

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-1');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Original incoming'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Quoted response');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 50));

      expect(capturedQuotedMessageId, 'incoming-1');
      expect(find.text('Replying to'), findsNothing);

      final saved = messageRepo.store.values
          .where((message) => message.text == 'Quoted response')
          .first;
      expect(saved.quotedMessageId, 'incoming-1');
    });

    testWidgets('swipe-to-reply voice send preserves quotedMessageId', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 1200
        ..fakeOutputPath = '/tmp/quoted_voice.m4a';
      final incoming = ConversationMessage(
        id: 'incoming-voice-1',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Quote this voice parent',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      String? capturedQuotedMessageId;

      Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required String targetPeerId,
        required String text,
        required String senderPeerId,
        required String senderUsername,
        String? messageId,
        String? timestamp,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        String? quotedMessageId,
        List<MediaAttachment>? mediaAttachments,
        MediaAttachmentRepository? mediaAttachmentRepo,
      }) async {
        capturedQuotedMessageId = quotedMessageId;
        final delivered = ConversationMessage(
          id: messageId!,
          contactPeerId: targetPeerId,
          senderPeerId: senderPeerId,
          text: text,
          timestamp: timestamp!,
          status: 'delivered',
          isIncoming: false,
          createdAt: timestamp,
          quotedMessageId: quotedMessageId,
          media: mediaAttachments ?? const [],
        );
        await messageRepo.saveMessage(delivered);
        return (SendChatMessageResult.success, delivered);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: sendFn,
        p2pService: FakeP2PService(localPeer: true, localMediaResult: true),
        audioRecorderService: recorder,
      );

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-voice-1');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      final recordingScreen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      final stopFuture = stopRecording();
      await tester.pump(const Duration(milliseconds: 300));
      await stopFuture;

      expect(capturedQuotedMessageId, 'incoming-voice-1');
      expect(find.text('Replying to'), findsNothing);

      final saved = messageRepo.store.values
          .where((message) => message.id != 'incoming-voice-1')
          .firstWhere((message) => !message.isIncoming);
      expect(saved.quotedMessageId, 'incoming-voice-1');
    });

    testWidgets(
      'voice send persists upload_pending attachment before local transfer',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final callOrder = <String>[];
        mediaAttachmentRepo.onSaveAttachment = (attachment) =>
            callOrder.add('save:${attachment.downloadStatus}');
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = '/tmp/quoted_voice_pending.m4a';
        final p2pService = TrackingLocalMediaP2PService(
          callOrder: callOrder,
          localPeer: true,
          localMediaResult: true,
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          p2pService: p2pService,
          audioRecorderService: recorder,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        final recordingScreen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        final stopFuture = stopRecording();
        await tester.pump(const Duration(milliseconds: 300));
        await stopFuture;
        await pumpUntil(tester, () => callOrder.contains('sendLocalMedia'));

        expect(
          callOrder,
          containsAllInOrder(['save:upload_pending', 'sendLocalMedia']),
        );
        final savedAttachment = mediaAttachmentRepo.allSavedAttachments
            .firstWhere(
              (attachment) => attachment.downloadStatus == 'upload_pending',
            );
        expect(savedAttachment.messageId, isNotEmpty);
        expect(savedAttachment.localPath, recorder.fakeOutputPath);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'repository change updates failed outgoing reply status in place',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final contact = makeContact();
        final parent = ConversationMessage(
          id: 'parent-retry',
          contactPeerId: contact.peerId,
          senderPeerId: contact.peerId,
          text: 'Original parent',
          timestamp: '2026-02-09T15:29:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:29:01.000Z',
        );
        final failedReply = ConversationMessage(
          id: 'failed-retry',
          contactPeerId: contact.peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Retry me',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:00.000Z',
          quotedMessageId: 'parent-retry',
        );
        await messageRepo.saveMessage(parent);
        await messageRepo.saveMessage(failedReply);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);

        await messageRepo.saveMessage(
          failedReply.copyWith(status: 'delivered'),
        );
        await tester.pump(const Duration(milliseconds: 500));

        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      },
    );

    testWidgets('upload failure restores quote draft and attachments', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final incoming = ConversationMessage(
        id: 'incoming-upload',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeContact().peerId,
        text: 'Upload parent',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(incoming);

      final tempDir = Directory.systemTemp.createTempSync('conv_retry_upload_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.jpg')
        ..writeAsStringSync('image');

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        uploadMediaFn:
            ({
              required bridge,
              required localFilePath,
              required mime,
              required recipientPeerId,
              mediaFileManager,
              blobId,
              width,
              height,
              durationMs,
              waveform,
              allowedPeers,
            }) async => null,
        initialAttachments: [attachment],
      );

      final screen = tester.widget<ConversationScreen>(
        find.byType(ConversationScreen),
      );
      screen.onQuoteReply!.call('incoming-upload');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry upload');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Upload parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry upload',
      );
      expect(find.text('Failed to upload media. Try again.'), findsOneWidget);
    });

    testWidgets(
      'send failure after upload restores quote draft and attachments',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final incoming = ConversationMessage(
          id: 'incoming-send-fail',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Send parent',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(incoming);

        final tempDir = Directory.systemTemp.createTempSync('conv_retry_send_');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/retry.jpg')
          ..writeAsStringSync('image');

        Future<(SendChatMessageResult, ConversationMessage?)> sendFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String text,
          required String senderPeerId,
          required String senderUsername,
          String? messageId,
          String? timestamp,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          String? quotedMessageId,
          List<MediaAttachment>? mediaAttachments,
          MediaAttachmentRepository? mediaAttachmentRepo,
        }) async => (SendChatMessageResult.sendFailed, null);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
          bridge: FakeBridge(),
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                blobId,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
              }) async => MediaAttachment(
                id: 'uploaded-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
          initialAttachments: [attachment],
        );

        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onQuoteReply!.call('incoming-send-fail');
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'Retry send');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Send parent'), findsWidgets);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Retry send',
        );
        expect(
          find.text('Failed to send message. Message saved.'),
          findsOneWidget,
        );
      },
    );
  });
}

/// Convenience send function that returns success instantly.
Future<(SendChatMessageResult, ConversationMessage?)> _instantSuccessSendFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  final delivered = ConversationMessage(
    id: messageId ?? 'msg-default',
    contactPeerId: targetPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: timestamp ?? DateTime.now().toUtc().toIso8601String(),
    status: 'delivered',
    isIncoming: false,
    createdAt: timestamp ?? DateTime.now().toUtc().toIso8601String(),
  );
  await messageRepo.saveMessage(delivered);
  return (SendChatMessageResult.success, delivered);
}
