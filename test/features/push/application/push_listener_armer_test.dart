import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/push/application/push_listener_armer.dart';

// 191 (Fix D2): PushListenerArmer makes the foreground-push / open-app listener
// arm observable (PUSH_LISTENERS_ARMED emitted exactly once), retryable (a
// not-ready arm is a no-op that does NOT consume the latch), and idempotent
// (repeated ready arms never double-subscribe).
void main() {
  tearDown(() => debugSetFlowEventSink(null));

  test('arms when firebaseReady, emits PUSH_LISTENERS_ARMED exactly once', () {
    var subscribeCalls = 0;
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);

    final armer = PushListenerArmer(
      firebaseReady: () => true,
      subscribe: () => subscribeCalls += 1,
      platform: 'ios',
    );

    armer.arm();
    armer.arm();

    expect(armer.armed, isTrue);
    expect(subscribeCalls, 1);
    final armedEvents = events
        .where((event) => event['event'] == 'PUSH_LISTENERS_ARMED')
        .toList();
    expect(armedEvents, hasLength(1));
    expect(armedEvents.single['details']['platform'], 'ios');
    expect(armedEvents.single['details']['kinds'], isNotEmpty);
  });

  test(
    'not-ready arm attempt is a no-op that does NOT consume the latch; '
    'later ready attempt arms',
    () {
      var subscribeCalls = 0;
      var ready = false;
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);

      final armer = PushListenerArmer(
        firebaseReady: () => ready,
        subscribe: () => subscribeCalls += 1,
        platform: 'ios',
      );

      // Not ready: no-op, latch NOT consumed.
      armer.arm();
      expect(armer.armed, isFalse);
      expect(subscribeCalls, 0);
      expect(
        events.where((event) => event['event'] == 'PUSH_LISTENERS_ARMED'),
        isEmpty,
      );

      // Becomes ready (the third arm point on Firebase readiness): now arms.
      ready = true;
      armer.arm();
      expect(armer.armed, isTrue);
      expect(subscribeCalls, 1);
      expect(
        events.where((event) => event['event'] == 'PUSH_LISTENERS_ARMED'),
        hasLength(1),
      );
    },
  );

  test('repeated arm calls never double-subscribe', () {
    var subscribeCalls = 0;

    final armer = PushListenerArmer(
      firebaseReady: () => true,
      subscribe: () => subscribeCalls += 1,
      platform: 'android',
    );

    armer.arm();
    armer.arm();
    armer.arm();

    expect(subscribeCalls, 1);
  });

  test('a throwing subscribe emits PUSH_LISTENER_ERROR and does not emit ARMED', () {
    final events = <Map<String, dynamic>>[];
    debugSetFlowEventSink(events.add);

    final armer = PushListenerArmer(
      firebaseReady: () => true,
      subscribe: () => throw StateError('subscribe boom'),
      platform: 'ios',
    );

    armer.arm();

    expect(
      events.where((event) => event['event'] == 'PUSH_LISTENER_ERROR'),
      hasLength(1),
    );
    expect(
      events.where((event) => event['event'] == 'PUSH_LISTENERS_ARMED'),
      isEmpty,
    );
  });
}
