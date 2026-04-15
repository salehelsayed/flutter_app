// test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart
//
// Phase 2 Unit 2C — Steps 3.3 + 3.4
// RED tests: verify that ConversationWired calls bg:begin before send/upload
// and bg:end afterwards. These tests are expected to FAIL (red) because
// the presentation layer does not yet call bg:begin/bg:end.

// ignore_for_file: unused_element_parameter

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../../shared/fakes/fake_upload_wake_lock_driver.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Bridge that records the order of every command it receives.
class _OrderRecordingBridge implements Bridge {
  final List<String> callLog = [];
  final List<String> operationLog;
  final String bgBeginResponse;
  final Set<String> throwOnCommands;
  final Map<String, String> responseOverrides;

  _OrderRecordingBridge({
    List<String>? operationLog,
    this.bgBeginResponse = '99',
    Set<String>? throwOnCommands,
    Map<String, String>? responseOverrides,
  }) : operationLog = operationLog ?? <String>[],
       throwOnCommands = throwOnCommands ?? <String>{},
       responseOverrides = responseOverrides ?? const <String, String>{};

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    operationLog.add('bridge:$cmd');
    if (throwOnCommands.contains(cmd)) {
      throw Exception('$cmd failed');
    }
    final overrideResponse = responseOverrides[cmd];
    if (overrideResponse != null) {
      return overrideResponse;
    }
    if (cmd == 'bg:begin') return bgBeginResponse;
    if (cmd == 'bg:end') return '';
    if (cmd == 'blob:keygen') {
      return jsonEncode({'ok': true, 'keyBase64': 'AAAA'});
    }
    if (cmd == 'blob:encrypt') {
      return jsonEncode({
        'ok': true,
        'encryptedPath': '/tmp/test.enc',
        'nonce': 'fake-nonce',
      });
    }
    if (cmd == 'media:upload') {
      return jsonEncode({
        'ok': true,
        'blobId': 'blob-1',
        'url': 'https://example.com/blob-1',
      });
    }
    if (cmd == 'message.encrypt') {
      return jsonEncode({
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': 'fake-ct',
        'nonce': 'fake-nonce',
      });
    }
    return jsonEncode({'ok': true});
  }

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(p2p.ConnectionState)? onPeerConnected;
  @override
  void Function(p2p.ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
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
}

class _FakeIdentityRepository implements IdentityRepository {
  final IdentityModel? identity;
  _FakeIdentityRepository(this.identity);

