import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/posts/domain/repositories/post_repository.dart';
import 'package:flutter_app/features/posts/domain/repositories/posts_privacy_settings_repository.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 134-P8 TC-32 — contract preservation.
///
/// The 134 feed redesign changed the feed's UI wholesale but MUST keep the
/// share-to-contact wiring intact: [FeedWired] still injects and stores
/// [PostRepository], [PendingPostTargetStore], and
/// [PostsPrivacySettingsRepository] so a post shared to a contact still routes
/// through the feed surface. This test builds the NEW [FeedWired] (the same
/// construction pattern as feed_focus_test / feed_wired_test) and asserts it
/// builds AND that the three share dependencies are reachable on the widget.
///
/// Green-by-construction: it compiles only against the post-redesign contract.
void main() {
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;

  final testIdentity = IdentityModel(
    peerId: 'me-peer',
    publicKey: 'me-pk',
    privateKey: 'me-sk',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Me',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    identityRepo = FakeIdentityRepository();
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
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

  FeedWired buildFeedWired(PostRepository postRepo) {
    final crListener = ContactRequestListener(
      contactRequestStream: const Stream.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener = ChatMessageListener(
      chatMessageStream: const Stream.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );
    return FeedWired(
      repository: identityRepo,
      contactRepository: contactRepo,
      contactRequestRepository: contactRequestRepo,
      contactRequestListener: crListener,
      messageRepository: messageRepo,
      postRepository: postRepo,
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
    );
  }

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  void setWideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets(
    'FeedWired builds and still injects the share-to-contact dependencies',
    (tester) async {
      setWideViewport(tester);
      identityRepo.seed(testIdentity);

      final wired = buildFeedWired(postRepository);
      await tester.pumpWidget(wrap(wired));
      // Bounded pumps — AmbientBackground.repeat() hangs pumpAndSettle.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      // It built.
      expect(find.byType(FeedWired), findsOneWidget);
      expect(tester.takeException(), isNull);

      // The post / share dependencies are reachable on the mounted widget,
      // proving the constructor contract that share-to-contact relies on is
      // preserved (identity-equal to what we injected).
      final mounted = tester.widget<FeedWired>(find.byType(FeedWired));
      expect(identical(mounted.postRepository, postRepository), isTrue);
      expect(
        identical(mounted.pendingPostTargetStore, pendingPostTargetStore),
        isTrue,
      );
      expect(
        identical(
          mounted.postsPrivacySettingsRepository,
          postsPrivacySettingsRepository,
        ),
        isTrue,
      );

      // Static type checks: the fields keep their domain contract types.
      expect(mounted.postRepository, isA<PostRepository>());
      expect(mounted.pendingPostTargetStore, isA<PendingPostTargetStore>());
      expect(
        mounted.postsPrivacySettingsRepository,
        isA<PostsPrivacySettingsRepository>(),
      );
    },
  );
}
