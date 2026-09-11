import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/settings/application/call_privacy_preference_use_cases.dart';
import 'package:flutter_app/features/settings/presentation/widgets/call_privacy_settings_control.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';

class _Store extends FakeSecureKeyStore {
  bool failRead = false;
  bool failWrite = false;
  Completer<void>? writeGate;

  @override
  Future<String?> read(String key) {
    if (failRead) throw StateError('unavailable');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    await writeGate?.future;
    if (failWrite) throw StateError('unavailable');
    await super.write(key, value);
  }
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    _Store store, {
    bool forceRelay = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CallPrivacySettingsControl(
            secureKeyStore: store,
            forceRelay: forceRelay,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saves explicit opt-in and opt-out; explains media and signaling scope',
    (tester) async {
      final store = _Store();
      await pump(tester, store);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      expect(find.textContaining('IP address'), findsOneWidget);
      expect(find.textContaining('Direct signaling'), findsOneWidget);
      for (final value in [true, false]) {
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(
          await loadAlwaysRelayCallsPreference(secureKeyStore: store),
          value,
        );
        expect(tester.widget<Switch>(find.byType(Switch)).value, value);
      }
    },
  );

  testWidgets(
    'unreadable preference shows protected state and retry, never an opt-out',
    (tester) async {
      final store = _Store()..failRead = true;
      await pump(tester, store);
      var control = tester.widget<Switch>(find.byType(Switch));
      expect(control.value, true);
      expect(control.onChanged, isNull);
      expect(find.textContaining('Could not load'), findsOneWidget);
      store.failRead = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      control = tester.widget<Switch>(find.byType(Switch));
      expect(control.value, false);
      expect(control.onChanged, isNotNull);
    },
  );

  testWidgets(
    'a failed opt-out never displays or persists a privacy downgrade',
    (tester) async {
      final store = _Store();
      await saveAlwaysRelayCallsPreference(
        secureKeyStore: store,
        alwaysRelay: true,
      );
      store.failWrite = true;
      await pump(tester, store);
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(await loadAlwaysRelayCallsPreference(secureKeyStore: store), true);
      expect(find.textContaining('Could not save'), findsOneWidget);
    },
  );

  testWidgets(
    'pending writes serialize changes and keep the last saved choice visible',
    (tester) async {
      final store = _Store();
      await pump(tester, store);
      store.writeGate = Completer<void>();
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      store.writeGate!.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
    },
  );

  testWidgets(
    'rollout notice distinguishes current transport from the saved preference',
    (tester) async {
      final store = _Store();
      await pump(tester, store, forceRelay: true);
      expect(find.textContaining('currently relays all calls'), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      expect(await store.read(alwaysRelayCallsStorageKey), isNull);
    },
  );
}
