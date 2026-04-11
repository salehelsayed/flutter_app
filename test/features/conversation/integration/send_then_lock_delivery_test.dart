import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/application/retry_incomplete_uploads_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_payload.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/test_user.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

class BobTestHarness {
  final TestUser bob;
  final FakeNotificationService notificationService;
  final ActiveConversationTracker conversationTracker;
  final List<ChatMessage> receivedMessages = [];
  late final ChatMessageListener _listener;
  late final StreamSubscription<ChatMessage> _rawSub;
  AppLifecycleState lifecycleState;

  BobTestHarness({
    required this.bob,
    this.lifecycleState = AppLifecycleState.paused,
  }) : notificationService = FakeNotificationService(),
       conversationTracker = ActiveConversationTracker() {
    _rawSub = bob.p2pService.messageStream.listen(receivedMessages.add);
    _listener = ChatMessageListener(
      chatMessageStream: bob.p2pService.messageStream,
      messageRepo: bob.messageRepo,
      contactRepo: bob.contactRepo,
      mediaAttachmentRepo: bob.mediaAttachmentRepo,
      bridge: bob.bridge,
      notificationService: notificationService,
      conversationTracker: conversationTracker,
      getAppLifecycleState: () => lifecycleState,
      getOwnMlKemSecretKey: () async => 'test-own-mlkem-sk',
      remoteNotificationGate: RecentRemoteNotificationGate(
        filePath:
            '${Directory.systemTemp.path}/send_then_lock_delivery_test_${identityHashCode(this)}.json',
      ),
      backgroundNotificationDuplicateGuardDelay: Duration.zero,
    );
  }

  void start() => _listener.start();

  void stop() {
    _listener.stop();
    _rawSub.cancel();
  }

  List<FakeNotification> get shownNotifications => notificationService.shown;

  void clearNotifications() => notificationService.shown.clear();

  Future<void> expectMessageCount(String contactPeerId, int count) async {
    final messages = await bob.messageRepo.getMessagesForContact(contactPeerId);
    expect(messages, hasLength(count));
  }

  Future<void> expectLatestMessageText(
    String contactPeerId,
    String text,
  ) async {
    final messages = await bob.messageRepo.getMessagesForContact(contactPeerId);
    expect(messages.last.text, text);
    expect(messages.last.isIncoming, isTrue);
  }

  void expectNotificationCount(int count, {String? reason}) {
    expect(shownNotifications, hasLength(count), reason: reason);
  }

  void expectLatestNotification({
    required String contactPeerId,
    required String body,
    String? senderUsername,
  }) {
    expect(shownNotifications, isNotEmpty);
    final last = shownNotifications.last;
    expect(last.contactPeerId, contactPeerId);
    expect(last.messageText, body);
    if (senderUsername != null) {
      expect(last.senderUsername, senderUsername);
    }
  }
}

class _WifiFirstVoiceP2PService implements P2PService {
  final P2PService _inner;
  final Set<String> _localPeerIds;
  final bool _sendLocalMediaResult;

  int sendLocalMediaCallCount = 0;

  _WifiFirstVoiceP2PService({
    required P2PService inner,
    required Set<String> localPeerIds,
    bool sendLocalMediaResult = false,
  }) : _inner = inner,
       _localPeerIds = localPeerIds,
       _sendLocalMediaResult = sendLocalMediaResult;

  @override
  NodeState get currentState => _inner.currentState;

  @override
  Stream<NodeState> get stateStream => _inner.stateStream;

  @override
  Stream<ChatMessage> get messageStream => _inner.messageStream;

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) =>
      _inner.startNode(privateKeyBase64, peerId);

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) =>
      _inner.startNodeCore(privateKeyBase64, peerId);

  @override
  Future<void> warmBackground() => _inner.warmBackground();

  @override
  Future<bool> stopNode() => _inner.stopNode();

  @override
  Future<bool> sendMessage(String peerId, String message) =>
      _inner.sendMessage(peerId, message);

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) => _inner.sendMessageWithReply(peerId, message, timeoutMs: timeoutMs);

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) =>
      _inner.discoverPeer(peerId, timeoutMs: timeoutMs);

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) => _inner.dialPeer(peerId, addresses: addresses, timeoutMs: timeoutMs);

  @override
  Future<bool> storeInInbox(String toPeerId, String message) =>
      _inner.storeInInbox(toPeerId, message);

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) =>
      _inner.retrieveInbox(timeoutMs: timeoutMs);

  @override
  Future<bool> registerPushToken(String token, String platform) =>
      _inner.registerPushToken(token, platform);

  @override
  Future<void> performImmediateHealthCheck() =>
      _inner.performImmediateHealthCheck();

  @override
  Future<void> drainOfflineInbox() => _inner.drainOfflineInbox();

  @override
  bool isConnectedToPeer(String peerId) => _inner.isConnectedToPeer(peerId);

  @override
  Future<RelayProbeResult> probeRelay(String peerId) =>
      _inner.probeRelay(peerId);

  @override
  bool isLocalPeer(String peerId) =>
      _localPeerIds.contains(peerId) || _inner.isLocalPeer(peerId);

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) => _inner.sendLocalMessage(
    peerId,
    message,
    fromPeerId,
    timeoutMs: timeoutMs,
  );

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
    return _sendLocalMediaResult;
  }

  @override
  String? get lastRecoveryMethod => _inner.lastRecoveryMethod;

  @override
  void dispose() => _inner.dispose();
}

