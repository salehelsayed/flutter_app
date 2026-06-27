import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../integration_test/_support/node_readiness.dart';

void main() {
  group('node readiness predicates', () {
    const onlineDirectState = NodeState(
      isStarted: true,
      sendCapabilityReady: true,
      inboxCapabilityReady: true,
      directReady: true,
      relayState: 'degraded',
    );

    test('isSendableBadgeState is true for onlineDirect', () {
      expect(
        onlineDirectState.badgeReadinessState,
        BadgeReadinessState.onlineDirect,
      );
      expect(isSendableBadgeState(onlineDirectState), isTrue);
    });

    test('onlineDirect is not relay-ready nor plain-online', () {
      expect(isRelayReadyBadgeState(onlineDirectState), isFalse);
      expect(isPlainOnlineBadgeState(onlineDirectState), isFalse);
    });
  });
}
