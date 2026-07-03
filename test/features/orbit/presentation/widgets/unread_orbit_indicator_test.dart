import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';

// 194 — messenger-orbit unread indicator (alternative B). Bare MaterialApp wrap,
// no l10n (this widget carries no localized strings). Lit-node tests use bounded
// pumps: the ~9s repeat rotation never settles (INV-1 guards absence-when-zero).
void main() {
  Widget wrap(
    Widget child, {
    bool disableAnimations = false,
    bool accessibleNavigation = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: disableAnimations,
              accessibleNavigation: accessibleNavigation,
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  int countSatellites(WidgetTester tester) => tester
      .widgetList(
        find.byWidgetPredicate((w) {
          final key = w.key;
          return key is ValueKey<String> &&
              key.value.startsWith('unread-satellite-');
        }),
      )
      .length;

  // Scope to the indicator's own AnimatedBuilder — a bare MaterialApp hosts its
  // own internal AnimationControllers (overlay/navigator) that would otherwise
  // shadow ours.
  List<AnimationController> controllers(WidgetTester tester) => tester
      .widgetList<AnimatedBuilder>(
        find.descendant(
          of: find.byType(UnreadOrbitIndicator),
          matching: find.byType(AnimatedBuilder),
        ),
      )
      .map((ab) => ab.listenable)
      .whereType<AnimationController>()
      .toList();

  Finder ringPaintFinder() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is UnreadOrbitRingPainter,
  );

  group('UnreadOrbitIndicator', () {
    testWidgets(
      'satellite count follows min(unread,3): 1->1, 2->2, 3->3, 4->3, 120->3',
      (tester) async {
        for (final probe in const [
          (1, 1),
          (2, 2),
          (3, 3),
          (4, 3),
          (120, 3),
        ]) {
          await tester.pumpWidget(
            wrap(
              UnreadOrbitIndicator(
                unreadCount: probe.$1,
                diameter: 38,
                motionEnabled: true,
              ),
            ),
          );
          await tester.pump();
          expect(
            countSatellites(tester),
            probe.$2,
            reason: 'unread=${probe.$1} should render ${probe.$2} satellites',
          );
          // No numerals anywhere on the node (product decision B).
          expect(find.byType(Text), findsNothing);
        }
      },
    );

    testWidgets('count 0 builds nothing (absent, not invisible)', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadOrbitIndicator(unreadCount: 0)));
      expect(
        find.descendant(
          of: find.byType(UnreadOrbitIndicator),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(countSatellites(tester), 0);
      // No live ticker on an empty indicator -> settle completes.
      await tester.pumpAndSettle();
    });

    testWidgets('ring and satellites use the green unread accent', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const UnreadOrbitIndicator(unreadCount: 2)));
      await tester.pump();

      final painter =
          tester.widget<CustomPaint>(ringPaintFinder()).painter
              as UnreadOrbitRingPainter;
      expect(painter.accent, UnreadOrbitIndicator.kUnreadAccent);

      final satellite = tester.widget<Container>(
        find.byKey(const ValueKey('unread-satellite-0')),
      );
      final decoration = satellite.decoration as BoxDecoration;
      expect(decoration.color, UnreadOrbitIndicator.kUnreadAccent);
    });

    testWidgets('rotation animates when motion enabled', (tester) async {
      await tester.pumpWidget(
        wrap(
          const UnreadOrbitIndicator(
            unreadCount: 2,
            diameter: 38,
            motionEnabled: true,
          ),
        ),
      );
      await tester.pump();

      final cs = controllers(tester);
      expect(cs, isNotEmpty);
      final c = cs.first;
      expect(c.isAnimating, isTrue);
      final v0 = c.value;
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.value, greaterThan(v0));
    });

    testWidgets('disableAnimations freezes rotation but indicator stays visible', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          const UnreadOrbitIndicator(unreadCount: 2, diameter: 38),
          disableAnimations: true,
        ),
      );
      await tester.pump();

      final c = controllers(tester).first;
      expect(c.isAnimating, isFalse);
      expect(c.value, 0.0);
      // Still statically visible: unread info is not motion-only.
      expect(ringPaintFinder(), findsOneWidget);
      expect(countSatellites(tester), 2);
    });

    testWidgets(
      'accessibleNavigation freezes rotation but indicator stays visible',
      (tester) async {
        await tester.pumpWidget(
          wrap(
            const UnreadOrbitIndicator(unreadCount: 2, diameter: 38),
            accessibleNavigation: true,
          ),
        );
        await tester.pump();

        final c = controllers(tester).first;
        expect(c.isAnimating, isFalse);
        expect(c.value, 0.0);
        expect(ringPaintFinder(), findsOneWidget);
        expect(countSatellites(tester), 2);
      },
    );

    testWidgets('TickerMode(enabled:false) halts rotation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TickerMode(
              enabled: false,
              child: Center(
                child: UnreadOrbitIndicator(unreadCount: 2, diameter: 38),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final c = controllers(tester).first;
      final v0 = c.value;
      await tester.pump(const Duration(milliseconds: 300));
      // Vsync'd ticker is muted off-screen -> value does not advance.
      expect(c.value, v0);
    });

    testWidgets('dispose mid-animation is clean', (tester) async {
      await tester.pumpWidget(
        wrap(const UnreadOrbitIndicator(unreadCount: 3, diameter: 38)),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
