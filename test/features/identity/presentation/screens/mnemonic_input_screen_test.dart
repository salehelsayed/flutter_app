import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/screens/mnemonic_input_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  group('MnemonicInputScreen', () {
    testWidgets('renders "Enter Recovery Phrase" title', (tester) async {
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) async {},
      )));
      expect(find.text('Recovery phrase'), findsOneWidget);
    });

    testWidgets('renders subtitle instruction text', (tester) async {
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) async {},
      )));
      expect(find.text('Please enter exactly 12 words'), findsOneWidget);
    });

    testWidgets('renders multiline TextField (4 lines)', (tester) async {
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) async {},
      )));
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.maxLines, 4);
    });

    testWidgets('renders "Restore identity" button', (tester) async {
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) async {},
      )));
      expect(find.text('Restore identity'), findsOneWidget);
    });

    testWidgets('shows back button in AppBar', (tester) async {
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) async {},
      )));
      expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    });

    testWidgets('button shows loading indicator when restore is in progress', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(wrap(MnemonicInputScreen(
        onRestorePressed: (_) => completer.future,
      )));
      // Tap the restore button
      await tester.tap(find.text('Restore identity'));
      await tester.pump();
      // Should show CircularProgressIndicator instead of text
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Restore identity'), findsNothing);
      // Complete the future to avoid pending timers
      completer.complete();
      await tester.pumpAndSettle();
    });
  });
}
