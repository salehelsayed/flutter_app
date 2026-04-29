import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';

void main() {
  Widget wrap({
    String username = 'Alice',
    String? peerId,
    String? mnemonic,
    bool isMnemonicRevealed = false,
    bool isPeerIdCopied = false,
    bool isMnemonicCopied = false,
    VoidCallback? onBack,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
    BackgroundReadableTone? readableToneOverride,
    ValueChanged<BackgroundPreference>? onBackgroundPreferenceChanged,
    bool showBackgroundChoice = true,
    String? backgroundPreferenceErrorText,
    ValueChanged<ImageQualityPreference>? onQualityChanged,
    ValueChanged<ImageQualityPreference>? onVideoQualityChanged,
    bool isNearbySharingEnabled = false,
    ValueChanged<bool>? onNearbySharingChanged,
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
          isMnemonicRevealed: isMnemonicRevealed,
          isPeerIdCopied: isPeerIdCopied,
          isMnemonicCopied: isMnemonicCopied,
          onBack: onBack,
          currentBackgroundPreference: backgroundPreference,
          onBackgroundPreferenceChanged: showBackgroundChoice
              ? onBackgroundPreferenceChanged ?? (_) {}
              : null,
          backgroundPreferenceErrorText: backgroundPreferenceErrorText,
          currentQuality: ImageQualityPreference.compressed,
          onQualityChanged: onQualityChanged,
          currentVideoQuality: ImageQualityPreference.original,
          onVideoQualityChanged: onVideoQualityChanged,
          isNearbySharingEnabled: isNearbySharingEnabled,
          onNearbySharingChanged: onNearbySharingChanged,
          onSwitchView: (_) {},
          activeTab: 'feed',
          showNavigationBar: showNavigationBar,
          readableToneOverride: readableToneOverride,
        ),
      ),
    );
  }

  testWidgets('renders "Settings" title', (tester) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        mnemonic:
            'one two three four five six seven eight nine ten eleven twelve',
      ),
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

  testWidgets('renders profile section, peer ID card, recovery phrase card', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        mnemonic:
            'one two three four five six seven eight nine ten eleven twelve',
      ),
    );

    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byType(SettingsPeerIdCard), findsOneWidget);
    expect(find.byType(SettingsRecoveryPhraseCard), findsOneWidget);
  });

  testWidgets('hides peer ID card when peerId is null', (tester) async {
    await tester.pumpWidget(
      wrap(
        peerId: null,
        mnemonic:
            'one two three four five six seven eight nine ten eleven twelve',
      ),
    );

    expect(find.byType(SettingsPeerIdCard), findsNothing);
  });

  testWidgets('hides recovery phrase card when mnemonic is null', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(peerId: '12D3KooWTestPeer123', mnemonic: null),
    );

    expect(find.byType(SettingsRecoveryPhraseCard), findsNothing);
  });

  testWidgets('renders FeedNavigationBar', (tester) async {
    await tester.pumpWidget(wrap(peerId: '12D3KooWTestPeer123'));

    expect(find.byType(FeedNavigationBar), findsOneWidget);
  });

  testWidgets('renders background choice with default selected', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(peerId: '12D3KooWTestPeer123'));

    expect(find.byType(BackgroundChoiceControl), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-default-selected-icon')),
      findsOneWidget,
    );
  });

  testWidgets('renders cosmic selected in picker', (tester) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        backgroundPreference: BackgroundPreference.cosmic,
      ),
    );

    expect(find.byType(BackgroundChoiceControl), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsOneWidget,
    );
  });

  testWidgets('renders selected cosmic as the full-screen background', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: '12D3KooWTestPeer123',
        backgroundPreference: BackgroundPreference.cosmic,
      ),
    );

    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders selected daylight lagoon with light readable Settings chrome',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          peerId: '12D3KooWTestPeer123',
          backgroundPreference: BackgroundPreference.daylightLagoon,
        ),
      );

      expect(find.byType(DaylightLagoonBackground), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('background-choice-daylight-lagoon-selected-icon'),
        ),
        findsOneWidget,
      );

      final title = tester.widget<Text>(find.text('Settings'));
      expect(
        title.style?.color,
        BackgroundReadableColors.representativeLight.textPrimary,
      );
    },
  );

  testWidgets('daylight full page includes every normal Settings section', (
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
        isMnemonicRevealed: true,
        isPeerIdCopied: true,
        isMnemonicCopied: true,
        onQualityChanged: (_) {},
        onVideoQualityChanged: (_) {},
        isNearbySharingEnabled: true,
        onNearbySharingChanged: (_) {},
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byType(BackgroundChoiceControl), findsOneWidget);
    expect(find.byType(SettingsPeerIdCard), findsOneWidget);
    expect(find.byType(SettingsRecoveryPhraseCard), findsOneWidget);
    expect(find.byType(FeedNavigationBar), findsOneWidget);
    expect(find.text('@AliceTheLightThemeTester'), findsOneWidget);
    expect(find.text(peerId), findsOneWidget);
    expect(find.text('Photo Quality'), findsOneWidget);
    expect(find.text('Video Quality'), findsOneWidget);
    expect(find.text('Share People Nearby'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('RECOVERY PHRASE'), findsOneWidget);
    expect(find.text('Copied!'), findsOneWidget);
    expect(find.text('Hide'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('background-choice-daylight-lagoon-selected-icon'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('daylight full page handles optional Settings sections absent', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        peerId: null,
        mnemonic: null,
        backgroundPreference: BackgroundPreference.daylightLagoon,
        showBackgroundChoice: false,
        onQualityChanged: null,
        onVideoQualityChanged: null,
        onNearbySharingChanged: null,
      ),
    );

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byType(SettingsPeerIdCard), findsNothing);
    expect(find.byType(SettingsRecoveryPhraseCard), findsNothing);
    expect(find.byType(BackgroundChoiceControl), findsNothing);
    expect(find.text('Photo Quality'), findsNothing);
    expect(find.text('Video Quality'), findsNothing);
    expect(find.text('Share People Nearby'), findsNothing);
    expect(find.byType(FeedNavigationBar), findsOneWidget);
  });
}
