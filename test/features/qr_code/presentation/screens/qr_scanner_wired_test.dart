import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/theme/app_theme.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_wired.dart';
import 'package:flutter_app/features/settings/application/download_profile_picture_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryContactRepository contactRepository;
  late FakeContactRequestRepository contactRequestRepository;
  late ContactRequestListener contactRequestListener;
  late InMemoryMessageRepository messageRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late ChatMessageListener chatMessageListener;
  late FakeIdentityRepository identityRepository;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late ImageProcessor imageProcessor;

  const ownPeerId = 'own-peer-id-12345';

  final identity = IdentityModel(
    peerId: ownPeerId,
    publicKey: 'own-public-key',
    privateKey: 'own-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  setUp(() {
    bridge = FakeBridge();
    bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'fakeSig'};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephPubBase64',
      'ciphertext': 'ctBase64',
      'nonce': 'nonceBase64',
    };
    contactRepository = InMemoryContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => ownPeerId,
    );
    messageRepository = InMemoryMessageRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
    );
    identityRepository = FakeIdentityRepository()..seed(identity);
    p2pService = FakeP2PService();
    mediaFileManager = FakeMediaFileManager();
    secureKeyStore = FakeSecureKeyStore();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
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
  });

  Widget buildScanner({
    ShareIntentService? shareIntentService,
    Future<void> Function(String qrData)? onMigrationQrScanned,
    AccountMigrationTransferRunFn? accountMigrationRunTransfer,
    DownloadProfilePictureFn? downloadProfilePictureFn,
    ThemeData? themeOverride,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: themeOverride,
      home: QRScannerWired(
        bridge: bridge,
        contactRepository: contactRepository,
        contactRequestRepository: contactRequestRepository,
        contactRequestListener: contactRequestListener,
        messageRepository: messageRepository,
        postRepository: postRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        identityRepository: identityRepository,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        feedClearedRepository: InMemoryFeedClearedRepository(),
        ownPeerId: ownPeerId,
        onMigrationQrScanned: onMigrationQrScanned,
        accountMigrationRunTransfer: accountMigrationRunTransfer,
        downloadProfilePictureFn:
            downloadProfilePictureFn ??
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
            }) async => null,
        shareIntentService: shareIntentService,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // 214: the post-scan landing now mounts the embedded Orbit pane, whose
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

  testWidgets('contact scanner keeps default contact copy', (tester) async {
    await tester.pumpWidget(buildScanner());
    await pumpFrames(tester);

    expect(find.text('Scan QR Code'), findsOneWidget);
    expect(
      find.text("Point your camera at a friend's QR code"),
      findsOneWidget,
    );
    expect(find.text("They'll be added to your circle"), findsOneWidget);
    expect(find.text('Paste QR Data'), findsOneWidget);
    expect(find.text('Scan migration QR'), findsNothing);
    expect(
      find.text('Point your camera at the Move Account QR on your new phone'),
      findsNothing,
    );
  });

  testWidgets('scanner is tuned for fast QR-only detection', (tester) async {
    await tester.pumpWidget(buildScanner());
    await pumpFrames(tester);

    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    final controller = scanner.controller!;

    expect(controller.detectionSpeed, DetectionSpeed.noDuplicates);
    expect(controller.formats, [BarcodeFormat.qrCode]);
    expect(controller.cameraResolution, const Size(1280, 720));
  });

  // TC-248-24 (GREEN sentinel): the scanner is a deliberate dark exception. Even
  // under a Signal light root it stays black with white camera chrome and
  // QR-only detection.
  testWidgets('Signal root keeps scanner black with white camera chrome', (
    tester,
  ) async {
    await tester.pumpWidget(buildScanner(themeOverride: AppTheme.lightTheme));
    await pumpFrames(tester);

    // The root really is the Signal light theme...
    final rootContext = tester.element(find.byType(QRScannerWired));
    expect(Theme.of(rootContext).brightness, Brightness.light);

    // ...yet the scanner scaffold stays black with the live camera chrome.
    final blackScaffold = tester
        .widgetList<Scaffold>(find.byType(Scaffold))
        .any((s) => s.backgroundColor == Colors.black);
    expect(blackScaffold, isTrue, reason: 'scanner scaffold stays black');
    expect(find.byType(MobileScanner), findsOneWidget);

    // QR-only detection is preserved.
    final scanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
    expect(scanner.controller!.formats, [BarcodeFormat.qrCode]);
  });

  testWidgets(
    'migration QR dispatches to migration handler without contact side effects',
    (tester) async {
      final scannedMigrationPayloads = <String>[];
      var downloadCalls = 0;
      final qrData = _buildMigrationQrData();

      await tester.pumpWidget(
        buildScanner(
          onMigrationQrScanned: (rawQrData) async {
            scannedMigrationPayloads.add(rawQrData);
          },
          downloadProfilePictureFn:
              ({
                required bridge,
                required contactRepo,
                required ownerPeerId,
                required avatarVersion,
              }) async {
                downloadCalls++;
                return null;
              },
        ),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(qrData);
      await pumpFrames(tester);

      expect(scannedMigrationPayloads, [qrData]);
      expect(await contactRepository.getContactCount(), 0);
      expect(downloadCalls, 0);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('contactrequest.encrypt')));
      expect(find.text('Added to your circle!'), findsNothing);
    },
  );

  testWidgets(
    'migration QR without handler fails safely without contact side effects',
    (tester) async {
      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(_buildMigrationQrData());
      await pumpFrames(tester);

      expect(await contactRepository.getContactCount(), 0);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('contactrequest.encrypt')));
      expect(find.text('Added to your circle!'), findsNothing);
    },
  );

  testWidgets(
    'contact QR sends an encrypted request and isolates profile download failure',
    (tester) async {
      const scannedPeerId = 'encrypted-peer-12345';
      String? downloadedOwnerPeerId;
      p2pService.emitState(const NodeState(isStarted: true, peerId: ownPeerId));
      p2pService.storeInInboxResult = true;

      await tester.pumpWidget(
        buildScanner(
          downloadProfilePictureFn:
              ({
                required bridge,
                required contactRepo,
                required ownerPeerId,
                required avatarVersion,
              }) async {
                downloadedOwnerPeerId = ownerPeerId;
                throw StateError('profile download failed');
              },
        ),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(
        _buildValidQrData(
          peerId: scannedPeerId,
          publicKey: 'scanned-encryption-public-key',
          username: 'Bob',
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Added to your circle!'), findsOneWidget);
      final contact = await contactRepository.getContact(scannedPeerId);
      expect(contact, isNotNull);
      expect(contact?.username, 'Bob');
      expect(downloadedOwnerPeerId, scannedPeerId);

      final signIndex = bridge.commandLog.indexOf('payload.sign');
      final encryptIndex = bridge.commandLog.indexOf('contactrequest.encrypt');
      expect(signIndex, greaterThanOrEqualTo(0));
      expect(encryptIndex, greaterThan(signIndex));

      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, scannedPeerId);
      final storedMessage = p2pService.lastStoreInInboxMessage;
      expect(storedMessage, isNotNull);
      final envelope = jsonDecode(storedMessage!) as Map<String, dynamic>;
      expect(envelope['type'], 'contact_request');
      expect(envelope['version'], '2');
      expect(envelope['encrypted'], {
        'ephemeralPublicKey': 'ephPubBase64',
        'ciphertext': 'ctBase64',
        'nonce': 'nonceBase64',
      });
      expect(envelope.containsKey('payload'), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '5p: QR scan success with buffered intent navigates to feed and pushes picker',
    (tester) async {
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'from qr'),
      );

      await tester.pumpWidget(
        buildScanner(shareIntentService: shareIntentService),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(_buildValidQrData());
      await pumpFrames(tester);

      expect(find.text('Added to your circle!'), findsOneWidget);
      final okButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'OK'),
      );
      expect(okButton.style?.foregroundColor?.resolve({}), Colors.black);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, count: 20);

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('from qr'), findsOneWidget);
    },
  );

  testWidgets(
    '5q: QR scan success without buffered intent lands on the Orbit surface',
    (tester) async {
      suppressShellRenderErrors();
      final shareIntentService = ShareIntentService(resetShareIntent: () {});

      await tester.pumpWidget(
        buildScanner(shareIntentService: shareIntentService),
      );
      await pumpFrames(tester);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(
        _buildValidQrData(peerId: 'new-peer-12345', username: 'Bob'),
      );
      await pumpFrames(tester);

      expect(find.text('Added to your circle!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpFrames(tester, count: 20);

      expect(shareIntentService.isSettled, isTrue);
      expect(shareIntentService.hasPendingIntent, isFalse);
      // 214 discriminating triple: the shell root survives the stack nuke AND
      // it renders the Orbit pane (Orbit is the main screen).
      expect(find.byType(FeedWired), findsOneWidget);
      expect(appShellController.activeTab, AppShellTab.orbit);
      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.text('Share with...'), findsNothing);
    },
  );

  testWidgets('contact QR success forwards Move Account runner into feed', (
    tester,
  ) async {
    final shareIntentService = ShareIntentService(resetShareIntent: () {});
    Future<AccountMigrationTransferResult> runner({
      required AccountMigrationTransferRequest request,
      required AccountMigrationTransferProgressCallback onProgress,
      required bool Function() isCancelled,
      AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
    }) async {
      return const AccountMigrationTransferResult.success();
    }

    await tester.pumpWidget(
      buildScanner(
        shareIntentService: shareIntentService,
        accountMigrationRunTransfer: runner,
      ),
    );
    await pumpFrames(tester);

    final scanner = tester.widget<QRScannerScreen>(
      find.byType(QRScannerScreen),
    );
    scanner.onScanned(
      _buildValidQrData(peerId: 'runner-peer-12345', username: 'Bob'),
    );
    await pumpFrames(tester);

    expect(find.text('Added to your circle!'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, count: 20);

    final feedWired = tester.widget<FeedWired>(find.byType(FeedWired));
    expect(feedWired.accountMigrationRunTransfer, same(runner));
  });
}

String _buildMigrationQrData({
  String sessionId = 'mig-session-1',
  String createdAt = '2026-01-01T12:00:00.000Z',
  String expiresAt = '2026-01-01T12:05:00.000Z',
}) {
  return jsonEncode({
    'kind': accountMigrationPairingQrKind,
    'version': currentAccountMigrationPairingQrVersion,
    'sessionId': sessionId,
    'createdAt': createdAt,
    'expiresAt': expiresAt,
    'newPhoneEphemeralPublicKey': 'new-phone-mlkem-public',
  });
}

String _buildValidQrData({
  String peerId = 'scanned-peer-id',
  String publicKey = 'scanned-pk',
  String username = 'Bob',
}) {
  final payload = SplayTreeMap<String, dynamic>.from({
    'ns': peerId,
    'pk': publicKey,
    'rv': '/dns4/relay/tcp/443/p2p/relay',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': username,
  });
  payload['sig'] = 'valid-sig';
  return jsonEncode(payload);
}
