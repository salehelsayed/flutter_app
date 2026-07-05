import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_qr_payload.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/home/presentation/widgets/scan_friend_card.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 209 — the Orbit QR chrome pair is RETIRED; My QR / Scan live as Settings
/// tiles (host-callback architecture: OrbitWired supplies `_onMyQR`/`_onScanQR`
/// to SettingsWired as `onMyQrRequested`/`onScanQrRequested`). This file keeps
/// the 196 destination contracts (INV-196-7: dep bundle, ScanFriendCard loop,
/// noIdentity state, migration branch) alive at the NEW host and inverts the
/// chrome-presence assertions (harness cloned from the 196 suite — bounded
/// pumps only; QR screens carry infinite animations, NEVER pumpAndSettle).
const _myQrChromeKey = ValueKey('orbit-my-qr-button');
const _scanChromeKey = ValueKey('orbit-scan-button');
const _centerAvatarKey = ValueKey('orbit-center-self-avatar');
const _myQrTileKey = ValueKey('settings-my-qr-tile');
const _scanTileKey = ValueKey('settings-scan-tile');

/// T10 — identity repo whose first load can be held open, so the pre-identity
/// surface state is observable (206/209: the Settings entry is the center
/// self-avatar, which mounts only once identity resolves — the defined
/// pre-identity state is "no entry yet", not a crashing scanner).
class _GateableIdentityRepository extends FakeIdentityRepository {
  Completer<void>? gate;

  @override
  Future<IdentityModel?> loadIdentity() async {
    final currentGate = gate;
    if (currentGate != null) {
      await currentGate.future;
    }
    return super.loadIdentity();
  }
}

