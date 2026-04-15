/// Simulator Benchmark: Timeout Accuracy (Test H)
///
/// Forces each configured timeout to fire and measures actualMs vs configuredMs.
/// Run: flutter test integration_test/benchmark_timeout_accuracy_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

import 'benchmark_helpers.dart';

const _configuredSharedDir = String.fromEnvironment(
  'BENCHMARK_SHARED_DIR',
  defaultValue: '/tmp',
);
const _configuredRunId = String.fromEnvironment(
  'BENCHMARK_RUN_ID',
  defaultValue: 'adhoc',
);
const _expectedGoTimeoutMessages = 2;

String _sharedPath(String name) =>
    '$_configuredSharedDir/h_${_configuredRunId}_$name';

void _writeSharedJson(String name, Map<String, dynamic> value) {
  Directory(_configuredSharedDir).createSync(recursive: true);
  File(_sharedPath(name)).writeAsStringSync(jsonEncode(value));
}

void _writeSharedSignal(String name) {
  Directory(_configuredSharedDir).createSync(recursive: true);
  File(_sharedPath(name)).writeAsStringSync('ok');
}

Future<void> _waitForSharedSignal(
  String name, {
  Duration timeout = const Duration(minutes: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sharedPath(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('Timed out waiting for shared signal: $name');
}

class _HangingBridge extends Bridge {
  @override
  bool get isInitialized => true;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) => Completer<String>().future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('H-Sim-1: Dart-side timeout accuracy', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: DART-SIDE TIMEOUTS (H-Sim-1)');
    print('${'═' * 60}\n');

    final results = <String, _TimeoutResult>{};
    final hangingBridge = _HangingBridge();

    // Relay probe uses a Dart-side .timeout(const Duration(seconds: 5)).
    print('[TEST] relay probe wrapper timeout (5s configured)...');
    var sw = Stopwatch()..start();
    try {
      await callP2PRelayProbe(
        hangingBridge,
        peerId: '12D3KooWTimeoutHarnessRelayProbe000000000000',
      );
      fail('callP2PRelayProbe should time out when the bridge never responds');
    } on TimeoutException {}
    sw.stop();
    results['relay_probe'] = _TimeoutResult(
      configured: 5000,
      actual: sw.elapsedMilliseconds,
    );

    // Foreground send paths rely on ordinary Dart Future.timeout wrappers too.
    // Measure a generic 2s timeout with a never-completing future so the
    // simulator harness reports the actual scheduler drift instead of a fast
    // transport error.
    print('[TEST] generic foreground timeout wrapper (2s configured)...');
    sw = Stopwatch()..start();
    try {
      await Completer<void>().future.timeout(const Duration(seconds: 2));
      fail('The generic timeout wrapper should time out');
    } on TimeoutException {}
    sw.stop();
    results['foreground_wrapper'] = _TimeoutResult(
      configured: 2000,
      actual: sw.elapsedMilliseconds,
    );

    // Print results
    print('\n--- Dart-side Timeout Results ---');
    var maxDeviation = 0.0;
    for (final entry in results.entries) {
      final r = entry.value;
      final deviation = (r.actual - r.configured).abs() / r.configured * 100;
      if (deviation > maxDeviation) maxDeviation = deviation;

      print(
        '[BENCHMARK] sim_${entry.key}_timeout_actual_ms = ${r.actual}ms '
        '(configured=${r.configured}ms, deviation=${deviation.toStringAsFixed(1)}%)',
      );
    }
    print(
      '[BENCHMARK] sim_dart_timeout_max_deviation_pct = '
      '${maxDeviation.toStringAsFixed(1)}%',
    );
  });

  testWidgets('H-Sim-2: Go-side timeout events via push', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: GO-SIDE TIMEOUTS (H-Sim-2)');
    print('${'═' * 60}\n');

    if (_configuredRunId == 'adhoc') {
      print(
        '[SKIP] H-Sim-2 requires '
        '`integration_test/scripts/run_timeout_accuracy_benchmark.dart`',
      );
      return;
    }

    final receiver = await createBenchmarkNode();
    await receiver.startAndWaitOnline();

    final hasCircuitAddresses = await waitFor(
      () => receiver.service.currentState.circuitAddresses.isNotEmpty,
      timeout: const Duration(seconds: 30),
      interval: const Duration(milliseconds: 200),
      label: 'receiver circuit address',
    );
    expect(
      hasCircuitAddresses,
      isTrue,
      reason: 'Receiver must expose a circuit address for timeout testing',
    );

    final receiverAddresses = receiver.service.currentState.circuitAddresses;
    _writeSharedJson('receiver_fixture.json', {
      'peerId': receiver.peerId,
      'addresses': receiverAddresses,
    });

    await _waitForSharedSignal('send_go');
    final events = await captureFlowEventsUntil(
      () async {
        _writeSharedSignal('capture_ready');
        await _waitForSharedSignal(
          'cli_send_done',
          timeout: const Duration(seconds: 30),
        );
      },
      postActionTimeout: const Duration(seconds: 8),
      until: (captured) {
        return filterEvents(captured, 'timeout:fired').length >=
                _expectedGoTimeoutMessages &&
            filterEvents(captured, 'message:direct_ack_timing').length >=
                _expectedGoTimeoutMessages;
      },
    );

    final timeoutEvents = filterEvents(events, 'timeout:fired');
    final ackEvents = filterEvents(events, 'message:direct_ack_timing');
    print('\n--- Go-side Timeout Results ---');
    print('[BENCHMARK] sim_go_timeout_events_count = ${timeoutEvents.length}');
    print('[BENCHMARK] sim_go_ack_timeout_events_count = ${ackEvents.length}');

    var maxDeviation = 0.0;
    for (final e in timeoutEvents) {
      final d = e['details'] as Map<String, dynamic>;
      final name = d['timeoutName'] as String? ?? 'unknown';
      final configuredMs = (d['configuredMs'] as num?)?.toInt() ?? 0;
      final actualMs = (d['actualMs'] as num?)?.toInt() ?? 0;

      final deviation = configuredMs > 0
          ? (actualMs - configuredMs).abs() / configuredMs * 100
          : 0.0;
      if (deviation > maxDeviation) maxDeviation = deviation;

      print(
        '[BENCHMARK] sim_${name}_actual_ms = ${actualMs}ms '
        '(configured=${configuredMs}ms, '
        'deviation=${deviation.toStringAsFixed(1)}%)',
      );
    }

    for (final e in ackEvents) {
      final d = e['details'] as Map<String, dynamic>;
      print(
        '[BENCHMARK] sim_direct_ack_wait_ms = ${d['waitMs'] ?? 'n/a'} '
        'outcome=${d['outcome'] ?? 'n/a'}',
      );
    }

    expect(timeoutEvents, isNotEmpty, reason: 'Go timeout events should fire');
    print(
      '[BENCHMARK] sim_go_timeout_max_deviation_pct = '
      '${maxDeviation.toStringAsFixed(1)}%',
    );
    expect(
      maxDeviation,
      lessThan(10.0),
      reason: 'All timeouts should fire within 10% of configured',
    );

    await receiver.dispose();
  });
}

class _TimeoutResult {
  final int configured;
  final int actual;
  _TimeoutResult({required this.configured, required this.actual});
}
