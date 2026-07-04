import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_geometry_prefs.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/orbit_arc_layout.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_ring_painter.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/l10n/app_localizations_en.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';

/// 198 F6 — the interactive Inner-Circle surface (Sculpt & Summon) driven
/// through its real production widget: edit session, geometry handles, find,
/// labels, persistence, and the reset seam.
class _SpyStore extends FakeSecureKeyStore {
  int writes = 0;
  int deletes = 0;
  @override
  Future<void> write(String key, String value) {
    writes++;
    return super.write(key, value);
  }

  @override
  Future<void> delete(String key) {
    deletes++;
    return super.delete(key);
  }
}

OrbitItem _friend(int i, {int unread = 0}) => OrbitFriendItem(OrbitFriend(
      contact: ContactModel(
        peerId: 'peer-$i',
        publicKey: 'pk-$i',
        rendezvous: '/ip4/127.0.0.1/tcp/400$i',
        username: 'friend$i',
        signature: 'sig-$i',
        scannedAt: '2024-01-01T00:00:00Z',
      ),
      messageCount: i,
      unreadCount: unread,
      lastMessageTimestamp: '2024-01-01T00:00:00Z',
    ));

OrbitItem _group(String name) => OrbitGroupItem(OrbitGroup(
      group: GroupModel(
        id: 'g-$name',
        name: name,
        type: GroupType.chat,
        topicName: 'topic-$name',
        createdBy: 'creator',
        myRole: GroupRole.admin,
        createdAt: DateTime.utc(2026, 1, 1),
      ),
      lastActivityTimestamp: DateTime.utc(2026, 7, 2),
    ));

List<OrbitItem> _friends(int n) => [for (var i = 0; i < n; i++) _friend(i)];

