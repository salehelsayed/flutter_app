import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../core/bridge/fake_bridge.dart';
import '../../core/secure_storage/fake_secure_key_store.dart';
import '../../core/services/fake_p2p_service.dart';
import '../../shared/fakes/fake_media_file_manager.dart';
import '../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../shared/fakes/in_memory_message_repository.dart';
import '../../shared/fakes/in_memory_post_repository.dart';
import '../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../contacts/domain/repositories/fake_contact_repository.dart';
import 'domain/repositories/fake_identity_repository.dart';

/// FDC-07 TC-07-03 — the cold-start orchestrator (StartupRouter._doStartP2P)
/// fires the early-LAN-discovery seam on node-start success, AFTER the plan-164
/// ensureRuntimeServicesReady gate and before the group-rejoin/drain block. The
/// seam is wired as an optional callback (NOT a P2PService interface method) so
/// it adds zero churn to the ~31 `implements P2PService` fakes.
void main() {
  late bool previousDeferredStartupMode;
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late FakeContactRequestRepository contactRequestRepository;
  late ContactRequestListener contactRequestListener;
  late InMemoryMessageRepository messageRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late ChatMessageListener chatMessageListener;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late InMemoryContactPresenceSnapshotRepository
  contactPresenceSnapshotRepository;

  final order = <String>[];
  var earlyDiscoveryCallCount = 0;

  final identity = IdentityModel(
    peerId: 'peer-self',
    publicKey: 'pk-self',
    privateKey: 'sk-self',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-pk-self',
    mlKemSecretKey: 'mlkem-sk-self',
    username: 'Alice',
    createdAt: '2026-03-15T10:00:00.000Z',
    updatedAt: '2026-03-15T10:00:00.000Z',
  );

  setUp(() {
    previousDeferredStartupMode = StartupConfig.deferredStartupMode;
    StartupConfig.deferredStartupMode = true;

    order.clear();
    earlyDiscoveryCallCount = 0;

    identityRepository = FakeIdentityRepository()..seed(identity);
    contactRepository = FakeContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    bridge = FakeBridge(
      initialResponses: {
        'payload.sign': {'ok': true, 'signature': 'test-sig'},
      },
    );
    p2pService = FakeP2PService();
    mediaFileManager = FakeMediaFileManager();
    secureKeyStore = FakeSecureKeyStore();
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
    messageRepository = InMemoryMessageRepository();
    postRepository = InMemoryPostRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    contactPresenceSnapshotRepository =
        InMemoryContactPresenceSnapshotRepository();

    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => identity.peerId,
    );

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
    );
  });

  tearDown(() {
    StartupConfig.deferredStartupMode = previousDeferredStartupMode;
    postsPrivacySettingsRepository.dispose();
    contactPresenceSnapshotRepository.dispose();
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget buildRouterApp() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StartupRouter(
        repository: identityRepository,
        feedClearedRepository: InMemoryFeedClearedRepository(),
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
        ensureRuntimeServicesReady: () async {
          order.add('ensure');
        },
        startEarlyLocalDiscovery: () async {
          order.add('early_discovery');
          earlyDiscoveryCallCount++;
        },
      ),
    );
  }

  testWidgets(
    'cold start fires the early-discovery seam once, after the 164 gate',
    (tester) async {
      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      // Node start was driven by the orchestrator.
      expect(p2pService.startNodeCallCount, 1);

      // The early-discovery seam fired exactly once on success.
      expect(
        earlyDiscoveryCallCount,
        1,
        reason: '_doStartP2P must invoke the early-discovery seam exactly once',
      );

      // ...AFTER the plan-164 ensureRuntimeServicesReady gate (INV-6: FDC-07
      // does not reorder node-start relative to that gate).
      expect(order.contains('ensure'), isTrue);
      expect(order.contains('early_discovery'), isTrue);
      expect(
        order.indexOf('ensure'),
        lessThan(order.indexOf('early_discovery')),
        reason: 'early discovery must fire AFTER ensureRuntimeServicesReady '
            '(order=$order)',
      );
    },
  );
}
