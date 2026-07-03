import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_app/features/home/presentation/widgets/scan_friend_card.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_list_header.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_display_screen.dart';
import 'package:flutter_app/features/qr_code/presentation/screens/qr_scanner_screen.dart';

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
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 196 — QR "My QR" / "Scan" entry migration to the Orbit top chrome (wired
/// host). Harness cloned from `orbit_view_split_test.dart:71-244` (bounded pumps
/// only — QRDisplayScreen / QRScannerScreen carry infinite animations, so NEVER
/// pumpAndSettle). Chrome keys: `orbit-my-qr-button` / `orbit-scan-button`.
const _myQrKey = ValueKey('orbit-my-qr-button');
const _scanKey = ValueKey('orbit-scan-button');

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

  List<ContactModel> manyContacts(int n) => List.generate(
    n,
    (i) => ContactModel(
      peerId: 'contact-$i',
      publicKey: 'pk-$i',
      rendezvous: '/dns4/relay/tcp/443',
      username: 'Friend $i',
      signature: 'sig-$i',
      scannedAt: DateTime.now().toUtc().toIso8601String(),
      mlKemPublicKey: 'mlkem-$i',
    ),
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
  });

  tearDown(() {
    debugSetFlowEventSink(null);
    postsPrivacySettingsRepository.dispose();
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void setNarrowTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 690);
    tester.view.devicePixelRatio = 1.0;
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

  Widget buildOrbitWired({
    String? initialFilterTab,
    AppShellController? appShellController,
    ValueNotifier<int>? feedUnreadCountListenable,
    InMemoryIntroductionRepository? introductionRepository,
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
      identityRepo: identityRepo,
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
    );

    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: orbitWidget,
    );
  }

  /// Bare `OrbitScreen` pump (donor: `orbit_screen_loading_test.dart`) with
  /// `onToggleView: null` — proves the chrome does NOT reuse the toggle's
  /// nullability gate (C6 perf-harness caveat).
  Widget buildBareOrbitScreen({
    OrbitViewMode viewMode = OrbitViewMode.innerCircle,
  }) {
    final openRow = ValueNotifier<Key?>(null);
    final scroll = ScrollController();
    final searchCtrl = TextEditingController();
    final searchFocus = FocusNode();
    final header = ValueNotifier(const OrbitHeaderProjection());
    final list = ValueNotifier(const OrbitViewProjection());
    addTearDown(openRow.dispose);
    addTearDown(scroll.dispose);
    addTearDown(searchCtrl.dispose);
    addTearDown(searchFocus.dispose);
    addTearDown(header.dispose);
    addTearDown(list.dispose);

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OrbitScreen(
        headerProjectionListenable: header,
        listProjectionListenable: list,
        scrollController: scroll,
        searchController: searchCtrl,
        searchFocusNode: searchFocus,
        collapseAnimation: const AlwaysStoppedAnimation(1.0),
        searchDockAnimation: const AlwaysStoppedAnimation(0.0),
        searchTriggerAnimation: const AlwaysStoppedAnimation(1.0),
        onClose: () {},
        onFriendTap: (_) {},
        onMyQR: () {},
        onScanQR: () {},
        onSearchOpen: () {},
        onSearchClose: () {},
        onSearchChanged: (_) {},
        onSearchClear: () {},
        onFilterChanged: (_) {},
        onArchiveFriend: (_) {},
        onUnarchiveFriend: (_) {},
        onBlockFriend: (_) {},
        onUnblockFriend: (_) {},
        onDeleteFriend: (_) {},
        openRowNotifier: openRow,
        onGroupTap: (_) {},
        onCreateGroup: (_) {},
        onArchiveGroup: (_) {},
        onUnarchiveGroup: (_) {},
        onDeleteGroup: (_) {},
        viewMode: viewMode,
        onToggleView: null,
      ),
    );
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

  group('196 orbit QR chrome migration', () {
    testWidgets('TC-01/02: inner-circle default shows the centered QR chrome '
        'pair', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // The default surface is the inner circle, and the chrome pair is on it.
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byKey(_myQrKey), findsOneWidget);
      expect(find.byKey(_scanKey), findsOneWidget);

      final myRect = tester.getRect(find.byKey(_myQrKey));
      final scanRect = tester.getRect(find.byKey(_scanKey));
      expect(myRect.center.dx, lessThan(scanRect.center.dx));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        (myRect.left + scanRect.right) / 2,
        moreOrLessEquals(width / 2, epsilon: 1),
      );
      expect(myRect.top, lessThan(120));
    });

    testWidgets('TC-03: 320dp width keeps toggle, pair, and FAB disjoint', (
      tester,
    ) async {
      setNarrowTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      final toggle = tester.getRect(
        find.byKey(const ValueKey('orbit-view-toggle')),
      );
      final myQr = tester.getRect(find.byKey(_myQrKey));
      final scan = tester.getRect(find.byKey(_scanKey));
      final fab = tester.getRect(find.byType(GlowFab));

      // Pairwise disjoint even at the narrowest supported width.
      expect(toggle.overlaps(myQr), isFalse);
      expect(toggle.overlaps(scan), isFalse);
      expect(fab.overlaps(myQr), isFalse);
      expect(fab.overlaps(scan), isFalse);
      expect(myQr.overlaps(scan), isFalse);

      // And still hit-testable (the whole suite's chrome taps depend on this).
      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 5);
      expect(find.byType(QRDisplayScreen), findsOneWidget);
    });

    testWidgets('TC-04: RTL keeps the pair centered, ordered, and clear of '
        'toggle/FAB', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired(locale: const Locale('ar')));
      await pumpOrbitFrames(tester, count: 4);

      final myQr = tester.getRect(find.byKey(_myQrKey));
      final scan = tester.getRect(find.byKey(_scanKey));
      final toggle = tester.getRect(
        find.byKey(const ValueKey('orbit-view-toggle')),
      );
      final fab = tester.getRect(find.byType(GlowFab));

      // Physical order preserved (My QR left of Scan) under RTL.
      expect(myQr.center.dx, lessThan(scan.center.dx));
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(
        (myQr.left + scan.right) / 2,
        moreOrLessEquals(width / 2, epsilon: 1),
      );
      // Clear of the physical top-left toggle and the physical top-right FAB.
      expect(toggle.right, lessThanOrEqualTo(myQr.left));
      expect(scan.right, lessThanOrEqualTo(fab.left));
    });

    testWidgets('TC-06: bare OrbitScreen (onToggleView null, innerCircle) '
        'still mounts the chrome', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();

      await tester.pumpWidget(
        buildBareOrbitScreen(viewMode: OrbitViewMode.innerCircle),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(_myQrKey), findsOneWidget);
      expect(find.byKey(_scanKey), findsOneWidget);
      // The toggle is NOT mounted here — the chrome must not share its gate.
      expect(find.byKey(const ValueKey('orbit-view-toggle')), findsNothing);
    });

    testWidgets('TC-07: tap My QR pushes the QR display and pop returns to the '
        'inner circle', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'sig'};

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 5);
      expect(find.byType(QRDisplayScreen), findsOneWidget);

      Navigator.of(tester.element(find.byType(QRDisplayScreen))).pop();
      await pumpOrbitFrames(tester, count: 5);
      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byType(FriendRow), findsNothing);
    });

    testWidgets('TC-08: tap Scan pushes the scanner (B6 dep set intact)', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      await tester.tap(find.byKey(_scanKey));
      await pumpOrbitFrames(tester, count: 6);
      // Construction of QRScannerScreen proves the full ~25-dep set (incl.
      // feedClearedRepository) threads through _onScanQR.
      expect(find.byType(QRScannerScreen), findsOneWidget);
    });

    testWidgets('TC-09: ScanFriendCard inside the pushed QR display still opens '
        'the scanner', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      bridge.responses['payload.sign'] = {'ok': true, 'signature': 'sig'};

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Open the My QR display (NOT the direct Scan chrome key).
      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRDisplayScreen), findsOneWidget);

      // The display's own ScanFriendCard threads to the scanner.
      await tester.tap(find.byType(ScanFriendCard));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
    });

    testWidgets('TC-10: Scan tap before identity load opens the scanner '
        'without crashing', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      // No identity seeded → _identity null → ownPeerId '' contract (locked
      // as-is; adding a throwing guard would go red here).
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 2);

      await tester.tap(find.byKey(_scanKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('TC-11: My QR without identity shows the display noIdentity '
        'state', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      // No identity seeded → QRDisplayWired resolves to the noIdentity state.
      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 2);

      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 6);
      // The QR display's noIdentity branch renders its own error-state copy
      // (donor: qr_display_wired_test.dart:88) rather than the QR surface — the
      // repo/bridge pass-through must reach it unbroken.
      expect(find.text('No Identity'), findsOneWidget);
    });

    testWidgets('TC-12: open FAB scrim eats a tap at the chrome position', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      // Open the create-group FAB → its full-screen scrim mounts above the
      // chrome (chrome is Layer 1c, the FAB is the last Stack child).
      await tester.tap(find.byType(GlowFab));
      await pumpOrbitFrames(tester, count: 4);
      expect(find.text('New Group'), findsOneWidget);

      // Tap at the My QR button's center: the scrim wins the hit.
      final myQrCenter = tester.getCenter(find.byKey(_myQrKey));
      await tester.tapAt(myQrCenter);
      await pumpOrbitFrames(tester, count: 4);

      // The menu closed and NO QR display opened.
      expect(find.text('New Group'), findsNothing);
      expect(find.byType(QRDisplayScreen), findsNothing);
    });

    testWidgets('TC-13: all-chats header carries no QR pills', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);
      await switchToAllChats(tester);

      expect(find.byType(FriendsListHeader), findsOneWidget);
      // Pills are gone: Semantics labels create no Text nodes.
      expect(find.text('My QR'), findsNothing);
      expect(find.text('Scan'), findsNothing);
    });

    testWidgets('TC-14: chrome pair present and functional on the all-chats '
        'surface', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);
      await switchToAllChats(tester);

      expect(find.byKey(_myQrKey), findsOneWidget);
      expect(find.byKey(_scanKey), findsOneWidget);
      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 5);
      expect(find.byType(QRDisplayScreen), findsOneWidget);
    });

    testWidgets('TC-15: active search keeps the chrome tappable', (
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

      // Open search from the all-chats surface.
      await tester.tap(find.byType(OrbitSearchTrigger));
      await pumpOrbitFrames(tester, count: 4);
      // The filter toggle hides under search, but the chrome persists.
      expect(find.byType(FriendsFilterToggle), findsNothing);
      expect(find.byKey(_scanKey), findsOneWidget);

      await tester.tap(find.byKey(_scanKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
    });

    testWidgets('TC-17: intros deep link (initialFilterTab intros) lands with '
        'working chrome', (tester) async {
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

      // The deep link forces the all-chats surface; the chrome is on it and
      // works with zero taps of the toggle.
      expect(find.byType(OrbitalVisualization), findsNothing);
      expect(find.byKey(_myQrKey), findsOneWidget);
      await tester.tap(find.byKey(_myQrKey));
      await pumpOrbitFrames(tester, count: 5);
      expect(find.byType(QRDisplayScreen), findsOneWidget);
    });

    testWidgets('TC-21: Feed->Orbit re-entry reset re-mounts the inner circle '
        'with chrome present', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);
      final shell = AppShellController(initialTab: AppShellTab.orbit);
      final feedUnread = ValueNotifier<int>(0);
      addTearDown(feedUnread.dispose);

      await tester.pumpWidget(
        buildOrbitWired(
          appShellController: shell,
          feedUnreadCountListenable: feedUnread,
        ),
      );
      await pumpOrbitFrames(tester, count: 4);

      await switchToAllChats(tester);
      expect(find.byType(FriendsFilterToggle), findsOneWidget);

      // Leave and re-enter → resets to the inner circle; chrome re-mounts.
      shell.switchTo(AppShellTab.feed);
      await pumpOrbitFrames(tester);
      shell.switchTo(AppShellTab.orbit);
      await pumpOrbitFrames(tester);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byKey(_myQrKey), findsOneWidget);
      expect(find.byKey(_scanKey), findsOneWidget);
    });

    testWidgets('TC-22: rapid toggle round-trips keep exactly one chrome pair', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      for (var i = 0; i < 4; i++) {
        await tester.tap(find.byKey(const ValueKey('orbit-view-toggle')));
        await pumpOrbitFrames(tester);
        expect(find.byKey(_myQrKey), findsOneWidget);
        expect(find.byKey(_scanKey), findsOneWidget);
      }
    });

    testWidgets('TC-23: fresh remount reconstructs the chrome on the default '
        'surface', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);
      await switchToAllChats(tester);

      // Full unmount → brand-new mount reconstructs the default with chrome.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);

      expect(find.byType(OrbitalVisualization), findsOneWidget);
      expect(find.byKey(_myQrKey), findsOneWidget);
      expect(find.byKey(_scanKey), findsOneWidget);
    });

    testWidgets('TC-24: scrolling the list under the chrome keeps it fixed and '
        'tappable', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed(manyContacts(20));

      await tester.pumpWidget(buildOrbitWired());
      await pumpOrbitFrames(tester, count: 4);
      await switchToAllChats(tester);

      final before = tester.getRect(find.byKey(_scanKey));
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await pumpOrbitFrames(tester);
      final after = tester.getRect(find.byKey(_scanKey));

      // Chrome is fixed chrome — not inside the CustomScrollView.
      expect(after, before);
      await tester.tap(find.byKey(_scanKey));
      await pumpOrbitFrames(tester, count: 6);
      expect(find.byType(QRScannerScreen), findsOneWidget);
    });
  });
}
