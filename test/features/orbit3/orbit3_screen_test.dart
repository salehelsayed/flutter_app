import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_mock_chat_screen.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_dimension_preferences_use_cases.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_mock_data.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_arch_layout.dart';
import 'package:flutter_app/features/orbit3/domain/orbit3_dimension_preferences.dart';
import 'package:flutter_app/features/orbit3/presentation/screens/orbit3_screen.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_arch_panel.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_one_circle.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../core/secure_storage/fake_secure_key_store.dart';

void main() {
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(440, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  Widget wrap() => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Orbit3Screen(userPeerId: 'me-peer'),
      );

  // Pump enough to drain the staggered OrbitalAvatar entrance timers
  // (globalIndex * 40ms) so none stay pending at teardown.
  Future<void> settle(WidgetTester tester, {int ms = 800}) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
  }

  // Cycle the population chip until [target] is displayed, then drain timers.
  Future<void> goTo(WidgetTester tester, String target) async {
    for (var i = 0; i < 6; i++) {
      if (find.text(target).evaluate().isNotEmpty) break;
      await tester.tap(find.byKey(const ValueKey('orbit3-population-cycler')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 2400));
  }

  String firstFriendName(int pop) =>
      Orbit3MockData.build(count: pop).firstWhere((it) => !it.isGroup).displayName;

  Finder expandToggle() => find.byKey(const ValueKey('orbit3-expand-toggle'));
  Finder archOverflow() => find.byKey(const ValueKey('orbit3-arch-overflow'));
  Finder archPanel() => find.byKey(const ValueKey('orbit3-arch-panel'));

  // Tapping the arch opens the overflow panel. The arch sits under the
  // circle-wide double-tap detector, so its onTap fires one kDoubleTapTimeout
  // (~300ms) late; pump that out, THEN drain the panel avatars' staggered
  // entrance timers (globalIndex * 40ms) before any teardown.
  Future<void> openArch(WidgetTester tester) async {
    await tester.tap(archOverflow());
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 2400));
  }

  // A short surface forces the arc band to fill (so the no-overlap geometry and
  // cap+scroll are exercised, as on a real phone with a nav bar + safe areas).
  void useShortSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  // ARCH avatars only — descendants of the arc rows, NOT the circle (which now
  // lives inside the same scroll surface under archPanel()).
  Finder archAvatars() => find.descendant(
      of: find.byType(Orbit3ArcRow), matching: find.byType(OrbitalAvatar));
  Finder circleAvatars() => find.descendant(
      of: find.byType(Orbit3OneCircle), matching: find.byType(OrbitalAvatar));

  double maxBottom(Finder f) {
    var m = double.negativeInfinity;
    for (final e in f.evaluate()) {
      final box = e.renderObject! as RenderBox;
      final b = box.localToGlobal(Offset(0, box.size.height)).dy;
      if (b > m) m = b;
    }
    return m;
  }

  double minTop(Finder f) {
    var m = double.infinity;
    for (final e in f.evaluate()) {
      final box = e.renderObject! as RenderBox;
      final t = box.localToGlobal(Offset.zero).dy;
      if (t < m) m = t;
    }
    return m;
  }

  testWidgets('renders ONLY the One Circle surface — no template selector, '
      'Messages, Manage, or floating scatter', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(Orbit3OneCircle), findsOneWidget);
    expect(find.text('Gravity'), findsNothing);
    expect(find.text('Tiered'), findsNothing);
    expect(find.text('One Circle'), findsNothing);
    expect(find.text('Messages'), findsNothing);
  });

  // ----- request #1: Orbit-parity fixed sizing -----

  testWidgets('avatars are Orbit-parity fixed sizes (ring1 38px, ring2 30px) '
      'and do not shrink with population', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13'); // two full rings, friends-only

    final sizes = tester
        .widgetList<OrbitalAvatar>(find.byType(OrbitalAvatar))
        .map((a) => a.size)
        .toSet();
    // Exactly the two Orbit ring sizes — no auto-shrink packing.
    expect(sizes, {38.0, 30.0});
  });

  // ----- request #2: sequential ring fill + expand -----

  testWidgets('starts with ONE ring around You until it is full (pop 5)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '5');

    expect(find.byType(OrbitalAvatar), findsNWidgets(5)); // all on ring 1
    expect(expandToggle(), findsNothing); // nothing hidden yet
    expect(archOverflow(), findsNothing); // overflow 0 → no arch
    // all five are the inner-ring size → a single ring
    final sizes = tester
        .widgetList<OrbitalAvatar>(find.byType(OrbitalAvatar))
        .map((a) => a.size)
        .toSet();
    expect(sizes, {38.0});
  });

  testWidgets('two full rings (pop 13) show everyone with NO expand arrow',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13');

    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // 5 + 8, friends-only
    expect(expandToggle(), findsNothing); // both rings full, nothing beyond
    expect(archOverflow(), findsNothing); // overflow 0 → no arch
  });

  testWidgets('past two rings (pop 24) shows the ARCH (+11) above the circle, '
      'NOT an in-ring expand node', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');

    // Inner circle stays at two rings (13) and never grows a third.
    expect(find.byType(OrbitalAvatar), findsNWidgets(13));
    expect(expandToggle(), findsNothing); // overflow lives on the arch now
    expect(archOverflow(), findsOneWidget);
    expect(find.text('+11'), findsOneWidget); // 24 − 13 overflow
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('tapping the arch opens the arc panel; a member tap opens chat',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');

    expect(archPanel(), findsNothing);
    await openArch(tester);

    expect(archPanel(), findsOneWidget);
    // The panel scrolls (you can scroll up for more rows).
    expect(
      find.descendant(of: archPanel(), matching: find.byType(Scrollable)),
      findsWidgets,
    );
    // At least the first arc row is laid out.
    expect(find.byKey(const ValueKey('orbit3-arch-arc-row-0')), findsOneWidget);

    // Tapping a panel member opens THAT member's chat.
    final panelAvatar = archAvatars();
    expect(panelAvatar, findsWidgets);
    await tester.tap(panelAvatar.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pop 50 arch shows +37; tapping opens the bottom-anchored panel',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');

    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // circle stays at 13
    expect(find.text('+37'), findsOneWidget); // 50 − 13

    await openArch(tester);
    expect(archPanel(), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit3-arch-arc-row-0')), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pop 50 expanded arcs never overlap the inner circle',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    expect(archAvatars(), findsWidgets);
    expect(circleAvatars(), findsWidgets);
    final arcsBottom = maxBottom(archAvatars());
    final circleTop = minTop(circleAvatars());
    expect(arcsBottom, lessThanOrEqualTo(circleTop + 0.5),
        reason: 'arcs bottom $arcsBottom must stay above circle top $circleTop');
    // The arches hug the circle (168 extension) — the lowest arch sits near the
    // (snug) box top, never buried deep inside it.
    final circleBoxTop = minTop(find.byType(Orbit3OneCircle));
    expect(circleBoxTop - arcsBottom, greaterThan(-20.0),
        reason: 'the lowest arch is not buried inside the circle box');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('no overlap holds when avatars are scaled up', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    // Scale members up — the geometry that worsens the overlap the most.
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    await openArch(tester);

    final arcsBottom = maxBottom(archAvatars());
    final circleTop = minTop(circleAvatars());
    expect(arcsBottom, lessThanOrEqualTo(circleTop + 0.5),
        reason: 'no overlap must hold at avatarScale 1.4');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('on a short screen the arcs cap & scroll, bottom-anchored',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    // Nearest arc row is present and a Scrollable exists.
    expect(find.byKey(const ValueKey('orbit3-arch-arc-row-0')), findsOneWidget);
    final scrollable = find
        .descendant(of: archPanel(), matching: find.byType(Scrollable))
        .first;
    expect(scrollable, findsOneWidget);
    // More arcs than fit → the band actually scrolls (not compressed to fit).
    final pos = tester.state<ScrollableState>(scrollable).position;
    expect(pos.maxScrollExtent, greaterThan(0.0),
        reason: 'short screen → arcs exceed the band → scrollable');
    // Bottom-anchored: row 0 (nearest the circle) sits BELOW row 1.
    final r0 =
        tester.getCenter(find.byKey(const ValueKey('orbit3-arch-arc-row-0')));
    final r1 =
        tester.getCenter(find.byKey(const ValueKey('orbit3-arch-arc-row-1')));
    expect(r0.dy, greaterThan(r1.dy));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the inner circle and the arches live in ONE scrollable surface',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    // Exactly one Scrollable hosts the whole expanded surface.
    expect(find.descendant(of: archPanel(), matching: find.byType(Scrollable)),
        findsOneWidget);

    // A circle avatar and an arch avatar resolve to the SAME ScrollableState.
    final circleSc = tester
        .element(circleAvatars().first)
        .findAncestorStateOfType<ScrollableState>();
    final archSc = tester
        .element(archAvatars().first)
        .findAncestorStateOfType<ScrollableState>();
    expect(circleSc, isNotNull,
        reason: 'the inner circle must live inside the scroll surface');
    expect(identical(circleSc, archSc), isTrue,
        reason: 'circle + arches share ONE scroll surface');

    // Opened anchored at the bottom (on the circle).
    final pos = circleSc!.position;
    expect(pos.maxScrollExtent, greaterThan(0.0));
    expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0));

    // One drag translates BOTH the circle and the arches together.
    final beforeCircle = tester.getCenter(circleAvatars().first);
    final beforeArch = tester.getCenter(archAvatars().first);
    await tester.drag(find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
        const Offset(0, 90)); // toward the top — opened anchored at the bottom
    await tester.pump();
    final dCircle =
        tester.getCenter(circleAvatars().first).dy - beforeCircle.dy;
    final dArch = tester.getCenter(archAvatars().first).dy - beforeArch.dy;
    expect((dCircle - dArch).abs(), lessThan(1.5),
        reason: 'circle + arches move together (one surface)');
    expect(dCircle.abs(), greaterThan(5.0),
        reason: 'the page actually scrolled');
    await tester.pump(const Duration(milliseconds: 2400)); // drain entrance timers
  });

  testWidgets('the pinned controls stay fixed while the surface scrolls',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    Offset centreOf(String key) =>
        tester.getCenter(find.byKey(ValueKey(key)));
    final collapseBefore = centreOf('orbit3-arch-collapse');
    final stepperBefore = centreOf('orbit3-avatar-size-inc');
    final circleBefore = tester.getCenter(circleAvatars().first);

    await tester.drag(find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
        const Offset(0, 90));
    await tester.pump();

    // The pinned controls do NOT move; the scroll surface (circle) does.
    expect((centreOf('orbit3-arch-collapse') - collapseBefore).distance,
        lessThan(1.0),
        reason: 'collapse pill is pinned, not in the scroll');
    expect((centreOf('orbit3-avatar-size-inc') - stepperBefore).distance,
        lessThan(1.0),
        reason: 'size stepper is pinned, not in the scroll');
    expect((tester.getCenter(circleAvatars().first).dy - circleBefore.dy).abs(),
        greaterThan(5.0),
        reason: 'the circle (inside the scroll) moved');
    await tester.pump(const Duration(milliseconds: 2400)); // drain timers
  });

  // Outer-ring radius = the farthest circle avatar centre from the circle box
  // centre. Avatar SIZE never moves a centre, so this isolates ring SPACING.
  double ringRadius(WidgetTester tester) {
    final cc = tester.getCenter(find.byType(Orbit3OneCircle));
    var maxD = 0.0;
    for (final e in circleAvatars().evaluate()) {
      final box = e.renderObject! as RenderBox;
      final c = box.localToGlobal(box.size.center(Offset.zero));
      final d = (c - cc).distance;
      if (d > maxD) maxD = d;
    }
    return maxD;
  }

  double maxCircleAvatarSize(WidgetTester tester) => tester
      .widgetList<OrbitalAvatar>(circleAvatars())
      .map((a) => a.size)
      .reduce((a, b) => a > b ? a : b);

  double archPitch(WidgetTester tester) {
    final r0 = tester.getCenter(find.byKey(const ValueKey('orbit3-arch-arc-row-0')));
    final r1 = tester.getCenter(find.byKey(const ValueKey('orbit3-arch-arc-row-1')));
    return (r0.dy - r1.dy).abs();
  }

  testWidgets('spacing stepper widens the orbit rings AND the arch row pitch '
      '(C1)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    final d0 = ringRadius(tester);
    final p0 = archPitch(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-spacing-inc')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 2400));
    expect(ringRadius(tester), greaterThan(d0 + 1),
        reason: 'spacing-inc widened the orbit rings');
    expect(archPitch(tester), greaterThan(p0 + 1),
        reason: 'spacing-inc widened the arch row pitch');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('spacing stepper does NOT change avatar size; size stepper does '
      'NOT change ring radius (C1 orthogonality)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    final size0 = maxCircleAvatarSize(tester);
    final r0 = ringRadius(tester);
    await tester.tap(find.byKey(const ValueKey('orbit3-spacing-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxCircleAvatarSize(tester), size0,
        reason: 'spacing does not touch avatar size');
    expect(ringRadius(tester), greaterThan(r0),
        reason: 'spacing widened the ring');
    final r1 = ringRadius(tester);
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxCircleAvatarSize(tester), greaterThan(size0),
        reason: 'size stepper grew the avatars');
    expect((ringRadius(tester) - r1).abs(), lessThan(2.0),
        reason: 'avatar size does not move ring centres');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('expanded group members render as OrbitalAvatars and stay adjacent '
      '(C2)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    // 35 friends + 2 groups, all OrbitalAvatars (was 35 + 2 flat glyphs).
    expect(archAvatars(), findsNWidgets(37));
    final groupKeys = find.byWidgetPredicate((w) =>
        w.key is ValueKey &&
        '${(w.key as ValueKey).value}'.startsWith('orbit3-arch-group-'));
    expect(groupKeys, findsNWidgets(2));
    final gc = groupKeys.evaluate().map((e) {
      final box = e.renderObject! as RenderBox;
      return box.localToGlobal(box.size.center(Offset.zero));
    }).toList();
    // Same arch row (within row height — a row apart would be ~rowHeight) and
    // ADJACENT (one slot apart, not the same or far apart). The small y delta is
    // the arc dome curve between neighbouring columns.
    expect((gc[0].dy - gc[1].dy).abs(), lessThan(25.0),
        reason: 'the two groups share one arch row');
    final dx = (gc[0].dx - gc[1].dx).abs();
    expect(dx, greaterThan(1.0), reason: 'distinct, neighbouring slots');
    // One slot apart (a sparse last row spreads ~80px/slot); a 2-slot gap (~165)
    // would mean a friend sits between the groups.
    expect(dx, lessThan(120.0), reason: 'adjacent (consecutive slots)');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('opening the arch does NOT re-animate the inner-circle avatars '
      '(C4)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    // Open and pump only briefly (NOT a full drain).
    await tester.tap(archOverflow());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final tf = tester.widget<Transform>(find
        .descendant(of: circleAvatars().first, matching: find.byType(Transform))
        .first);
    expect(tf.transform.getMaxScaleOnAxis(), greaterThan(0.95),
        reason: 'inner circle stays full size (no re-entrance) on expand');
    await tester.pump(const Duration(milliseconds: 2400));
  });

  testWidgets('increasing spacing keeps the circle box square — avatars stay on '
      'the orbit (168 off-orbit fix)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    // Bump spacing to the max so the circle box exceeds the pane width.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-spacing-inc')));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 2400));
    final s = tester.getSize(find.byType(Orbit3OneCircle));
    expect(s.width, closeTo(s.height, 1.0),
        reason: 'a width-clamped (non-square) box offsets the painter centre '
            'from the avatar centre → avatars off the rings');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('curve stepper increases the arch dome amplitude (168 curve)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    double amplitude() {
      final ys = find
          .descendant(
              of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
              matching: find.byType(OrbitalAvatar))
          .evaluate()
          .map((e) {
        final box = e.renderObject! as RenderBox;
        return box.localToGlobal(box.size.center(Offset.zero)).dy;
      }).toList();
      return ys.reduce((a, b) => a > b ? a : b) -
          ys.reduce((a, b) => a < b ? a : b);
    }

    final a0 = amplitude();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-curve-inc')));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 2400));
    expect(amplitude(), greaterThan(a0 + 1),
        reason: 'more curve = a deeper arch dome');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('each arch row holds at most 7 avatars (168 7-per-arch fix)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    // row 0 is a FULL row → exactly 7 (was 8).
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
            matching: find.byType(OrbitalAvatar)),
        findsNWidgets(7));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('inner-circle avatars match the arch avatars in size (168)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    final circleSizes = tester
        .widgetList<OrbitalAvatar>(circleAvatars())
        .map((a) => a.size)
        .toSet();
    final archSize =
        tester.widgetList<OrbitalAvatar>(archAvatars()).first.size;
    expect(circleSizes.length, 1, reason: 'inner avatars are one uniform size');
    expect(circleSizes.first, closeTo(archSize, 0.01),
        reason: 'inner avatar size == arch avatar size');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the first arch starts close to the circle, like an extension '
      '(168)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    final clearance = minTop(circleAvatars()) - maxBottom(archAvatars());
    expect(clearance, greaterThan(0.0), reason: 'no overlap');
    expect(clearance, lessThan(30.0),
        reason: 'the first arch hugs the circle (extension)');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('per-arch stepper changes the avatars per arch row (168)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    int row0() => find
        .descendant(
            of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
            matching: find.byType(OrbitalAvatar))
        .evaluate()
        .length;
    final n0 = row0();
    await tester.tap(find.byKey(const ValueKey('orbit3-perrow-dec')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    final nDec = row0();
    expect(nDec, lessThan(n0), reason: 'fewer per arch');
    await tester.tap(find.byKey(const ValueKey('orbit3-perrow-inc')));
    await tester.tap(find.byKey(const ValueKey('orbit3-perrow-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(row0(), greaterThan(nDec), reason: 'more per arch');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('100-user population seats 100 and the arch opens + scrolls (C5)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '100');

    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // collapsed circle
    expect(find.text('+87'), findsOneWidget); // 100 − 13

    await openArch(tester);
    expect(archAvatars(), findsNWidgets(87)); // all overflow, incl. groups
    final scrollable = find
        .descendant(of: archPanel(), matching: find.byType(Scrollable))
        .first;
    expect(tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0.0));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 3000)); // drain ~100 timers
  });

  testWidgets('open arch shows a collapse button that closes to the circle',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    await openArch(tester);

    expect(find.byKey(const ValueKey('orbit3-arch-collapse')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('orbit3-arch-collapse')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));

    expect(archPanel(), findsNothing);
    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // back to the circle
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('avatar-size stepper grows then shrinks the circle avatars',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');

    double maxSize() => tester
        .widgetList<OrbitalAvatar>(find.byType(OrbitalAvatar))
        .map((a) => a.size)
        .reduce((a, b) => a > b ? a : b);

    // Pop 24 has overflow, so the collapsed circle keeps the EXPANDED uniform
    // arch-avatar size (36) rather than the 38px ring-0 parity (R3).
    expect(maxSize(), 36.0);

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxSize(), greaterThan(36.0)); // bigger

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-dec')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-dec')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxSize(), lessThan(36.0)); // smaller than the 1.0 baseline
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the arch panel honors the avatar-size scale (sibling surface)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');

    // Bump the size up while the panel is closed, then open it.
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    await openArch(tester);

    final panelMax = tester
        .widgetList<OrbitalAvatar>(
          find.descendant(of: archPanel(), matching: find.byType(OrbitalAvatar)),
        )
        .map((a) => a.size)
        .reduce((a, b) => a > b ? a : b);
    expect(panelMax, greaterThan(38.0)); // panel avatars scaled like the circle
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('cycling population keeps two rings, updates the arch count, and '
      'closes an open panel', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    await openArch(tester);
    expect(archPanel(), findsOneWidget);

    await goTo(tester, '50'); // cycle population
    expect(archPanel(), findsNothing); // panel auto-closed
    expect(find.text('+37'), findsOneWidget); // count updated
    expect(find.byType(OrbitalAvatar), findsNWidgets(13)); // still two rings
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- carried-over features (double-tap names, search, chat) -----

  testWidgets('double-tap over the orbit toggles names; single tap on a member '
      'opens that member\'s chat', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13');

    final name = firstFriendName(13);
    expect(find.text(name), findsOneWidget); // names default ON

    final centre = tester.getCenter(find.byType(Orbit3OneCircle));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(name), findsNothing); // toggled off

    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(name), findsOneWidget); // toggled back on

    // Single tap on a member opens the chat for THAT member.
    await tester.tap(find.byType(OrbitalAvatar).first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 350)); // > double-tap timeout
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(Orbit2MockChatScreen),
        matching: find.text(name),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('double-tap directly OVER a member also toggles names', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13');

    expect(find.text('You'), findsOneWidget);
    final member = tester.getCenter(find.byType(OrbitalAvatar).first);
    await tester.tapAt(member);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(member);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('You'), findsNothing);
    expect(find.byType(Orbit2MockChatScreen), findsNothing); // not a chat open
    await settle(tester);
  });

  testWidgets('names render AROUND the orbits (member + centre You) and hide',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13');

    final name = firstFriendName(13);
    expect(find.text(name), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('orbit3-names-toggle')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text(name), findsNothing);
    expect(find.text('You'), findsNothing);
    await settle(tester);
  });

  testWidgets('searching a member makes it glow', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '13');

    final friends =
        Orbit3MockData.build(count: 13).where((it) => !it.isGroup).toList();
    final target = friends.first;
    final other = friends[1];

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), target.displayName);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(ValueKey('inner-glow-${target.id}')), findsOneWidget);
    expect(find.byKey(ValueKey('inner-glow-${other.id}')), findsNothing);
    await settle(tester);
  });

  // ----- request #1: names on ALL avatars (arches included) -----

  testWidgets('arch avatars show names; a double-tap on the arches toggles '
      'them off and back on (R1)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    // An overflow member (past the 13 inner seats) only ever appears on the
    // arches, so its label proves arch names render.
    final overflowName = Orbit3MockData.build(count: 50)
        .skip(kOrbit3InnerSeats)
        .firstWhere((it) => !it.isGroup)
        .displayName;
    Finder archLabel() => find.descendant(
        of: find.byType(Orbit3ArcRow), matching: find.text(overflowName));
    expect(archLabel(), findsWidgets); // names default ON

    final row0 =
        tester.getCenter(find.byKey(const ValueKey('orbit3-arch-arc-row-0')));
    await tester.tapAt(row0);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(row0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(archLabel(), findsNothing); // double-tap over the arch hid the names

    await tester.tapAt(row0);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(row0);
    await tester.pump(const Duration(milliseconds: 400));
    expect(archLabel(), findsWidgets); // toggled back on
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- request #2: dotted connectors threading each arch -----

  testWidgets('each arch row paints dotted connectors between its avatars (R2)',
      (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
        matching: find.byKey(const ValueKey('orbit3-arch-connector')),
      ),
      findsOneWidget,
    );

    // Draw-proof: the painter actually emits dotted segments (not just mounted).
    final painter = tester
        .widget<CustomPaint>(find.descendant(
          of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
          matching: find.byKey(const ValueKey('orbit3-arch-connector')),
        ))
        .painter!;
    final canvas = _CountingCanvas();
    painter.paint(canvas, const Size(360, 60));
    expect(canvas.lines, greaterThan(0),
        reason: 'a full arch row draws dotted connector segments');
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- request #3: collapse keeps the tuned size (no jump) -----

  testWidgets('collapsing keeps the inner orbit at the tuned uniform size — no '
      'jump back to parity (R3)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24'); // overflow → collapsed mirrors the expanded sizing

    double maxCircle() => tester
        .widgetList<OrbitalAvatar>(circleAvatars())
        .map((a) => a.size)
        .reduce((a, b) => a > b ? a : b);

    // Collapsed: the uniform arch-avatar size (36), NOT the 38px ring-0 parity.
    final collapsed = maxCircle();
    expect(collapsed, closeTo(36.0, 0.01));

    // Expanded: the same size → opening/closing the arches causes no size jump.
    await openArch(tester);
    expect(maxCircle(), closeTo(collapsed, 0.01),
        reason: 'expanded inner-circle size == collapsed size');

    // Collapse again → still the tuned uniform size (it persisted).
    await tester.tap(find.byKey(const ValueKey('orbit3-arch-collapse')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxCircle(), closeTo(collapsed, 0.01));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('collapsed-overflow view does not RenderFlex-overflow on a short, '
      'wide surface even at max spacing (R3 layout)', (tester) async {
    tester.view.physicalSize = const Size(900, 380); // landscape-ish
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(wrap());
    await goTo(tester, '50'); // overflow → the collapsed-overflow Column path

    // Max spacing grows the snug box past the short pane height; Flexible must
    // bound it so the Column never overflows.
    for (var i = 0; i < 5; i++) {
      await tester.tap(find.byKey(const ValueKey('orbit3-spacing-inc')));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pump(const Duration(milliseconds: 2400));
    expect(tester.takeException(), isNull,
        reason: 'no RenderFlex overflow in the collapsed-overflow column');
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- request #4: a live numeric value on every +/- stepper -----

  testWidgets('every +/- stepper shows its live numeric value (R4)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24'); // steppers visible in the collapsed one-circle view

    String val(String key) =>
        tester.widget<Text>(find.byKey(ValueKey(key))).data!;

    // Defaults: scales read as a one-decimal multiplier, per-arch as a count.
    expect(val('orbit3-avatar-size-value'), '1.0×');
    expect(val('orbit3-spacing-value'), '1.0×');
    expect(val('orbit3-curve-value'), '1.0×');
    expect(val('orbit3-perrow-value'), '7');

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(val('orbit3-avatar-size-value'), '1.2×'); // +0.2 step

    await tester.tap(find.byKey(const ValueKey('orbit3-perrow-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(val('orbit3-perrow-value'), '8'); // +1 step
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- follow-up mods: no flash on names, bottom collapse, steady circle -----

  testWidgets('arch avatars + labels carry stable keys so showing names never '
      'shuffles/reloads them (Mod 1)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester); // names default ON → avatars AND labels present

    // Without these stable keys, toggling names interleaves the label
    // Positioneds and reconciliation reuses an avatar's element for a label —
    // swapping the avatar's underlying image (the "disappear then appear" flash
    // the user saw). Keyed by member id, each avatar/label stays bound to its
    // member, so showing names only ADDS labels and never disturbs the avatars.
    Finder keyed(String prefix) => find.byWidgetPredicate((w) =>
        w is Positioned &&
        w.key is ValueKey &&
        '${(w.key as ValueKey).value}'.startsWith(prefix));
    expect(keyed('orbit3-arch-av-'), findsWidgets);
    expect(keyed('orbit3-arch-lbl-'), findsWidgets);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('arch avatars bloom with the inner-circle entrance, NOT the '
      'rise-up slide (Mod 3)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await openArch(tester);
    final avs = tester.widgetList<OrbitalAvatar>(archAvatars());
    expect(avs, isNotEmpty);
    expect(avs.every((a) => a.riseUp == false), isTrue,
        reason: 'arches use the classic scale+fade, not the rise-up slide');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the collapse pill sits at the BOTTOM, below the inner circle '
      '(Mod 2)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    await openArch(tester);

    final collapseY =
        tester.getCenter(find.byKey(const ValueKey('orbit3-arch-collapse'))).dy;
    final circleY = tester.getCenter(find.byType(Orbit3OneCircle)).dy;
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    expect(collapseY, greaterThan(circleY),
        reason: 'collapse is below the inner circle, not pinned to the top');
    expect(screenH - collapseY, lessThan(120.0),
        reason: 'collapse rides the bottom band near the nav bar');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('expanding the arches does NOT shift the inner circle vertically '
      '(Mod 2 steady circle)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    final collapsedY = tester.getCenter(find.byType(Orbit3OneCircle)).dy;
    await openArch(tester);
    final expandedY = tester.getCenter(find.byType(Orbit3OneCircle)).dy;
    expect((expandedY - collapsedY).abs(), lessThan(20.0),
        reason: 'the inner circle stays put when the arches expand');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('with many arches, expanding prioritises them — lowest arch hugs '
      'the Collapse pill and the inner circle drops below the fold (Mod 2 '
      'arch-priority)', (tester) async {
    useShortSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '100'); // 87 overflow arches → fill the screen
    await openArch(tester);

    final collapseTop =
        tester.getRect(find.byKey(const ValueKey('orbit3-arch-collapse'))).top;
    final row0Bottom = maxBottom(find.descendant(
        of: find.byKey(const ValueKey('orbit3-arch-arc-row-0')),
        matching: find.byType(OrbitalAvatar)));

    // The lowest arch sits JUST above the Collapse pill (not buried, not off).
    expect(row0Bottom, lessThan(collapseTop + 1),
        reason: 'lowest arch clears the Collapse pill');
    expect(collapseTop - row0Bottom, lessThan(90.0),
        reason: 'lowest arch is near the Collapse pill');

    // The inner circle has slid below the fold (its avatars are below the pill).
    expect(minTop(circleAvatars()), greaterThan(collapseTop),
        reason: 'inner circle dropped below the fold to prioritise arches');
    await tester.pump(const Duration(seconds: 1));
  });

  // ----- dimension persistence + reset (plan 169) -----

  Widget wrapWithStore(FakeSecureKeyStore store) => MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Orbit3Screen(userPeerId: 'me-peer', secureKeyStore: store),
      );

  String stepperVal(WidgetTester tester, String key) =>
      tester.widget<Text>(find.byKey(ValueKey(key))).data!;

  testWidgets('mounts with a seeded store → all four steppers show the '
      'persisted values (169 load)', (tester) async {
    useTallSurface(tester);
    final store = FakeSecureKeyStore();
    await saveOrbit3DimensionPreferences(
      secureKeyStore: store,
      prefs: const Orbit3DimensionPreferences(
          avatarScale: 1.2, spacingScale: 1.2, curveScale: 1.5, perRow: 5),
    );
    await tester.pumpWidget(wrapWithStore(store));
    await settle(tester); // flush the fire-and-forget load + entrance timers

    // Default population (24) shows the steppers in the collapsed one-circle view.
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), '1.2×');
    expect(stepperVal(tester, 'orbit3-spacing-value'), '1.2×');
    expect(stepperVal(tester, 'orbit3-curve-value'), '1.5×');
    expect(stepperVal(tester, 'orbit3-perrow-value'), '5');
  });

  testWidgets('a changed knob persists across a fresh re-mount with the same '
      'store (169 durability)', (tester) async {
    useTallSurface(tester);
    final store = FakeSecureKeyStore();

    await tester.pumpWidget(wrapWithStore(store));
    await settle(tester);
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), '1.0×'); // fresh

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await settle(tester);
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), '1.2×'); // bumped+saved

    // Relaunch: tear the tree down, then mount a fresh screen on the SAME store.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pumpWidget(wrapWithStore(store));
    await settle(tester);
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), '1.2×',
        reason: 'the persisted value reconstructs on a fresh mount');
  });

  testWidgets('Reset restores all four defaults AND clears storage (169 reset)',
      (tester) async {
    useTallSurface(tester);
    final store = FakeSecureKeyStore();
    await tester.pumpWidget(wrapWithStore(store));
    await settle(tester);

    // Move every knob off its default.
    for (final k in const [
      'orbit3-avatar-size-inc',
      'orbit3-spacing-inc',
      'orbit3-curve-inc',
      'orbit3-perrow-inc',
    ]) {
      await tester.tap(find.byKey(ValueKey(k)));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await settle(tester);
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), isNot('1.0×'));

    // Reset.
    await tester.tap(find.byKey(const ValueKey('orbit3-reset-dimensions')));
    await tester.pump(const Duration(milliseconds: 60));
    await settle(tester);
    expect(stepperVal(tester, 'orbit3-avatar-size-value'), '1.0×');
    expect(stepperVal(tester, 'orbit3-spacing-value'), '1.0×');
    expect(stepperVal(tester, 'orbit3-curve-value'), '1.0×');
    expect(stepperVal(tester, 'orbit3-perrow-value'), '7');

    final stored = await tester.runAsync(
        () => store.read(Orbit3DimensionPreferences.storageKey));
    expect(stored, isNull, reason: 'reset clears the saved value');
  });

  // ----- constellation map: on-screen zoom controls -----

  testWidgets('constellation view shows ＋/－ zoom buttons that drive the zoom '
      'without error', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    // Switch from One Circle to the constellation map.
    await tester.tap(find.byKey(const ValueKey('orbit3-view-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit3-zoom-in')), findsOneWidget);
    expect(find.byKey(const ValueKey('orbit3-zoom-out')), findsOneWidget);

    // Zoom in (blooms avatars) and back out — no exceptions, drain any
    // entrance timers the revealed avatars schedule before teardown.
    await tester.tap(find.byKey(const ValueKey('orbit3-zoom-in')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2400));

    await tester.tap(find.byKey(const ValueKey('orbit3-zoom-out')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 2400));

    expect(tester.takeException(), isNull);
  });
}

/// A no-op [Canvas] that just counts drawLine calls, so a test can assert the
/// arch connector painter actually emits dotted segments (R2 draw-proof).
class _CountingCanvas implements Canvas {
  int lines = 0;

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines++;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
