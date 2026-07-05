import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/presentation/widgets/glow_fab.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../../../../core/services/fake_p2p_service.dart';
import 'orbit_screen_pump_harness.dart';

/// 211 — the connection-status pill (Offline/Connecting/Online/Online./Online ✦)
/// migrates from the Feed header to the Orbit top-right chrome, next to the
/// ExpandableFab "+" (Layer 4b, mounted BEFORE the FAB so the open-menu scrim
/// covers it — INV-211-4). Present on BOTH views (single persistent element —
/// INV-211-5), hidden during sculpt-edit (the edit banner owns the top band),
/// passive, and byte-untouched as a widget (INV-211-3: the state/telemetry
/// contract stays locked by connection_status_indicator_test).
///
/// NOTE: this whole file is compile-RED on HEAD — `buildOrbitScreenHarness`
/// and `OrbitScreen` have no `p2pService` parameter until 211-E2/E6 land.
void main() {
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

  // The five-state NodeState oracle — same shapes as the widget suite
  // (connection_status_indicator_test.dart), so labels track the real
  // service-owned badge contract, not a parallel fixture.
  NodeState stateFor(BadgeReadinessState state) {
    return switch (state) {
      BadgeReadinessState.offline => const NodeState(isStarted: false),
      BadgeReadinessState.connecting => const NodeState(
          isStarted: true,
          relayState: 'degraded',
        ),
      BadgeReadinessState.online => const NodeState(
          isStarted: true,
          relayState: 'degraded',
          sendCapabilityReady: true,
          inboxCapabilityReady: true,
        ),
      BadgeReadinessState.onlineDotted => const NodeState(
          isStarted: true,
          relayState: 'online',
          circuitAddresses: ['/p2p-circuit/relay1'],
          sendCapabilityReady: true,
          inboxCapabilityReady: true,
        ),
      BadgeReadinessState.onlineDirect => const NodeState(
          isStarted: true,
          relayState: 'online',
          circuitAddresses: ['/p2p-circuit/relay1'],
          sendCapabilityReady: true,
          inboxCapabilityReady: true,
          directReady: true,
        ),
    };
  }

  Widget pumpOrbit({
    required OrbitViewMode viewMode,
    FakeP2PService? service,
    List<OrbitItem> innerItems = const [],
    VoidCallback? onToggleView,
    Locale locale = const Locale('en'),
  }) =>
      buildOrbitScreenHarness(
        viewMode: viewMode,
        header: OrbitHeaderProjection(userPeerId: 'me', innerItems: innerItems),
        p2pService: service,
        onToggleView: onToggleView ?? () {},
        locale: locale,
      );

  Future<void> settle(WidgetTester tester, {int count = 8}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 90));
    }
  }

  final indicatorF = find.byType(ConnectionStatusIndicator);

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

  testWidgets('TC-211-11 pill renders top-right, next to the +', (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    final service = FakeP2PService();

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
    );
    await settle(tester);

    expect(indicatorF, findsOneWidget);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final pill = tester.getRect(indicatorF);
    final fab = tester.getRect(find.byType(GlowFab));

    expect(pill.right, lessThanOrEqualTo(fab.left),
        reason: 'pill sits fully LEFT of the +');
    expect(fab.left - pill.right, lessThanOrEqualTo(12),
        reason: 'pill hugs the + (right:64 = 16 fab inset + 40 fab + 8 gap)');
    expect((pill.center.dy - fab.center.dy).abs(), lessThanOrEqualTo(2),
        reason: 'vertically centered with the +');
    expect(pill.top, lessThan(120), reason: 'top chrome band');
    expect(pill.center.dx, greaterThan(width / 2),
        reason: 'physical right half (stays clear of the qr-migration T3 '
            'top-center background tap)');
  });

  testWidgets('TC-211-12 pill present on BOTH views', (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.allChats, service: FakeP2PService()),
    );
    await settle(tester);
    expect(indicatorF, findsOneWidget);

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: FakeP2PService()),
    );
    await settle(tester);
    expect(indicatorF, findsOneWidget);
  });

  testWidgets(
      'TC-211-13/29 sculpt-edit hides the pill; exit re-shows it with the '
      'CURRENT state', (tester) async {
    // Default (wide) test surface: the sculpt-suite bgPoint recipe needs the
    // canvas centered far from the left edge so the long-press lands on empty
    // background, not a ring node (node long-press must NOT enter edit).
    suppressChromeErrors();
    final service = FakeP2PService(
      initialState: stateFor(BadgeReadinessState.offline),
    );

    await tester.pumpWidget(
      pumpOrbit(
        viewMode: OrbitViewMode.innerCircle,
        service: service,
        innerItems: friends(8),
      ),
    );
    // Full settle (sculpt-suite recipe): the surface entrance animations must
    // finish before the background long-press registers.
    await settle(tester, count: 16);
    expect(indicatorF, findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);

    // Enter edit: the banner spans the full top width → the pill unmounts.
    await longPressBg(tester);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsOneWidget);
    expect(indicatorF, findsNothing,
        reason: 'pill hidden during sculpt-edit');

    // Node comes online WHILE the pill is hidden.
    service.emitState(stateFor(BadgeReadinessState.onlineDotted));
    await tester.pump();

    // Exit edit: the pill re-mounts seeded from currentState — it must show
    // the LIVE state, not the pre-edit Offline.
    await tapAwayBg(tester);
    await settle(tester);
    expect(find.byKey(const ValueKey('orbit-edit-banner')), findsNothing);
    expect(indicatorF, findsOneWidget);
    expect(find.text('Online.'), findsOneWidget,
        reason: 're-seeded from currentState on re-mount');
    expect(find.text('Offline'), findsNothing);
  });

  testWidgets('TC-211-14 open FAB menu scrim covers the pill (mount order)',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: FakeP2PService()),
    );
    await settle(tester);

    final pillCenter = tester.getRect(indicatorF).center;

    // Open the + menu → the FAB's own scrim mounts above every earlier layer.
    await tester.tap(find.byType(GlowFab));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('expandable_fab_scrim')), findsOneWidget);

    // A tap AT the pill must land on the scrim (pill mounted BEFORE the FAB →
    // scrim wins) and close the menu.
    await tester.tapAt(pillCenter);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('expandable_fab_scrim')), findsNothing,
        reason: 'scrim consumed the tap → menu closed (INV-211-4)');
    expect(indicatorF, findsOneWidget);
  });

  testWidgets('TC-211-15 RTL: pill stays physical top-right', (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();

    await tester.pumpWidget(
      pumpOrbit(
        viewMode: OrbitViewMode.innerCircle,
        service: FakeP2PService(),
        locale: const Locale('ar'),
      ),
    );
    await settle(tester);

    final width = tester.view.physicalSize.width / tester.view.devicePixelRatio;
    final pill = tester.getRect(indicatorF);
    final toggle =
        tester.getRect(find.byKey(const ValueKey('orbit-view-toggle')));

    expect(pill.center.dx, greaterThan(width / 2),
        reason: 'physical right under RTL (Positioned, not Directional)');
    expect(pill.left, greaterThan(toggle.right),
        reason: 'no overlap with the physical top-left toggle');
  });

  testWidgets('TC-211-16 no service → no pill, no crash', (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: null),
    );
    await settle(tester);

    expect(indicatorF, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-211-17 text-scale 1.5 + "Online ✦": no FAB overlap',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(
      pumpOrbit(
        viewMode: OrbitViewMode.innerCircle,
        service: FakeP2PService(
          initialState: stateFor(BadgeReadinessState.onlineDirect),
        ),
      ),
    );
    await settle(tester);

    expect(find.text('Online ✦'), findsOneWidget);
    final pill = tester.getRect(indicatorF);
    final fab = tester.getRect(find.byType(GlowFab));
    expect(pill.right, lessThanOrEqualTo(fab.left),
        reason: 'widest label at 1.5× still clears the +');
    expect((pill.center.dy - fab.center.dy).abs(), lessThanOrEqualTo(2),
        reason: 'height:40 + Center keeps vertical alignment at any scale');
    expect(tester.takeException(), isNull);
  });

  testWidgets('TC-211-18/27 first frame seeds from currentState — no flash',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();

    // Pre-set READY before the pump: very first frame shows Online., never an
    // Offline flash (cross-screen arrival from Feed keeps the live state).
    await tester.pumpWidget(
      pumpOrbit(
        viewMode: OrbitViewMode.innerCircle,
        service: FakeP2PService(
          initialState: stateFor(BadgeReadinessState.onlineDotted),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Online.'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);

    // Variant: FRESH mount (the keyed element must not survive — a service is
    // a stable identity in production) pre-set OFFLINE → arrival shows Offline.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(
      pumpOrbit(
        viewMode: OrbitViewMode.innerCircle,
        service: FakeP2PService(
          initialState: stateFor(BadgeReadinessState.offline),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('TC-211-19 five-state live updates track the stream',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    final service = FakeP2PService(
      initialState: stateFor(BadgeReadinessState.offline),
    );

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
    );
    await settle(tester);
    expect(find.text('Offline'), findsOneWidget);

    const expectations = [
      (BadgeReadinessState.connecting, 'Connecting'),
      (BadgeReadinessState.online, 'Online'),
      (BadgeReadinessState.onlineDotted, 'Online.'),
      (BadgeReadinessState.onlineDirect, 'Online ✦'),
    ];
    for (final (state, label) in expectations) {
      service.emitState(stateFor(state));
      await tester.pump();
      expect(find.text(label), findsOneWidget,
          reason: 'live label for $state');
    }
  });

  testWidgets('TC-211-20 pill is passive — no button semantics, no handlers',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: FakeP2PService()),
    );
    await settle(tester);

    final data = tester.getSemantics(indicatorF).getSemanticsData();
    expect(data.flagsCollection.isButton, isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);

    // Tapping it (menu closed) triggers nothing.
    await tester.tapAt(tester.getRect(indicatorF).center);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(indicatorF, findsOneWidget);
    expect(find.byKey(const Key('expandable_fab_scrim')), findsNothing);

    handle.dispose();
  });

  testWidgets(
      'TC-211-21/22 single persistent pill across view toggles — readiness '
      'flow event fires exactly once', (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);
    addTearDown(() => debugSetFlowEventSink(null));

    final service = FakeP2PService(
      initialState: stateFor(BadgeReadinessState.offline),
    );

    int badgeEvents() => events
        .where((e) => e['event'] == 'TIME_TO_ONLINE_BADGE_WIDGET')
        .length;

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
    );
    await settle(tester);
    expect(indicatorF, findsOneWidget);
    final element = tester.element(indicatorF);

    // Toggle to the list view: the keyed Layer 4b element must survive the
    // Stack reshuffle (no remount ⇒ no re-subscribe ⇒ no re-emit vector).
    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.allChats, service: service),
    );
    await settle(tester);
    expect(indicatorF, findsOneWidget);
    expect(identical(tester.element(indicatorF), element), isTrue,
        reason: 'one persistent element across the toggle (INV-211-5)');

    // Readiness arrives on the list view → exactly one flow event.
    service.emitState(stateFor(BadgeReadinessState.online));
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);
    expect(badgeEvents(), 1);

    // Toggle back while ready: still the same element, still one event.
    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
    );
    await settle(tester);
    expect(indicatorF, findsOneWidget);
    expect(identical(tester.element(indicatorF), element), isTrue);
    expect(badgeEvents(), 1, reason: 'no re-emit from the toggle');

    // Ready→ready is not a transition — still one.
    service.emitState(stateFor(BadgeReadinessState.onlineDotted));
    await tester.pump();
    expect(badgeEvents(), 1);
  });

  testWidgets('TC-211-28 remount storm converges, no stream errors',
      (tester) async {
    setPhoneSurface(tester);
    suppressChromeErrors();
    final service = FakeP2PService(
      initialState: stateFor(BadgeReadinessState.offline),
    );

    final cycle = [
      BadgeReadinessState.connecting,
      BadgeReadinessState.online,
      BadgeReadinessState.offline,
      BadgeReadinessState.onlineDotted,
      BadgeReadinessState.onlineDirect,
    ];
    for (final state in cycle) {
      await tester.pumpWidget(
        pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
      );
      await settle(tester, count: 2);
      expect(indicatorF, findsOneWidget);

      service.emitState(stateFor(state));
      await tester.pump();

      // Hard unmount between rounds.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }

    await tester.pumpWidget(
      pumpOrbit(viewMode: OrbitViewMode.innerCircle, service: service),
    );
    await settle(tester, count: 2);
    expect(find.text('Online ✦'), findsOneWidget,
        reason: 'converges to the latest emitted state');
    expect(tester.takeException(), isNull);
  });
}