class _WidgetVoiceP2PService implements P2PService {
  final Set<String> _localPeerIds;

  int sendLocalMediaCallCount = 0;

  _WidgetVoiceP2PService({required Set<String> localPeerIds})
    : _localPeerIds = localPeerIds;

  @override
  NodeState get currentState => const NodeState(isStarted: true, peerId: 'me');

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      true;

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
  }) async => const SendMessageResult(sent: true, reply: 'received: ok');

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async => false;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      const [];

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  bool isLocalPeer(String peerId) => _localPeerIds.contains(peerId);

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
    return false;
  }

  @override
  String? get lastRecoveryMethod => null;

  @override
  void dispose() {}
}

class _FakeJustAudioPlatform extends JustAudioPlatform {
  final Map<String, _FakeAudioPlayerPlatform> _players = {};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = _FakeAudioPlayerPlatform(request.id);
    _players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await _players.remove(request.id)?.dispose(DisposeRequest());
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    for (final player in _players.values) {
      await player.dispose(DisposeRequest());
    }
    _players.clear();
    return DisposeAllPlayersResponse();
  }
}

class _FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  final _playbackEvents = StreamController<PlaybackEventMessage>.broadcast();
  final _playerData = StreamController<PlayerDataMessage>.broadcast();
  bool _disposed = false;

  _FakeAudioPlayerPlatform(super.id) {
    _emitPlayback(ProcessingStateMessage.idle);
  }

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream =>
      _playbackEvents.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _playerData.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    _emitPlayback(
      ProcessingStateMessage.ready,
      duration: const Duration(seconds: 1),
      currentIndex: request.initialIndex ?? 0,
    );
    return LoadResponse(duration: const Duration(seconds: 1));
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    _playerData.add(PlayerDataMessage(playing: true));
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    _playerData.add(PlayerDataMessage(playing: false));
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async {
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    return SetLoopModeResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    return SetShuffleModeResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async {
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    return SeekResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    if (_disposed) return DisposeResponse();
    _disposed = true;
    await _playbackEvents.close();
    await _playerData.close();
    return DisposeResponse();
  }

  void _emitPlayback(
    ProcessingStateMessage state, {
    Duration updatePosition = Duration.zero,
    Duration bufferedPosition = Duration.zero,
    Duration? duration,
    int? currentIndex,
  }) {
    if (_disposed) return;
    _playbackEvents.add(
      PlaybackEventMessage(
        processingState: state,
        updateTime: DateTime.now(),
        updatePosition: updatePosition,
        bufferedPosition: bufferedPosition,
        duration: duration,
        icyMetadata: null,
        currentIndex: currentIndex,
        androidAudioSessionId: null,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('B.1 Send-then-lock: proves the original bug is fixed', () {
    late FakeP2PNetwork network;
    late TestUser alice;
    late TestUser bob;
    late BobTestHarness bobHarness;
    late FakeIdentityRepository aliceIdentityRepo;
    late InMemoryMediaAttachmentRepository aliceMediaAttachmentRepo;
    late InMemoryMediaAttachmentRepository bobMediaAttachmentRepo;
    late PassthroughCryptoBridge aliceBridge;
    late JustAudioPlatform originalAudioPlatform;
    late _FakeJustAudioPlatform fakeAudioPlatform;
    late Directory tempDir;

    Future<String> writeTempMediaFile(String name, List<int> bytes) async {
      final file = File('${tempDir.path}/$name');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }

    Future<int> retryAliceFailedMessages() {
      return retryFailedMessages(
        messageRepo: alice.messageRepo,
        identityRepo: aliceIdentityRepo,
        contactRepo: alice.contactRepo,
        p2pService: alice.p2pService,
        bridge: alice.bridge,
        mediaAttachmentRepo: aliceMediaAttachmentRepo,
      );
    }

    Future<int> retryAliceIncompleteUploads({P2PService? p2pService}) {
      return retryIncompleteUploads(
        mediaAttachmentRepo: aliceMediaAttachmentRepo,
        messageRepo: alice.messageRepo,
        bridge: alice.bridge,
        p2pService: p2pService ?? alice.p2pService,
        identityRepo: aliceIdentityRepo,
        contactRepo: alice.contactRepo,
      );
    }

    Future<void> waitForBob() async {
      await Future.delayed(const Duration(milliseconds: 150));
    }

    Future<void> pumpConversationWired(
      WidgetTester tester, {
      required ContactModel contact,
      required ChatMessageListener chatListener,
      required P2PService p2pService,
      SendChatMessageFn sendChatMessageFn = sendChatMessage,
      SendVoiceMessageFn sendVoiceMessageFn = sendVoiceMessage,
      FakeAudioRecorderService? audioRecorderService,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ConversationWired(
            contact: contact,
            identityRepo: aliceIdentityRepo,
            messageRepo: alice.messageRepo,
            chatMessageListener: chatListener,
            p2pService: p2pService,
            bridge: alice.bridge,
            contactRepo: alice.contactRepo,
            mediaAttachmentRepo: aliceMediaAttachmentRepo,
            sendChatMessageFn: sendChatMessageFn,
            sendVoiceMessageFn: sendVoiceMessageFn,
            audioRecorderService: audioRecorderService,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
    }

    MediaAttachment audioAttachment({
      required String id,
      required int durationMs,
      required String createdAt,
      String textPath = '/tmp/test-audio.m4a',
    }) {
      return MediaAttachment(
        id: id,
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        durationMs: durationMs,
        waveform: const [0.2, 0.6, 0.8, 0.3],
        localPath: textPath,
        downloadStatus: 'done',
        createdAt: createdAt,
      );
    }

    MediaAttachment imageAttachment({
      required String id,
      required String createdAt,
      String localPath = '/tmp/test-image.jpg',
    }) {
      return MediaAttachment(
        id: id,
        messageId: '',
        mime: 'image/jpeg',
        size: 128000,
        mediaType: 'image',
        width: 1440,
        height: 1080,
        localPath: localPath,
        downloadStatus: 'done',
        createdAt: createdAt,
      );
    }

    setUp(() async {
      originalAudioPlatform = JustAudioPlatform.instance;
      fakeAudioPlatform = _FakeJustAudioPlatform();
      JustAudioPlatform.instance = fakeAudioPlatform;
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());

      network = FakeP2PNetwork();
      tempDir = await Directory.systemTemp.createTemp('send_then_lock_');
      aliceMediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      bobMediaAttachmentRepo = InMemoryMediaAttachmentRepository();
      aliceBridge = PassthroughCryptoBridge();

      alice = TestUser.create(
        peerId: 'peer-alice',
        username: 'Alice',
        network: network,
        mediaAttachmentRepo: aliceMediaAttachmentRepo,
        bridge: aliceBridge,
      );
      bob = TestUser.create(
        peerId: 'peer-bob',
        username: 'Bob',
        network: network,
        mediaAttachmentRepo: bobMediaAttachmentRepo,
        autoStartListener: false,
      );

      bobHarness = BobTestHarness(bob: bob);
      bobHarness.start();

      alice.addContact(bob);
      bob.addContact(alice);
      alice.setOnline(true);
      bob.setOnline(true);

      aliceIdentityRepo = FakeIdentityRepository()
        ..seed(
          IdentityModel(
            peerId: alice.peerId,
            publicKey: 'pk-${alice.peerId}',
            privateKey: 'alice-privkey',
            mnemonic12:
                'word1 word2 word3 word4 word5 word6 '
                'word7 word8 word9 word10 word11 word12',
            mlKemPublicKey: 'alice-mlkem-pk',
            mlKemSecretKey: 'alice-mlkem-sk',
            username: alice.username,
            createdAt: '2026-01-01T00:00:00.000Z',
            updatedAt: '2026-01-01T00:00:00.000Z',
          ),
        );
    });

    tearDown(() async {
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      bobHarness.stop();
      alice.dispose();
      bob.dispose();
      await fakeAudioPlatform.disposeAllPlayers(DisposeAllPlayersRequest());
      JustAudioPlatform.instance = originalAudioPlatform;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      '1. THE REAL BUG: original-row text recovery follows handleAppPaused -> handleAppResumed',
      () async {
        const messageId = 'stuck-msg-001';
        final timestamp = DateTime.now().toUtc().toIso8601String();
        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: 'Stuck in sending',
            timestamp: timestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: timestamp,
          ),
        );

        await alice.simulatePause();

        final afterPause = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(afterPause, hasLength(1));
        expect(afterPause.single.id, messageId);
        expect(afterPause.single.status, 'failed');

        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: 'delivered-msg-002',
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: 'Already delivered',
            timestamp: timestamp,
            status: 'delivered',
            isIncoming: false,
            createdAt: timestamp,
          ),
        );
        await alice.simulatePause();
        final helperMessage = (await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        )).firstWhere((message) => message.id == 'delivered-msg-002');
        expect(helperMessage.status, 'delivered');

        bobHarness.clearNotifications();
        final callOrder = <String>[];
        await alice.simulateResume(
          retryFailedMessagesFn: () async {
            callOrder.add('retryFailedMessages');
            return retryAliceFailedMessages();
          },
        );
        expect(callOrder, ['retryFailedMessages']);

        await waitForBob();

        final afterResume = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        final stuckRows = afterResume
            .where((message) => message.id == messageId)
            .toList();
        expect(stuckRows, hasLength(1));
        expect(stuckRows.single.status, anyOf('delivered', 'sent'));
        expect(afterResume, hasLength(2));

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Stuck in sending',
        );
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Stuck in sending',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '2. MEDIA-UPLOAD-LOCK: interrupted image upload recovers through the production resume chain',
      () async {
        const messageId = 'media-stuck-img-001';
        const attachmentId = 'blob-img-001';
        final timestamp = DateTime.now().toUtc().toIso8601String();
        final durablePath = await writeTempMediaFile(
          'image.jpg',
          List<int>.generate(32, (index) => index),
        );

        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: '',
            timestamp: timestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: timestamp,
          ),
        );
        await aliceMediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 204800,
            mediaType: 'image',
            width: 1920,
            height: 1080,
            localPath: durablePath,
            downloadStatus: 'upload_pending',
            createdAt: timestamp,
          ),
        );

        aliceBridge.throwOnSend = true;
        expect(await retryAliceIncompleteUploads(), 0);
        await alice.simulatePause();

        final pausedMessage = await alice.messageRepo.getMessage(messageId);
        expect(pausedMessage?.status, 'failed');
        final pendingAttachment =
            (await aliceMediaAttachmentRepo.getAttachmentsForMessage(
              messageId,
            )).single;
        expect(pendingAttachment.id, attachmentId);
        expect(pendingAttachment.downloadStatus, 'upload_pending');

        aliceBridge.throwOnSend = false;
        bobHarness.clearNotifications();
        final callOrder = <String>[];
        await alice.simulateResume(
          retryIncompleteUploadsFn: () async {
            callOrder.add('retryIncompleteUploads');
            return retryAliceIncompleteUploads();
          },
          retryFailedMessagesFn: () async {
            callOrder.add('retryFailedMessages');
            return retryAliceFailedMessages();
          },
        );
        expect(callOrder, ['retryIncompleteUploads', 'retryFailedMessages']);

        await waitForBob();

        final recoveredMessage = await alice.messageRepo.getMessage(messageId);
        expect(recoveredMessage?.status, anyOf('delivered', 'sent'));
        final recoveredAttachments = await aliceMediaAttachmentRepo
            .getAttachmentsForMessage(messageId);
        expect(recoveredAttachments, hasLength(1));
        expect(recoveredAttachments.single.id, attachmentId);
        expect(recoveredAttachments.single.downloadStatus, 'done');

        await bobHarness.expectMessageCount(alice.peerId, 1);
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Photo',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '3. VOICE-UPLOAD-LOCK: interrupted voice upload recovers through relay on resume',
      () async {
        const messageId = 'voice-stuck-001';
        const attachmentId = 'blob-voice-001';
        final timestamp = DateTime.now().toUtc().toIso8601String();
        final durablePath = await writeTempMediaFile(
          'voice.m4a',
          List<int>.filled(48, 7),
        );

        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: '',
            timestamp: timestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: timestamp,
          ),
        );
        await aliceMediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'audio/mp4',
            size: 83200,
            mediaType: 'audio',
            durationMs: 5200,
            waveform: const [0.1, 0.5, 0.8, 0.3, 0.6],
            localPath: durablePath,
            downloadStatus: 'upload_pending',
            createdAt: timestamp,
          ),
        );

        aliceBridge.throwOnSend = true;
        expect(await retryAliceIncompleteUploads(), 0);
        await alice.simulatePause();

        aliceBridge.throwOnSend = false;
        bobHarness.clearNotifications();
        await alice.simulateResume(
          retryIncompleteUploadsFn: retryAliceIncompleteUploads,
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        await waitForBob();

        final recoveredMessage = await alice.messageRepo.getMessage(messageId);
        expect(recoveredMessage?.status, anyOf('delivered', 'sent'));
        final recoveredAttachment =
            (await aliceMediaAttachmentRepo.getAttachmentsForMessage(
              messageId,
            )).single;
        expect(recoveredAttachment.id, attachmentId);
        expect(recoveredAttachment.downloadStatus, 'done');
        expect(recoveredAttachment.durationMs, 5200);
        expect(recoveredAttachment.waveform, [0.1, 0.5, 0.8, 0.3, 0.6]);

        await bobHarness.expectMessageCount(alice.peerId, 1);
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Voice message',
          senderUsername: 'Alice',
        );
      },
    );

    testWidgets(
      '3b. WIFI-INTERRUPTED-VOICE: local-peer voice transport is attempted before relay recovery on resume',
      (tester) async {
        final durablePath = await tester.runAsync(
          () => writeTempMediaFile('wifi-voice.m4a', List<int>.filled(40, 9)),
        );
        final recorder = FakeAudioRecorderService()
          ..fakeOutputPath = durablePath
          ..fakeDurationMs = 4100
          ..fakeSizeBytes = 64000;
        final widgetP2p = _WidgetVoiceP2PService(localPeerIds: {bob.peerId});
        final wifiFirstP2p = _WifiFirstVoiceP2PService(
          inner: alice.p2pService,
          localPeerIds: {bob.peerId},
        );
        final contact = await alice.contactRepo.getContact(bob.peerId);
        expect(contact, isNotNull);
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: alice.messageRepo,
          contactRepo: alice.contactRepo,
          bridge: alice.bridge,
          getOwnMlKemSecretKey: () async => 'alice-mlkem-sk',
        );

        await pumpConversationWired(
          tester,
          contact: contact!,
          chatListener: chatListener,
          p2pService: widgetP2p,
          audioRecorderService: recorder,
          sendVoiceMessageFn:
              ({
                required p2pService,
                required messageRepo,
                required targetPeerId,
                required senderPeerId,
                required senderUsername,
                required recording,
                required bridge,
                recipientMlKemPublicKey,
                mediaAttachmentRepo,
                mediaFileManager,
                text,
                quotedMessageId,
                waveform,
                messageId,
                timestamp,
                blobId,
              }) async => (SendVoiceMessageResult.uploadFailed, null),
        );
        bobHarness.clearNotifications();

        var screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump(const Duration(milliseconds: 100));

        screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );

        final stopRecording = screen.onRecordStop! as Future<void> Function();
        final stopFuture = stopRecording();
        await tester.pump(const Duration(milliseconds: 300));
        await stopFuture;
        await tester.pump();

        expect(widgetP2p.isLocalPeer(bob.peerId), isTrue);
        expect(widgetP2p.sendLocalMediaCallCount, 1);

        final stuckMessage = (await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        )).single;
        expect(stuckMessage.status, 'failed');
        final pendingAttachment =
            (await aliceMediaAttachmentRepo.getAttachmentsForMessage(
              stuckMessage.id,
            )).single;
        expect(pendingAttachment.downloadStatus, 'upload_pending');
        expect(pendingAttachment.durationMs, 4100);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        chatListener.dispose();
        await recorder.dispose();

        final callOrder = <String>[];
        await tester.runAsync(() async {
          await alice.simulatePause();
          await alice.simulateResume(
            retryIncompleteUploadsFn: () async {
              callOrder.add('retryIncompleteUploads');
              return retryAliceIncompleteUploads(p2pService: wifiFirstP2p);
            },
            retryFailedMessagesFn: () async {
              callOrder.add('retryFailedMessages');
              return retryAliceFailedMessages();
            },
          );
          await waitForBob();
        });
        expect(callOrder, ['retryIncompleteUploads', 'retryFailedMessages']);

        final recoveredMessage = await alice.messageRepo.getMessage(
          stuckMessage.id,
        );
        expect(recoveredMessage?.status, anyOf('delivered', 'sent'));
        final recoveredAttachment =
            (await aliceMediaAttachmentRepo.getAttachmentsForMessage(
              stuckMessage.id,
            )).single;
        expect(recoveredAttachment.downloadStatus, 'done');

        await bobHarness.expectMessageCount(alice.peerId, 1);
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Voice message',
          senderUsername: 'Alice',
        );
      },
    );

    test('4. REGRESSION: completed send is not overwritten by pause', () async {
      bobHarness.clearNotifications();
      final (result, _) = await alice.sendMessage(
        bob.peerId,
        'Hello from locked phone',
      );

      expect(result, SendChatMessageResult.success);
      await alice.simulatePause();
      await waitForBob();

      final aliceMessages = await alice.messageRepo.getMessagesForContact(
        bob.peerId,
      );
      expect(aliceMessages, hasLength(1));
      expect(aliceMessages.single.status, isNot('sending'));
      expect(aliceMessages.single.status, isNot('failed'));

      await bobHarness.expectMessageCount(alice.peerId, 1);
      await bobHarness.expectLatestMessageText(
        alice.peerId,
        'Hello from locked phone',
      );
      bobHarness.expectNotificationCount(1);
      bobHarness.expectLatestNotification(
        contactPeerId: alice.peerId,
        body: 'Hello from locked phone',
        senderUsername: 'Alice',
      );
    });

    testWidgets(
      '5. conversation_wired widget path saves the optimistic row before send and updates the same row',
      (tester) async {
        final chatListener = ChatMessageListener(
          chatMessageStream: const Stream.empty(),
          messageRepo: alice.messageRepo,
          contactRepo: alice.contactRepo,
          bridge: alice.bridge,
          getOwnMlKemSecretKey: () async => 'alice-mlkem-sk',
        );
        final contact = await alice.contactRepo.getContact(bob.peerId);
        expect(contact, isNotNull);
        final allowSend = Completer<void>();
        final optimisticRowSeen = Completer<ConversationMessage?>();

        await pumpConversationWired(
          tester,
          contact: contact!,
          chatListener: chatListener,
          p2pService: alice.p2pService,
          sendChatMessageFn:
              ({
                required p2pService,
                required messageRepo,
                required targetPeerId,
                required text,
                required senderPeerId,
                required senderUsername,
                messageId,
                timestamp,
                bridge,
                recipientMlKemPublicKey,
                quotedMessageId,
                mediaAttachments,
                mediaAttachmentRepo,
              }) async {
                final savedBeforeSend = await messageRepo.getMessage(
                  messageId!,
                );
                if (!optimisticRowSeen.isCompleted) {
                  optimisticRowSeen.complete(savedBeforeSend);
                }
                await allowSend.future;
                return sendChatMessage(
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

        bobHarness.clearNotifications();
        final screen = tester.widget<ConversationScreen>(
          find.byType(ConversationScreen),
        );
        screen.onSend('Two-phase test');
        await tester.pump();

        final savedBeforeSend = await optimisticRowSeen.future;
        expect(savedBeforeSend, isNotNull);
        expect(savedBeforeSend!.status, 'sending');

        final intermediate = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(intermediate, hasLength(1));
        expect(intermediate.single.id, savedBeforeSend.id);
        expect(intermediate.single.status, 'sending');

        allowSend.complete();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump();
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.pump();

        final afterSend = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(afterSend, hasLength(1));
        expect(afterSend.single.id, savedBeforeSend.id);
        expect(afterSend.single.status, isNot('sending'));

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Two-phase test',
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    test(
      '6. direct-first offline delivery still reaches Bob after inbox drain',
      () async {
        bob.setOnline(false);

        final (result, _) = await alice.sendMessage(
          bob.peerId,
          'Direct-first test',
        );

        expect(result, SendChatMessageResult.success);
        final aliceMessages = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(aliceMessages, hasLength(1));
        expect(aliceMessages.single.status, anyOf('delivered', 'sent'));
        expect(network.storeInInboxCallCount, greaterThanOrEqualTo(1));

        bob.setOnline(true);
        await bob.drainOfflineInbox();
        await waitForBob();

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Direct-first test',
        );
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Direct-first test',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '7. app-killed mid-send recovery reuses the original row and still notifies Bob',
      () async {
        const messageId = 'app-killed-001';
        final timestamp = DateTime.now().toUtc().toIso8601String();

        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: 'Killed mid-send',
            timestamp: timestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: timestamp,
            wireEnvelope: MessagePayload(
              id: messageId,
              text: 'Killed mid-send',
              senderPeerId: alice.peerId,
              senderUsername: alice.username,
              timestamp: timestamp,
            ).toJson(),
          ),
        );

        await alice.simulatePause();
        final pausedMessage = await alice.messageRepo.getMessage(messageId);
        expect(pausedMessage?.status, 'failed');
        expect(pausedMessage?.wireEnvelope, isNotNull);

        bob.setOnline(false);
        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        final recoveredMessage = await alice.messageRepo.getMessage(messageId);
        expect(recoveredMessage?.status, 'delivered');
        expect(recoveredMessage?.transport, 'inbox');

        bobHarness.clearNotifications();
        bob.setOnline(true);
        await bob.drainOfflineInbox();
        await waitForBob();

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Killed mid-send',
        );
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Killed mid-send',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '7b. failed send during transport loss survives lock and recovers on resume exactly once',
      () async {
        bobHarness.clearNotifications();
        network.deliveryFails = true;
        network.inboxDisabled = true;

        final (result, failedMessage) = await alice.sendMessage(
          bob.peerId,
          'Switch then lock',
        );

        expect(result, isNot(SendChatMessageResult.success));
        expect(failedMessage, isNotNull);
        expect(failedMessage!.status, 'failed');
        expect(failedMessage.wireEnvelope, isNotNull);

        final failedId = failedMessage.id;
        final failedRows = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(failedRows, hasLength(1));
        expect(failedRows.single.id, failedId);
        expect(failedRows.single.status, 'failed');

        network.deliveryFails = false;
        network.inboxDisabled = false;
        bob.setOnline(false);

        await alice.simulatePause();
        final afterPause = await alice.messageRepo.getMessage(failedId);
        expect(afterPause?.status, 'failed');

        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        final recoveredMessage = await alice.messageRepo.getMessage(failedId);
        expect(recoveredMessage?.status, 'delivered');
        expect(recoveredMessage?.transport, 'inbox');

        bob.setOnline(true);
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);
        await waitForBob();

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Switch then lock',
        );
        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Switch then lock',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '7bb. failed edit survives lock and recovers on resume with same-id edited state',
      () async {
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Original before edit',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        await waitForBob();

        network.deliveryFails = true;
        network.inboxDisabled = true;

        final recipient = await alice.contactRepo.getContact(bob.peerId);
        expect(recipient, isNotNull);

        final (editResult, failedEdit) = await editChatMessage(
          p2pService: alice.p2pService,
          messageRepo: alice.messageRepo,
          originalMessage: sentMessage!,
          updatedText: 'Edited after lock',
          senderUsername: alice.username,
          bridge: alice.bridge,
          recipientMlKemPublicKey: recipient!.mlKemPublicKey,
        );

        expect(editResult, SendChatMessageResult.sendFailed);
        expect(failedEdit, isNotNull);
        expect(failedEdit!.id, sentMessage.id);
        expect(failedEdit.status, 'failed');
        expect(failedEdit.text, 'Edited after lock');
        expect(failedEdit.editedAt, isNotNull);
        expect(failedEdit.wireEnvelope, isNotNull);

        final beforePause = await alice.loadConversationWith(bob.peerId);
        expect(beforePause, hasLength(1));
        expect(beforePause.single.id, sentMessage.id);
        expect(beforePause.single.text, 'Edited after lock');
        expect(beforePause.single.editedAt, failedEdit.editedAt);

        network.deliveryFails = false;
        network.inboxDisabled = false;
        bob.setOnline(false);

        await alice.simulatePause();
        final afterPause = await alice.messageRepo.getMessage(sentMessage.id);
        expect(afterPause?.status, 'failed');

        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        final recoveredMessage = await alice.messageRepo.getMessage(
          sentMessage.id,
        );
        expect(recoveredMessage, isNotNull);
        expect(recoveredMessage!.status, 'delivered');
        expect(recoveredMessage.transport, 'inbox');
        expect(recoveredMessage.text, 'Edited after lock');
        expect(recoveredMessage.editedAt, failedEdit.editedAt);

        bob.setOnline(true);
        final drained = await bob.drainOfflineInbox();
        expect(drained, 1);
        await waitForBob();

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Edited after lock',
        );
        final bobMessages = await bob.messageRepo.getMessagesForContact(
          alice.peerId,
        );
        expect(bobMessages.single.id, sentMessage.id);
        expect(bobMessages.single.editedAt, isNotNull);
      },
    );

    test(
      '7c. failed delete-for-everyone stays visible through pause and hides only after resume delivery',
      () async {
        final (sendResult, sentMessage) = await alice.sendMessage(
          bob.peerId,
          'Delete after lock',
        );
        expect(sendResult, SendChatMessageResult.success);
        expect(sentMessage, isNotNull);

        await waitForBob();

        network.deliveryFails = true;
        network.inboxDisabled = true;

        final (deleteResult, failedDelete) = await alice
            .deleteMessageForEveryone(sentMessage!);

        expect(deleteResult, SendChatMessageResult.sendFailed);
        expect(failedDelete, isNotNull);
        expect(failedDelete!.id, sentMessage.id);
        expect(failedDelete.status, 'failed');
        expect(failedDelete.isDeleted, isTrue);
        expect(failedDelete.isHidden, isFalse);

        final beforePause = await alice.loadConversationWith(bob.peerId);
        expect(beforePause, hasLength(1));
        expect(beforePause.single.id, sentMessage.id);
        expect(beforePause.single.isDeleted, isTrue);
        expect(beforePause.single.isHidden, isFalse);

        await alice.simulatePause();

        network.deliveryFails = false;
        network.inboxDisabled = false;

        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        final stored = await alice.messageRepo.getMessage(sentMessage.id);
        expect(stored, isNotNull);
        expect(stored!.status, 'delivered');
        expect(stored.transport, 'inbox');
        expect(stored.isDeleted, isTrue);
        expect(stored.isHidden, isTrue);
        expect(stored.hiddenAt, stored.deletedAt);

        final afterResume = await alice.loadConversationWith(bob.peerId);
        expect(afterResume, isEmpty);
      },
    );

    test(
      '8. rapid lock-unlock remains exact-once across repeated pause/resume cycles',
      () async {
        const messageId = 'rapid-lock-001';
        final timestamp = DateTime.now().toUtc().toIso8601String();

        await alice.messageRepo.saveMessage(
          ConversationMessage(
            id: messageId,
            contactPeerId: bob.peerId,
            senderPeerId: alice.peerId,
            text: 'Rapid cycle test',
            timestamp: timestamp,
            status: 'sending',
            isIncoming: false,
            createdAt: timestamp,
          ),
        );

        await alice.simulatePause();
        await alice.simulatePause();
        bobHarness.clearNotifications();

        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );
        await alice.simulateResume(
          retryFailedMessagesFn: retryAliceFailedMessages,
        );

        await waitForBob();

        final recoveredRows = await alice.messageRepo.getMessagesForContact(
          bob.peerId,
        );
        expect(recoveredRows, hasLength(1));
        expect(recoveredRows.single.id, messageId);
        expect(recoveredRows.single.status, anyOf('delivered', 'sent'));

        await bobHarness.expectMessageCount(alice.peerId, 1);
        await bobHarness.expectLatestMessageText(
          alice.peerId,
          'Rapid cycle test',
        );
        bobHarness.expectNotificationCount(
          1,
          reason: 'Rapid resume cycles must not duplicate notifications',
        );
      },
    );

    test(
      '9. VOICE-WITH-CAPTION: notification body uses the caption instead of the fallback label',
      () async {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        bobHarness.clearNotifications();

        final (result, _) = await alice
            .sendMessageWithMedia(bob.peerId, 'Listen to this', [
              audioAttachment(
                id: 'blob-voice-caption-001',
                durationMs: 3000,
                createdAt: timestamp,
              ),
            ]);

        expect(result, SendChatMessageResult.success);
        await waitForBob();

        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Listen to this',
          senderUsername: 'Alice',
        );
      },
    );

    test(
      '10. MEDIA-NOTIFICATION-BODY: image caption beats the Photo fallback',
      () async {
        final timestamp = DateTime.now().toUtc().toIso8601String();
        bobHarness.clearNotifications();

        final (result, _) = await alice.sendMessageWithMedia(
          bob.peerId,
          'Look at this',
          [imageAttachment(id: 'blob-photo-caption-001', createdAt: timestamp)],
        );

        expect(result, SendChatMessageResult.success);
        await waitForBob();

        bobHarness.expectLatestNotification(
          contactPeerId: alice.peerId,
          body: 'Look at this',
          senderUsername: 'Alice',
        );
      },
    );
  });
}
