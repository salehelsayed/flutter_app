import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_theme.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture')) {
        return;
      }
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap(BackgroundReadableColors colors) {
    return MaterialApp(
      theme: ThemeData(extensions: [colors]),
      home: Scaffold(
        body: Center(
          child: NavBarButton(
            label: 'Feed',
            svgAsset: 'assets/icons/nav_feed.svg',
            isActive: true,
            onTap: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('light active pill, icon, and text use Signal accent', (
    tester,
  ) async {
    suppressAssetErrors(tester);
    const colors = BackgroundReadableColors.representativeLight;

    await tester.pumpWidget(wrap(colors));
    await tester.pump();

    final text = tester.widget<Text>(find.text('Feed'));
    expect(text.style!.color, colors.navActive);

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(
      svg.colorFilter,
      ColorFilter.mode(colors.navActive, BlendMode.srcIn),
    );

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final gradient = (container.decoration as BoxDecoration).gradient;
    expect((gradient as LinearGradient).colors.first, colors.navActiveFill);
  });

  testWidgets('dark active branch stays on NavBarTheme literals', (
    tester,
  ) async {
    suppressAssetErrors(tester);

    await tester.pumpWidget(wrap(BackgroundReadableColors.dark));
    await tester.pump();

    final text = tester.widget<Text>(find.text('Feed'));
    expect(text.style!.color, NavBarTheme.activeTextColor);

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    final gradient = (container.decoration as BoxDecoration).gradient;
    expect((gradient as LinearGradient).colors, NavBarTheme.activePillGradient);
  });
}
