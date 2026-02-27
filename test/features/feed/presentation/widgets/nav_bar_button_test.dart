import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_theme.dart';

void main() {
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) return;
      oldHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(
          body: Center(child: child),
        ),
      );

  NavBarButton makeButton({
    bool isActive = false,
    int badgeCount = 0,
    VoidCallback? onTap,
  }) =>
      NavBarButton(
        label: 'Feed',
        svgAsset: 'assets/icons/nav_feed.svg',
        isActive: isActive,
        onTap: onTap ?? () {},
        badgeCount: badgeCount,
      );

  group('NavBarButton – dimensions', () {
    testWidgets('button width is NavBarTheme.buttonWidth (70)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: true)));
      await tester.pump(const Duration(milliseconds: 250));

      final animBox = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      // Width is set directly on AnimatedContainer via constraints
      expect(animBox.constraints?.maxWidth, NavBarTheme.buttonWidth);
      expect(animBox.constraints?.minWidth, NavBarTheme.buttonWidth);
    });

    testWidgets('text fontSize is NavBarTheme.textSize (11)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton()));
      await tester.pump();

      final text = tester.widget<Text>(find.text('Feed'));
      expect(text.style?.fontSize, NavBarTheme.textSize);
    });

    testWidgets('icon-text gap is NavBarTheme.iconTextGap (2)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton()));
      await tester.pump();

      // The Column has a SizedBox spacer between icon and text
      final column = tester.widget<Column>(find.byType(Column).first);
      final spacer = column.children
          .whereType<SizedBox>()
          .where((s) => s.height == NavBarTheme.iconTextGap);
      expect(spacer, isNotEmpty);
    });
  });

  group('NavBarButton – active state', () {
    testWidgets('active: dark gradient pill (12%→5% white)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: true)));
      await tester.pump(const Duration(milliseconds: 250));

      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final dec = container.decoration as BoxDecoration;
      final gradient = dec.gradient as LinearGradient;
      expect(gradient.colors, NavBarTheme.activePillGradient);
    });

    testWidgets('active: NO border', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: true)));
      await tester.pump(const Duration(milliseconds: 250));

      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final dec = container.decoration as BoxDecoration;
      expect(dec.border, isNull);
    });

    testWidgets('active: NO boxShadow', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: true)));
      await tester.pump(const Duration(milliseconds: 250));

      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final dec = container.decoration as BoxDecoration;
      expect(dec.boxShadow, isNull);
    });

    testWidgets('active: white text, w600', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: true)));
      await tester.pump();

      final text = tester.widget<Text>(find.text('Feed'));
      expect(text.style?.color, NavBarTheme.activeTextColor);
      expect(text.style?.fontWeight, NavBarTheme.activeWeight);
    });
  });

  group('NavBarButton – inactive state', () {
    testWidgets('inactive: no gradient', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: false)));
      await tester.pump();

      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      final dec = container.decoration as BoxDecoration;
      expect(dec.gradient, isNull);
    });

    testWidgets('inactive: 55% text opacity, w500', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(isActive: false)));
      await tester.pump();

      final text = tester.widget<Text>(find.text('Feed'));
      expect(text.style?.color, NavBarTheme.inactiveTextColor);
      expect(text.style?.fontWeight, NavBarTheme.inactiveWeight);
    });
  });

  group('NavBarButton – interaction', () {
    testWidgets('tap callback fires', (tester) async {
      suppressAssetErrors(tester);
      var tapped = false;
      await tester.pumpWidget(wrap(makeButton(onTap: () => tapped = true)));
      await tester.pump();

      await tester.tap(find.text('Feed'));
      expect(tapped, isTrue);
    });

    testWidgets('animation duration is 220ms easeOut', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton()));
      await tester.pump();

      final container = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      expect(container.duration, NavBarTheme.animationDuration);
      expect(container.curve, NavBarTheme.animationCurve);
    });
  });

  group('NavBarButton – badge', () {
    testWidgets('badge hidden when count=0', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(badgeCount: 0)));
      await tester.pump();

      expect(find.byType(Positioned), findsNothing);
    });

    testWidgets('badge shows count text', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(badgeCount: 7)));
      await tester.pump();

      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('badge shows "99+" for overflow', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(badgeCount: 150)));
      await tester.pump();

      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('badge uses RED gradient', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(badgeCount: 3)));
      await tester.pump();

      // The badge is a Positioned > Container
      final positioned = tester.widget<Positioned>(find.byType(Positioned));
      expect(positioned, isNotNull);

      // Find the decorated container inside the badge
      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.gradient is LinearGradient) {
          return (dec.gradient as LinearGradient).colors.first ==
              NavBarTheme.badgeGradientColors.first;
        }
        return false;
      }).toList();
      expect(containers, isNotEmpty);
    });

    testWidgets('badge shadow is red-tinted', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(makeButton(badgeCount: 3)));
      await tester.pump();

      final containers = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.boxShadow != null) {
          return dec.boxShadow!.any(
              (s) => s.color == NavBarTheme.badgeShadowColor);
        }
        return false;
      }).toList();
      expect(containers, isNotEmpty);
    });
  });
}
