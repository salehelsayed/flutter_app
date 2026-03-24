import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';

void main() {
  Widget wrap({
    String? peerId,
    String? mnemonic,
    VoidCallback? onBack,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(
        username: 'Alice',
        peerId: peerId,
        mnemonic: mnemonic,
        onBack: onBack,
        onSwitchView: (_) {},
        activeTab: 'feed',
      ),
    );
  }

  testWidgets('renders "Settings" title', (tester) async {
    await tester.pumpWidget(wrap(
      peerId: '12D3KooWTestPeer123',
      mnemonic: 'one two three four five six seven eight nine ten eleven twelve',
    ));

    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('back button calls onBack', (tester) async {
    var backed = false;
    await tester.pumpWidget(wrap(
      peerId: '12D3KooWTestPeer123',
      onBack: () => backed = true,
    ));

    await tester.tap(find.byIcon(Icons.chevron_left));
    expect(backed, isTrue);
  });

  testWidgets('renders profile section, peer ID card, recovery phrase card', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      peerId: '12D3KooWTestPeer123',
      mnemonic: 'one two three four five six seven eight nine ten eleven twelve',
    ));

    expect(find.byType(SettingsProfileSection), findsOneWidget);
    expect(find.byType(SettingsPeerIdCard), findsOneWidget);
    expect(find.byType(SettingsRecoveryPhraseCard), findsOneWidget);
  });

  testWidgets('hides peer ID card when peerId is null', (tester) async {
    await tester.pumpWidget(wrap(
      peerId: null,
      mnemonic: 'one two three four five six seven eight nine ten eleven twelve',
    ));

    expect(find.byType(SettingsPeerIdCard), findsNothing);
  });

  testWidgets('hides recovery phrase card when mnemonic is null', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(
      peerId: '12D3KooWTestPeer123',
      mnemonic: null,
    ));

    expect(find.byType(SettingsRecoveryPhraseCard), findsNothing);
  });

  testWidgets('renders FeedNavigationBar', (tester) async {
    await tester.pumpWidget(wrap(
      peerId: '12D3KooWTestPeer123',
    ));

    expect(find.byType(FeedNavigationBar), findsOneWidget);
  });
}
