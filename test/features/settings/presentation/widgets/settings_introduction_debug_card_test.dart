import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_introduction_debug_card.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

void main() {
  const light = BackgroundReadableColors.representativeLight;

  const intro = IntroductionModel(
    id: 'intro-1',
    introducerId: 'me',
    recipientId: 'peer-recipient',
    introducedId: 'peer-introduced',
    recipientUsername: 'Ann',
    introducedUsername: 'Bob',
    createdAt: '2026-01-01T00:00:00.000Z',
  );

  Widget wrap({
    required List<IntroductionModel> introductions,
    bool isLoading = false,
    String? errorText,
    VoidCallback? onRefresh,
    ValueChanged<String>? onDeleteIntroduction,
    ValueChanged<IntroductionModel>? onDeletePair,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(extensions: const [light]),
      home: Scaffold(
        backgroundColor: const Color(0xFFECE8E1),
        body: SingleChildScrollView(
          child: SettingsIntroductionDebugCard(
            introductions: introductions,
            isLoading: isLoading,
            errorText: errorText,
            onRefresh: onRefresh ?? () {},
            onDeleteIntroduction: onDeleteIntroduction ?? (_) {},
            onDeletePair: onDeletePair ?? (_) {},
          ),
        ),
      ),
    );
  }

  Color actionColor(WidgetTester tester, String key) {
    final text = tester.widget<Text>(
      find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text)),
    );
    return text.style!.color!;
  }

  testWidgets(
    'Signal introduction diagnostics use semantic light roles and preserve '
    'action callbacks',
    (tester) async {
      var refreshCount = 0;
      final deletedRows = <String>[];
      final deletedPairs = <IntroductionModel>[];

      await tester.pumpWidget(
        wrap(
          introductions: const [intro],
          onRefresh: () => refreshCount++,
          onDeleteIntroduction: deletedRows.add,
          onDeletePair: deletedPairs.add,
        ),
      );

      // Row title uses warm readable text (never near-white).
      final title = tester.widget<Text>(find.text('@Ann <-> @Bob'));
      expect(title.style!.color, light.textPrimary);
      expectTextContrast(title.style!.color!, light.surfaceSubtle);

      // Distinct destructive (row) vs warning (pair) action colors, both AA.
      final rowColor = actionColor(tester, 'settings-intro-delete-row-intro-1');
      final pairColor = actionColor(
        tester,
        'settings-intro-delete-pair-intro-1',
      );
      expect(rowColor, const Color(0xFFB4232F));
      expect(pairColor, const Color(0xFF9A3412));
      expect(rowColor, isNot(pairColor));
      expectTextContrast(rowColor, light.surfaceSubtle);
      expectTextContrast(pairColor, light.surfaceSubtle);

      // Callbacks are wired exactly (refresh/delete counts preserved).
      await tester.tap(
        find.byKey(const ValueKey('settings-intro-debug-refresh')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-intro-delete-row-intro-1')),
      );
      await tester.tap(
        find.byKey(const ValueKey('settings-intro-delete-pair-intro-1')),
      );
      expect(refreshCount, 1);
      expect(deletedRows, ['intro-1']);
      expect(deletedPairs, [intro]);
    },
  );

  testWidgets('Signal loading + error states use warm readable roles', (
    tester,
  ) async {
    // Loading spinner uses the warm accent, not the old teal-on-nothing.
    await tester.pumpWidget(wrap(introductions: const [], isLoading: true));
    final spinner = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(spinner.color, light.accent);

    // Error text uses the light destructive color and is readable.
    await tester.pumpWidget(wrap(introductions: const [], errorText: 'boom'));
    final error = tester.widget<Text>(find.text('boom'));
    expect(error.style!.color, const Color(0xFFB4232F));
    expectTextContrast(error.style!.color!, light.surfaceRaised);
  });
}
