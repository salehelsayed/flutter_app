import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/conversation/domain/models/media_preview_descriptor.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_thought_note.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_thought_note_bubble.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

OrbitFriend _friend(int index) => OrbitFriend(
  contact: ContactModel(
    peerId: 'friend-$index',
    username: 'Friend $index',
    publicKey: 'pk-$index',
    rendezvous: '',
    signature: '',
    scannedAt: '2026-10-21T00:00:00Z',
  ),
  messageCount: 0,
  unreadCount: 0,
);

void main() {
  final start = DateTime.utc(2026, 10, 21, 12);
  OrbitThoughtNote note(
    String id, {
    String text = 'A thought',
    bool read = false,
    Duration lifetime = const Duration(hours: 1),
    MediaPreviewDescriptor? media,
  }) => OrbitThoughtNote(
    postId: id,
    text: text,
    media: media,
    isRead: read,
    expiresAt: start.add(lifetime),
  );
  final friends = [for (var i = 0; i < 14; i++) _friend(i)];
  final items = friends.map<OrbitItem>(OrbitFriendItem.new).toList();

  Widget wrap(Widget child, {bool reduceMotion = true}) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    ),
  );

  testWidgets('thought plus dismisses edit/find before opening a composer', (
    tester,
  ) async {
    var shared = 0;
    final findSignal = ValueNotifier(0);
    addTearDown(findSignal.dispose);
    await tester.pumpWidget(
      wrap(
        InnerCircleInteractiveSurface(
          userPeerId: 'self',
          items: const [],
          onFriendTap: (_) {},
          onGroupTap: (_) {},
          onSelfAvatarTap: () {},
          onComposeThought: () => shared++,
          findOpenSignal: findSignal,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.longPress(
      find.byKey(const ValueKey('orbit-center-self-avatar')),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('orbit-compose-thought')));
    await tester.pump();
    expect(shared, 0);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
    findSignal.value++;
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('orbit-compose-thought')));
    await tester.pump();
    expect(shared, 0);
    await tester.tap(find.byKey(const ValueKey('orbit-compose-thought')));
    expect(shared, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'only eligible ring friends receive notes, with separate note/chat taps',
    (tester) async {
      final openedThoughts = <String>[];
      final openedChats = <String>[];
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(
            userPeerId: 'self',
            items: items,
            nowProvider: () => start,
            thoughtsByPeerId: {
              'friend-0': note('live'),
              'friend-13': note('arc'),
              'friend-1': note('expired', lifetime: Duration.zero),
            },
            onThoughtTap: openedThoughts.add,
            onFriendTap: (friend) => openedChats.add(friend.peerId),
          ),
        ),
      );
      expect(find.byType(OrbitThoughtNoteBubble), findsOneWidget);
      await tester.tap(find.byType(OrbitThoughtNoteBubble));
      expect(openedThoughts, ['live']);
      expect(openedChats, isEmpty);
      await tester.tap(find.byKey(const ValueKey('orbit-node-0')));
      await tester.tap(find.byKey(const ValueKey('orbit-node-2')));
      expect(openedChats, ['friend-0', 'friend-2']);
      expect(
        tester
            .widgetList<OrbitalAvatar>(find.byType(OrbitalAvatar))
            .every((avatar) => avatar.unreadCount == 0),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('an Arabic note reads right to left in an English app', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        OrbitThoughtNoteBubble(
          authorName: 'Friend 0',
          note: note('ar', text: 'فكرة هادئة'),
        ),
      ),
    );
    final paragraph = tester.renderObject<RenderParagraph>(
      find.text('فكرة هادئة'),
    );
    expect(paragraph.textDirection, TextDirection.rtl);
  });

  testWidgets(
    'bubble width/ellipsis and only heavier text distinguish unseen',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          OrbitThoughtNoteBubble(
            authorName: 'Friend 0',
            note: note('short', text: 'H'),
          ),
        ),
      );
      final shortWidth = tester
          .getSize(find.byType(OrbitThoughtNoteBubble))
          .width;
      expect(shortWidth, 40);
      expect(
        tester.widget<Text>(find.text('H')).style!.fontWeight,
        FontWeight.w600,
      );
      final long = List.filled(100, 'long thought').join(' ');
      await tester.pumpWidget(
        wrap(
          OrbitThoughtNoteBubble(
            authorName: 'Friend 0',
            note: note('long', text: long, read: true),
          ),
        ),
      );
      final text = tester.widget<Text>(find.text(long));
      expect(tester.getSize(find.byType(OrbitThoughtNoteBubble)).width, 150);
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(text.style!.fontWeight, FontWeight.w400);
      expect(text.style!.fontSize, 11.5);
      expect(text.style!.height, 1.22);
    },
  );

  testWidgets('a note sized under the app text style shows all its text', (
    tester,
  ) async {
    // The app theme's inherited text style (on phones, a real font) must size
    // the bubble too, or the last letters are clipped.
    for (final shown in [
      note(
        'label',
        text: '',
        media: const MediaPreviewDescriptor(type: 'image', count: 1),
      ),
      note('bold', text: 'Reply thought from B'),
    ]) {
      await tester.pumpWidget(
        wrap(
          DefaultTextStyle(
            style: const TextStyle(letterSpacing: 3),
            child: OrbitThoughtNoteBubble(authorName: 'Friend 0', note: shown),
          ),
        ),
      );
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(OrbitThoughtNoteBubble),
          matching: find.byType(RichText),
        ),
      );
      final box = tester.getSize(
        find
            .descendant(
              of: find.byType(OrbitThoughtNoteBubble),
              matching: find.byType(Container),
            )
            .first,
      );
      // Never clipped: the laid-out lines fit the bubble, and text is only cut
      // where the ellipsis shows.
      expect(
        paragraph.size.height,
        lessThanOrEqualTo(box.height - 12 + 0.01),
        reason: shown.postId,
      );
      if (!paragraph.didExceedMaxLines) {
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.constraints.maxWidth + 0.01),
          reason: shown.postId,
        );
      }
    }
  });

  testWidgets('a media-only thought shows its media label; text wins', (
    tester,
  ) async {
    Future<void> show(String text, MediaPreviewDescriptor media) =>
        tester.pumpWidget(
          wrap(
            OrbitThoughtNoteBubble(
              authorName: 'Friend 0',
              note: note('media', text: text, media: media),
            ),
          ),
        );
    await show('', const MediaPreviewDescriptor(type: 'image', count: 3));
    expect(find.text('3 photos'), findsOneWidget);
    await show('', const MediaPreviewDescriptor(type: 'video', count: 1));
    expect(find.text('Video'), findsOneWidget);
    await show('', const MediaPreviewDescriptor(type: 'audio', count: 1));
    expect(find.text('Voice message'), findsOneWidget);
    await show('Look', const MediaPreviewDescriptor(type: 'image', count: 1));
    expect(find.text('Look'), findsOneWidget);
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets(
    'a shown note is a labelled semantics button that opens the thought',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final opened = <String>[];
      Widget scene(double visibility) => wrap(
        OrbitalVisualization(
          userPeerId: 'self',
          items: items.take(2).toList(),
          nowProvider: () => start,
          thoughtVisibility: visibility,
          thoughtsByPeerId: {
            'friend-0': note('live'),
            'friend-1': note(
              'voice',
              text: '',
              media: const MediaPreviewDescriptor(type: 'audio', count: 1),
            ),
          },
          onThoughtTap: opened.add,
        ),
      );
      await tester.pumpWidget(scene(1));
      final node = tester.getSemantics(
        find.bySemanticsLabel('Thought from Friend 0: A thought'),
      );
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      expect(
        find.semantics.byLabel('Thought from Friend 1: Voice message'),
        findsOne,
      );
      tester.semantics.tap(
        find.semantics.byLabel('Thought from Friend 0: A thought'),
      );
      expect(opened, ['live']);

      await tester.pumpWidget(scene(0.3));
      expect(find.byType(OrbitThoughtNoteBubble), findsNWidgets(2));
      expect(find.semantics.byLabel(RegExp('Thought from')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      semantics.dispose();
    },
  );

  testWidgets('notes appearing on a phone keep the centre node in place', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    Widget scene(Map<String, OrbitThoughtNote> thoughts) => wrap(
      InnerCircleInteractiveSurface(
        userPeerId: 'self',
        onSelfAvatarTap: () {},
        items: items.take(13).toList(),
        onFriendTap: (_) {},
        onGroupTap: (_) {},
        thoughtsByPeerId: thoughts,
        nowProvider: () => start,
      ),
    );
    Offset self() => tester.getCenter(
      find.byKey(const ValueKey('orbit-center-self-avatar')),
    );
    await tester.pumpWidget(scene(const {}));
    await tester.pump(const Duration(seconds: 2));
    final without = self();
    Map<String, OrbitThoughtNote> thoughts(int count) => {
      for (var i = 0; i < count; i++)
        'friend-$i': note('n$i', text: 'A longer thought about today $i'),
    };
    await tester.pumpWidget(scene(thoughts(4)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(OrbitThoughtNoteBubble), findsNWidgets(4));
    expect(self(), without);

    // Thirteen stacked notes outgrow the spare space; they still start on
    // the surface (below the app bar), and the centre yields only the rest.
    await tester.pumpWidget(scene(thoughts(13)));
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(OrbitThoughtNoteBubble), findsNWidgets(13));
    final top = tester.getRect(find.byType(InnerCircleInteractiveSurface)).top;
    final bubbleTops = [
      for (final element in find.byType(OrbitThoughtNoteBubble).evaluate())
        tester.getRect(find.byWidget(element.widget)).top,
    ];
    expect(bubbleTops.reduce(math.min), greaterThanOrEqualTo(top));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'the own note sits above the self node, clear of friends, and opens its thought',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      final semantics = tester.ensureSemantics();
      final opened = <String>[];
      var shares = 0;
      Widget scene(Map<String, OrbitThoughtNote> thoughts) => wrap(
        InnerCircleInteractiveSurface(
          userPeerId: 'self',
          onSelfAvatarTap: () {},
          onComposeThought: () => shares++,
          items: items.take(13).toList(),
          onFriendTap: (_) {},
          onGroupTap: (_) {},
          onThoughtTap: opened.add,
          thoughtsByPeerId: thoughts,
          nowProvider: () => start,
        ),
      );
      final friendNotes = {
        for (var i = 0; i < 4; i++)
          'friend-$i': note('n$i', text: 'A longer thought about today $i'),
      };
      final plus = find.byKey(const ValueKey('orbit-compose-thought'));
      final self = find.byKey(const ValueKey('orbit-center-self-avatar'));
      await tester.pumpWidget(scene(friendNotes));
      await tester.pump(const Duration(seconds: 2));
      final plusWithout = tester.getRect(plus);
      final selfWithout = tester.getRect(self);

      await tester.pumpWidget(
        scene({
          ...friendNotes,
          'self': note('mine', text: 'My own thought', read: true),
        }),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('My own thought'), findsOneWidget);
      expect(find.byType(OrbitThoughtNoteBubble), findsNWidgets(5));
      expect(tester.getRect(plus), plusWithout);
      expect(tester.getRect(self), selfWithout);
      final own = tester.getRect(
        find.byKey(const ValueKey('orbit-thought-note-self')),
      );
      expect(own.bottom, lessThanOrEqualTo(selfWithout.top));
      expect(own.center.dx, closeTo(selfWithout.center.dx, 0.01));
      for (var i = 0; i < 13; i++) {
        final face = tester.getRect(
          find.descendant(
            of: find.byKey(ValueKey('orbit-node-$i')),
            matching: find.byType(OrbitalAvatar),
          ),
        );
        expect(own.overlaps(face), isFalse, reason: 'face $i');
        if (i < 4) {
          final friendNote = tester.getRect(
            find.byKey(ValueKey('orbit-thought-note-$i')),
          );
          expect(own.overlaps(friendNote), isFalse, reason: 'note $i');
        }
      }
      expect(find.semantics.byLabel('Your thought: My own thought'), findsOne);
      tester.semantics.tap(
        find.semantics.byLabel('Your thought: My own thought'),
      );
      expect(opened, ['mine']);
      await tester.tap(plus);
      expect(shares, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
      semantics.dispose();
    },
  );

  testWidgets('the own note alone follows pinch, spread and its deadline', (
    tester,
  ) async {
    var now = start;
    var reloads = 0;
    await tester.pumpWidget(
      wrap(
        InnerCircleInteractiveSurface(
          userPeerId: 'self',
          onSelfAvatarTap: () {},
          items: items.take(2).toList(),
          onFriendTap: (_) {},
          onGroupTap: (_) {},
          thoughtsByPeerId: {
            'self': note(
              'mine',
              text: 'My own thought',
              read: true,
              lifetime: const Duration(minutes: 1),
            ),
          },
          nowProvider: () => now,
          onThoughtsExpired: () => reloads++,
        ),
      ),
    );
    expect(find.text('My own thought'), findsOneWidget);
    final center = tester.getCenter(
      find.byKey(const ValueKey('orbit-thought-pinch-surface')),
    );
    Future<void> twoFingers(double startGap, double travel, int pointer) async {
      final a = await tester.startGesture(
        center - Offset(startGap, 0),
        pointer: pointer,
      );
      final b = await tester.startGesture(
        center + Offset(startGap, 0),
        pointer: pointer + 1,
      );
      await a.moveBy(Offset(travel, 0));
      await b.moveBy(Offset(-travel, 0));
      await tester.pump();
      await a.up();
      await b.up();
    }

    await twoFingers(50, 25, 1);
    expect(find.text('My own thought'), findsNothing);
    await twoFingers(30, -25, 3);
    expect(find.text('My own thought'), findsOneWidget);
    now = start.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    expect(find.text('My own thought'), findsNothing);
    expect(reloads, 1);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'thumbs pinch anywhere on a phone screen, not only on the orbit',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        wrap(
          InnerCircleInteractiveSurface(
            userPeerId: 'self',
            items: items.take(2).toList(),
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            thoughtsByPeerId: {'friend-0': note('thumbs', text: 'Thumb note')},
            nowProvider: () => start,
          ),
        ),
      );
      expect(find.text('Thumb note'), findsOneWidget);
      Future<void> thumbs(Offset left, Offset right, double travel) async {
        final a = await tester.startGesture(left, pointer: 11);
        final b = await tester.startGesture(right, pointer: 12);
        for (var i = 0; i < 6; i++) {
          await a.moveBy(Offset(travel / 6, 0));
          await b.moveBy(Offset(-travel / 6, 0));
          await tester.pump();
        }
        await a.up();
        await b.up();
        await tester.pump();
      }

      await thumbs(const Offset(20, 700), const Offset(370, 700), 120);
      expect(find.text('Thumb note'), findsNothing);
      await thumbs(const Offset(140, 760), const Offset(250, 760), -110);
      expect(find.text('Thumb note'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets(
    'deadline removes note without store/sweep changes and reloads host',
    (tester) async {
      var now = start;
      var reloads = 0;
      final unchangedNotes = {
        'friend-0': note('expires', lifetime: const Duration(seconds: 1)),
      };
      await tester.pumpWidget(
        wrap(
          InnerCircleInteractiveSurface(
            userPeerId: 'self',
            items: items.take(2).toList(),
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            thoughtsByPeerId: unchangedNotes,
            nowProvider: () => now,
            onThoughtsExpired: () => reloads++,
          ),
        ),
      );
      expect(find.byType(OrbitThoughtNoteBubble), findsOneWidget);
      now = start.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      expect(
        unchangedNotes,
        hasLength(1),
        reason: 'sweep never removed the row',
      );
      expect(reloads, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'badge first hides notes, then expands arcs; pinch/spread are session choices',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          InnerCircleInteractiveSurface(
            userPeerId: 'self',
            onSelfAvatarTap: () {},
            items: items,
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            thoughtsByPeerId: {'friend-0': note('live')},
            nowProvider: () => start,
          ),
        ),
      );
      OrbitalVisualization viz() =>
          tester.widget(find.byType(OrbitalVisualization));
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      expect(viz().overflowExpanded, isFalse);
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(viz().overflowExpanded, isTrue);
      final rect = tester.getRect(
        find.byKey(const ValueKey('orbit-thought-pinch-surface')),
      );
      final center = rect.center;
      final left = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final right = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await left.moveBy(const Offset(-25, 0));
      await right.moveBy(const Offset(25, 0));
      await tester.pump();
      await left.up();
      await right.up();
      expect(find.byType(OrbitThoughtNoteBubble), findsOneWidget);
      expect(viz().overflowExpanded, isFalse);
      final a = await tester.startGesture(
        center - const Offset(50, 0),
        pointer: 3,
      );
      final b = await tester.startGesture(
        center + const Offset(50, 0),
        pointer: 4,
      );
      await a.moveBy(const Offset(25, 0));
      await b.moveBy(const Offset(-25, 0));
      await tester.pump();
      await a.up();
      await b.up();
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      expect(viz().thoughtVisibility, 0);
      final layout = computeOrbitLayout(
        memberCount: items.length,
        geometry: viz().geometry,
      );
      final self = tester.getCenter(
        find.byKey(const ValueKey('orbit-center-self-avatar')),
      );
      for (final seat in layout.seats.where(
        (seat) => seat.kind != OrbitSeatKind.arc,
      )) {
        expect(
          (tester.getCenter(find.byKey(ValueKey('orbit-node-${seat.index}'))) -
                  self -
                  Offset(seat.dx, seat.dy))
              .distance,
          lessThan(0.01),
        );
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets(
    'size controls are blocked while notes are out and work after hiding',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          InnerCircleInteractiveSurface(
            userPeerId: 'self',
            items: items.take(2).toList(),
            onFriendTap: (_) {},
            onGroupTap: (_) {},
            thoughtsByPeerId: {'friend-0': note('live')},
            nowProvider: () => start,
          ),
        ),
      );
      final background = find.byKey(
        const ValueKey('orbit-inner-circle-background'),
      );
      final empty = tester.getRect(background).topLeft + const Offset(12, 12);
      await tester.longPressAt(empty);
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
      final center = tester.getCenter(
        find.byKey(const ValueKey('orbit-thought-pinch-surface')),
      );
      final a = await tester.startGesture(
        center - const Offset(50, 0),
        pointer: 1,
      );
      final b = await tester.startGesture(
        center + const Offset(50, 0),
        pointer: 2,
      );
      await a.moveBy(const Offset(25, 0));
      await b.moveBy(const Offset(-25, 0));
      await a.up();
      await b.up();
      await tester.pump();
      await tester.longPressAt(empty);
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('a press held across expiry cannot open a stale thought', (
    tester,
  ) async {
    var now = start;
    final opened = <String>[];
    await tester.pumpWidget(
      wrap(
        OrbitalVisualization(
          userPeerId: 'self',
          items: items.take(1).toList(),
          thoughtsByPeerId: {
            'friend-0': note('held', lifetime: const Duration(seconds: 1)),
          },
          nowProvider: () => now,
          onThoughtTap: opened.add,
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(OrbitThoughtNoteBubble)),
    );
    now = start.add(const Duration(seconds: 1));
    await gesture.up();
    expect(opened, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'thought arrival during size editing keeps notes hidden and preserves the edit',
    (tester) async {
      Widget scene(Map<String, OrbitThoughtNote> thoughts) => wrap(
        InnerCircleInteractiveSurface(
          userPeerId: 'self',
          items: items.take(2).toList(),
          onFriendTap: (_) {},
          onGroupTap: (_) {},
          thoughtsByPeerId: thoughts,
          nowProvider: () => start,
        ),
      );
      OrbitalVisualization viz() =>
          tester.widget(find.byType(OrbitalVisualization));
      await tester.pumpWidget(scene(const {}));
      final background = find.byKey(
        const ValueKey('orbit-inner-circle-background'),
      );
      await tester.longPressAt(
        tester.getRect(background).topLeft + const Offset(12, 12),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-handle-avatarScale')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-decrease')));
      await tester.pump();
      final editedGeometry = viz().geometry;
      expect(editedGeometry.avatarScale, closeTo(1.2, 1e-9));

      await tester.pumpWidget(scene({'friend-0': note('arrived-during-edit')}));
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('orbit-edit-step-decrease')),
        findsOneWidget,
      );
      expect(viz().geometry, editedGeometry);
      expect(viz().thoughtVisibility, 0);

      // The same armed control remains usable; arrival did not end or reset it.
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-decrease')));
      await tester.pump();
      expect(viz().geometry.avatarScale, closeTo(1.0, 1e-9));
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  Widget arcSurface(Map<String, OrbitThoughtNote> notes) => wrap(
    InnerCircleInteractiveSurface(
      userPeerId: 'self',
      onSelfAvatarTap: () {},
      items: items,
      onFriendTap: (_) {},
      onGroupTap: (_) {},
      thoughtsByPeerId: notes,
      nowProvider: () => start,
    ),
  );

  Future<void> pinchIn(WidgetTester tester) async {
    final center = tester.getCenter(
      find.byKey(const ValueKey('orbit-thought-pinch-surface')),
    );
    final a = await tester.startGesture(
      center - const Offset(50, 0),
      pointer: 11,
    );
    final b = await tester.startGesture(
      center + const Offset(50, 0),
      pointer: 12,
    );
    await a.moveBy(const Offset(25, 0));
    await b.moveBy(const Offset(-25, 0));
    await tester.pump();
    await a.up();
    await b.up();
    await tester.pump();
  }

  testWidgets('notes put away by the badge come back when the arcs close', (
    tester,
  ) async {
    await tester.pumpWidget(arcSurface({'friend-0': note('live')}));
    OrbitalVisualization viz() =>
        tester.widget(find.byType(OrbitalVisualization));
    for (final expanded in [false, true, false]) {
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(viz().overflowExpanded, expanded);
    }
    expect(
      find.byType(OrbitThoughtNoteBubble),
      findsOneWidget,
      reason: 'closing the arcs restores notes the badge put away',
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'notes put away by a pinch stay away for a new thought and the arcs',
    (tester) async {
      await tester.pumpWidget(arcSurface({'friend-0': note('live')}));
      await pinchIn(tester);
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      await tester.pumpWidget(arcSurface({'friend-0': note('newer')}));
      await tester.pump();
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(find.byType(OrbitThoughtNoteBubble), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'a first thought arriving under open arcs waits for them to close',
    (tester) async {
      await tester.pumpWidget(arcSurface(const {}));
      OrbitalVisualization viz() =>
          tester.widget(find.byType(OrbitalVisualization));
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(viz().overflowExpanded, isTrue);
      await tester.pumpWidget(arcSurface({'friend-0': note('first')}));
      await tester.pump();
      expect(
        find.byType(OrbitThoughtNoteBubble),
        findsNothing,
        reason: 'notes must not cover the open arc faces',
      );
      expect(viz().overflowExpanded, isTrue);
      await tester.tap(find.byType(OverflowBadge));
      await tester.pump();
      expect(viz().overflowExpanded, isFalse);
      expect(find.byType(OrbitThoughtNoteBubble), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
