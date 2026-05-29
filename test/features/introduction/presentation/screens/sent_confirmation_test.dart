import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/introduction/presentation/screens/sent_confirmation_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  Widget buildSubject({
    required int introductionCount,
    required List<String> introducedUsernames,
    VoidCallback? onBackToConversation,
    BackgroundPreference backgroundPreference =
        BackgroundPreference.defaultBackground,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SentConfirmationScreen(
          introductionCount: introductionCount,
          introducedUsernames: introducedUsernames,
          onBackToConversation: onBackToConversation ?? () {},
          backgroundPreference: backgroundPreference,
        ),
      ),
    );
  }

  testWidgets('correct count displayed in title', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 3,
        introducedUsernames: ['Alice', 'Bob', 'Charlie'],
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('3 introductions sent'), findsOneWidget);
  });

  testWidgets('singular form for count of 1', (tester) async {
    await tester.pumpWidget(
      buildSubject(introductionCount: 1, introducedUsernames: ['Alice']),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('1 introduction sent'), findsOneWidget);
  });

  testWidgets('avatar row renders friend names with overflow', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 5,
        introducedUsernames: ['Alice', 'Bob', 'Charlie', 'Dave', 'Eve'],
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      find.textContaining('Alice, Bob, Charlie and 2 more'),
      findsOneWidget,
    );
  });

  testWidgets('"Back to conversation" button triggers callback', (
    tester,
  ) async {
    var callbackCalled = false;
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 1,
        introducedUsernames: ['Alice'],
        onBackToConversation: () => callbackCalled = true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    await tester.tap(find.text('Back to conversation'));
    await tester.pump();

    expect(callbackCalled, isTrue);
  });

  testWidgets('daylight background uses light readable text roles', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        introductionCount: 2,
        introducedUsernames: ['Alice', 'Bob'],
        backgroundPreference: BackgroundPreference.daylightLagoon,
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(DaylightLagoonBackground), findsOneWidget);

    const colors = BackgroundReadableColors.representativeLight;
    final titleColor = tester
        .widget<Text>(find.text('2 introductions sent'))
        .style
        ?.color;
    final namesColor = tester
        .widget<Text>(find.text('Alice, Bob'))
        .style
        ?.color;

    expect(titleColor, colors.textPrimary);
    expect(namesColor, colors.textMuted);
    expectTextContrast(titleColor!, Colors.white);
    expectTextContrast(namesColor!, Colors.white);
  });
}
