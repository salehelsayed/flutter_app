import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/identity/presentation/navigation/startup_route_transition.dart';

void main() {
  group('buildStartupReplacementRoute', () {
    test('builds an opaque startup replacement route', () {
      final route = buildStartupReplacementRoute<void>(
        builder: (_) => const Placeholder(),
      );

      expect(route.opaque, isTrue);
    });

    testWidgets('uses fade only without slide translation', (tester) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Builder(
            builder: (context) {
              final route = buildStartupReplacementRoute<void>(
                builder: (_) => const Placeholder(),
              );

              return route.buildTransitions(
                context,
                const AlwaysStoppedAnimation<double>(0.5),
                const AlwaysStoppedAnimation<double>(0.0),
                const Placeholder(),
              );
            },
          ),
        ),
      );

      expect(find.byType(FadeTransition), findsOneWidget);
      expect(find.byType(SlideTransition), findsNothing);
    });

    test('uses a short forward transition suitable for startup handoff', () {
      final route = buildStartupReplacementRoute<void>(
        builder: (_) => const Placeholder(),
      );

      expect(route.transitionDuration, const Duration(milliseconds: 160));
      expect(
        route.reverseTransitionDuration,
        const Duration(milliseconds: 120),
      );
    });
  });
}
