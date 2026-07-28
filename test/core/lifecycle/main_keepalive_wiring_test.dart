import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 183 (TC-183-21) — active-chat keepalive lifecycle wiring locks.
//
// ActivePeerKeepAliveUseCase is built + unit-tested (the loop) but is inert until
// _MyAppState (W1) constructs it from the concrete P2PServiceImpl (the
// PeerLivenessProbe) + the conversation tracker's active 1:1 peer, REUSING
// warmPeer + drainOfflineInbox as its drop handlers, and (W2) arms it on resume,
// (W3) cancels it on pause/hidden, (W4) disposes it on teardown.
//
// SOURCE-ASSERTION locks — pumping the full MyApp host-side is infeasible (native
// channels / Firebase / SQLCipher) — following the TC-181 wiring-lock precedent.
// Behavioral closure is the device-proof (TC-183-50/51).

/// Slice the `_MyAppState` class body out of [src] (decl → next top-level class).
String _myAppStateClass(String src) {
  const sig = 'class _MyAppState extends State<MyApp>';
  final start = src.indexOf(sig);
  expect(start, isNonNegative, reason: 'expected to find: $sig');
  final after = start + sig.length;
  final next = RegExp(
    r'\n(?:class |abstract class |mixin )',
  ).firstMatch(src.substring(after));
  final end = next == null ? src.length : after + next.start;
  return src.substring(start, end);
}

/// Slice a 2-space-indented member body out of [classBody].
String _member(String classBody, String startSig) {
  final start = classBody.indexOf(startSig);
  expect(start, isNonNegative, reason: 'expected to find member: $startSig');
  final after = start + startSig.length;
  final next = RegExp(
    r'\n  (?:@override|void |Future<|bool |Widget |String |int )',
  ).firstMatch(classBody.substring(after));
  final end = next == null ? classBody.length : after + next.start;
  return classBody.substring(start, end);
}

void main() {
  late String applicationRootSrc;
  late String myAppState;

  setUpAll(() async {
    applicationRootSrc = await File(
      'lib/app/application_root.dart',
    ).readAsString();
    myAppState = _myAppStateClass(applicationRootSrc);
  });

  test(
    'TC-183-W1: _MyAppState constructs the keepalive from the concrete impl + tracker',
    () {
      // Anchor: this is the real shipped app entry, not a stub.
      expect(app.MyApp.navigatorKey, isNotNull);

      expect(
        applicationRootSrc,
        contains('active_peer_keepalive_use_case.dart'),
        reason:
            'ActivePeerKeepAliveUseCase must be imported into application_root.dart',
      );
      expect(
        myAppState,
        contains('ActivePeerKeepAliveUseCase('),
        reason: 'the keepalive must be constructed in _MyAppState',
      );
      // The probe is the concrete P2PServiceImpl (implements PeerLivenessProbe —
      // kept off base P2PService to spare the ~31 fakes; no cast needed).
      expect(
        myAppState,
        contains('probe: widget.p2pService'),
        reason:
            'must wire the PeerLivenessProbe from the concrete impl (no cast)',
      );
      // The active 1:1 peer is sourced from the conversation tracker.
      expect(
        myAppState,
        contains('activePeerId: () => widget.conversationTracker.activePeerId'),
        reason: 'the open 1:1 peer drives the probe',
      );
    },
  );

  test('TC-183-W1b: drop handlers REUSE warmPeer + drainOfflineInbox', () {
    expect(
      myAppState,
      contains('onDropReWarm: widget.p2pService.warmPeer'),
      reason: 'a drop must re-dial via the existing warmPeer (no new re-dial)',
    );
    expect(
      myAppState,
      contains('onDropDrain: widget.p2pService.drainOfflineInbox'),
      reason: 'a drop must drain via the existing public drainOfflineInbox',
    );
  });

  test('TC-183-W2: resume arms the keepalive', () {
    final onResumed = _member(myAppState, 'Future<void> _onResumed() async {');
    expect(
      onResumed,
      contains('_keepAliveUseCase.onForegrounded()'),
      reason: '_onResumed must arm the keepalive loop',
    );
  });

  test('TC-183-W3: pause/hidden cancels the keepalive', () {
    final onPaused = _member(myAppState, 'void _onPaused() {');
    expect(
      onPaused,
      contains('_keepAliveUseCase.onBackgrounded()'),
      reason:
          '_onPaused must cancel the keepalive loop (zero pings while suspended)',
    );
    // The only background edges remain paused||hidden routing into _onPaused.
    expect(
      applicationRootSrc,
      contains('state == AppLifecycleState.paused ||'),
    );
    expect(applicationRootSrc, contains('state == AppLifecycleState.hidden'));
  });

  test('TC-183-W4: teardown disposes the keepalive (no Timer leak)', () {
    final dispose = _member(myAppState, 'void dispose() {');
    expect(
      dispose,
      contains('_keepAliveUseCase.dispose()'),
      reason:
          'the ~8s keepalive Timer leaks unless dispose() is called on teardown',
    );
  });

  test(
    'TC-183-52: cold start arms the keepalive + presence when launched foreground',
    () {
      // Flutter delivers NO initial `resumed` lifecycle transition on a fresh
      // launch, so `_onResumed()` never runs and the foreground-only heartbeats
      // would stay dormant until the first background→foreground cycle
      // (device-proven 2026-07-01: no `peer:ping` fired until the app was cycled).
      // initState must arm them once, guarded on a foreground (resumed) launch.
      final initState = _member(myAppState, 'void initState() {');
      // The arm must be GUARDED on a foreground (resumed) launch...
      final guardIdx = initState.indexOf('AppLifecycleState.resumed');
      expect(
        guardIdx,
        isNonNegative,
        reason:
            'the cold-start arm must be guarded on a foreground (resumed) launch',
      );
      // ...and BOTH heartbeats must be armed AFTER that guard (co-located inside
      // the resumed block — not merely present somewhere in initState). This
      // catches a mutation that keeps the arms but weakens/moves the guard, which a
      // bare `contains` would miss. Within initState both onForegrounded calls
      // appear ONLY in the cold-start block, so "after the guard" pins them to it.
      final afterGuard = initState.substring(guardIdx);
      expect(
        afterGuard,
        contains('_keepAliveUseCase.onForegrounded()'),
        reason:
            'initState must arm the 183 keepalive inside the resumed guard '
            '(else it is dormant until the first background→foreground cycle)',
      );
      // The 181 presence heartbeat shares the identical cold-start gap — arm it
      // from the same guarded seam so a cold-launched foreground app publishes.
      expect(
        afterGuard,
        contains('_setPresenceUseCase.onForegrounded()'),
        reason:
            'initState must also arm the 181 presence heartbeat in the same guard',
      );
    },
  );
}
