import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_wired.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

/// 209 — the "One Screen" Settings contract (spec §7.2/§7.3): the full page —
/// profile header, QR/Scan tiles, IDENTITY group (peer ID, recovery), and
/// PREFERENCES group (background / photo / video rows with at-rest values,
/// inline nearby switch, move row) — fits 390×844 at textScale 1.0 with zero
/// scroll (debug cards excluded), degrades to a normal scroll on shorter
/// viewports, and keeps its pinned-constants budget (avatar 72, 44px rows,
/// shrink-wrapped Switch) locked.
const _rowKeysInOrder = <String>[
  'settings-row-peer-id',
  'settings-row-recovery',
  'settings-row-background',
  'settings-row-photo-quality',
  'settings-row-video-quality',
  'settings-row-nearby',
  'settings-move-account-action',
];

void main() {
  const twelveWords =
      'abandon ability able about above absent absorb abstract absurd abuse access accident';

  void setViewport(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void setPhoneViewport(WidgetTester tester) =>
      setViewport(tester, const Size(390, 844));

  Widget wrapScreen({
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    Locale locale = const Locale('en'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsScreen(
          username: 'Alice',
          peerId: '12D3KooWTestPeer123456789',
          mnemonic: twelveWords,
          onMyQr: () {},
          onScan: () {},
          onOpenBackgroundSheet: () {},
          onOpenPhotoQualitySheet: () {},
          onOpenVideoQualitySheet: () {},
          onOpenRecoverySheet: () {},
          currentBackgroundPreference: backgroundPreference,
          currentQuality: ImageQualityPreference.compressed,
          currentVideoQuality: ImageQualityPreference.compressed,
          isNearbySharingEnabled: false,
          onNearbySharingChanged: (_) {},
          onMoveAccountToNewPhone: () {},
          debugSection: null,
          onSwitchView: (_) {},
          activeTab: 'feed',
        ),
      ),
    );
  }

  ScrollPosition pageScrollPosition(WidgetTester tester) {
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    return scrollable.position;
  }

  Future<void> pumpWired(
    WidgetTester tester, {
    required FakeIdentityRepository identityRepo,
    required FakeSecureKeyStore store,
    AppShellController? appShellController,
  }) async {
    final shell = appShellController ?? AppShellController();
    if (appShellController == null) {
      addTearDown(shell.dispose);
    }
    final privacyRepo = InMemoryPostsPrivacySettingsRepository();
    addTearDown(privacyRepo.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsWired(
          identityRepo: identityRepo,
          bridge: FakeBridge(),
          contactRepo: FakeContactRepository(),
          p2pService: FakeP2PService(),
          secureKeyStore: store,
          imageProcessor: ImageProcessor(),
          appShellController: shell,
          postsPrivacySettingsRepository: privacyRepo,
        ),
      ),
    );
    // AmbientBackground animates forever — bounded pumps only.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('T1 whole page fits 390x844 with zero scroll', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(wrapScreen());

    // Every row + both tiles are actually in the tree (a shrunken page that
    // dropped content would trivially "fit").
    for (final key in _rowKeysInOrder) {
      expect(find.byKey(ValueKey(key)), findsOneWidget, reason: key);
    }
    expect(find.byKey(const ValueKey('settings-my-qr-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-scan-tile')), findsOneWidget);

    expect(pageScrollPosition(tester).maxScrollExtent, 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('T2 grouped rows with keys render in order', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(wrapScreen());

    // Section labels from the two NEW l10n keys.
    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('PREFERENCES'), findsOneWidget);

    var previousDy = double.negativeInfinity;
    for (final key in _rowKeysInOrder) {
      final dy = tester.getTopLeft(find.byKey(ValueKey(key))).dy;
      expect(
        dy,
        greaterThan(previousDy),
        reason: '$key out of order (dy=$dy, previous=$previousDy)',
      );
      previousDy = dy;
    }
  });

  testWidgets('T3 rows show persisted at-rest values after settle', (
    tester,
  ) async {
    setPhoneViewport(tester);
    final store = FakeSecureKeyStore();
    await store.write(BackgroundPreference.storageKey, 'cosmic');
    await store.write(ImageQualityPreference.storageKey, 'original');
    await store.write(ImageQualityPreference.videoStorageKey, 'original');
    final identityRepo = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'value-peer',
          mnemonic12: twelveWords,
        ),
      );

    await pumpWired(tester, identityRepo: identityRepo, store: store);

    // The at-rest values on the rows — no sub-sheet opened. With the inline
    // chooser retired, 'Cosmic' appears exactly once (the background row
    // value) and 'Original' exactly twice (photo + video rows).
    expect(find.text('Cosmic'), findsOneWidget);
    expect(find.text('Original'), findsNWidgets(2));
    expect(find.text('Compressed'), findsNothing);
  });

  testWidgets('T4 667pt viewport scrolls with every row reachable', (
    tester,
  ) async {
    setViewport(tester, const Size(390, 667));
    await tester.pumpWidget(wrapScreen());

    expect(pageScrollPosition(tester).maxScrollExtent, greaterThan(0.0));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-move-account-action')),
      120,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey('settings-move-account-action')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('T5 textScale 1.5 lays out without overflow', (tester) async {
    setPhoneViewport(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(wrapScreen());
    expect(tester.takeException(), isNull);

    // The page may become scrollable at 1.5x — every control stays reachable.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-move-account-action')),
      120,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.byKey(const ValueKey('settings-move-account-action')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('T6 daylight tone renders light readable roles on rows', (
    tester,
  ) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(
      wrapScreen(backgroundPreference: BackgroundPreference.daylightLagoon),
    );

    final rowLabel = tester.widget<Text>(find.text('Background'));
    expect(
      rowLabel.style?.color,
      BackgroundReadableColors.representativeLight.textPrimary,
    );

    final title = tester.widget<Text>(find.text('Settings'));
    expect(
      title.style?.color,
      BackgroundReadableColors.representativeLight.textPrimary,
    );
  });

  testWidgets('T7 ar full-page RTL renders without overflow', (tester) async {
    setPhoneViewport(tester);
    await tester.pumpWidget(wrapScreen(locale: const Locale('ar')));

    expect(tester.takeException(), isNull);
    expect(find.text('الإعدادات'), findsOneWidget);
    expect(find.text('الخلفية'), findsOneWidget);
    expect(find.text('مشاركة القريبين منك'), findsOneWidget);
    // Row chevrons render under RTL.
    expect(find.byIcon(Icons.chevron_right), findsWidgets);
    // Tiles mirror with the page (locked in detail by settings_qr_tiles T2).
    expect(find.text('رمزي'), findsOneWidget);
    expect(find.text('مسح'), findsOneWidget);
  });

  testWidgets('T8 row value updates in place after sub-sheet change', (
    tester,
  ) async {
    setPhoneViewport(tester);
    final store = FakeSecureKeyStore();
    final identityRepo = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'refresh-peer',
          mnemonic12: twelveWords,
        ),
      );
    await pumpWired(tester, identityRepo: identityRepo, store: store);

    expect(find.text('Default'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-row-background')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(BackgroundChoiceControl), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));

    // Sheet closed back to the page; the row value updated in place.
    expect(find.byType(BackgroundChoiceControl), findsNothing);
    expect(find.text('Cosmic'), findsOneWidget);
    expect(await store.read(BackgroundPreference.storageKey), 'cosmic');
  });

  testWidgets('T9 reopen reconstructs values from storage', (tester) async {
    setPhoneViewport(tester);
    final store = FakeSecureKeyStore();
    final identityRepo = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'durable-peer',
          mnemonic12: twelveWords,
        ),
      );
    await pumpWired(tester, identityRepo: identityRepo, store: store);

    await tester.tap(find.byKey(const ValueKey('settings-row-background')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Cosmic'), findsOneWidget);

    // Dispose the whole tree, then re-mount against the SAME store: the value
    // must come back from storage, not from ephemeral widget state.
    await tester.pumpWidget(const SizedBox());
    await pumpWired(tester, identityRepo: identityRepo, store: store);

    expect(find.text('Cosmic'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
  });
}
