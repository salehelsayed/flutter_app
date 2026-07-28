import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/posts/application/nearby_location_service.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 206 — the Orbit center self-avatar is the (migrated) Settings entry point.
///
/// These pin: idle center tap → Settings (slide-up), full-screen parity,
/// back-to-orbit, modal-state gating (edit / find), single-flight route,
/// long-press sculpt-entry uniformity, identity change-kind avatar refresh, and
/// the SHARED-controller + orbit-threaded nearby-service wiring locks.
class _FakeNearbyLocationService implements NearbyLocationService {
  @override
  Future<NearbyComposeAvailability> loadComposeAvailability() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.sharingOff,
      );

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromCompose() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.ready,
      );

  @override
  Future<NearbyComposeAvailability> refreshInteractivelyFromSettings() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.ready,
      );

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnPostsOpen() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.stale,
      );

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnResume() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.stale,
      );

  @override
  Future<NearbyComposeAvailability> refreshSilentlyOnStartup() async =>
      const NearbyComposeAvailability(
        state: NearbyComposeAvailabilityState.stale,
      );

  @override
  Future<void> handleSharingDisabled() async {}

  @override
  Future<bool> openAppSettings() async => true;
}

class _EmptyGroupExitDiagnosticRepository
    implements GroupExitDiagnosticRepository {
  @override
  Future<void> appendOutcome(List<GroupExitDiagnostic> diagnostics) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<List<GroupExitDiagnostic>> loadForAction({
    required String groupId,
    required String intentId,
  }) async => const [];

  @override
  Future<List<GroupExitDiagnostic>> loadNewest() async => const [];
}

