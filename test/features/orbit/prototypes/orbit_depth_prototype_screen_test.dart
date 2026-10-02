import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../prototypes/orbit_depth/orbit_depth_prototype_screen.dart';

void main() {
  const flatHint = 'Swipe up to see thoughts';
  const depthHint = 'Swipe sideways to turn · up to go further';
  const middleHint = 'Up to go further · down to come back';
  const lastHint = 'Swipe down to come back';

  Future<void> pumpPrototype(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          size: const Size(390, 844),
          disableAnimations: disableAnimations,
        ),
        child: const MaterialApp(home: OrbitDepthPrototypeScreen()),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> swipe(WidgetTester tester, Offset by) async {
    await tester.flingFrom(const Offset(195, 600), by, 1500);
    await settle(tester);
  }

  Offset layla(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey('avatar-layla')));

  testWidgets('swipe up tilts into depth and thoughts appear', (tester) async {
    await pumpPrototype(tester);
    expect(find.text(flatHint), findsOneWidget);

    await swipe(tester, const Offset(0, -200));
    expect(find.text(depthHint), findsOneWidget);
    expect(find.text('airport at 6. taxi anyone?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sideways swipe turns the orbit only in depth', (tester) async {
    await pumpPrototype(tester);
    final flatStart = layla(tester);
    await swipe(tester, const Offset(-160, 0));
    expect(layla(tester), flatStart);

    await swipe(tester, const Offset(0, -200));
    final depthStart = layla(tester);
    await swipe(tester, const Offset(-160, 0));
    expect((layla(tester) - depthStart).distance, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  testWidgets('thought bubbles stay on screen while the orbit turns', (
    tester,
  ) async {
    const thoughts = [
      'roof sunrise again. who’s up?',
      'exam at 9. wish me luck',
      'who has a drill I can borrow?',
      'airport at 6. taxi anyone?',
      'new plant. his name is kevin',
    ];
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // Turn more than a full circle one seat at a time (no fling), checking
    // mid-turn and after each friend clicks into the front seat.
    for (var step = 0; step < 10; step++) {
      final gesture = await tester.startGesture(const Offset(195, 600));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await tester.pump(const Duration(milliseconds: 16));
        if (i == 6) {
          for (final thought in thoughts) {
            expect(find.text(thought), findsWidgets, reason: 'mid $step');
          }
        }
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await settle(tester);
      for (final thought in thoughts) {
        expect(find.text(thought), findsWidgets, reason: 'step $step');
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the friend at the front opens up their thought', (tester) async {
    const nourMore = 'I land at 5:40 and can share the fare into the city.';
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    expect(find.text(nourMore), findsOneWidget);
    expect(find.text('3 comments'), findsOneWidget);

    // A slow drag of one seat lands the next friend at the front; nour's
    // card folds back into a bubble.
    final gesture = await tester.startGesture(const Offset(195, 600));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);
    expect(find.text(nourMore), findsNothing);
    expect(find.text('airport at 6. taxi anyone?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a voice thought plays from its card', (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // omar sits three seats round from nour (nour, tarek, yousef, omar).
    for (var step = 0; step < 3; step++) {
      final gesture = await tester.startGesture(const Offset(195, 600));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await settle(tester);
    }
    expect(find.text('omar · 35 min'), findsOneWidget);
    await tester.tap(find.byTooltip('Play voice note'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Pause voice note'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe up flies through layers, swipe down comes back', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await swipe(tester, const Offset(0, -200));
    expect(find.text(middleHint), findsOneWidget);
    expect(find.text('This week · 7'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await swipe(tester, const Offset(0, -200));
    }
    expect(find.text(lastHint), findsOneWidget);
    expect(find.text('A while ago · 7'), findsOneWidget);
    await swipe(tester, const Offset(0, -200));
    expect(find.text(lastHint), findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await swipe(tester, const Offset(0, 200));
    }
    expect(find.text(depthHint), findsOneWidget);
    await swipe(tester, const Offset(0, 200));
    expect(find.text(flatHint), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow partial drag springs back to flat', (tester) async {
    await pumpPrototype(tester);
    final gesture = await tester.startGesture(const Offset(195, 600));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await settle(tester);
    expect(find.text(flatHint), findsOneWidget);
  });

  testWidgets('reduced motion toggles instantly and opens a thought', (
    tester,
  ) async {
    await pumpPrototype(tester, disableAnimations: true);
    await tester.tap(find.byTooltip('Toggle depth'));
    await tester.pumpAndSettle();
    expect(find.text(depthHint), findsOneWidget);

    await tester.tap(find.text('airport at 6. taxi anyone?'));
    await tester.pumpAndSettle();
    expect(find.text('nour · 20 min ago'), findsOneWidget);
  });
}
