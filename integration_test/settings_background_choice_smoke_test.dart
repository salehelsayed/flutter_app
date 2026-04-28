import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/feed/domain/models/feed_item.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_screen.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/cosmic_background.dart';
import 'package:flutter_app/features/settings/application/background_preference_use_cases.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/screens/settings_screen.dart';
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
              onBackgroundPreferenceChanged: (preference) async {
                await saveBackgroundPreference(
                  secureKeyStore: secureKeyStore,
                  preference: preference,
                );
                setRouteState(() => currentPreference = preference);
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

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(AmbientBackground), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);

    await tester.tap(find.byKey(const ValueKey('open-settings-smoke')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Cosmic'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('background-choice-cosmic')),
    );
    await tester.tap(find.byKey(const ValueKey('background-choice-cosmic')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'cosmic',
    );
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.chevron_left));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(AmbientBackground), findsOneWidget);
    expect(find.byType(CosmicBackground), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('open-settings-smoke')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.text('Background'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('background-choice-cosmic-selected-icon')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('background-choice-default')),
    );
    await tester.tap(find.byKey(const ValueKey('background-choice-default')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      await secureKeyStore.read(BackgroundPreference.storageKey),
      'default',
    );

    await tester.tap(find.byIcon(Icons.chevron_left));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }

    expect(find.byType(FeedScreen), findsOneWidget);
    expect(find.byType(CosmicBackground), findsNothing);
  });
}
