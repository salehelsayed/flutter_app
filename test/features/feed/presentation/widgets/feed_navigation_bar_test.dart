import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_theme.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  // SVG assets may not load in test environment — suppress render errors.
  void suppressAssetErrors(WidgetTester tester) {
    final oldHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        final msg = details.exceptionAsString();
        if (msg.contains('Unable to load asset') ||
            msg.contains('SvgPicture') ||
            msg.contains('ImageFilter')) {
          return;
        }
        oldHandler?.call(details);
      };
    addTearDown(() => FlutterError.onError = oldHandler);
  }

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: Center(child: child)),
  );

  group('FeedNavigationBar', () {
    testWidgets('renders 2 NavBarButtons with correct labels', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      expect(find.byType(NavBarButton), findsNWidgets(2));
      expect(find.text('Feed'), findsOneWidget);
      expect(find.text('Orbit'), findsOneWidget);
      expect(find.text('Remember'), findsNothing);
      expect(find.text('Posts'), findsNothing);
    });

    testWidgets('feedBadgeCount is only passed to Feed button', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(
          FeedNavigationBar(
            activeTab: 'feed',
            onSwitchView: (_) {},
            feedBadgeCount: 5,
          ),
        ),
      );
      await tester.pump();

      final buttons = tester
          .widgetList<NavBarButton>(find.byType(NavBarButton))
          .toList();
      expect(buttons[0].badgeCount, 5); // Feed
      expect(buttons[1].badgeCount, 0); // Orbit
    });

    testWidgets('bar shrink-wraps to fit buttons', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      final row = tester.widget<Row>(find.byType(Row));
      expect(row.mainAxisSize, MainAxisSize.min);
    });

    testWidgets('bar padding matches NavBarTheme.barPadding', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      // The Container inside ClipRRect holds the bar decoration + padding.
      final container = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.padding == NavBarTheme.barPadding)
          .toList();
      expect(container, isNotEmpty);
    });

    testWidgets('gradient colors match dark opaque targets', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      final container = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final dec = c.decoration;
            if (dec is BoxDecoration && dec.gradient is LinearGradient) {
              return (dec.gradient as LinearGradient).colors.first ==
                  NavBarTheme.barGradientColors.first;
            }
            return false;
          })
          .toList();
      expect(container, isNotEmpty);
    });

    testWidgets('border color is subtle (0.07 white)', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      final container = tester
          .widgetList<Container>(find.byType(Container))
          .where((c) {
            final dec = c.decoration;
            if (dec is BoxDecoration && dec.border is Border) {
              final border = dec.border as Border;
              return border.top.color == NavBarTheme.barBorderColor;
            }
            return false;
          })
          .toList();
      expect(container, isNotEmpty);
    });

    testWidgets('BackdropFilter exists', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    testWidgets('button spacing is NavBarTheme.buttonSpacing', (tester) async {
      suppressAssetErrors(tester);
      await tester.pumpWidget(
        wrap(FeedNavigationBar(activeTab: 'feed', onSwitchView: (_) {})),
      );
      await tester.pump();

      final spacers = tester
          .widgetList<SizedBox>(find.byType(SizedBox))
          .where((s) => s.width == NavBarTheme.buttonSpacing)
          .toList();
      // 1 spacer between 2 buttons
      expect(spacers.length, 1);
    });

    testWidgets('tap callbacks fire correctly', (tester) async {
      suppressAssetErrors(tester);
      String? tapped;
      await tester.pumpWidget(
        wrap(
          FeedNavigationBar(
            activeTab: 'feed',
            onSwitchView: (tab) => tapped = tab,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('Orbit'));
      expect(tapped, 'orbit');

      expect(find.text('Remember'), findsNothing);
      expect(find.text('Posts'), findsNothing);
    });
  });
}
