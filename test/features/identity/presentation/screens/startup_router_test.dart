import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/application/startup_decision.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/identity/presentation/widgets/startup_loading_gate.dart';
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

  Widget buildStartupRouter({
    IdentityRepository? repoOverride,
    ContactRepository? contactRepoOverride,
    P2PService? p2pServiceOverride,
    ShareIntentService? shareIntentService,
    List<NavigatorObserver> navigatorObservers = const [],
  }) {
    return MaterialApp(
      navigatorObservers: navigatorObservers,
      home: StartupRouter(
        repository: repoOverride ?? identityRepo,
        contactRepository: contactRepoOverride ?? contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepo,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pServiceOverride ?? p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: noOpImageProcessor(),
        shareIntentService: shareIntentService,
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
    testWidgets(
      'shows bootstrap loading gate while startup decision is pending',
      (tester) async {
        final delayedRepo = _DelayedIdentityRepository(testIdentityWithMlKem);

        await tester.pumpWidget(buildStartupRouter(repoOverride: delayedRepo));
        await tester.pump();

        expect(find.byType(StartupLoadingGate), findsOneWidget);
        expect(find.text('Preparing your space...'), findsOneWidget);
        expect(find.text('Loading...'), findsNothing);
        expect(find.byIcon(Icons.lock), findsNothing);
        expect(find.byType(FeedWired), findsNothing);
        expect(find.text('Feed'), findsNothing);
        expect(find.text('Remember'), findsNothing);

        delayedRepo.complete();
        await pumpRouting(tester);
      },
    );

    testWidgets(
      'keeps bootstrap gate visible until startup route is committed',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final delayedContactRepo = _DelayedContactCountRepository();
        delayedContactRepo.seed([testContact]);

        await tester.pumpWidget(
          buildStartupRouter(contactRepoOverride: delayedContactRepo),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(find.byType(StartupLoadingGate), findsOneWidget);
        expect(find.byType(FeedWired), findsNothing);
        expect(find.text('Feed'), findsNothing);

        delayedContactRepo.complete();
        await pumpRouting(tester);

        expect(find.byType(FeedWired), findsOneWidget);
      },
    );

    testWidgets('routes to feed after showing opening feed stage', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      final delayedContactRepo = _DelayedContactCountRepository();
      delayedContactRepo.seed([testContact]);

      await tester.pumpWidget(
        buildStartupRouter(contactRepoOverride: delayedContactRepo),
      );
      await tester.pump();

      delayedContactRepo.complete();
      await tester.pump();

      expect(find.text('Opening Feed...'), findsOneWidget);

      await pumpRouting(tester);

      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets(
      'routes to first time experience after showing opening setup stage',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final delayedContactRepo = _DelayedContactCountRepository();

        await tester.pumpWidget(
          buildStartupRouter(contactRepoOverride: delayedContactRepo),
        );
        await tester.pump();

        delayedContactRepo.complete();
        await tester.pump();

        expect(find.text('Opening setup...'), findsOneWidget);

        await pumpRouting(tester);

        expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
      },
    );

    testWidgets('routes to onboarding after showing opening onboarding stage', (
      tester,
    ) async {
      final delayedRepo = _DelayedIdentityRepository(null);

      await tester.pumpWidget(buildStartupRouter(repoOverride: delayedRepo));
      await tester.pump();

      delayedRepo.complete();
      await tester.pump();

      expect(find.text('Opening onboarding...'), findsOneWidget);

      await pumpRouting(tester);

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
    });

    testWidgets('navigates to FeedWired when identity exists with contacts', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FeedWired), findsOneWidget);
    });

    testWidgets('settles and replays a buffered share after routing to feed', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'shared hello'),
      );

      await pumpAndRoute(
        tester,
        buildStartupRouter(shareIntentService: shareIntentService),
      );
      await tester.pump();

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('shared hello'), findsOneWidget);
    });

    testWidgets(
      'passes the share service into first-time experience when onboarding is still required',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final shareIntentService = ShareIntentService(resetShareIntent: () {});

        await pumpAndRoute(
          tester,
          buildStartupRouter(shareIntentService: shareIntentService),
        );

        final firstTimeWidget = tester.widget<FirstTimeExperienceWired>(
          find.byType(FirstTimeExperienceWired),
        );
        expect(firstTimeWidget.shareIntentService, same(shareIntentService));
      },
    );

    testWidgets(
      '5j: cold start + needsIdentity buffers intent without showing the picker',
      (tester) async {
        final shareIntentService = ShareIntentService(resetShareIntent: () {});
        await shareIntentService.bufferIntent(
          const ShareIntent(
            type: ShareIntentType.text,
            text: 'defer onboarding',
          ),
        );

        await pumpAndRoute(
          tester,
          buildStartupRouter(shareIntentService: shareIntentService),
        );

        expect(find.byType(IdentityChoiceWired), findsOneWidget);
        expect(find.text('Share with...'), findsNothing);
        expect(shareIntentService.isSettled, isFalse);
        expect(shareIntentService.hasPendingIntent, isTrue);
      },
    );

    testWidgets(
      '5k: cold start + hasIdentityNoContacts keeps the intent buffered until first contact',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final shareIntentService = ShareIntentService(resetShareIntent: () {});
        await shareIntentService.bufferIntent(
          const ShareIntent(
            type: ShareIntentType.text,
            text: 'wait for contact',
          ),
        );

        await pumpAndRoute(
          tester,
          buildStartupRouter(shareIntentService: shareIntentService),
        );

        expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
        expect(find.text('Share with...'), findsNothing);
        expect(shareIntentService.isSettled, isFalse);
        expect(shareIntentService.hasPendingIntent, isTrue);
      },
    );

    test(
      '5l: cold start + needsIdentity keeps cache-copied file paths buffered',
      () async {
        final tempDir = Directory.systemTemp.createTempSync('startup_share_');
        final originalDir = Directory('${tempDir.path}/original')
          ..createSync(recursive: true);
        final originalFile = File('${originalDir.path}/shared.jpg')
          ..writeAsStringSync('image');
        final shareIntentService = ShareIntentService(
          getCacheDirectory: () async => tempDir,
          resetShareIntent: () {},
        );
        await shareIntentService.bufferIntent(
          ShareIntent(
            type: ShareIntentType.files,
            filePaths: [originalFile.path],
          ),
        );

        final decision = await decideStartupRoute(
          identityRepo: identityRepo,
          contactRepo: contactRepo,
        );

        final pending = shareIntentService.consumePendingIntent();
        expect(decision, StartupDecision.needsIdentity);
        expect(pending, isNotNull);
        expect(pending!.filePaths.single, contains('share_cache'));
        expect(pending.filePaths.single, isNot(originalFile.path));
      },
    );

    testWidgets(
      'navigates to FirstTimeExperienceWired when identity exists no contacts',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);

        await pumpAndRoute(tester, buildStartupRouter());

        expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
      },
    );

    testWidgets('navigates to IdentityChoiceWired when no identity', (
      tester,
    ) async {
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

    testWidgets('starts P2P node after navigating to FeedWired', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(p2pService.startNodeCallCount, 1);
    });

    testWidgets('does not wait for p2p startup before route replacement', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);
      final delayedP2PService = _DelayedStartP2PService();

      await pumpAndRoute(
        tester,
        buildStartupRouter(p2pServiceOverride: delayedP2PService),
      );

      expect(find.byType(FeedWired), findsOneWidget);
      expect(delayedP2PService.startNodeEntered, isTrue);
      expect(delayedP2PService.startNodePending, isTrue);

      delayedP2PService.completeStart();
      await tester.pump();
    });

    testWidgets('starts P2P node after navigating to FTE', (tester) async {
      identityRepo.seed(testIdentityWithMlKem);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(p2pService.startNodeCallCount, 1);
    });

    testWidgets('shows error UI when repository throws', (tester) async {
      await pumpAndRoute(
        tester,
        buildStartupRouter(repoOverride: _ThrowingIdentityRepository()),
      );

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

    testWidgets('preserves retry flow after startup failure', (tester) async {
      final toggleRepo = _ToggleIdentityRepository();

      await pumpAndRoute(tester, buildStartupRouter(repoOverride: toggleRepo));

      expect(find.text('Failed to initialize'), findsOneWidget);

      toggleRepo.shouldThrow = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(find.byType(StartupLoadingGate), findsOneWidget);

      await pumpRouting(tester);

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
    });

    testWidgets('ML-KEM failure is non-fatal (still navigates)', (
      tester,
    ) async {
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

    testWidgets(
      'cold launch shows only bootstrap gate before feed route appears',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final delayedContactRepo = _DelayedContactCountRepository();
        delayedContactRepo.seed([testContact]);

        await tester.pumpWidget(
          buildStartupRouter(contactRepoOverride: delayedContactRepo),
        );
        await tester.pump();

        expect(find.byType(StartupLoadingGate), findsOneWidget);
        expect(find.byType(FeedWired), findsNothing);
        expect(find.text('Feed'), findsNothing);
        expect(find.text('Remember'), findsNothing);

        delayedContactRepo.complete();
        await pumpRouting(tester);
      },
    );

    testWidgets(
      'hot restart style delayed startup does not expose feed chrome before handoff',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final delayedContactRepo = _DelayedContactCountRepository();
        delayedContactRepo.seed([testContact]);

        await tester.pumpWidget(
          buildStartupRouter(contactRepoOverride: delayedContactRepo),
        );
        await tester.pump();

        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 32));
        }

        expect(find.byType(StartupLoadingGate), findsOneWidget);
        expect(find.text('Feed'), findsNothing);
        expect(find.text('Orbit'), findsNothing);
        expect(find.text('Remember'), findsNothing);

        delayedContactRepo.complete();
        await pumpRouting(tester);
      },
    );

    testWidgets('bootstrap gate disappears once feed route is visible', (
      tester,
    ) async {
      identityRepo.seed(testIdentityWithMlKem);
      contactRepo.seed([testContact]);

      await pumpAndRoute(tester, buildStartupRouter());

      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.byType(StartupLoadingGate), findsNothing);
    });

    testWidgets(
      'bootstrap gate does not block existing feed loading placeholders after handoff',
      (tester) async {
        identityRepo.seed(testIdentityWithMlKem);
        final feedLoadingContactRepo = _DelayedFeedLoadContactRepository();
        feedLoadingContactRepo.seed([testContact]);

        await pumpAndRoute(
          tester,
          buildStartupRouter(contactRepoOverride: feedLoadingContactRepo),
        );

        expect(find.byType(FeedWired), findsOneWidget);
        expect(find.byType(StartupLoadingGate), findsNothing);
        expect(
          find.byKey(const ValueKey('feed-loading-status')),
          findsOneWidget,
        );
        expect(find.text('Loading Feed...'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('feed-loading-card-0')),
          findsOneWidget,
        );

        feedLoadingContactRepo.completeFeedLoad();
        await pumpRouting(tester);
      },
    );
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

