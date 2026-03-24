import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/presentation/widgets/edit_pinned_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildWidget(String initialText) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: EditPinnedPostSheet(
          initialText: initialText,
          onSubmit: (_) async {},
        ),
      ),
    );
  }

  testWidgets('Arabic-only hydrated initialText starts RTL on first frame', (
    tester,
  ) async {
    await tester.pumpWidget(buildWidget('مرحبا'));

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets(
    'Arabic-first mixed hydrated initialText starts RTL on first frame',
    (tester) async {
      await tester.pumpWidget(buildWidget('مرحبا Hello 123'));

      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.rtl,
      );
    },
  );

  testWidgets(
    'English-first mixed hydrated initialText stays LTR on first frame',
    (tester) async {
      await tester.pumpWidget(buildWidget('Hello مرحبا 123'));

      expect(
        tester.widget<TextField>(find.byType(TextField)).textDirection,
        TextDirection.ltr,
      );
    },
  );
}
