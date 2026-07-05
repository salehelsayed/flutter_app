import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';

void main() {
  Widget wrap({
    String username = 'Alice',
    String? peerId,
    String? mnemonic,
    bool isPeerIdCopied = false,
    VoidCallback? onBack,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    BackgroundReadableTone? readableToneOverride,
    VoidCallback? onMyQr,
    VoidCallback? onScan,
    VoidCallback? onOpenBackgroundSheet,
    VoidCallback? onOpenPhotoQualitySheet,
    VoidCallback? onOpenVideoQualitySheet,
    VoidCallback? onOpenRecoverySheet,
    ImageQualityPreference currentQuality = ImageQualityPreference.compressed,
    ImageQualityPreference currentVideoQuality =
        ImageQualityPreference.original,
    bool isNearbySharingEnabled = false,
    ValueChanged<bool>? onNearbySharingChanged,
    VoidCallback? onMoveAccountToNewPhone,
    bool showNavigationBar = true,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SettingsScreen(
          username: username,
          peerId: peerId,
          mnemonic: mnemonic,
          isPeerIdCopied: isPeerIdCopied,
          onBack: onBack,
          currentBackgroundPreference: backgroundPreference,
          onMyQr: onMyQr,
          onScan: onScan,
          onOpenBackgroundSheet: onOpenBackgroundSheet,
          onOpenPhotoQualitySheet: onOpenPhotoQualitySheet,
          onOpenVideoQualitySheet: onOpenVideoQualitySheet,
          onOpenRecoverySheet: onOpenRecoverySheet,
          currentQuality: currentQuality,
          currentVideoQuality: currentVideoQuality,
          isNearbySharingEnabled: isNearbySharingEnabled,
          onNearbySharingChanged: onNearbySharingChanged,
          onMoveAccountToNewPhone: onMoveAccountToNewPhone,
          onSwitchView: (_) {},
          activeTab: 'feed',
          showNavigationBar: showNavigationBar,
          readableToneOverride: readableToneOverride,
        ),
      ),
    );
  }

  const twelveWords =
      'one two three four five six seven eight nine ten eleven twelve';

  testWidgets('renders "Settings" title', (tester) async {
    await tester.pumpWidget(
      wrap(peerId: '12D3KooWTestPeer123', mnemonic: twelveWords),
    );

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('header uses representative light readable roles', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        readableToneOverride: BackgroundReadableTone.representativeLight,
      ),
    );

    final title = tester.widget<Text>(find.text('Settings'));
    expect(
      title.style?.color,
      BackgroundReadableColors.representativeLight.textPrimary,
    );

    final backIcon = tester.widget<Icon>(find.byIcon(Icons.chevron_left));
    expect(
      backIcon.color,
      BackgroundReadableColors.representativeLight.iconPrimary,
    );
  });

  testWidgets('back button calls onBack', (tester) async {
    var backed = false;
    await tester.pumpWidget(
      wrap(peerId: '12D3KooWTestPeer123', onBack: () => backed = true),
    );

    await tester.tap(find.byIcon(Icons.chevron_left));
    expect(backed, isTrue);
  });

  testWidgets('renders profile section and identity rows', (tester) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        mnemonic: twelveWords,
        onOpenRecoverySheet: () {},
      ),
    );

    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-row-peer-id')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-row-recovery')), findsOneWidget);
  });

  testWidgets('hides peer ID row when peerId is null', (tester) async {
    await tester.pumpWidget(
      wrap(peerId: null, mnemonic: twelveWords, onOpenRecoverySheet: () {}),
    );

    expect(find.byKey(const ValueKey('settings-row-peer-id')), findsNothing);
  });

  testWidgets('hides recovery row when mnemonic is null', (tester) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        mnemonic: null,
        onOpenRecoverySheet: () {},
      ),
    );

    expect(find.byKey(const ValueKey('settings-row-recovery')), findsNothing);
  });

  testWidgets('renders FeedNavigationBar', (tester) async {
    await tester.pumpWidget(wrap(peerId: '12D3KooWTestPeer123'));

    expect(find.byType(FeedNavigationBar), findsOneWidget);
  });

  testWidgets('background row shows the active choice at rest', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(peerId: '12D3KooWTestPeer123', onOpenBackgroundSheet: () {}),
    );

    expect(
      find.byKey(const ValueKey('settings-row-background')),
      findsOneWidget,
    );
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    // The always-expanded inline chooser is retired: no other option labels.
    expect(find.text('Cosmic'), findsNothing);
  });

  testWidgets('background row tap opens the sheet callback', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        onOpenBackgroundSheet: () => opened++,
      ),
    );

    await tester.tap(find.byKey(const ValueKey('settings-row-background')));
    expect(opened, 1);
  });

  testWidgets('renders selected cosmic as the full-screen background', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        backgroundPreference: BackgroundPreference.cosmic,
        onOpenBackgroundSheet: () {},
      ),
    );

    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);
  });

  testWidgets(
    'renders selected daylight lagoon with light readable Settings chrome',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          peerId: '12D3KooWTestPeer123',
          backgroundPreference: BackgroundPreference.daylightLagoon,
          onOpenBackgroundSheet: () {},
        ),
      );

      expect(find.byType(DaylightLagoonBackground), findsOneWidget);
      expect(find.text('Daylight Lagoon'), findsOneWidget);

      final title = tester.widget<Text>(find.text('Settings'));
      expect(
        title.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );
    },
  );

  testWidgets('daylight full page includes every One-Screen section', (
    tester,
  ) async {
    const peerId =
        '12D3KooWLongPeerForSettingsLightThemeVisualCoverage123456789';

    await tester.pumpWidget(
      wrap(
        username: 'AliceTheLightThemeTester',
        peerId: peerId,
        mnemonic:
            'abandon ability able about above absent absorb abstract absurd abuse access accident',
        backgroundPreference: BackgroundPreference.daylightLagoon,
        isPeerIdCopied: true,
        onMyQr: () {},
        onScan: () {},
        onOpenBackgroundSheet: () {},
        onOpenPhotoQualitySheet: () {},
        onOpenVideoQualitySheet: () {},
        onOpenRecoverySheet: () {},
        isNearbySharingEnabled: true,
        onNearbySharingChanged: (_) {},
        onMoveAccountToNewPhone: () {},
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byType(FeedNavigationBar), findsOneWidget);
    expect(find.text('@AliceTheLightThemeTester'), findsOneWidget);
    expect(find.text(peerId), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-my-qr-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-scan-tile')), findsOneWidget);
    expect(find.text('IDENTITY'), findsOneWidget);
    expect(find.text('PREFERENCES'), findsOneWidget);
    expect(find.text('Photo Quality'), findsOneWidget);
    expect(find.text('Video Quality'), findsOneWidget);
    expect(find.text('Share People Nearby'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('RECOVERY PHRASE'), findsOneWidget);
    // The peer-id copy trailing reflects the copied state.
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('renders move account row when callback is supplied', (
    tester,
  ) async {
    var movePressed = false;

    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        onMoveAccountToNewPhone: () => movePressed = true,
      ),
    );

    expect(find.text('Move account to new phone'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-move-account-action')),
    );
    await tester.tap(
      find.byKey(const ValueKey('settings-move-account-action')),
    );
    await tester.pump();

    expect(movePressed, isTrue);
  });

  testWidgets('daylight full page handles optional sections absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: null,
        mnemonic: null,
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-row-peer-id')), findsNothing);
    expect(find.byKey(const ValueKey('settings-row-recovery')), findsNothing);
    expect(find.byKey(const ValueKey('settings-row-background')), findsNothing);
    expect(find.byKey(const ValueKey('settings-my-qr-tile')), findsNothing);
    expect(find.text('Photo Quality'), findsNothing);
    expect(find.text('Video Quality'), findsNothing);
    expect(find.text('Share People Nearby'), findsNothing);
    expect(find.byType(FeedNavigationBar), findsOneWidget);
  });
}
