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
  final next = RegExp(r'\n(?:class |abstract class |mixin )')
      .firstMatch(src.substring(after));
  final end = next == null ? src.length : after + next.start;
  return src.substring(start, end);
}

/// Slice a 2-space-indented member body out of [classBody].
String _member(String classBody, String startSig) {
  final start = classBody.indexOf(startSig);
  expect(start, isNonNegative, reason: 'expected to find member: $startSig');
  final after = start + startSig.length;
  final next =
      RegExp(r'\n  (?:@override|void |Future<|bool |Widget |String |int )')
          .firstMatch(classBody.substring(after));
  final end = next == null ? classBody.length : after + next.start;
  return classBody.substring(start, end);
}

void main() {
  late String mainSrc;
  late String myAppState;

  setUpAll(() async {
    mainSrc = await File('lib/main.dart').readAsString();
    myAppState = _myAppStateClass(mainSrc);
  });

  test('TC-183-W1: _MyAppState constructs the keepalive from the concrete impl + tracker', () {
    // Anchor: this is the real shipped app entry, not a stub.
    expect(app.MyApp.navigatorKey, isNotNull);

    expect(
      mainSrc,
      contains('active_peer_keepalive_use_case.dart'),
      reason: 'ActivePeerKeepAliveUseCase must be imported into main.dart',
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
      reason: 'must wire the PeerLivenessProbe from the concrete impl (no cast)',
    );
    // The active 1:1 peer is sourced from the conversation tracker.
    expect(
      myAppState,
      contains('activePeerId: () => widget.conversationTracker.activePeerId'),
      reason: 'the open 1:1 peer drives the probe',
    );
  });

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
      reason: '_onPaused must cancel the keepalive loop (zero pings while suspended)',
    );
    // The only background edges remain paused||hidden routing into _onPaused.
    expect(mainSrc, contains('state == AppLifecycleState.paused ||'));
    expect(mainSrc, contains('state == AppLifecycleState.hidden'));
  });

  test('TC-183-W4: teardown disposes the keepalive (no Timer leak)', () {
    final dispose = _member(myAppState, 'void dispose() {');
    expect(
      dispose,
      contains('_keepAliveUseCase.dispose()'),
      reason: 'the ~8s keepalive Timer leaks unless dispose() is called on teardown',
    );
  });
}
