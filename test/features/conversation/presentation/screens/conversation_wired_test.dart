import 'dart:io';
import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/text_sanitizer.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/delete_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/recording_overlay.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/bridge/fake_bridge.dart';
import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/fake_media_picker.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../domain/repositories/fake_media_attachment_repository.dart';

const _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

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
  Future<int> deleteMessage(String id) async {
    final removed = store.remove(id);
    return removed == null ? 0 : 1;
  }

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

class InboxRetryP2PService extends FakeP2PService {
  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => true;
}

void main() {
  late FakeUploadWakeLockDriver wakeLockDriver;

  setUp(() {
    wakeLockDriver = FakeUploadWakeLockDriver();
    UploadWakeLockController.debugReset(driver: wakeLockDriver);
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

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
    EditChatMessageFn? editFn,
    DeleteMessageForMeFn? deleteForMeFn,
    DeleteMessageForEveryoneFn? deleteForEveryoneFn,
    P2PService? p2pService,
    Bridge? bridge,
    UploadMediaFn? uploadMediaFn,
    SendVoiceMessageFn? sendVoiceMessageFn,
    MediaAttachmentRepository? mediaAttachmentRepo,
    ContactRepository? contactRepo,
    MediaFileManager? mediaFileManager,
    FakeAudioRecorderService? audioRecorderService,
    ImageProcessor? imageProcessor,
    MediaPicker? mediaPicker,
    String? initialText,
    List<File>? initialAttachments,
    List<PendingComposerMedia>? initialPendingMedia,
    ImageQualityPreference qualityPreference =
        ImageQualityPreference.compressed,
    ImageQualityPreference videoQualityPreference =
        ImageQualityPreference.compressed,
    int maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
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
          editChatMessageFn: editFn ?? editChatMessage,
          deleteMessageForMeFn: deleteForMeFn ?? deleteMessageForMe,
          deleteMessageForEveryoneFn:
              deleteForEveryoneFn ?? deleteMessageForEveryone,
          uploadMediaFn: uploadMediaFn ?? uploadMedia,
          sendVoiceMessageFn: sendVoiceMessageFn ?? sendVoiceMessage,
          contactRepo: contactRepo,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: audioRecorderService,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
          qualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
          initialText: initialText,
          initialAttachments: initialAttachments,
          initialPendingMedia: initialPendingMedia,
          maxAttachmentBudgetBytes: maxAttachmentBudgetBytes,
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
      if (condition()) {
        await tester.pump(const Duration(milliseconds: 500));
        return;
      }
      await tester.pump(step);
    }
    await tester.pump(const Duration(milliseconds: 500));
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

    testWidgets(
      'sanitized optimistic text stays consistent before and after persistence',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final sendGate = Completer<void>();
        String? capturedText;
        String? capturedMessageId;

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
          capturedText = text;
          capturedMessageId = messageId;
          await sendGate.future;

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

        const rawText = 'مرحبا\u202E Hello\u200E 123';
        final sanitizedText = sanitizeMessageText(rawText);

        await tester.enterText(find.byType(TextField), rawText);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(capturedText, sanitizedText);
        expect(find.text(rawText), findsNothing);
        expect(find.text(sanitizedText), findsOneWidget);
        expect(messageRepo.store, hasLength(1));
        expect(messageRepo.store.values.single.text, sanitizedText);
        expect(messageRepo.store.values.single.status, 'sending');

        sendGate.complete();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedMessageId, isNotNull);
        expect(find.text(rawText), findsNothing);
        expect(find.text(sanitizedText), findsOneWidget);
        expect(messageRepo.store, hasLength(1));
        expect(messageRepo.store.values.single.text, sanitizedText);
        expect(messageRepo.store.values.single.status, 'delivered');
      },
    );

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

    testWidgets(
      'hydrated initialPendingMedia uses budget bytes instead of file size',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conversation_hydrated_budget_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final smallFile = File('${tempDir.path}/hydrated.jpg')
          ..writeAsStringSync('12');

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          initialPendingMedia: [
            PendingComposerMedia(file: smallFile, budgetBytes: 12),
          ],
          maxAttachmentBudgetBytes: 10,
        );

        expect(find.text('Media Too Large'), findsOneWidget);
      },
    );

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

    testWidgets(
      'relay media send reuses optimistic attachment id and clears upload_pending placeholder',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_stable_media_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/stable.jpg')
          ..writeAsStringSync('image');

        String? uploadedBlobId;
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
          if (mediaAttachments != null && mediaAttachmentRepo != null) {
            for (final attachment in mediaAttachments) {
              await mediaAttachmentRepo.saveAttachment(
                attachment.copyWith(messageId: messageId!),
              );
            }
          }

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
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
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
                uploadedBlobId = blobId;
                return MediaAttachment(
                  id: blobId ?? 'fallback-upload-id',
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
        await pumpUntil(
          tester,
          () => uploadedBlobId != null && sentMessageId != null,
        );

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessageId!,
        );
        expect(uploadedBlobId, isNotNull);
        expect(attachments.length, 1);
        expect(attachments.single.id, uploadedBlobId);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(
          pending.where((attachment) => attachment.messageId == sentMessageId!),
          isEmpty,
        );

        await tester.pump(const Duration(milliseconds: 500));
      },
    );

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
      'gallery multi-video batches keep one processing tile with honest batch context',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_gallery_batch_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final firstVideo = File('${tempDir.path}/video-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final stillImage = File('${tempDir.path}/image-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final secondVideo = File('${tempDir.path}/video-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedFirstVideo = File('${tempDir.path}/processed-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedImage = File('${tempDir.path}/processed-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedSecondVideo = File('${tempDir.path}/processed-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [
            XFile(firstVideo.path),
            XFile(stillImage.path),
            XFile(secondVideo.path),
          ];
        final videoResults = [
          Completer<VideoProcessResult>(),
          Completer<VideoProcessResult>(),
        ];
        final imageResult = Completer<XFile?>();
        var imageCompressionStarted = false;
        final progressCallbacks = <void Function(double)?>[];
        var videoCallCount = 0;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                if (path == stillImage.path) {
                  imageCompressionStarted = true;
                  return imageResult.future;
                }
                return null;
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async {
                progressCallbacks.add(onProgress);
                final result = videoResults[videoCallCount];
                videoCallCount++;
                return result.future;
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
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () => progressCallbacks.length == 1);

        progressCallbacks.single!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        videoResults[0].complete(
          VideoProcessResult(path: processedFirstVideo.path),
        );
        await pumpUntil(tester, () => imageCompressionStarted);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);

        imageResult.complete(XFile(processedImage.path));
        await pumpUntil(tester, () => progressCallbacks.length == 2);

        progressCallbacks.last!(60);
        await tester.pump();

        expect(find.text('Processing (2/2)'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);

        videoResults[1].complete(
          VideoProcessResult(path: processedSecondVideo.path),
        );
        await tester.pump();
      },
    );

    testWidgets('recorded single video keeps single-item processing copy', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final tempDir = Directory.systemTemp.createTempSync('conv_camera_video_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final cameraVideo = File('${tempDir.path}/camera-video.mp4')
        ..writeAsBytesSync(_tinyPngBytes);
      final processedVideo = File('${tempDir.path}/camera-video-out.mp4')
        ..writeAsBytesSync(_tinyPngBytes);

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile(cameraVideo.path);
      final result = Completer<VideoProcessResult>();
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
              void Function(double progress)? onProgress,
            }) async {
              progressCallback = onProgress;
              return result.future;
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

      expect(progressCallback, isNotNull);

      progressCallback!(40);
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Processing (1/1)'), findsNothing);
      expect(find.text('40%'), findsOneWidget);

      result.complete(VideoProcessResult(path: processedVideo.path));
      await tester.pump();
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

        expect(find.byType(RecordingOverlay), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0:01'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(messageRepo.getMessagesPageCalls, initialPageLoads);

        await gesture.up();
        await tester.pump();
      },
    );

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

    testWidgets(
      'long-press reply on an outgoing message requests focus and sends quotedMessageId',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'outgoing-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Quote this sent message',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

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

        await tester.longPress(find.text('Quote this sent message'));
        await tester.pump(const Duration(milliseconds: 250));

        expect(
          find.byKey(MessageContextOverlay.selectedMessageKey),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(MessageContextOverlay.selectedMessageKey),
            matching: find.text('Quote this sent message'),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
        await tester.pump();

        expect(find.text('Replying to'), findsOneWidget);
        expect(find.text('Quote this sent message'), findsWidgets);
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.enterText(
          find.byType(TextField),
          'Quoted after long press',
        );
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 50));

        expect(capturedQuotedMessageId, 'outgoing-1');
        expect(find.text('Replying to'), findsNothing);

        final saved = messageRepo.store.values
            .where((message) => message.text == 'Quoted after long press')
            .first;
        expect(saved.quotedMessageId, 'outgoing-1');
      },
    );

    testWidgets(
      'edit action prefills the composer and cancel exits edit mode',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'editable-1',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Fix this typo',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(outgoing);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await tester.longPress(find.text('Fix this typo'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        expect(
          find.byKey(ConversationScreen.editModeBannerKey),
          findsOneWidget,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fix this typo',
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).focusNode?.hasFocus,
          isTrue,
        );

        await tester.tap(find.byKey(ConversationScreen.cancelEditKey));
        await tester.pump();

        expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '',
        );
      },
    );

    testWidgets('identical-text edit submit is a no-op', (tester) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final outgoing = ConversationMessage(
        id: 'editable-noop',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Same text',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(outgoing);

      var editCalls = 0;

      Future<(SendChatMessageResult, ConversationMessage?)> editFn({
        required P2PService p2pService,
        required MessageRepository messageRepo,
        required ConversationMessage originalMessage,
        required String updatedText,
        required String senderUsername,
        Bridge? bridge,
        String? recipientMlKemPublicKey,
        MediaAttachmentRepository? mediaAttachmentRepo,
        bool emitTimingEvent = true,
      }) async {
        editCalls++;
        return (SendChatMessageResult.success, originalMessage);
      }

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        editFn: editFn,
      );

      await tester.longPress(find.text('Same text'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump();

      expect(editCalls, 0);
      expect(messageRepo.store['editable-noop']?.editedAt, isNull);
      expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
    });

    testWidgets(
      'changed edit submit updates the same row through the shared edit path',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final outgoing = ConversationMessage(
          id: 'editable-submit',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Before edit',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
          quotedMessageId: 'quoted-parent',
        );
        await messageRepo.saveMessage(outgoing);

        String? capturedOriginalId;
        String? capturedUpdatedText;

        Future<(SendChatMessageResult, ConversationMessage?)> editFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required ConversationMessage originalMessage,
          required String updatedText,
          required String senderUsername,
          Bridge? bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          bool emitTimingEvent = true,
        }) async {
          capturedOriginalId = originalMessage.id;
          capturedUpdatedText = updatedText;
          final edited = originalMessage.copyWith(
            text: updatedText,
            editedAt: '2026-02-09T16:00:00.000Z',
          );
          await messageRepo.saveMessage(edited);
          return (SendChatMessageResult.success, edited);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          editFn: editFn,
        );

        await tester.longPress(find.text('Before edit'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.editActionKey));
        await tester.pump();

        await tester.enterText(find.byType(TextField), 'After edit');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump();

        expect(capturedOriginalId, 'editable-submit');
        expect(capturedUpdatedText, 'After edit');
        expect(messageRepo.store['editable-submit']?.text, 'After edit');
        expect(
          messageRepo.store['editable-submit']?.quotedMessageId,
          'quoted-parent',
        );
        expect(
          messageRepo.store['editable-submit']?.editedAt,
          '2026-02-09T16:00:00.000Z',
        );
        expect(find.byKey(ConversationScreen.editModeBannerKey), findsNothing);
      },
    );

    testWidgets(
      'delivered outgoing rows offer delete-for-me and delete-for-everyone',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        await messageRepo.saveMessage(
          ConversationMessage(
            id: 'delete-options-outgoing',
            contactPeerId: makeContact().peerId,
            senderPeerId: makeIdentity().peerId,
            text: 'Delete options',
            timestamp: '2026-02-09T15:30:00.000Z',
            status: 'delivered',
            isIncoming: false,
            createdAt: '2026-02-09T15:30:01.000Z',
          ),
        );

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await tester.longPress(find.text('Delete options'));
        await tester.pump(const Duration(milliseconds: 250));
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpUntil(
          tester,
          () => find
              .byKey(ConversationWired.deleteSheetKey)
              .evaluate()
              .isNotEmpty,
        );

        expect(find.byKey(ConversationWired.deleteSheetKey), findsOneWidget);
        expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
        expect(
          find.byKey(ConversationWired.deleteForEveryoneKey),
          findsOneWidget,
        );
        expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
      },
    );

    testWidgets('incoming rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'incoming-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Incoming delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Incoming delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteSheetKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
      expect(find.byKey(ConversationWired.deleteCancelKey), findsOneWidget);
    });

    testWidgets('failed outgoing rows only offer delete-for-me and cancel', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'failed-delete-options',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeIdentity().peerId,
          text: 'Failed delete options',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'failed',
          isIncoming: false,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Failed delete options'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );

      expect(find.byKey(ConversationWired.deleteForMeKey), findsOneWidget);
      expect(find.byKey(ConversationWired.deleteForEveryoneKey), findsNothing);
    });

    testWidgets('delete-for-me removes the row from Orbit locally', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'delete-for-me-row',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Delete for me only',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        ),
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await tester.longPress(find.text('Delete for me only'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
      await pumpUntil(
        tester,
        () =>
            find.byKey(ConversationWired.deleteSheetKey).evaluate().isNotEmpty,
      );
      tester
          .widget<InkWell>(
            find.descendant(
              of: find.byKey(ConversationWired.deleteForMeKey),
              matching: find.byType(InkWell),
            ),
          )
          .onTap!();
      await pumpUntil(
        tester,
        () => find.text('Delete for me only').evaluate().isEmpty,
      );

      expect(find.text('Delete for me only'), findsNothing);
      expect(messageRepo.store.containsKey('delete-for-me-row'), isFalse);
      expect(find.text('Connected!'), findsWidgets);
    });

    testWidgets('hidden outgoing tombstones are removed from the Orbit list', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final original = ConversationMessage(
        id: 'delete-for-everyone-row',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Delete everywhere',
        timestamp: '2026-02-09T15:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-02-09T15:30:01.000Z',
      );
      await messageRepo.saveMessage(original);

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
      );

      await messageRepo.saveMessage(
        original.copyWith(
          text: '',
          deletedAt: '2026-03-31T11:00:00.000Z',
          deletedByPeerId: original.senderPeerId,
          hiddenAt: '2026-03-31T11:00:00.000Z',
          media: const [],
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Delete everywhere').evaluate().isEmpty,
      );

      expect(find.text('Delete everywhere'), findsNothing);
      expect(messageRepo.store['delete-for-everyone-row']?.isHidden, isTrue);
    });

    testWidgets(
      'incoming deleted tombstones refresh into the Orbit placeholder',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final original = ConversationMessage(
          id: 'incoming-tombstone',
          contactPeerId: makeContact().peerId,
          senderPeerId: makeContact().peerId,
          text: 'Original incoming text',
          timestamp: '2026-02-09T15:30:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-02-09T15:30:01.000Z',
        );
        await messageRepo.saveMessage(original);

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
        );

        await messageRepo.saveMessage(
          original.copyWith(
            text: '',
            deletedAt: '2026-03-31T11:05:00.000Z',
            deletedByPeerId: makeContact().peerId,
            media: const [],
          ),
        );
        await pumpUntil(
          tester,
          () => find.text('This message was deleted').evaluate().isNotEmpty,
        );

        expect(find.text('Original incoming text'), findsNothing);
        expect(find.text('This message was deleted'), findsOneWidget);
      },
    );

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
      'voice local send reuses optimistic attachment id and clears upload_pending placeholder',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = '/tmp/voice_local_stable.m4a';
        final p2pService = TrackingLocalMediaP2PService(
          callOrder: <String>[],
          localPeer: true,
          localMediaResult: true,
        );

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
          if (mediaAttachments != null && mediaAttachmentRepo != null) {
            for (final attachment in mediaAttachments) {
              await mediaAttachmentRepo.saveAttachment(
                attachment.copyWith(messageId: messageId!),
              );
            }
          }

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
          return (
            SendChatMessageResult.success,
            delivered.copyWith(media: mediaAttachments ?? const []),
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
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
        await stopRecording();
        await tester.pump(const Duration(milliseconds: 300));

        final sentMessage = messageRepo.store.values.firstWhere(
          (message) => !message.isIncoming,
        );
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
        );
        expect(attachments.length, 1);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(
          pending.where((attachment) => attachment.messageId == sentMessage.id),
          isEmpty,
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'voice relay fallback passes optimistic attachment id to sendVoiceMessage',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = '/tmp/voice_relay_stable.m4a';
        String? capturedBlobId;

        Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceFn({
          required P2PService p2pService,
          required MessageRepository messageRepo,
          required String targetPeerId,
          required String senderPeerId,
          required String senderUsername,
          required AudioRecording recording,
          required Bridge bridge,
          String? recipientMlKemPublicKey,
          MediaAttachmentRepository? mediaAttachmentRepo,
          MediaFileManager? mediaFileManager,
          String? text,
          String? quotedMessageId,
          List<double>? waveform,
          String? messageId,
          String? timestamp,
          String? blobId,
        }) async {
          capturedBlobId = blobId;
          if (mediaAttachmentRepo != null && messageId != null) {
            await mediaAttachmentRepo.saveAttachment(
              MediaAttachment(
                id: blobId ?? 'voice-fallback-upload-id',
                messageId: messageId,
                mime: recording.mime,
                size: recording.sizeBytes,
                mediaType: 'audio',
                durationMs: recording.durationMs,
                localPath: recording.filePath,
                downloadStatus: 'done',
                createdAt:
                    timestamp ?? DateTime.now().toUtc().toIso8601String(),
                waveform: waveform,
              ),
            );
          }

          final delivered = ConversationMessage(
            id: messageId!,
            contactPeerId: targetPeerId,
            senderPeerId: senderPeerId,
            text: text ?? '',
            timestamp: timestamp!,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
            quotedMessageId: quotedMessageId,
          );
          await messageRepo.saveMessage(delivered);
          return (SendVoiceMessageResult.success, delivered);
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: _instantSuccessSendFn,
          bridge: FakeBridge(),
          audioRecorderService: recorder,
          mediaAttachmentRepo: mediaAttachmentRepo,
          sendVoiceMessageFn: sendVoiceFn,
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
        await stopRecording();
        await tester.pump(const Duration(milliseconds: 300));

        final sentMessage = messageRepo.store.values.firstWhere(
          (message) => !message.isIncoming,
        );
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sentMessage.id,
        );
        expect(capturedBlobId, isNotNull);
        expect(attachments.length, 1);
        expect(attachments.single.id, capturedBlobId);
        expect(attachments.single.downloadStatus, 'done');
        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(
          pending.where((attachment) => attachment.messageId == sentMessage.id),
          isEmpty,
        );
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

    testWidgets('shows relay upload progress and blocks leaving mid-upload', (
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
        'conv_upload_progress_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/progress.jpg')
        ..writeAsStringSync('0123456789');

      final uploadGate = Completer<void>();
      final uploadStarted = Completer<void>();
      String? activeBlobId;

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
            }) async {
              activeBlobId = blobId;
              uploadStarted.complete();
              await uploadGate.future;
              return MediaAttachment(
                id: blobId ?? 'uploaded-progress-1',
                messageId: '',
                mime: mime,
                size: File(localFilePath).lengthSync(),
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                createdAt: DateTime.now().toUtc().toIso8601String(),
              );
            },
        initialAttachments: [attachment],
      );

      await tester.enterText(find.byType(TextField), 'Uploading');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await uploadStarted.future;
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.enableCalls, 1);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      emitMediaUploadProgressEvent({
        'id': activeBlobId,
        'sentBytes': 5,
        'totalBytes': 10,
        'toPeerId': makeContact().peerId,
      });
      await tester.pump();

      expect(
        find.text(
          '${formatPendingComposerBudgetBytes(5)} / '
          '${formatPendingComposerBudgetBytes(10)}',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Keep the app open until the upload completes'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();

      expect(find.text('Leave conversation?'), findsOneWidget);
      expect(
        find.text(
          'An upload is in progress. Leaving may interrupt it. Are you sure?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('upload-leave-stay')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.disableCalls, 0);

      uploadGate.complete();
      await pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('upload-progress-banner'))
                .evaluate()
                .isEmpty &&
            wakeLockDriver.disableCalls == 1,
      );

      expect(UploadWakeLockController.debugActiveHolds, 0);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets(
      'cancel on the active upload banner restores video composer state and suppresses the final send',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_cancel_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/cancel.mp4')
          ..writeAsStringSync('0123456789');

        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        var sendCalls = 0;

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
          sendCalls++;
          return _instantSuccessSendFn(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: targetPeerId,
            text: text,
            senderPeerId: senderPeerId,
            senderUsername: senderUsername,
            messageId: messageId,
            timestamp: timestamp,
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            quotedMessageId: quotedMessageId,
            mediaAttachments: mediaAttachments,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
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
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-cancel-1',
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Cancel upload');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await uploadStarted.future;
        await tester.pump();

        expect(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
          findsOneWidget,
        );

        await tester.tap(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
        );
        await tester.pump();

        expect(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
          findsNothing,
        );

        uploadGate.complete();
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.text('Failed to upload media. Try again.'), findsNothing);
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel upload',
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(messageRepo.store.values.single.status, 'failed');
        final failedMessageId = messageRepo.store.values.single.id;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(failedMessageId);
        expect(storedAttachments, hasLength(1));
        expect(storedAttachments.single.downloadStatus, 'upload_failed');
        expect(sendCalls, 0);
        expect(UploadWakeLockController.debugActiveHolds, 0);
      },
    );

    testWidgets(
      'cancel requested before an upload failure resolves still shows the cancel outcome',
      (tester) async {
        final identityRepo = FakeIdentityRepository(makeIdentity());
        final messageRepo = FakeMessageRepository();
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: messageRepo,
          contactRepo: FakeContactRepository(),
        );
        final mediaAttachmentRepo = FakeMediaAttachmentRepository();
        final tempDir = Directory.systemTemp.createTempSync(
          'conv_cancel_upload_failure_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/cancel-failure.mp4')
          ..writeAsStringSync('0123456789');

        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        var sendCalls = 0;

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
          sendCalls++;
          return _instantSuccessSendFn(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: targetPeerId,
            text: text,
            senderPeerId: senderPeerId,
            senderUsername: senderUsername,
            messageId: messageId,
            timestamp: timestamp,
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            quotedMessageId: quotedMessageId,
            mediaAttachments: mediaAttachments,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );
        }

        await pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          chatListener: chatListener,
          sendFn: sendFn,
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
                uploadStarted.complete();
                await uploadGate.future;
                return null;
              },
          initialAttachments: [attachment],
        );

        await tester.enterText(find.byType(TextField), 'Cancel failed upload');
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await uploadStarted.future;
        await tester.pump();

        await tester.tap(
          find.byKey(const ValueKey('upload-progress-cancel-button')),
        );
        await tester.pump();

        uploadGate.complete();
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.text('Failed to upload media. Try again.'), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel failed upload',
        );
        expect(sendCalls, 0);
        expect(messageRepo.store.values.single.status, 'failed');
        final failedMessageId = messageRepo.store.values.single.id;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(failedMessageId);
        expect(storedAttachments, hasLength(1));
        expect(storedAttachments.single.downloadStatus, 'upload_failed');
      },
    );

    testWidgets('retry control re-sends a failed outgoing media row', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final failedMessage = ConversationMessage(
        id: 'failed-media-msg',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: 'Retry me',
        timestamp: '2026-02-11T10:05:00.000Z',
        status: 'failed',
        wireEnvelope: '{"ciphertext":"abc"}',
        isIncoming: false,
        createdAt: '2026-02-11T10:05:00.000Z',
        media: const [
          MediaAttachment(
            id: 'persisted-attachment',
            messageId: 'failed-media-msg',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: '/tmp/retry.jpg',
            downloadStatus: 'done',
            createdAt: '2026-02-11T10:05:00.000Z',
          ),
        ],
      );
      await messageRepo.saveMessage(failedMessage);
      mediaAttachmentRepo.seedAttachments(
        messageId: failedMessage.id,
        attachments: failedMessage.media,
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        bridge: FakeBridge(),
        contactRepo: FakeContactRepository(),
        mediaAttachmentRepo: mediaAttachmentRepo,
        p2pService: InboxRetryP2PService(),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(const ValueKey('failed-media-retry-failed-media-msg')),
      );
      await pumpUntil(
        tester,
        () => messageRepo.store['failed-media-msg']?.status == 'delivered',
      );

      expect(messageRepo.store['failed-media-msg']?.status, 'delivered');
      expect(find.byIcon(Icons.done_all_rounded), findsOneWidget);
      expect(find.text('Could not retry media message.'), findsNothing);
    });

    testWidgets('delete control removes a failed outgoing media row and files', (
      tester,
    ) async {
      final identityRepo = FakeIdentityRepository(makeIdentity());
      final messageRepo = FakeMessageRepository();
      final mediaAttachmentRepo = FakeMediaAttachmentRepository();
      final mediaFileManager = FakeMediaFileManager();
      final chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: FakeContactRepository(),
      );
      final failedMessage = ConversationMessage(
        id: 'failed-delete-msg',
        contactPeerId: makeContact().peerId,
        senderPeerId: makeIdentity().peerId,
        text: '',
        timestamp: '2026-02-11T10:05:00.000Z',
        status: 'failed',
        isIncoming: false,
        createdAt: '2026-02-11T10:05:00.000Z',
        media: const [
          MediaAttachment(
            id: 'pending-delete-attachment',
            messageId: 'failed-delete-msg',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/failed-delete-msg/pending-delete-attachment.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-02-11T10:05:00.000Z',
          ),
        ],
      );
      await messageRepo.saveMessage(failedMessage);
      mediaAttachmentRepo.seedAttachments(
        messageId: failedMessage.id,
        attachments: failedMessage.media,
      );

      await pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatListener: chatListener,
        sendFn: _instantSuccessSendFn,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(
        find.byKey(const ValueKey('failed-media-delete-failed-delete-msg')),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(messageRepo.store.containsKey(failedMessage.id), isFalse);
      expect(
        await mediaAttachmentRepo.getAttachmentsForMessage(failedMessage.id),
        isEmpty,
      );
      expect(
        mediaFileManager.deletedFilePaths,
        contains(
          '/tmp/test_docs/pending_uploads/failed-delete-msg/'
          'pending-delete-attachment.jpg',
        ),
      );
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
