import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child, {BackgroundReadableColors? readableColors}) =>
      MaterialApp(
        theme: ThemeData(
          extensions: [readableColors ?? BackgroundReadableColors.dark],
        ),
        home: Scaffold(body: child),
      );

  group('OrbitCloseButton', () {
    testWidgets('renders a 44px circle container', (tester) async {
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () {})));
      final container = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final decoration = c.decoration;
            if (decoration is BoxDecoration) {
              return decoration.shape == BoxShape.circle;
            }
            return false;
          })
          .first;
      expect(container.constraints?.maxWidth, 44);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        wrap(OrbitCloseButton(onTap: () => tapped = true)),
      );
      await tester.tap(find.byType(OrbitCloseButton));
      expect(tapped, isTrue);
    });

    testWidgets('Orbit close has a localized button label', (
      tester,
    ) async {
      const deadline = Duration(seconds: 3);
      var closed = false;
      await tester
          .pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(body: OrbitCloseButton(onTap: () => closed = true)),
            ),
          )
          .timeout(deadline);
      final control = find.bySemanticsLabel('Close Orbit');
      expect(control, findsOneWidget);
      await tester.tap(control).timeout(deadline);
      expect(closed, isTrue);
    });

    testWidgets('renders CustomPaint (X painter)', (tester) async {
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () {})));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('uses the light chrome hairline and faint fill on daylight', (tester) async {
      const colors = BackgroundReadableColors.representativeLight;

      await tester.pumpWidget(
        wrap(OrbitCloseButton(onTap: () {}), readableColors: colors),
      );

      final container = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final decoration = c.decoration;
            if (decoration is BoxDecoration) {
              return decoration.shape == BoxShape.circle;
            }
            return false;
          })
          .first;
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, colors.chromeFaintFill);
      expect((decoration.border as Border).top.color, colors.chromeHairline);
    });
  });
}
