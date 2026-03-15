import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

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
  late _FakeNearbyLocationService nearbyLocationService;

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
    nearbyLocationService = _FakeNearbyLocationService();

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

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget buildRouterApp() {
    return MaterialApp(
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
        contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
        nearbyLocationService: nearbyLocationService,
      ),
    );
  }

  testWidgets(
    'no-contacts startup keeps nearby deps and reruns silent refresh after node start',
    (tester) async {
      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester, count: 20);

      final firstTimeWired = tester.widget<FirstTimeExperienceWired>(
        find.byType(FirstTimeExperienceWired),
      );

      expect(
        firstTimeWired.contactPresenceSnapshotRepository,
        same(contactPresenceSnapshotRepository),
      );
      expect(firstTimeWired.nearbyLocationService, same(nearbyLocationService));
      expect(p2pService.startNodeCallCount, 1);
      expect(nearbyLocationService.refreshSilentlyOnStartupCallCount, 2);
    },
  );
}

class _FakeNearbyLocationService implements NearbyLocationService {
  int loadComposeAvailabilityCallCount = 0;
  int refreshSilentlyOnStartupCallCount = 0;
  int refreshSilentlyOnResumeCallCount = 0;
  int refreshSilentlyOnPostsOpenCallCount = 0;
  int refreshInteractivelyFromSettingsCallCount = 0;
  int refreshInteractivelyFromComposeCallCount = 0;
  int handleSharingDisabledCallCount = 0;

  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async {
    loadComposeAvailabilityCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.sharingOff,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() async {
    refreshInteractivelyFromComposeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() async {
    refreshInteractivelyFromSettingsCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.ready,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async {
    refreshSilentlyOnPostsOpenCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() async {
    refreshSilentlyOnResumeCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() async {
    refreshSilentlyOnStartupCallCount++;
    return const NearbyComposeAvailability(
      state: NearbyComposeAvailabilityState.stale,
    );
  }

  @override
  Future<void> handleSharingDisabled() async {
    handleSharingDisabledCallCount++;
  }

  @override
  Future<bool> openAppSettings() async => true;
}
