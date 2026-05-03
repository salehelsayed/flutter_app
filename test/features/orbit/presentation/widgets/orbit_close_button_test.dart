import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';

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

    testWidgets('renders CustomPaint (X painter)', (tester) async {
      await tester.pumpWidget(wrap(OrbitCloseButton(onTap: () {})));
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('uses readable glass chrome on daylight', (tester) async {
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

      expect(decoration.color, colors.glassSurface);
      expect((decoration.border as Border).top.color, colors.glassBorder);
    });
  });
}
