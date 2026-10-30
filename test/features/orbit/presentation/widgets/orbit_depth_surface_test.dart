import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../shared/bidi_layout_checks.dart';
import '../../support/depth_fixtures.dart';

void main() {
  late DateTime now;
  late List<String> seen, chats, opened, settled;
  late List<bool> ownership;
  late Map<String, PostModel> thoughts;
  late ValueNotifier<int> reset;
  VoidCallback? back;
  bool rtl = false;
  bool reduceMotion = true;
  Brightness brightness = Brightness.dark;
  setUp(() {
    now = depthNow;
    seen = [];
    chats = [];
    opened = [];
    settled = [];
    ownership = [];
    thoughts = {for (var i = 0; i < 12; i++) 'peer-$i': depthThought(i)};
    reset = ValueNotifier(0);
    back = null;
    rtl = false;
    reduceMotion = true;
    brightness = Brightness.dark;
  });
  Future<void> mount(
    WidgetTester tester, {
    Future<List<PostMediaAttachmentModel>> Function(String)? load,
    Widget? child,
    List<int>? order,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
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
                for (final i in order ?? [for (var i = 0; i < 12; i++) i])
                  OrbitFriendItem(depthFriend(i)),
              ],
              thoughts: thoughts,
              nowProvider: () => now,
              resetSignal: reset,
              onThoughtDeparted: seen.add,
              onFriendTap: (friend) => chats.add(friend.peerId),
              onThoughtTap: opened.add,
              onOwnsHostGestureChanged: ownership.add,
              onBackActionChanged: (value) => back = value,
              onSettled: (layer, front, turned) =>
                  settled.add('${layer.name}:$front:$turned'),
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

  Future<void> rest(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> swipe(WidgetTester tester, Offset delta) async {
    await tester.timedDrag(
      find.byType(OrbitDepthSurface),
      delta,
      const Duration(seconds: 1),
    );
    await rest(tester);
  }

  Future<void> tapFace(WidgetTester tester, int i) async {
    await tester.tap(find.byKey(ValueKey('orbit-depth-face-peer-$i')));
    await rest(tester);
  }

  Future<void> enter(WidgetTester tester) =>
      swipe(tester, const Offset(0, -220));

  Finder card(int i) => find.byKey(ValueKey('orbit-depth-card-post-$i'));
  Finder face(int i) => find.byKey(ValueKey('orbit-depth-face-peer-$i'));
  Finder seatOf(int i) =>
      find.byKey(ValueKey('orbit-depth-seat-inner-peer-$i'));
  final anyCard = find.byWidgetPredicate(
    (w) => switch (w.key) {
      ValueKey<String>(:final value) =>
        value.startsWith('orbit-depth-card-') &&
            value != 'orbit-depth-card-slot',
      _ => false,
    },
  );
  final centerSlot = find.byKey(const ValueKey('orbit-depth-center-slot'));
  String centerName(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const ValueKey('orbit-depth-name'))).data!;
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    ServicesBinding.instance.channelBuffers.push(
      SystemChannels.lifecycle.name,
      const StringCodec().encodeMessage('$state'),
      (_) {},
    );
    await tester.pump();
  }

  testWidgets(
    'a vertical swipe enters with the friend chatted with last in the '
    'center, named, with their thought below, and marks nothing',
    (tester) async {
      await mount(tester);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(
          of: find.byKey(const ValueKey('flat-scroll')),
          matching: find.byType(Scrollable),
        ),
      );
      await enter(tester);
      expect(
        find.byKey(const ValueKey('orbit-depth-inner-top')),
        findsOneWidget,
      );
      expect(centerName(tester), 'Friend 0');
      expect(tester.getSize(centerSlot), const Size(72, 72));
      expect(tester.getCenter(centerSlot).dx, 195);
      expect(anyCard, findsOneWidget);
      expect(card(0), findsOneWidget);
      expect(
        tester.getTopLeft(card(0)).dy,
        greaterThan(tester.getBottomLeft(seatOf(1)).dy),
      );
      expect(scrollable.position.pixels, 0);
      expect(seen, isEmpty);
      expect(ownership, [true]);
      expect(back, isNotNull);
      expect(settled, ['inner:peer-0:false']);
      expect(tester.binding.transientCallbackCount, 0);
      await finish(tester);
    },
  );

  for (final (theme, tint) in [
    (Brightness.dark, const Color(0xFFCFE0FF)),
    (Brightness.light, const Color(0xFF2F5FB8)),
  ]) {
    testWidgets('the near half of the ring is tinted blue in ${theme.name} '
        'theme and the far half keeps the plain line', (tester) async {
      brightness = theme;
      await mount(tester);
      await enter(tester);
      final text = Theme.of(
        tester.element(find.byType(OrbitDepthSurface)),
      ).colorScheme.onSurface;
      expect(
        tester.renderObject(find.byKey(const ValueKey('orbit-depth-ring'))),
        paints
          ..path(color: text.withValues(alpha: .25))
          ..path(color: tint.withValues(alpha: .45)),
      );
      await finish(tester);
    });
  }

  testWidgets(
    'entering 3D, a face flies from where the 2D orbit showed it to its seat '
    'as the finger drags; a face 2D did not show fades in at its seat',
    (tester) async {
      reduceMotion = false;
      await mount(
        tester,
        child: const Stack(
          children: [
            Positioned(
              left: 160,
              top: 365,
              width: 70,
              height: 70,
              child: SizedBox(key: ValueKey('orbit-center-self-avatar')),
            ),
            Positioned(
              left: 242,
              top: 379,
              width: 42,
              height: 42,
              child: SizedBox(key: ValueKey('peer-1')),
            ),
          ],
        ),
      );
      final finger = await tester.startGesture(const Offset(195, 700));
      await finger.moveBy(const Offset(0, -12));
      await tester.pump();
      final start = tester.getRect(seatOf(1));
      expect(start.center.dx, closeTo(263, 2));
      expect(start.center.dy, closeTo(400, 2));
      expect(start.width, closeTo(42, 1));
      await finger.moveBy(const Offset(0, -148));
      await tester.pump();
      final half = tester.getRect(seatOf(1)).center;
      double alpha(int i) => tester
          .widget<Opacity>(
            find
                .descendant(of: seatOf(i), matching: find.byType(Opacity))
                .first,
          )
          .opacity;
      final fadingIn = alpha(2);
      await finger.up();
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      final seat = tester.getRect(seatOf(1)).center;
      expect(seat.dy, lessThan(200));
      expect(half.dx, closeTo((263 + seat.dx) / 2, 2));
      expect(half.dy, closeTo((400 + seat.dy) / 2, 2));
      expect(fadingIn, closeTo(.5, .02));
      expect(alpha(2), 1);
      await finish(tester);
    },
  );

  testWidgets(
    'the 3D ring and the thought sit where the shipped 3D Orbit put them',
    (tester) async {
      await mount(tester);
      await enter(tester);
      // Values from main's placement: 67 degree tilt, camera 3, ring radius
      // 146, scale min(width / 390, height / 640), centre below the old
      // outer ring's far edge, thought slot max(cy + 146 cos(tilt) 1.45 + 38,
      // 140).
      final center = tester.getCenter(centerSlot);
      expect(center.dx, closeTo(195, .05));
      expect(center.dy, closeTo(105.89, .05));
      expect(tester.getTopLeft(card(0)).dy, closeTo(226.61, .05));
      final next = tester.getCenter(seatOf(1));
      expect(next.dx - 195, closeTo(149.35, .05));
      expect(next.dy - 105.89, closeTo(33.69, .05));
      await finish(tester);
    },
  );

  testWidgets('only friends with a live thought are on the ring', (
    tester,
  ) async {
    thoughts = {
      'peer-2': depthThought(2),
      'peer-3': depthThought(3, expiry: depthNow),
      'peer-5': depthThought(5),
    };
    await mount(tester);
    await enter(tester);
    expect(centerName(tester), 'Friend 2');
    expect(face(2), findsOneWidget);
    expect(face(5), findsOneWidget);
    for (final i in [0, 1, 3, 4, 6]) {
      expect(face(i), findsNothing, reason: 'peer-$i');
    }
    await finish(tester);
  });

  testWidgets('nothing turns on its own', (tester) async {
    await mount(tester);
    await enter(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(centerName(tester), 'Friend 0');
    expect(card(0), findsOneWidget);
    expect(seen, isEmpty);
    expect(tester.binding.transientCallbackCount, 0);
    await finish(tester);
  });

  testWidgets(
    'a right-to-left swipe brings the next friend, exactly one seat, and '
    'marks the thought that left',
    (tester) async {
      await mount(tester);
      await enter(tester);
      await swipe(tester, const Offset(-400, 0));
      expect(centerName(tester), 'Friend 1');
      expect(card(1), findsOneWidget);
      expect(seen, ['post-0']);
      expect(settled.last, 'inner:peer-1:true');
      await swipe(tester, const Offset(400, 0));
      expect(centerName(tester), 'Friend 0');
      expect(seen, ['post-0', 'post-1']);
      await swipe(tester, const Offset(400, 0));
      expect(centerName(tester), 'Friend 11');
      await finish(tester);
    },
  );

  testWidgets('a short drag springs back without marking', (tester) async {
    await mount(tester);
    await enter(tester);
    await tester.drag(find.byType(OrbitDepthSurface), const Offset(-20, 0));
    await tester.pump();
    await tester.pump();
    expect(centerName(tester), 'Friend 0');
    expect(seen, isEmpty);
    await finish(tester);
  });

  testWidgets('in a right-to-left app the next friend waits on the left and '
      'a left-to-right swipe brings it', (tester) async {
    rtl = true;
    await mount(tester);
    await enter(tester);
    expect(
      tester.getCenter(seatOf(1)).dx,
      lessThan(tester.getCenter(centerSlot).dx),
    );
    await swipe(tester, const Offset(400, 0));
    expect(centerName(tester), 'Friend 1');
    await finish(tester);
  });

  testWidgets(
    'tapping a ring face brings it to the center; tapping the center opens '
    'the chat; tapping the thought opens it',
    (tester) async {
      await mount(tester);
      await enter(tester);
      await tapFace(tester, 2);
      expect(centerName(tester), 'Friend 2');
      expect(chats, isEmpty);
      expect(seen, ['post-0']);
      await tester.tap(face(2));
      await tester.tap(find.text('Thought 2'));
      expect(chats, ['peer-2']);
      expect(opened, ['post-2']);
      await finish(tester);
    },
  );

  testWidgets(
    'one seat from rest settles in about 0.9 s without overshooting the '
    'center',
    (tester) async {
      reduceMotion = false;
      await mount(tester);
      await enter(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(face(1));
      // The friend leaving the center slides back to the ring at the turn's
      // own pace, without the lift that pulls the arriving face in early.
      final xs = <double>[];
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        xs.add(195 - tester.getCenter(seatOf(0)).dx);
      }
      final seat = xs.last;
      final settledAt =
          10 * (xs.lastIndexWhere((x) => (x - seat).abs() >= 1) + 2);
      expect(seat, greaterThan(100));
      expect(xs.reduce((a, b) => a > b ? a : b), lessThan(seat + .5));
      expect(settledAt, inInclusiveRange(700, 1000));
      expect(centerName(tester), 'Friend 1');
      await finish(tester);
    },
  );

  testWidgets(
    'photos keep one decode size through a turn, so they never reload and '
    'flicker',
    (tester) async {
      reduceMotion = false;
      await mount(tester);
      await enter(tester);
      await tester.pump(const Duration(seconds: 2));
      await tester.tap(face(1));
      final sizes = <double>{};
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        sizes.addAll(
          tester
              .widgetList<UserAvatar>(find.byType(UserAvatar))
              .map((avatar) => avatar.size),
        );
      }
      expect(sizes, {72.0});
      expect(tester.getSize(seatOf(0)).width, lessThan(40));
      await finish(tester);
    },
  );

  testWidgets('Reduce Motion cuts to the next friend with a 200 ms crossfade', (
    tester,
  ) async {
    await mount(tester);
    await enter(tester);
    await tester.tap(face(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final slot = centerSlot;
    expect(
      find.descendant(of: slot, matching: find.byType(UserAvatar)),
      findsNWidgets(2),
    );
    expect(card(0), findsOneWidget);
    expect(card(1), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      find.descendant(of: slot, matching: find.byType(UserAvatar)),
      findsOneWidget,
    );
    expect(anyCard, findsOneWidget);
    expect(card(1), findsOneWidget);
    await finish(tester);
  });

  testWidgets(
    'friends joining or leaving the queue never change who is in the center',
    (tester) async {
      await mount(tester, order: [0, 1, 2, 3, 4, 5, 6, 7]);
      await enter(tester);
      await tapFace(tester, 2);
      expect(centerName(tester), 'Friend 2');
      thoughts = {...thoughts, 'peer-20': depthThought(20)};
      await mount(tester, order: [20, 0, 1, 2, 3, 4, 5, 6, 7]);
      expect(centerName(tester), 'Friend 2');
      thoughts = {...thoughts}..remove('peer-0');
      await mount(tester, order: [20, 0, 1, 2, 3, 4, 5, 6, 7]);
      expect(centerName(tester), 'Friend 2');
      expect(card(2), findsOneWidget);
      seen.clear();
      thoughts = {...thoughts}..remove('peer-2');
      await mount(tester, order: [20, 1, 2, 3, 4, 5, 6, 7]);
      await rest(tester);
      expect(card(2), findsNothing);
      expect(anyCard, findsOneWidget);
      expect(seen, isEmpty);
      // The newcomer joined the end of the frozen queue and is on the ring.
      expect(face(20), findsOneWidget);
      await finish(tester);
    },
  );

  testWidgets('with no live thoughts the ring says so', (tester) async {
    thoughts = {};
    await mount(tester);
    await enter(tester);
    expect(
      find.byKey(const ValueKey('orbit-depth-empty-ring')),
      findsOneWidget,
    );
    expect(find.text('No thoughts here right now.'), findsOneWidget);
    expect(anyCard, findsNothing);
    await finish(tester);
  });

  testWidgets(
    'back returns to flat, marks the shown thought once, and lets the route '
    'pop again',
    (tester) async {
      await mount(tester);
      await enter(tester);
      back!();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-depth-stage')), findsNothing);
      expect(back, isNull);
      expect(seen, ['post-0']);
      expect(ownership, [true, false]);
      expect(
        tester
            .widget<PopScope>(
              find.byWidgetPredicate((widget) => widget is PopScope),
            )
            .canPop,
        isTrue,
      );
      expect(settled.last, 'flat:null:false');
      await finish(tester);
    },
  );

  testWidgets('a covering route holds the ring and resumes it on pop', (
    tester,
  ) async {
    await mount(tester);
    await enter(tester);
    await swipe(tester, const Offset(-400, 0));
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
    Navigator.of(context).pop();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(centerName(tester), 'Friend 1');
    expect(card(1), findsOneWidget);
    expect(back, isNotNull);
    expect(ownership, [true, false, true]);
    expect(seen, ['post-0']);
    await finish(tester);
  });

  testWidgets(
    'a notification shade or dialog keeps 3D; backgrounding the app resets it',
    (tester) async {
      await mount(tester);
      await enter(tester);
      await lifecycle(tester, AppLifecycleState.inactive);
      expect(card(0), findsOneWidget);
      expect(back, isNotNull);
      await lifecycle(tester, AppLifecycleState.paused);
      expect(back, isNull);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(card(0), findsNothing);
      expect(find.text('Flat circle'), findsOneWidget);
      await finish(tester);
    },
  );

  for (final control in ['center', 'ring', 'card']) {
    testWidgets(
      'a second finger suppresses the $control tap for the whole sequence',
      (tester) async {
        await mount(tester);
        await enter(tester);
        final target = switch (control) {
          'center' => face(0),
          'ring' => face(1),
          _ => find.text('Thought 0'),
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
        expect(centerName(tester), 'Friend 0');
        await finish(tester);
      },
    );
  }

  testWidgets(
    'entering depth again shows the card media it already loaded at once',
    (tester) async {
      final photo = PostMediaAttachmentModel(
        mediaId: 'photo-0',
        postId: 'post-0',
        blobId: 'blob-0',
        kind: 'image',
        mime: 'image/jpeg',
        sizeBytes: 1,
        createdAt: depthNow.toIso8601String(),
      );
      thoughts['peer-0'] = depthThought(0, mediaKind: 'image');
      Completer<List<PostMediaAttachmentModel>>? held;
      await mount(tester, load: (_) => held?.future ?? Future.value([photo]));
      await enter(tester);
      expect(find.byType(MediaGrid), findsOneWidget);
      await swipe(tester, const Offset(0, 220));
      expect(card(0), findsNothing);
      held = Completer();
      await enter(tester);
      expect(card(0), findsOneWidget);
      expect(find.byType(MediaGrid), findsOneWidget);
      held.complete([photo]);
      await tester.pump();
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
      await enter(tester);
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

  for (final c in bidiCases) {
    testWidgets('the 3D card lays out mixed text: ${c.label}', (tester) async {
      thoughts['peer-0'] = depthThought(0, text: c.text);
      await mount(tester);
      await enter(tester);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.byKey(const ValueKey('orbit-depth-text-post-0')),
      );
      expectBidiLayout(
        c,
        direction: paragraph.textDirection,
        boxes: paragraph.getBoxesForSelection,
        area: tester.getRect(card(0)),
        toGlobal: paragraph.localToGlobal,
      );
      await finish(tester);
    });
  }
  for (final appRtl in [false, true]) {
    for (final (text, direction) in [
      ('مرحبا 🙂', TextDirection.rtl),
      ('Hi 🙂', TextDirection.ltr),
    ]) {
      testWidgets(
        'the 3D card puts a short ${direction.name} thought on its own side '
        'in a ${appRtl ? 'right-to-left' : 'left-to-right'} app',
        (tester) async {
          rtl = appRtl;
          thoughts['peer-0'] = depthThought(0, text: text);
          await mount(tester);
          await enter(tester);
          final paragraph = tester.renderObject<RenderParagraph>(
            find.byKey(const ValueKey('orbit-depth-text-post-0')),
          );
          expect(paragraph.textDirection, direction);
          final start = paragraph
              .localToGlobal(
                paragraph.getOffsetForCaret(
                  const TextPosition(offset: 0),
                  Rect.zero,
                ),
              )
              .dx;
          final area = tester.getRect(card(0));
          expect(
            start,
            closeTo(direction == TextDirection.rtl ? area.right : area.left, 2),
          );
          await finish(tester);
        },
      );
    }
  }
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
