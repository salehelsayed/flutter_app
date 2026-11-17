import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_route_authority.dart';
import 'package:flutter_app/features/feed/domain/models/feed_session_reply.dart';
// test/features/feed/presentation/screens/feed_wired_bg_task_test.dart
import '../../../../shared/fakes/in_memory_contact_request_repository.dart';
//
// Phase 2 Unit 2C — Step 3.5
// RED tests: verify that FeedWired _onInlineSend calls bg:begin before
// sendChatMessage and bg:end afterwards.
// These tests are expected to FAIL (red) because the presentation layer
// does not yet call bg:begin/bg:end.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';

import 'package:flutter_app/l10n/app_localizations.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Bridge that records every command name in order.
class _OrderRecordingBridge implements Bridge {
  final List<String> callLog = [];
  final List<String> operationLog;
  Completer<void>? bgBeginGate;
  final String bgBeginResponse;

  _OrderRecordingBridge({
    List<String>? operationLog,
    this.bgBeginResponse = '42',
  }) : operationLog = operationLog ?? <String>[];

  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final cmd = decoded['cmd'] as String;
    callLog.add(cmd);
    operationLog.add('bridge:$cmd');
    if (cmd == 'bg:begin') await bgBeginGate?.future;
    if (cmd == 'bg:begin') return bgBeginResponse;
    if (cmd == 'bg:end') return '';
    if (cmd == 'message.encrypt') {
      return jsonEncode({
        'ok': true,
        'kem': 'fake-kem',
        'ciphertext': 'fake-ct',
        'nonce': 'fake-nonce',
      });
    }
    // Default: return valid JSON for other commands
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
  IdentityModel? _identity;
  void seed(IdentityModel? identity) => _identity = identity;

  @override
  Future<IdentityModel?> loadIdentity() async => _identity;
  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    _identity = identity;
  }
}

class _FakeContactRepository implements ContactRepository {
  @override
  Future<ContactModel?> updateContactAvatar(
    String peerId, {
    required String avatarPath,
    required String avatarVersion,
  }) async {
    final current = _contacts[peerId];
    if (current == null || current.isBlocked) return null;
    final updated = current.copyWith(
      avatarPath: avatarPath,
      avatarVersion: avatarVersion,
    );
    _contacts[peerId] = updated;
    return updated;
  }

  final Map<String, ContactModel> _contacts = {};

  void seed(List<ContactModel> contacts) {
    _contacts.clear();
    for (final c in contacts) {
      _contacts[c.peerId] = c;
    }
  }

  @override
  Future<void> addContact(ContactModel c) async {
    _contacts[c.peerId] = c;
  }

  @override
  Future<bool> contactExists(String peerId) async =>
      _contacts.containsKey(peerId);
  @override
  Future<void> deleteContact(String peerId) async => _contacts.remove(peerId);
  @override
  Future<List<ContactModel>> getAllContacts() async =>
      _contacts.values.toList();
  @override
  Future<ContactModel?> getContact(String peerId) async => _contacts[peerId];
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

class _FakeContactRequestRepository extends InMemoryContactRequestRepository {
  @override
  Future<void> addRequest(ContactRequestModel r) async {}
  @override
  Future<ContactRequestModel?> getRequest(String peerId) async => null;
  @override
  Future<List<ContactRequestModel>> getPendingRequests() async => [];
  @override
  Future<void> updateStatus(String peerId, ContactRequestStatus status) async {}
  @override
  Future<void> deleteRequest(String peerId) async {}
  @override
  Future<bool> requestExists(String peerId) async => false;
}

class _FakeP2PService implements P2PService {
  final bool isStarted = true;
  final DiscoveredPeer? discoverPeerResult = const DiscoveredPeer(
    id: 'contact-peer-id',
    addresses: ['/ip4/127.0.0.1/tcp/4001'],
  );
  final bool dialPeerResult = true;
  final bool sendMessageResult = true;
  final bool storeInInboxResult = false;
  final RelayProbeResult probeRelayResultValue = RelayProbeResult.error;
  final List<String> operationLog;

  _FakeP2PService({List<String>? operationLog})
    : operationLog = operationLog ?? <String>[];

