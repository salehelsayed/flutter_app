import 'dart:async';
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
import 'package:flutter_app/features/contact_request/application/mlkem_reannounce_marker.dart';
import 'package:flutter_app/features/contact_request/application/retry_incomplete_key_exchanges_use_case.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
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
import '../../../../shared/fakes/ed25519_contact_request_crypto.dart';
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
    Future<void> Function(String qrData)? onDirectLinkedDeviceQrScanned,
    AccountMigrationTransferRunFn? accountMigrationRunTransfer,
    DownloadProfilePictureFn? downloadProfilePictureFn,
    ThemeData? themeOverride,
    Future<bool> Function(String peerId)? shouldMarkContactRequest,
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
        onDirectLinkedDeviceQrScanned: onDirectLinkedDeviceQrScanned,
        accountMigrationRunTransfer: accountMigrationRunTransfer,
        downloadProfilePictureFn:
            downloadProfilePictureFn ??
            ({
              required bridge,
              required contactRepo,
              required ownerPeerId,
              required avatarVersion,
              bool retryPendingRequest = false,
            }) async => null,
        shareIntentService: shareIntentService,
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        shouldMarkContactRequest:
            shouldMarkContactRequest ?? (_) async => false,
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
                bool retryPendingRequest = false,
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
    'offline QR add keeps automatic request recovery before local success',
    (tester) async {
      final scanned = _fx('new');

      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(_buildValidQrData(identity: scanned));
      await pumpFrames(tester, count: 20);

      // The confirmation describes the completed local add. An offline
      // reciprocal request must remain owned by reconnect/resume recovery.
      expect(await contactRepository.getContact(scanned.peerId), isNotNull);
      expect(find.text('Added to your circle!'), findsOneWidget);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(
        await readMlKemReannounceMarker(secureKeyStore),
        contains(scanned.peerId),
      );
    },
  );

  testWidgets(
    'failed QR rescan of a keyed contact is redriven by key exchange recovery',
    (tester) async {
      final scanned = _fx('existing');
      final existing = ContactModel(
        peerId: scanned.peerId,
        publicKey: scanned.publicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob (stored)',
        signature: 'stored-sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        mlKemPublicKey: 'their-mlkem',
      );
      contactRepository.addTestContact(existing);
      identityRepository.seed(
        IdentityModel.fromJson({
          ...identity.toJson(),
          'mlKemPublicKey': 'own-mlkem',
        }),
      );
      p2pService.emitState(const NodeState(isStarted: true, peerId: ownPeerId));
      p2pService.storeInInboxResult = false;

      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(_buildValidQrData(identity: scanned));
      await pumpFrames(tester, count: 20);

      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(p2pService.storeInInboxCallCount, 1);
      p2pService.storeInInboxResult = true;
      expect(
        await retryIncompleteKeyExchanges(
          contactRepo: contactRepository,
          identityRepo: identityRepository,
          p2pService: p2pService,
          bridge: bridge,
          secureKeyStore: secureKeyStore,
        ),
        1,
      );
      expect(p2pService.storeInInboxCallCount, 2);
      expect(await readMlKemReannounceMarker(secureKeyStore), isEmpty);
      expect(await contactRepository.getContactCount(), 1);
      expect(
        (await contactRepository.getContact(scanned.peerId))!.toMap(),
        existing.toMap(),
      );
    },
  );

  testWidgets(
    'contact QR sends an encrypted request and isolates profile download failure',
    (tester) async {
      final scannedPeerId = _fx('encrypted').peerId;
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
                bool retryPendingRequest = false,
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
        _buildValidQrData(identity: _fx('encrypted'), username: 'Bob'),
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
    'scanning an existing contact shows the circle dialog and re-sends our '
    'request without touching the stored row',
    (tester) async {
      final existingPeerId = _fx('existing').peerId;
      final existing = ContactModel(
        peerId: existingPeerId,
        publicKey: _fx('existing').publicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob (stored)',
        signature: 'stored-sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );
      contactRepository.addTestContact(existing);
      var downloadCalls = 0;
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
                bool retryPendingRequest = false,
              }) async {
                downloadCalls++;
                return null;
              },
        ),
      );
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(
            _buildValidQrData(identity: _fx('existing'), username: 'Bob'),
          );
      await pumpFrames(tester, count: 20);

      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(find.text('Added to your circle!'), findsNothing);

      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, existingPeerId);
      final envelope =
          jsonDecode(p2pService.lastStoreInInboxMessage!)
              as Map<String, dynamic>;
      expect(envelope['type'], 'contact_request');
      expect(envelope['version'], '2');
      expect(envelope['intent'], 'new_request');
      expect(_contactRequestRecipientKeys(bridge), [_fx('existing').publicKey]);

      // No profile download, no delete, no duplicate, no overwrite.
      expect(downloadCalls, 0);
      expect(await contactRepository.getContactCount(), 1);
      expect(
        (await contactRepository.getContact(existingPeerId))!.toMap(),
        existing.toMap(),
      );
    },
  );

  testWidgets(
    'a QR that claims a stored contact with a different key fails the '
    'identity binding and encrypts nothing',
    (tester) async {
      final existingPeerId = _fx('existing').peerId;
      final existing = ContactModel(
        peerId: existingPeerId,
        publicKey: _fx('existing').publicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Bob (stored)',
        signature: 'stored-sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
      );
      contactRepository.addTestContact(existing);
      p2pService.emitState(const NodeState(isStarted: true, peerId: ownPeerId));
      p2pService.storeInInboxResult = true;

      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(
            _buildValidQrData(
              identity: _fx('existing'),
              publicKeyOverride: _fx('untrusted').publicKey,
            ),
          );
      await pumpFrames(tester, count: 20);

      expect(find.text('Invalid Signature'), findsOneWidget);
      expect(find.text('Already in your circle!'), findsNothing);
      expect(_contactRequestRecipientKeys(bridge), isEmpty);
      expect(p2pService.storeInInboxCallCount, 0);
      expect(await contactRepository.getContactCount(), 1);
      expect(
        (await contactRepository.getContact(existingPeerId))!.toMap(),
        existing.toMap(),
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(_buildValidQrData(identity: _fx('existing')));
      await pumpFrames(tester, count: 20);
      expect(_contactRequestRecipientKeys(bridge), [_fx('existing').publicKey]);
      expect(p2pService.storeInInboxCallCount, 1);
    },
  );

  // Task 12b, owner decision 1(a): only a peer verified as updated gets the
  // signed repair marker; any other peer gets today's unmarked request.
  for (final eligible in [true, false]) {
    testWidgets(
      're-scanning an existing contact ${eligible ? 'verified as updated sends '
                'a signed new_request marker' : 'not verified as updated sends '
                'an unmarked request'}',
      (tester) async {
        final existing = ContactModel(
          peerId: _fx('existing').peerId,
          publicKey: _fx('existing').publicKey,
          rendezvous: '/dns4/relay/tcp/443/p2p/relay',
          username: 'Bob (stored)',
          signature: 'stored-sig',
          scannedAt: '2026-01-01T00:00:00.000Z',
        );
        contactRepository.addTestContact(existing);
        p2pService.emitState(
          const NodeState(isStarted: true, peerId: ownPeerId),
        );
        p2pService.storeInInboxResult = true;
        final asked = <String>[];

        await tester.pumpWidget(
          buildScanner(
            shouldMarkContactRequest: (peerId) async {
              asked.add(peerId);
              return eligible;
            },
          ),
        );
        await pumpFrames(tester);
        tester
            .widget<QRScannerScreen>(find.byType(QRScannerScreen))
            .onScanned(_buildValidQrData(identity: _fx('existing')));
        await pumpFrames(tester, count: 20);

        expect(asked, [existing.peerId]);
        final encrypt = bridge.sentMessages
            .map((m) => jsonDecode(m) as Map<String, dynamic>)
            .singleWhere((r) => r['cmd'] == 'contactrequest.encrypt');
        final payload =
            jsonDecode(
                  (encrypt['payload'] as Map<String, dynamic>)['plaintext']
                      as String,
                )
                as Map<String, dynamic>;
        if (eligible) {
          final cr = payload['cr'] as Map<String, dynamic>;
          expect(cr['kind'], 'new_request');
          expect(cr['to'], existing.peerId);
          final envelope =
              jsonDecode(p2pService.lastStoreInInboxMessage!)
                  as Map<String, dynamic>;
          expect(envelope['msgId'], cr['id']);
        } else {
          expect(payload.containsKey('cr'), isFalse);
        }
      },
    );
  }

  testWidgets(
    'scanning a blocked contact shows the circle dialog and sends nothing',
    (tester) async {
      final openPeerId = _fx('open').peerId;
      final blockedPeerId = _fx('blocked').peerId;
      final blocked = ContactModel(
        peerId: blockedPeerId,
        publicKey: _fx('blocked').publicKey,
        rendezvous: '/dns4/relay/tcp/443/p2p/relay',
        username: 'Mallory',
        signature: 'blocked-sig',
        scannedAt: '2026-01-01T00:00:00.000Z',
        isBlocked: true,
        blockedAt: '2026-01-02T00:00:00.000Z',
      );
      contactRepository
        ..addTestContact(
          ContactModel(
            peerId: openPeerId,
            publicKey: _fx('open').publicKey,
            rendezvous: '/dns4/relay/tcp/443/p2p/relay',
            username: 'Bob',
            signature: 'open-sig',
            scannedAt: '2026-01-01T00:00:00.000Z',
          ),
        )
        ..addTestContact(blocked);
      p2pService.emitState(const NodeState(isStarted: true, peerId: ownPeerId));
      p2pService.storeInInboxResult = true;

      // Control: the open contact's re-scan does send, so the silence below
      // is the blocked branch and not a dead send path.
      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(_buildValidQrData(identity: _fx('open')));
      await pumpFrames(tester, count: 20);
      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, openPeerId);

      // Tear the first scanner down so its dialog is gone before the second.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(_buildValidQrData(identity: _fx('blocked')));
      await pumpFrames(tester, count: 20);

      expect(find.text('Already in your circle!'), findsOneWidget);
      expect(p2pService.storeInInboxCallCount, 1);
      expect(p2pService.lastStoreInInboxPeerId, openPeerId);
      expect(await contactRepository.getContactCount(), 2);
      expect(
        await readMlKemReannounceMarker(secureKeyStore),
        isNot(contains(blockedPeerId)),
      );
      expect(
        (await contactRepository.getContact(blockedPeerId))!.toMap(),
        blocked.toMap(),
      );
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
        _buildValidQrData(identity: _fx('new'), username: 'Bob'),
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

  testWidgets('a scan finishes after the scanner route has already closed', (
    tester,
  ) async {
    // The scanner pops itself as soon as it reports a code. Signature
    // verification can outlast that close (always, with system animations
    // off); the contact, its request and the "added" hand-off must survive.
    suppressShellRenderErrors();
    p2pService.emitState(const NodeState(isStarted: true, peerId: ownPeerId));
    p2pService.storeInInboxResult = true;
    final gatedBridge = _VerifyGatedBridge()
      ..responses.addAll(bridge.responses);
    bridge = gatedBridge;
    final scanner = (buildScanner() as MaterialApp).home!;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => scanner)),
                child: const Text('Open scanner'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open scanner'));
    await pumpFrames(tester);

    await tester.tap(find.text('Paste QR Data'));
    await pumpFrames(tester);
    await tester.enterText(
      find.byType(TextField).last,
      _buildValidQrData(identity: _fx('late'), username: 'Bob'),
    );
    await tester.tap(find.text('Submit'));
    await pumpFrames(tester, count: 20);
    expect(find.byType(QRScannerScreen), findsNothing);
    expect(gatedBridge.verifyRequested, isTrue);

    gatedBridge.releaseVerify();
    await pumpFrames(tester);

    expect(await contactRepository.getContact(_fx('late').peerId), isNotNull);
    expect(find.text('Added to your circle!'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, count: 20);
    expect(find.byType(FeedWired), findsOneWidget);
    expect(gatedBridge.commandLog, contains('contactrequest.encrypt'));
    expect(p2pService.lastStoreInInboxPeerId, _fx('late').peerId);
  });

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
      _buildValidQrData(identity: _fx('runner'), username: 'Bob'),
    );
    await pumpFrames(tester);

    expect(find.text('Added to your circle!'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await pumpFrames(tester, count: 20);

    final feedWired = tester.widget<FeedWired>(find.byType(FeedWired));
    expect(feedWired.accountMigrationRunTransfer, same(runner));
  });

  testWidgets(
    'TC-360-02a dual-signed linked-device QR stages only exact known-contact '
    'pending authority',
    (tester) async {
      // A linked-device document is a different protocol with different
      // authority. Routing it to the legacy contact parser would let a
      // document that parser was never designed to authenticate reach a
      // success path that mutates contact and ML-KEM state.
      final linkedDocument = jsonEncode(<String, Object?>{
        'mknoon': <String, Object?>{
          'accountSignature': 'account-signature',
          'body': <String, Object?>{
            'accountPeerId':
                '12D3KooWP7CwQswqLKZbwvYd9wrEynnL9F2aKVP1X9huNASBTuqj',
            'accountPublicKey': 'xXheGGW3CJOK/4Fh1XMAZJZmOxqhCDTjltxWaGmixmo=',
            'deviceId': 'installation-1',
            'deviceMlKemPublicKey': 'device-mlkem',
            'issuedAt': '2026-08-11T12:00:00.000Z',
            'transportPeerId':
                '12D3KooWPCyWnZCXR3VGdrQjLr5d8TBaAHD956XZvo6xoCXYB5AR',
            'transportPublicKey':
                'xvKsVZiXDHljNxTT61w017/D6S2ljHNUs3mW2aSvOrI=',
          },
          'purpose': 'direct_linked_device_binding',
          'transportSignature': 'transport-signature',
          'version': 1,
        },
      });

      // ── Routed to the trust flow when that route supplied a handler. ──
      final dispatched = <String>[];
      await tester.pumpWidget(
        buildScanner(
          onDirectLinkedDeviceQrScanned: (raw) async => dispatched.add(raw),
        ),
      );
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(linkedDocument);
      await pumpFrames(tester);

      expect(dispatched, <String>[linkedDocument]);
      expect(await contactRepository.getContactCount(), 0);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('contactrequest.encrypt')));
      expect(find.text('Added to your circle!'), findsNothing);

      // ── Refused outright from an ordinary "scan a friend's code" entry
      // point, which supplies no handler. It must NOT fall through to the
      // contact parser. ──
      await tester.pumpWidget(buildScanner());
      await pumpFrames(tester);
      tester
          .widget<QRScannerScreen>(find.byType(QRScannerScreen))
          .onScanned(linkedDocument);
      await pumpFrames(tester);

      expect(await contactRepository.getContactCount(), 0);
      expect(bridge.commandLog, isNot(contains('payload.verify')));
      expect(bridge.commandLog, isNot(contains('contactrequest.encrypt')));
      expect(find.text('Added to your circle!'), findsNothing);
    },
  );
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

