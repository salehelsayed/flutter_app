import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/main.dart' as app;

// 181 — presence lifecycle wiring locks.
//
// SetPresenceUseCase (the FDC-09 §6.3 producer) is built + unit-tested but was
// constructed/called NOWHERE in production, so the committed send-side
// `unreachable` short-circuit (send_chat_message_use_case.dart:776-783) is inert.
// These locks assert _MyAppState now (W1) constructs the producer from the
// concrete P2PServiceImpl, dispatches (W2) onForegrounded on resume — unawaited,
// (W3) onBackgrounded on pause/hidden, (W4) dispose on teardown, and (W5) does
// NOT announce on detached. W6 guards the ~31-fake invariant: setPresence stays
// off the base P2PService interface.
//
// These are SOURCE-ASSERTION locks — pumping the full MyApp host-side is
// infeasible (native channels / Firebase / SQLCipher) — following the TC-164-02
// wiring-lock precedent. Behavioral closure is the device-proof (TC-181-33/34).

/// Slice the `_MyAppState` class body out of [src] (from its declaration to the
/// next top-level class), so member assertions cannot collide with another
/// class's `dispose()` / `_onPaused()` elsewhere in the large main.dart.
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

/// Slice a 2-space-indented member body out of [classBody], from [startSig] to
/// the next top-level member, so assertions are scoped to one method.
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

/// Slice a top-level class/interface block out of [src].
String _classBlock(String src, String startSig) {
  final start = src.indexOf(startSig);
  expect(start, isNonNegative, reason: 'expected to find: $startSig');
  final after = start + startSig.length;
  final next = RegExp(r'\n(?:abstract |enum |class |mixin )')
      .firstMatch(src.substring(after));
  final end = next == null ? src.length : after + next.start;
  return src.substring(start, end);
}

void main() {
  late String mainSrc;
  late String myAppState;
  late String p2pSrc;

  setUpAll(() async {
    mainSrc = await File('lib/main.dart').readAsString();
    myAppState = _myAppStateClass(mainSrc);
    p2pSrc = await File('lib/core/services/p2p_service.dart').readAsString();
  });

  test('TC-181-W1: _MyAppState constructs SetPresenceUseCase from the concrete p2p service', () {
    // Anchor: this is the real shipped app entry, not a stub.
    expect(app.MyApp.navigatorKey, isNotNull);

    expect(
      mainSrc,
      contains('set_presence_use_case.dart'),
      reason: 'SetPresenceUseCase must be imported into main.dart',
    );
    expect(
      myAppState,
      contains('SetPresenceUseCase('),
      reason: 'the producer must be constructed in _MyAppState',
    );
    // Wired from the concrete P2PServiceImpl field (widget.p2pService), which
    // implements RelayPresenceSet — NO cast, and NO new base-interface method
    // (W6 guards the interface separately).
    expect(
      myAppState,
      contains('presenceSetter: widget.p2pService'),
      reason: 'must wire the RelayPresenceSet param from the concrete impl (no cast)',
    );
  });

  test('TC-181-W2: resume announces foreground, unawaited', () {
    final onResumed = _member(myAppState, 'Future<void> _onResumed() async {');
    expect(
      onResumed,
      contains('unawaited(_setPresenceUseCase.onForegrounded())'),
      reason: '_onResumed must announce foreground UNAWAITED (no resume-path latency)',
    );
  });

  test('TC-181-W3: pause/hidden announces background', () {
    final onPaused = _member(myAppState, 'void _onPaused() {');
    expect(
      onPaused,
      contains('_setPresenceUseCase.onBackgrounded()'),
      reason: '_onPaused must announce background',
    );
    // The only background edges remain paused||hidden routing into _onPaused.
    expect(mainSrc, contains('state == AppLifecycleState.paused ||'));
    expect(mainSrc, contains('state == AppLifecycleState.hidden'));
  });

  test('TC-181-W4: teardown disposes the producer (no Timer leak)', () {
    final dispose = _member(myAppState, 'void dispose() {');
    expect(
      dispose,
      contains('_setPresenceUseCase.dispose()'),
      reason: 'the 60s heartbeat Timer leaks unless dispose() is called on teardown',
    );
  });

  test('TC-181-W5: detached does NOT announce background (negative)', () {
    final onDetached = _member(myAppState, 'void _onDetached() {');
    expect(
      onDetached.contains('onBackgrounded'),
      isFalse,
      reason: 'detached is teardown-only; presence announces only on resume/pause',
    );
  });

  test('TC-181-W6: setPresence stays OFF the base P2PService interface (~31-fake invariant)', () {
    // setPresence belongs to the opt-in RelayPresenceSet capability...
    final relayPresenceSet =
        _classBlock(p2pSrc, 'abstract interface class RelayPresenceSet {');
    expect(relayPresenceSet, contains('setPresence'));
    // ...and must NOT be on the base interface (would force ~31 fakes to grow it).
    final baseP2P = _classBlock(p2pSrc, 'abstract class P2PService {');
    expect(
      baseP2P.contains('setPresence'),
      isFalse,
      reason: 'hoisting setPresence to the base P2PService interface breaks ~31 fakes',
    );
  });
}
