import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_mock_chat_screen.dart';
import 'package:flutter_app/features/orbit3/application/orbit3_mock_data.dart';
import 'package:flutter_app/features/orbit3/presentation/screens/orbit3_screen.dart';
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
  int friendCount(int pop) =>
      Orbit3MockData.build(count: pop).where((it) => !it.isGroup).length;

  Finder expandToggle() => find.byKey(const ValueKey('orbit3-expand-toggle'));

  // The expand node sits under the circle-wide double-tap detector, so its onTap
  // fires one kDoubleTapTimeout (~300ms) late. Pump first to let the toggle fire
  // and rebuild, THEN drain the revealed avatars' staggered entrance timers
  // (globalIndex * 40ms, up to ~1.9s at the dense end) before any teardown.
  Future<void> tapExpand(WidgetTester tester) async {
    await tester.tap(expandToggle());
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 2400));
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
  });

  testWidgets('past two rings (pop 24) hides the rest behind an expand arrow; '
      'tapping it reveals the next ring(s)', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');

    // Collapsed: only the two inner rings (13 members) + an expand arrow.
    expect(find.byType(OrbitalAvatar), findsNWidgets(13));
    expect(expandToggle(), findsOneWidget);
    expect(find.text('+11'), findsOneWidget); // 24 − 13 hidden

    // Expand → the 3rd ring (and the 2 groups) appear; everyone is now seated.
    await tapExpand(tester);

    expect(find.byType(OrbitalAvatar), findsNWidgets(friendCount(24))); // 22
    for (final g in Orbit3MockData.build(count: 24).where((it) => it.isGroup)) {
      expect(find.byKey(ValueKey('orbit3-inner-group-${g.id}')), findsOneWidget);
    }
    // The node is now a collapse (up) arrow.
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

    // Collapse back to two rings.
    await tapExpand(tester);
    expect(find.byType(OrbitalAvatar), findsNWidgets(13));
  });

  testWidgets('cycling population resets to the collapsed two-ring view',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    await tapExpand(tester); // expand at 24
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget);

    await goTo(tester, '50'); // cycle population → collapses
    expect(find.byType(OrbitalAvatar), findsNWidgets(13));
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsNothing);
    expect(expandToggle(), findsOneWidget); // expand arrow again
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('expanding at the dense end (pop 50) seats EVERY member, '
      'no overlap', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '50');
    await tapExpand(tester);

    expect(find.byType(OrbitalAvatar), findsNWidgets(friendCount(50))); // 48
  });

  testWidgets('no two avatars overlap when a 3rd ring is shown (pop 24 expanded)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await goTo(tester, '24');
    await tapExpand(tester);

    final avatars = find.byType(OrbitalAvatar).evaluate().map((e) {
      final box = e.renderObject! as RenderBox;
      return (
        size: (e.widget as OrbitalAvatar).size,
        center: box.localToGlobal(box.size.center(Offset.zero)),
      );
    }).toList();

    for (var i = 0; i < avatars.length; i++) {
      for (var j = i + 1; j < avatars.length; j++) {
        final minGap = (avatars[i].size + avatars[j].size) / 2;
        expect((avatars[i].center - avatars[j].center).distance,
            greaterThanOrEqualTo(minGap - 0.5),
            reason: 'avatars $i and $j overlap');
      }
    }
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
