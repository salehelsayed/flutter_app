import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/helpers/readability_test_helpers.dart';

OrbitFriend _makeFriend(int i, {int unreadCount = 0}) {
  return OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$i-abcdef1234',
      publicKey: 'pk-$i',
      rendezvous: '/ip4/127.0.0.1/tcp/400$i',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2024-01-01T00:00:00Z',
    ),
    messageCount: i,
    unreadCount: unreadCount,
  );
}

// 197 — the visualization renders the merged inner-circle union. These helpers
// wrap the friend/group domain models into the `OrbitItem` seats the widget
// now takes (friends were `List<OrbitFriend>` before 197).
List<OrbitItem> _items(List<OrbitFriend> friends) =>
    friends.map<OrbitItem>(OrbitFriendItem.new).toList();

OrbitGroup _makeGroup(
  int i, {
  String? name,
  String? avatarPath,
  int unreadCount = 0,
}) {
  return OrbitGroup(
    group: GroupModel(
      id: 'g-$i',
      name: name ?? 'Group $i',
      type: GroupType.chat,
      topicName: 'topic-g-$i',
      createdBy: 'creator',
      myRole: GroupRole.admin,
      createdAt: DateTime.utc(2026, 1, 1),
      avatarPath: avatarPath,
    ),
    unreadCount: unreadCount,
    lastActivityTimestamp: DateTime.utc(2026, 7, 2, 12 - i),
  );
}

