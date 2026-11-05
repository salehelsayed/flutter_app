import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_app/features/posts/presentation/screens/you_page_screen.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

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

  final composer = find.byKey(const ValueKey('you-composer'));
  final hint = find.descendant(of: composer, matching: find.byType(Text));
  final photo = find.byIcon(Icons.image_outlined);

  /// The colour of the nearest box painted behind [child].
  Color boxBehind(WidgetTester tester, Finder child) {
    final box = tester.widget<Container>(
      find.ancestor(of: child, matching: find.byType(Container)).first,
    );
    return (box.decoration! as BoxDecoration).color!;
  }

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

  testWidgets('on Lagoon the compose entry reads too: its hint and photo '
      'icon against what they sit on', (tester) async {
    await pump(tester, BackgroundPreference.daylightLagoon);
    final lagoon = tester.widget<DaylightLagoonBackground>(
      find.byType(DaylightLagoonBackground),
    );
    final bar = boxBehind(tester, composer);
    final hintColor = tester.widget<Text>(hint).style!.color!;
    final photoColor = tester.widget<Icon>(photo).color!;
    // Lightest to darkest ground, bare and under both colour washes.
    final grounds = [
      for (final ground in lagoon.groundGradientColors) ...[
        ground,
        Color.alphaBlend(
          lagoon.sageWash,
          Color.alphaBlend(lagoon.violetWash, ground),
        ),
      ],
    ];
    for (final ground in grounds) {
      final onBar = Color.alphaBlend(bar, ground);
      expectTextContrast(
        hintColor,
        Color.alphaBlend(boxBehind(tester, hint), onBar),
        reason: 'hint on ${ground.toARGB32().toRadixString(16)}',
      );
      expectComponentContrast(
        photoColor,
        Color.alphaBlend(boxBehind(tester, photo), onBar),
        reason: 'photo icon on ${ground.toARGB32().toRadixString(16)}',
      );
    }
  });

  testWidgets('on the dark default the words keep their light colours', (
    tester,
  ) async {
    await pump(tester, BackgroundPreference.defaultBackground);
    expect(colorOf(tester, '41 friends'), const Color(0xFF9AA59F));
    // The compose entry keeps its dark look to the byte.
    expect(boxBehind(tester, composer), const Color(0x2E05070C));
    expect(tester.widget<Text>(hint).style!.color, const Color(0xFF8A8F98));
    expect(tester.widget<Icon>(photo).color, const Color(0xFFC7CEC9));
  });
}
