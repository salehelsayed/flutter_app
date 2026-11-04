import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

final _now = DateTime.utc(2026, 11, 4, 12);

void main() {
  Future<void> pump(
    WidgetTester tester,
    BackgroundPreference preference,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: YouPageScreen(
          load: (limit, tag) async => const YouPageData(
            username: 'Saleh',
            avatarBytes: null,
            friendCount: 41,
            thought: null,
            past: [],
          ),
          now: () => _now,
          onBack: () {},
          onOpenChat: (_) async {},
          onCompose: (_) async {},
          backgroundPreference: preference,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Color colorOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.text(text)).style!.color!;

  for (final preference in BackgroundPreference.values) {
    testWidgets(
      'the You page sits on the Orbit background: ${preference.name}',
      (tester) async {
        await pump(tester, preference);
        final background = tester.widget<AmbientBackground>(
          find.byType(AmbientBackground),
        );
        expect(background.preference, preference);
        expect(
          tester
              .widget<Scaffold>(find.byKey(const ValueKey('you')))
              .backgroundColor,
          Colors.transparent,
        );
      },
    );
  }

  testWidgets('on the light Lagoon background its words turn dark to stay '
      'readable', (tester) async {
    await pump(tester, BackgroundPreference.daylightLagoon);
    expect(colorOf(tester, '41 friends').computeLuminance(), lessThan(.3));
    expect(
      colorOf(tester, 'Nothing shared right now').computeLuminance(),
      lessThan(.3),
    );
  });

  testWidgets('on the dark default the words keep their light colours', (
    tester,
  ) async {
    await pump(tester, BackgroundPreference.defaultBackground);
    expect(colorOf(tester, '41 friends'), const Color(0xFF9AA59F));
  });
}
