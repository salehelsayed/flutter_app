import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/debug/production_journeys/production_journey_controller.dart';
import 'package:flutter_app/debug/production_journeys/production_performance_controls.dart';
import 'package:flutter_app/debug/production_journeys/sims_runtime_protocol.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../core/bridge/fake_bridge.dart';
import '../core/services/fake_p2p_service.dart';
import '../features/identity/domain/repositories/fake_identity_repository.dart';

const _online = NodeState(
  isStarted: true,
  peerId: 'local',
  sendCapabilityReady: true,
  inboxCapabilityReady: true,
  relayState: 'online',
  connections: [
    p2p.ConnectionState(
      peerId: 'relay',
      multiaddrs: [],
      direction: 'outbound',
      status: 'connected',
      isRelay: true,
    ),
  ],
);
const _degraded = NodeState(isStarted: true, peerId: 'local');

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProductionJourneyController controller;
  late FakeP2PService service;
  late FakeBridge bridge;
  var sequence = 0;
  const invocation = SimsRuntimeInvocation(
    schema: simsRuntimeConfigSchema,
    profileId: 'android.e2e.performance_relay',
    scenarioId: performanceJourney,
    role: 'alice',
    runId: 'recovery-run',
    nonce: 'recovery-nonce',
    values: {},
  );
  Future<Map<String, Object?>> command(
    String operation, [
    Map<String, Object?> arguments = const {},
  ]) => controller.execute({
    'invocation': invocation.toJson(),
    'sequence': ++sequence,
    'operation': operation,
    'arguments': arguments,
  });

  setUp(() async {
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    directory = await Directory.systemTemp.createTemp('performance-controls-');
    controller = ProductionJourneyController(
      directory: directory,
      profileId: invocation.profileId,
      invocation: invocation,
    );
    sequence = 0;
    service = FakeP2PService(initialState: _online);
    bridge = FakeBridge();
    bindProductionPerformanceControls(
      controller: controller,
      bridge: bridge,
      p2pService: service,
      identityRepository: FakeIdentityRepository(),
    );
    controller.foregroundPush.bind((_) async {});
    controller.markRuntimeReady();
    await controller.start();
  });
  tearDown(() async {
    controller.dispose();
    await directory.delete(recursive: true);
  });

  Future<void> observeRecoveryLoss() async {
    await command('performance_begin', {'window': 'recovery'});
    await command('performance_disconnect_relay');
    service.emitState(_degraded);
    final receipt = await command('performance_snapshot');
    expect(receipt['badge'], 'connecting');
  }

  test(
    'observed loss permits health and inbox after automatic recovery',
    () async {
      await observeRecoveryLoss();
      service.emitState(_online);
      final result = await command('performance_recover');
      expect(result['badge'], 'onlineDotted');
      expect(service.performImmediateHealthCheckCallCount, 1);
      expect(service.drainOfflineInboxCallCount, 1);
      expect(bridge.commandLog, ['peer:disconnect']);
      await expectLater(command('performance_recover'), throwsStateError);
      expect(service.performImmediateHealthCheckCallCount, 1);
    },
  );

  test('C-Sim-2 runs three recoveries, one per repeated window', () async {
    for (final window in [
      'repeated-recovery-1',
      'repeated-recovery-2',
      'repeated-recovery-3',
    ]) {
      service.emitState(_online);
      await command('performance_begin', {'window': window});
      await command('performance_disconnect_relay');
      service.emitState(_degraded);
      await command('performance_snapshot');
      await command('performance_recover');
      await expectLater(command('performance_recover'), throwsStateError);
    }
    expect(service.performImmediateHealthCheckCallCount, 3);
    expect(service.drainOfflineInboxCallCount, 3);
    expect(bridge.commandLog, [
      'peer:disconnect',
      'peer:disconnect',
      'peer:disconnect',
    ]);
    service.emitState(_online);
    await expectLater(
      command('performance_begin', {'window': 'repeated-recovery-4'}),
      throwsStateError,
    );
  });

  test(
    'foreground recovery also operates while loss is still visible',
    () async {
      await observeRecoveryLoss();
      await command('performance_recover');
      expect(service.performImmediateHealthCheckCallCount, 1);
      expect(service.drainOfflineInboxCallCount, 1);
    },
  );

  test('disconnect alone cannot substitute for observed relay loss', () async {
    await command('performance_begin', {'window': 'recovery'});
    await command('performance_disconnect_relay');
    await expectLater(command('performance_recover'), throwsStateError);
    expect(service.performImmediateHealthCheckCallCount, 0);
    expect(service.drainOfflineInboxCallCount, 0);
  });

  test('state observed before disconnect cannot authorize recovery', () async {
    await command('performance_begin', {'window': 'recovery'});
    service.emitState(_degraded);
    await command('performance_snapshot');
    service.emitState(_online);
    await command('performance_disconnect_relay');
    await expectLater(command('performance_recover'), throwsStateError);
    expect(service.performImmediateHealthCheckCallCount, 0);
  });

  test('recovery loss receipt cannot cross measurement windows', () async {
    await observeRecoveryLoss();
    service.emitState(_online);
    await command('performance_begin', {'window': 'healthy'});
    await expectLater(command('performance_recover'), throwsStateError);
    expect(service.performImmediateHealthCheckCallCount, 0);
  });

  test(
    'health failure is preserved and does not fabricate inbox completion',
    () async {
      await observeRecoveryLoss();
      service.throwOnHealthCheck = true;
      await expectLater(command('performance_recover'), throwsException);
      expect(service.performImmediateHealthCheckCallCount, 1);
      expect(service.drainOfflineInboxCallCount, 0);
      await expectLater(command('performance_recover'), throwsStateError);
    },
  );
}
