import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_presentation_gate.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

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
  late ContactRequestPresentationGate contactRequestPresentationGate;
  late List<NotificationRouteTarget> routedTargets;
  late Future<RemoteMessage?> Function() getInitialRemoteMessage;
  late int clearDeliveredNotificationsCount;

  final identity = IdentityModel(
    peerId: 'peer-self',
    publicKey: 'pk-self',
    privateKey: 'sk-self',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-pk-self',
    mlKemSecretKey: 'mlkem-sk-self',
    username: 'Alice',
    createdAt: '2026-04-03T12:00:00.000Z',
    updatedAt: '2026-04-03T12:00:00.000Z',
  );

  setUp(() {
    previousDeferredStartupMode = StartupConfig.deferredStartupMode;
    StartupConfig.deferredStartupMode = true;

    identityRepository = FakeIdentityRepository()..seed(identity);
    contactRepository = FakeContactRepository()
      ..seed([
        ContactModel(
          peerId: 'peer-existing',
          publicKey: 'pk-existing',
          rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-existing',
          username: 'Existing',
          signature: 'sig-existing',
          scannedAt: '2026-04-03T12:00:00.000Z',
        ),
      ]);
    contactRequestRepository = FakeContactRequestRepository();
    messageRepository = InMemoryMessageRepository();
    postRepository = InMemoryPostRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    bridge = FakeBridge();
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
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    contactRequestPresentationGate = ContactRequestPresentationGate();
    routedTargets = <NotificationRouteTarget>[];
    getInitialRemoteMessage = () async => null;
    clearDeliveredNotificationsCount = 0;

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
        contactRequestPresentationGate: contactRequestPresentationGate,
        getInitialRemoteMessage: getInitialRemoteMessage,
        shouldHandleInitialPushOpen: () => true,
        clearDeliveredNotifications: () async {
          clearDeliveredNotificationsCount += 1;
        },
        onNotificationRouteTarget: (routeTarget) async {
          routedTargets.add(routeTarget);
        },
      ),
    );
  }

  testWidgets('cold-start contact-request push drains inbox then routes', (
    tester,
  ) async {
    getInitialRemoteMessage = () async => const RemoteMessage(
      data: {'type': 'contact_request', 'sender_id': 'peer-request-123'},
    );

    await tester.pumpWidget(buildRouterApp());
    await pumpFrames(tester);

    expect(routedTargets, hasLength(1));
    expect(
      routedTargets.single.kind,
      NotificationRouteTargetKind.contactRequest,
    );
    expect(routedTargets.single.peerId, 'peer-request-123');
    expect(p2pService.startNodeCallCount, 1);
    expect(p2pService.drainOfflineInboxCallCount, 1);
    expect(clearDeliveredNotificationsCount, 1);
    expect(
      contactRequestPresentationGate.shouldSuppress('peer-request-123'),
      isFalse,
    );
  });

  testWidgets('cold-start intros push drains inbox then routes', (
    tester,
  ) async {
    getInitialRemoteMessage = () async =>
        const RemoteMessage(data: {'type': 'intros'});

    await tester.pumpWidget(buildRouterApp());
    await pumpFrames(tester);

    expect(routedTargets, hasLength(1));
    expect(routedTargets.single.kind, NotificationRouteTargetKind.intros);
    expect(p2pService.startNodeCallCount, 1);
    expect(p2pService.drainOfflineInboxCallCount, 1);
    expect(clearDeliveredNotificationsCount, 1);
  });

  testWidgets('invalid cold-start push falls back cleanly without route', (
    tester,
  ) async {
    getInitialRemoteMessage = () async =>
        const RemoteMessage(data: {'type': 'unknown_future_type'});

    await tester.pumpWidget(buildRouterApp());
    await pumpFrames(tester);

    expect(routedTargets, isEmpty);
    expect(p2pService.startNodeCallCount, 1);
    expect(
      p2pService.drainOfflineInboxCallCount,
      1,
      reason: 'missing initial pushes should still trigger inbox recovery',
    );
    expect(clearDeliveredNotificationsCount, 0);
  });
}
