import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/services/active_peer_keepalive_use_case.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

// 183 — active-chat keepalive loop (host floor).
//
// The use case is modeled VERBATIM on 181's SetPresenceUseCase: a foreground-only
// Timer.periodic (~8 s, well under the ~30 s QUIC idle) that pings the OPEN 1:1
// peer via an injected PeerLivenessProbe, keeps the warm connection alive, and on
// M consecutive misses REUSES warmPeer (onDropReWarm) + drainOfflineInbox
// (onDropDrain). The real `peer:ping` leg is the device-proof (TC-183-50); here
// the probe is faked + fakeAsync drives the cadence.

/// Records every pingPeer call + the timeout, returns a configurable result, and
/// can be made to throw to prove the loop never propagates a thrown ping.
class _FakeProbe implements PeerLivenessProbe {
  final List<String> pings = [];
  bool result = true;
  bool throwOnPing = false;
  int? lastTimeoutMs;

  @override
  Future<bool> pingPeer(String peerId, {required int timeoutMs}) async {
    pings.add(peerId);
    lastTimeoutMs = timeoutMs;
    if (throwOnPing) {
      throw Exception('ping boom');
    }
    return result;
  }
}

void main() {
  late _FakeProbe probe;
  late String? activePeer;
  late List<String> reWarms;
  late int drains;
  late List<Map<String, dynamic>> events;

  const interval = Duration(seconds: 8);
  const threshold = 2;

  setUp(() {
    flowEventLoggingEnabled = false;
    probe = _FakeProbe();
    activePeer = 'peerAlice';
    reWarms = [];
    drains = 0;
    events = [];
    debugSetFlowEventSink((p) => events.add(Map<String, dynamic>.from(p)));
  });

  tearDown(() => debugSetFlowEventSink(null));

  ActivePeerKeepAliveUseCase build() => ActivePeerKeepAliveUseCase(
    probe: probe,
    activePeerId: () => activePeer,
    onDropReWarm: (p) async => reWarms.add(p),
    onDropDrain: () async => drains++,
    interval: interval,
    missThreshold: threshold,
    pingTimeout: const Duration(seconds: 4),
  );

  List<Map<String, dynamic>> eventsNamed(String name) =>
      events.where((e) => e['event'] == name).toList();

  // TC-183-01/02 — arms on foreground and probes the active 1:1 peer on cadence.
  test('TC-183-01/02: arms on foreground + probes every interval', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      expect(useCase.isProbeActive, isTrue);
      expect(probe.pings, isEmpty); // no probe until the first tick

      async.elapse(interval * 3);
      async.flushMicrotasks();

      // Exactly one ping per interval, all to the active 1:1 peer.
      expect(probe.pings, hasLength(3));
      expect(probe.pings.every((p) => p == 'peerAlice'), isTrue);
      // The configured ping timeout (< interval) is forwarded.
      expect(probe.lastTimeoutMs, 4000);
    });
  });

  // TC-183-03 — cancels on background: no further pings while suspended.
  test('TC-183-03: cancels on background (zero pings while suspended)', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1));

      useCase.onBackgrounded();
      expect(useCase.isProbeActive, isFalse);

      async.elapse(interval * 5);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1)); // none fired while backgrounded
    });
  });

  // TC-183-04 — clearing the active peer cancels the in-progress miss streak, so
  // a closed-then-reopened chat never inherits a stale miss (no premature
  // re-dial). Mutation: drop the null-branch reset → the stale miss carries over
  // and a drop fires after a single fresh miss → red.
  test('TC-183-04: clearing the active peer resets the miss streak', () {
    fakeAsync((async) {
      probe.result = false; // every reachable tick is a miss
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval); // miss #1 (below threshold 2)
      async.flushMicrotasks();
      expect(reWarms, isEmpty);

      // Chat closes: active peer clears.
      activePeer = null;
      async.elapse(interval); // null tick → no ping, streak reset
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1)); // the null tick did NOT ping

      // A new chat opens; it must take a FULL threshold of fresh misses.
      activePeer = 'peerAlice';
      async.elapse(interval); // fresh miss #1 (not #2)
      async.flushMicrotasks();
      expect(reWarms, isEmpty, reason: 'stale pre-clear miss must not carry over');
    });
  });

  // TC-183-05 — a successful ping resets the miss count and never re-dials.
  test('TC-183-05: success resets the miss count (no re-dial)', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      probe.result = false;
      useCase.onForegrounded();
      async.elapse(interval); // miss #1
      async.flushMicrotasks();

      probe.result = true;
      async.elapse(interval); // success → reset, NO re-dial
      async.flushMicrotasks();
      expect(reWarms, isEmpty);

      probe.result = false;
      async.elapse(interval); // miss #1 (post-reset)
      async.flushMicrotasks();
      expect(reWarms, isEmpty, reason: 'count restarted after the success');

      async.elapse(interval); // miss #2 → NOW it fires
      async.flushMicrotasks();
      expect(reWarms, hasLength(1));
    });
  });

  // TC-183-06 — M consecutive misses trigger exactly ONE warmPeer (threshold, not
  // per-miss). Mutation: re-dial per-miss (no threshold) → fires after miss #1.
  test('TC-183-06: M consecutive misses → exactly one re-warm', () {
    fakeAsync((async) {
      probe.result = false;
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval); // miss #1 — must NOT fire yet
      async.flushMicrotasks();
      expect(reWarms, isEmpty, reason: 'threshold not reached after one miss');

      async.elapse(interval); // miss #2 → fire
      async.flushMicrotasks();
      expect(reWarms, equals(['peerAlice']));
    });
  });

  // TC-183-07 — a drop also drains the offline inbox exactly once, and emits a
  // KEEPALIVE_PEER_DROP discriminator carrying the active peerId (distinguishes a
  // real drop-driven re-warm from warmPeer's other one-shot triggers).
  test('TC-183-07: drop → drain once + KEEPALIVE_PEER_DROP carries the peer', () {
    fakeAsync((async) {
      flowEventLoggingEnabled = false;
      probe.result = false;
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval * threshold);
      async.flushMicrotasks();

      expect(drains, 1);
      final drop = eventsNamed('KEEPALIVE_PEER_DROP');
      expect(drop, hasLength(1));
      expect((drop.single['details'] as Map)['peerId'], 'peerAlice');
    });
  });

  // TC-183-08 — a null OR `group:` active peer is NEVER probed (1:1 only; groups
  // have their own GossipSub liveness). Mutation: ping null/group.
  test('TC-183-08: null / group: active peer → zero pings', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      activePeer = null;
      useCase.onForegrounded();
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(probe.pings, isEmpty);

      activePeer = 'group:room-1';
      async.elapse(interval * 3);
      async.flushMicrotasks();
      expect(probe.pings, isEmpty);
    });
  });

  // TC-183-09 — a durably-failing probe (e.g. an account-migration-gated peer
  // that returns false every tick) re-dials at most ONCE until the peer recovers
  // — it does NOT spam warmPeer/drain every M ticks. Mutation: remove the
  // dropped-latch → fires every M ticks → many re-dials.
  test('TC-183-09: durably-failing probe re-dials once, not per window (no spam)', () {
    fakeAsync((async) {
      probe.result = false; // never recovers
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval * 10);
      async.flushMicrotasks();

      expect(reWarms, hasLength(1), reason: 'latched until recovery — no spam');
      expect(drains, 1);
    });
  });

  // TC-183-10 — a thrown ping is non-load-bearing: it never propagates, is
  // treated as a miss, and the loop keeps running. Mutation: rethrow → the drop
  // logic never runs (await rethrows) → no re-warm.
  test('TC-183-10: a thrown ping never propagates (treated as a miss)', () {
    fakeAsync((async) {
      probe.throwOnPing = true;
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      async.elapse(interval * threshold);
      async.flushMicrotasks();

      // Two thrown pings counted as misses → exactly one re-dial; no exception
      // escaped to fail the test.
      expect(reWarms, equals(['peerAlice']));
    });
  });

  // TC-183-11 — rapid foreground↔background churn arms exactly ONE loop (a fresh
  // onForegrounded cancels any prior timer); pings stay bounded to one/interval.
  // Mutation: drop the cancel-before-arm → leaked duplicate timers → 2+ pings.
  test('TC-183-11: churn arms one loop (bounded pings)', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      useCase.onBackgrounded();
      useCase.onForegrounded();
      useCase.onForegrounded(); // re-arm twice in a row

      async.elapse(interval);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1), reason: 'exactly one timer armed');
    });
  });

  // TC-183-12 — resume re-arms the loop a pause cancelled (else liveness silently
  // stops after one background). Mutation: a one-shot guard that never re-arms.
  test('TC-183-12: resume re-arms after a pause', () {
    fakeAsync((async) {
      final useCase = build();
      addTearDown(useCase.dispose);

      useCase.onForegrounded();
      useCase.onBackgrounded();
      async.elapse(interval); // suspended — no pings
      async.flushMicrotasks();
      expect(probe.pings, isEmpty);

      useCase.onForegrounded(); // re-arm
      async.elapse(interval);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1));
    });
  });

  // Durability: dispose() cancels the timer — no further pings after teardown
  // (the ~8 s Timer.periodic would otherwise leak across hot-restart).
  test('dispose() stops the loop (no leaked timer)', () {
    fakeAsync((async) {
      final useCase = build();

      useCase.onForegrounded();
      async.elapse(interval);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1));

      useCase.dispose();
      expect(useCase.isProbeActive, isFalse);

      async.elapse(interval * 5);
      async.flushMicrotasks();
      expect(probe.pings, hasLength(1));
    });
  });
}