  @override
  Future<IdentityModel?> loadIdentity() async => identity;
  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _FakeMessageRepository
    implements MessageRepository, MessageRepositoryChangeSource {
  final _ctrl = StreamController<ConversationMessage>.broadcast();

  @override
  Stream<ConversationMessage> get messageChanges => _ctrl.stream;
  @override
  Future<void> saveMessage(ConversationMessage m) async {}
  @override
  Future<List<ConversationMessage>> getMessagesForContact(String pid) async =>
      [];
  @override
  Future<ConversationMessage?> getLatestMessageForContact(String pid) async =>
      null;
  @override
  Future<ConversationMessage?> getMessage(String id) async => null;
  @override
  Future<bool> messageExists(String id) async => false;
  @override
  Future<void> updateMessageStatus(String id, String status) async {}
  @override
  Future<int> getMessageCountForContact(String pid) async => 0;
  @override
  Future<int> markConversationAsRead(String pid) async => 0;
  @override
  Future<int> getUnreadCountForContact(String pid) async => 0;
  @override
  Future<int> getTotalUnreadCount() async => 0;
  @override
  Future<int> getTotalUnreadCountExcludingArchived() async => 0;
  @override
  Future<int> deleteMessagesForContact(String pid) async => 0;
  @override
  Future<int> deleteMessage(String id) async => 0;
  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String pid, {
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

class _FakeContactRepository implements ContactRepository {
  @override
  Future<void> addContact(ContactModel c) async {}
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

class _FakeP2PService implements P2PService {
  final bool localPeer;
  final bool localMediaResult;
  final bool throwOnSendLocalMedia;
  final bool sendMessageResult;
  final bool storeInInboxResult;
  final DiscoveredPeer? discoverPeerResult;
  final bool dialPeerResult;
  final List<String> operationLog;
  int sendLocalMediaCallCount = 0;

  _FakeP2PService({
    this.localPeer = false, // used by Phase 3C voice tests
    this.localMediaResult = false, // used by Phase 3C voice tests
    this.throwOnSendLocalMedia = false, // used by Phase 3C voice tests
    this.sendMessageResult = true,
    this.storeInInboxResult = true,
    this.discoverPeerResult,
    this.dialPeerResult = true,
    List<String>? operationLog,
  }) : operationLog = operationLog ?? <String>[];

  @override
  NodeState get currentState =>
      const NodeState(isStarted: true, peerId: 'peer-me');
  @override
  Stream<NodeState> get stateStream => const Stream.empty();
  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();
  @override
  Future<bool> startNode(String pk, String peerId) async => true;
  @override
  Future<bool> startNodeCore(String pk, String peerId) async => true;
  @override
  Future<void> warmBackground() async {}
  @override
  Future<bool> stopNode() async => true;
  @override
  Future<bool> sendMessage(String peerId, String message) async => true;
  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async {
    operationLog.add('p2p:sendMessageWithReply');
    return SendMessageResult(sent: sendMessageResult, reply: 'received: ok');
  }

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    operationLog.add('p2p:discoverPeer');
    return discoverPeerResult;
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => dialPeerResult;
  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) async {
    operationLog.add('p2p:storeInInbox');
    return storeInInboxResult;
  }

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      [];
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
    operationLog.add('p2p:sendLocalMedia');
    sendLocalMediaCallCount++;
    if (throwOnSendLocalMedia) throw Exception('sendLocalMedia failed');
    return localMediaResult;
  }

  @override
  String? get lastRecoveryMethod => null;
  @override
  void dispose() {}
}

class _FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  @override
  Future<void> saveAttachment(MediaAttachment a) async {}
  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(String mid) async =>
      [];
  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> mids,
  ) async => {};
  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;
  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async => 0;
  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async => 0;
  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => [];
  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async => [];
  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}
  @override
  Future<void> updateLocalPath(String id, String localPath) async {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ContactModel _makeContact() => ContactModel(
  peerId: '12D3KooWContactPeer123',
  publicKey: 'pub',
  rendezvous: '/dns4/relay/tcp/443/p2p/relay',
  username: 'Alice',
  signature: 'sig',
  scannedAt: '2026-02-11T10:00:00.000Z',
);

IdentityModel _makeIdentity() => IdentityModel(
  peerId: '12D3KooWMyPeer123',
  publicKey: 'pub',
  privateKey: 'priv',
  mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
  username: 'Me',
  createdAt: '2026-02-11T09:00:00.000Z',
  updatedAt: '2026-02-11T09:00:00.000Z',
);

/// Instant-success send function.
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
  final ts = timestamp ?? DateTime.now().toUtc().toIso8601String();
  final delivered = ConversationMessage(
    id: messageId ?? 'msg-default',
    contactPeerId: targetPeerId,
    senderPeerId: senderPeerId,
    text: text,
    timestamp: ts,
    status: 'delivered',
    isIncoming: false,
    createdAt: ts,
  );
  return (SendChatMessageResult.success, delivered);
}

/// Pumps a ConversationWired widget with the given overrides.
Future<void> _pumpConversationWired(
  WidgetTester tester, {
  required Bridge bridge,
  SendChatMessageFn? sendFn,
  SendVoiceMessageFn? sendVoiceFn,
  UploadMediaFn? uploadMediaFn,
  P2PService? p2pService,
  List<File>? initialAttachments,
  FakeAudioRecorderService? audioRecorderService,
}) async {
  final identityRepo = _FakeIdentityRepository(_makeIdentity());
  final messageRepo = _FakeMessageRepository();
  final chatListener = ChatMessageListener(
    chatMessageStream: const Stream<ChatMessage>.empty(),
    messageRepo: messageRepo,
    contactRepo: _FakeContactRepository(),
  );

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ConversationWired(
        contact: _makeContact(),
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatMessageListener: chatListener,
        p2pService: p2pService ?? _FakeP2PService(),
        bridge: bridge,
        sendChatMessageFn: sendFn ?? _instantSuccessSendFn,
        sendVoiceMessageFn: sendVoiceFn ?? sendVoiceMessage,
        uploadMediaFn: uploadMediaFn ?? uploadMedia,
        mediaAttachmentRepo: _FakeMediaAttachmentRepository(),
        initialAttachments: initialAttachments,
        audioRecorderService: audioRecorderService,
      ),
    ),
  );
  // Wait for initState / loadIdentity to settle
  await tester.pump(const Duration(milliseconds: 400));
}

