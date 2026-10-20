import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../prototypes/orbit_depth/main.dart' as proto;
import '../../../../prototypes/orbit_depth/orbit_depth_prototype_screen.dart';

void main() {
  // The look the phone build uses.
  setUpAll(proto.applyPlaygroundSettings);
  setUp(resetOrbitPrototype);

  Future<void> pumpPrototype(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    // Print every error in full, so an overflow names its widget.
    final report = FlutterError.onError;
    FlutterError.onError = (details) {
      FlutterError.dumpErrorToConsole(details, forceReport: true);
      report?.call(details);
    };
    addTearDown(() => FlutterError.onError = report);
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

  Future<void> wait(WidgetTester tester, int seconds) async {
    for (var i = 0; i < seconds * 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Ends a case: the prototype's pending answers are cancelled, and nothing
  /// overflowed or threw on the way.
  Future<void> finish(WidgetTester tester) async {
    final error = tester.takeException();
    if (error is FlutterError) debugPrint(error.toStringDeep());
    expect(error, isNull);
    await tester.pumpWidget(const SizedBox());
    resetOrbitPrototype();
  }

  /// A tap that waits only for a sheet to slide, not for everything to
  /// settle, so several steps fit inside the prototype's answer delays.
  Future<void> quickTap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder);
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Finder key(String k) => find.byKey(ValueKey(k));

  Finder field(String hint) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.hintText == hint,
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await settle(tester);
  }

  Future<void> back(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Back').last);
    await settle(tester);
  }

  /// Scrolls the people you can reach until [finder] is on screen.
  Future<void> reveal(
    WidgetTester tester,
    Finder finder, {
    bool up = false,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      up ? -250 : 250,
      scrollable: find
          .descendant(of: key('reach'), matching: find.byType(Scrollable))
          .last,
    );
    await tester.pump();
  }

  Finder chatsBadge(String count) =>
      find.descendant(of: key('chats-badge'), matching: find.text(count));

  /// Swipes up slowly, so the orbit settles on the next stop up.
  Future<void> swipeUp(WidgetTester tester) async {
    await tester.timedDragFrom(
      const Offset(195, 600),
      const Offset(0, -300),
      const Duration(milliseconds: 900),
    );
    await settle(tester);
  }

  /// Swipes down slowly, so the orbit settles on the next stop down.
  Future<void> swipeDown(WidgetTester tester) async {
    await tester.timedDragFrom(
      const Offset(195, 300),
      const Offset(0, 300),
      const Duration(milliseconds: 900),
    );
    await settle(tester);
  }

  /// From the flat orbit to Close, the way the hint under it does.
  Future<void> tilt(WidgetTester tester) => swipeUp(tester);

  Future<void> openChats(WidgetTester tester) => tap(tester, key('open-chats'));

  testWidgets(
    'opens flat; tapping a face opens your chat, the thought quoted',
    (tester) async {
      await pumpPrototype(tester);
      await settle(tester);
      // The flat orbit is Close alone; Friends waits in depth.
      expect(key('avatar-omar'), findsOneWidget);
      expect(key('avatar-maya'), findsNothing);
      expect(key('avatar-more'), findsNothing);
      expect(key('card-omar'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      // New thoughts are dots; Friends waits on a faint ring outside.
      expect(key('thought-dot-omar'), findsOneWidget);
      expect(key('peek-ring-1'), findsOneWidget);
      // No branches on the orbit.
      expect(find.textContaining('via omar'), findsNothing);
      // Sideways does not turn the flat orbit.
      final before = tester.getCenter(key('avatar-omar'));
      await tester.timedDragFrom(
        const Offset(300, 420),
        const Offset(-200, 0),
        const Duration(milliseconds: 400),
      );
      await settle(tester);
      expect(tester.getCenter(key('avatar-omar')), before);

      await tap(tester, key('avatar-omar'));
      expect(key('dm-omar'), findsOneWidget);
      expect(key('quote-chip'), findsOneWidget);
      expect(field('Reply to omar…'), findsOneWidget);
      await tester.enterText(field('Reply to omar…'), 'good luck!!');
      await tester.tap(find.byTooltip('Send'));
      await settle(tester);
      expect(key('quote-chip'), findsNothing);
      expect(key('quote-omar0'), findsOneWidget);
      expect(field('Message omar…'), findsOneWidget);
      // Answering it means you saw it.
      await back(tester);
      expect(key('thought-dot-omar'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('flat: the +N badge opens everyone outside Close on arcs', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    final badge = find.byKey(const ValueKey('orbit-overflow-badge'));
    expect(badge, findsOneWidget);
    expect(find.byKey(const ValueKey('orbit-old-rings')), findsOneWidget);
    expect(find.byKey(const ValueKey('arc-avatar-maya')), findsNothing);

    await tester.tap(badge);
    await settle(tester);
    expect(find.byKey(const ValueKey('orbit-arcs')), findsOneWidget);
    expect(find.byKey(const ValueKey('arc-avatar-maya')), findsOneWidget);
    // More friends than the arcs hold: the last seat opens everyone.
    expect(find.byKey(const ValueKey('arc-more')), findsOneWidget);

    await tester.tap(badge);
    await settle(tester);
    expect(find.byKey(const ValueKey('arc-avatar-maya')), findsNothing);
    expect(find.byKey(const ValueKey('orbit-arcs')), findsNothing);
    await finish(tester);
  });

  testWidgets('× sends without the quote', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('avatar-tarek'));
    expect(key('quote-chip'), findsOneWidget);
    await tap(tester, key('drop-quote'));
    expect(key('quote-chip'), findsNothing);
    expect(field('Message tarek…'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('swipe up tilts onto Close at the first unseen; back flattens', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await swipeUp(tester);
    expect(key('card-omar'), findsOneWidget);
    // The dial has no reply bar; the card opens the thought.
    expect(field('Reply to omar…'), findsNothing);
    expect(key('tilt-hint'), findsNothing);

    // Turning on marks the thought you read as seen.
    await tester.flingFrom(const Offset(195, 150), const Offset(-120, 0), 900);
    await wait(tester, 3);
    expect(key('card-omar'), findsNothing);
    expect(key('thought-dot-omar'), findsNothing);

    // Tapping a face in depth turns it to the front; the front face chats.
    await tap(tester, key('avatar-omar'));
    expect(key('card-omar'), findsOneWidget);
    expect(key('dm-omar'), findsNothing);
    await tap(tester, key('avatar-omar'));
    expect(key('dm-omar'), findsOneWidget);
    expect(key('quote-chip'), findsNothing);
    await back(tester);

    // System back steps down to flat before it would leave.
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(key('card-omar'), findsNothing);
    expect(key('avatar-maya'), findsNothing);
    await finish(tester);
  });

  testWidgets('on Close, Friends waits faintly outside; its name goes there', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    expect(key('peek-ring-1'), findsOneWidget);
    await tilt(tester);
    expect(key('peek-ring-1'), findsOneWidget);
    expect(key('peek-new-1'), findsOneWidget);
    await tap(tester, key('peek-ring-1'));
    expect(key('card-maya'), findsOneWidget);
    expect(key('peek-ring-1'), findsNothing);
    await finish(tester);
  });

  testWidgets('swipe down opens the dial with the orbit at the bottom', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    // Up: the orbit at the top, the card under it.
    await swipeUp(tester);
    final top = tester.getCenter(key('avatar-omar')).dy;
    expect(top, lessThan(300));
    expect(tester.getTopLeft(key('card-omar')).dy, greaterThan(top));
    // Back down to flat, then down again: the orbit at the bottom.
    await swipeDown(tester);
    expect(key('card-omar'), findsNothing);
    await swipeDown(tester);
    final bottom = tester.getCenter(key('avatar-omar')).dy;
    expect(bottom, greaterThan(500));
    expect(tester.getTopLeft(key('card-omar')).dy, lessThan(bottom));
    // Further down is further out: Friends. Up comes back to Close.
    await swipeDown(tester);
    expect(key('card-maya'), findsOneWidget);
    expect(tester.getCenter(key('avatar-maya')).dy, greaterThan(500));
    await swipeUp(tester);
    expect(key('peek-ring-1'), findsOneWidget);
    expect(tester.getCenter(key('avatar-omar')).dy, greaterThan(500));
    await finish(tester);
  });

  testWidgets('up again flies on to Friends; +N opens everyone', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    await swipeUp(tester);
    expect(key('card-maya'), findsOneWidget);
    expect(find.text('+23'), findsOneWidget);
    await tap(tester, key('avatar-more'));
    expect(key('friends-search'), findsOneWidget);
    expect(key('close-face-omar'), findsOneWidget);
    await tester.enterText(key('friends-search'), 'hu');
    await settle(tester);
    expect(key('friend-row-maya'), findsNothing);
    await tap(tester, key('friend-row-huda'));
    expect(key('dm-huda'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('in depth a face without posts leaves an empty seat', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    // Flat, all of Close, posts or not.
    expect(key('avatar-dina'), findsOneWidget);
    expect(key('empty-seats'), findsNothing);
    await tilt(tester);
    expect(key('avatar-dina'), findsNothing);
    expect(key('empty-seats'), findsOneWidget);
    for (final name in ['omar', 'tarek', 'nour', 'layla', 'sara']) {
      expect(key('avatar-$name'), findsOneWidget);
    }
    await swipeUp(tester);
    for (final name in [
      'maya',
      'dana',
      'khaled',
      'ward',
      'lina',
      'mira',
      'huda',
    ]) {
      expect(key('avatar-$name'), findsOneWidget);
    }
    expect(key('avatar-yousef'), findsNothing);
    expect(key('avatar-karim'), findsNothing);
    // Back to flat, Dina is home again.
    await swipeDown(tester);
    await swipeDown(tester);
    expect(key('avatar-dina'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('words alone read larger; a voice note sits under its words; '
      'a short thought opens as a quote', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    final omarWords = find.descendant(
      of: key('universe-media-card-omar'),
      matching: find.textContaining('exam at 9'),
    );
    final voice = find.descendant(
      of: key('universe-media-card-omar'),
      matching: find.text('voice note'),
    );
    expect(
      tester.getTopLeft(voice).dy - tester.getBottomLeft(omarWords).dy,
      lessThan(60),
    );
    final withVoice = tester.widget<Text>(omarWords).style!.fontSize!;

    await swipeUp(tester);
    await tap(tester, key('avatar-khaled'));
    final alone = find.descendant(
      of: key('text-post-khaled'),
      matching: find.text('lost my keys. again.'),
    );
    expect(tester.widget<Text>(alone).style!.fontSize!, greaterThan(withVoice));

    await tap(tester, key('text-post-khaled'));
    expect(key('quote-khaled-0'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('no counts: a card says who it was for; your thought says '
      'each reaction on its sender\'s face', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    expect(
      find.descendant(
        of: key('universe-media-card-omar'),
        matching: find.text('for their Close'),
      ),
      findsOneWidget,
    );
    await swipeDown(tester);
    await tap(tester, key('you-avatar'));
    await tester.scrollUntilVisible(
      key('reactions-1'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    for (final name in ['layla', 'omar']) {
      expect(
        find.descendant(of: key('reaction-1-$name'), matching: find.text('😂')),
        findsOneWidget,
      );
    }
    expect(find.textContaining('😂 2'), findsNothing);
    await finish(tester);
  });

  testWidgets('hold a thought to react; hold again to take it back', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    await tester.longPress(key('universe-media-card-omar'));
    await settle(tester);
    expect(key('reaction-tray'), findsOneWidget);
    await tap(tester, key('react-😍'));
    expect(key('reaction-tray'), findsNothing);
    expect(find.text('You reacted 😍'), findsOneWidget);

    await tester.longPress(key('universe-media-card-omar'));
    await settle(tester);
    await tap(tester, key('react-😍'));
    expect(find.text('You reacted 😍'), findsNothing);
    await finish(tester);
  });

  testWidgets('the front face is a reply in your chat, the thought quoted', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    // The dial has no reply bar: the friend at the front opens your chat.
    await tap(tester, key('avatar-omar'));
    expect(key('quote-chip'), findsOneWidget);
    await tester.enterText(field('Reply to omar…'), 'good luck!!');
    await tester.tap(find.byTooltip('Send'));
    await settle(tester);
    await back(tester);
    // One line under the card: your own chat with omar, nobody else's.
    expect(key('reply-line-omar'), findsOneWidget);
    expect(find.text('You: good luck!!'), findsOneWidget);

    await openChats(tester);
    await tap(tester, key('chat-row-omar'));
    expect(key('quote-omar0'), findsOneWidget);
    expect(find.text('omar’s thought'), findsOneWidget);
    expect(find.text('exam at 9. wish me luck'), findsOneWidget);
    await wait(tester, 5);
    expect(find.text('thank you!! 🙏'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a gone thought keeps its words in your chat', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await openChats(tester);
    await tap(tester, key('chat-row-nour'));
    await tester.scrollUntilVisible(
      find.text('nour’s thought · gone'),
      300,
      scrollable: find.descendant(
        of: key('dm-nour'),
        matching: find.byType(Scrollable),
      ),
    );
    expect(
      find.text('concert tickets for thursday, who’s in?'),
      findsOneWidget,
    );
    // A live thought's quote opens it.
    await tester.scrollUntilVisible(
      key('quote-nour0'),
      -300,
      scrollable: find.descendant(
        of: key('dm-nour'),
        matching: find.byType(Scrollable),
      ),
    );
    await tap(tester, key('quote-nour0'));
    expect(key('thought-nour-0'), findsOneWidget);
    expect(field('→ @nour'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('people you can reach, in their own words, by topic', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('open-reach'));
    expect(key('open-for-hisam'), findsOneWidget);
    expect(
      find.text(
        'Ten years designing app icons and signage. Happy to look at early '
        'work, give honest feedback, and talk about freelancing in Cairo over '
        'coffee.',
      ),
      findsOneWidget,
    );
    // Two friends carry hisam; one card says so.
    expect(find.text('via omar and layla'), findsOneWidget);
    // salim wrote nothing, so friends of friends don't see salim.
    expect(key('open-for-salim'), findsNothing);
    await tap(tester, key('reach-topic-hiking'));
    await reveal(tester, key('open-for-idris'));
    expect(key('open-for-idris'), findsOneWidget);
    expect(key('open-for-hisam'), findsNothing);
    await finish(tester);
  });

  testWidgets('a friend’s world narrows the people to those through them', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tester.longPress(key('avatar-omar'));
    await settle(tester);
    await tap(tester, key('menu-world'));
    await tap(tester, find.text('2 people via omar  ›'));
    expect(key('reach-via'), findsOneWidget);
    expect(key('open-for-ruba'), findsNothing);
    expect(key('open-for-hisam'), findsOneWidget);
    await reveal(tester, key('open-for-idris'));
    expect(key('open-for-idris'), findsOneWidget);
    await tester.tap(key('reach-via'));
    await settle(tester);
    expect(key('open-for-ruba'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('through omar: knock on hisam, wait, then a chat', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('open-reach'));
    await tap(tester, key('knock-hisam'));
    expect(key('knock-sheet'), findsOneWidget);
    // What they wrote heads the knock.
    expect(
      find.descendant(
        of: key('knock-sheet'),
        matching: find.textContaining('Ten years designing'),
      ),
      findsOneWidget,
    );
    // A topic is required.
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: key('send-knock'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tap(tester, key('topic-design feedback'));
    expect(
      find.text('hisam will see: You, via omar, about design feedback.'),
      findsOneWidget,
    );
    expect(
      find.text('No reply means nothing happens. We don’t tell omar.'),
      findsOneWidget,
    );
    await tester.enterText(
      field('Say why you’re reaching out'),
      'could you look at my app icons?',
    );
    await tap(tester, key('send-knock'));
    expect(key('knock-sheet'), findsNothing);
    expect(
      find.descendant(of: key('knock-hisam'), matching: find.text('Waiting')),
      findsOneWidget,
    );

    await back(tester);
    await openChats(tester);
    await tester.scrollUntilVisible(key('waiting-hisam'), 200);
    expect(find.text('Waiting for hisam · 14 days left'), findsOneWidget);
    await wait(tester, 5);
    expect(key('waiting-hisam'), findsNothing);
    expect(
      find.descendant(
        of: key('chat-row-hisam'),
        matching: find.text('via omar'),
      ),
      findsOneWidget,
    );
    await tap(tester, key('chat-row-hisam'));
    expect(key('introduced-note'), findsOneWidget);
    expect(find.text('Only you and hisam see this'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('their world: only what a friend of a friend opened, and an '
      'introduction through omar', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('open-reach'));
    await tap(tester, key('world-link-hisam'));
    expect(key('world-hisam'), findsOneWidget);
    expect(find.text('via omar and layla'), findsOneWidget);
    expect(key('open-for-note'), findsOneWidget);
    final world = find
        .descendant(of: key('world-hisam'), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(
      key('locked-spaces'),
      250,
      scrollable: world,
    );
    expect(find.text('Design work'), findsOneWidget);
    expect(
      find.text('2 more spaces stay with hisam’s friends'),
      findsOneWidget,
    );

    await tap(tester, key('ask-intro-hisam'));
    expect(key('intro-ask-sheet'), findsOneWidget);
    await tester.enterText(
      field('A line for omar'),
      'building an icon set, would love an expert eye',
    );
    await tap(tester, key('send-intro-ask'));
    expect(
      find.descendant(of: key('knock-hisam'), matching: find.text('Waiting')),
      findsOneWidget,
    );
    expect(key('ask-intro-hisam'), findsNothing);

    await back(tester);
    await back(tester);
    await openChats(tester);
    await tester.scrollUntilVisible(key('waiting-hisam'), 200);
    expect(
      find.text('omar introduced you · waiting for hisam'),
      findsOneWidget,
    );
    await wait(tester, 3);
    await tap(tester, key('chat-row-hisam'));
    expect(
      find.text('omar introduced you: “a good friend, you two should talk”'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a friend holding three asks can’t take another', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('open-reach'));
    await reveal(tester, key('world-link-ruba'));
    await tap(tester, key('world-link-ruba'));
    await tap(tester, key('ask-intro-ruba'));
    expect(
      find.text('layla can’t take introductions right now.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.descendant(
              of: key('send-intro-ask'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await finish(tester);
  });

  testWidgets('three open knocks at most', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('open-reach'));
    // tala already waits; two more fill the three.
    for (final (name, topic) in [
      ('hisam', 'design feedback'),
      ('idris', 'hiking'),
    ]) {
      await reveal(tester, key('knock-$name'));
      await quickTap(tester, key('knock-$name'));
      await quickTap(tester, key('topic-$topic'));
      await quickTap(tester, key('send-knock'));
    }
    await settle(tester);
    await reveal(tester, key('knock-ruba'), up: true);
    await quickTap(tester, key('knock-ruba'));
    expect(key('knock-limit'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('requests wait at the top of Chats; say hi opens a chat', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    // Something waits: a quiet dot, never how much.
    expect(tester.widget<Badge>(key('chats-badge')).isLabelVisible, isTrue);
    expect(chatsBadge('4'), findsNothing);
    await openChats(tester);
    expect(find.text('3 requests'), findsOneWidget);
    expect(key('request-yazan'), findsNothing);
    await tap(tester, key('requests-row'));
    expect(find.text('via layla and sami'), findsOneWidget);
    expect(
      find.text('maya introduced you: “my old manager, the best mentor I had”'),
      findsOneWidget,
    );
    expect(find.text('zein asks for an introduction to sara'), findsOneWidget);

    await tap(tester, key('say-hi-yazan'));
    expect(key('dm-yazan'), findsOneWidget);
    expect(key('introduced-note'), findsOneWidget);
    await back(tester);
    expect(key('request-yazan'), findsNothing);

    await tap(tester, key('introduce-zein'));
    expect(key('intro-ask-zein'), findsNothing);
    // Pausing a friend drops every request through them, silently.
    await tap(tester, key('request-more-munir'));
    await tap(tester, key('pause-maya'));
    expect(key('requests-row'), findsNothing);
    expect(key('chat-row-yazan'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the + opens your page ready to write; who wrote comes after', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    // The + opens your page with the keyboard up, not a sheet.
    await tap(tester, key('share-thought'));
    expect(key('you'), findsOneWidget);
    expect(key('composer'), findsNothing);
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.enterText(key('you-field'), 'first swim of the year /');
    await tester.pump();
    expect(find.text('6 Close friends'), findsOneWidget);
    await tap(tester, key('command-close'));
    await tap(tester, key('you-share'));
    expect(key('your-thought-100'), findsOneWidget);
    expect(find.text('[close] >'), findsWidgets);
    await wait(tester, 8);
    // Nour's face says she wrote; her words wait in your chat, not here.
    expect(key('wrote-100-nour'), findsOneWidget);
    expect(find.text('love this. tell me more?'), findsNothing);
    expect(
      find.descendant(of: key('wrote-100-nour'), matching: key('unread-nour')),
      findsOneWidget,
    );
    await tap(tester, key('wrote-100-nour'));
    expect(find.text('Your thought'), findsWidgets);
    expect(find.text('love this. tell me more?'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a # keeps a thought with its tag; a tag you come back to '
      'can become a Space on a ring', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('share-thought'));
    expect(key('tag-offer-walks'), findsNothing);

    await tester.enterText(key('you-field'), 'the old harbour path #wa');
    await tester.pump();
    expect(key('tags'), findsOneWidget);
    await tap(tester, key('tag-walks'));
    expect(key('tags'), findsNothing);
    await tap(tester, key('you-share'));

    // Twice now: the offer, once.
    expect(key('tag-offer-walks'), findsOneWidget);
    await tap(tester, key('tag-offer-yes'));
    await tap(tester, key('tag-space-ring-close'));
    await tap(tester, key('tag-space-make'));
    expect(key('tag-offer-walks'), findsNothing);

    await tester.enterText(key('you-field'), '#wa');
    await tester.pump();
    expect(
      find.descendant(of: key('tags'), matching: find.text('Space · Close')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a Space tag opens its shelf: moments under quiet time '
      'dividers, no ratings', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('you-avatar'));
    await tap(tester, key('tag-link-books'));
    expect(key('space-Books'), findsOneWidget);
    expect(key('shelf-when-this week'), findsOneWidget);
    expect(key('shelf-thought-1'), findsOneWidget);
    expect(key('shelf-when-August'), findsOneWidget);
    // Every entry is something you wrote, not a filled-in book record.
    expect(
      find.text(
        'finished The Pragmatic Programmer by Hunt & Thomas. '
        'should have read this years ago',
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    await finish(tester);
  });

  testWidgets('a friend\'s card names the Spaces they keep; a tag opens '
      'that shelf', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tilt(tester);
    await tap(tester, key('space-tag-omar-books'));
    expect(key('space-Books'), findsOneWidget);
    await back(tester);

    await swipeUp(tester);
    expect(key('space-tag-maya-work'), findsOneWidget);
    await tap(tester, key('space-tag-maya-work'));
    expect(key('space-Work'), findsOneWidget);
    expect(
      find.text('new job starts monday. nervous in the good way'),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('not now means never: the offer does not come back', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('share-thought'));
    for (final text in ['harbour again #walks', 'and again #walks']) {
      await tester.enterText(key('you-field'), text);
      await tester.pump();
      await tap(tester, key('you-share'));
      if (find.byKey(const ValueKey('tag-offer-walks')).evaluate().isNotEmpty) {
        await tap(tester, key('tag-offer-no'));
      }
    }
    expect(key('tag-offer-walks'), findsNothing);
    await finish(tester);
  });

  testWidgets('you choose who is Close; the rings follow', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('you-avatar'));
    await tap(tester, key('you-world'));
    expect(find.text('Close friends (6)  ›'), findsOneWidget);
    await tap(tester, key('you-close'));
    await tap(tester, key('close-maya'));
    expect(find.text('Close friends · 7 of 15'), findsOneWidget);
    await back(tester);
    expect(find.text('Close friends (7)  ›'), findsOneWidget);
    await back(tester);
    await back(tester);

    await tester.longPress(key('avatar-omar'));
    await settle(tester);
    expect(find.text('Move to Friends'), findsOneWidget);
    await tap(tester, key('menu-close'));
    await tap(tester, key('you-avatar'));
    await tap(tester, key('you-world'));
    expect(find.text('Close friends (6)  ›'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('friends of friends: being found and carrying are two yeses', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('you-avatar'));
    await tap(tester, key('you-world'));
    await tap(tester, key('ring-fof'));
    await tap(tester, key('you-fof'));
    await tap(tester, key('findable-switch'));
    // Carrying stays on: it is a separate choice.
    final carrying = find.text('You carry cards for: sara, tarek');
    await tester.scrollUntilVisible(
      carrying,
      200,
      scrollable: find
          .descendant(
            of: key('fof-settings'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(carrying, findsOneWidget);
    await tap(tester, key('carry-switch'));
    expect(find.text('You carry cards for: sara, tarek'), findsNothing);
    expect(
      find.text('Every switch works at once. Turning one off tells nobody.'),
      findsOneWidget,
    );
    await back(tester);
    expect(find.text('You can’t be found  ›'), findsOneWidget);
    // Nobody can find you, so the note friends of friends read is gone.
    expect(key('you-note'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'your page: swipe up the rings to go out, then view as a friend',
    (tester) async {
      await pumpPrototype(tester);
      await settle(tester);
      await tap(tester, key('you-avatar'));
      await tap(tester, key('you-world'));
      expect(key('your-thought-1'), findsOneWidget);
      expect(key('your-thought-0'), findsNothing);
      await tester.drag(key('you-rings'), const Offset(0, -120));
      await settle(tester);
      expect(key('your-thought-0'), findsOneWidget);
      expect(key('you-space-Runs'), findsOneWidget);
      await tester.drag(key('you-rings'), const Offset(0, -120));
      await settle(tester);
      expect(key('you-space-Books'), findsOneWidget);
      expect(key('you-note'), findsOneWidget);
      await tester.drag(key('you-rings'), const Offset(0, 120));
      await settle(tester);
      expect(key('you-space-Runs'), findsOneWidget);

      await tap(tester, key('view-as'));
      await tap(tester, key('view-as-friends'));
      expect(find.text('Viewing as a friend · sees 5 of 6'), findsOneWidget);
      expect(key('your-thought-1'), findsNothing);
      expect(key('you-add'), findsNothing);
      // Reactions and who wrote stay yours.
      expect(key('wrote-0'), findsNothing);
      await tap(tester, key('as-me'));
      expect(key('viewing'), findsNothing);
      expect(key('you-space-Runs'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('your page: / picks who sees a thought; a photo goes with it', (
    tester,
  ) async {
    await pumpPrototype(tester);
    await settle(tester);
    await tap(tester, key('you-avatar'));
    // Friends who wrote about your run, each a private row.
    expect(key('wrote-0-tarek'), findsOneWidget);
    expect(key('wrote-icon-0'), findsOneWidget);
    expect(find.text('wrote to you · in your chats'), findsNothing);
    await tester.enterText(key('you-field'), 'first swim of the year /');
    await tester.pump();
    expect(key('commands'), findsOneWidget);
    await tap(tester, key('command-close'));
    expect(key('commands'), findsNothing);
    await tap(tester, key('add-photo'));
    expect(key('attached-photo'), findsOneWidget);
    await tap(tester, key('you-share'));
    expect(key('your-thought-100'), findsOneWidget);
    expect(find.text('first swim of the year'), findsOneWidget);
    expect(key('attached-photo'), findsNothing);
    await finish(tester);
  });

  testWidgets(
    'spreading fingers on the tilted orbit shows every thought over its friend',
    (tester) async {
      await pumpPrototype(tester);
      await settle(tester);
      await swipeUp(tester);
      expect(key('card-omar'), findsOneWidget);
      expect(key('new-thought-nour'), findsNothing);

      Future<void> pinch(
        double from,
        double to, {
        bool collapse = false,
      }) async {
        const centre = Offset(195, 260);
        final a = await tester.startGesture(centre - Offset(from, 0));
        final b = await tester.startGesture(centre + Offset(from, 0));
        for (var i = 1; i <= 6; i++) {
          final d = from + (to - from) * i / 6;
          await a.moveTo(centre - Offset(d, 0));
          await b.moveTo(centre + Offset(d, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        // iOS can report both touches at one spot as they lift.
        if (collapse) {
          await tester.pump(const Duration(milliseconds: 120));
          await a.moveTo(centre);
          await b.moveTo(centre);
        }
        // One finger lifts first, and the other drifts before it follows.
        await a.up();
        await b.moveBy(const Offset(-90, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await b.up();
        await settle(tester);
      }

      await pinch(50, 120);
      expect(key('card-omar'), findsNothing);
      expect(key('new-thought-nour'), findsOneWidget);
      await pinch(120, 50, collapse: true);
      expect(key('card-omar'), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets(
    'the flat orbit shows faces; spreading fingers brings every bubble',
    (tester) async {
      await pumpPrototype(tester);
      await settle(tester);
      expect(key('new-thought-nour'), findsNothing);
      expect(key('thought-dot-nour'), findsOneWidget);

      Future<void> pinch(double from, double to) async {
        const centre = Offset(195, 320);
        final a = await tester.startGesture(centre - Offset(from, 10));
        await tester.pump(const Duration(milliseconds: 80));
        await a.moveBy(const Offset(6, 4));
        final b = await tester.startGesture(centre + Offset(from, 10));
        for (var i = 1; i <= 8; i++) {
          final d = from + (to - from) * i / 8;
          await a.moveTo(centre - Offset(d, 4));
          await b.moveTo(centre + Offset(d, 4));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 120));
        await a.moveTo(centre);
        await b.moveTo(centre);
        await a.up();
        await b.moveBy(const Offset(-90, 0));
        await tester.pump(const Duration(milliseconds: 16));
        await b.up();
        await settle(tester);
      }

      await pinch(50, 130);
      expect(key('new-thought-nour'), findsOneWidget);
      expect(key('thought-dot-nour'), findsNothing);
      // Still flat: no reply dock.
      expect(field('Reply to omar…'), findsNothing);
      await pinch(130, 50);
      expect(key('new-thought-nour'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets(
    'your page: photos and videos open full screen; voice plays here',
    (tester) async {
      await pumpPrototype(tester);
      await settle(tester);
      await tap(tester, key('you-avatar'));
      expect(key('voice-1'), findsOneWidget);
      await tap(tester, key('media-0-1'));
      expect(key('media-viewer'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(key('media-viewer'), findsNothing);
      await finish(tester);
    },
  );

  testWidgets('Reduce Motion keeps the flat orbit and tilts without motion', (
    tester,
  ) async {
    await pumpPrototype(tester, disableAnimations: true);
    await tester.pump();
    expect(key('avatar-omar'), findsOneWidget);
    await tester.dragFrom(const Offset(195, 600), const Offset(0, -300));
    await tester.pump();
    expect(key('card-omar'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a face opens its chat under a row of Close; the row switches '
      'the chat and holds still; back sends the faces home', (tester) async {
    await pumpPrototype(tester);
    await settle(tester);
    final onOrbit = tester.getCenter(key('avatar-tarek'));

    await tester.tap(key('avatar-omar'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(key('strip-ghost-tarek'), findsOneWidget);
    expect(tester.getCenter(key('strip-ghost-tarek')), isNot(onOrbit));

    await settle(tester);
    expect(key('strip-ghost-tarek'), findsNothing);
    expect(key('dm-omar'), findsOneWidget);
    for (final name in ['omar', 'tarek', 'nour', 'layla', 'sara', 'dina']) {
      expect(key('strip-face-$name'), findsOneWidget);
    }
    final omarAt = tester.getCenter(key('strip-face-omar'));
    final tarekAt = tester.getCenter(key('strip-face-tarek'));
    expect(omarAt.dx, lessThan(tarekAt.dx));

    await tap(tester, key('strip-face-tarek'));
    expect(key('dm-tarek'), findsOneWidget);
    expect(key('dm-omar'), findsNothing);
    expect(field('Reply to tarek…'), findsOneWidget);
    expect(tester.getCenter(key('strip-face-omar')), omarAt);
    expect(tester.getCenter(key('strip-face-tarek')), tarekAt);

    await back(tester);
    expect(key('chat-strip'), findsNothing);
    expect(tester.getCenter(key('avatar-tarek')), onOrbit);
    final face = tester.widget<Opacity>(
      find
          .descendant(of: key('avatar-tarek'), matching: find.byType(Opacity))
          .first,
    );
    expect(face.opacity, greaterThan(0));
    await finish(tester);
  });

  testWidgets('with Reduce Motion the chat and its row arrive at once', (
    tester,
  ) async {
    await pumpPrototype(tester, disableAnimations: true);
    await settle(tester);
    await tester.tap(key('avatar-omar'));
    await tester.pump();
    await tester.pump();
    expect(key('dm-omar'), findsOneWidget);
    expect(key('strip-face-tarek'), findsOneWidget);
    expect(key('strip-ghost-tarek'), findsNothing);
    await finish(tester);
  });
}
