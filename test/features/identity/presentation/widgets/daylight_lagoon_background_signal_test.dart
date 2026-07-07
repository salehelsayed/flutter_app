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

  testWidgets('ground base is exactly Paper White with pinned vignette stops', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    final background = tester.widget<DaylightLagoonBackground>(
      find.byType(DaylightLagoonBackground),
    );
    expect(background.baseColor, const Color(0xFFFFFFFF));
    expect(background.groundGradientColors, const [
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0xFFF0F1F4),
    ]);

    final root = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
    );
    final decoration = root.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFFFFFFF));
    expect((decoration.gradient as RadialGradient).colors, const [
      Color(0xFFFFFFFF),
      Color(0xFFFFFFFF),
      Color(0xFFF0F1F4),
    ]);
  });

  testWidgets('ambient washes are disabled for the clean white ground', (
    tester,
  ) async {
    await tester.pumpWidget(wrap());

    final background = tester.widget<DaylightLagoonBackground>(
      find.byType(DaylightLagoonBackground),
    );
    expect(background.violetWash, const Color(0x00FFFFFF));
    expect(background.blueWash, const Color(0x00FFFFFF));
  });

  testWidgets('reduce-motion static path keeps the Signal frame', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(disableAnimations: true));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('daylight-lagoon-background-painter')),
      findsOneWidget,
    );
    final root = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('daylight-lagoon-background-root')),
    );
    expect((root.decoration as BoxDecoration).color, const Color(0xFFFFFFFF));
  });
}