void main() {
  Widget wrap(Widget child, {BackgroundReadableColors? readableColors}) =>
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          extensions: [readableColors ?? BackgroundReadableColors.dark],
        ),
        home: Scaffold(body: child),
      );

  // OrbitalAvatar uses Future.delayed for staggered animations,
  // and OverflowBadge uses Future.delayed(1000ms). We must pump
  // past all timers to avoid "pending timer" test failures.
  Future<void> pumpPastAnimations(WidgetTester tester) async {
    await tester.pumpAndSettle();
  }

  // 194 — bounded pumps for LIT-node tests. A lit node hosts the messenger-orbit
  // indicator whose ~9s repeat rotation NEVER settles, so pumpAndSettle would
  // hang. 1600ms drains the entrance staggers + the 1000ms overflow timer while
  // leaving the infinite ticker to be torn down with the tree.
  Future<void> pumpBounded(WidgetTester tester, {int count = 16}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Wrap that can override locale (RTL) and the reduce-motion MediaQuery flag.
  Widget wrapMq(
    Widget child, {
    BackgroundReadableColors? readableColors,
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
  }) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(
      extensions: [readableColors ?? BackgroundReadableColors.dark],
    ),
    home: Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );

  Finder ringPainterFinder() => find.byWidgetPredicate(
    (w) => w is CustomPaint && w.painter is UnreadOrbitRingPainter,
  );

  List<AnimationController> indicatorControllers(WidgetTester tester) => tester
      .widgetList<AnimatedBuilder>(
        find.descendant(
          of: find.byType(UnreadOrbitIndicator),
          matching: find.byType(AnimatedBuilder),
        ),
      )
      .map((ab) => ab.listenable)
      .whereType<AnimationController>()
      .toList();

  group('OrbitalVisualization', () {
    testWidgets('renders "YOUR INNER CIRCLE" text', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: const <OrbitItem>[])),
      );
      await pumpPastAnimations(tester);
      expect(find.text('YOUR INNER CIRCLE'), findsOneWidget);
    });

    testWidgets('renders center UserAvatar', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: const <OrbitItem>[])),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(UserAvatar), findsOneWidget);
    });

    testWidgets('renders OrbitalAvatars for friends in ring 1', (tester) async {
      final friends = List.generate(3, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OrbitalAvatar), findsNWidgets(3));
    });

    testWidgets('renders OrbitalAvatars for friends in ring 2', (tester) async {
      final friends = List.generate(8, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
        ),
      );
      await pumpPastAnimations(tester);
      // 5 in ring 1 + 3 in ring 2
      expect(find.byType(OrbitalAvatar), findsNWidgets(8));
    });

    testWidgets('shows OverflowBadge when more than 13 friends', (
      tester,
    ) async {
      final friends = List.generate(15, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OverflowBadge), findsOneWidget);
    });

    testWidgets('hides OverflowBadge when 13 or fewer friends', (tester) async {
      final friends = List.generate(10, (i) => _makeFriend(i));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
        ),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(OverflowBadge), findsNothing);
    });

    testWidgets('renders CustomPaint for orbital rings', (tester) async {
      await tester.pumpWidget(
        wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: const <OrbitItem>[])),
      );
      await pumpPastAnimations(tester);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('uses readable heading and overflow text on daylight', (
      tester,
    ) async {
      const colors = BackgroundReadableColors.representativeLight;
      final friends = List.generate(15, (i) => _makeFriend(i));

      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
          readableColors: colors,
        ),
      );
      await pumpPastAnimations(tester);

      final heading = tester.widget<Text>(find.text('YOUR INNER CIRCLE'));
      final overflow = tester.widget<Text>(find.text('+2'));

      expect(heading.style!.color, colors.textMuted);
      expect(overflow.style!.color, colors.textMuted);
      expectTextContrast(heading.style!.color!, colors.surfaceBase);
      expectTextContrast(overflow.style!.color!, colors.surfaceSubtle);
    });

    testWidgets('inner-ring avatar tap reports the exact friend', (
      tester,
    ) async {
      final friends = List.generate(3, (i) => _makeFriend(i));
      OrbitFriend? tappedFriend;

      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(
            userPeerId: 'my-peer-id-123',
            items: _items(friends),
            onFriendTap: (friend) => tappedFriend = friend,
          ),
        ),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.bySemanticsLabel('Open chat with friend1'));

      expect(tappedFriend?.peerId, 'peer-1-abcdef1234');
    });

    testWidgets('outer-ring avatar tap reports the exact friend', (
      tester,
    ) async {
      final friends = List.generate(8, (i) => _makeFriend(i));
      OrbitFriend? tappedFriend;

      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(
            userPeerId: 'my-peer-id-123',
            items: _items(friends),
            onFriendTap: (friend) => tappedFriend = friend,
          ),
        ),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.bySemanticsLabel('Open chat with friend6'));

      expect(tappedFriend?.peerId, 'peer-6-abcdef1234');
    });

    testWidgets('center avatar and overflow badge do not open chat', (
      tester,
    ) async {
      final friends = List.generate(15, (i) => _makeFriend(i));
      var tapCount = 0;

      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(
            userPeerId: 'my-peer-id-123',
            items: _items(friends),
            onFriendTap: (_) => tapCount++,
          ),
        ),
      );
      await pumpPastAnimations(tester);

      await tester.tap(find.byType(UserAvatar).first);
      await tester.tap(find.byType(OverflowBadge), warnIfMissed: false);

      expect(tapCount, 0);
    });

    // ── 194: per-node unread "messenger orbit" indicator ───────────────────

    testWidgets(
      'TC-194-01/34: lit friend shows unread orbit; unlit nodes and center '
      'self do not',
      (tester) async {
        final friends = [
          _makeFriend(0),
          _makeFriend(1, unreadCount: 2),
          _makeFriend(2),
        ];
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
          ),
        );
        await pumpBounded(tester);

        // Exactly one lit node; the center self (a plain UserAvatar) and the
        // two unlit nodes render no indicator.
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'TC-194-06: indicator renders on ring-1 (38px) and ring-2 (30px) nodes '
      'scaled to the node diameter',
      (tester) async {
        final friends = List.generate(
          7,
          (i) => _makeFriend(i, unreadCount: (i == 1 || i == 6) ? 1 : 0),
        );
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
          ),
        );
        await pumpBounded(tester);

        expect(find.byType(UnreadOrbitIndicator), findsNWidgets(2));
        final diameters = tester
            .widgetList<UnreadOrbitIndicator>(find.byType(UnreadOrbitIndicator))
            .map((w) => w.diameter)
            .toSet();
        expect(diameters, {38.0, 30.0});
      },
    );

    testWidgets('TC-194-07: all 13 visible nodes lit renders without exceptions', (
      tester,
    ) async {
      final friends = List.generate(13, (i) => _makeFriend(i, unreadCount: 1));
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
        ),
      );
      await pumpBounded(tester);

      expect(find.byType(UnreadOrbitIndicator), findsNWidgets(13));
      expect(tester.takeException(), isNull);
    });

    testWidgets('TC-194-26: lit node keeps 48px tap target and opens chat', (
      tester,
    ) async {
      final friends = [_makeFriend(0, unreadCount: 3)];
      OrbitFriend? tapped;
      await tester.pumpWidget(
        wrap(
          OrbitalVisualization(
            userPeerId: 'my-peer-id-123',
            items: _items(friends),
            onFriendTap: (f) => tapped = f,
          ),
        ),
      );
      await pumpBounded(tester);

      final tapTarget = find.byType(GestureDetector);
      expect(tester.getSize(tapTarget), const Size(48, 48));
      final rect = tester.getRect(tapTarget);
      await tester.tapAt(rect.center + const Offset(22, 0));
      expect(tapped?.peerId, 'peer-0-abcdef1234');
    });

    testWidgets(
      'TC-194-27: lit node semantics announces unread; unlit label unchanged',
      (tester) async {
        final handle = tester.ensureSemantics();
        final friends = [_makeFriend(0, unreadCount: 2), _makeFriend(1)];
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(
              userPeerId: 'my-peer-id-123',
              items: _items(friends),
              onFriendTap: (_) {},
            ),
          ),
        );
        await pumpBounded(tester);

        expect(
          find.bySemanticsLabel('Open chat with friend0, 2 unread messages'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('Open chat with friend1'),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'TC-194-29: RTL (ar) renders lit nodes at physical positions without '
      'exception',
      (tester) async {
        final friends = [_makeFriend(0, unreadCount: 1), _makeFriend(1)];
        await tester.pumpWidget(
          wrapMq(
            OrbitalVisualization(
              userPeerId: 'my-peer-id-123',
              items: _items(friends),
              onFriendTap: (_) {},
            ),
            locale: const Locale('ar'),
          ),
        );
        await pumpBounded(tester);

        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TC-194-30: daylight readable palette keeps the indicator present and '
      'green',
      (tester) async {
        const colors = BackgroundReadableColors.representativeLight;
        final friends = [_makeFriend(0, unreadCount: 2), _makeFriend(1)];
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
            readableColors: colors,
          ),
        );
        await pumpBounded(tester);

        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        final painter =
            tester.widget<CustomPaint>(ringPainterFinder()).painter
                as UnreadOrbitRingPainter;
        // Deliberately theme-independent: green unread accent on light surface.
        expect(painter.accent, UnreadOrbitIndicator.kUnreadAccent);
      },
    );

    testWidgets(
      'TC-194-31: 16 friends: overflow badge unchanged; hidden lit friend '
      'causes no error',
      (tester) async {
        final friends = List.generate(
          16,
          (i) => _makeFriend(i, unreadCount: (i == 0 || i == 14) ? 2 : 0),
        );
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
          ),
        );
        await pumpBounded(tester);

        expect(find.byType(OverflowBadge), findsOneWidget);
        expect(find.text('+3'), findsOneWidget);
        // Only the visible lit friend (index 0) renders an indicator; the lit
        // friend hidden beyond 13 (index 14) neither renders nor crashes.
        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'TC-194-24: motion seam - reduce-motion MediaQuery freezes satellite '
      'spin at the visualization level',
      (tester) async {
        final friends = [_makeFriend(0, unreadCount: 2)];
        await tester.pumpWidget(
          wrapMq(
            OrbitalVisualization(userPeerId: 'my-peer-id-123', items: _items(friends)),
            disableAnimations: true,
          ),
        );
        await pumpBounded(tester);

        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
        final controllers = indicatorControllers(tester);
        expect(controllers, isNotEmpty);
        expect(controllers.every((c) => !c.isAnimating), isTrue);
      },
    );

    // ── 197: group chats interleaved on the inner-circle rings ──────────────

    testWidgets(
      'TC-197-03: renders a group node with GroupAvatar on the ring',
      (tester) async {
        final items = <OrbitItem>[
          OrbitFriendItem(_makeFriend(0)),
          OrbitFriendItem(_makeFriend(1)),
          OrbitGroupItem(
            _makeGroup(2, name: 'Alpha Group', avatarPath: 'group/g-2.jpg'),
          ),
        ];
        await tester.pumpWidget(
          wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: items)),
        );
        await pumpPastAnimations(tester);

        // The group seats a GroupAvatar node while the two friend nodes stay.
        expect(find.byType(GroupAvatar), findsOneWidget);
        expect(find.byType(OrbitalAvatar), findsNWidgets(3));
      },
    );

    testWidgets(
      'TC-197-04: group node with unread overlays UnreadOrbitIndicator',
      (tester) async {
        final items = <OrbitItem>[
          OrbitGroupItem(_makeGroup(1, name: 'Alpha Group', unreadCount: 3)),
        ];
        await tester.pumpWidget(
          wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: items)),
        );
        await pumpBounded(tester);

        expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      },
    );

    testWidgets(
      'TC-197-04b: a zero-unread group renders no UnreadOrbitIndicator',
      (tester) async {
        final items = <OrbitItem>[
          OrbitGroupItem(_makeGroup(1, name: 'Alpha Group', unreadCount: 0)),
        ];
        await tester.pumpWidget(
          wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: items)),
        );
        await pumpPastAnimations(tester);

        expect(find.byType(UnreadOrbitIndicator), findsNothing);
      },
    );

    testWidgets(
      'TC-197-05: group node falls back to initials when avatarPath is null',
      (tester) async {
        final items = <OrbitItem>[
          OrbitGroupItem(_makeGroup(1, name: 'Alpha Group', avatarPath: null)),
        ];
        await tester.pumpWidget(
          wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: items)),
        );
        await pumpPastAnimations(tester);

        expect(find.byType(GroupAvatar), findsOneWidget);
        // Initials fallback ("Alpha Group" -> "AG"), not an Image.file.
        expect(find.text('AG'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(GroupAvatar),
            matching: find.byType(Image),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'TC-197-06: tapping a group node invokes onGroupTap with that group',
      (tester) async {
        final items = <OrbitItem>[
          OrbitFriendItem(_makeFriend(0)),
          OrbitGroupItem(_makeGroup(1, name: 'Alpha Group')),
        ];
        OrbitGroup? tappedGroup;
        OrbitFriend? tappedFriend;
        await tester.pumpWidget(
          wrap(
            OrbitalVisualization(
              userPeerId: 'my-peer-id-123',
              items: items,
              onFriendTap: (f) => tappedFriend = f,
              onGroupTap: (g) => tappedGroup = g,
            ),
          ),
        );
        await pumpPastAnimations(tester);

        // The group node's own opaque tap target routes to onGroupTap.
        final groupTapTarget = find
            .ancestor(
              of: find.byType(GroupAvatar),
              matching: find.byType(GestureDetector),
            )
            .first;
        await tester.tap(groupTapTarget);
        expect(tappedGroup?.groupId, 'g-1');
        expect(tappedFriend, isNull);

        // The friend node still routes to onFriendTap (unbroken).
        await tester.tap(find.bySemanticsLabel('Open chat with friend0'));
        expect(tappedFriend?.peerId, 'peer-0-abcdef1234');
      },
    );

    testWidgets(
      'TC-197-07: overflow badge counts friends and groups combined',
      (tester) async {
        final items = <OrbitItem>[
          for (var i = 0; i < 12; i++) OrbitFriendItem(_makeFriend(i)),
          for (var i = 0; i < 3; i++)
            OrbitGroupItem(_makeGroup(100 + i, name: 'Group $i')),
        ];
        await tester.pumpWidget(
          wrap(OrbitalVisualization(userPeerId: 'my-peer-id-123', items: items)),
        );
        await pumpPastAnimations(tester);

        // 15 total -> exactly 13 seated, overflow badge shows +2.
        expect(find.byType(OrbitalAvatar), findsNWidgets(13));
        expect(find.byType(OverflowBadge), findsOneWidget);
        expect(find.text('+2'), findsOneWidget);
      },
    );
  });
}
