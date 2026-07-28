import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';

void main() {
  group('handleAppResumed — stale export-pause recovery', () {
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

    test('successful recovery emits the recovered event and resume proceeds',
        () async {
      var recoveryCalls = 0;

      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverInterruptedExportPause: () async {
          recoveryCalls++;
          return true;
        },
      );

      expect(recoveryCalls, 1);
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERED'),
        hasLength(1),
      );
    });

    test('no-op recovery stays silent', () async {
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverInterruptedExportPause: () async => false,
      );

      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERED'),
        isEmpty,
      );
      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERY_FAILED'),
        isEmpty,
      );
    });

    test('a throwing recovery is contained and resume continues', () async {
      await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverInterruptedExportPause: () async =>
            throw StateError('keychain still locked'),
      );

      expect(
        eventsNamed('APP_LIFECYCLE_RESUME_EXPORT_PAUSE_RECOVERY_FAILED'),
        hasLength(1),
      );
      // The resume pipeline itself must not be aborted by the failure.
      expect(eventsNamed('APP_LIFECYCLE_RESUME_BEGIN'), hasLength(1));
    });

    test('recovery runs BEFORE the migration network gate', () async {
      // The gate denies everything while the stale pause persists, so the
      // recovery hook is only useful if it executes first.
      final order = <String>[];

      final result = await handleAppResumed(
        bridge: bridge,
        p2pService: p2pService,
        recoverInterruptedExportPause: () async {
          order.add('recover');
          return true;
        },
        accountMigrationNetworkGate: ({peerId, required operation}) async {
          order.add('gate:$operation');
          return false; // still gated: resume is skipped, but AFTER recovery
        },
      );

      expect(result, isFalse);
      expect(order.first, 'recover');
      expect(order.skip(1), isNotEmpty);
      expect(order.skip(1).every((entry) => entry.startsWith('gate:')), isTrue);
    });
  });
}