void main() {
  late List<OrbitFriend> tappedFriends;
  late List<OrbitGroup> tappedGroups;
  late List<bool> editEvents;

  setUp(() {
    tappedFriends = [];
    tappedGroups = [];
    editEvents = [];
  });

  Widget host(
    List<OrbitItem> items, {
    FakeSecureKeyStore? store,
    Listenable? resetSignal,
    Key? key,
    Locale locale = const Locale('en'),
    bool resizeToAvoidBottomInset = true,
    TargetPlatform? platform,
    double bottomClearance = 0,
  }) =>
      MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            platform: platform,
            extensions: [BackgroundReadableColors.dark]),
        home: Scaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          body: InnerCircleInteractiveSurface(
            key: key,
            userPeerId: 'me',
            items: items,
            onFriendTap: tappedFriends.add,
            onGroupTap: tappedGroups.add,
            secureKeyStore: store,
            onEditSessionActiveChanged: editEvents.add,
            resetSignal: resetSignal,
            bottomClearance: bottomClearance,
          ),
        ),
      );

  Future<void> settle(WidgetTester tester, {int count = 16}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  Offset bgPoint(WidgetTester tester) {
    // A point to the LEFT of the (horizontally centered) circle column — empty
    // background, never on a node/title/caption, so the sibling background
    // gesture layer receives it.
    final r = tester.getRect(
        find.byKey(const ValueKey('orbit-inner-circle-background')));
    return Offset(r.left + 36, r.center.dy);
  }

  Future<void> longPressBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await tester.pump(const Duration(milliseconds: 620)); // past 500ms long-press
    await g.up();
    await tester.pump();
  }

  Future<void> doubleTapBg(WidgetTester tester) async {
    final p = bgPoint(tester);
    final g1 = await tester.startGesture(p);
    await g1.up();
    await tester.pump(const Duration(milliseconds: 60));
    final g2 = await tester.startGesture(p);
    await g2.up();
    await tester.pump();
  }

  Future<void> tapAwayBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await g.up();
    await tester.pump(const Duration(milliseconds: 350)); // clear double-tap window
  }

  Finder bannerF() => find.byKey(const ValueKey('orbit-edit-banner'));
  Finder handleF(OrbitKnob k) =>
      find.byKey(ValueKey('orbit-handle-${k.name}'));
  Finder bubbleF() => find.byKey(const ValueKey('orbit-edit-value-bubble'));

  // ---- 198 fidelity helpers (geometry-anchored handles) ----
  // Mounted-even-if-band-hidden variant (Offstage hides from default finders).
  Finder handleAnyF(OrbitKnob k) =>
      find.byKey(ValueKey('orbit-handle-${k.name}'), skipOffstage: false);
  Finder canvasF() => find.byKey(const ValueKey('orbit-viz-canvas'));
  Offset canvasOrigin(WidgetTester tester) => tester.getTopLeft(canvasF());

  double overhangOf(int itemCount, OrbitGeometryPrefs g,
          {required bool expanded}) =>
      expanded
          ? orbitArcOverhang(memberCount: itemCount, geometry: g, centerY: 160)
          : 0.0;

  // Centre-local anchor formulas (plan §RED catalog) — an independent oracle,
  // deliberately NOT the production helper. sp/av/og/cv/pr sit on the PAINTED
  // geometry (ring2 seats are +15° off — never assert against seat rects).
  Offset anchorOf(OrbitKnob knob, OrbitGeometryPrefs g,
      {bool mirrored = false}) {
    final sp = g.spacingScale;
    final r0 = (108 + 46 * g.orbitGap) * sp;
    final phi0 = orbitArcPhi(r0, g.arcWrap);
    final sign = mirrored ? -1.0 : 1.0;
    return switch (knob) {
      OrbitKnob.spacingScale => Offset(0, 108 * sp),
      OrbitKnob.avatarScale => Offset(0, -62 * sp),
      OrbitKnob.orbitGap => Offset(0, -r0),
      OrbitKnob.arcWrap =>
        Offset(sign * r0 * math.sin(phi0), -r0 * math.cos(phi0)),
      OrbitKnob.maxPerArc =>
        Offset(-sign * r0 * math.sin(phi0), -r0 * math.cos(phi0)),
    };
  }

  Offset expectedCenter(
    WidgetTester tester,
    OrbitKnob knob,
    OrbitGeometryPrefs g,
    int itemCount, {
    required bool expanded,
    bool mirrored = false,
  }) {
    final o = canvasOrigin(tester);
    final ov = overhangOf(itemCount, g, expanded: expanded);
    final a = anchorOf(knob, g, mirrored: mirrored);
    return o + Offset(160 + a.dx, 160 + ov + a.dy);
  }

  String bubbleText(WidgetTester tester) => tester
      .widget<Text>(
          find.descendant(of: bubbleF(), matching: find.byType(Text)))
      .data!;
  double bubbleValue(WidgetTester tester) =>
      double.parse(bubbleText(tester).replaceAll('×', ''));

  double ringOpacity(WidgetTester tester) => tester
      .widget<Opacity>(find
          .ancestor(
              of: find.byWidgetPredicate(
                  (w) => w is CustomPaint && w.painter is OrbitalRingPainter),
              matching: find.byType(Opacity))
          .first)
      .opacity;

  // The viz's per-node dim wrapper (OrbitalAvatar has its own inner entrance
  // Opacity, so ancestor-of-node lookups grab the wrong one).
  double nodeOpacity(WidgetTester tester, int index) => tester
      .widget<Opacity>(find.byKey(ValueKey('orbit-node-dim-$index')))
      .opacity;

  Finder centreAvatarF() => find.byType(UserAvatar).first;

  Future<void> expandBadge(WidgetTester tester) async {
    await tester.tap(find.byType(OverflowBadge));
    await settle(tester);
  }

  group('198 F6 — edit session (Group B)', () {
    testWidgets('TC-198-14 long-press empty space enters edit (banner, Reset)',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(bannerF(), findsNothing);

      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-edit-reset')), findsOneWidget);
      expect(editEvents, [true]);
      await settle(tester);
    });

    testWidgets('TC-198-26 collapsed edit shows only av/sp handles',
        (tester) async {
      await tester.pumpWidget(host(_friends(20))); // overflow, but collapsed
      await settle(tester);
      await longPressBg(tester);
      expect(handleF(OrbitKnob.avatarScale), findsOneWidget);
      expect(handleF(OrbitKnob.spacingScale), findsOneWidget);
      expect(handleF(OrbitKnob.arcWrap), findsNothing);
      expect(handleF(OrbitKnob.maxPerArc), findsNothing);
      expect(handleF(OrbitKnob.orbitGap), findsNothing);
      await settle(tester);
    });

    testWidgets('expanded edit shows all 5 handles', (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await tester.tap(find.byType(OverflowBadge)); // expand arcs
      await settle(tester);
      await longPressBg(tester);
      for (final k in OrbitKnob.values) {
        expect(handleF(k), findsOneWidget, reason: '${k.name} handle');
      }
      await settle(tester);
    });

    testWidgets('TC-198-20/21 arm shows bubble + steppers; step + clamp',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bubbleF(), findsNothing);

      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(bubbleF(), findsOneWidget);
      expect(find.text('1.0×'), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-edit-step-increase')),
          findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);
      // saturate at 1.4 without throwing.
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
        await tester.pump();
      }
      expect(find.text('1.4×'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-22 handle drag changes the knob', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(find.text('1.0×'), findsOneWidget);

      // Drag up increases avatarScale (-dy/90); a big drag saturates at 1.4.
      await tester.drag(handleF(OrbitKnob.avatarScale), const Offset(0, -80));
      await tester.pump();
      expect(find.text('1.0×'), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-25 Reset restores defaults, session stays active',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();
      // still editing (banner present), value back to default.
      expect(bannerF(), findsOneWidget);
      expect(find.text('1.0×'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-18 empty-space tap-away exits; callback fires false',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tapAwayBg(tester);
      expect(bannerF(), findsNothing);
      expect(editEvents, [true, false]);
      await settle(tester);
    });

    testWidgets('TC-198-19 dimmed node tap-away exits edit, does NOT open chat',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      // Tapping a (dimmed) node while editing ends the session without routing.
      // friend2 — friend0's 12-o'clock seat now hosts the av handle, whose
      // handle-wins overlap contract is pinned separately by TC-198F-25.
      await tester.tap(find.bySemanticsLabel('Open chat with friend2'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(bannerF(), findsNothing);
      expect(tappedFriends, isEmpty);
      await settle(tester);
    });

    testWidgets('TC-198-27 badge toggles arcs mid-edit without exiting',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tester.tap(find.byType(OverflowBadge));
      await settle(tester);
      // still editing, and now all 5 handles show (arcs expanded).
      expect(bannerF(), findsOneWidget);
      expect(handleF(OrbitKnob.orbitGap), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-15 long-press on a node does not enter edit',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.longPress(find.bySemanticsLabel('Open chat with friend0'));
      await tester.pump();
      expect(bannerF(), findsNothing);
      await settle(tester);
    });
  });

  group('198 F6 — persistence (Group D)', () {
    testWidgets('TC-198-33 sculpt persists across a remount', (tester) async {
      final store = FakeSecureKeyStore();
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('a')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget);
      await settle(tester);

      // Remount a fresh surface state against the same store.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('b')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(find.text('1.2×'), findsOneWidget,
          reason: 'restored the persisted avatarScale');
      await settle(tester);
    });

    testWidgets('TC-198-36 Reset deletes the key → fresh mount is default',
        (tester) async {
      final store = FakeSecureKeyStore();
      await store.write(OrbitGeometryPrefs.storageKey, '1.2|1.0|1.0|9|1.0');
      await tester.pumpWidget(host(_friends(8), store: store, key: const ValueKey('a')));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();
      await settle(tester);

      expect(await store.read(OrbitGeometryPrefs.storageKey), isNull);
    });

    testWidgets('TC-198-38 no write until first edit; first edit writes once',
        (tester) async {
      final spy = _SpyStore();
      await tester.pumpWidget(host(_friends(20), store: spy));
      await settle(tester);
      // Expansion + labels write nothing.
      await tester.tap(find.byType(OverflowBadge));
      await settle(tester);
      await doubleTapBg(tester); // labels
      await settle(tester);
      expect(spy.writes, 0);

      // First knob edit writes.
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(spy.writes, 1);
      await settle(tester);
    });
  });

  group('198 F6 — find (Group E)', () {
    testWidgets('TC-198-39 find pill present, expands with focus',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(find.byKey(const ValueKey('orbit-find-pill')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-40 single match lights + chip with ring provenance',
        (tester) async {
      final items = <OrbitItem>[_friend(0), _group('Zenith'), _friend(2)];
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'zenith');
      await tester.pump();
      // one chip, provenance "Ring 1" (index 1 → ring 1).
      expect(find.byKey(const ValueKey('orbit-find-chip-1')), findsOneWidget);
      expect(find.text('Ring 1'), findsOneWidget);
      await settle(tester);
    });

    testWidgets('TC-198-41 six matches light all, exactly 4 chips',
        (tester) async {
      final items = [for (var i = 0; i < 6; i++) _friend(i)]; // friend0..5
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-4')), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-44 group match chips + opens the group conversation',
        (tester) async {
      final items = <OrbitItem>[..._friends(5), _group('Book Club')];
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'book');
      await tester.pump();
      final chip = find.byKey(const ValueKey('orbit-find-chip-5'));
      expect(chip, findsOneWidget);
      await tester.tap(chip);
      await tester.pump();
      expect(tappedGroups.single.name, 'Book Club');
      await settle(tester);
    });

    testWidgets('TC-198-46 zero matches → no chips (anti-signal)',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      await settle(tester);
    });

    testWidgets('TC-198-48 tap-away closes + clears find', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);

      await tapAwayBg(tester);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      await settle(tester);
    });
  });

  group('198 F6 — composition (Group F) + reset (Group R)', () {
    testWidgets('TC-198-53 double-tap toggles labels', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      expect(find.text('friend0'), findsNothing);

      await doubleTapBg(tester);
      await settle(tester);
      expect(find.text('friend0'), findsOneWidget);

      await doubleTapBg(tester);
      await settle(tester);
      expect(find.text('friend0'), findsNothing);
    });

    testWidgets('TC-198-50 typing in find does not exit edit', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      expect(bannerF(), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(bannerF(), findsOneWidget, reason: 'edit survives find typing');
      await settle(tester);
    });

    testWidgets('TC-198-52 chip tap opens chat AND ends edit', (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend0');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-find-chip-0')));
      await tester.pump();
      expect(tappedFriends.single.username, 'friend0');
      expect(bannerF(), findsNothing, reason: 'chip tap ended the edit session');
      await settle(tester);
    });

    testWidgets('TC-198-54 single node tap opens chat immediately',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('Open chat with friend3'));
      await tester.pump(); // no double-tap-timeout wait
      expect(tappedFriends.single.username, 'friend3');
      await settle(tester);
    });

    testWidgets('TC-198-63 reset signal collapses arcs, exits edit, clears find',
        (tester) async {
      final reset = ValueNotifier<int>(0);
      addTearDown(reset.dispose);
      await tester.pumpWidget(host(_friends(20), resetSignal: reset));
      await settle(tester);
      await tester.tap(find.byType(OverflowBadge)); // expand
      await settle(tester);
      await longPressBg(tester); // edit
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(bannerF(), findsOneWidget);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);

      reset.value++; // Feed→Orbit rising edge
      await settle(tester);
      expect(bannerF(), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      expect(editEvents.last, isFalse);
    });
  });

  group('198 fidelity — geometry-anchored handles (F rows)', () {
    const g0 = OrbitGeometryPrefs.defaults;

    testWidgets('TC-198F-01 five handles seated at geometry anchors (expanded)',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      for (final k in OrbitKnob.values) {
        final expected = expectedCenter(tester, k, g0, 20, expanded: true);
        final actual = tester.getCenter(handleF(k));
        expect((actual - expected).distance, lessThan(2.0),
            reason: '${k.name} at $actual, formula anchor $expected');
      }
      await settle(tester);
    });

    testWidgets(
        'TC-198F-02 handles re-seat same-frame on knob change; Reset re-seats to defaults',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      // One drag-update frame: the sp drag clamps at 0.7 (slop-proof) and every
      // handle must sit at the NEW geometry's formula anchor on THIS pump.
      final gDrag =
          await tester.startGesture(tester.getCenter(handleF(OrbitKnob.spacingScale)));
      await tester.pump(const Duration(milliseconds: 20));
      await gDrag.moveBy(const Offset(0, -20)); // consume the touch slop
      await tester.pump();
      await gDrag.moveBy(const Offset(0, -60)); // deep past the 0.7 clamp
      await tester.pump(); // the single frame under test — no lag allowed
      expect(find.text('0.7×'), findsOneWidget);
      final gNew = g0.copyWith(spacingScale: 0.7);
      for (final k in OrbitKnob.values) {
        final expected = expectedCenter(tester, k, gNew, 20, expanded: true);
        expect((tester.getCenter(handleF(k)) - expected).distance, lessThan(2.0),
            reason: '${k.name} re-seated same-frame');
      }
      await gDrag.up();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();
      for (final k in OrbitKnob.values) {
        final expected = expectedCenter(tester, k, g0, 20, expanded: true);
        expect((tester.getCenter(handleF(k)) - expected).distance, lessThan(2.0),
            reason: '${k.name} re-seated to the default anchor after Reset');
      }
      await settle(tester);
    });

    testWidgets(
        'TC-198-71 handles track scroll; off-band hidden not unmounted; armed survives',
        (tester) async {
      await tester.pumpWidget(host(_friends(80))); // deep stack — scrollable
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      // sp's anchor starts below the fold: hidden (default finders skip
      // Offstage) but MOUNTED (state maintained, recognizer alive).
      expect(handleF(OrbitKnob.spacingScale), findsNothing);
      expect(handleAnyF(OrbitKnob.spacingScale), findsOneWidget);

      await tester.tap(handleF(OrbitKnob.orbitGap), warnIfMissed: false);
      await tester.pump();
      expect(bubbleF(), findsOneWidget);

      // Scroll: every visible handle shifts by exactly the canvas delta.
      const visibleKnobs = [
        OrbitKnob.orbitGap,
        OrbitKnob.avatarScale,
        OrbitKnob.arcWrap,
        OrbitKnob.maxPerArc,
      ];
      final before = {
        for (final k in visibleKnobs) k: tester.getCenter(handleF(k)),
      };
      final originBefore = canvasOrigin(tester);
      await tester.dragFrom(const Offset(60, 300), const Offset(0, -120));
      await tester.pump();
      final dy = canvasOrigin(tester).dy - originBefore.dy;
      expect(dy, lessThan(-80), reason: 'the surface actually scrolled');
      for (final k in visibleKnobs) {
        expect(tester.getCenter(handleF(k)).dy - before[k]!.dy, closeTo(dy, 2),
            reason: '${k.name} tracked the scroll delta');
        expect(tester.getCenter(handleF(k)).dx, closeTo(before[k]!.dx, 2));
      }
      expect(bubbleF(), findsOneWidget, reason: 'armed og survived the scroll');

      // Scroll to the bottom: sp enters the band at its formula anchor.
      await tester.dragFrom(const Offset(60, 300), const Offset(0, -400));
      await settle(tester, count: 4);
      expect(handleF(OrbitKnob.spacingScale), findsOneWidget);
      final spExpected =
          expectedCenter(tester, OrbitKnob.spacingScale, g0, 80, expanded: true);
      expect(
          (tester.getCenter(handleF(OrbitKnob.spacingScale)) - spExpected)
              .distance,
          lessThan(2.0));
      expect(bubbleF(), findsOneWidget);

      // Scroll back to the top: sp exits again — hidden, never unmounted.
      await tester.dragFrom(const Offset(60, 300), const Offset(0, 600));
      await settle(tester, count: 4);
      expect(handleF(OrbitKnob.spacingScale), findsNothing);
      expect(handleAnyF(OrbitKnob.spacingScale), findsOneWidget);
      expect(bubbleF(), findsOneWidget, reason: 'og still armed');
      await settle(tester);
    });

    testWidgets(
        'TC-198F-04 live drag never interrupted by re-seat/band-hide; yield gate held',
        (tester) async {
      // 340px band: 203 B5 removed the viz title (~41px above the canvas), so
      // the top-anchored canvas — and with it the cv tip's whole sweep — sits
      // that much higher. 380−41≈340 keeps the original crossing margin (the
      // saturated arcWrap tip bottoms out at ~366).
      tester.view.physicalSize = const Size(800, 340);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      // Sweep the cv tip around the circle: the anchor crosses the bottom band
      // edge mid-gesture while the SAME drag keeps delivering updates
      // (bounded until-hidden sweep — the exact crossing step is
      // layout-dependent).
      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.arcWrap)));
      await tester.pump(const Duration(milliseconds: 20));
      var steps = 0;
      while (handleF(OrbitKnob.arcWrap).evaluate().isNotEmpty && steps < 24) {
        await g.moveBy(const Offset(-7, 16));
        await tester.pump();
        steps++;
      }
      // The tip anchor is now below the 340px band → hidden but mounted, and
      // the gesture is still live.
      expect(handleF(OrbitKnob.arcWrap), findsNothing,
          reason: 'cv handle band-hidden mid-drag (crossed by step $steps)');
      expect(handleAnyF(OrbitKnob.arcWrap), findsOneWidget,
          reason: 'band-hide must never unmount (kills the recognizer)');
      final vHidden = bubbleValue(tester);
      await g.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(bubbleValue(tester), greaterThan(vHidden + 0.1),
          reason: 'drag updates keep flowing while hidden');
      expect(editEvents, [true],
          reason: 'yield gate (INV-8) never dropped mid-drag');
      await g.up();
      await tester.pump();
      expect(editEvents, [true]);
      expect(tester.takeException(), isNull);
      await settle(tester);
    });

    testWidgets(
        'TC-198-72 planted circle: og drag on a deep stack keeps the circle stationary (scroll compensates)',
        (tester) async {
      await tester.pumpWidget(host(_friends(80)));
      await settle(tester);
      await expandBadge(tester);
      // Scroll to the bottom, then back off the boundary so clamping cannot
      // mask a missing compensation seam.
      await tester.dragFrom(const Offset(60, 300), const Offset(0, -500));
      await settle(tester, count: 4);
      await tester.dragFrom(const Offset(60, 300), const Offset(0, 60));
      await settle(tester, count: 4);
      await longPressBg(tester);
      await settle(tester);

      final userBefore = tester.getCenter(centreAvatarF());
      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.orbitGap)));
      await tester.pump(const Duration(milliseconds: 20));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(0, 8)); // shrink og → overhang shrinks
        await tester.pump();
        final drift =
            (tester.getCenter(centreAvatarF()).dy - userBefore.dy).abs();
        expect(drift, lessThan(8),
            reason: 'circle planted mid-drag (step ${i + 1})');
      }
      await g.up();
      await tester.pump();
      expect((tester.getCenter(centreAvatarF()).dy - userBefore.dy).abs(),
          lessThan(8),
          reason: 'circle planted after the drag');
      expect(find.text('1.0×'), findsNothing, reason: 'og actually changed');
      await settle(tester);
    });

    testWidgets('TC-198F-06 RTL: tip↔knob assignment pinned in screen space',
        (tester) async {
      await tester.pumpWidget(host(_friends(20), locale: const Locale('ar')));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      final cv = tester.getCenter(handleF(OrbitKnob.arcWrap));
      final pr = tester.getCenter(handleF(OrbitKnob.maxPerArc));
      final cvExpected = expectedCenter(tester, OrbitKnob.arcWrap, g0, 20,
          expanded: true, mirrored: true);
      final prExpected = expectedCenter(tester, OrbitKnob.maxPerArc, g0, 20,
          expanded: true, mirrored: true);
      expect((cv - cvExpected).distance, lessThan(2.0),
          reason: 'cv follows the mirrored +φ tip');
      expect((pr - prExpected).distance, lessThan(2.0),
          reason: 'pr rides the mirrored −φ twin tip');
      // Under RTL cv sits screen-LEFT and pr screen-RIGHT — and never swap.
      final centreX = canvasOrigin(tester).dx + 160;
      expect(cv.dx, lessThan(centreX));
      expect(pr.dx, greaterThan(centreX));
      expect(tester.takeException(), isNull, reason: 'no overflow errors');
      await settle(tester);
    });

    testWidgets(
        'TC-198F-07 collapsed edit: av/sp at ring anchors; cv/pr/og absent',
        (tester) async {
      await tester.pumpWidget(host(_friends(12)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      for (final k in [OrbitKnob.avatarScale, OrbitKnob.spacingScale]) {
        final expected = expectedCenter(tester, k, g0, 12, expanded: false);
        expect((tester.getCenter(handleF(k)) - expected).distance,
            lessThan(2.0),
            reason: '${k.name} at its ring anchor while collapsed');
      }
      for (final k in [
        OrbitKnob.arcWrap,
        OrbitKnob.maxPerArc,
        OrbitKnob.orbitGap,
      ]) {
        expect(handleAnyF(k), findsNothing,
            reason: '${k.name} truly absent (not just hidden) while collapsed');
      }
      await settle(tester);
    });

    testWidgets('TC-198F-08 keyboard during edit+find does not desync handles',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();

      // Keyboard: a real view inset shrinks the Scaffold body → constraints
      // change → the measured origin must be re-derived.
      tester.view.viewInsets = const FakeViewPadding(bottom: 600); // 200 logical
      addTearDown(tester.view.resetViewInsets);
      await tester.pump();
      await settle(tester);

      var visible = 0;
      for (final k in OrbitKnob.values) {
        if (handleF(k).evaluate().isEmpty) continue; // band-hide is legal
        visible++;
        final expected = expectedCenter(tester, k, g0, 20, expanded: true);
        expect((tester.getCenter(handleF(k)) - expected).distance,
            lessThan(2.0),
            reason: '${k.name} matches the re-measured origin');
      }
      expect(visible, greaterThanOrEqualTo(3));
      expect(bannerF(), findsOneWidget, reason: 'edit survived the keyboard');
      await settle(tester);
    });

    testWidgets(
        'TC-198F-09 first frame after long-press: no crash, handles appear only positioned',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester); // ends with a single pump — the first frame
      // Either not yet shown (first-frame guard) or already at a valid anchor —
      // never a (0,0)/top-left cluster.
      for (final k in OrbitKnob.values) {
        if (handleF(k).evaluate().isEmpty) continue;
        final expected = expectedCenter(tester, k, g0, 20, expanded: true);
        expect((tester.getCenter(handleF(k)) - expected).distance,
            lessThan(2.0),
            reason: '${k.name} must never render unpositioned');
      }
      expect(tester.takeException(), isNull);
      await settle(tester);
      for (final k in OrbitKnob.values) {
        final expected = expectedCenter(tester, k, g0, 20, expanded: true);
        expect((tester.getCenter(handleF(k)) - expected).distance,
            lessThan(2.0),
            reason: '${k.name} settled at its anchor');
      }
    });

    testWidgets(
        'TC-198F-13 pulse/timer lifecycle: stops on session end; survives route-pop mid-edit',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.pump();
      final discF =
          find.byKey(const ValueKey('orbit-handle-disc-avatarScale'));
      double blur() =>
          (tester.widget<Container>(discF).decoration! as BoxDecoration)
              .boxShadow!
              .first
              .blurRadius;
      final b0 = blur();
      await tester.pump(const Duration(milliseconds: 800));
      expect(blur(), isNot(closeTo(b0, 0.01)), reason: 'pulse is running');

      await tapAwayBg(tester);
      expect(bannerF(), findsNothing);
      expect(discF, findsNothing,
          reason: 'session end tears the pulse down with the overlay');
      await settle(tester);

      // Re-enter, then rip the route out mid-edit (the F13 perf harness pops
      // the route while editing) — no ticker/timer leak, no exception.
      await longPressBg(tester);
      await tester.pump();
      expect(bannerF(), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'TC-198-20R value bubble floats above the ARMED handle and moves on re-arm',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      final avCenter = tester.getCenter(handleF(OrbitKnob.avatarScale));
      var bubble = tester.getRect(bubbleF());
      expect((bubble.center.dx - avCenter.dx).abs(), lessThanOrEqualTo(2.0),
          reason: 'bubble horizontally centred on the armed handle');
      expect(bubble.bottom, lessThan(avCenter.dy - 15),
          reason: 'bubble floats above the disc');
      expect(avCenter.dy - 15 - bubble.bottom, lessThanOrEqualTo(12),
          reason: 'bubble hugs the disc (gap ≤12px)');
      expect(find.text('1.0×'), findsOneWidget);
      final text = tester.widget<Text>(
          find.descendant(of: bubbleF(), matching: find.byType(Text)));
      expect(text.style!.color, const Color(0xFF4ECDC4),
          reason: 'teal armed-value treatment');

      await tester.tap(handleF(OrbitKnob.spacingScale), warnIfMissed: false);
      await tester.pump();
      final spCenter = tester.getCenter(handleF(OrbitKnob.spacingScale));
      bubble = tester.getRect(bubbleF());
      expect((bubble.center.dx - spCenter.dx).abs(), lessThanOrEqualTo(2.0));
      expect(bubble.bottom, lessThan(spCenter.dy - 15),
          reason: 'bubble relocated above the re-armed handle');
      await settle(tester);
    });

    testWidgets('TC-198F-15 bubble tracks the handle and updates live mid-drag',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      final start = tester.getCenter(handleF(OrbitKnob.spacingScale));
      final g = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(0, -20)); // slop + arm via pan-start
      await tester.pump();
      await g.moveBy(const Offset(0, -25));
      await tester.pump(); // mid-drag frame
      expect(find.text('1.0×'), findsNothing,
          reason: 'value updates live mid-drag, not on drag-end');
      final spNow = tester.getCenter(handleF(OrbitKnob.spacingScale));
      expect(spNow.dy, lessThan(start.dy),
          reason: 'sp anchor rose as the knob shrank');
      final bubble = tester.getRect(bubbleF());
      expect((bubble.center.dx - spNow.dx).abs(), lessThanOrEqualTo(2.0));
      expect(bubble.bottom, lessThan(spNow.dy - 14),
          reason: 'bubble tracks the moving anchor');
      await g.up();
      await tester.pump();
      await settle(tester);
    });

    // ── 203 B3: handle discs scale with the avatar-size knob ──────────────

    testWidgets(
        'TC-203-09 seeded avatarScale 1.4 renders 42px discs — collapsed av '
        'AND expanded og handles', (tester) async {
      // Seed BEFORE pump — _restoreGeometry runs once from initState, a later
      // write is a silent no-op.
      final store = FakeSecureKeyStore();
      await store.write(OrbitGeometryPrefs.storageKey, '1.4|1.0|1.0|9|1.0');
      await tester.pumpWidget(host(_friends(8), store: store));
      await settle(tester);
      await longPressBg(tester);
      await tester.pump();
      final avDisc = tester.getSize(
          find.byKey(const ValueKey('orbit-handle-disc-avatarScale')));
      expect(avDisc.width, closeTo(42, 0.5),
          reason: 'collapsed-mode disc scales from the persisted store');
      await settle(tester);

      // Expanded-only witness: the og handle only mounts with arcs expanded
      // (one ctor site serves both modes, but the wiring must be SEEN there).
      final store2 = FakeSecureKeyStore();
      await store2.write(OrbitGeometryPrefs.storageKey, '1.4|1.0|1.0|9|1.0');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(host(_friends(20), store: store2));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await tester.pump();
      final ogDisc = tester.getSize(
          find.byKey(const ValueKey('orbit-handle-disc-orbitGap')));
      expect(ogDisc.width, closeTo(42, 0.5),
          reason: 'expanded-mode disc scales from the persisted store');
      await settle(tester);
    });

    testWidgets(
        'TC-203-10 live application: av clamp-drag grows the disc same-pump',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale));
      await tester.pump();
      expect(
          tester
              .getSize(find.byKey(
                  const ValueKey('orbit-handle-disc-avatarScale')))
              .width,
          closeTo(30, 0.5));

      // Saturates the 1.4 clamp regardless of the ~18px tester slop
      // (TC-198-22 precedent), asserting MID-GESTURE — a settle-only
      // (pan-end) application stays red here.
      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.avatarScale)));
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(0, -20)); // slop + pan-start (F15 precedent)
      await tester.pump();
      await g.moveBy(const Offset(0, -60)); // −60/90 saturates the 1.4 clamp
      await tester.pump(); // ONE pump — same-frame application, no lag
      expect(
          tester
              .getSize(find.byKey(
                  const ValueKey('orbit-handle-disc-avatarScale')))
              .width,
          closeTo(42, 0.5),
          reason: 'disc grew in the drag\'s own build, gesture still live');
      expect(find.text('1.4×'), findsOneWidget,
          reason: 'value-bubble corroboration');
      await g.up();
      await tester.pump();
      await settle(tester);
    });

    testWidgets(
        'TC-203-11 bubble hugs the SCALED disc at 1.4 (shared '
        'effectiveDiscSize lock)', (tester) async {
      final store = FakeSecureKeyStore();
      await store.write(OrbitGeometryPrefs.storageKey, '1.4|1.0|1.0|9|1.0');
      await tester.pumpWidget(host(_friends(8), store: store));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      final avCenter = tester.getCenter(handleF(OrbitKnob.avatarScale));
      final bubble = tester.getRect(bubbleF());
      // Bubble bottom = disc center − (effectiveDiscSize/2 + 6) = center − 27.
      // A partial fix that scales the widget but leaves the bubble clamp on
      // discSize/2 sits at center − 21 and stays red here.
      expect(avCenter.dy - bubble.bottom, closeTo(27, 2.0),
          reason: 'bubble bottom hugs the 42px disc: half 21 + 6px gap');
      await settle(tester);
    });

    testWidgets('TC-198-20S −/+ steppers land at the bottom corners while armed',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      expect(find.byKey(const ValueKey('orbit-edit-step-decrease')),
          findsNothing,
          reason: 'absent when nothing is armed');

      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final dec = tester
          .getRect(find.byKey(const ValueKey('orbit-edit-step-decrease')));
      final inc = tester
          .getRect(find.byKey(const ValueKey('orbit-edit-step-increase')));
      expect(dec.left - surface.left, closeTo(22, 2));
      expect(surface.right - inc.right, closeTo(22, 2));
      expect(surface.bottom - dec.bottom, closeTo(28, 2),
          reason: '− rides the nav-bar line');
      expect(surface.bottom - inc.bottom, closeTo(28, 2),
          reason: '+ rides the nav-bar line');
      expect(dec.size, const Size(48, 48));
      expect(inc.size, const Size(48, 48));
      await settle(tester);
    });

    testWidgets(
        'TC-198F-17 armed-state bottom re-flow: find pill lifts and stays usable',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      Rect pill() =>
          tester.getRect(find.byKey(const ValueKey('orbit-find-pill')));
      expect(surface.bottom - pill().bottom, closeTo(40, 2),
          reason: 'idle band while nothing is armed');

      await tester.tap(handleF(OrbitKnob.orbitGap), warnIfMissed: false);
      await tester.pump();
      expect(surface.bottom - pill().bottom, closeTo(88, 2),
          reason: 'armed: pill lifts clear of the + stepper band');

      // The lifted pill still opens find WITHOUT ending the edit session.
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      expect(find.byType(TextField), findsOneWidget);
      expect(bannerF(), findsOneWidget);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(bannerF(), findsOneWidget,
          reason: 'expanded pill + armed: focus does not end edit');

      // Disarm (badge collapse disarms cv/pr/og) → pill returns to its band.
      await tester.tap(find.byType(OverflowBadge), warnIfMissed: false);
      await settle(tester);
      expect(bubbleF(), findsNothing, reason: 'og disarmed by the collapse');
      expect(surface.bottom - pill().bottom, closeTo(40, 2));
      await settle(tester);
    });

    testWidgets(
        'TC-198F-18 bottom-band disjointness sweep (armed × find × chips × keyboard)',
        (tester) async {
      tester.view.viewInsets = const FakeViewPadding(bottom: 360); // 120 logical
      addTearDown(tester.view.resetViewInsets);
      // resizeToAvoidBottomInset:false mirrors the production orbit screen —
      // every bottom-anchored edit element must carry the bottomInset term.
      await tester.pumpWidget(
          host(_friends(20), resizeToAvoidBottomInset: false));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(handleF(OrbitKnob.orbitGap), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend1');
      await tester.pump();

      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final chipKeys = [
        for (final el in find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>).value.startsWith('orbit-find-chip-'))
            .evaluate())
          (el.widget.key! as ValueKey<String>).value,
      ];
      expect(chipKeys.length, greaterThanOrEqualTo(2),
          reason: 'the sweep needs at least two chips');
      final rects = <String, Rect>{
        'decrease': tester
            .getRect(find.byKey(const ValueKey('orbit-edit-step-decrease'))),
        'increase': tester
            .getRect(find.byKey(const ValueKey('orbit-edit-step-increase'))),
        'pill': tester.getRect(find.byKey(const ValueKey('orbit-find-pill'))),
        for (final k in chipKeys) k: tester.getRect(find.byKey(ValueKey(k))),
      };
      final names = rects.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          expect(rects[names[i]]!.overlaps(rects[names[j]]!), isFalse,
              reason: '${names[i]} × ${names[j]} must be disjoint');
        }
      }
      // The bottomInset term is present on every bottom-anchored element.
      expect(surface.bottom - rects['increase']!.bottom, closeTo(120 + 28, 2));
      expect(surface.bottom - rects['decrease']!.bottom, closeTo(120 + 28, 2));
      expect(surface.bottom - rects['pill']!.bottom, closeTo(120 + 88, 2));
      for (final k in chipKeys) {
        expect(surface.bottom - rects[k]!.bottom, closeTo(120 + 144, 6),
            reason: 'chip strip lifts to its armed-state band ($k)');
      }
      await settle(tester);
    });

    testWidgets(
        'TC-198-21R stepper press flash-lifts the dim 650ms; cancels safely',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);
      OrbitalVisualization viz() => tester
          .widget<OrbitalVisualization>(find.byType(OrbitalVisualization));
      expect(viz().editDim, isTrue);

      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      final inc = find.byKey(const ValueKey('orbit-edit-step-increase'));
      await tester.tap(inc);
      await tester.pump();
      expect(viz().editDim, isFalse, reason: 'stepper press lifts the dim');
      await tester.pump(const Duration(milliseconds: 700));
      expect(viz().editDim, isTrue, reason: 'dim returns after 650ms');

      // Rapid double-press re-arms the window: still lifted at t=900ms.
      await tester.tap(inc);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(inc);
      await tester.pump(const Duration(milliseconds: 500));
      expect(viz().editDim, isFalse,
          reason: 're-pressed at t=400ms → still lifted at t=900ms');
      await tester.pump(const Duration(milliseconds: 700));
      expect(viz().editDim, isTrue);

      // Press then tap-away inside the window: session end cancels the timer.
      await tester.tap(inc);
      await tester.pump();
      await tapAwayBg(tester);
      expect(bannerF(), findsNothing);
      await tester.pump(const Duration(milliseconds: 700));
      expect(viz().editDim, isFalse,
          reason: 'no dim flip after the session ended');
      await settle(tester);
    });

    testWidgets(
        'TC-198F-20 ring emphasis while editing; find-lit nodes stay full-bright through the flash',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      final dynamic vizIdle =
          tester.widget(find.byType(OrbitalVisualization));
      expect(vizIdle.editEmphasis as bool, isFalse);
      expect(ringOpacity(tester), 1.0);

      await longPressBg(tester);
      await settle(tester);
      final dynamic vizEdit =
          tester.widget(find.byType(OrbitalVisualization));
      expect(vizEdit.editEmphasis as bool, isTrue);
      expect(ringOpacity(tester), 0.85,
          reason: 'edit-idle: brightened ring (HEAD pinned 0.45)');

      // Mid-drag → 1.0, back to the brightened value on release.
      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.avatarScale)));
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      expect(ringOpacity(tester), 1.0, reason: 'dragging: rings full-bright');
      await g.up();
      await tester.pump();
      expect(ringOpacity(tester), 0.85);

      // Find during edit, then a stepper flash: rings 1.0, the lit node stays
      // full-bright (INV-5), the unlit node follows the find dim.
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend0');
      await tester.pump();
      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
      await tester.pump();
      expect(ringOpacity(tester), 1.0, reason: 'flash: rings full-bright');
      expect(nodeOpacity(tester, 0), 1.0,
          reason: 'find-lit node stays bright through the flash');
      expect(nodeOpacity(tester, 1), 0.28,
          reason: 'unlit node keeps the find dim during the flash');
      await tester.pump(const Duration(milliseconds: 700));
      expect(ringOpacity(tester), 0.85);
      expect(nodeOpacity(tester, 0), 1.0);
      expect(nodeOpacity(tester, 1), 0.22,
          reason: 'edit dim resumes after the flash');
      await settle(tester);
    });

    testWidgets('TC-198F-21 same dy, sp=1.5 → og delta ÷1.5', (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      Future<double> dragOgAndRead() async {
        final g = await tester.startGesture(
            tester.getCenter(handleF(OrbitKnob.orbitGap)));
        await tester.pump(const Duration(milliseconds: 20));
        await g.moveBy(const Offset(0, -20)); // slop
        await tester.pump();
        await g.moveBy(const Offset(0, -46)); // identical post-slop travel
        await tester.pump();
        final v = bubbleValue(tester);
        await g.up();
        await tester.pump();
        return v;
      }

      final ogAtSp1 = await dragOgAndRead();
      await tester.tap(find.byKey(const ValueKey('orbit-edit-reset')));
      await tester.pump();

      // sp → 1.5 via the stepper (5 coarse increments of 0.1).
      await tester.tap(handleF(OrbitKnob.spacingScale), warnIfMissed: false);
      await tester.pump();
      for (var i = 0; i < 5; i++) {
        await tester
            .tap(find.byKey(const ValueKey('orbit-edit-step-increase')));
        await tester.pump();
      }
      expect(find.text('1.5×'), findsOneWidget);
      final ogAtSp15 = await dragOgAndRead();

      expect(ogAtSp15, lessThan(ogAtSp1),
          reason: 'the ÷sp term slows og at wide spacing');
      expect((ogAtSp1 - 1.0) / (ogAtSp15 - 1.0), closeTo(1.5, 0.35),
          reason: 'same finger travel → knob delta ratio ≈ sp ratio');
      await settle(tester);
    });

    testWidgets('TC-198F-22 horizontal drag on the cv handle changes the wrap',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      final cvCenter = tester.getCenter(handleF(OrbitKnob.arcWrap));
      final origin = canvasOrigin(tester);
      final centre =
          origin + Offset(160, 160 + overhangOf(20, g0, expanded: true));
      final g = await tester.startGesture(cvCenter);
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveBy(const Offset(30, 0));
      await tester.pump();

      // The mapping follows the ABSOLUTE pointer angle, so the prediction is
      // slop-proof: impossible on HEAD where cv ignores dx entirely.
      final pointer = cvCenter + const Offset(60, 0);
      final predicted = (math
                  .atan2(pointer.dx - centre.dx, centre.dy - pointer.dy)
                  .abs() /
              1.25)
          .clamp(0.5, 2.5);
      expect(find.text('1.0×'), findsNothing,
          reason: 'a horizontal-only drag changed the wrap');
      expect(bubbleValue(tester), closeTo(predicted, 0.051),
          reason: 'cv lands at the atan2 prediction for the final pointer');
      await g.up();
      await tester.pump();
      await settle(tester);
    });

    testWidgets('TC-198F-23 banner + Reset wear the green terminal chrome',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);

      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final bannerDeco = tester.widget<Container>(bannerF()).decoration!
          as BoxDecoration;
      expect(bannerDeco.border, isNotNull,
          reason: 'banner wears the green-tinted bordered pill');
      expect((bannerDeco.border! as Border).top.color,
          const Color(0x591DB954));
      final bannerText = tester.widget<Text>(
          find.descendant(of: bannerF(), matching: find.byType(Text)));
      expect(bannerText.style!.color, const Color(0xFF1ED760));
      expect(bannerText.data, 'TAP AWAY TO FINISH', reason: 'copy unchanged');
      final bRect = tester.getRect(bannerF());
      expect((bRect.center.dx - surface.center.dx).abs(), lessThan(2.0),
          reason: 'banner stays top-centre');
      expect(bRect.top - surface.top, lessThan(60));

      final resetF = find.byKey(const ValueKey('orbit-edit-reset'));
      expect(find.descendant(of: resetF, matching: find.text('Reset')),
          findsOneWidget, reason: 'copy unchanged');
      expect(
          find.ancestor(
              of: find.text('Reset'), matching: find.byType(TextButton)),
          findsNothing,
          reason: 'Reset is the dark bordered pill, not a TextButton');
      final resetDeco = tester
          .widget<Container>(
              find.descendant(of: resetF, matching: find.byType(Container))
                  .first)
          .decoration! as BoxDecoration;
      expect(resetDeco.border, isNotNull);
      expect((resetDeco.border! as Border).top.color, const Color(0x29FFFFFF));
      expect(resetDeco.color, const Color(0xB30A0A0F));
      final rRect = tester.getRect(resetF);
      expect(rRect.top - surface.top, lessThan(60), reason: 'Reset top-left');
      expect(rRect.left - surface.left, lessThan(40));
      await settle(tester);
    });

    testWidgets(
        'TC-198-56 ensureSemantics sweep: exactly one labeled button per handle; steppers/Reset/pill labeled',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final en = AppLocalizationsEn();
      final names = <OrbitKnob, String>{
        OrbitKnob.avatarScale: en.orbit_handle_avatar_size,
        OrbitKnob.spacingScale: en.orbit_handle_ring_spacing,
        OrbitKnob.arcWrap: en.orbit_handle_arc_wrap,
        OrbitKnob.maxPerArc: en.orbit_handle_max_per_arc,
        OrbitKnob.orbitGap: en.orbit_handle_orbit_gap,
      };
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);

      for (final k in OrbitKnob.values) {
        final name = names[k]!;
        expect(name.contains('↕') || name.contains('⟷'), isFalse,
            reason: 'glyphs never enter Semantics labels');
        final f = find.bySemanticsLabel(name);
        expect(f, findsOneWidget,
            reason:
                'exactly ONE $name node — the tip-pill must not double-announce');
        expect(tester.getSemantics(f).flagsCollection.isButton, isTrue,
            reason: '$name announces as a button');
      }

      await tester.tap(handleF(OrbitKnob.avatarScale), warnIfMissed: false);
      await tester.pump();
      final incLabel =
          en.orbit_edit_step_increase(names[OrbitKnob.avatarScale]!);
      final decLabel =
          en.orbit_edit_step_decrease(names[OrbitKnob.avatarScale]!);
      expect(incLabel.contains('↕') || incLabel.contains('⟷'), isFalse);
      expect(find.bySemanticsLabel(incLabel), findsOneWidget);
      expect(find.bySemanticsLabel(decLabel), findsOneWidget);
      expect(find.bySemanticsLabel(en.orbit_edit_reset), findsOneWidget);
      expect(find.bySemanticsLabel(en.orbit_find_pill_semantics),
          findsOneWidget);
      await settle(tester);
      semantics.dispose();
    });

    // QA follow-up (wf_75f2c515-12b finding 1): a handle unmounted mid-drag
    // (badge collapse) disposes its recognizer without onPanEnd/Cancel — the
    // surface must settle the drag bookkeeping and persist the value itself.
    testWidgets(
        'TC-198F-26 badge collapse mid og-drag settles the drag: dim restores, value persists',
        (tester) async {
      final store = FakeSecureKeyStore();
      await tester.pumpWidget(host(_friends(20), store: store));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      OrbitalVisualization viz() => tester
          .widget<OrbitalVisualization>(find.byType(OrbitalVisualization));

      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.orbitGap)));
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(viz().editDim, isFalse, reason: 'dim lifted mid-drag');
      expect(await store.read(OrbitGeometryPrefs.storageKey), isNull,
          reason: 'nothing persisted before the drag settles');

      // A second finger collapses the badge mid-drag → the og handle unmounts.
      await tester.tap(find.byType(OverflowBadge), warnIfMissed: false);
      await settle(tester, count: 4);
      expect(bannerF(), findsOneWidget, reason: 'still editing');
      expect(viz().editDim, isTrue,
          reason: 'dim restored after the drag died with its handle');
      expect(await store.read(OrbitGeometryPrefs.storageKey), isNotNull,
          reason: 'the interrupted drag value was persisted');
      await g.up(); // stale pointer-up must be harmless
      await tester.pump();
      expect(tester.takeException(), isNull);
      await settle(tester);
    });

    // QA follow-up (finding 4): with a short stack there is no scroll range to
    // absorb Δoverhang — compensation must not force the position out of range
    // (the circle rides the growth; steppers remain the recovery path).
    testWidgets(
        'TC-198F-27 og drag on a short stack: no out-of-range scroll (canvas stays pinned)',
        (tester) async {
      // iOS bouncing physics tolerate out-of-range pixels (Android clamping
      // self-corrects) — this is where a forced jump becomes visible drift.
      await tester.pumpWidget(host(_friends(20),
          platform: TargetPlatform.iOS)); // fits the viewport
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      final originBefore = canvasOrigin(tester);
      final g = await tester.startGesture(
          tester.getCenter(handleF(OrbitKnob.orbitGap)));
      await tester.pump(const Duration(milliseconds: 20));
      await g.moveBy(const Offset(0, -20));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await g.moveBy(const Offset(0, -12)); // grow og → overhang grows
        await tester.pump();
        expect(canvasOrigin(tester).dy, closeTo(originBefore.dy, 1.0),
            reason: 'content top pinned, no forced scroll (step ${i + 1})');
      }
      await g.up();
      await tester.pump();
      await settle(tester);
      expect(canvasOrigin(tester).dy, closeTo(originBefore.dy, 1.0),
          reason: 'no ballistic settle after release');
      expect(tester.takeException(), isNull);
    });

    // QA follow-up (finding 3): the bubble stays PRESENT while its armed
    // handle is band-hidden (TC-198-71 contract) but must clamp into the
    // surface band instead of painting past it.
    testWidgets(
        'TC-198F-28 armed bubble clamps to the surface band while its handle is off-band',
        (tester) async {
      await tester.pumpWidget(host(_friends(80)));
      await settle(tester);
      await expandBadge(tester);
      await tester.dragFrom(const Offset(60, 300), const Offset(0, -500));
      await settle(tester, count: 4);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(handleF(OrbitKnob.spacingScale), warnIfMissed: false);
      await tester.pump();
      expect(bubbleF(), findsOneWidget);

      // Scroll back to the top: sp exits the band; bubble present AND inside.
      await tester.dragFrom(const Offset(60, 300), const Offset(0, 600));
      await settle(tester, count: 4);
      expect(handleF(OrbitKnob.spacingScale), findsNothing);
      expect(bubbleF(), findsOneWidget,
          reason: 'armed state survives (TC-198-71 contract)');
      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final b = tester.getRect(bubbleF());
      expect(b.bottom, lessThanOrEqualTo(surface.bottom + 0.1),
          reason: 'bubble never paints past the surface bottom');
      expect(b.top, greaterThanOrEqualTo(surface.top - 0.1),
          reason: 'bubble never paints past the surface top');
      await settle(tester);
    });

    testWidgets(
        'TC-198F-25 z-order: handles win pointer events over underlying seats',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await longPressBg(tester);
      await settle(tester);

      // friend0's ring-1 seat sits exactly at 12 o'clock — the av handle's
      // anchor. Tapping there must arm the handle, never open a chat and never
      // end the session (node-tap-in-edit is tap-away anyway).
      final expected = expectedCenter(
          tester, OrbitKnob.avatarScale, g0, 8, expanded: false);
      expect(
          (tester.getCenter(handleF(OrbitKnob.avatarScale)) - expected)
              .distance,
          lessThan(2.0));
      await tester.tapAt(expected);
      await tester.pump();
      expect(bubbleF(), findsOneWidget, reason: 'the handle won the tap');
      expect(tappedFriends, isEmpty, reason: 'no chat opened');
      expect(bannerF(), findsOneWidget, reason: 'session did not end');
      await settle(tester);
    });
  });

  // ==========================================================================
  // 201 — element identity + find UX (find-pill remount/size/avatar +
  // label-toggle avatar blink). All rows extend this GROUP_TESTS-pinned suite.
  // ==========================================================================
  group('201 — element identity + find UX (TC-201)', () {
    // TC-201-01 — the find TextField element survives an edit enter AND exit.
    testWidgets('TC-201-01 find TextField State survives edit enter and exit',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      final s1 = tester.state(find.byType(EditableText));

      // Edit enters — banner/Reset/handle-layer Positioneds are inserted BEFORE
      // the find slots in the outer Stack. Unkeyed → the pill's slot is stolen
      // and the EditableText deactivates (focus/IME drop).
      await longPressBg(tester);
      await tester.pump();
      expect(bannerF(), findsOneWidget, reason: 'edit session active');
      expect(identical(tester.state(find.byType(EditableText)), s1), isTrue,
          reason: 'edit-enter must not remount the find TextField');

      // Exit edit via a background tap WHILE editing: _onBackgroundTap ends the
      // edit FIRST and leaves find open (the query-clearing else-if is not hit).
      await tapAwayBg(tester);
      expect(bannerF(), findsNothing, reason: 'edit ended');
      expect(find.byType(EditableText), findsOneWidget,
          reason: 'find stays open after the edit exit');
      expect(identical(tester.state(find.byType(EditableText)), s1), isTrue,
          reason: 'edit-exit must not remount the find TextField');
      await settle(tester);
    });

    // TC-201-02 — the find TextField survives the chips empty↔non-empty edges.
    testWidgets(
        'TC-201-02 find TextField State survives the chips empty and non-empty edges',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      final s1 = tester.state(find.byType(EditableText));

      // empty → non-empty: the chip strip Positioned is inserted before the pill.
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsOneWidget);
      expect(identical(tester.state(find.byType(EditableText)), s1), isTrue,
          reason: 'chips appearing must not remount the find TextField');

      // non-empty → empty: the chip strip is removed again (reverse edge).
      await tester.enterText(find.byType(TextField), 'zzzzz');
      await tester.pump();
      expect(find.byKey(const ValueKey('orbit-find-chip-0')), findsNothing);
      expect(identical(tester.state(find.byType(EditableText)), s1), isTrue,
          reason: 'chips disappearing must not remount the find TextField');
      await settle(tester);
    });

    // TC-201-03 — the expanded pill is a full-width, >=48-high bar.
    testWidgets('TC-201-03 expanded find pill is a full-width >=48-high bar',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      final s = tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final r = tester.getRect(find.byKey(const ValueKey('orbit-find-pill')));
      expect(r.left - s.left, closeTo(16, 2), reason: 'left inset 16');
      expect(s.right - r.right, closeTo(16, 2), reason: 'right inset 16');
      expect(r.height, greaterThanOrEqualTo(48), reason: 'a >=48-high bar');

      // Non-armed pill x chip-strip disjointness (the F18 sweep runs armed-only,
      // leaving the idle-state slack unpinned).
      await tester.enterText(find.byType(TextField), 'friend');
      await tester.pump();
      final pill =
          tester.getRect(find.byKey(const ValueKey('orbit-find-pill')));
      final chip0 =
          tester.getRect(find.byKey(const ValueKey('orbit-find-chip-0')));
      expect(pill.overlaps(chip0), isFalse,
          reason: 'the widened pill clears the chip strip while idle');
      await settle(tester);
    });

    // TC-201-05 — a friend find chip shows the member's avatar.
    testWidgets('TC-201-05 friend find chip shows the member avatar',
        (tester) async {
      await tester.pumpWidget(
          host(<OrbitItem>[..._friends(5), _group('Book Club')]));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend0');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('orbit-find-chip-0')),
          matching: find.byType(UserAvatar),
        ),
        findsOneWidget,
        reason: 'the friend chip renders a UserAvatar, not name-only text',
      );
      await settle(tester);
    });

    // TC-201-06 — a group find chip shows the group avatar.
    testWidgets('TC-201-06 group find chip shows the group avatar',
        (tester) async {
      await tester.pumpWidget(
          host(<OrbitItem>[..._friends(5), _group('Book Club')]));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'book');
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('orbit-find-chip-5')),
          matching: find.byType(GroupAvatar),
        ),
        findsOneWidget,
        reason: 'the group chip renders a GroupAvatar',
      );
      await settle(tester);
    });

    // TC-201-07 — four long-name chips lay out without overflow.
    testWidgets('TC-201-07 four long-name chips lay out without overflow',
        (tester) async {
      final longName = 'z' * 38; // exceeds any sane chip width
      final items = <OrbitItem>[
        for (var i = 0; i < 4; i++)
          OrbitFriendItem(OrbitFriend(
            contact: ContactModel(
              peerId: 'peer-long-$i',
              publicKey: 'pk-$i',
              rendezvous: '/ip4/127.0.0.1/tcp/500$i',
              username: 'match$longName$i',
              signature: 'sig-$i',
              scannedAt: '2024-01-01T00:00:00Z',
            ),
            messageCount: i,
            lastMessageTimestamp: '2024-01-01T00:00:00Z',
          )),
      ];
      await tester.pumpWidget(host(items));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'match');
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'four long-name chips must not overflow the strip');
      final label = tester.widget<Text>(find.descendant(
        of: find.byKey(const ValueKey('orbit-find-chip-0')),
        matching: find.text('match${longName}0'),
      ));
      expect(label.overflow, TextOverflow.ellipsis,
          reason: 'chip label ellipsises');
      expect(
        find.ancestor(
          of: find.text('match${longName}0'),
          matching: find.byType(Flexible),
        ),
        findsWidgets,
        reason: 'chip label sits inside a Flexible',
      );
      await settle(tester);
    });

    // TC-201-08 — the label double-tap does not remount orbit nodes.
    testWidgets('TC-201-08 label double-tap does not remount orbit nodes',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      final before =
          tester.stateList<State>(find.byType(OrbitalAvatar)).toList();

      await doubleTapBg(tester); // labels on
      await tester.pump();
      final afterOn =
          tester.stateList<State>(find.byType(OrbitalAvatar)).toList();
      expect(afterOn.length, before.length);
      for (var i = 0; i < before.length; i++) {
        expect(identical(before[i], afterOn[i]), isTrue,
            reason: 'node $i must not re-inflate on the label toggle');
      }

      await doubleTapBg(tester); // labels off
      await tester.pump();
      final afterOff =
          tester.stateList<State>(find.byType(OrbitalAvatar)).toList();
      for (var i = 0; i < before.length; i++) {
        expect(identical(before[i], afterOff[i]), isTrue,
            reason: 'node $i must not re-inflate on the label toggle-off');
      }
      await settle(tester);
    });

    // TC-201-09 — the OverflowBadge survives label toggle + arc expand/collapse.
    testWidgets(
        'TC-201-09 OverflowBadge survives label toggle and arc expand and collapse',
        (tester) async {
      await tester.pumpWidget(host(_friends(20)));
      await settle(tester);
      final b1 = tester.state(find.byType(OverflowBadge));

      await doubleTapBg(tester); // labels on
      await tester.pump();
      expect(identical(tester.state(find.byType(OverflowBadge)), b1), isTrue,
          reason: 'badge must not re-inflate on the label toggle');

      await tester.tap(find.byType(OverflowBadge)); // expand arcs
      await settle(tester);
      expect(identical(tester.state(find.byType(OverflowBadge)), b1), isTrue,
          reason: 'badge must not re-inflate on arc expand');

      await tester.tap(find.byType(OverflowBadge)); // collapse arcs
      await settle(tester);
      expect(identical(tester.state(find.byType(OverflowBadge)), b1), isTrue,
          reason: 'badge must not re-inflate on arc collapse');
      await settle(tester);
    });

    // TC-201-11 — the collapsed find pill is a 44px tap target.
    testWidgets('TC-201-11 collapsed find pill is a 44px tap target',
        (tester) async {
      await tester.pumpWidget(host(_friends(8)));
      await settle(tester);
      final size =
          tester.getSize(find.byKey(const ValueKey('orbit-find-pill')));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      await settle(tester);
    });

    // TC-201-14 — a non-zero bottomClearance lifts the WHOLE find/edit stack by
    // a uniform amount and must NOT collapse the staggered bands. Regression:
    // `max(base, clearance)` pinned the small-base elements (pill 40 / steppers
    // 28) up to the clearance, overlapping the chip strip / each other whenever
    // the host clearance (58-88 in persistent nav) exceeded those bases.
    testWidgets('TC-201-14 bottomClearance preserves the staggered bottom bands',
        (tester) async {
      await tester.pumpWidget(host(_friends(20), bottomClearance: 88));
      await settle(tester);
      await expandBadge(tester);
      await longPressBg(tester);
      await settle(tester);
      await tester.tap(handleF(OrbitKnob.orbitGap), warnIfMissed: false);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('orbit-find-pill')));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'friend1');
      await tester.pump();

      final surface =
          tester.getRect(find.byType(InnerCircleInteractiveSurface));
      final chipKeys = [
        for (final el in find
            .byWidgetPredicate((w) =>
                w.key is ValueKey<String> &&
                (w.key! as ValueKey<String>)
                    .value
                    .startsWith('orbit-find-chip-'))
            .evaluate())
          (el.widget.key! as ValueKey<String>).value,
      ];
      expect(chipKeys.length, greaterThanOrEqualTo(2));
      final rects = <String, Rect>{
        'decrease': tester
            .getRect(find.byKey(const ValueKey('orbit-edit-step-decrease'))),
        'increase': tester
            .getRect(find.byKey(const ValueKey('orbit-edit-step-increase'))),
        'pill': tester.getRect(find.byKey(const ValueKey('orbit-find-pill'))),
        for (final k in chipKeys) k: tester.getRect(find.byKey(ValueKey(k))),
      };
      final names = rects.keys.toList();
      for (var i = 0; i < names.length; i++) {
        for (var j = i + 1; j < names.length; j++) {
          expect(rects[names[i]]!.overlaps(rects[names[j]]!), isFalse,
              reason: '${names[i]} x ${names[j]} disjoint under clearance');
        }
      }
      // The lowest band (steppers) sits at/above the clearance floor.
      expect(surface.bottom - rects['decrease']!.bottom,
          greaterThanOrEqualTo(88 - 2));
      await settle(tester);
    });
  });
}
