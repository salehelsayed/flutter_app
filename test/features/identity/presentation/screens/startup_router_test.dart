import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late ContactRequestListener contactRequestListener;
  late ChatMessageListener chatMessageListener;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'TestUser',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  final testIdentityWithMlKem = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-pk',
    mlKemSecretKey: 'mlkem-sk',
    username: 'TestUser',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  final testContact = ContactModel(
    peerId: 'contact-peer-id',
    publicKey: 'contact-public-key',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'ContactUser',
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
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
    mediaFileManager = FakeMediaFileManager();

    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
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
    contactRequestListener.dispose();
    chatMessageListener.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  ImageProcessor noOpImageProcessor() => ImageProcessor(
        compressFile: ({required path, required quality, required keepExif,
            minWidth = 1920, minHeight = 1080}) async =>
            null,
        compressVideo: ({required path, required compress, onProgress}) async =>
            null,
      );

  Widget buildStartupRouter({IdentityRepository? repoOverride}) {
    return MaterialApp(
      home: StartupRouter(
        repository: repoOverride ?? identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: noOpImageProcessor(),
      ),
    );
  }

  /// Set a large test surface to avoid RenderFlex overflow errors.
  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 1.0;
  }

  /// Pump enough frames for async routing to complete without pumpAndSettle.
  Future<void> pumpRouting(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Pump widget with large test surface to avoid overflow errors, then route.
  Future<void> pumpAndRoute(WidgetTester tester, Widget widget) async {
    setLargeTestSurface(tester);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(widget);
    await pumpRouting(tester);
  }

  group('StartupRouter', () {
    testWidgets('shows loading UI initially', (tester) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildStartupRouter());
      // Single pump — async routing hasn't completed yet
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Loading...'), findsOneWidget);
    });

    testWidgets('navigates to FeedWired when identity exists with contacts',
        (tester) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets(
        'navigates to FirstTimeExperienceWired when identity exists no contacts',
        (tester) async {
      identityRepo.seed(testIdentityWithMlKem);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
    });

    testWidgets('navigates to IdentityChoiceWired when no identity',
        (tester) async {
      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
    });

    testWidgets('calls ML-KEM keygen when identity lacks keys', (tester) async {
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      bridge.responses['mlkem.keygen'] = {
        'ok': true,
        'publicKey': 'gen-pk',
        'secretKey': 'gen-sk',
      };

      await pumpAndRoute(tester, buildStartupRouter());

      expect(bridge.lastCommand, 'mlkem.keygen');
    });

    testWidgets('skips ML-KEM keygen when identity has keys', (tester) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(bridge.lastCommand, isNot('mlkem.keygen'));
    });

    testWidgets('saves enriched identity after ML-KEM keygen', (tester) async {
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      bridge.responses['mlkem.keygen'] = {
        'ok': true,
        'publicKey': 'gen-pk',
        'secretKey': 'gen-sk',
      };

      await pumpAndRoute(tester, buildStartupRouter());

      expect(identityRepo.saveIdentityCallCount, greaterThanOrEqualTo(1));
      expect(identityRepo.lastSavedIdentity?.mlKemPublicKey, 'gen-pk');
    });

    testWidgets('starts P2P node after navigating to FeedWired',
        (tester) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(p2pService.startNodeCallCount, 1);
    });

    testWidgets('starts P2P node after navigating to FTE', (tester) async {
      identityRepo.seed(testIdentityWithMlKem);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(p2pService.startNodeCallCount, 1);
    });

    testWidgets('shows error UI when repository throws', (tester) async {
      await pumpAndRoute(
          tester, buildStartupRouter(repoOverride: _ThrowingIdentityRepository()));

      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.text('Failed to initialize'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry re-triggers routing after error', (tester) async {
      final toggleRepo = _ToggleIdentityRepository();

      await pumpAndRoute(tester, buildStartupRouter(repoOverride: toggleRepo));

      expect(find.text('Failed to initialize'), findsOneWidget);

      toggleRepo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await pumpRouting(tester);

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
    });

    testWidgets('ML-KEM failure is non-fatal (still navigates)',
        (tester) async {
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      bridge.responses['mlkem.keygen'] = {'ok': false, 'errorCode': 'FAIL'};

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets('P2P start failure does not show error UI', (tester) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);
      p2pService.startNodeResult = false;

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.text('Failed to initialize'), findsNothing);
    });
  });
}

class _ThrowingIdentityRepository implements IdentityRepository {
  @override
  Future<IdentityModel?> loadIdentity() async {
    throw Exception('Test: repository failure');
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _ToggleIdentityRepository implements IdentityRepository {
  bool shouldThrow = true;
  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async {
    if (shouldThrow) throw Exception('Test: toggle error');
    return identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}
