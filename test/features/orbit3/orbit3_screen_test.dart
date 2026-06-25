import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_mock_chat_screen.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_mock_data.dart';
import 'package:flutter_app/features/orbit3/presentation/screens/orbit3_screen.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_arch_panel.dart';
import 'package:flutter_app/features/orbit3/presentation/widgets/orbit3_one_circle.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

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
    // Measure the gap against the circle BOX top (not its inset ring avatars) so
    // deleting the SizedBox(16) spacer is actually detectable (167 review nit).
    final circleBoxTop = minTop(find.byType(Orbit3OneCircle));
    expect(circleBoxTop - arcsBottom, inInclusiveRange(12.0, 30.0),
        reason: 'the arch→circle gap is ~23px (7px row remainder + 16px spacer)');
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

    expect(maxSize(), 38.0); // Orbit-parity ring 0 at scale 1.0

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-inc')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxSize(), greaterThan(38.0)); // bigger

    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-dec')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.byKey(const ValueKey('orbit3-avatar-size-dec')));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 2400));
    expect(maxSize(), lessThan(38.0)); // smaller than the 1.0 baseline
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
