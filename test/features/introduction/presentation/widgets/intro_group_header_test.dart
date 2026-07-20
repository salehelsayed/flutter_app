import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  Text textWidget(WidgetTester tester, String text) {
    return tester.widget<Text>(find.text(text));
  }

  group('IntroGroupHeader', () {
    testWidgets('renders mixed-script introducer usernames', (tester) async {
      await tester.pumpWidget(
        wrap(const IntroGroupHeader(introducerUsername: 'ليلى Alpha')),
      );

      expect(find.text('From'), findsOneWidget);
      expect(find.text('ليلى Alpha'), findsOneWidget);
    });

    testWidgets('renders plain English usernames', (tester) async {
      await tester.pumpWidget(
        wrap(const IntroGroupHeader(introducerUsername: 'Alice')),
      );

      expect(find.text('From'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('dynamic Arabic-first username stays explicit inside header', (
      tester,
    ) async {
      const username = 'ليلى Alpha';
      await tester.pumpWidget(
        wrap(const IntroGroupHeader(introducerUsername: username)),
      );

      expect(textWidget(tester, username).textDirection, TextDirection.rtl);
      expect(
        tester.getTopLeft(find.text('From')).dx,
        lessThan(tester.getTopLeft(find.text(username)).dx),
      );
    });

    testWidgets('dynamic English-first username stays explicit inside header', (
      tester,
    ) async {
      const username = 'Alpha ليلى';
      await tester.pumpWidget(
        wrap(const IntroGroupHeader(introducerUsername: username)),
      );

      expect(textWidget(tester, username).textDirection, TextDirection.ltr);
      expect(
        tester.getTopLeft(find.text('From')).dx,
        lessThan(tester.getTopLeft(find.text(username)).dx),
      );
    });
  });
}
