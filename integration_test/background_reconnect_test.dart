// Integration test: Background → Foreground reconnection smoke test.
//
// Runs on a REAL device with the real Go bridge and relay server.
// Exercises the full reconnection lifecycle:
//   1. Start node → wait for Online (circuit addresses from relay)
//   2. Disconnect relay peer → verify Degraded (simulates background drop)
//   3. Run handleAppResumed() → verify recovery back to Online
//   4. Measure timing at each step
//
// Run on device:
//   flutter test integration_test/background_reconnect_test.dart -d <DEVICE_ID>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

/// Relay peer ID extracted from the default rendezvous address.
final _relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

/// Wait for a condition with timeout, polling every [interval].
Future<bool> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
  Duration interval = const Duration(milliseconds: 500),
  String label = '',
}) async {
  final stopwatch = Stopwatch()..start();
  while (stopwatch.elapsed < timeout) {
    if (condition()) {
      stopwatch.stop();
      print('[WAIT] "$label" satisfied after ${stopwatch.elapsedMilliseconds}ms');
      return true;
    }
    await Future<void>.delayed(interval);
  }
  stopwatch.stop();
  print('[WAIT] "$label" TIMED OUT after ${stopwatch.elapsedMilliseconds}ms');
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('Background → Foreground reconnection smoke test', (
    tester,
  ) async {
    print('\n');
    print('═' * 60);
    print('  BACKGROUND → FOREGROUND RECONNECTION TEST');
    print('═' * 60);
    print('');

    // ---------------------------------------------------------------
    // 1. Initialize bridge and generate identity
    // ---------------------------------------------------------------
    print('[PHASE 1] Initializing bridge...');
    final bridge = GoBridgeClient();
    await bridge.initialize();
    print('[PHASE 1] Bridge initialized');

    print('[PHASE 1] Generating identity...');
    final genResponse = await bridge.send(jsonEncode({
      'cmd': 'identity.generate',
      'payload': {},
    }));
    final genResult = jsonDecode(genResponse) as Map<String, dynamic>;
    expect(genResult['ok'], true, reason: 'identity.generate should succeed');
    final identity = genResult['identity'] as Map<String, dynamic>;
    final peerId = identity['peerId'] as String;
    final privateKey = identity['privateKey'] as String;
    print('[PHASE 1] Identity: ${peerId.substring(0, 24)}...');

    // ---------------------------------------------------------------
    // 2. Start node and wait for Online
    // ---------------------------------------------------------------
    print('');
    print('─' * 60);
    print('[PHASE 2] Starting P2P node and waiting for Online...');
    final startTime = DateTime.now();

    final p2pService = P2PServiceImpl(bridge: bridge);

    // Collect state transitions for reporting
    final stateLog = <String>[];
    final stateSub = p2pService.stateStream.listen((state) {
      final health = healthFromState(state);
      final elapsed = DateTime.now().difference(startTime).inMilliseconds;
      final entry = '  +${elapsed}ms  ${health.name.toUpperCase()}'
          '  circuits=${state.circuitAddresses.length}'
          '  conns=${state.connections.length}';
      stateLog.add(entry);
      print('[STATE] $entry');
    });

    final started = await p2pService.startNode(privateKey, peerId);
    if (!started) {
      stateSub.cancel();
      p2pService.dispose();
      bridge.dispose();
      fail('P2P node failed to start (relay unreachable)');
    }

    final nodeStartedMs =
        DateTime.now().difference(startTime).inMilliseconds;
    print('[PHASE 2] Node started in ${nodeStartedMs}ms');
    print('[PHASE 2] Initial state: '
        'isStarted=${p2pService.currentState.isStarted}, '
        'circuits=${p2pService.currentState.circuitAddresses.length}');

    // Wait for circuit addresses (Online)
    final reachedOnline = await _waitFor(
      () => healthFromState(p2pService.currentState) == ConnectionHealth.online,
      timeout: const Duration(seconds: 30),
      label: 'Online after start',
    );

    final timeToOnlineMs =
        DateTime.now().difference(startTime).inMilliseconds;

    if (!reachedOnline) {
      print('[PHASE 2] FAILED: Never reached Online after ${timeToOnlineMs}ms');
      print('[PHASE 2] Final state: '
          'circuits=${p2pService.currentState.circuitAddresses.length}');

      stateSub.cancel();
      await p2pService.stopNode();
      p2pService.dispose();
      bridge.dispose();
      fail('Node did not reach Online within 30s');
    }

    print('[PHASE 2] ONLINE in ${timeToOnlineMs}ms');
    print('[PHASE 2] Circuit addresses:');
    for (final addr in p2pService.currentState.circuitAddresses) {
      print('  $addr');
    }

    // ---------------------------------------------------------------
    // 3. Simulate background: disconnect relay peer
    // ---------------------------------------------------------------
    print('');
    print('─' * 60);
    print('[PHASE 3] Simulating background — disconnecting relay peer...');
    print('[PHASE 3] Relay peer: $_relayPeerId');

    final disconnectStart = DateTime.now();

    // Disconnect from the relay to simulate what happens when iOS/Android
    // suspends the app and the relay connection times out.
    final disconnectResponse = await bridge.send(jsonEncode({
      'cmd': 'peer:disconnect',
      'payload': {'peerId': _relayPeerId},
    }));
    final disconnectResult =
        jsonDecode(disconnectResponse) as Map<String, dynamic>;
    print('[PHASE 3] Disconnect result: ${disconnectResult['ok']}');

    // Wait a moment for the node to notice the disconnect
    await Future<void>.delayed(const Duration(seconds: 2));

    // Poll current status
    final statusResponse = await bridge.send(jsonEncode({
      'cmd': 'node:status',
      'payload': {},
    }));
    final statusResult = jsonDecode(statusResponse) as Map<String, dynamic>;
    final postDisconnectState = NodeState.fromJson(statusResult);
    final postDisconnectHealth = healthFromState(postDisconnectState);

    final disconnectMs =
        DateTime.now().difference(disconnectStart).inMilliseconds;
    print('[PHASE 3] Post-disconnect state (${disconnectMs}ms):');
    print('  isStarted: ${postDisconnectState.isStarted}');
    print('  circuits: ${postDisconnectState.circuitAddresses.length}');
    print('  connections: ${postDisconnectState.connections.length}');
    print('  health: ${postDisconnectHealth.name}');

    if (postDisconnectHealth == ConnectionHealth.online) {
      print('[PHASE 3] NOTE: Still online after disconnect — '
          'relay may have auto-reconnected. Trying again with longer wait...');
      // Try disconnecting again and waiting longer
      await bridge.send(jsonEncode({
        'cmd': 'peer:disconnect',
        'payload': {'peerId': _relayPeerId},
      }));
      await Future<void>.delayed(const Duration(seconds: 5));
    }

    // ---------------------------------------------------------------
    // 4. Trigger resume recovery (handleAppResumed)
    // ---------------------------------------------------------------
    print('');
    print('─' * 60);
    print('[PHASE 4] Running handleAppResumed() — simulating foreground...');

    final resumeStart = DateTime.now();

    // Snapshot state before recovery
    print('[PHASE 4] State BEFORE resume: '
        'circuits=${p2pService.currentState.circuitAddresses.length}, '
        'health=${healthFromState(p2pService.currentState).name}');

    final bridgeOk = await handleAppResumed(
      bridge: bridge,
      p2pService: p2pService,
    );

    final resumeMs =
        DateTime.now().difference(resumeStart).inMilliseconds;
    print('[PHASE 4] handleAppResumed() completed in ${resumeMs}ms');
    print('[PHASE 4] Bridge was healthy: $bridgeOk');
    print('[PHASE 4] State AFTER resume: '
        'circuits=${p2pService.currentState.circuitAddresses.length}, '
        'health=${healthFromState(p2pService.currentState).name}');

    // ---------------------------------------------------------------
    // 5. Wait for Online (may need additional health checks)
    // ---------------------------------------------------------------
    print('');
    print('─' * 60);
    print('[PHASE 5] Waiting for Online after resume...');

    final recoveryStart = DateTime.now();
    final recoveredOnline = await _waitFor(
      () => healthFromState(p2pService.currentState) == ConnectionHealth.online,
      timeout: const Duration(seconds: 60),
      interval: const Duration(seconds: 1),
      label: 'Online after resume',
    );

    final recoveryMs =
        DateTime.now().difference(recoveryStart).inMilliseconds;
    final totalMs = DateTime.now().difference(startTime).inMilliseconds;

    // ---------------------------------------------------------------
    // 6. Report results
    // ---------------------------------------------------------------
    print('');
    print('═' * 60);
    print('  RESULTS');
    print('═' * 60);
    print('');
    print('  Time to first Online:     ${timeToOnlineMs}ms');
    print('  handleAppResumed() took:  ${resumeMs}ms');
    print('  Recovery to Online:       ${recoveryMs}ms');
    print('  Total test time:          ${totalMs}ms');
    print('');
    print('  Final state:');
    print('    isStarted:  ${p2pService.currentState.isStarted}');
    print('    circuits:   ${p2pService.currentState.circuitAddresses.length}');
    print('    connections:${p2pService.currentState.connections.length}');
    print('    health:     ${healthFromState(p2pService.currentState).name}');
    print('');
    print('  State transition log:');
    for (final entry in stateLog) {
      print(entry);
    }
    print('');

    if (recoveredOnline) {
      print('  ✓ PASS: Recovered to Online after ${recoveryMs}ms');
    } else {
      print('  ✗ FAIL: Did NOT recover to Online within 60s');
      print('    → This confirms the bug: relay reservation is not completing');
    }

    print('');
    print('═' * 60);

    // Expect recovery — this is the assertion that will catch the bug
    expect(recoveredOnline, isTrue,
        reason: 'App should recover to Online after background → foreground. '
            'Recovery took ${recoveryMs}ms. '
            'If this fails, the relay reservation is broken.');

    // Cleanup
    await stateSub.cancel();
    await p2pService.stopNode();
    p2pService.dispose();
    bridge.dispose();
  });
}
