import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/session_divider.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  group('SessionDivider', () {
    testWidgets('renders "PREVIOUSLY SEEN" text', (tester) async {
      await tester.pumpWidget(wrap(const SessionDivider()));
      expect(find.text('PREVIOUSLY SEEN'), findsOneWidget);
    });

    testWidgets('text has letterSpacing of 1', (tester) async {
      await tester.pumpWidget(wrap(const SessionDivider()));
      final text = tester.widget<Text>(find.text('PREVIOUSLY SEEN'));
      expect(text.style?.letterSpacing, 1);
    });

    testWidgets('renders two gradient divider lines', (tester) async {
      await tester.pumpWidget(wrap(const SessionDivider()));
      expect(find.byType(Expanded), findsNWidgets(2));
    });
  });
}