class _DelayedIdentityRepository extends FakeIdentityRepository {
  final Completer<void> _completer = Completer<void>();

  _DelayedIdentityRepository(IdentityModel? identity) {
    seed(identity);
  }

  void complete() {
    if (_completer.isCompleted) return;
    _completer.complete();
  }

  @override
  Future<IdentityModel?> loadIdentity() async {
    await _completer.future;
    return super.loadIdentity();
  }
}

class _DelayedContactCountRepository extends FakeContactRepository {
  final Completer<void> _completer = Completer<void>();

  void complete() {
    if (_completer.isCompleted) return;
    _completer.complete();
  }

  @override
  Future<int> getContactCount() async {
    await _completer.future;
    return super.getContactCount();
  }
}

class _DelayedFeedLoadContactRepository extends FakeContactRepository {
  final Completer<void> _feedLoadCompleter = Completer<void>();

  void completeFeedLoad() {
    if (_feedLoadCompleter.isCompleted) return;
    _feedLoadCompleter.complete();
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    await _feedLoadCompleter.future;
    return super.getActiveContacts();
  }
}

class _DelayedStartP2PService extends FakeP2PService {
  final Completer<void> _startCompleter = Completer<void>();
  bool startNodeEntered = false;

  bool get startNodePending => startNodeEntered && !_startCompleter.isCompleted;

  void completeStart() {
    if (_startCompleter.isCompleted) return;
    _startCompleter.complete();
  }

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async {
    startNodeEntered = true;
    startNodeCallCount++;
    lastStartNodePrivateKey = privateKeyBase64;
    lastStartNodePeerId = peerId;
    await _startCompleter.future;
    return startNodeResult;
  }
}