/// Holds `payload.verify` until [releaseVerify], so a test can close the
/// scanner route while the scan is still being processed.
class _VerifyGatedBridge extends FakeBridge {
  final _verifyGate = Completer<void>();
  bool verifyRequested = false;

  void releaseVerify() => _verifyGate.complete();

  @override
  Future<String> send(String message) async {
    final cmd = (jsonDecode(message) as Map<String, dynamic>)['cmd'];
    if (cmd == 'payload.verify') {
      verifyRequested = true;
      await _verifyGate.future;
    }
    return super.send(message);
  }
}

List<String> _contactRequestRecipientKeys(FakeBridge bridge) {
  final keys = <String>[];
  for (final message in bridge.sentMessages) {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] != 'contactrequest.encrypt') continue;
    final payload = request['payload'] as Map<String, dynamic>;
    keys.add(payload['recipientPublicKey'] as String);
  }
  return keys;
}

// Task 12b: every scanned QR names a real Ed25519 identity, so its peer ID is
// the libp2p ID of its key (the parser now checks that binding).
final _fixtures = <String, TestEd25519Identity>{};
TestEd25519Identity _fx(String label) => _fixtures.putIfAbsent(
  label,
  () => TestEd25519Identity.fromSeedByte(0x60 + _fixtures.length),
);

String _buildValidQrData({
  TestEd25519Identity? identity,
  String? publicKeyOverride,
  String username = 'Bob',
}) {
  final id = identity ?? _fx('scanned');
  final payload = SplayTreeMap<String, dynamic>.from({
    'ns': id.peerId,
    'pk': publicKeyOverride ?? id.publicKey,
    'rv': '/dns4/relay/tcp/443/p2p/relay',
    'ts': DateTime.now().toUtc().toIso8601String(),
    'un': username,
  });
  payload['sig'] = 'valid-sig';
  return jsonEncode(payload);
}
