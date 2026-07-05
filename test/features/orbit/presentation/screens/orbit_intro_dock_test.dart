import 'package:flutter/material.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../core/services/fake_p2p_service.dart';
import 'orbit_screen_pump_harness.dart';

/// 207 — the intro dock joins the inner-circle top chrome row (Layer 4c,
/// left:64 beside the view toggle, right-bounded by the 211 pill reserve,
/// mounted BEFORE the FAB so the open-menu scrim covers it). Raw reviewCount
/// gates the slot; unseenReviewCount selects dock vs remnant. Wired behavior
/// (tap flip, dismissal, unseen math) lives in orbit_wired_test.dart — this
/// file pins the screen-level placement contract via the pump harness.
void main() {
  final dockF = find.byKey(const ValueKey('orbit-intro-dock'));
  final remnantF = find.byKey(const ValueKey('orbit-intro-remnant'));

  void setPhoneSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(414, 896);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  void suppressChromeErrors() {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final msg = details.exceptionAsString();
      if (details.toString().contains('overflowed') ||
          msg.contains('Unable to load asset') ||
          msg.contains('SvgPicture') ||
          msg.contains('ImageFilter')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  OrbitItem friend(int i) => OrbitFriendItem(OrbitFriend(
        contact: ContactModel(
          peerId: 'peer-$i',
          publicKey: 'pk-$i',
          rendezvous: '/ip4/127.0.0.1/tcp/400$i',
          username: 'friend$i',
          signature: 'sig-$i',
          scannedAt: '2024-01-01T00:00:00Z',
        ),
        messageCount: i,
        lastMessageTimestamp: '2024-01-01T00:00:00Z',
      ));

  List<OrbitItem> friends(int n) => [for (var i = 0; i < n; i++) friend(i)];

  // Widest pill vocabulary (TC-211-17's oracle): onlineDirect → 'Online ✦'.
  const onlineDirectState = NodeState(
    isStarted: true,
    relayState: 'online',
    circuitAddresses: ['/p2p-circuit/relay1'],
    sendCapabilityReady: true,
    inboxCapabilityReady: true,
    directReady: true,
  );

  const pendingProjection = OrbitViewProjection(
    introCount: 2,
    pendingGroupInviteCount: 1,
    reviewCount: 3,
    unseenReviewCount: 3,
  );

  Future<void> settle(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  // Sculpt-edit drive recipe (borrowed from orbit_sculpt_summon_wired_test):
  // long-press empty background enters edit, tap-away exits.
  Offset bgPoint(WidgetTester tester) {
    final r = tester.getRect(
        find.byKey(const ValueKey('orbit-inner-circle-background')));
    return Offset(r.left + 36, r.center.dy);
  }

  Future<void> longPressBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await tester.pump(const Duration(milliseconds: 620));
    await g.up();
    await tester.pump();
  }

  Future<void> tapAwayBg(WidgetTester tester) async {
    final g = await tester.startGesture(bgPoint(tester));
    await g.up();
    await tester.pump(const Duration(milliseconds: 350));
  }

  group('Orbit intro dock screen placement', () {
    testWidgets('TC-207-01 dock renders on inner-circle when reviewCount > 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: pendingProjection,
        ),
      );

      final dock = find.byKey(const ValueKey('orbit-intro-dock'));
      expect(dock, findsOneWidget);
      final rect = tester.getRect(dock);
      expect(rect.left, 64);
      // Test env has zero safe-area padding → band top = safeTop(0) + 8.
      expect(rect.top, 8);
    });

    testWidgets('TC-207-02 count-gated: present at >0 then absent at 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: const OrbitViewProjection(reviewCount: 1, unseenReviewCount: 1),
        ),
      );
      expect(find.byKey(const ValueKey('orbit-intro-dock')), findsOneWidget);

      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: const OrbitViewProjection(),
        ),
      );
      expect(find.byKey(const ValueKey('orbit-intro-dock')), findsNothing);
      expect(find.byKey(const ValueKey('orbit-intro-remnant')), findsNothing);
    });

    testWidgets('TC-207-03 all-chats keeps banner and does not mount dock', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.allChats,
          onToggleView: () {},
          list: const OrbitViewProjection(reviewCount: 1, unseenReviewCount: 1),
        ),
      );

      expect(find.byKey(const ValueKey('orbit-intro-dock')), findsNothing);
      expect(find.byKey(const ValueKey('orbit-intro-remnant')), findsNothing);
    });

    testWidgets(
        'TC-207-05 dock clears the widest pill at 390dp, textScale 1.5, '
        'and stays reserve-capped with no service', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      suppressChromeErrors();

      // Widest pill state at 1.0×: dock keeps the 8dp gap to the pill's
      // floating left edge.
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          p2pService: FakeP2PService(initialState: onlineDirectState),
          list: pendingProjection,
        ),
      );
      await settle(tester);
      expect(find.text('Online ✦'), findsOneWidget);
      var dock = tester.getRect(dockF);
      var pill = tester.getRect(find.byType(ConnectionStatusIndicator));
      expect(dock.right, lessThanOrEqualTo(pill.left - 8),
          reason: 'dock keeps the 8dp gap to the widest pill');

      // 1.5× text scale: both chrome pieces grow — still NO overlap.
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          p2pService: FakeP2PService(initialState: onlineDirectState),
          list: pendingProjection,
        ),
      );
      await settle(tester);
      dock = tester.getRect(dockF);
      pill = tester.getRect(find.byType(ConnectionStatusIndicator));
      expect(dock.right, lessThanOrEqualTo(pill.left),
          reason: 'no overlap at 1.5× text scale');
      expect(tester.takeException(), isNull);

      // No service → no pill; the reserve constant still caps the slot, so
      // the dock never wanders into the pill/FAB band.
      tester.platformDispatcher.textScaleFactorTestValue = 1.0;
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: pendingProjection,
        ),
      );
      await settle(tester);
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(find.byType(ConnectionStatusIndicator), findsNothing);
      dock = tester.getRect(dockF);
      expect(dock.right, lessThanOrEqualTo(width - 206),
          reason: 'reserve-capped even without a pill');
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'TC-207-06 FAB scrim covers the dock; keyed element survives '
        'projection repumps', (tester) async {
      setPhoneSurface(tester);
      suppressChromeErrors();

      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: pendingProjection,
        ),
      );
      await settle(tester);
      expect(dockF, findsOneWidget);
      final element = tester.element(dockF);
      final dockCenter = tester.getRect(dockF).center;

      // Open the + menu → the FAB's own scrim mounts above every earlier
      // layer. A tap AT the dock must land on the scrim (dock mounted BEFORE
      // the FAB) and close the menu.
      await tester.tap(find.byType(GlowFab));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('expandable_fab_scrim')), findsOneWidget);
      await tester.tapAt(dockCenter);
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const Key('expandable_fab_scrim')), findsNothing,
          reason: 'scrim consumed the tap → menu closed');
      expect(dockF, findsOneWidget);

      // A projection repump (3 → 2 unseen) rebuilds the label but must reuse
      // the same keyed element (no remount across Stack reshuffles).
      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          list: const OrbitViewProjection(
            introCount: 2,
            pendingGroupInviteCount: 1,
            reviewCount: 3,
            unseenReviewCount: 2,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('2 new'), findsOneWidget);
      expect(identical(tester.element(dockF), element), isTrue,
          reason: 'one persistent keyed element across repumps');
    });

    testWidgets('TC-207-07 sculpt-edit hides the dock; exit re-shows it', (
      tester,
    ) async {
      // Default (wide) test surface: the sculpt-suite bgPoint recipe needs the
      // canvas centered far from the left edge so the long-press lands on
      // empty background, not a ring node.
      suppressChromeErrors();

      await tester.pumpWidget(
        buildOrbitScreenHarness(
          viewMode: OrbitViewMode.innerCircle,
          onToggleView: () {},
          header: OrbitHeaderProjection(
            userPeerId: 'me',
            innerItems: friends(8),
          ),
          list: pendingProjection,
        ),
      );
      await settle(tester, count: 16);
      expect(dockF, findsOneWidget);

      // Enter edit: the banner spans the full top width → the dock unmounts
      // (and no remnant sneaks in either).
      await longPressBg(tester);
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
      expect(dockF, findsNothing, reason: 'dock hidden during sculpt-edit');
      expect(remnantF, findsNothing);

      // Exit edit: the dock re-mounts.
      await tapAwayBg(tester);
      await settle(tester);
      expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
      expect(dockF, findsOneWidget);
    });

    testWidgets('TC-207-08 RTL keeps dock in the physical left band', (
      tester,
    ) async {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.rtl,
          child: buildOrbitScreenHarness(
            viewMode: OrbitViewMode.innerCircle,
            onToggleView: () {},
            list: const OrbitViewProjection(
              reviewCount: 1,
              unseenReviewCount: 1,
            ),
          ),
        ),
      );

      expect(tester.getRect(find.byKey(const ValueKey('orbit-intro-dock'))).left, 64);
    });
  });
}
