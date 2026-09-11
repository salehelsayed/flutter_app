import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/settings/presentation/widgets/call_diagnostics_settings_section.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('large report preview stays bounded and copies the full report', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    final report =
        '${List.filled(60000, '{"stage":"preflight","reason":"none"}').join('\n')}\nEND_OF_FULL_REPORT';
    String? copied;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CallDiagnosticsSettingsSection(
            enabled: enabled,
            setEnabled: (value) async => enabled.value = value,
            exportPreview: () async => report,
            clear: () async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Call diagnostics'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preview support report'));
    await tester.pumpAndSettle();
    final visibleReport = tester
        .widget<SelectableText>(find.byType(SelectableText))
        .data!;
    expect(visibleReport.length, lessThanOrEqualTo(8194));
    expect(visibleReport, startsWith('{"stage":"preflight"'));
    expect(visibleReport, isNot(contains('END_OF_FULL_REPORT')));
    expect(
      find.text('Showing part of the report. Copy includes the full report.'),
      findsOneWidget,
    );
    final copy = find.widgetWithText(TextButton, 'Copy support report');
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, report);
    expect(find.text('Support report copied'), findsOneWidget);
    Navigator.of(tester.element(copy)).pop();
    await tester.pumpAndSettle();
    expect(find.byType(SelectableText), findsNothing);
    expect(find.text('Call diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sharing status distinguishes pending setup and incomplete uploads',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      var status = <String, Object?>{
        'enabled': true,
        'consentPending': true,
        'storageHealthy': true,
        'queuedEvents': 7,
        'droppedEvents': 0,
        'lastUploadAtMs': 0,
      };
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CallDiagnosticsSettingsSection(
              enabled: enabled,
              setEnabled: (_) async {},
              exportPreview: () async => '{}',
              clear: () async {},
              status: () async => status,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Call diagnostics'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Sharing setup is pending'), findsOneWidget);
      expect(find.text('Sharing is ready.'), findsNothing);
      expect(find.text('7 events waiting to upload'), findsOneWidget);
      expect(find.textContaining('Last upload:'), findsNothing);
      status = <String, Object?>{
        'enabled': true,
        'consentPending': false,
        'storageHealthy': true,
        'queuedEvents': 0,
        'droppedEvents': 2,
        'lastUploadAtMs': 1788879600000,
        'lastError': 'none',
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.text('Sharing is ready.'), findsOneWidget);
      expect(find.textContaining('Sharing setup is pending'), findsNothing);
      expect(find.text('0 events waiting to upload'), findsOneWidget);
      expect(find.textContaining('Last upload:'), findsOneWidget);
      expect(find.text('Upload is waiting to retry.'), findsNothing);
      expect(find.textContaining('Reports may be incomplete'), findsOneWidget);
      status = <String, Object?>{
        ...status,
        'enabled': false,
        'consentPending': true,
      };
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(
        find.textContaining('The server update is pending'),
        findsOneWidget,
      );
      status = <String, Object?>{...status, 'storageHealthy': false};
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      expect(find.textContaining('Reports cannot be saved'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
    },
  );

  for (final initiallyEnabled in <bool>[true, false]) {
    testWidgets(
      initiallyEnabled
          ? 'default-on sharing allows an explicit opt-out'
          : 'saved opt-out stays off until an explicit opt-in',
      (tester) async {
        final enabled = ValueNotifier(initiallyEnabled);
        addTearDown(enabled.dispose);
        final changes = <bool>[];
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: CallDiagnosticsSettingsSection(
                enabled: enabled,
                setEnabled: (value) async {
                  changes.add(value);
                  enabled.value = value;
                },
                exportPreview: () async => '{}',
                clear: () async {},
              ),
            ),
          ),
        );
        expect(changes, isEmpty);
        await tester.tap(find.text('Call diagnostics'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          initiallyEnabled,
        );
        expect(
          find.textContaining('Sharing is on by default.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('You can turn it off at any time.'),
          findsOneWidget,
        );
        expect(find.textContaining('off by default'), findsNothing);
        expect(find.textContaining('7 days'), findsOneWidget);
        expect(find.textContaining('14 days'), findsOneWidget);
        expect(find.textContaining('No audio'), findsOneWidget);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(changes, <bool>[!initiallyEnabled]);
        expect(enabled.value, !initiallyEnabled);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          !initiallyEnabled,
        );
      },
    );
  }

  testWidgets(
    'clear revokes sharing before clearing and blocks duplicate actions',
    (tester) async {
      final enabled = ValueNotifier(true);
      addTearDown(enabled.dispose);
      final clearGate = Completer<void>();
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: CallDiagnosticsSettingsSection(
              enabled: enabled,
              setEnabled: (value) async {
                events.add('enabled:$value');
                enabled.value = value;
              },
              exportPreview: () async =>
                  '{"stage":"preflight","reason":"microphone_denied"}',
              clear: () {
                events.add('clear');
                return clearGate.future;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Call diagnostics'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Preview support report'));
      await tester.pumpAndSettle();
      expect(find.textContaining('microphone_denied'), findsOneWidget);
      final clearButton = find.widgetWithText(
        TextButton,
        'Turn off and clear reports',
      );
      // The disclosure and preview can place this action below the viewport.
      await tester.ensureVisible(clearButton);
      await tester.pumpAndSettle();
      expect(clearButton.hitTestable(), findsOneWidget);
      await tester.tap(clearButton);
      await tester.pump();
      expect(events, <String>['enabled:false', 'clear']);
      final button = tester.widget<TextButton>(clearButton);
      expect(button.onPressed, isNull);
      clearGate.complete();
      await tester.pumpAndSettle();
      expect(find.textContaining('microphone_denied'), findsNothing);
    },
  );

  testWidgets('Arabic call status localizes counts dates and update failures', (
    tester,
  ) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CallDiagnosticsSettingsSection(
            enabled: enabled,
            setEnabled: (_) async => throw StateError('not displayed'),
            exportPreview: () async => '{}',
            clear: () async {},
            status: () async => <String, Object?>{
              'enabled': true,
              'consentPending': false,
              'storageHealthy': true,
              'queuedEvents': 2,
              'droppedEvents': 2,
              'lastUploadAtMs': 1788879600000,
              'lastError': 'none',
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('تشخيص المكالمات'));
    await tester.pumpAndSettle();
    expect(find.text('حدثان بانتظار الإرسال'), findsOneWidget);
    expect(
      find.text('تم إسقاط حدثين. قد تكون التقارير غير مكتملة.'),
      findsOneWidget,
    );
    expect(find.textContaining('آخر إرسال:'), findsOneWidget);
    expect(find.textContaining('Last upload:'), findsNothing);
    final toggle = find.byType(SwitchListTile);
    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(
      find.text('تعذّر تحديث إعدادات التشخيص. يُرجى المحاولة مجددًا.'),
      findsOneWidget,
    );
    expect(find.textContaining('not displayed'), findsNothing);
    expect(enabled.value, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
  });
}
