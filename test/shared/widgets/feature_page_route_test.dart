import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/presentation/navigation/feed_route_transition.dart';
import 'package:flutter_app/features/orbit/presentation/navigation/orbit_route_transition.dart';
import 'package:flutter_app/features/settings/presentation/navigation/settings_route_transition.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _BuildRoute = Route<void> Function({
  required WidgetBuilder builder,
  RouteSettings? settings,
});

const _open = ValueKey('open-feature');
const _screen = ValueKey('feature-screen');
const _deadline = Duration(seconds: 3);

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 50),
    EnginePhase.sendSemanticsUpdate,
    _deadline,
  );
}

Future<PageRoute<void>> _openFeature(
  WidgetTester tester,
  _BuildRoute buildRoute, {
  required TargetPlatform platform,
  required TextDirection direction,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  late final Route<void> route;
  await tester
      .pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => Directionality(
            textDirection: direction,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  key: _open,
                  onPressed: () {
                    route = buildRoute(
                      settings: const RouteSettings(name: 'feature'),
                      builder: (_) => const Scaffold(key: _screen),
                    );
                    Navigator.of(context).push(route);
                  },
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      )
      .timeout(_deadline);
  await tester.tap(find.byKey(_open)).timeout(_deadline);
  await tester.pump().timeout(_deadline);
  return route as PageRoute<void>;
}

Future<void> _edgeSwipeBack(
  WidgetTester tester,
  TextDirection direction,
) async {
  final rtl = direction == TextDirection.rtl;
  await tester
      .dragFrom(Offset(rtl ? 397 : 3, 400), Offset(rtl ? -340 : 340, 0))
      .timeout(_deadline);
  await _settle(tester);
  expect(find.byKey(_open), findsOneWidget);
  expect(find.byKey(_screen), findsNothing);
}

void main() {
  final routes = <String, _BuildRoute>{
    'Feed': buildFeedSlideUpRoute<void>,
    'Orbit': buildOrbitSlideUpRoute<void>,
    'Settings': buildSettingsSlideUpRoute<void>,
  };

  for (final entry in routes.entries) {
    testWidgets('${entry.key} supports the iOS back swipe on the RTL edge', (
      tester,
    ) async {
      await _openFeature(
        tester,
        entry.value,
        platform: TargetPlatform.iOS,
        direction: TextDirection.rtl,
      );
      await _settle(tester);
      await _edgeSwipeBack(tester, TextDirection.rtl);
    });

    for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
      testWidgets(
        '${entry.key} uses a 200 ms Reduce Motion fade on $platform',
        (tester) async {
          final route = await _openFeature(
            tester,
            entry.value,
            platform: platform,
            direction: TextDirection.ltr,
            reduceMotion: true,
          );
          expect(route.settings.name, 'feature');
          expect(route.transitionDuration, const Duration(milliseconds: 200));
          expect(
            route.reverseTransitionDuration,
            const Duration(milliseconds: 200),
          );
          await tester
              .pump(const Duration(milliseconds: 100))
              .timeout(_deadline);
          final screen = find.byKey(_screen);
          expect(tester.getTopLeft(screen), Offset.zero);
          final fades = tester.widgetList<FadeTransition>(
            find.ancestor(of: screen, matching: find.byType(FadeTransition)),
          );
          expect(
            fades.any(
              (fade) => fade.opacity.value > 0 && fade.opacity.value < 1,
            ),
            isTrue,
          );
          await _settle(tester);
          if (platform == TargetPlatform.iOS) {
            await _edgeSwipeBack(tester, TextDirection.ltr);
          }
        },
      );
    }
  }
}
