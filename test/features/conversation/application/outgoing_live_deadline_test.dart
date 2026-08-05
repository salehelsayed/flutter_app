import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/features/conversation/application/outgoing_live_deadline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'R3 direct deadline uses one T0 remaining budget and exact reserve margins',
    () {
      var elapsed = Duration.zero;
      final deadline = OutgoingLiveDeadline(() => elapsed);

      expect(outgoingLiveBudget, const Duration(seconds: 6));
      expect(committedAckReserve, const Duration(seconds: 3));
      expect(p2pBridgeWatchdogMargin, const Duration(milliseconds: 500));
      expect(outgoingDiscoverPhaseCap, const Duration(seconds: 2));
      expect(outgoingDialPhaseCap, const Duration(milliseconds: 1500));

      expect(deadline.remaining, outgoingLiveBudget);
      expect(deadline.allocatePhaseTimeoutMs(outgoingDiscoverPhaseCap), 2000);
      expect(deadline.allocatePhaseTimeoutMs(outgoingDialPhaseCap), 1500);
      expect(deadline.allocateCommittedSendTimeoutMs(), 5500);

      elapsed = const Duration(milliseconds: 1250);
      expect(deadline.remaining, const Duration(milliseconds: 4750));
      expect(deadline.allocateCommittedSendTimeoutMs(), 4250);

      elapsed = outgoingLiveBudget + const Duration(milliseconds: 1);
      expect(deadline.remaining, Duration.zero);
      expect(deadline.allocatePhaseTimeoutMs(outgoingDiscoverPhaseCap), isNull);
      expect(deadline.allocateCommittedSendTimeoutMs(), isNull);
    },
  );

  test('R3 phase admission uses serialized milliseconds and clamps to cap', () {
    var elapsed = Duration.zero;
    final deadline = OutgoingLiveDeadline(() => elapsed);

    elapsed = const Duration(microseconds: 5499001);
    expect(deadline.remaining, const Duration(microseconds: 500999));
    expect(deadline.allocatePhaseTimeoutMs(outgoingDiscoverPhaseCap), isNull);

    elapsed = const Duration(milliseconds: 5499);
    expect(deadline.remaining, const Duration(milliseconds: 501));
    expect(deadline.allocatePhaseTimeoutMs(outgoingDiscoverPhaseCap), 1);

    elapsed = Duration.zero;
    final discoverMs = deadline.allocatePhaseTimeoutMs(
      outgoingDiscoverPhaseCap,
    );
    final dialMs = deadline.allocatePhaseTimeoutMs(outgoingDialPhaseCap);
    expect(discoverMs, outgoingDiscoverPhaseCap.inMilliseconds);
    expect(dialMs, outgoingDialPhaseCap.inMilliseconds);
    expect(
      discoverMs! + p2pBridgeWatchdogMargin.inMilliseconds,
      lessThanOrEqualTo(deadline.remaining.inMilliseconds),
    );
    expect(
      dialMs! + p2pBridgeWatchdogMargin.inMilliseconds,
      lessThanOrEqualTo(deadline.remaining.inMilliseconds),
    );
  });

  test('R3 committed send admission compares after millisecond flooring', () {
    var elapsed = Duration.zero;
    final deadline = OutgoingLiveDeadline(() => elapsed);

    final rows = <({Duration availableAfterMargin, int? expected})>[
      (
        availableAfterMargin: const Duration(milliseconds: 3000),
        expected: null,
      ),
      (
        availableAfterMargin: const Duration(microseconds: 3000999),
        expected: null,
      ),
      (
        availableAfterMargin: const Duration(milliseconds: 3001),
        expected: 3001,
      ),
    ];

    for (final row in rows) {
      final requiredRemaining =
          row.availableAfterMargin + p2pBridgeWatchdogMargin;
      elapsed = outgoingLiveBudget - requiredRemaining;
      expect(
        deadline.allocateCommittedSendTimeoutMs(),
        row.expected,
        reason:
            'available=${row.availableAfterMargin.inMicroseconds}us must be '
            'admitted only after serialized milliseconds exceed the reserve',
      );
    }
  });
}
