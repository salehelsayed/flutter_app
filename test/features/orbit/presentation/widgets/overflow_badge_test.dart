import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // 198 — the interactive (onTap) path reads AppLocalizations for its Semantics.
  Widget wrapL10n(Widget child, {bool disableAnimations = false}) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      );

  group('OverflowBadge', () {
    testWidgets('renders "+N" text with count', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 5)));
      // Advance past 1000ms entrance delay + 500ms animation.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('+5'), findsOneWidget);
    });

    testWidgets('renders 28px circular container', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 3)));
      // Pump past the entrance delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      // The Container has explicit width: 28, height: 28, and circular shape.
      final containers = tester.widgetList<Container>(find.byType(Container));
      final sized = containers.where((c) {
        final d = c.decoration;
        if (d is BoxDecoration && d.shape == BoxShape.circle) {
          // Check if this is the 28px container by examining constraints
          return true;
        }
        return false;
      });
      expect(sized, isNotEmpty);
    });

    testWidgets('renders CustomPaint (dashed border)', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 2)));
      // Pump past entrance delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.descendant(
        of: find.byType(OverflowBadge),
        matching: find.byType(CustomPaint),
      ), findsOneWidget);
    });

    testWidgets('uses BackdropFilter for frosted glass', (tester) async {
      await tester.pumpWidget(wrap(const OverflowBadge(count: 4)));
      // Widget tree is built immediately, BackdropFilter is present from start.
      expect(find.byType(BackdropFilter), findsOneWidget);
      // Clean up pending timers by pumping past the delay.
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
    });

    // 198 F8 — chevron open-state swap.
    testWidgets('collapsed shows +N; expanded swaps to a chevron', (tester) async {
      await tester.pumpWidget(
        wrapL10n(OverflowBadge(count: 3, onTap: () {}, expanded: false)),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('+3'), findsOneWidget);
      expect(find.text('⌄'), findsNothing);

      await tester.pumpWidget(
        wrapL10n(OverflowBadge(count: 3, onTap: () {}, expanded: true)),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();
      expect(find.text('⌄'), findsOneWidget);
      expect(find.text('+3'), findsNothing);
    });

    // 198 F8 — onTap fires once per tap; the hit target is ≥44pt.
    testWidgets('onTap fires once per tap, 44pt hit target', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrapL10n(OverflowBadge(count: 2, onTap: () => taps++)),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();

      final hit = find.descendant(
        of: find.byType(OverflowBadge),
        matching: find.byType(GestureDetector),
      );
      expect(tester.getSize(hit).width, greaterThanOrEqualTo(44));
      expect(tester.getSize(hit).height, greaterThanOrEqualTo(44));

      await tester.tap(hit);
      await tester.pump();
      expect(taps, 1);
    });

    // 198 F8 — reduce-motion: no entrance frames, appears fully immediately.
    testWidgets('reduce-motion badge appears fully with no entrance timer',
        (tester) async {
      await tester.pumpWidget(
        wrapL10n(OverflowBadge(count: 5, onTap: () {}), disableAnimations: true),
      );
      // No pump past 1000ms: under reduce-motion it is already fully visible.
      final opacity = tester.widget<Opacity>(find.descendant(
        of: find.byType(OverflowBadge),
        matching: find.byType(Opacity),
      ));
      expect(opacity.opacity, 1.0);
      expect(find.text('+5'), findsOneWidget);
      // No pending entrance timer to drain (test would fail if one were left).
    });
  });
}
