import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_theme.dart';

void main() {
  // SVG assets may not load in test environment — suppress render errors.
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

  group('FeedNavigationBar', () {
    testWidgets('renders 3 NavBarButtons with correct labels', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      expect(find.byType(NavBarButton), findsNWidgets(4));
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Remember'), findsOneWidget);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('Orbit'), findsOneWidget);
    });

    testWidgets('feedBadgeCount is only passed to Feed button', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
        feedBadgeCount: 5,
      )));
      await tester.pump();

      final buttons =
          tester.widgetList<NavBarButton>(find.byType(NavBarButton)).toList();
      expect(buttons[0].badgeCount, 5); // Feed
      expect(buttons[1].badgeCount, 0); // Remember
      expect(buttons[2].badgeCount, 0); // Groups
      expect(buttons[3].badgeCount, 0); // Orbit
    });

    testWidgets('maxWidth matches NavBarTheme.barMaxWidth', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      final boxes = tester
          .widgetList<ConstrainedBox>(find.byType(ConstrainedBox))
          .where((b) => b.constraints.maxWidth == NavBarTheme.barMaxWidth)
          .toList();
      expect(boxes, isNotEmpty);
    });

    testWidgets('bar padding matches NavBarTheme.barPadding', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      // The Container inside ClipRRect holds the bar decoration + padding.
      final container = tester.widgetList<Container>(find.byType(Container))
          .where((c) => c.padding == NavBarTheme.barPadding)
          .toList();
      expect(container, isNotEmpty);
    });

    testWidgets('gradient colors match dark opaque targets', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      final container = tester.widgetList<Container>(find.byType(Container))
          .where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.gradient is LinearGradient) {
          return (dec.gradient as LinearGradient).colors.first ==
              NavBarTheme.barGradientColors.first;
        }
        return false;
      }).toList();
      expect(container, isNotEmpty);
    });

    testWidgets('border color is subtle (0.07 white)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      final container = tester.widgetList<Container>(find.byType(Container))
          .where((c) {
        final dec = c.decoration;
        if (dec is BoxDecoration && dec.border is Border) {
          final border = dec.border as Border;
          return border.top.color == NavBarTheme.barBorderColor;
        }
        return false;
      }).toList();
      expect(container, isNotEmpty);
    });

    testWidgets('BackdropFilter exists', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('button spacing is NavBarTheme.buttonSpacing', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (_) {},
      )));
      await tester.pump();

      final spacers = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.width == NavBarTheme.buttonSpacing)
          .toList();
      // 3 spacers between 4 buttons
      expect(spacers.length, 3);
    });

    testWidgets('tap callbacks fire correctly', (tester) async {
      suppressAssetErrors(tester);
      String? tapped;
      await tester.pumpWidget(wrap(FeedNavigationBar(
        activeTab: 'feed',
        onSwitchView: (tab) => tapped = tab,
      )));
      await tester.pump();

      await tester.tap(find.text('Orbit'));
      expect(tapped, 'orbit');

      await tester.tap(find.text('Remember'));
      expect(tapped, 'remember');
    });
  });
}
