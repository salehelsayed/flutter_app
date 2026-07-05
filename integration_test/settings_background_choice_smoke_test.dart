import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background_mirrored.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_app/features/settings/presentation/widgets/background_choice_control.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class _SmokeSecureKeyStore implements SecureKeyStore {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Settings background choice smoke over Feed', (tester) async {
    final secureKeyStore = _SmokeSecureKeyStore();
    var currentPreference = BackgroundPreference.defaultBackground;

    Future<void> openSettings(
      BuildContext context,
      StateSetter setHomeState,
    ) async {
      currentPreference = await loadBackgroundPreference(
        secureKeyStore: secureKeyStore,
      );

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => StatefulBuilder(
            builder: (context, setRouteState) => SettingsScreen(
              username: 'Alice',
              peerId: '12D3KooWSmokePeer',
              currentBackgroundPreference: currentPreference,
              // 209: the inline chooser retired — the row opens a focused
              // sheet hosting the same BackgroundChoiceControl (mirrors the
              // SettingsWired sheet wiring at the pure-UI level).
              onOpenBackgroundSheet: () {
                showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  builder: (sheetContext) => Container(
                    color: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: BackgroundChoiceControl(
                      value: currentPreference,
                      onChanged: (preference) async {
                        await saveBackgroundPreference(
                          secureKeyStore: secureKeyStore,
                          preference: preference,
                        );
                        setRouteState(() => currentPreference = preference);
                        if (sheetContext.mounted) {
                          Navigator.of(sheetContext).pop();
                        }
                      },
                    ),
                  ),
                );
              },
              onBack: () => Navigator.of(context).pop(),
              onSwitchView: (_) {},
              activeTab: 'feed',
              showNavigationBar: false,
            ),
          ),
        ),
      );

      final reloaded = await loadBackgroundPreference(
        secureKeyStore: secureKeyStore,
      );
      setHomeState(() => currentPreference = reloaded);
    }

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StatefulBuilder(
          builder: (context, setHomeState) => Scaffold(
            body: Builder(
              builder: (context) => Stack(
                children: [
                  FeedScreen(
                    username: 'Alice',
                    feedItems: const <FeedItem>[],
                    onSwitchView: (_) {},
                    activeTab: 'feed',
                    backgroundPreference: currentPreference,
                  ),
                  SafeArea(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: ElevatedButton(
                        key: const ValueKey('open-settings-smoke'),
                        onPressed: () => openSettings(context, setHomeState),
                        child: const Text('Open Settings'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    Future<void> openSettingsPage() async {
      await tester.tap(find.byKey(const ValueKey('open-settings-smoke')));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> openBackgroundSheet() async {
      await tester.tap(find.byKey(const ValueKey('settings-row-background')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> selectBackground(String optionKey) async {
      await openBackgroundSheet();
      await tester.ensureVisible(find.byKey(ValueKey(optionKey)));
      await tester.tap(find.byKey(ValueKey(optionKey)));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    Future<void> popToFeed() async {
      await tester.tap(find.byIcon(Icons.chevron_left));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 80));
      }
    }

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(AmbientBackground), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);

    await openSettingsPage();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);

    // The options live behind the row's focused sheet now.
    await openBackgroundSheet();
    expect(find.text('Cosmic'), findsOneWidget);
    expect(find.text('Mirrored cosmic'), findsOneWidget);
    expect(find.text('Daylight Lagoon'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-default-selected-icon')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('background-choice-daylight-lagoon')),
    );
    await tester.tap(
      find.byKey(const ValueKey('background-choice-daylight-lagoon')),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'daylight_lagoon',
    );
    expect(find.text('Daylight Lagoon'), findsOneWidget); // row value
    expect(find.byType(DaylightLagoonBackground), findsOneWidget);

    await popToFeed();

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(AmbientBackground), findsOneWidget);
    expect(find.byType(DaylightLagoonBackground), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);

    await openSettingsPage();
    expect(find.text('Background'), findsOneWidget);
    await openBackgroundSheet();
    expect(
      find.byKey(
        const ValueKey('background-choice-daylight-lagoon-selected-icon'),
      ),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('background-choice-cosmic-mirrored')),
    );
    await tester.tap(
      find.byKey(const ValueKey('background-choice-cosmic-mirrored')),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'cosmic_mirrored',
    );
    expect(find.text('Mirrored cosmic'), findsOneWidget); // row value

    await popToFeed();

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(AmbientBackground), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsOneWidget);

    await openSettingsPage();
    expect(find.text('Background'), findsOneWidget);
    await selectBackground('background-choice-cosmic');
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'cosmic',
    );
    expect(find.text('Cosmic'), findsOneWidget); // row value

    await popToFeed();

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(CosmicBackground), findsOneWidget);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);

    await openSettingsPage();
    await selectBackground('background-choice-default');
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'default',
    );

    await popToFeed();

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
    expect(find.byType(CosmicBackgroundMirrored), findsNothing);
  });
}
