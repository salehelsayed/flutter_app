import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_media.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/depth_fixtures.dart';

void main() {
  late DateTime now;
  late List<String> seen, chats, opened;
  late List<bool> ownership;
  late Map<String, PostModel> thoughts;
  late ValueNotifier<int> reset;
  VoidCallback? back;
  bool active = true;
  bool enabled = true;
  bool rtl = false;
  bool reduceMotion = true;
  int population = 14;
  setUp(() {
    now = depthNow;
    seen = [];
    chats = [];
    opened = [];
    ownership = [];
    thoughts = {
      for (var i = 0; i < 14; i++) 'peer-$i': depthThought(i, read: i == 0),
    };
    reset = ValueNotifier(0);
    back = null;
    active = true;
    enabled = true;
    rtl = false;
    reduceMotion = true;
    population = 14;
  });
  Future<void> mount(
    WidgetTester tester, {
    Future<List<PostMediaAttachmentModel>> Function(String)? load,
    Widget? child,
    Size size = const Size(390, 640),
    double topClearance = 0,
    double bottomClearance = 0,
    List<int>? order,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(
            body: OrbitDepthSurface(
              items: [
                for (final i
                    in order ?? [for (var i = 0; i < population; i++) i])
                  OrbitFriendItem(depthFriend(i)),
              ],
              thoughts: thoughts,
              active: active,
              gesturesEnabled: enabled,
              topClearance: topClearance,
              bottomClearance: bottomClearance,
              nowProvider: () => now,
              resetSignal: reset,
              onThoughtDeparted: seen.add,
              onFriendTap: (friend) => chats.add(friend.peerId),
              onThoughtTap: opened.add,
              onOpenFriends: () => opened.add('friends'),
              onOwnsHostGestureChanged: ownership.add,
              onBackActionChanged: (value) => back = value,
              loadMedia: load,
              downloadMedia: (item) async => item,
              child:
                  child ??
                  SingleChildScrollView(
                    key: const ValueKey('flat-scroll'),
                    child: Container(
                      height: 1400,
                      color: Colors.transparent,
                      child: const Text('Flat circle'),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    reset.dispose();
  }

  Future<void> swipe(WidgetTester tester, Offset delta) async {
    await tester.timedDrag(
      find.byType(OrbitDepthSurface),
      delta,
      const Duration(seconds: 1),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder card(int i) => find.byKey(ValueKey('orbit-depth-card-post-$i'));
  Finder face(int i) => find.byKey(ValueKey('orbit-depth-face-peer-$i'));
  final anyCard = find.byWidgetPredicate(
    (w) => switch (w.key) {
      ValueKey<String>(:final value) =>
        value.startsWith('orbit-depth-card-') &&
            value != 'orbit-depth-card-slot',
      _ => false,
    },
  );
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.lifecycle.name,
      const StringCodec().encodeMessage('$state'),
      (_) {},
    );
    await tester.pump();
  }

  void expectAt(WidgetTester tester, Finder finder, Offset where) {
    final center = tester.getCenter(finder);
    expect(center.dx, closeTo(where.dx, .01));
    expect(center.dy, closeTo(where.dy, .01));
  }

  testWidgets(
    'vertical entry defeats flat scroll and lands first unseen without marking',
    (tester) async {
      await mount(tester);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('flat-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await swipe(tester, const Offset(0, -220));
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-top')),
        findsOneWidget,
      );
      expect(card(1), findsOneWidget);
      expect(scrollable.position.pixels, 0);
      expect(seen, isEmpty);
      expect(ownership, [true]);
      expect(back, isNotNull);
      expect(tester.binding.transientCallbackCount, 0);
      await finish(tester);
    },
  );
  testWidgets(
    'down entry puts dial below the card and returns outer inner flat via back',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, 220));
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-bottom')),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(card(1)).dy,
        lessThan(
          tester
              .getCenter(find.byKey(const ValueKey('orbit-depth-face-peer-1')))
              .dy,
        ),
      );
      await swipe(tester, const Offset(0, 240));
      expect(card(5), findsOneWidget);
      expect(seen, ['post-1']);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-bottom')),
        findsOneWidget,
      );
      expect(card(1), findsOneWidget);
      back!();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-bottom')),
        findsNothing,
      );
      expect(find.text('Flat circle'), findsOneWidget);
      expect(back, isNull);
      expect(ownership, [true, false]);
      await finish(tester);
    },
  );
  testWidgets(
    'turn folds while held, snaps on release, marks exact departed once',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final gesture = await tester.startGesture(const Offset(195, 300));
      await gesture.moveBy(const Offset(-90, 0));
      await tester.pump();
      expect(card(1), findsNothing);
      expect(
        find.byKey(const ValueKey('orbit-depth-note-post-1')),
        findsOneWidget,
      );
      expect(seen, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(card(1), findsNothing);
      expect(anyCard, findsOneWidget);
      expect(seen, ['post-1']);
      await finish(tester);
    },
  );
  testWidgets(
    'cancelled turn and second-finger remainder never mark or fling',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final first = await tester.startGesture(
        const Offset(130, 300),
        pointer: 1,
      );
      await first.moveBy(const Offset(-50, 0));
      await tester.pump();
      await first.cancel();
      await tester.pump();
      await tester.pump();
      expect(card(1), findsOneWidget);
      expect(seen, isEmpty);
      final a = await tester.startGesture(const Offset(110, 310), pointer: 2);
      final b = await tester.startGesture(const Offset(270, 310), pointer: 3);
      await a.moveBy(const Offset(35, 0));
      await b.moveBy(const Offset(-35, 0));
      await tester.pump();
      expect(card(1), findsNothing);
      expect(
        find.byKey(const ValueKey('orbit-depth-note-post-1')),
        findsOneWidget,
      );
      await b.up();
      await a.moveBy(const Offset(-200, 60));
      await a.up();
      await tester.pump();
      await tester.pump();
      expect(seen, isEmpty);
      // Spread restores the front card; a leftover finger did not change it.
      final c = await tester.startGesture(const Offset(150, 310), pointer: 4);
      final d = await tester.startGesture(const Offset(240, 310), pointer: 5);
      await c.moveBy(const Offset(-35, 0));
      await d.moveBy(const Offset(35, 0));
      await tester.pump();
      await c.up();
      await d.up();
      await tester.pump();
      await tester.pump();
      expect(card(1), findsOneWidget);
      expect(seen, isEmpty);
      await finish(tester);
    },
  );
  testWidgets(
    'tap nonfront selects, front opens chat, body opens existing thought route',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      await tester.tap(find.byKey(const ValueKey('orbit-depth-face-peer-2')));
      await tester.pump();
      await tester.pump();
      expect(card(2), findsOneWidget);
      expect(seen, ['post-1']);
      expect(chats, isEmpty);
      await tester.tap(find.byKey(const ValueKey('orbit-depth-face-peer-2')));
      await tester.pump();
      expect(chats, ['peer-2']);
      await tester.tap(find.text('Thought 2'));
      await tester.pump();
      expect(opened, ['post-2']);
      await tester.tap(find.byKey(const ValueKey('orbit-depth-outer-peek')));
      await tester.pump();
      await tester.pump();
      expect(card(5), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('orbit-depth-overflow')));
      await tester.pump();
      expect(opened.last, 'friends');
      await finish(tester);
    },
  );
  testWidgets(
    'read refresh keeps front, replacement switches exact card, expiry leaves empty seat',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      thoughts = {...thoughts, 'peer-1': depthThought(1, read: true)};
      await mount(tester);
      expect(card(1), findsOneWidget);
      thoughts = {
        ...thoughts,
        'peer-1': depthThought(
          1,
          id: 'replacement',
          expiry: now.add(const Duration(seconds: 3)),
        ),
      };
      await mount(tester);
      expect(
        find.byKey(const ValueKey('orbit-depth-card-replacement')),
        findsOneWidget,
      );
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('orbit-depth-card-replacement')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('orbit-depth-empty-peer-1')),
        findsOneWidget,
      );
      expect(seen, isEmpty);
      await finish(tester);
    },
  );
  testWidgets(
    'empty ring remains navigable and exact eligibility removal cannot preserve a face',
    (tester) async {
      thoughts = {};
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(
        find.byKey(const ValueKey('orbit-depth-empty-peer-1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('orbit-depth-face-peer-1')),
        findsNothing,
      );
      back!();
      await tester.pump();
      await tester.pump();
      expect(ownership.last, false);
      await finish(tester);
    },
  );
  testWidgets(
    'edit/find disable entry and inactive/reset clears back and media work without reads',
    (tester) async {
      enabled = false;
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(back, isNull);
      enabled = true;
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(back, isNotNull);
      active = false;
      await mount(tester);
      expect(back, isNull);
      expect(seen, isEmpty);
      active = true;
      await mount(tester);
      // Leaving the Orbit tab forgets the ring; coming back starts flat.
      expect(find.byKey(const ValueKey('orbit-depth-inner-top')), findsNothing);
      await swipe(tester, const Offset(0, -220));
      reset.value++;
      await tester.pump();
      expect(back, isNull);
      expect(seen, isEmpty);
      await finish(tester);
    },
  );
  testWidgets('RTL reverses dial rotation with mirrored seat geometry', (
    tester,
  ) async {
    await mount(tester);
    await swipe(tester, const Offset(0, -220));
    await swipe(tester, const Offset(-90, 0));
    final ltr = anyCard.evaluate().single.widget.key;
    reset.value++;
    await tester.pump();
    rtl = true;
    await mount(tester);
    await swipe(tester, const Offset(0, -220));
    await swipe(tester, const Offset(-90, 0));
    final mirrored = anyCard.evaluate().single.widget.key;
    expect(mirrored, ltr);
    await finish(tester);
  });
  testWidgets(
    'late previous-card media never reappears after selection; a covering route holds the ring and resumes it on pop',
    (tester) async {
      final held = Completer<List<PostMediaAttachmentModel>>();
      final loads = <String>[];
      Future<List<PostMediaAttachmentModel>> load(String id) {
        loads.add(id);
        return held.future;
      }

      thoughts = {...thoughts, 'peer-1': depthThought(1, mediaKind: 'image')};
      await mount(tester, load: load);
      await swipe(tester, const Offset(0, -220));
      expect(loads, ['post-1']);
      await tester.tap(find.byKey(const ValueKey('orbit-depth-face-peer-2')));
      await tester.pump();
      await tester.pump();
      held.complete([]);
      await tester.pump();
      expect(card(2), findsOneWidget);
      expect(
        find.byKey(const ValueKey('orbit-depth-media-retry')),
        findsNothing,
      );
      final context = tester.element(find.byType(OrbitDepthSurface));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('Covered')),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(back, isNull);
      expect(ownership.last, isFalse);
      expect(seen, ['post-1']);
      // The covering chat marks the thought read and re-sorts friends while
      // the orbit waits underneath; popping finds the same ring and card.
      thoughts = {...thoughts, 'peer-2': depthThought(2, read: true)};
      await mount(tester, load: load);
      Navigator.of(context).pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-top')),
        findsOneWidget,
      );
      expect(card(2), findsOneWidget);
      expect(back, isNotNull);
      expect(ownership, [true, false, true]);
      expect(seen, ['post-1']);
      await finish(tester);
    },
  );
  testWidgets(
    'expiry moves the replacement face to the same front position as its card',
    (tester) async {
      population = 3;
      thoughts = {
        'peer-0': depthThought(0, expiry: now.add(const Duration(seconds: 3))),
        'peer-1': depthThought(1),
      };
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final oldFront = tester.getCenter(
        find.byKey(const ValueKey('orbit-depth-face-peer-0')),
      );
      now = now.add(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(card(1), findsOneWidget);
      final replacement = tester.getCenter(
        find.byKey(const ValueKey('orbit-depth-face-peer-1')),
      );
      expect(replacement.dx, closeTo(oldFront.dx, .01));
      expect(replacement.dy, closeTo(oldFront.dy, .01));
      expect(
        find.byKey(const ValueKey('orbit-depth-empty-peer-0')),
        findsOneWidget,
      );
      expect(seen, isEmpty);
      await finish(tester);
    },
  );
  for (final control in ['face', 'peek', 'card', 'overflow']) {
    testWidgets(
      'small second-finger pinch suppresses $control tap for the entire sequence',
      (tester) async {
        await mount(tester);
        await swipe(tester, const Offset(0, -220));
        if (control == 'overflow') {
          await tester.tap(
            find.byKey(const ValueKey('orbit-depth-outer-peek')),
          );
          await tester.pump();
          await tester.pump();
          seen.clear();
        }
        final Finder target = switch (control) {
          'face' => find.byKey(const ValueKey('orbit-depth-face-peer-1')),
          'peek' => find.byKey(const ValueKey('orbit-depth-outer-peek')),
          'overflow' => find.byKey(const ValueKey('orbit-depth-overflow')),
          _ => find.text('Thought 1'),
        };
        final point = tester.getCenter(target);
        final side = point.dx < 200 ? 1.0 : -1.0;
        final a = await tester.startGesture(point, pointer: 21);
        final b = await tester.startGesture(
          point + Offset(100 * side, 0),
          pointer: 22,
        );
        await b.moveBy(Offset(-13 * side, 0));
        await tester.pump();
        await a.up();
        await b.up();
        await tester.pump();
        await tester.pump();
        expect(chats, isEmpty);
        expect(opened, isEmpty);
        expect(seen, isEmpty);
        expect(
          find.byKey(
            ValueKey(
              'orbit-depth-${control == 'overflow' ? 'outer' : 'inner'}-top',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(
            ValueKey('orbit-depth-note-post-${control == 'overflow' ? 5 : 1}'),
          ),
          findsOneWidget,
        );
        await finish(tester);
      },
    );
  }
  testWidgets(
    'spring back keeps route pop blocked until the final flat landing',
    (tester) async {
      reduceMotion = false;
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      await tester.pump(const Duration(seconds: 3));
      back!();
      await tester.pump(const Duration(milliseconds: 30));
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isFalse,
      );
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      expect(back, isNull);
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isTrue,
      );
      expect(seen, ['post-1']);
      await finish(tester);
    },
  );
  testWidgets(
    'turning Reduce Motion on during back finalizes flat and departure exactly once',
    (tester) async {
      reduceMotion = false;
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      back!();
      await tester.pump(const Duration(milliseconds: 30));
      reduceMotion = true;
      await mount(tester);
      final backCleared = back == null;
      final released = ownership.last == false;
      final canPop = tester
          .widget<PopScope>(
            find.byWidgetPredicate((widget) => widget is PopScope),
          )
          .canPop;
      final writes = List<String>.of(seen);
      final depthGone = find
          .byKey(const ValueKey('orbit-depth-inner-top'))
          .evaluate()
          .isEmpty;
      await tester.pump(const Duration(seconds: 3));
      final finalWrites = List<String>.of(seen);
      await finish(tester);
      expect(depthGone, isTrue);
      expect(backCleared, isTrue);
      expect(released, isTrue);
      expect(canPop, isTrue);
      expect(writes, ['post-1']);
      expect(finalWrites, ['post-1']);
    },
  );
  testWidgets(
    'partial entry tilts from the flat center before springing to the dock',
    (tester) async {
      reduceMotion = false;
      await mount(tester);
      final gesture = await tester.startGesture(const Offset(195, 350));
      await gesture.moveBy(const Offset(0, -80));
      await tester.pump();
      final self = find.byWidgetPredicate(
        (widget) => widget is UserAvatar && widget.peerId == '',
      );
      final partialY = tester.getCenter(self).dy;
      await gesture.moveBy(const Offset(0, -140));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();
      final finalY = tester.getCenter(self).dy;
      await finish(tester);
      expect(partialY, closeTo(266.47, .01));
      expect(finalY, closeTo(105.89, .01));
    },
  );
  testWidgets(
    'reverse vertical swipes traverse outer inner flat with a top card below its face',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(
        tester.getTopLeft(card(1)).dy,
        greaterThan(
          tester
              .getCenter(find.byKey(const ValueKey('orbit-depth-face-peer-1')))
              .dy,
        ),
      );
      await swipe(tester, const Offset(0, -240));
      expect(card(5), findsOneWidget);
      await swipe(tester, const Offset(0, 240));
      expect(card(1), findsOneWidget);
      await swipe(tester, const Offset(0, 220));
      expect(back, isNull);
      expect(ownership.last, isFalse);
      await finish(tester);
    },
  );
  testWidgets(
    'deliberate turn advances twenty percent of the real next thought gap without repacking empty seats',
    (tester) async {
      population = 5;
      thoughts = {'peer-0': depthThought(0), 'peer-1': depthThought(1)};
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(card(0), findsOneWidget);
      await swipe(tester, const Offset(40, 0));
      expect(card(1), findsOneWidget);
      expect(seen, ['post-0']);
      expect(
        find.byKey(const ValueKey('orbit-depth-empty-peer-2')),
        findsOneWidget,
      );
      await finish(tester);
    },
  );
  testWidgets(
    'replacement arriving during a held turn never inherits the departed read',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final gesture = await tester.startGesture(const Offset(195, 300));
      await gesture.moveBy(const Offset(-90, 0));
      await tester.pump();
      thoughts = {...thoughts, 'peer-1': depthThought(1, id: 'replacement')};
      await mount(tester);
      await gesture.up();
      await tester.pump();
      await tester.pump();
      final writes = List<String>.of(seen);
      await finish(tester);
      expect(writes, ['post-1']);
    },
  );
  testWidgets(
    'replacement shown only as an overview bubble is not marked on leaving',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final a = await tester.startGesture(const Offset(110, 310), pointer: 41);
      final b = await tester.startGesture(const Offset(270, 310), pointer: 42);
      await a.moveBy(const Offset(35, 0));
      await b.moveBy(const Offset(-35, 0));
      await a.up();
      await b.up();
      await tester.pump();
      await tester.pump();
      thoughts = {...thoughts, 'peer-1': depthThought(1, id: 'replacement')};
      await mount(tester);
      expect(
        find.byKey(const ValueKey('orbit-depth-note-replacement')),
        findsOneWidget,
      );
      back!();
      await tester.pump();
      await tester.pump();
      final writes = List<String>.of(seen);
      await finish(tester);
      expect(writes, isNot(contains('replacement')));
    },
  );
  testWidgets(
    'the front card keeps its media while the orbit springs into depth',
    (tester) async {
      reduceMotion = false;
      thoughts['peer-1'] = depthThought(1, mediaKind: 'image');
      await mount(tester, load: (_) async => const []);
      final gesture = await tester.startGesture(const Offset(195, 560));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -22));
        await tester.pump(const Duration(milliseconds: 40));
      }
      await gesture.up();
      final mediaStates = <State>{};
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 25));
        final media = find.byType(OrbitDepthMedia);
        if (media.evaluate().isNotEmpty) mediaStates.add(tester.state(media));
      }
      expect(card(1), findsOneWidget);
      expect(mediaStates, hasLength(1));
      await finish(tester);
    },
  );
  testWidgets(
    'entering depth again shows the card media it already loaded at once',
    (tester) async {
      final photo = PostMediaAttachmentModel(
        mediaId: 'photo-1',
        postId: 'post-1',
        blobId: 'blob-1',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 1,
        createdAt: depthNow.toIso8601String(),
      );
      thoughts['peer-1'] = depthThought(1, mediaKind: 'image');
      Completer<List<PostMediaAttachmentModel>>? held;
      await mount(tester, load: (_) => held?.future ?? Future.value([photo]));
      await swipe(tester, const Offset(0, -220));
      expect(find.byType(MediaGrid), findsOneWidget);
      await swipe(tester, const Offset(0, 220));
      expect(card(1), findsNothing);
      held = Completer();
      await swipe(tester, const Offset(0, -220));
      expect(card(1), findsOneWidget);
      expect(find.byType(MediaGrid), findsOneWidget);
      held.complete([photo]);
      await tester.pump();
      await finish(tester);
    },
  );
  testWidgets(
    'a notification shade or dialog keeps 3D; backgrounding the app resets it',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      await lifecycle(tester, AppLifecycleState.inactive);
      expect(card(1), findsOneWidget);
      expect(back, isNotNull);
      // Flutter stops drawing frames while paused; the reset shows on resume.
      await lifecycle(tester, AppLifecycleState.paused);
      expect(back, isNull);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(card(1), findsNothing);
      expect(find.text('Flat circle'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets(
    'seats hold still while friends re-sort in 3D, a friend who leaves takes the seat along, flat re-seats',
    (tester) async {
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final face1 = tester.getCenter(face(1));
      final face3 = tester.getCenter(face(3));
      final byRecency = [for (var i = 13; i >= 0; i--) i];
      await mount(tester, order: byRecency);
      expect(card(1), findsOneWidget);
      expectAt(tester, face(1), face1);
      expectAt(tester, face(3), face3);
      expect(seen, isEmpty);
      await mount(tester, order: byRecency.where((i) => i != 3).toList());
      expect(face(3), findsNothing);
      expect(
        find.byKey(const ValueKey('orbit-depth-seat-inner-peer-3')),
        findsNothing,
      );
      expectAt(tester, face(1), face1);
      await swipe(tester, const Offset(0, 220));
      expect(find.text('Flat circle'), findsOneWidget);
      await swipe(tester, const Offset(0, -220));
      expect(card(13), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets(
    'a thought taller than the card slot is clipped to it and still opens on tap',
    (tester) async {
      final long = List.filled(40, 'A long thought that keeps going').join(' ');
      thoughts['peer-1'] = depthThought(1, text: long);
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final slot = tester.getRect(card(1));
      expect(slot.bottom, lessThanOrEqualTo(620));
      expect(tester.getRect(find.text(long)).bottom, greaterThan(slot.bottom));
      expect(tester.takeException(), isNull);
      await tester.tapAt(slot.topLeft + const Offset(24, 24));
      await tester.pump();
      expect(opened, ['post-1']);
      await finish(tester);
    },
  );
  testWidgets(
    'bottom-anchored 3D keeps the front face and card above the nav band on a short screen',
    (tester) async {
      await mount(tester, size: const Size(360, 640), bottomClearance: 80);
      await swipe(tester, const Offset(0, 220));
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-bottom')),
        findsOneWidget,
      );
      final front = tester.getRect(face(1));
      expect(front.bottom, lessThanOrEqualTo(560));
      expect(tester.getRect(card(1)).bottom, lessThanOrEqualTo(front.top));
      await finish(tester);
    },
  );
  for (final size in const [Size(360, 640), Size(390, 844)]) {
    testWidgets(
      'top-anchored 3D keeps every seat and the outer peek below the header on ${size.width.toInt()}x${size.height.toInt()}',
      (tester) async {
        await mount(tester, size: size, topClearance: 56, bottomClearance: 80);
        await swipe(tester, const Offset(0, -220));
        expect(
          find.byKey(const ValueKey('orbit-depth-inner-top')),
          findsOneWidget,
        );
        final seats = find.byWidgetPredicate(
          (w) => switch (w.key) {
            ValueKey<String>(:final value) => value.startsWith(
              'orbit-depth-seat-',
            ),
            _ => false,
          },
        );
        final tops = [
          for (var i = 0; i < seats.evaluate().length; i++)
            tester.getRect(seats.at(i)).top,
        ];
        expect(tops.length, greaterThan(5));
        expect(tops.reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(56));
        expect(
          tester
              .getRect(find.byKey(const ValueKey('orbit-depth-outer-peek')))
              .top,
          greaterThanOrEqualTo(56),
        );
        expect(
          tester.getRect(card(1)).bottom,
          lessThanOrEqualTo(size.height - 80),
        );
        await finish(tester);
      },
    );
  }
  testWidgets(
    'a ring with no thoughts says so in the card slot instead of a blank dial',
    (tester) async {
      thoughts = {};
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-top')),
        findsOneWidget,
      );
      expect(find.text('No thoughts here right now.'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets(
    'flying to an empty outer ring says so; the inner card shows no such line',
    (tester) async {
      thoughts = {
        for (var i = 0; i < 5; i++) 'peer-$i': depthThought(i, read: i == 0),
      };
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      expect(anyCard, findsOneWidget);
      expect(find.text('No thoughts here right now.'), findsNothing);
      await swipe(tester, const Offset(0, -300));
      expect(
        find.byKey(const ValueKey('orbit-depth-outer-top')),
        findsOneWidget,
      );
      expect(anyCard, findsNothing);
      expect(find.text('No thoughts here right now.'), findsOneWidget);
      await finish(tester);
    },
  );
  testWidgets(
    'the outer-ring peek counts live thoughts and hides when there are none',
    (tester) async {
      thoughts = {
        for (var i = 0; i < 7; i++) 'peer-$i': depthThought(i, read: i == 0),
      };
      await mount(tester);
      await swipe(tester, const Offset(0, -220));
      final peek = find.byKey(const ValueKey('orbit-depth-outer-peek'));
      expect(
        tester
            .widget<Text>(
              find.descendant(of: peek, matching: find.byType(Text)),
            )
            .data,
        'Outer circle · 2',
      );
      thoughts = {
        for (var i = 0; i < 5; i++) 'peer-$i': depthThought(i, read: i == 0),
      };
      await mount(tester);
      expect(peek, findsNothing);
      await finish(tester);
    },
  );
  testWidgets(
    'the flat orbit stops ticking under the 3D stage and ticks again in flat',
    (tester) async {
      final ticks = ValueNotifier(0);
      await mount(tester, child: _TickCounter(ticks));
      var from = ticks.value;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ticks.value - from, 3);
      await swipe(tester, const Offset(0, -220));
      from = ticks.value;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ticks.value - from, 0);
      await swipe(tester, const Offset(0, 220));
      from = ticks.value;
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(ticks.value - from, 3);
      await finish(tester);
      ticks.dispose();
    },
  );
  testWidgets('the 3D card lays the thought out in its own direction', (
    tester,
  ) async {
    const arabic = 'مرحبا بالعالم';
    thoughts['peer-1'] = depthThought(1, text: arabic);
    await mount(tester);
    await swipe(tester, const Offset(0, -220));
    expect(
      tester.renderObject<RenderParagraph>(find.text(arabic)).textDirection,
      TextDirection.rtl,
    );
    await finish(tester);
  });
}

class _TickCounter extends StatefulWidget {
  const _TickCounter(this.ticks);
  final ValueNotifier<int> ticks;
  @override
  State<_TickCounter> createState() => _TickCounterState();
}

class _TickCounterState extends State<_TickCounter>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => widget.ticks.value++)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
