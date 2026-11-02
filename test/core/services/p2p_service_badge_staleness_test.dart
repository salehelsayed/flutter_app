import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../bridge/fake_bridge.dart';
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';

void main() {
  test(
    'LL-23 stale online status cannot override a failed inbox probe',
    () async {
      final onlineStatus = <String, dynamic>{
        'ok': true,
        'peerId': 'test-peer',
        'isStarted': true,
        'listenAddresses': <String>[],
        'circuitAddresses': ['/p2p-circuit/relay1'],
        'connections': <dynamic>[],
        'relayState': 'online',
      };
      final emptyInbox = <String, dynamic>{
        'ok': true,
        'messages': <dynamic>[],
        'hasMore': false,
        'custodyContract': ackOrExpiryInboxCustodyContract,
      };
      final bridge = FakeBridge(
        initialResponses: {
          'node:start': onlineStatus,
          'node:status': onlineStatus,
          'inbox:retrieve': emptyInbox,
          'inbox:retrieve_pending': emptyInbox,
        },
      );
      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: InMemoryInboxStagingRepository(),
      );
      addTearDown(service.dispose);

      await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'test-peer');
      service.recordSuccessfulSendProof(
        source: 'test_send',
        trigger: 'test_action',
        sendPath: 'direct',
      );
      await service.retrieveInbox();
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );

      bridge.responses['inbox:retrieve_pending'] = {
        'ok': false,
        'errorCode': 'RELAY_UNREACHABLE',
      };
      await service.performImmediateHealthCheck();

      expect(bridge.commandLog, contains('inbox:retrieve_pending'));
      expect(service.currentState.relayState, 'online');
      expect(service.currentState.inboxCapabilityReady, isFalse);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.connecting,
      );

      bridge.responses['inbox:retrieve_pending'] = emptyInbox;
      await service.performImmediateHealthCheck();
      expect(service.currentState.inboxCapabilityReady, isTrue);
      expect(
        service.currentState.badgeReadinessState,
        BadgeReadinessState.onlineDotted,
      );
    },
  );
}
