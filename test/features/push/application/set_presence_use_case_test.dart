import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/set_presence_use_case.dart';

// FDC-09 §6.3 write side — SetPresenceUseCase: foreground/background self-publish
// + foreground heartbeat. The move-feature gate (TC-09-07) lives at the
// P2PServiceImpl layer (p2p_service_impl_presence_cache_test.dart, mirroring
// FDC-08's C3b); the unknown-action→unsupported MAPPING (TC-09-08) lives at the
// bridge-client layer (p2p_bridge_client_presence_test.dart). Here we lock the
// use-case behaviour: when its setter reports `unsupported`, it emits the skip
// event and does NOT retry/spam (TC-09-08b).

/// Records every setPresence call and returns a configurable result. An optional
/// [gate] makes setPresence hang so the non-blocking pause contract is testable.
class _FakePresenceSetter implements RelayPresenceSet {
  final List<({String state, int ttlMs})> calls = [];
  PresenceSetResult result = PresenceSetResult.published;
  Completer<void>? gate;

  @override
  Future<PresenceSetResult> setPresence(String state, int ttlMs) async {
    calls.add((state: state, ttlMs: ttlMs));
    if (gate != null) {
      await gate!.future;
    }
    return result;
  }
}

void main() {
  late List<Map<String, dynamic>> events;

  setUp(() {
    flowEventLoggingEnabled = false;
    events = [];
    debugSetFlowEventSink((p) => events.add(Map<String, dynamic>.from(p)));
  });

  tearDown(() => debugSetFlowEventSink(null));

  List<Map<String, dynamic>> eventsNamed(String name) =>
      events.where((e) => e['event'] == name).toList();

  // TC-09-04 — onForegrounded publishes `foreground` exactly once with the
  // 180 s TTL + emits PRESENCE_SELF_PUBLISH{state: foreground}.
  test('TC-09-04: onForegrounded publishes foreground once', () async {
    final setter = _FakePresenceSetter();
    final useCase = SetPresenceUseCase(presenceSetter: setter);
    addTearDown(useCase.dispose);

    await useCase.onForegrounded();

    expect(setter.calls, hasLength(1));
    expect(setter.calls.single.state, 'foreground');
    expect(setter.calls.single.ttlMs, 180000);

    final pub = eventsNamed('PRESENCE_SELF_PUBLISH');
    expect(pub, hasLength(1));
    expect((pub.single['details'] as Map)['state'], 'foreground');
    expect((pub.single['details'] as Map).containsKey('bestEffort'), isFalse);
  });

  // TC-09-05 — onBackgrounded fires a best-effort `background` publish that is
  // fire-and-forget: it returns immediately even though the publish HANGS, and
  // the flow event carries bestEffort:true (the discriminator vs TC-09-04).
  // Mutation (await the publish) would make this time out.
  test('TC-09-05: onBackgrounded background publish is best-effort, non-blocking', () async {
    final setter = _FakePresenceSetter()..gate = Completer<void>();
    final useCase = SetPresenceUseCase(presenceSetter: setter);
    addTearDown(useCase.dispose);

    // Hung setPresence must NOT block onBackgrounded.
    await useCase.onBackgrounded().timeout(
      const Duration(milliseconds: 200),
      onTimeout: () => fail('onBackgrounded blocked on the (hung) publish'),
    );

    expect(setter.calls, hasLength(1));
    expect(setter.calls.single.state, 'background');

    final pub = eventsNamed('PRESENCE_SELF_PUBLISH');
    expect(pub, hasLength(1));
    expect((pub.single['details'] as Map)['state'], 'background');
    expect((pub.single['details'] as Map)['bestEffort'], isTrue);

    setter.gate!.complete(); // release the hung publish before teardown
  });

  // TC-09-06 — the foreground heartbeat re-publishes per interval and is
  // CANCELLED on background (so it can never fire while suspended).
  test('TC-09-06: foreground heartbeat refreshes TTL + cancels on pause', () {
    fakeAsync((async) {
      final setter = _FakePresenceSetter();
      final useCase = SetPresenceUseCase(
        presenceSetter: setter,
        heartbeatInterval: const Duration(seconds: 60),
      );
      addTearDown(useCase.dispose);

      useCase.onForegrounded(); // initial publish + arm heartbeat
      async.flushMicrotasks();
      expect(setter.calls, hasLength(1));
      expect(useCase.isHeartbeatActive, isTrue);

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(setter.calls, hasLength(2)); // heartbeat tick 1

      async.elapse(const Duration(seconds: 60));
      async.flushMicrotasks();
      expect(setter.calls, hasLength(3)); // heartbeat tick 2
      expect(setter.calls.every((c) => c.state == 'foreground'), isTrue);

      useCase.onBackgrounded(); // cancels heartbeat + one background publish
      async.flushMicrotasks();
      expect(useCase.isHeartbeatActive, isFalse);
      final afterPause = setter.calls.length; // 3 fg + 1 bg
      expect(setter.calls.last.state, 'background');

      async.elapse(const Duration(seconds: 180)); // no more ticks while paused
      async.flushMicrotasks();
      expect(setter.calls, hasLength(afterPause));
    });
  });

  // TC-09-08b — when the setter reports `unsupported` (old relay), the use-case
  // emits PRESENCE_SELF_PUBLISH_UNSUPPORTED and does NOT retry/spam.
  test('TC-09-08: unsupported old relay → skip event, no retry', () async {
    final setter = _FakePresenceSetter()..result = PresenceSetResult.unsupported;
    final useCase = SetPresenceUseCase(presenceSetter: setter);
    addTearDown(useCase.dispose);

    await useCase.onForegrounded();

    expect(setter.calls, hasLength(1)); // published once, not retried
    expect(eventsNamed('PRESENCE_SELF_PUBLISH_UNSUPPORTED'), hasLength(1));
    expect(
      (eventsNamed('PRESENCE_SELF_PUBLISH_UNSUPPORTED').single['details']
          as Map)['state'],
      'foreground',
    );
  });

  // TC-181-05 — dispose() cancels the heartbeat: NO further publishes fire after
  // teardown (the 60 s Timer.periodic would otherwise leak across hot-restart /
  // node-reinit). Mutation: remove `_stopHeartbeat()` from dispose() → ticks
  // continue → red.
  test('TC-181-05: dispose() stops the heartbeat, no further publishes', () {
    fakeAsync((async) {
      final setter = _FakePresenceSetter();
      final useCase = SetPresenceUseCase(
        presenceSetter: setter,
        heartbeatInterval: const Duration(seconds: 60),
      );

      useCase.onForegrounded(); // initial foreground publish + arm heartbeat
      async.flushMicrotasks();
      expect(setter.calls, hasLength(1));
      expect(useCase.isHeartbeatActive, isTrue);

      useCase.dispose();
      expect(useCase.isHeartbeatActive, isFalse);

      async.elapse(const Duration(seconds: 180)); // 3 would-be ticks
      async.flushMicrotasks();
      expect(setter.calls, hasLength(1)); // none fired after dispose
    });
  });

  // TC-181-07 — a `blocked` (account-move paused) or `failed` (network drop)
  // result is non-load-bearing: it never throws and never retries/spams. (The
  // `unsupported` old-relay case is TC-09-08.) Mutation: make _publish rethrow on
  // a non-published result → the awaited onForegrounded() throws → red.
  test('TC-181-07: blocked and failed results never throw, no retry', () async {
    for (final r in [PresenceSetResult.blocked, PresenceSetResult.failed]) {
      final setter = _FakePresenceSetter()..result = r;
      final useCase = SetPresenceUseCase(presenceSetter: setter);
      addTearDown(useCase.dispose);

      // Neither edge may throw on a non-published result.
      await useCase.onForegrounded();
      await useCase.onBackgrounded();

      // One publish per edge — no retry/spam on the degraded result.
      expect(setter.calls.where((c) => c.state == 'foreground'), hasLength(1));
      expect(setter.calls.where((c) => c.state == 'background'), hasLength(1));
    }
  });
}
