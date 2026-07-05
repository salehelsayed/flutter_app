import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart'
    show ConversationWired;
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_screen.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_contact_presence_snapshot_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

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
  late InMemoryContactPresenceSnapshotRepository
  contactPresenceSnapshotRepository;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;
  late ContactRequestListener contactRequestListener;
  late ChatMessageListener chatMessageListener;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late _FakeNearbyLocationService nearbyLocationService;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
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
    contactPresenceSnapshotRepository =
        InMemoryContactPresenceSnapshotRepository();
    mediaFileManager = FakeMediaFileManager();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    nearbyLocationService = _FakeNearbyLocationService();
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

    // Mock path_provider channel
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
    postsPrivacySettingsRepository.dispose();
    contactPresenceSnapshotRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  // 214: the post-accept landing now mounts the embedded Orbit pane, whose
  // chrome raises the same benign asset/overflow noise feed_wired_test
  // suppresses when it pumps OrbitWired.
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

  Widget buildFTE({
    ContactRequestListener? overrideListener,
    ShareIntentService? shareIntentService,
    AccountMigrationTransferRunFn? accountMigrationRunTransfer,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FirstTimeExperienceWired(
        repository: identityRepo,
        contactRepository: contactRepo,
        contactRequestRepository: contactRequestRepo,
        contactRequestListener: overrideListener ?? contactRequestListener,
        messageRepository: messageRepo,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepo,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        imageProcessor: imageProcessor,
        secureKeyStore: secureKeyStore,
        shareIntentService: shareIntentService,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        feedClearedRepository: InMemoryFeedClearedRepository(),
        contactPresenceSnapshotRepository: contactPresenceSnapshotRepository,
        nearbyLocationService: nearbyLocationService,
        accountMigrationRunTransfer: accountMigrationRunTransfer,
      ),
    );
  }

  group('FirstTimeExperienceWired', () {
    testWidgets('shows QR shimmer before post-frame QR generation completes', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());

      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);
      expect(find.byType(QrImageView), findsNothing);
    });

    testWidgets('loads identity and generates QR data after first frame', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump(); // trigger post-frame callback
      await tester.pump(); // let async resolve

      // Identity was loaded
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));
      // Bridge was called for signing
      expect(bridge.sendCallCount, greaterThanOrEqualTo(1));
      expect(bridge.lastCommand, 'payload.sign');

      // The widget rendered without errors — find the screen
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);
    });

    testWidgets('replaces shimmer with QR image after QR data loads', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsOneWidget);

      await tester.pump();
      await tester.pump();

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.byKey(const ValueKey('qr-loading-shimmer')), findsNothing);
    });

    testWidgets('displays username from loaded identity', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // The EditableUsernameWidget shows 'mknoon/' prefix and '@Alice'
      expect(find.textContaining('Alice'), findsOneWidget);
    });

    testWidgets('updates username and regenerates QR', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Verify initial username is displayed
      expect(find.textContaining('Alice'), findsOneWidget);

      // Tap on the username area to start editing (GestureDetector wrapping the username row)
      await tester.tap(find.textContaining('Alice'));
      await tester.pump();

      // Now a TextField should be visible for editing
      final textFieldFinder = find.byType(TextField);
      expect(textFieldFinder, findsOneWidget);

      // Clear and type new username
      await tester.enterText(textFieldFinder, 'Bob');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      // Identity should have been saved with new username
      expect(identityRepo.saveIdentityCallCount, greaterThanOrEqualTo(1));
      expect(identityRepo.lastSavedIdentity?.username, 'Bob');

      // Bridge should be called again for QR regeneration (2 total: initial + after rename)
      expect(bridge.sendCallCount, greaterThanOrEqualTo(2));
    });

    testWidgets('scan button exists and is tappable', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // The ScanFriendCard contains the text "Scan a friend's code"
      final scanCardFinder = find.text("Scan a friend's code");
      expect(scanCardFinder, findsOneWidget);

      // Also verify the arrow icon exists (part of ScanFriendCard)
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);

      // Verify the crop_free icon (the scan icon) is present
      expect(find.byIcon(Icons.crop_free), findsOneWidget);
    });

    testWidgets('scan routes Move Account QR to old-phone migration', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      final createdAt = DateTime.now().toUtc();
      final migrationQr = MigrationQrPayload(
        sessionId: 'fte-migration-session',
        createdAt: createdAt,
        expiresAt: createdAt.add(const Duration(minutes: 5)),
        newPhoneEphemeralPublicKey: 'new-phone-ephemeral-public',
        channelNonce: 'fte-channel-nonce',
      ).toJsonString();

      Future<AccountMigrationTransferResult> runner({
        required AccountMigrationTransferRequest request,
        required AccountMigrationTransferProgressCallback onProgress,
        required bool Function() isCancelled,
        AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
      }) async {
        return const AccountMigrationTransferResult.success();
      }

      await tester.pumpWidget(buildFTE(accountMigrationRunTransfer: runner));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text("Scan a friend's code"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(migrationQr);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final journey = tester.widget<AccountMigrationJourneyWired>(
        find.byType(AccountMigrationJourneyWired),
      );
      expect(journey.runTransfer, same(runner));
      expect(journey.initialScannedQr, migrationQr);
    });

    testWidgets('does not crash when contact request stream emits', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      // Create a controllable request stream that emits ContactRequestModel directly
      final requestController =
          StreamController<ContactRequestModel>.broadcast();

      // Build a custom ContactRequestListener that we can emit on.
      // Instead of going through the raw ChatMessage processing pipeline,
      // we directly test the widget's subscription by using a listener
      // whose requestStream we control.
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      Future<AccountMigrationTransferResult> runner({
        required AccountMigrationTransferRequest request,
        required AccountMigrationTransferProgressCallback onProgress,
        required bool Function() isCancelled,
        AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
      }) async {
        return const AccountMigrationTransferResult.success();
      }

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          accountMigrationRunTransfer: runner,
        ),
      );
      await tester.pump();
      await tester.pump();

      // Emit a contact request on the stream
      final request = ContactRequestModel(
        peerId: 'sender-peer-id-1234567890',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );

      requestController.add(request);
      await tester.pump();
      await tester.pump();

      // The ContactRequestDialog should appear with the username
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('wants to connect with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);

      await requestController.close();
    });

    testWidgets('handles missing identity gracefully', (tester) async {
      // Do NOT seed any identity — loadIdentity will return null
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Should not crash — screen renders with default state
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);

      // Identity was attempted to be loaded
      expect(identityRepo.loadIdentityCallCount, greaterThanOrEqualTo(1));

      // Bridge should NOT have been called (no identity => no signing needed)
      expect(bridge.sendCallCount, 0);

      // Username should be the default 'Username'
      expect(find.textContaining('Username'), findsOneWidget);
    });

    testWidgets('displays QR data in screen after payload build', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // After successful build, the FirstTimeExperienceScreen should have
      // non-null qrData. We can verify this by checking that the QrImageView
      // widget is present (it's rendered when qrData is non-null).
      // The QRCodeSection shows a QrImageView when data is provided.
      expect(find.byType(FirstTimeExperienceScreen), findsOneWidget);

      // When qrData is null, a shimmer/loading is shown.
      // When qrData is non-null, a QrImageView is rendered.
      // Find the QrImageView widget from qr_flutter package.
      // Since the import is from qr_flutter, let's look for it by type name.
      final qrImageFinder = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == 'QrImageView',
      );
      expect(qrImageFinder, findsOneWidget);
    });

    testWidgets('disposes subscription without errors', (tester) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      await tester.pumpWidget(buildFTE());
      await tester.pump();
      await tester.pump();

      // Now replace the widget to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('replaced'))),
      );
      await tester.pump();

      // If dispose throws, the test would fail. Reaching here means success.
      expect(find.text('replaced'), findsOneWidget);
    });

    testWidgets('accept success settles and replays a buffered share', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephemeral-pk',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      };

      final request = ContactRequestModel(
        peerId: 'sender-peer-id-1234567890',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRequestRepo.seed([request]);

      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'from onboarding'),
      );

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          shareIntentService: shareIntentService,
        ),
      );
      await tester.pump();
      await tester.pump();

      requestController.add(request);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('from onboarding'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await requestController.close();
    });

    testWidgets('notPending still settles and replays a buffered share', (
      tester,
    ) async {
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};

      final acceptedRequest = ContactRequestModel(
        peerId: 'sender-peer-id-accepted',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
        status: ContactRequestStatus.accepted,
      );
      contactRequestRepo.seed([acceptedRequest]);
      await contactRepo.addContact(acceptedRequest.toContactModel());

      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'already added'),
      );

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          shareIntentService: shareIntentService,
        ),
      );
      await tester.pump();
      await tester.pump();

      requestController.add(acceptedRequest);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(shareIntentService.isSettled, isTrue);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('already added'), findsOneWidget);

      // 214: the shell underneath now mounts the Orbit pane, whose avatars
      // schedule zero-duration timers on mount — flush them before teardown.
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await requestController.close();
    });

    testWidgets(
      '5o: accept success without buffered intent lands on the Orbit surface',
      (tester) async {
        suppressShellRenderErrors();
        identityRepo.seed(testIdentity);
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'test-sig',
        };
        bridge.responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-pk',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        };

        final request = ContactRequestModel(
          peerId: 'sender-peer-id-feed-only',
          publicKey: 'sender-pub-key',
          rendezvous: '/p2p-circuit/relay',
          username: 'Charlie',
          signature: 'sender-sig',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
        );
        contactRequestRepo.seed([request]);

        final requestController =
            StreamController<ContactRequestModel>.broadcast();
        final customListener = _FakeContactRequestListener(
          requestStream: requestController.stream,
        );
        final shareIntentService = ShareIntentService(resetShareIntent: () {});

        await tester.pumpWidget(
          buildFTE(
            overrideListener: customListener,
            shareIntentService: shareIntentService,
          ),
        );
        await tester.pump();
        await tester.pump();

        requestController.add(request);
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Accept'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        expect(shareIntentService.isSettled, isTrue);
        expect(shareIntentService.hasPendingIntent, isFalse);
        // 214 discriminating triple: the shell replaces the FTE route AND it
        // renders the Orbit pane (Orbit is the main screen).
        expect(find.byType(FeedWired), findsOneWidget);
        expect(appShellController.activeTab, AppShellTab.orbit);
        expect(find.byType(OrbitWired), findsOneWidget);
        expect(find.text('Share with...'), findsNothing);

        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        await requestController.close();
      },
    );

    // 215 TC-06: accepting the first request establishes the Feed shell AND
    // pushes the new contact's 1:1 chat ON TOP (two-push, not a shell-replace),
    // then settles the share flow last.
    testWidgets(
      'accepting the first request lands on Feed AND opens the new contact chat on top',
      (tester) async {
        suppressShellRenderErrors();
        identityRepo.seed(testIdentity);
        bridge.responses['payload.sign'] = {
          'ok': true,
          'signature': 'test-sig',
        };
        bridge.responses['contactrequest.encrypt'] = {
          'ok': true,
          'ephemeralPublicKey': 'ephemeral-pk',
          'ciphertext': 'ciphertext',
          'nonce': 'nonce',
        };

        final request = ContactRequestModel(
          peerId: 'sender-peer-id-chat',
          publicKey: 'sender-pub-key',
          rendezvous: '/p2p-circuit/relay',
          username: 'Charlie',
          signature: 'sender-sig',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
        );
        contactRequestRepo.seed([request]);

        final requestController =
            StreamController<ContactRequestModel>.broadcast();
        final customListener = _FakeContactRequestListener(
          requestStream: requestController.stream,
        );
        final shareIntentService = ShareIntentService(resetShareIntent: () {});

        await tester.pumpWidget(
          buildFTE(
            overrideListener: customListener,
            shareIntentService: shareIntentService,
          ),
        );
        await tester.pump();
        await tester.pump();

        requestController.add(request);
        await tester.pump();
        await tester.pump();

        await tester.tap(find.text('Accept'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();

        // The chat rides ON TOP of the established Feed shell.
        expect(find.byType(ConversationWired), findsOneWidget);
        expect(
          tester
              .widget<ConversationWired>(find.byType(ConversationWired))
              .contact
              .peerId,
          request.peerId,
        );
        // Feed shell preserved underneath (offstage under the opaque chat
        // route) — proves two-push, not a shell-replacing chat.
        expect(find.byType(FeedWired, skipOffstage: false), findsOneWidget);
        expect(appShellController.activeTab, AppShellTab.orbit);

        await tester.pump(const Duration(seconds: 5));
        await tester.pump();
        await requestController.close();
      },
    );

    testWidgets('accept success forwards nearby dependencies into feed', (
      tester,
    ) async {
      suppressShellRenderErrors();
      identityRepo.seed(testIdentity);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephemeral-pk',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      };

      final request = ContactRequestModel(
        peerId: 'sender-peer-id-nearby',
        publicKey: 'sender-pub-key',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'sender-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRequestRepo.seed([request]);

      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      final customListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      Future<AccountMigrationTransferResult> runner({
        required AccountMigrationTransferRequest request,
        required AccountMigrationTransferProgressCallback onProgress,
        required bool Function() isCancelled,
        AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
      }) async {
        return const AccountMigrationTransferResult.success();
      }

      await tester.pumpWidget(
        buildFTE(
          overrideListener: customListener,
          accountMigrationRunTransfer: runner,
        ),
      );
      await tester.pump();
      await tester.pump();

      requestController.add(request);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Accept'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      final feedWired = tester.widget<FeedWired>(find.byType(FeedWired));
      expect(
        feedWired.contactPresenceSnapshotRepository,
        same(contactPresenceSnapshotRepository),
      );
      expect(feedWired.nearbyLocationService, same(nearbyLocationService));
      expect(feedWired.accountMigrationRunTransfer, same(runner));
      // 214: the forwarded shell lands on the Orbit surface.
      expect(appShellController.activeTab, AppShellTab.orbit);
      expect(find.byType(OrbitWired), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      await requestController.close();
    });
  });
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

/// A minimal fake that exposes a controllable [requestStream] without
/// needing to process raw ChatMessages through the real listener pipeline.
class _FakeContactRequestListener extends ContactRequestListener {
  final Stream<ContactRequestModel> _overrideStream;

  _FakeContactRequestListener({
    required Stream<ContactRequestModel> requestStream,
  }) : _overrideStream = requestStream,
       super(
         contactRequestStream: const Stream<ChatMessage>.empty(),
         requestRepo: _NoOpContactRequestRepo(),
         contactRepo: _NoOpContactRepo(),
         bridge: FakeBridge(),
         getOwnPeerId: () => '',
       );

  @override
  Stream<ContactRequestModel> get requestStream => _overrideStream;
}

/// Minimal no-op repos for the fake listener constructor.
class _NoOpContactRequestRepo extends FakeContactRequestRepository {}

class _NoOpContactRepo extends FakeContactRepository {}
