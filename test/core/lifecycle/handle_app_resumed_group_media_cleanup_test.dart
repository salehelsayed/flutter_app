import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

// 235 (TC-235-10): resume-time deletion-journal cleanup is LOCAL-ONLY work.
// It must run BEFORE the account-migration network gate (a denied gate must
// not leave committed deletes half-cleaned) and its failure must never break
// the resume path.

void main() {
  group('handleAppResumed — 235 group media deletion cleanup', () {
    late FakeBridge bridge;
    late FakeP2PService p2pService;
    late List<Map<String, dynamic>> flowEvents;

    setUp(() {
      bridge = FakeBridge();
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'my-peer',
          circuitAddresses: ['/p2p-circuit/addr1'],
        ),
      );
      flowEvents = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flowEvents.add);
    });

    tearDown(() {
      debugSetFlowEventSink(null);
      p2pService.dispose();
    });

    List<Map<String, dynamic>> eventsNamed(String name) => flowEvents
        .where((event) => event['event'] == name)
        .toList(growable: false);

    test(
      'GMA-10R resume cleanup runs when network recovery is denied',
      () async {
        final order = <String>[];
        final result = await handleAppResumed(
          bridge: bridge,
          p2pService: p2pService,
          groupMediaDeletionCleanupFn: () async {
            order.add('cleanup');
          },
          accountMigrationNetworkGate: ({peerId, required operation}) async {
            order.add('gate:$operation');
            return false; // deny every networked resume step
          },
        );

        expect(result, isFalse, reason: 'the denied gate still blocks resume');
        expect(order.first, 'cleanup', reason: 'cleanup runs BEFORE the gate');
        expect(order.skip(1), isNotEmpty);
        expect(
          order.skip(1).every((entry) => entry.startsWith('gate:')),
          isTrue,
        );
        expect(
          eventsNamed('APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_DONE'),
          hasLength(1),
        );
      },
    );

    test('a throwing cleanup is contained and resume continues', () async {
      var gateCalls = 0;
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        groupMediaDeletionCleanupFn: () async {
          throw StateError('injected cleanup failure');
        },
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          gateCalls += 1;
          return false;
        },
      );

      expect(
        gateCalls,
        greaterThan(0),
        reason: 'a failed cleanup never blocks the resume pipeline',
      );
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_FAILED'),
        hasLength(1),
      );
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_DONE'),
        isEmpty,
      );
    });

    test('resume without a cleanup seam behaves exactly as before', () async {
      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        accountMigrationNetworkGate: ({peerId, required operation}) async =>
            false,
      );
      expect(result, isFalse);
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_DONE'),
        isEmpty,
      );
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_GROUP_MEDIA_CLEANUP_FAILED'),
        isEmpty,
      );
    });
  });
}
