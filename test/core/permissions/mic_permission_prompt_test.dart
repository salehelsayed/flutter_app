import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/permissions/mic_permission_prompt.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../shared/fakes/fake_mic_permission_gateway.dart';

void main() {
  Future<void> openPrompt(
    WidgetTester tester,
    FakeMicPermissionGateway gateway,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showMicPermissionDeniedPrompt(context, gateway: gateway),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'permanentlyDenied shows the rationale sheet with an Open Settings action',
    (tester) async {
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final gateway = FakeMicPermissionGateway()
        ..statusToReturn = MicPermissionStatus.permanentlyDenied;
      await openPrompt(tester, gateway);

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byKey(const ValueKey('mic-perm-sheet')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(l10n.mic_perm_dialog_title), findsOneWidget);
      expect(find.text(l10n.mic_perm_dialog_body), findsOneWidget);
      expect(
        find.byKey(const ValueKey('mic-perm-open-settings')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('mic-perm-not-now')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets(
    'denied mic prompt uses allow-microphone copy with settings recovery',
    (tester) async {
      final gateway = FakeMicPermissionGateway();
      await openPrompt(tester, gateway);

      expect(find.text('Allow microphone access'), findsOneWidget);
      expect(
        find.text(
          "To record voice messages, turn it on in your phone's settings.",
        ),
        findsOneWidget,
      );
      expect(find.text('Not now'), findsOneWidget);
      expect(find.text('Open Settings'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('mic-perm-open-settings')));
      await tester.pumpAndSettle();

      expect(gateway.openAppSettingsCallCount, 1);
    },
  );

  testWidgets(
    'tapping Open Settings invokes gateway.openAppSettings exactly once and dismisses',
    (tester) async {
      final gateway = FakeMicPermissionGateway();
      await openPrompt(tester, gateway);

      await tester.tap(find.byKey(const ValueKey('mic-perm-open-settings')));
      await tester.pumpAndSettle();

      expect(gateway.openAppSettingsCallCount, 1);
      // Guard against wiring the deep-link to the wrong button.
      expect(gateway.requestCallCount, 0);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );

  testWidgets('tapping Not now dismisses without opening settings', (
    tester,
  ) async {
    final gateway = FakeMicPermissionGateway();
    await openPrompt(tester, gateway);

    await tester.tap(find.byKey(const ValueKey('mic-perm-not-now')));
    await tester.pumpAndSettle();

    expect(gateway.openAppSettingsCallCount, 0);
    expect(find.byType(BottomSheet), findsNothing);
  });
}
