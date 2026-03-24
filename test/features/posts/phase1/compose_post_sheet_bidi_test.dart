import 'dart:ui' show TextDirection;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/presentation/widgets/compose_post_sheet.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget buildWidget() {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ComposePostSheet(
          eligibleContacts: const <ContactModel>[],
          onSubmit: (_) async {},
        ),
      ),
    );
  }

  testWidgets('Arabic-only input drives RTL', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.enterText(find.byType(TextField), 'مرحبا');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('Arabic-first mixed input drives RTL', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.enterText(find.byType(TextField), 'مرحبا Hello 123');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.rtl,
    );
  });

  testWidgets('English-first mixed input stays LTR', (tester) async {
    await tester.pumpWidget(buildWidget());
    await tester.enterText(find.byType(TextField), 'Hello مرحبا 123');
    await tester.pump();

    expect(
      tester.widget<TextField>(find.byType(TextField)).textDirection,
      TextDirection.ltr,
    );
  });
}
