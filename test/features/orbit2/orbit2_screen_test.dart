import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/orbit2/application/orbit2_mock_data.dart';
import 'package:flutter_app/features/orbit2/domain/models/orbit2_inner_item.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_mock_chat_screen.dart';
import 'package:flutter_app/features/orbit2/presentation/screens/orbit2_screen.dart';
import 'package:flutter_app/features/orbit2/presentation/widgets/floating_avatar.dart';
import 'package:flutter_app/features/orbit2/presentation/widgets/orbit2_group_node.dart';
import 'package:flutter_app/features/orbit2/presentation/widgets/orbit2_inbox_view.dart';
import 'package:flutter_app/features/orbit2/presentation/widgets/orbit2_inner_circle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_avatar.dart';
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
        home: const Orbit2Screen(userPeerId: 'me-peer'),
      );

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder avatarByIndex(int i) =>
      find.byKey(ValueKey('floating-avatar-orbit2-canvas-$i'));

  testWidgets('renders inner circle + friends + groups; no message surface',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(Orbit2InnerCircle), findsOneWidget);
    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    expect(find.byType(Orbit2GroupNode), findsNWidgets(2));
    // #2 — no Simulate / incoming-message surface.
    expect(find.text('Simulate'), findsNothing);
  });

  testWidgets('#1 the inner circle defaults to the bottom', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    final inner = tester.getCenter(find.byType(Orbit2InnerCircle));
    final screen = tester.getSize(find.byType(Orbit2Screen));
    expect(inner.dy, greaterThan(screen.height * 0.55)); // bottom half
    // floating avatars sit above it
    expect(tester.getCenter(avatarByIndex(1)).dy, lessThan(inner.dy));
  });

  testWidgets('all floating avatars are one size', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);
    expect(tester.getSize(avatarByIndex(0)).width,
        tester.getSize(avatarByIndex(1)).width);
  });

  testWidgets('tapping a floating avatar opens the mock chat', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);
    await tester.tap(avatarByIndex(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
  });

  testWidgets('tapping a group opens the group chat', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('group-node-orbit2-group-work')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
    expect(find.text('Work Crew'), findsOneWidget);
  });

  testWidgets('#6 dropping a friend on another separates them (no merge)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    final a = tester.getCenter(avatarByIndex(1));
    final b = tester.getCenter(avatarByIndex(2));
    await tester.drag(avatarByIndex(1), b - a); // drop friend 1 onto friend 2
    await settle(tester);

    // No merge: counts unchanged.
    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    expect(find.byType(Orbit2GroupNode), findsNWidgets(2));
    // No overlap: they're pushed apart (≥ r1+r2).
    final c1 = tester.getCenter(avatarByIndex(1));
    final c2 = tester.getCenter(avatarByIndex(2));
    expect((c1 - c2).distance, greaterThanOrEqualTo(40.0));
  });

  testWidgets('#4 double-tap toggles name labels', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Idris'), findsOneWidget); // a name label

    // Double-tap an empty spot on the canvas (left edge, clear of avatars/dock).
    const empty = Offset(8, 340);
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await settle(tester);
    expect(find.text('Idris'), findsNothing); // names hidden

    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await settle(tester);
    expect(find.text('Idris'), findsOneWidget); // restored
  });

  testWidgets('#5 searching an inner-circle member makes it glow', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.byIcon(Icons.search_rounded)); // open search
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'Layla'); // an inner member
    await settle(tester);

    expect(find.byKey(const ValueKey('inner-glow-orbit2-inner-0')), findsOneWidget);
    // a non-matching member is not glowing
    expect(find.byKey(const ValueKey('inner-glow-orbit2-inner-1')), findsNothing);
  });

  testWidgets('#3 expand control is a compact node that grows/shrinks the cluster',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    final original = tester.getSize(find.byType(Orbit2InnerCircle)).width;
    expect(find.text('+3'), findsOneWidget);
    // compact, not a full-width banner
    final node = find.ancestor(
        of: find.text('+3'), matching: find.byType(Container)).first;
    expect(tester.getSize(node).width, lessThanOrEqualTo(36.0));

    await tester.tap(find.text('+3')); // expand
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(Orbit2InnerCircle)).width,
        greaterThan(original));
    expect(find.text('+3'), findsNothing); // now a chevron

    // collapse via the chevron node
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded),
        findsWidgets); // node now shows a chevron
    await tester.tap(find.byKey(const ValueKey('inner-expand-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(Orbit2InnerCircle)).width, original);
  });

  testWidgets('promote: long-press-carry a friend onto the cluster', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    final from = tester.getCenter(avatarByIndex(1));
    final onto = tester.getCenter(find.byType(Orbit2InnerCircle));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(onto);
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloatingAvatar), findsNWidgets(9));
    expect(find.textContaining('added to your inner circle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // drain snackbar/entrance timers
  });

  testWidgets('remove: long-press-drag an inner member out', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    final member = find.byType(OrbitalAvatar).first;
    final from = tester.getCenter(member);
    final inner = tester.getCenter(find.byType(Orbit2InnerCircle));
    final out = Offset(inner.dx, inner.dy - 320); // far above (outside the zone)

    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(out);
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloatingAvatar), findsNWidgets(11));
    expect(find.textContaining('removed from your inner circle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // drain snackbar/entrance timers
  });

  testWidgets('the layout selector switches templates', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Gravity'), findsOneWidget);
    await tester.tap(find.text('Gravity'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Tiered'), findsOneWidget);
    await tester.tap(find.text('Tiered'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Tiered'), findsOneWidget);
    expect(find.text('Gravity'), findsNothing);
  });

  // ----- #1 — the "+N" node lives ON the outer orbit ring -----

  Finder innerMembers() => find.descendant(
        of: find.byType(Orbit2InnerCircle),
        matching: find.byType(OrbitalAvatar),
      );

  testWidgets('#1 the +N node sits on ring2 INSIDE the box (not below it)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    final node = find.byKey(const ValueKey('inner-expand-toggle'));
    expect(node, findsOneWidget);
    final nodeC = tester.getCenter(node);
    final innerC = tester.getCenter(find.byType(Orbit2InnerCircle));
    final innerW = tester.getSize(find.byType(Orbit2InnerCircle)).width;
    // inside the cluster box (pre-#1 it escaped below via bottom:-4)
    expect(nodeC.dy, lessThan(innerC.dy + innerW / 2));
    // sits on the outermost drawn orbit (ring2R = size*0.31)
    expect((nodeC - innerC).distance, closeTo(innerW * 0.31, 12));
  });

  testWidgets('#1 the +N node occupies a distinct slot (no member overlap)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    final nodeRect =
        tester.getRect(find.byKey(const ValueKey('inner-expand-toggle')));
    for (final e in innerMembers().evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.overlaps(nodeRect), isFalse,
          reason: 'an inner member avatar overlaps the +N node');
    }
  });

  testWidgets('#1 inner members stay tappable with the node on their ring',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(innerMembers().first); // a ring-1 member, clear of the node
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
  });

  testWidgets('#1 expanded: node rides the ring3 orbit, then collapses back',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await tester.tap(find.text('+3')); // expand
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    final innerC = tester.getCenter(find.byType(Orbit2InnerCircle));
    final innerW = tester.getSize(find.byType(Orbit2InnerCircle)).width;
    final nodeC =
        tester.getCenter(find.byKey(const ValueKey('inner-expand-toggle')));
    expect(nodeC.dy, lessThan(innerC.dy + innerW / 2)); // still inside the box
    expect((nodeC - innerC).distance,
        closeTo(innerW * 0.44, 14)); // now ring3R = size*0.44
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('inner-expand-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('+3'), findsOneWidget);
  });

  testWidgets('#1 +N stays truthful as the circle grows (promote → +4)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('+3'), findsOneWidget);
    // long-press-carry a floating friend onto the cluster
    final from = tester.getCenter(avatarByIndex(1));
    final onto = tester.getCenter(find.byType(Orbit2InnerCircle));
    final g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await g.moveTo(onto);
    await tester.pump();
    await g.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));

    expect(find.text('+4'), findsOneWidget); // 17 members − 13 shown
    expect(find.byKey(const ValueKey('inner-expand-toggle')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2)); // drain snackbar/entrance
  });

  // ----- #2 — inner-circle name labels (auto-grow + spread) -----

  testWidgets('#2 names on (default): inner member + centre "You" labels render',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    // names default ON → inner labels render (ring1 + ring2 + centre)
    expect(find.text('Karim'), findsOneWidget); // ring1 (inner-1)
    expect(find.text('Hadi'), findsOneWidget); // ring2 (inner-5)
    expect(find.text('You'), findsOneWidget); // centre self
    // ring3 names only once expanded
    expect(find.text('Yara'), findsNothing); // inner-13
    await tester.tap(find.byKey(const ValueKey('inner-expand-toggle')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('Yara'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1)); // drain ring3 entrance timers
  });

  testWidgets('#2 adjacent inner labels do not overlap (legible)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    Rect r(String n) => tester.getRect(find.text(n));
    // same-ring neighbours stay apart (the "name across a face" bug guard)
    expect(r('Karim').overlaps(r('Mina')), isFalse); // ring1 neighbours
    expect(r('Mina').overlaps(r('Tariq')), isFalse); // ring1 neighbours
    expect(r('Hadi').overlaps(r('Dana')), isFalse); // ring2 neighbours
    // a label does not cover the centre "You"
    expect(r('Karim').overlaps(r('You')), isFalse);
  });

  testWidgets('#2 double-tap toggles inner names (and centre You) off/on',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);

    const empty = Offset(8, 340);
    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await settle(tester);
    expect(find.text('Karim'), findsNothing); // inner labels gone
    expect(find.text('You'), findsNothing);
    expect(find.text('Idris'), findsNothing); // canvas labels gone too (shared)

    await tester.tapAt(empty);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(empty);
    await settle(tester);
    expect(find.text('Karim'), findsOneWidget); // restored
  });

  // ----- #4 — Manage mode (add/remove friends AND groups) -----

  const manageToggle = ValueKey('orbit2-manage-toggle');
  Future<void> enterManage(WidgetTester tester) async {
    await tester.tap(find.byKey(manageToggle));
    await tester.pump(const Duration(milliseconds: 200));
  }

  const workKey = ValueKey('group-node-orbit2-group-work');
  const innerWorkKey = ValueKey('inner-group-orbit2-group-work');

  testWidgets('#4 Manage: tap a floating friend adds it to the inner circle',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    await enterManage(tester);
    await tester.tap(avatarByIndex(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloatingAvatar), findsNWidgets(9));
    expect(find.textContaining('added to your inner circle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('#4 Manage: tap a floating GROUP moves it into the inner circle',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byKey(workKey), findsOneWidget); // on the canvas
    await enterManage(tester);
    await tester.tap(find.byKey(workKey), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(workKey), findsNothing); // left the canvas
    expect(find.byKey(innerWorkKey), findsOneWidget); // now inside the circle
    expect(find.byType(Orbit2InnerCircle), findsOneWidget);
    expect(find.textContaining('added to your inner circle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('#4 Manage: tap an inner member removes it', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    await enterManage(tester);
    await tester.tap(innerMembers().first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FloatingAvatar), findsNWidgets(11));
    expect(find.textContaining('removed from your inner circle'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('#4 a promoted group glows when searched by name', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await enterManage(tester);
    await tester.tap(find.byKey(workKey), warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(manageToggle)); // exit manage
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.byIcon(Icons.search_rounded));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(find.byType(TextField), 'Work Crew');
    await settle(tester);
    expect(find.byKey(const ValueKey('inner-glow-orbit2-group-work')),
        findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('#4 Manage: a node tap does not open chat; Done restores it',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await enterManage(tester);
    await tester.tap(avatarByIndex(2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(Orbit2MockChatScreen), findsNothing); // promoted, not chat
    await tester.pump(const Duration(seconds: 2)); // drain promote snackbar

    await tester.tap(find.byKey(manageToggle)); // exit manage
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(avatarByIndex(3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
  });

  testWidgets('#4 Manage: tapping an inner group removes it (back to canvas)',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await enterManage(tester);
    await tester.tap(find.byKey(workKey), warnIfMissed: false); // add
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(innerWorkKey), findsOneWidget);

    await tester.tap(find.byKey(innerWorkKey), warnIfMissed: false); // remove
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(innerWorkKey), findsNothing);
    expect(find.byKey(workKey), findsOneWidget); // back on the canvas
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('#4 Manage mode clears when cycling population', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await enterManage(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget); // manage active
    await tester.tap(find.byIcon(Icons.people_alt_rounded)); // cycle population
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.byIcon(Icons.group_add_rounded), findsOneWidget); // inactive
    await tester.pump(const Duration(seconds: 1)); // drain entrance timers
  });

  // ----- #3 — Messages / Inbox view -----

  Future<void> openMessages(WidgetTester tester) async {
    await tester.tap(find.text('Gravity')); // expand the layout selector
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  String topInboxRowId() {
    final mock = Orbit2MockData.build(canvasCount: 10);
    final inner = mock.innerCircle.map(Orbit2InnerItem.friend).toList();
    return Orbit2MockData.inboxEntries(
            inner: inner, canvas: mock.canvas, groups: mock.groups)
        .first
        .id;
  }

  testWidgets('#3 opening Messages hides the inner circle and shows rows',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(Orbit2InnerCircle), findsOneWidget);
    await openMessages(tester);

    expect(find.byType(Orbit2InnerCircle), findsNothing);
    expect(find.byType(Orbit2InboxView), findsOneWidget);
    expect(find.byKey(ValueKey('inbox-row-${topInboxRowId()}')), findsOneWidget);
  });

  testWidgets('#3 tapping an inbox row opens the mock chat', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await openMessages(tester);
    await tester.tap(find.byKey(ValueKey('inbox-row-${topInboxRowId()}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(Orbit2MockChatScreen), findsOneWidget);
  });

  testWidgets('#3 picking a template restores the constellation', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await openMessages(tester);
    expect(find.byType(Orbit2InnerCircle), findsNothing);

    await tester.tap(find.text('Messages')); // collapsed pill → expand menu
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Tiered'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(Orbit2InboxView), findsNothing);
    expect(find.byType(Orbit2InnerCircle), findsOneWidget);
    expect(find.text('Tiered'), findsWidgets); // pill reflects the new template
    await tester.pump(const Duration(seconds: 1)); // drain inner-circle entrance
  });

  testWidgets('#3 Messages view shows no constellation chrome', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    await openMessages(tester);
    expect(find.byType(FloatingAvatar), findsNothing);
    expect(find.byKey(const ValueKey('inner-expand-toggle')), findsNothing);
  });

  // ----- review fixes -----

  testWidgets('a cancelled carry-out does not strand a phantom member',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap());
    await settle(tester);

    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    // Long-press an inner member to start carrying it OUT (a ghost appears)…
    final g = await tester.startGesture(tester.getCenter(innerMembers().first));
    await tester.pump(const Duration(milliseconds: 700)); // long-press accepted
    expect(find.byType(FloatingAvatar), findsNWidgets(11)); // carried-out ghost
    // …then the OS cancels the gesture (no clean release).
    await g.cancel();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Ghost cleared, member restored, no demote happened.
    expect(find.byType(FloatingAvatar), findsNWidgets(10));
    await tester.pump(const Duration(seconds: 1)); // drain entrance timers
  });
}
