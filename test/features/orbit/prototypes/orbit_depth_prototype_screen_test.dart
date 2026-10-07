import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../prototypes/orbit_depth/orbit_depth_prototype_screen.dart';

void main() {
  // Which view is showing, read from the layer label at the top: it only
  // exists in depth and names the orbit you are on.
  final flatHint = find.text('Recent · 7');
  final depthHint = find.text('Recent · 7');
  final middleHint = find.text('This week · 7');
  final lastHint = find.text('A while ago · 7');

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
    await tester.flingFrom(const Offset(195, 260), by, 1500);
    await settle(tester);
  }

  Offset layla(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey('avatar-layla')));

  testWidgets('swipe up tilts into depth and thoughts appear', (tester) async {
    await pumpPrototype(tester);
    expect(flatHint, findsNothing);

    await swipe(tester, const Offset(0, -200));
    expect(depthHint, findsOneWidget);
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

  testWidgets('bubbles over the flat orbit, dots once tilted', (tester) async {
    const thoughts = {
      'layla': 'weekend up north. still can’t feel my legs',
      'omar': 'exam at 9. wish me luck',
      'tarek': 'who has a drill I can borrow?',
      'nour': 'airport at 6. taxi anyone?',
      'sara': 'we adopted her! meet luna',
    };
    await pumpPrototype(tester);
    await settle(tester);
    // Flat: every thought is a bubble over its friend; no dots.
    for (final text in thoughts.values) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    expect(find.byKey(const ValueKey('thought-dot-omar')), findsNothing);

    await swipe(tester, const Offset(0, -200));
    // Tilted: nour (at the front) has her card; the others are dots.
    expect(find.text('airport at 6. taxi anyone?'), findsOneWidget);
    for (final name in ['layla', 'omar', 'tarek', 'sara']) {
      expect(find.byKey(ValueKey('thought-dot-$name')), findsOneWidget);
      expect(find.text(thoughts[name]!), findsNothing, reason: name);
    }

    // Turn a full circle one seat at a time: the friend at the front always
    // has their card, everyone else with a thought keeps their dot.
    for (var step = 0; step < 8; step++) {
      final gesture = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await settle(tester);
      final dots = thoughts.keys
          .where(
            (n) => find.byKey(ValueKey('thought-dot-$n')).evaluate().isNotEmpty,
          )
          .length;
      final cards = thoughts.values
          .where((text) => find.text(text).evaluate().isNotEmpty)
          .length;
      expect(dots + cards, 5, reason: 'step $step');
      expect(cards, lessThanOrEqualTo(1), reason: 'step $step');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('the friend at the front opens up their thought', (tester) async {
    const nourMore = 'I land at 5:40 and can share the fare into the city.';
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    expect(find.text(nourMore), findsOneWidget);
    expect(find.textContaining('3 replies'), findsOneWidget);

    // A slow drag of one seat lands the next friend at the front; nour's
    // card folds back into a bubble.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);
    expect(find.text(nourMore), findsNothing);
    // Away from the front, nour's thought is a dot on her avatar.
    expect(find.byKey(const ValueKey('thought-dot-nour')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long text post folds behind Show more', (tester) async {
    const lastLine =
        'also, if anyone knows how to find the studs in an old plaster wall '
        'without drilling ten test holes, please tell me before I do exactly '
        'that.';
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // tarek sits one seat round from nour.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);

    expect(find.byKey(const ValueKey('text-post-tarek')), findsOneWidget);
    expect(find.text('who has a drill I can borrow?'), findsOneWidget);
    expect(find.text(lastLine), findsNothing);

    // Show more opens the whole post full screen.
    await tester.tap(find.text('Show more'));
    await settle(tester);
    expect(find.byKey(const ValueKey('post-screen')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(lastLine),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('post-screen')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text(lastLine), findsOneWidget);
    await tester.tap(find.byTooltip('Close post'));
    await settle(tester);
    expect(find.byKey(const ValueKey('post-screen')), findsNothing);
    expect(find.byKey(const ValueKey('text-post-tarek')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in the universe look a post floats without a card', (
    tester,
  ) async {
    OrbitDepthTuning.postCards = OrbitPostCards.universe;
    addTearDown(() => OrbitDepthTuning.postCards = OrbitPostCards.framed);
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    final card = find.byKey(const ValueKey('text-post-nour'));
    expect(card, findsOneWidget);
    final box = tester
        .widgetList<Container>(
          find.descendant(of: card, matching: find.byType(Container)),
        )
        .first;
    expect(box.decoration, isNull);
    expect(
      find.text('I land at 5:40 and can share the fare into the city.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('in the universe look photos float under the words', (
    tester,
  ) async {
    OrbitDepthTuning.postCards = OrbitPostCards.universe;
    addTearDown(() => OrbitDepthTuning.postCards = OrbitPostCards.framed);
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // One seat the other way brings layla and her six photos to the front.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);

    final media = find.byKey(const ValueKey('universe-media-layla'));
    expect(media, findsOneWidget);
    expect(find.byKey(const ValueKey('carousel-layla')), findsNothing);
    expect(
      find.text('weekend up north. still can’t feel my legs'),
      findsOneWidget,
    );
    expect(find.text('Reply to photo 1…'), findsOneWidget);

    // Swiping the photos re-aims the dock, as the framed carousel does.
    await tester.flingFrom(
      tester.getCenter(media),
      const Offset(-200, 0),
      800,
    );
    await settle(tester);
    expect(find.text('Reply to photo 2…'), findsOneWidget);

    // Back to the first photo: the prototype remembers each friend's slide
    // for the whole run, and later tests start layla on photo 1.
    await tester.flingFrom(
      tester.getCenter(media),
      const Offset(200, 0),
      800,
    );
    await settle(tester);
    expect(find.text('Reply to photo 1…'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a post card opens it full screen to reply', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await tester.tap(find.text('I land at 5:40 and can share the fare into the city.'));
    await settle(tester);
    expect(find.byKey(const ValueKey('post-screen')), findsOneWidget);
    // Full screen names who wrote it, since the orbit is out of sight.
    expect(find.text('20 min ago'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'I can share!');
    await tester.tap(find.byTooltip('Send reply'));
    await tester.pump();
    expect(find.text('I can share!'), findsOneWidget);
    await tester.tap(find.byTooltip('Close post'));
    await settle(tester);
    expect(find.byKey(const ValueKey('post-screen')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a voice thought plays from its card', (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // omar sits three seats round from nour (nour, tarek, yousef, omar).
    for (var step = 0; step < 3; step++) {
      final gesture = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await settle(tester);
    }
    expect(find.textContaining('35 min ago'), findsOneWidget);
    await tester.tap(find.byTooltip('Play voice note'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byTooltip('Pause voice note'), findsOneWidget);
    expect(find.text('0:12'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the card folds while a finger turns, opens on release', (
    tester,
  ) async {
    const nourMore = 'I land at 5:40 and can share the fare into the city.';
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    expect(find.text(nourMore), findsOneWidget);

    // A small turn that will snap back to nour: while the thumb is down the
    // card is folded, so nothing sits under the thumb.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 6; i++) {
      await gesture.moveBy(const Offset(-5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(nourMore), findsNothing);

    await gesture.up();
    await settle(tester);
    expect(find.text(nourMore), findsOneWidget);
  });

  testWidgets('dive into a friend, their books, and one book', (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await tester.tap(find.byKey(const ValueKey('avatar-layla')));
    await settle(tester);
    expect(find.text("layla's world"), findsOneWidget);
    // Her world opens on her Thoughts; tapping the Books tile turns it round.
    await tester.tap(find.byKey(const ValueKey('space-Books')));
    await settle(tester);
    expect(find.text('Reading list · 6 books'), findsOneWidget);

    await tester.tap(find.text('Dive in'));
    await settle(tester);
    expect(find.text('layla  ›  Books'), findsOneWidget);
    expect(
      find.text(
        'a third in. slow start but it is growing on me',
        findRichText: true,
      ),
      findsNothing,
    );
    expect(
      find.text('“a third in. slow start but it is growing on me”'),
      findsOneWidget,
    );

    await tester.tap(find.text('Open'));
    await settle(tester);
    expect(find.text('Say something about The Alchemist'), findsOneWidget);
    Navigator.of(
      tester.element(find.text('Say something about The Alchemist')),
    ).pop();
    await settle(tester);

    // Swiping down backs out a level at a time.
    await swipe(tester, const Offset(0, 200));
    expect(find.text("layla's world"), findsOneWidget);
    await swipe(tester, const Offset(0, 200));
    expect(depthHint, findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a challenge shows progress and takes a cheer', (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await tester.tap(find.byKey(const ValueKey('avatar-omar')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('space-Plank challenge')));
    await settle(tester);
    expect(find.text('Challenge · 4 of 7 done'), findsOneWidget);

    await tester.tap(find.text('Dive in'));
    await settle(tester);
    expect(find.text('omar  ›  Plank challenge'), findsOneWidget);
    expect(find.text('Day 5 · Fri'), findsOneWidget);
    expect(find.text('4/7'), findsOneWidget);

    await tester.tap(find.text('Cheer'));
    await tester.pump();
    expect(find.text('Cheered'), findsOneWidget);
    expect(find.text('1 cheer'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('your own world has a new-space tile', (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await tester.tap(find.bySemanticsLabel('You'));
    await settle(tester);
    expect(find.text('your world'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('space-Books')));
    await settle(tester);
    expect(find.text('Reading list · 2 books'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("a friend's thoughts live in their world", (tester) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));

    // The front thought card links to nour's world.
    await tester.tap(find.text("nour's world ›"));
    await settle(tester);
    expect(find.text("nour's world"), findsOneWidget);
    expect(find.text('Thoughts · 2, newest 20 min ago'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);

    // Omar's voice note is kept in his Thoughts space and plays there.
    await tester.tap(find.byKey(const ValueKey('avatar-omar')));
    await settle(tester);
    expect(find.text('Thoughts · 5, newest 35 min ago'), findsOneWidget);
    await tester.tap(find.text('Dive in'));
    await settle(tester);
    expect(find.text('omar  ›  Thoughts'), findsOneWidget);
    expect(find.text('35 min ago · on the orbit now'), findsOneWidget);
    await tester.tap(find.byTooltip('Play voice note'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byTooltip('Pause voice note'), findsOneWidget);

    // One seat round: a thought posted from his Plank challenge links to it.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);
    expect(find.text('Thursday plank: 1:10, new best'), findsOneWidget);
    await tester.tap(find.text('from Plank challenge  ›'));
    await settle(tester);
    expect(find.text('omar  ›  Plank challenge'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets("swiping up on the card goes through a friend's posts", (
    tester,
  ) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    for (var step = 0; step < 3; step++) {
      final gesture = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 12; i++) {
        await gesture.moveBy(const Offset(-5, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await settle(tester);
    }
    expect(find.text('exam at 9. wish me luck'), findsWidgets);
    expect(find.text('4 more from omar · swipe up'), findsOneWidget);

    await tester.fling(
      find.text('4 more from omar · swipe up'),
      const Offset(0, -160),
      1200,
    );
    await settle(tester);
    expect(find.text('Thursday plank: 1:10, new best'), findsWidgets);
    expect(find.text('3 more from omar · swipe up'), findsOneWidget);
    expect(find.text('from Plank challenge  ›'), findsOneWidget);

    await tester.fling(
      find.text('3 more from omar · swipe up'),
      const Offset(0, 160),
      1200,
    );
    await settle(tester);
    expect(find.text('4 more from omar · swipe up'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('swipe up flies through layers, swipe down comes back', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    await swipe(tester, const Offset(0, -200));
    expect(middleHint, findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await swipe(tester, const Offset(0, -200));
    }
    expect(lastHint, findsOneWidget);
    await swipe(tester, const Offset(0, -200));
    expect(lastHint, findsOneWidget);

    for (var i = 0; i < 5; i++) {
      await swipe(tester, const Offset(0, 200));
    }
    expect(depthHint, findsOneWidget);
    await swipe(tester, const Offset(0, 200));
    expect(flatHint, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow partial drag springs back to flat', (tester) async {
    await pumpPrototype(tester);
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, -10));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.up();
    await settle(tester);
    expect(flatHint, findsNothing);
  });

  testWidgets('reduced motion toggles instantly and aims the dock', (
    tester,
  ) async {
    await pumpPrototype(tester, disableAnimations: true);
    await tester.tap(find.byTooltip('Toggle depth'));
    await tester.pumpAndSettle();
    expect(depthHint, findsOneWidget);

    // nour's thought is text only, so the dock answers the thought itself.
    expect(find.text('Reply to nour’s thought…'), findsOneWidget);
    // The field says what it answers; no extra chip above the dock.
    expect(find.byKey(const ValueKey('dock-target')), findsNothing);
  });

  testWidgets('swiping the carousel re-aims the dock and reactions land', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await swipe(tester, const Offset(0, -200));
    // One seat the other way brings layla and her six photos to the front.
    final gesture = await tester.startGesture(const Offset(195, 300));
    for (var i = 0; i < 14; i++) {
      await gesture.moveBy(const Offset(5, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await settle(tester);
    final carousel = find.byKey(const ValueKey('carousel-layla'));
    expect(carousel, findsOneWidget);
    expect(find.text('1/6'), findsOneWidget);
    expect(find.text('Reply to photo 1…'), findsOneWidget);

    // Swipe the card, not the orbit: the next photo, and the dock follows.
    await tester.flingFrom(
      tester.getCenter(carousel),
      const Offset(-200, 0),
      800,
    );
    await settle(tester);
    expect(find.text('2/6'), findsOneWidget);
    expect(find.text('Reply to photo 2…'), findsOneWidget);
    expect(find.byKey(const ValueKey('carousel-layla')), findsOneWidget);

    await tester.tap(find.byTooltip('React'));
    await tester.pump();
    await tester.tap(find.text('\u{1F60D}'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('you: \u{1F60D}'), findsOneWidget);
    expect(find.text('\u{1F60D} sent to photo 2'), findsOneWidget);
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
