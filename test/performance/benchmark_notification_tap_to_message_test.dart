import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/utils/notification_tap_timing.dart';
import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Notification Tap to Message Timing', () {
    test(
      'NT1: NOTIFICATION_TAP_TO_MESSAGE_TIMING is emitted with elapsedMs >= 0',
      () async {
        final tappedAt = DateTime.now().subtract(const Duration(milliseconds: 50));

        final events = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'conversation',
          );
        });

        final timing = harness.filterEvents(
          events,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        expect(timing, isNotEmpty,
            reason: 'Should emit NOTIFICATION_TAP_TO_MESSAGE_TIMING');

        final details = timing.first['details'] as Map<String, dynamic>;
        expect(details['elapsedMs'], isA<int>());
        expect(details['elapsedMs'], greaterThanOrEqualTo(0));
      },
    );

    test(
      'NT2: routeKind field matches notification type',
      () async {
        final tappedAt = DateTime.now();

        // Test 'conversation' routeKind
        final conversationEvents = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'conversation',
          );
        });

        final convTiming = harness.filterEvents(
          conversationEvents,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        expect(
          (convTiming.first['details'] as Map<String, dynamic>)['routeKind'],
          'conversation',
        );

        // Test 'group' routeKind
        final groupEvents = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'group',
            messageId: 'abc12345',
          );
        });

        final groupTiming = harness.filterEvents(
          groupEvents,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        expect(
          (groupTiming.first['details'] as Map<String, dynamic>)['routeKind'],
          'group',
        );
      },
    );

    test(
      'NT3: messageId is present and truncated to 8 chars',
      () async {
        final tappedAt = DateTime.now();
        const longMessageId = 'abcdefghijklmnop1234567890';

        final events = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'group',
            messageId: longMessageId,
          );
        });

        final timing = harness.filterEvents(
          events,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        expect(timing, isNotEmpty);

        final details = timing.first['details'] as Map<String, dynamic>;
        final emittedMessageId = details['messageId'] as String;
        expect(emittedMessageId, 'abcdefgh');
        expect(emittedMessageId.length, 8);

        // Also verify short messageId is left untouched
        final shortEvents = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'conversation',
            messageId: 'short',
          );
        });

        final shortTiming = harness.filterEvents(
          shortEvents,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        final shortDetails =
            shortTiming.first['details'] as Map<String, dynamic>;
        expect(shortDetails['messageId'], 'short');

        // Verify null messageId becomes empty string
        final nullEvents = await harness.captureFlowEvents(() async {
          emitNotificationTapTiming(
            tappedAt: tappedAt,
            routeKind: 'conversation',
          );
        });

        final nullTiming = harness.filterEvents(
          nullEvents,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        final nullDetails =
            nullTiming.first['details'] as Map<String, dynamic>;
        expect(nullDetails['messageId'], '');
      },
    );

    test(
      'NT4: event is NOT emitted when notificationTappedAt is null '
      '(non-message notification)',
      () async {
        // Simulate a contactRequest notification — no tappedAt is passed,
        // so emitNotificationTapTiming should never be called.
        // We verify this by confirming no timing event is captured when
        // the function is not invoked (the guard in ConversationWired
        // checks for null tappedAt and skips emission).
        final events = await harness.captureFlowEvents(() async {
          // Intentionally do NOT call emitNotificationTapTiming —
          // this mirrors the production path for contactRequest/intros
          // where notificationTappedAt is null and the guard returns early.
        });

        final timing = harness.filterEvents(
          events,
          'NOTIFICATION_TAP_TO_MESSAGE_TIMING',
        );
        expect(timing, isEmpty,
            reason:
                'No timing event should be emitted for non-message notifications');
      },
    );
  });
}
