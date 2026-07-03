import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_ring_painter.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

OrbitFriend _makeFriend(int i, {int unreadCount = 0}) => OrbitFriend(
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

OrbitGroup _makeGroup(int i, {String? name, int unreadCount = 0}) => OrbitGroup(
      group: GroupModel(
        id: 'g-$i',
        name: name ?? 'Group $i',
        type: GroupType.chat,
        topicName: 'topic-g-$i',
        createdBy: 'creator',
        myRole: GroupRole.admin,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      unreadCount: unreadCount,
      lastActivityTimestamp: DateTime.utc(2026, 7, 2, 12 - i),
    );

List<OrbitItem> _friends(int n) =>
    [for (var i = 0; i < n; i++) OrbitFriendItem(_makeFriend(i))];

void main() {
  Widget wrap(
    Widget child, {
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [BackgroundReadableColors.dark]),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(disableAnimations: disableAnimations),
            child: Scaffold(body: SingleChildScrollView(child: child)),
          ),
        ),
      );

  Future<void> pumpBounded(WidgetTester tester, {int count = 16}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  // Bounded settle: drains the badge's 1000ms + entrance Future.delayed timers
  // (which do NOT schedule frames, so pumpAndSettle would return early and leak
  // them) without hanging on any infinite lit-node rotation.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  // A host that flips overflowExpanded when the badge is tapped (the parent's
  // job in production; here it lets the widget-tier tests toggle via the badge).
  Widget expandable(
    List<OrbitItem> items, {
    OrbitGeometryPrefs geometry = OrbitGeometryPrefs.defaults,
    bool startExpanded = false,
    bool labelsVisible = false,
    Locale locale = const Locale('en'),
    bool disableAnimations = false,
    ValueChanged<OrbitGroup>? onGroupTap,
  }) {
    var expanded = startExpanded;
    return wrap(
      StatefulBuilder(
        builder: (context, setState) => OrbitalVisualization(
          userPeerId: 'my-peer-id-123',
          items: items,
          onFriendTap: (_) {},
          onGroupTap: onGroupTap ?? (_) {},
          geometry: geometry,
          overflowExpanded: expanded,
          labelsVisible: labelsVisible,
          onBadgeTap: () => setState(() => expanded = !expanded),
        ),
      ),
      locale: locale,
      disableAnimations: disableAnimations,
    );
  }

  OrbitalRingPainter painterOf(WidgetTester tester) {
    final cp = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
          (c) => c.painter is OrbitalRingPainter,
        );
    return cp.painter! as OrbitalRingPainter;
  }

  Offset centerOf(WidgetTester tester) =>
      tester.getRect(find.byType(UserAvatar).first).center;

  Offset nodeOffset(WidgetTester tester, String label) =>
      tester.getRect(find.bySemanticsLabel(label)).center - centerOf(tester);

  group('OrbitalVisualization arcs (198 F5)', () {
    // TC-198-01
    testWidgets('badge tap seats item 14 on arc 1 + chevron', (tester) async {
      await tester.pumpWidget(expandable(_friends(14)));
      await settle(tester);
      // Collapsed: 13 ring nodes, overflow member (friend13) not rendered.
      expect(find.byType(OrbitalAvatar), findsNWidgets(13));
      expect(find.bySemanticsLabel('Open chat with friend13'), findsNothing);
      expect(find.text('⌄'), findsNothing);

      await tester.tap(find.byType(OverflowBadge));
      await settle(tester);
      // Expanded: the 14th member is seated (on arc 1) and the chevron shows.
      expect(find.byType(OrbitalAvatar), findsNWidgets(14));
      expect(find.bySemanticsLabel('Open chat with friend13'), findsOneWidget);
      expect(find.text('⌄'), findsOneWidget);
    });

    // TC-198-02
    testWidgets('thirteen items: no badge, no arcs', (tester) async {
      await tester.pumpWidget(expandable(_friends(13)));
      await settle(tester);
      expect(find.byType(OverflowBadge), findsNothing);
      expect(find.byType(OrbitalAvatar), findsNWidgets(13));
      expect(painterOf(tester).arcs, isEmpty);
    });

    // TC-198-05
    testWidgets('collapse round-trip twice', (tester) async {
      await tester.pumpWidget(expandable(_friends(20)));
      await settle(tester);
      for (var i = 0; i < 2; i++) {
        expect(find.byType(OrbitalAvatar), findsNWidgets(13));
        await tester.tap(find.byType(OverflowBadge));
        await settle(tester);
        expect(find.byType(OrbitalAvatar), findsNWidgets(20));
        await tester.tap(find.byType(OverflowBadge));
        await settle(tester);
      }
      expect(find.byType(OrbitalAvatar), findsNWidgets(13));
    });

    // TC-198-06 render half
    testWidgets('24 items: 11 arc nodes once each, 2 painted arcs', (tester) async {
      await tester.pumpWidget(expandable(_friends(24), startExpanded: true));
      await settle(tester);
      expect(find.byType(OrbitalAvatar), findsNWidgets(24)); // 13 ring + 11 arc
      final arcs = painterOf(tester).arcs;
      expect(arcs.map((a) => a.arcIndex).toSet(), {0, 1});
    });

    // TC-198-09
    testWidgets('expansion under disableAnimations is instant', (tester) async {
      await tester.pumpWidget(
        expandable(_friends(16), startExpanded: true, disableAnimations: true),
      );
      await tester.pump(); // no long delay
      // The overflow arc node is already fully opaque (no entrance frames).
      final opacity = tester.widget<Opacity>(find
          .descendant(
            of: find.ancestor(
              of: find.bySemanticsLabel('Open chat with friend13'),
              matching: find.byType(OrbitalAvatar),
            ),
            matching: find.byType(Opacity),
          )
          .first);
      expect(opacity.opacity, 1.0);
      await settle(tester); // drain the pre-198 ring entrance timers
    });

    // TC-198-10
    testWidgets('overflow group node renders GroupAvatar and fires group tap',
        (tester) async {
      OrbitGroup? tapped;
      final items = <OrbitItem>[
        ..._friends(13),
        OrbitGroupItem(_makeGroup(0, name: 'Overflow Crew')),
      ];
      await tester.pumpWidget(
        expandable(items, startExpanded: true, onGroupTap: (g) => tapped = g),
      );
      await settle(tester);
      expect(find.byType(GroupAvatar), findsOneWidget);
      await tester.tap(find.bySemanticsLabel(RegExp('Overflow Crew')));
      await tester.pump();
      expect(tapped?.name, 'Overflow Crew');
    });

    // TC-198-11 render half
    testWidgets('unread indicator renders on an arc node', (tester) async {
      final items = <OrbitItem>[
        ..._friends(13),
        OrbitFriendItem(_makeFriend(99, unreadCount: 4)),
      ];
      await tester.pumpWidget(expandable(items, startExpanded: true));
      await pumpBounded(tester);
      expect(find.byType(UnreadOrbitIndicator), findsWidgets);
      expect(
        find.bySemanticsLabel(RegExp('friend99, 4 unread')),
        findsOneWidget,
      );
    });

    // TC-198-12
    testWidgets('every arc hit area ≥44px', (tester) async {
      await tester.pumpWidget(expandable(_friends(24), startExpanded: true));
      await settle(tester);
      // Overflow members friend13..friend23 are arc nodes.
      for (final i in [13, 18, 23]) {
        final gd = find.descendant(
          of: find.ancestor(
            of: find.bySemanticsLabel('Open chat with friend$i'),
            matching: find.byType(OrbitalAvatar),
          ),
          matching: find.byType(GestureDetector),
        );
        final size = tester.getSize(gd.first);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
    });

    // TC-198-13 render half
    testWidgets('seat 14 sits exactly where the layout places it', (tester) async {
      await tester.pumpWidget(expandable(_friends(24), startExpanded: true));
      await settle(tester);
      final seat13 = computeOrbitLayout(
        memberCount: 24,
        geometry: OrbitGeometryPrefs.defaults,
      ).seats[13];
      final off = nodeOffset(tester, 'Open chat with friend13');
      expect(off.dx, closeTo(seat13.dx, 1.0));
      expect(off.dy, closeTo(seat13.dy, 1.0));
    });

    // TC-198-28
    testWidgets('av 0.6 / 1.4 scale arc avatars; 44px floors hold', (tester) async {
      for (final (av, expected) in [(0.6, 20.4), (1.4, 47.6)]) {
        await tester.pumpWidget(expandable(
          _friends(16),
          geometry: OrbitGeometryPrefs.defaults.copyWith(avatarScale: av),
          startExpanded: true,
        ));
        await settle(tester);
        final node = tester.widget<OrbitalAvatar>(find.ancestor(
          of: find.bySemanticsLabel('Open chat with friend13'),
          matching: find.byType(OrbitalAvatar),
        ));
        expect(node.size, closeTo(expected, 0.01));
        final gd = find.descendant(
          of: find.ancestor(
            of: find.bySemanticsLabel('Open chat with friend13'),
            matching: find.byType(OrbitalAvatar),
          ),
          matching: find.byType(GestureDetector),
        );
        expect(tester.getSize(gd.first).width, greaterThanOrEqualTo(44));
      }
    });

    // TC-198-29
    testWidgets('sp 1.5 scales node seats AND painted ring/arc paths',
        (tester) async {
      await tester.pumpWidget(expandable(
        _friends(16),
        geometry: OrbitGeometryPrefs.defaults.copyWith(spacingScale: 1.5),
        startExpanded: true,
      ));
      await settle(tester);
      final painter = painterOf(tester);
      expect(painter.ring1Radius, closeTo(62 * 1.5, 1e-6));
      expect(painter.ring2Radius, closeTo(108 * 1.5, 1e-6));
      // arc 0 radius = (108 + 46) * 1.5 = 231.
      expect(painter.arcs.first.radius, closeTo(231, 1e-6));
      // A ring node also sits at the scaled radius.
      final off = nodeOffset(tester, 'Open chat with friend0');
      expect(off.distance, closeTo(62 * 1.5, 1.0));
    });

    // TC-198-58
    testWidgets('arc fill mirrors under RTL', (tester) async {
      await tester.pumpWidget(expandable(
        _friends(24),
        startExpanded: true,
        locale: const Locale('ar'),
      ));
      await settle(tester);
      final seat13 = computeOrbitLayout(
        memberCount: 24,
        geometry: OrbitGeometryPrefs.defaults,
        mirrored: true,
      ).seats[13];
      final off = nodeOffset(tester, 'Open chat with friend13');
      expect(off.dx, closeTo(seat13.dx, 1.0)); // mirrored dx
      expect(off.dy, closeTo(seat13.dy, 1.0));
    });

    // TC-198-61
    testWidgets('arc friend nodes reuse ring semantic labels', (tester) async {
      await tester.pumpWidget(expandable(_friends(24), startExpanded: true));
      await settle(tester);
      // Same "Open chat with …" species as ring nodes.
      expect(find.bySemanticsLabel('Open chat with friend0'), findsOneWidget);
      expect(find.bySemanticsLabel('Open chat with friend20'), findsOneWidget);
    });

    // TC-198-62
    testWidgets('knobs=1.0, ≤13 items: geometry identical to HEAD (no badge)',
        (tester) async {
      await tester.pumpWidget(expandable(_friends(13)));
      await settle(tester);
      expect(find.byType(OverflowBadge), findsNothing);
      // Ring 1 node at 62px, ring 2 node at 108px — the pre-198 consts.
      expect(nodeOffset(tester, 'Open chat with friend0').distance,
          closeTo(62, 1.0));
      expect(nodeOffset(tester, 'Open chat with friend5').distance,
          closeTo(108, 1.0));
    });

    // TC-198-53 per-node render half
    testWidgets('labelsVisible renders a name under every node', (tester) async {
      await tester.pumpWidget(expandable(_friends(13)));
      await settle(tester);
      expect(find.text('friend0'), findsNothing);

      await tester.pumpWidget(expandable(_friends(13), labelsVisible: true));
      await settle(tester);
      expect(find.text('friend0'), findsOneWidget);
      expect(find.text('friend7'), findsOneWidget);
    });

    // Entrance must relinquish opacity (not pin nodes mid-entrance).
    testWidgets('after entrance an arc node is fully opaque', (tester) async {
      await tester.pumpWidget(expandable(_friends(16), startExpanded: true));
      await settle(tester);
      final opacity = tester.widget<Opacity>(find
          .descendant(
            of: find.ancestor(
              of: find.bySemanticsLabel('Open chat with friend13'),
              matching: find.byType(OrbitalAvatar),
            ),
            matching: find.byType(Opacity),
          )
          .first);
      expect(opacity.opacity, 1.0);
    });
  });
}
