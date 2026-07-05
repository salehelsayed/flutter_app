// 214 (PROD-CRITICAL): the full first-run journey — QR/scan screen → first
// accepted friend request — must terminate on the FeedWired shell rendering
// the Orbit pane. Orbit is the main screen; Feed stays reachable inside the
// same shell. Widget-pumped end-to-end over fakes: StartupRouter routes a
// 0-contact identity to FirstTimeExperienceWired, an incoming contact request
// arrives, Accept reciprocates and replaces the route with the shell.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_feed_cleared_repository.dart';
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

  final identity = IdentityModel(
    peerId: 'peer-self-first-run',
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
    // First run: identity exists, ZERO contacts → FTE landing.
    contactRepository = FakeContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    messageRepository = InMemoryMessageRepository();
    postRepository = InMemoryPostRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    bridge = FakeBridge();
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
    bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephemeral-pk',
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
    };
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
    // Production constructs the controller bare (main.dart) — the landing
    // surface must come from the class default, not a fixture override.
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
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
    StartupConfig.deferredStartupMode = previousDeferredStartupMode;
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  void suppressShellRenderErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (details.toString().contains('overflowed') ||
          message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('first-run journey: QR screen → first accept → Orbit surface', (
    tester,
  ) async {
    suppressShellRenderErrors();

    final requestController = StreamController<ContactRequestModel>.broadcast();
    addTearDown(requestController.close);
    final requestListener = _FakeContactRequestListener(
      requestStream: requestController.stream,
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      ownPeerId: identity.peerId,
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StartupRouter(
          repository: identityRepository,
          feedClearedRepository: InMemoryFeedClearedRepository(),
          contactRepository: contactRepository,
          contactRequestRepository: contactRequestRepository,
          contactRequestListener: requestListener,
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
        ),
      ),
    );
    await pumpFrames(tester);

    // Leg 1: a 0-contact identity lands on the intro QR/scan screen.
    expect(find.byType(FirstTimeExperienceWired), findsOneWidget);

    // Leg 2: the first friend request arrives.
    final request = ContactRequestModel(
      peerId: 'sender-peer-first-friend',
      publicKey: 'sender-pub-key',
      rendezvous: '/p2p-circuit/relay',
      username: 'Charlie',
      signature: 'sender-sig',
      receivedAt: DateTime.now().toUtc().toIso8601String(),
    );
    contactRequestRepository.seed([request]);
    requestController.add(request);
    await tester.pump();
    await tester.pump();

    // Leg 3: accept it.
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await pumpFrames(tester);

    // The journey terminates on the shell root showing the Orbit surface.
    expect(find.byType(FeedWired), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(FeedWired))).canPop(),
      isFalse,
    );
    expect(appShellController.activeTab, AppShellTab.orbit);
    expect(find.byType(OrbitWired), findsOneWidget);

    // Golden-path parity: the accepted contact is durably present.
    final acceptedContact = await contactRepository.getContact(request.peerId);
    expect(acceptedContact, isNotNull);
    expect(acceptedContact!.username, 'Charlie');

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
  });
}

/// Fake [ContactRequestListener] whose [requestStream] is test-controlled.
class _FakeContactRequestListener extends ContactRequestListener {
  final Stream<ContactRequestModel> _overrideStream;

  _FakeContactRequestListener({
    required Stream<ContactRequestModel> requestStream,
    required super.requestRepo,
    required super.contactRepo,
    required super.bridge,
    required String ownPeerId,
  }) : _overrideStream = requestStream,
       super(
         contactRequestStream: const Stream<ChatMessage>.empty(),
         getOwnPeerId: () => ownPeerId,
       );

  @override
  Stream<ContactRequestModel> get requestStream => _overrideStream;
}
