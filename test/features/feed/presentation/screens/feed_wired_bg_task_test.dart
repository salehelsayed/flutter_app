// test/features/feed/presentation/screens/feed_wired_bg_task_test.dart
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
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contact_request/domain/repositories/contact_request_repository.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
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

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Bridge that records every command name in order.
class _OrderRecordingBridge implements Bridge {
  final List<String> callLog = [];
  final List<String> operationLog;
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

class _FakeContactRequestRepository implements ContactRequestRepository {
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
  final bool isStarted;
  final DiscoveredPeer? discoverPeerResult;
  final bool dialPeerResult;
  final bool sendMessageResult;
  final bool storeInInboxResult;
  final RelayProbeResult probeRelayResultValue;
  final List<String> operationLog;

  _FakeP2PService({
    this.isStarted = true,
    this.discoverPeerResult = const DiscoveredPeer(
      id: 'contact-peer-id',
      addresses: ['/ip4/127.0.0.1/tcp/4001'],
    ),
    this.dialPeerResult = true,
    this.sendMessageResult = true,
    this.storeInInboxResult = false,
    this.probeRelayResultValue = RelayProbeResult.error,
    List<String>? operationLog,
  }) : operationLog = operationLog ?? <String>[];

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
      probeRelayResultValue;
  @override
  bool isConnectedToPeer(String peerId) => false;
  @override
  bool isLocalPeer(String peerId) => false;
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
    appShellController = AppShellController();
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
  Widget buildFeedWiredWithBridge(_OrderRecordingBridge bridge) {
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
      ),
    );
  }

  /// Seeds identity and contact, pumps, and waits for feed to load.
  Future<void> pumpAndSeedFeed(
    WidgetTester tester,
    _OrderRecordingBridge bridge,
  ) async {
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

    await tester.pumpWidget(buildFeedWiredWithBridge(bridge));
    // Allow feed to load
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('FeedWired _onInlineSend — background task ordering', () {
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

    testWidgets(
      'bg:end fires after a real inline send failure and draft is restored',
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
        p2pService = _FakeP2PService(
          sendMessageResult: false,
          storeInInboxResult: false,
          operationLog: operationLog,
        );
        final bridge = _OrderRecordingBridge(operationLog: operationLog);
        await pumpAndSeedFeed(tester, bridge);

        final bobCard = find.textContaining('Bob');
        expect(bobCard, findsWidgets);
        await tester.tap(bobCard.first);
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }

        const draftText = 'feed send should fail';
        await tester.enterText(find.byType(TextField).last, draftText);
        await tester.pump();
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded).last);
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pump(const Duration(milliseconds: 500));

        final messages = await messageRepo.getMessagesForContact(
          'contact-peer-id',
        );
        final failedOutgoing = messages
            .where((message) => !message.isIncoming)
            .firstWhere((message) => message.status == 'failed');

        expect(failedOutgoing.text, draftText);
        final restoredComposer = tester.widget<TextField>(
          find.byType(TextField).last,
        );
        expect(
          restoredComposer.controller?.text,
          draftText,
          reason: 'Draft text should be restored after a failed inline send',
        );
        _expectOrdered(
          operationLog,
          'bridge:bg:begin',
          'p2p:sendMessageWithReply',
        );
        _expectOrdered(operationLog, 'p2p:storeInInbox', 'bridge:bg:end');
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
