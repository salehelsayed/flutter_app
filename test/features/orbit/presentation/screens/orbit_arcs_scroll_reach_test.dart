import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_depth_surface.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/overflow_badge.dart';
import 'package:flutter_test/flutter_test.dart';

import 'orbit_screen_pump_harness.dart';

/// BL-27: with enough inner-circle members the expanded arcs push the circle
/// (and its collapse badge) below the screen. The production screen wraps the
/// rings in the 3D depth surface; the expanded orbit must still scroll so the
/// badge can be reached and tapped to collapse the arcs again.
OrbitItem _friend(int i) => OrbitFriendItem(
  OrbitFriend(
    contact: ContactModel(
      peerId: 'peer-$i',
      publicKey: 'pk-$i',
      rendezvous: '/ip4/127.0.0.1/tcp/400$i',
      username: 'friend$i',
      signature: 'sig-$i',
      scannedAt: '2024-01-01T00:00:00Z',
    ),
    messageCount: i,
    unreadCount: 0,
    lastMessageTimestamp: '2024-01-01T00:00:00Z',
  ),
);

List<OrbitItem> _friends(int n) => [for (var i = 0; i < n; i++) _friend(i)];

const _phone = Size(390, 844);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 90));
  }
}

bool _expanded(WidgetTester tester) => tester
    .widget<OrbitalVisualization>(find.byType(OrbitalVisualization))
    .overflowExpanded;

bool _badgeOnScreen(WidgetTester tester) {
  final badge = find.byType(OverflowBadge).hitTestable();
  if (badge.evaluate().isEmpty) return false;
  final centre = tester.getCenter(badge);
  return centre.dy > 0 && centre.dy < _phone.height;
}

void main() {
  for (final (name, locale, scale) in [
    ('LTR', const Locale('en'), 1.0),
    ('RTL', const Locale('ar'), 1.0),
    ('large text', const Locale('en'), 2.0),
  ]) {
    testWidgets('BL-27 expanded arcs scroll to the collapse badge ($name)', (
      tester,
    ) async {
      tester.view.physicalSize = _phone * 3;
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = scale;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          header: OrbitHeaderProjection(
            userPeerId: 'me',
            innerItems: _friends(80),
          ),
          locale: locale,
        ),
      );
      await _settle(tester);
      expect(find.byType(OverflowBadge).hitTestable(), findsOneWidget);

      await tester.tap(find.byType(OverflowBadge));
      await _settle(tester);
      expect(_expanded(tester), isTrue);
      expect(
        _badgeOnScreen(tester),
        isFalse,
        reason: 'precondition: 80 members push the badge below the screen',
      );

      // Swipe the content up until the badge is reachable (bounded).
      for (var i = 0; i < 12 && !_badgeOnScreen(tester); i++) {
        await tester.dragFrom(const Offset(24, 700), const Offset(0, -400));
        await _settle(tester);
      }
      expect(
        _badgeOnScreen(tester),
        isTrue,
        reason: 'the expanded orbit must scroll the badge into view',
      );

      await tester.tap(find.byType(OverflowBadge).hitTestable());
      await _settle(tester);
      expect(_expanded(tester), isFalse, reason: 'the badge collapses arcs');
    });
  }

  testWidgets('BL-27 the 3D swipe pauses only while the arcs are open', (
    tester,
  ) async {
    tester.view.physicalSize = _phone * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final reset = ValueNotifier<int>(0);
    addTearDown(reset.dispose);
    Widget screen(OrbitViewMode mode) => buildOrbitScreenHarness(
      viewMode: mode,
      header: OrbitHeaderProjection(userPeerId: 'me', innerItems: _friends(80)),
      innerCircleResetListenable: reset,
    );
    bool depthGestures() => tester
        .widget<OrbitDepthSurface>(find.byType(OrbitDepthSurface))
        .gesturesEnabled;

    await tester.pumpWidget(screen(OrbitViewMode.innerCircle));
    await _settle(tester);
    expect(depthGestures(), isTrue);

    await tester.tap(find.byType(OverflowBadge));
    await _settle(tester);
    expect(_expanded(tester), isTrue);
    expect(depthGestures(), isFalse, reason: 'open arcs own vertical drags');

    // The Feed -> Orbit reset collapses the arcs another way.
    reset.value++;
    await _settle(tester);
    expect(_expanded(tester), isFalse);
    expect(depthGestures(), isTrue, reason: 'reset collapse restores 3D');

    // Leaving the rings while expanded must not leave 3D paused on return.
    await tester.tap(find.byType(OverflowBadge));
    await _settle(tester);
    expect(depthGestures(), isFalse);
    await tester.pumpWidget(screen(OrbitViewMode.allChats));
    await _settle(tester);
    await tester.pumpWidget(screen(OrbitViewMode.innerCircle));
    await _settle(tester);
    expect(_expanded(tester), isFalse);
    expect(depthGestures(), isTrue, reason: 'a fresh rings surface is flat');
  });
}