IntroductionModel _pendingIntroduction({
  required String ownPeerId,
  required String otherPeerId,
  required String createdAt,
  String id = 'orbit-intro',
}) {
  return IntroductionModel(
    id: id,
    introducerId: 'peer-A',
    recipientId: ownPeerId,
    introducedId: otherPeerId,
    createdAt: createdAt,
    introducerUsername: 'Noor',
    recipientUsername: 'Alice',
    introducedUsername: 'Dora',
  );
}

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
  late ImageProcessor imageProcessor;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late List<Map<String, dynamic>> flowEvents;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-test-peer-id-12345',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  final testContact = ContactModel(
    peerId: 'contact-peer-id',
    publicKey: 'contact-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'Bob',
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: 'mlkem-contact-peer-id',
  );

  String freshPendingIntroductionCreatedAt() => DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 1))
      .toIso8601String();

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
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
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
    debugSetFlowEventSink(null);
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  void suppressNavAssetErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  AppShellController freshController() {
    final controller = AppShellController(initialTab: AppShellTab.orbit);
    addTearDown(controller.dispose);
    return controller;
  }

  Widget buildOrbitWired({
    String? initialFilterTab,
    AppShellController? appShellController,
    ValueNotifier<int>? feedUnreadCountListenable,
    InMemoryIntroductionRepository? introductionRepository,
    InMemoryPostRepository? postRepository,
    PendingPostTargetStore? pendingPostTargetStore,
    AccountMigrationTransferRunFn? accountMigrationRunTransfer,
    FakeIdentityRepository? identityRepository,
    Locale locale = const Locale('en'),
  }) {
    final crListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => '',
    );
    final cmListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );

    final orbitWidget = OrbitWired(
      identityRepo: identityRepository ?? identityRepo,
      contactRepo: contactRepo,
      contactRequestRepo: contactRequestRepo,
      contactRequestListener: crListener,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      chatMessageListener: cmListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      feedClearedRepository: InMemoryFeedClearedRepository(),
      groupRepository: groupRepo,
      groupMessageRepository: groupMsgRepo,
      introductionRepository: introductionRepository,
      appShellController: appShellController,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      feedUnreadCountListenable: feedUnreadCountListenable,
      initialFilterTab: initialFilterTab,
      postRepository: postRepository,
      pendingPostTargetStore: pendingPostTargetStore,
      accountMigrationRunTransfer: accountMigrationRunTransfer,
    );

    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: orbitWidget,
    );
  }

  ValueNotifier<int> freshFeedUnread() {
    final notifier = ValueNotifier<int>(0);
    addTearDown(notifier.dispose);
    return notifier;
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 3}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> switchToAllChats(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
    await pumpOrbitFrames(tester);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(_centerAvatarKey));
    await pumpOrbitFrames(tester, count: 6);
    expect(find.byType(SettingsWired), findsOneWidget);
  }

  group('209 orbit QR chrome retirement + Settings host', () {
    testWidgets('T1: inner-circle surface has no QR chrome; toggle and create '
        'button intact', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byKey(_myQrChromeKey), findsNothing);
      expect(find.byKey(_scanChromeKey), findsNothing);
      // What remains stays: the view toggle and the create-group FAB.
      expect(find.byKey(const ValueKey('orbit-view-toggle')), findsOneWidget);
      expect(find.byType(ExpandableFab), findsOneWidget);
    });

    testWidgets('T2: all-chats surface has no QR chrome and no header pills', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);
      await switchToAllChats(tester);

      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.byKey(_myQrChromeKey), findsNothing);
      expect(find.byKey(_scanChromeKey), findsNothing);
      // 196 INV-196-2 outcome preserved: no pills resurrect on the header.
      expect(find.text('My QR'), findsNothing);
      expect(find.text('Scan'), findsNothing);
    });

    testWidgets('T3: tap at the old chrome position performs background '
        'behavior only', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Old chrome band: top-center, safeTop(0 in tests)+8, 40px circles with
      // an 8px gap. Tap the old My QR button CENTER (cx - 24) — the exact
      // page center falls in the tap-transparent gap even on HEAD.
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.tapAt(Offset(width / 2 - 24, 28));
      await pumpOrbitFrames(tester, count: 4);

      // No phantom QR action, no route pushed.
      expect(find.byType(QRDisplayScreen), findsNothing);
      expect(find.byType(QRScannerScreen), findsNothing);
      expect(find.byType(SettingsWired), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T4: intros deep link still forces all-chats (chromeless)', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        _pendingIntroduction(
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'intro-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          initialFilterTab: 'intros',
          introductionRepository: introRepo,
        ),
      );
      await pumpOrbitFrames(tester, count: 6);

      // TC-17's surviving assertion (deep link forces all-chats) + inverted
      // chrome asserts. The visualization-absence leg is GREEN on HEAD by
      // design — documented sentinel within a red file.
      expect(find.byType(OrbitalVisualization), findsNothing);
      expect(find.byKey(_myQrChromeKey), findsNothing);
      expect(find.byKey(_scanChromeKey), findsNothing);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);
    });

    testWidgets('T5: feed->orbit re-entry renders chromeless without '
        'exceptions', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      final shell = freshController();

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: shell,
          feedUnreadCountListenable: freshFeedUnread(),
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await switchToAllChats(tester);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);

      // Leave and re-enter → resets to the inner circle; still chromeless.
      shell.switchTo(AppShellTab.feed);
      await pumpOrbitFrames(tester);
      shell.switchTo(AppShellTab.orbit);
      await pumpOrbitFrames(tester);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byKey(_myQrChromeKey), findsNothing);
      expect(find.byKey(_scanChromeKey), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T6 PROD-CRITICAL: center avatar -> Settings tiles -> Scan -> '
        'valid QR -> success -> fresh FeedWired with forwarded runner', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'sig'};
      bridge.responses['contactrequest.encrypt'] = {
        'ok': true,
        'ephemeralPublicKey': 'ephPubBase64',
        'ciphertext': 'ctBase64',
        'nonce': 'nonceBase64',
      };
      Future<AccountMigrationTransferResult> runner({
        required AccountMigrationTransferRequest request,
        required AccountMigrationTransferProgressCallback onProgress,
        required bool Function() isCancelled,
        AccountMigrationTransferSegmentProgressCallback? onSegmentProgress,
      }) async {
        return const AccountMigrationTransferResult.success();
      }

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: freshController(),
          feedUnreadCountListenable: freshFeedUnread(),
          postRepository: InMemoryPostRepository(),
          pendingPostTargetStore: PendingPostTargetStore(),
          accountMigrationRunTransfer: runner,
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await openSettings(tester);
      await tester.tap(find.byKey(_scanTileKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);

      // Direct-fire the scan callback (qr_scanner_wired_test technique — the
      // camera never runs in widget tests).
      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(
        _buildValidQrData(peerId: 'scanned-peer-12345', username: 'Bob'),
      );
      await pumpOrbitFrames(tester, count: 6);

      expect(find.text('Added to your circle!'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await pumpOrbitFrames(tester, count: 10);

      // pushAndRemoveUntil destroyed the whole stack (Settings included) and
      // rebuilt a functioning Feed with the runner forwarded (BASELINE
      // contract) — no _missing* StateError anywhere in the flow.
      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.byType(SettingsWired), findsNothing);
      final feedWired = tester.widget<FeedWired>(find.byType(FeedWired));
      expect(feedWired.accountMigrationRunTransfer, same(runner));

      // TC-209-38/39 outcome: the contact landed in the SHARED repo (the
      // fresh tree re-reads it — orbit load path locked by orbit_wired_test)
      // and the scan-path side effects fired (signature verify + avatar
      // download attempt; the mutual-add contract itself is the BASELINE
      // qr_scanner_wired_test sentinel).
      expect(await contactRepo.contactExists('scanned-peer-12345'), isTrue);
      expect(bridge.commandLog, contains('payload.verify'));
      expect(bridge.commandLog, contains('profile:download'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('T7: migration QR from settings-hosted scanner routes to the '
        'old-phone journey', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: freshController(),
          feedUnreadCountListenable: freshFeedUnread(),
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await openSettings(tester);
      await tester.tap(find.byKey(_scanTileKey));
      await pumpOrbitFrames(tester, count: 6);

      final scanner = tester.widget<QRScannerScreen>(
        find.byType(QRScannerScreen),
      );
      scanner.onScanned(_buildMigrationQrData());
      await pumpOrbitFrames(tester, count: 6);

      // Orbit's onMigrationQrScanned branch reached through the closure.
      expect(find.byType(AccountMigrationJourneyWired), findsOneWidget);
      expect(await contactRepo.contactExists('scanned-peer-id'), isFalse);
    });

    testWidgets('T8: My QR from Settings reaches the display; close returns '
        'to the same Settings; ScanFriendCard cross-link opens the scanner', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'sig'};

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: freshController(),
          feedUnreadCountListenable: freshFeedUnread(),
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await openSettings(tester);
      await tester.tap(find.byKey(_myQrTileKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRDisplayScreen), findsOneWidget);

      // Close the display → back to the SAME Settings route (no re-entry).
      Navigator.of(tester.element(find.byType(QRDisplayScreen))).pop();
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRDisplayScreen), findsNothing);
      expect(find.byType(SettingsWired), findsOneWidget);

      // INV-196-7 display→scan loop at the new host.
      await tester.tap(find.byKey(_myQrTileKey));
      await pumpOrbitFrames(tester, count: 6);
      await tester.tap(find.byType(ScanFriendCard));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
    });

    testWidgets('T9: My QR with no identity shows the noIdentity state', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      // Identity must exist to reach Settings (the center avatar is the
      // identity-gated entry); it is then cleared so the display resolves to
      // its noIdentity state — the INV-196-7 error contract at the new host.
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: freshController(),
          feedUnreadCountListenable: freshFeedUnread(),
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await openSettings(tester);
      identityRepo.seed(null);
      await tester.tap(find.byKey(_myQrTileKey));
      await pumpOrbitFrames(tester, count: 6);

      expect(find.text('No Identity'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('T10: pre-identity surface exposes no entry; post-load scan '
        'opens crash-free', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      final gateableRepo = _GateableIdentityRepository()..seed(testIdentity);
      gateableRepo.gate = Completer<void>();
      contactRepo.seed([testContact]);

      await tester.pumpWidget(
        buildOrbitWired(
          identityRepository: gateableRepo,
          appShellController: freshController(),
          feedUnreadCountListenable: freshFeedUnread(),
        ),
      );
      await pumpOrbitFrames(tester, count: 2);

      // Before identity resolves the center-avatar Settings entry is absent —
      // the defined pre-identity state (196's chrome was identity-independent;
      // the 206/209 entry is identity-gated by design). No crash.
      expect(find.byKey(_centerAvatarKey), findsNothing);
      expect(tester.takeException(), isNull);

      gateableRepo.gate!.complete();
      gateableRepo.gate = null;
      await pumpOrbitFrames(tester, count: 4);

      await openSettings(tester);
      await tester.tap(find.byKey(_scanTileKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
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