int _logIndex(List<String> operationLog, String entry) {
  final index = operationLog.indexOf(entry);
  expect(index, isNot(-1), reason: 'Expected "$entry" in $operationLog');
  return index;
}

void _expectOrdered(List<String> operationLog, String earlier, String later) {
  expect(
    _logIndex(operationLog, earlier),
    lessThan(_logIndex(operationLog, later)),
    reason: 'Expected "$earlier" before "$later" in $operationLog',
  );
}

Future<void> _recordAndStopVoice(WidgetTester tester) async {
  final screen = tester.widget<ConversationScreen>(
    find.byType(ConversationScreen),
  );
  final startRecording = screen.onRecordStart! as Future<void> Function();
  await startRecording();
  await tester.pump(const Duration(milliseconds: 100));

  final refreshedScreen = tester.widget<ConversationScreen>(
    find.byType(ConversationScreen),
  );
  final stopRecording =
      refreshedScreen.onRecordStop! as Future<void> Function();
  final stopFuture = stopRecording();
  await tester.pump(const Duration(milliseconds: 300));
  await stopFuture;
  await tester.pump(const Duration(milliseconds: 300));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // Suppress overflow errors from card layouts in test surface.
  late void Function(FlutterErrorDetails)? originalOnError;
  setUp(() {
    originalOnError = FlutterError.onError;
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
  });
  tearDown(() {
    FlutterError.onError = originalOnError;
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  group('ConversationWired _onSend — background task ordering', () {
    testWidgets(
      'bg:begin happens before media upload and bg:end happens after send',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        bool uploadCalled = false;
        bool sendCalled = false;

        final tempDir = Directory.systemTemp.createTempSync('bg_task_test_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final attachment = File('${tempDir.path}/photo.jpg')
          ..writeAsStringSync('image');

        await _pumpConversationWired(
          tester,
          bridge: bridge,
          uploadMediaFn:
              ({
                required Bridge bridge,
                required String localFilePath,
                required String mime,
                required String recipientPeerId,
                MediaFileManager? mediaFileManager,
                int? width,
                int? height,
                int? durationMs,
                List<double>? waveform,
                List<String>? allowedPeers,
                String? blobId,
              }) async {
                uploadCalled = true;
                operationLog.add('uploadMediaFn');
                return MediaAttachment(
                  id: 'media-1',
                  messageId: '',
                  mime: mime,
                  size: 100,
                  mediaType: 'image',
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
          sendFn:
              ({
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
                operationLog.add('sendChatMessageFn');
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
              },
          initialAttachments: [attachment],
        );

        // Type text and tap send
        await tester.enterText(find.byType(TextField), 'hello');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          uploadCalled,
          isTrue,
          reason: 'uploadMediaFn must be called when there are attachments',
        );
        expect(sendCalled, isTrue);
        _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
        _expectOrdered(operationLog, 'uploadMediaFn', 'sendChatMessageFn');
        _expectOrdered(operationLog, 'sendChatMessageFn', 'bridge:bg:end');
      },
    );

    testWidgets('bg:end fires in finally when media upload throws', (
      tester,
    ) async {
      final operationLog = <String>[];
      final bridge = _OrderRecordingBridge(operationLog: operationLog);

      final tempDir = Directory.systemTemp.createTempSync(
        'bg_task_test_throw_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final attachment = File('${tempDir.path}/photo.jpg')
        ..writeAsStringSync('image');

      await _pumpConversationWired(
        tester,
        bridge: bridge,
        uploadMediaFn:
            ({
              required Bridge bridge,
              required String localFilePath,
              required String mime,
              required String recipientPeerId,
              MediaFileManager? mediaFileManager,
              int? width,
              int? height,
              int? durationMs,
              List<double>? waveform,
              List<String>? allowedPeers,
              String? blobId,
            }) async {
              operationLog.add('uploadMediaFn');
              throw Exception('simulated network interruption during upload');
            },
        initialAttachments: [attachment],
      );

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));

      _expectOrdered(operationLog, 'bridge:bg:begin', 'uploadMediaFn');
      _expectOrdered(operationLog, 'uploadMediaFn', 'bridge:bg:end');
    });
  });

  group('ConversationWired _onSend text-only — background task ordering', () {
    testWidgets(
      'bg:begin happens before text-only send and bg:end happens after',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        bool sendCalled = false;

        await _pumpConversationWired(
          tester,
          bridge: bridge,
          sendFn:
              ({
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
                operationLog.add('sendChatMessageFn');
                final ts =
                    timestamp ?? DateTime.now().toUtc().toIso8601String();
                return (
                  SendChatMessageResult.success,
                  ConversationMessage(
                    id: messageId ?? 'msg-1',
                    contactPeerId: targetPeerId,
                    senderPeerId: senderPeerId,
                    text: text,
                    timestamp: ts,
                    status: 'delivered',
                    isIncoming: false,
                    createdAt: ts,
                  ),
                );
              },
        );

        await tester.enterText(find.byType(TextField), 'hello text only');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        expect(sendCalled, isTrue);
        _expectOrdered(operationLog, 'bridge:bg:begin', 'sendChatMessageFn');
        _expectOrdered(operationLog, 'sendChatMessageFn', 'bridge:bg:end');
      },
    );
  });

  group('ConversationWired _onRecordStop — background task ordering', () {
    testWidgets(
      'local WiFi voice send starts bg task before local transfer and ends after delegated send',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1200
          ..fakeOutputPath = '/tmp/voice_local_bg.m4a';
        final file = File(recorder.fakeOutputPath!)..writeAsStringSync('voice');
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });
        final p2pService = _FakeP2PService(
          localPeer: true,
          localMediaResult: true,
          operationLog: operationLog,
        );

        await _pumpConversationWired(
          tester,
          bridge: bridge,
          p2pService: p2pService,
          audioRecorderService: recorder,
          sendFn:
              ({
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
                operationLog.add('sendChatMessageFn');
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
              },
        );

        await _recordAndStopVoice(tester);

        expect(p2pService.sendLocalMediaCallCount, 1);
        _expectOrdered(operationLog, 'bridge:bg:begin', 'p2p:sendLocalMedia');
        _expectOrdered(operationLog, 'p2p:sendLocalMedia', 'sendChatMessageFn');
        _expectOrdered(operationLog, 'sendChatMessageFn', 'bridge:bg:end');
      },
    );

    testWidgets('bg:end fires when relay voice upload fails early', (
      tester,
    ) async {
      final operationLog = <String>[];
      final bridge = _OrderRecordingBridge(operationLog: operationLog);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 1200
        ..fakeOutputPath = '/tmp/voice_relay_fail_bg.m4a';
      final file = File(recorder.fakeOutputPath!)..writeAsStringSync('voice');
      addTearDown(() {
        if (file.existsSync()) file.deleteSync();
      });

      await _pumpConversationWired(
        tester,
        bridge: bridge,
        p2pService: _FakeP2PService(operationLog: operationLog),
        audioRecorderService: recorder,
        sendVoiceFn:
            ({
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
              operationLog.add('sendVoiceMessageFn');
              return (SendVoiceMessageResult.uploadFailed, null);
            },
      );

      await _recordAndStopVoice(tester);

      _expectOrdered(operationLog, 'bridge:bg:begin', 'sendVoiceMessageFn');
      _expectOrdered(operationLog, 'sendVoiceMessageFn', 'bridge:bg:end');
    });

    testWidgets(
      'relay voice branch begins before sendVoiceMessage and ends after success',
      (tester) async {
        final operationLog = <String>[];
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1600
          ..fakeOutputPath = '/tmp/voice_relay_bg.m4a';
        final file = File(recorder.fakeOutputPath!)..writeAsStringSync('voice');
        addTearDown(() {
          if (file.existsSync()) file.deleteSync();
        });

        final relayP2pService = _FakeP2PService(operationLog: operationLog);
        await _pumpConversationWired(
          tester,
          bridge: bridge,
          p2pService: relayP2pService,
          audioRecorderService: recorder,
          sendVoiceFn:
              ({
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
                operationLog.add('sendVoiceMessageFn');
                final ts =
                    timestamp ?? DateTime.now().toUtc().toIso8601String();
                return (
                  SendVoiceMessageResult.success,
                  ConversationMessage(
                    id: messageId ?? 'voice-msg-1',
                    contactPeerId: targetPeerId,
                    senderPeerId: senderPeerId,
                    text: text ?? '',
                    timestamp: ts,
                    status: 'delivered',
                    isIncoming: false,
                    createdAt: ts,
                    media: const [],
                  ),
                );
              },
        );

        await _recordAndStopVoice(tester);

        expect(relayP2pService.sendLocalMediaCallCount, 0);
        _expectOrdered(operationLog, 'bridge:bg:begin', 'sendVoiceMessageFn');
        _expectOrdered(operationLog, 'sendVoiceMessageFn', 'bridge:bg:end');
      },
    );
  });
}
