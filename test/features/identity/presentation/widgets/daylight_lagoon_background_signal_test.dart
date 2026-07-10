import 'package:flutter/material.dart';
import 'package:flutter_app/features/identity/presentation/widgets/daylight_lagoon_background.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget wrap({bool disableAnimations = false}) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: const DaylightLagoonBackground(child: Text('Signal')),
      ),
    );
  }

  testWidgets(
    'warm mineral ground has static violet and sage blooms without a ticker',
    (tester) async {
      await tester.pumpWidget(wrap());

      final background = tester.widget<DaylightLagoonBackground>(
        find.byType(DaylightLagoonBackground),
      );
      // Warm mineral ground, not paper white.
      expect(background.baseColor, const Color(0xFFECE8E1));
      expect(background.groundGradientColors, const [
        Color(0xFFF4F0EA),
        Color(0xFFECE8E1),
        Color(0xFFE5DED5),
      ]);
      // Visible static blooms (not transparent washes).
      expect(background.violetWash, const Color(0x177C69C8));
      expect(background.sageWash, const Color(0x1258A989));

      final root = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('daylight-lagoon-background-root')),
      );
      final decoration = root.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFECE8E1));
      final gradient = decoration.gradient as RadialGradient;
      expect(gradient.colors, const [
        Color(0xFFF4F0EA),
        Color(0xFFECE8E1),
        Color(0xFFE5DED5),
      ]);
      expect(gradient.stops, const [0.0, 0.62, 1.0]);

      // No running background ticker, and the painter never marks willChange.
      expect(tester.hasRunningAnimations, isFalse);
      final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('daylight-lagoon-background-painter')),
      );
      expect(paint.willChange, isFalse);
    },
  );

  testWidgets('reduced-motion renders the same still Signal composition', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(disableAnimations: true));
    await tester.pump();

    expect(tester.hasRunningAnimations, isFalse);
    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-painter')),
      findsOneWidget,
    );
    final root = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
    );
    expect((root.decoration as BoxDecoration).color, const Color(0xFFECE8E1));
  });
}