  @override
  NodeState get currentState =>
      NodeState(isStarted: isStarted, peerId: 'test-peer-id-12345');
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
  }) async {
    operationLog.add('p2p:dialPeer');
    return dialPeerResult;
  }

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<bool> storeInInbox(
    String toPeerId,
    String message, {
    int? timeoutMs,
  }) async {
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
      probeRelayResultValue;
  @override
  bool isConnectedToPeer(String peerId) => false;
  @override
  bool isLocalPeer(String peerId) => false;

  @override
  String? lastKnownGoodTransport(String peerId) => null;

  @override
  void recordSuccessfulTransport(String peerId, String transport) {}

  @override
  Future<bool> discoverLocalPeer(
    String peerId, {
    required Duration timeout,
  }) async => false;

  @override
  Stream<LocalMediaReady> get incomingLocalMediaStream => const Stream.empty();
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
    bool enc = false,
    String? encScheme,
  }) async => false;
  @override
  String? get lastRecoveryMethod => null;
  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _testIdentity = IdentityModel(
  peerId: 'test-peer-id-12345',
  publicKey: 'test-public-key',
  privateKey: 'test-private-key',
  mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
  username: 'Alice',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

final _testContact = ContactModel(
  peerId: 'contact-peer-id',
  publicKey: 'contact-pk',
  rendezvous: '/dns4/relay/tcp/443',
  username: 'Bob',
  signature: 'sig',
  scannedAt: DateTime.now().toUtc().toIso8601String(),
  mlKemPublicKey: 'mlkem-contact-peer-id',
);

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

class _IntentFeedRepository extends InMemoryMessageRepository
    implements AuthoredDirectTextIntentRepository {
  final Completer<bool> admission = Completer<bool>();
  AuthoredDirectTextIntent? requested;
  final List<AuthoredDirectTextIntent> intents = [];
  @override
  bool get supportsAuthoredDirectTextIntents => true;
  @override
  Future<bool> saveAuthoredDirectTextIntent(
    AuthoredDirectTextIntent intent,
  ) async {
    requested = intent;
    if (!await admission.future) return false;
    intents.add(intent);
    return true;
  }

  @override
  Future<bool> cancelAuthoredDirectTextIntent(
    AuthoredDirectTextIntent intent,
  ) async => intents.remove(intent);
  @override
  Future<List<AuthoredDirectTextIntent>>
  loadAuthoredDirectTextIntents() async => intents;
}

void main() {
  late _FakeIdentityRepository identityRepo;
  late _FakeContactRepository contactRepo;
  late _FakeContactRequestRepository contactRequestRepo;
  late _FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;

  setUp(() {
    identityRepo = _FakeIdentityRepository();
    contactRepo = _FakeContactRepository();
    contactRequestRepo = _FakeContactRequestRepository();
    p2pService = _FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    // 214: this suite arranges feed-first behavior; pin the start tab now that
    // the bare default is orbit (orbit-as-home locked elsewhere).
    appShellController = AppShellController(initialTab: AppShellTab.feed);
    pendingPostTargetStore = PendingPostTargetStore();
    mediaFileManager = FakeMediaFileManager();
    imageProcessor = ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    );

    // Mock path_provider for getApplicationDocumentsDirectory()
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp/test_docs';
            }
            return null;
          },
        );
  });

  tearDown(() {
    postRepository.dispose();
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  /// Builds a FeedWired with the _OrderRecordingBridge, wrapped in MaterialApp.
  Widget buildFeedWiredWithBridge(_OrderRecordingBridge bridge, {
    ActiveIdentityReporter? activityReporter,
  }) {
    final effectiveContactRepo = contactRepo;
    final effectiveMessageRepo = messageRepo;

    final crListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: effectiveContactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );

    final cmListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: effectiveMessageRepo,
      contactRepo: effectiveContactRepo,
    );

    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FeedWired(
        directRouteAuthority: DirectConversationRouteAuthority(activityReporter: activityReporter),
        repository: identityRepo,
        contactRepository: effectiveContactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: crListener,
        messageRepository: effectiveMessageRepo,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: cmListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        feedClearedRepository: InMemoryFeedClearedRepository(),
      ),
    );
  }

  /// Seeds identity and contact, pumps, and waits for feed to load.
  Future<void> pumpAndSeedFeed(
    WidgetTester tester,
    _OrderRecordingBridge bridge, {
    ActiveIdentityReporter? activityReporter,
  }) async {
    // Suppress RenderFlex overflow errors from card layouts in test surface
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    // Don't addTearDown here — caller handles it.

    identityRepo.seed(_testIdentity);
    contactRepo.seed([_testContact]);

    // Add a message from contact so the feed card appears
    await messageRepo.saveMessage(
      ConversationMessage(
        id: 'msg-feed-1',
        contactPeerId: 'contact-peer-id',
        text: 'Hello from Bob',
        senderPeerId: 'contact-peer-id',
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        status: 'delivered',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );

    tester.view.physicalSize = const Size(1284, 2778);
    tester.view.devicePixelRatio = 1.0;

    await tester.pumpWidget(buildFeedWiredWithBridge(bridge, activityReporter: activityReporter));
    // Allow feed to load
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const feedCaptureScenarios = [
    ('E2U-F001 unchanged Feed owner marks admitted inline text', 'same'),
    ('E2U-F002 Feed sender drift preserves communication and suppresses activity', 'drift'),
    ('E2U-F003 unarmed Feed observation cannot be replaced after enabling', 'unarmed'),
    ('E2U-F004 refused Feed intent creates neither custody nor activity', 'refused'),
    ('E2U-F005 Feed retained-custody retry creates no new activity observation', 'retry'),
  ];
  for (final (name, scenario) in feedCaptureScenarios) {
    testWidgets(name, (tester) async {
      final originalOnError = FlutterError.onError;
      final repository = _IntentFeedRepository();
      messageRepo = repository;
      final bridge = _DailyFeedBridge();
      final reporter = ActiveIdentityReporter(statePath: '/unused/feed-capture.json');
      reporter.attachBridge(bridge);
      reporter.observeIdentity(accountPeerId: _testIdentity.peerId,
        rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
        profileBinding: _feedCaptureBinding);
      await reporter.observeConsent((enabled: scenario != 'unarmed', consentEpoch: 7))
          .timeout(const Duration(seconds: 2));
      Future<void>? sending;
      var finished = false;
      Object? sendError;
      try {
        await pumpAndSeedFeed(tester, bridge, activityReporter: reporter);
        FeedScreen screen() => tester.widget<FeedScreen>(find.byType(FeedScreen));
        final callback = screen().onComposerSend!;
        sending = Future<void>.sync(() => callback('contact-peer-id', 'fresh private Feed text'))
            .then<void>((_) { finished = true; }, onError: (Object error, StackTrace stack) {
              sendError = error;
              finished = true;
            });
        for (var i = 0; i < 20 && repository.requested == null; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(repository.requested, isNotNull, reason: 'hold the first authored intent await');
        expect(repository.directInboxCustodyStageCallCount, 0);
        expect(bridge.marks, isEmpty);
        if (scenario == 'drift') {
          final successor = IdentityModel(peerId: 'successor-peer', publicKey: 'successor-pk',
            privateKey: 'successor-sk', mnemonic12: _testIdentity.mnemonic12,
            username: 'Successor', createdAt: _testIdentity.createdAt,
            updatedAt: _testIdentity.updatedAt);
          identityRepo.seed(successor);
          reporter.observeIdentity(accountPeerId: successor.peerId,
            rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 19)),
            profileBinding: _feedCaptureOtherBinding);
          await reporter.observeConsent((enabled: true, consentEpoch: 7))
              .timeout(const Duration(seconds: 2));
          appShellController.notifyIdentityChanged();
          for (var i = 0; i < 20 && screen().userPeerId != successor.peerId; i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(screen().userPeerId, successor.peerId, reason: 'the real Feed identity reload must finish');
        } else if (scenario == 'unarmed') {
          await reporter.observeConsent((enabled: true, consentEpoch: 8))
              .timeout(const Duration(seconds: 2));
        }
        repository.admission.complete(scenario != 'refused');
        for (var i = 0; i < 40 && !finished; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        expect(finished, isTrue, reason: 'authored callback must settle within the fixture budget');
        await sending.timeout(const Duration(seconds: 2));
        if (scenario == 'refused') {
          expect(sendError, isA<StateError>());
          expect(repository.directInboxCustodyStageCallCount, 0);
          expect(bridge.callLog, isNot(contains('bg:begin')));
          expect(bridge.marks, isEmpty);
        } else {
          expect(sendError, isNull);
          for (var i = 0; i < 60 && !bridge.callLog.contains('bg:end'); i++) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(bridge.callLog, contains('bg:end'), reason: 'join the actual detached send, not just intent admission');
          expect(repository.directInboxCustodyStageCallCount, 1);
          final id = repository.requested!.id;
          final message = await repository.getMessage(id).timeout(const Duration(seconds: 2));
          expect(message, isNotNull);
          expect(message!.senderPeerId, scenario == 'drift' ? 'successor-peer' : _testIdentity.peerId,
            reason: 'analytics must not rewrite the incumbent communication identity');
          if (scenario == 'retry') {
            bridge.marks.clear();
            final transportsBefore = p2pService.operationLog.where((entry) => entry == 'p2p:sendMessageWithReply').length;
            final custodyBefore = await repository.loadDirectInboxCustodyOwnerForMessageId(messageId: id)
                .timeout(const Duration(seconds: 2));
            expect(custodyBefore, isNotNull);
            await repository.updateMessageStatus(id, 'failed').timeout(const Duration(seconds: 2));
            final retry = (screen().onRetrySend as Future<void> Function(String, FeedSessionReply))(
              'contact-peer-id', FeedSessionReply(messageId: id, text: message.text));
            var retried = false;
            final settled = retry.whenComplete(() => retried = true);
            for (var i = 0; i < 60 && !retried; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }
            expect(retried, isTrue);
            await settled.timeout(const Duration(seconds: 2));
            final custodyAfter = await repository.loadDirectInboxCustodyOwnerForMessageId(messageId: id)
                .timeout(const Duration(seconds: 2));
            expect(custodyAfter, isNotNull);
            expect(custodyAfter!.recipientPeerId, custodyBefore!.recipientPeerId);
            expect(custodyAfter.messageId, custodyBefore.messageId);
            expect(custodyAfter.incarnationId, custodyBefore.incarnationId);
            expect(custodyAfter.wireEnvelope, custodyBefore.wireEnvelope);
            expect(custodyAfter.retryCount, custodyBefore.retryCount + 1,
              reason: 'the exact retained custody retry must actually run');
            expect(custodyAfter.lastErrorCode, 'store_failed');
            expect(p2pService.operationLog.where((entry) => entry == 'p2p:sendMessageWithReply').length,
              transportsBefore, reason: 'retained custody owns retry without a new live send');
            expect(repository.directInboxCustodyStageCallCount, 1, reason: 'retry reuses retained custody');
            expect(bridge.marks, isEmpty);
          } else {
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }
            expect(bridge.marks, scenario == 'same' ? hasLength(1) : isEmpty);
          }
        }
      } finally {
        if (!repository.admission.isCompleted) {
          repository.admission.complete(false);
        }
        for (var i = 0; i < 40 && !finished && sending != null; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        if (sending != null) {
          await sending.timeout(const Duration(seconds: 2));
        }
        // The authored callback detaches dispatch; settle every started native
        // background-task scope before disposing its widget/reporter, even
        // when an earlier contract assertion failed.
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 10));
          final begins = bridge.callLog.where((cmd) => cmd == 'bg:begin').length;
          final ends = bridge.callLog.where((cmd) => cmd == 'bg:end').length;
          if (ends >= begins) {
            break;
          }
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await reporter.dispose().timeout(const Duration(seconds: 2));
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        FlutterError.onError = originalOnError;
      }
    });
  }

  group('FeedWired _onInlineSend — background task ordering', () {
    for (final scenario in [0, 1, 2]) {
      final admitted = scenario != 0;
      final edited = scenario == 2;
      testWidgets(
        'authored Feed text ${edited ? 'keeps new typing' : ''} ${admitted ? 'commits before input release and bubble' : 'write refusal preserves input'}',
        (tester) async {
          addTearDown(() {
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final originalOnError = FlutterError.onError;
          addTearDown(() => FlutterError.onError = originalOnError);
          final repository = _IntentFeedRepository();
          messageRepo = repository;
          final bridge = _OrderRecordingBridge()
            ..bgBeginGate = Completer<void>();
          await pumpAndSeedFeed(tester, bridge);
          await tester.tap(find.textContaining('Bob').first);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final input = find.byKey(const ValueKey('feed-composer-field'));
          await tester.enterText(input, 'durable Feed text');
          await tester.pump();
          await tester.tap(find.byKey(const ValueKey('feed-composer-send')));
          await tester.pump();
          expect(repository.requested?.text, 'durable Feed text');
          expect(repository.intents, isEmpty);
          expect(bridge.callLog, isNot(contains('bg:begin')));
          expect(
            tester.widget<TextField>(input).controller!.text,
            'durable Feed text',
          );
          expect(
            tester
                .widget<FeedScreen>(find.byType(FeedScreen))
                .sessionReplies
                .values
                .expand((x) => x),
            isEmpty,
          );
          if (edited) {
            await tester.enterText(input, 'new draft');
            await tester.pump();
          }
          repository.admission.complete(admitted);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 50));
          expect(repository.intents, admitted ? hasLength(1) : isEmpty);
          expect(
            tester.widget<TextField>(input).controller!.text,
            edited
                ? 'new draft'
                : admitted
                ? ''
                : 'durable Feed text',
          );
          expect(
            tester
                .widget<FeedScreen>(find.byType(FeedScreen))
                .sessionReplies
                .values
                .expand((x) => x),
            admitted ? hasLength(1) : isEmpty,
          );
          expect(bridge.callLog.contains('bg:begin'), admitted);
          bridge.bgBeginGate!.complete();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
        },
      );
    }

    testWidgets(
      'bg:begin happens before inline send transport and bg:end happens after success',
      (tester) async {
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.toString().contains('overflowed')) return;
          originalOnError?.call(details);
        };
        addTearDown(() {
          FlutterError.onError = originalOnError;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final operationLog = <String>[];
        p2pService = _FakeP2PService(operationLog: operationLog);
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        await pumpAndSeedFeed(tester, bridge);
        final bobCard = find.textContaining('Bob');
        expect(
          bobCard,
          findsWidgets,
          reason: 'Bob card must be visible in the feed',
        );
        await tester.tap(bobCard.first);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        await tester.enterText(find.byType(TextField).last, 'hello from feed');
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded).last);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        final messages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        final outgoing = messages
            .where((message) => !message.isIncoming)
            .toList();
        expect(
          outgoing,
          isNotEmpty,
          reason: 'Inline send should persist an outgoing message',
        );
        _expectOrdered(operationLog, 'bridge:bg:begin', 'p2p:discoverPeer');
        _expectOrdered(
          operationLog,
          'p2p:sendMessageWithReply',
          'bridge:bg:end',
        );
      },
    );

    testWidgets('inline send proceeds when OS refuses background task', (
      tester,
    ) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.toString().contains('overflowed')) return;
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final operationLog = <String>[];
      p2pService = _FakeP2PService(operationLog: operationLog);
      final bridge = _OrderRecordingBridge(
        operationLog: operationLog,
        bgBeginResponse: '',
      );
      await pumpAndSeedFeed(tester, bridge);

      final bobCard = find.textContaining('Bob');
      expect(bobCard, findsWidgets);
      await tester.tap(bobCard.first);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      final textFields = find.byType(TextField);
      if (textFields.evaluate().isNotEmpty) {
        await tester.enterText(textFields.last, 'hello from feed');
        await tester.pump();

        final sendButtons = find.byIcon(Icons.arrow_upward_rounded);
        if (sendButtons.evaluate().isNotEmpty) {
          await tester.tap(sendButtons.last);
          await tester.pump(const Duration(milliseconds: 500));
          await tester.pump(const Duration(milliseconds: 500));
        }
      }

      final messages = await messageRepo.getMessagesForContact(
        'contact-peer-id',
      );
      final outgoing = messages
          .where((message) => !message.isIncoming)
          .toList();

      expect(
        outgoing,
        isNotEmpty,
        reason: 'Send must still succeed even if bg:begin returns no task ID',
      );
      expect(
        bridge.callLog.where((cmd) => cmd == 'bg:end'),
        isEmpty,
        reason: 'bg:end should not be called when the OS refuses bg:begin',
      );
      _expectOrdered(operationLog, 'bridge:bg:begin', 'p2p:discoverPeer');
      expect(
        operationLog,
        contains('p2p:sendMessageWithReply'),
        reason: 'Transport send must still execute after OS refusal',
      );
    });
  });
}

const _feedCaptureBinding = 'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _feedCaptureOtherBinding = 'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _DailyFeedBridge extends _OrderRecordingBridge {
  final marks = <Map<String, dynamic>>[];
  int _revision = 0;
  @override
  bool get isInitialized => true;
  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] != 'active_identity_reporter_v1') {
      return super.send(message);
    }
    final request = Map<String, dynamic>.from(envelope['payload'] as Map);
    final revision = request['op'] == 'configure' ? ++_revision : request['revision'];
    if (request['op'] == 'mark') {
      marks.add(request);
    }
    return jsonEncode({'ok': true, 'data': {
      'revision': revision, 'consentEpoch': request['consentEpoch'],
      if (request['op'] == 'configure') 'configured': request['enabled'] == true && request['profileBinding'] != '',
      if (request['op'] == 'mark') 'accepted': true,
      if (request['op'] == 'flush') 'queued': true,
    }});
  }
}