void main() {
  const centerKey = ValueKey('orbit-center-self-avatar');

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
  late InMemoryPostsPrivacySettingsRepository postsPrivacyRepo;
  late InMemoryFeedClearedRepository feedClearedRepo;

  IdentityModel identityWith({Uint8List? avatarBlob}) => IdentityModel(
    peerId: 'my-peer-id-12345',
    publicKey: 'pk',
    privateKey: 'sk',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-my-peer-id-12345',
    username: 'Alice',
    avatarBlob: avatarBlob,
    createdAt: '2026-03-15T10:00:00.000Z',
    updatedAt: '2026-03-15T10:00:00.000Z',
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
    postsPrivacyRepo = InMemoryPostsPrivacySettingsRepository();
    feedClearedRepo = InMemoryFeedClearedRepository();

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
    postsPrivacyRepo.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  void setLargeSurface(WidgetTester tester) {
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

  Widget buildOrbit({
    required AppShellController appShellController,
    NearbyLocationService? nearbyLocationService,
    GroupExitDiagnosticRepository? groupExitDiagnosticRepository,
    bool disableAnimations = false,
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

    final orbit = OrbitWired(
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
      feedClearedRepository: feedClearedRepo,
      appShellController: appShellController,
      // A non-null feed-unread listenable ⇒ persistent Feed/Orbit nav (the real
      // embedded-host layout): no standalone close button overlapping the find
      // pill / center chrome.
      feedUnreadCountListenable: ValueNotifier<int>(0),
      postsPrivacySettingsRepository: postsPrivacyRepo,
      nearbyLocationService: nearbyLocationService,
      groupExitDiagnosticRepository: groupExitDiagnosticRepository,
    );

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: disableAnimations),
          child: orbit,
        ),
      ),
    );
  }

  Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder centerAvatar() => find.byKey(centerKey);

  UserAvatar centerUserAvatar(WidgetTester tester) => tester.widget<UserAvatar>(
    find.descendant(of: centerAvatar(), matching: find.byType(UserAvatar)),
  );

  AppShellController freshController() {
    final controller = AppShellController(initialTab: AppShellTab.orbit);
    addTearDown(controller.dispose);
    return controller;
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(centerAvatar());
    await pumpFrames(tester);
  }

  testWidgets('TC-206-01 idle center tap opens Settings via slide-up', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);

    expect(centerAvatar(), findsOneWidget);
    await openSettings(tester);

    expect(find.byType(SettingsWired), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('TC-206-02 orbit-opened Settings is the full screen', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);
    await openSettings(tester);

    // Full Settings surface: title + posts-nearby section + move-account entry.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Share People Nearby'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-move-account-action')),
      findsOneWidget,
    );
  });

  testWidgets('TC-206-03 back returns to orbit intact', (tester) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);
    await openSettings(tester);
    expect(find.byType(SettingsWired), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await pumpFrames(tester);

    expect(find.byType(SettingsWired), findsNothing);
    // Back on the orbit surface: the center avatar (idle, no edit banner).
    expect(centerAvatar(), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
  });

  testWidgets('TC-206-04 identity without photo still opens Settings', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    // Null avatar bytes → the placeholder ring avatar renders, still tappable.
    identityRepo.seed(identityWith(avatarBlob: null));

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);
    await openSettings(tester);

    expect(find.byType(SettingsWired), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('TC-206-06 rapid taps push exactly one settings route', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);

    // Two immediate taps with no settle between them (double-tap cadence).
    await tester.tap(centerAvatar());
    await tester.tap(centerAvatar());
    await pumpFrames(tester);

    // Single-flight latch: exactly one Settings route, not two stacked.
    expect(find.byType(SettingsWired), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_left));
    await pumpFrames(tester);
    expect(find.byType(SettingsWired), findsNothing);
    expect(centerAvatar(), findsOneWidget);
  });

  testWidgets('TC-206-07 long-press center enters edit, no Settings', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);

    final gesture = await tester.startGesture(tester.getCenter(centerAvatar()));
    await tester.pump(const Duration(milliseconds: 620)); // past long-press
    await gesture.up();
    await pumpFrames(tester);

    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
    expect(find.byType(SettingsWired), findsNothing);
  });

  testWidgets('TC-206-08 mid-edit center tap ends edit, no Settings', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);

    // Enter edit via a center long-press (sculpt-entry uniformity, TC-206-07).
    final edit = await tester.startGesture(tester.getCenter(centerAvatar()));
    await tester.pump(const Duration(milliseconds: 620));
    await edit.up();
    await pumpFrames(tester);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);

    // Mid-edit center tap dismisses edit and does NOT open Settings.
    await tester.tap(centerAvatar());
    await pumpFrames(tester);

    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
    expect(find.byType(SettingsWired), findsNothing);
  });

  testWidgets(
    'TC-206-09 find-open center tap closes find; next tap opens Settings',
    (tester) async {
      setLargeSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(identityWith());

      await tester.pumpWidget(
        buildOrbit(appShellController: freshController()),
      );
      await pumpFrames(tester);

      // Open the find pill.
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await pumpFrames(tester);
      expect(find.byKey(const ValueKey('orbit-find-pill')), findsOneWidget);

      // Center tap while find is open: closes find, does NOT open Settings.
      await tester.tap(centerAvatar());
      await pumpFrames(tester);
      expect(find.byType(SettingsWired), findsNothing);

      // A subsequent idle center tap DOES open Settings.
      await tester.tap(centerAvatar());
      await pumpFrames(tester);
      expect(find.byType(SettingsWired), findsOneWidget);
    },
  );

  testWidgets('TC-206-18 identity change-kind refreshes center avatar bytes', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    final controller = freshController();
    final bytesA = Uint8List.fromList([1, 2, 3, 4]);
    final bytesB = Uint8List.fromList([9, 8, 7, 6]);
    identityRepo.seed(identityWith(avatarBlob: bytesA));

    await tester.pumpWidget(buildOrbit(appShellController: controller));
    await pumpFrames(tester);
    expect(centerUserAvatar(tester).avatarBytes, bytesA);

    // Swap the identity's avatar, then fire the identity change-kind.
    identityRepo.seed(identityWith(avatarBlob: bytesB));
    controller.notifyIdentityChanged();
    await pumpFrames(tester);

    expect(centerUserAvatar(tester).avatarBytes, bytesB);
  });

  testWidgets(
    'TC-206-22 wiring-lock: SettingsWired receives orbit-threaded nearby '
    'service + SHARED controller',
    (tester) async {
      setLargeSurface(tester);
      suppressOverflowErrors();
      final controller = freshController();
      final nearby = _FakeNearbyLocationService();
      identityRepo.seed(identityWith());

      await tester.pumpWidget(
        buildOrbit(
          appShellController: controller,
          nearbyLocationService: nearby,
        ),
      );
      await pumpFrames(tester);
      await openSettings(tester);

      final settings = tester.widget<SettingsWired>(find.byType(SettingsWired));
      expect(identical(settings.nearbyLocationService, nearby), isTrue);
      expect(identical(settings.appShellController, controller), isTrue);
    },
  );

  testWidgets(
    'PB266-13 Orbit Settings receives the identical release diagnostic '
    'repository',
    (tester) async {
      setLargeSurface(tester);
      suppressOverflowErrors();
      final repository = _EmptyGroupExitDiagnosticRepository();
      identityRepo.seed(identityWith());

      await tester.pumpWidget(
        buildOrbit(
          appShellController: freshController(),
          groupExitDiagnosticRepository: repository,
        ),
      );
      await pumpFrames(tester);
      await openSettings(tester);

      final settings = tester.widget<SettingsWired>(find.byType(SettingsWired));
      expect(
        identical(settings.groupExitDiagnosticRepository, repository),
        isTrue,
      );
    },
  );

  testWidgets('TC-206-23 move-account reachable from orbit-opened Settings', (
    tester,
  ) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);
    await openSettings(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-move-account-action')),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-move-account-action')),
    );
    await pumpFrames(tester);
    expect(find.byType(AccountMigrationJourneyWired), findsOneWidget);

    // Pop the migration route via the root navigator (its own back chrome is
    // out of scope) → back to the still-mounted Settings screen.
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await pumpFrames(tester);
    expect(find.byType(AccountMigrationJourneyWired), findsNothing);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets('TC-206-29 reopen after pop', (tester) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(buildOrbit(appShellController: freshController()));
    await pumpFrames(tester);

    await openSettings(tester);
    expect(find.byType(SettingsWired), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await pumpFrames(tester);
    expect(find.byType(SettingsWired), findsNothing);

    // The single-flight latch released on pop → a second tap re-opens.
    await openSettings(tester);
    expect(find.byType(SettingsWired), findsOneWidget);
  });

  testWidgets(
    'TC-226-16 swipe-right on Settings returns to orbit intact and center '
    'tap reopens Settings',
    (tester) async {
      setLargeSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(identityWith());

      await tester.pumpWidget(
        buildOrbit(appShellController: freshController()),
      );
      await pumpFrames(tester);

      await openSettings(tester);
      expect(find.byType(SettingsWired), findsOneWidget);

      await tester.fling(
        find.byType(SettingsScreen),
        const Offset(300, 0),
        1200,
      );
      await pumpFrames(tester);

      expect(find.byType(SettingsWired), findsNothing);
      expect(centerAvatar(), findsOneWidget);

      await openSettings(tester);
      expect(find.byType(SettingsWired), findsOneWidget);
    },
  );

  testWidgets('TC-206-27 reduce-motion open + return', (tester) async {
    setLargeSurface(tester);
    suppressOverflowErrors();
    identityRepo.seed(identityWith());

    await tester.pumpWidget(
      buildOrbit(
        appShellController: freshController(),
        disableAnimations: true,
      ),
    );
    await pumpFrames(tester);

    await openSettings(tester);
    expect(find.byType(SettingsWired), findsOneWidget);
    await tester.tap(find.byIcon(Icons.chevron_left));
    await pumpFrames(tester);
    expect(find.byType(SettingsWired), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('TC-206-24 source-guard: both OrbitWired ctor sites thread '
      'nearbyLocationService', () {
    final feedWired = File(
      'lib/features/feed/presentation/screens/feed_wired.dart',
    ).readAsStringSync();
    final applicationRoot = File(
      'lib/app/application_root.dart',
    ).readAsStringSync();

    // Each file constructs exactly one OrbitWired(...). Isolate that arg block
    // and assert nearbyLocationService is threaded into it.
    bool orbitCtorThreadsNearby(String source) {
      final start = source.indexOf('OrbitWired(');
      if (start < 0) return false;
      // Walk to the matching close paren.
      var depth = 0;
      var end = -1;
      for (var i = source.indexOf('(', start); i < source.length; i++) {
        final c = source[i];
        if (c == '(') depth++;
        if (c == ')') {
          depth--;
          if (depth == 0) {
            end = i;
            break;
          }
        }
      }
      if (end < 0) return false;
      final args = source.substring(start, end);
      return args.contains('nearbyLocationService:');
    }

    expect(
      orbitCtorThreadsNearby(feedWired),
      isTrue,
      reason: 'feed_wired.dart OrbitWired must thread nearbyLocationService',
    );
    expect(
      orbitCtorThreadsNearby(applicationRoot),
      isTrue,
      reason:
          'application_root.dart OrbitWired must thread nearbyLocationService',
    );
  });

  test(
    'PB266-13 source guard threads diagnostics through every live route hop',
    () {
      String source(String path) => File(path).readAsStringSync();

      List<String> callBlocks(String input, String symbol) {
        final blocks = <String>[];
        var cursor = 0;
        while (true) {
          final start = input.indexOf('$symbol(', cursor);
          if (start < 0) break;
          if (start > 0 && RegExp(r'[A-Za-z0-9_]').hasMatch(input[start - 1])) {
            cursor = start + symbol.length;
            continue;
          }
          var depth = 0;
          var end = -1;
          for (var i = input.indexOf('(', start); i < input.length; i++) {
            final char = input[i];
            if (char == '(') depth++;
            if (char == ')') {
              depth--;
              if (depth == 0) {
                end = i + 1;
                break;
              }
            }
          }
          expect(end, greaterThan(start), reason: 'unclosed $symbol call');
          blocks.add(input.substring(start, end));
          cursor = end;
        }
        return blocks.where((block) => !block.startsWith('$symbol({')).toList();
      }

      void expectThreaded(String path, String symbol, {required int count}) {
        final blocks = callBlocks(source(path), symbol);
        expect(blocks, hasLength(count), reason: '$path $symbol census');
        for (final block in blocks) {
          expect(
            block,
            contains('groupExitDiagnosticRepository:'),
            reason: '$path $symbol must forward the shared repository',
          );
        }
      }

      const startup = 'lib/features/identity/presentation/startup_router.dart';
      const fte =
          'lib/features/home/presentation/screens/'
          'first_time_experience_wired.dart';
      const qr =
          'lib/features/qr_code/presentation/screens/qr_scanner_wired.dart';
      const feed = 'lib/features/feed/presentation/screens/feed_wired.dart';
      const orbit = 'lib/features/orbit/presentation/screens/orbit_wired.dart';

      expectThreaded(startup, 'StartupRouter', count: 1);
      expectThreaded(startup, 'FirstTimeExperienceWired', count: 2);
      expectThreaded(startup, 'FeedWired', count: 1);
      expectThreaded(fte, 'FeedWired', count: 1);
      expectThreaded(fte, 'QRScannerWired', count: 1);
      expectThreaded(qr, 'FeedWired', count: 1);
      expectThreaded(feed, 'OrbitWired', count: 1);
      expectThreaded(orbit, 'QRScannerWired', count: 1);
      expectThreaded(orbit, 'SettingsWired', count: 1);

      for (final path in [startup, fte, qr, feed, orbit]) {
        final contents = source(path);
        expect(
          contents,
          contains(
            'GroupExitDiagnosticRepository? groupExitDiagnosticRepository',
          ),
          reason: '$path must expose the nullable test seam',
        );
        expect(contents, contains('this.groupExitDiagnosticRepository'));
      }
    },
  );

  test('PB266-08 Orbit group-exit events expose only fixed diagnostics', () {
    final contents = File(
      'lib/features/orbit/presentation/screens/orbit_wired.dart',
    ).readAsStringSync();
    const expected = <String, (String, String)>{
      'ORBIT_FL_GROUP_EXIT_CLASSIFY_ERROR': ('EX01', 'authority'),
      'ORBIT_FL_GROUP_EXIT_PROMOTION_ERROR': ('EX02', 'role_sync'),
      'ORBIT_FL_DELETE_GROUP_ERROR': ('EX10', 'local_delete'),
      'ORBIT_FL_DELETE_SELF_REMOVED_GROUP_ERROR': ('EX10', 'local_delete'),
      'ORBIT_FL_STUCK_EXIT_CLASSIFY_ERROR': ('EX01', 'authority'),
    };

    for (final entry in expected.entries) {
      final eventOffset = contents.indexOf("event: '${entry.key}'");
      expect(eventOffset, greaterThanOrEqualTo(0), reason: entry.key);
      final detailsOffset = contents.indexOf('details:', eventOffset);
      final endOffset = contents.indexOf('},', detailsOffset);
      expect(endOffset, greaterThan(detailsOffset), reason: entry.key);
      final details = contents.substring(detailsOffset, endOffset + 2);
      expect(details, contains("'code': '${entry.value.$1}'"));
      expect(details, contains("'phase': '${entry.value.$2}'"));
      expect(details, contains("'severity': 'failure'"));
      expect(details, isNot(contains('groupId')));
      expect(details, isNot(contains("'error'")));
      expect(details, isNot(contains('toString()')));
    }
  });
}
