import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/features/settings/presentation/widgets/app_diagnostics_settings_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late AppDiagnostics diagnostics;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('app-settings-test-');
    diagnostics = await AppDiagnostics.installForTesting(directory: directory);
  });

  tearDown(() async {
    await diagnostics.dispose();
    await directory.delete(recursive: true);
  });

  testWidgets('support code is copyable and opting out disables collection', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    String? copied;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: AppDiagnosticsSettingsSection()),
      ),
    );
    await tester.tap(find.text('App diagnostics'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sharing is on by default'), findsOneWidget);
    final copy = find.widgetWithText(TextButton, 'Copy support code');
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, diagnostics.supportCode);
    expect(AppDiagnostics.isValidTraceId(copied), true);
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(toggle);
      await diagnostics.flush();
      await diagnostics.eventsForTesting();
    });
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(diagnostics.enabled, false);
    expect(diagnostics.startAttempt(feature: 'message'), isNull);
    expect(find.text('Copy support code'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });

  for (final (language, title, switchLabel, copyLabel, privacy, defaultNotice)
      in [
        (
          'ar',
          'تشخيص التطبيق',
          'مشاركة بيانات تشخيص التطبيق',
          'نسخ رمز الدعم',
          'لا تشمل الرسائل',
          'المشاركة مفعّلة افتراضيًا.',
        ),
        (
          'de',
          'App-Diagnose',
          'App-Diagnosedaten teilen',
          'Supportcode kopieren',
          'Keine Nachrichten',
          'Das Teilen ist standardmäßig aktiviert.',
        ),
      ]) {
    testWidgets('app diagnostic disclosure and controls use $language', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: AppDiagnosticsSettingsSection()),
        ),
      );
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text(switchLabel), findsOneWidget);
      expect(find.text(copyLabel), findsOneWidget);
      expect(find.textContaining(privacy), findsOneWidget);
      expect(find.textContaining(defaultNotice), findsOneWidget);
      expect(find.text('App diagnostics'), findsNothing);
      expect(find.text('Copy support code'), findsNothing);
      expect(
        Directionality.of(tester.element(find.byType(SwitchListTile))),
        language == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
    });
  }
}
