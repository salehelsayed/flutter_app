import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/home/presentation/widgets/empty_circle_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(size: Size(400, 800)),
        child: child,
      ),
    ),
  );

  group('EmptyCircleState', () {
    testWidgets('renders "Your circle is waiting to be filled" text', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(find.text('Your circle is waiting to be filled'), findsOneWidget);
    });

    testWidgets('renders subtitle text', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(find.textContaining('Scan a friend'), findsOneWidget);
    });

    testWidgets('renders CustomPaint for dashed circles', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders constellation dots painter', (tester) async {
      await tester.pumpWidget(wrap(const EmptyCircleState()));
      await tester.pump();
      // The center icon container has a CustomPaint with constellation dots
      final customPaints = tester.widgetList<CustomPaint>(
        find.byType(CustomPaint),
      );
      expect(customPaints.length, greaterThanOrEqualTo(2));
    });

    // TC-25 (156, preservation sentinel — GREEN on HEAD and after fix): the
    // first-open orbit rides its own ..repeat() controller and must keep
    // animating even under reduce-motion. 156 QW-3 confines its reduce-motion
    // gate to ambient_background.dart and must NOT freeze this orbit.
    testWidgets(
      'TC-25: first-open orbit keeps animating even under disableAnimations',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(
                  size: Size(400, 800),
                  disableAnimations: true,
                ),
                child: const TickerMode(
                  enabled: true,
                  child: EmptyCircleState(),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));

        final controllers = tester
            .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
            .map((ab) => ab.listenable)
            .whereType<AnimationController>()
            .toList();
        expect(controllers, isNotEmpty);
        expect(
          controllers.any((c) => c.isAnimating),
          isTrue,
          reason: 'the first-open orbit must keep animating under reduce-motion',
        );
      },
    );
  });
}
