#!/usr/bin/env dart

/// Benchmark Suite Orchestrator
///
/// Automates running all implemented simulator benchmarks and aggregates results
/// into the baseline table from 03b Section 5.
///
/// Usage:
///   dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID>
///   dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID> --scenarios B,F,G
///
/// Prerequisites:
///   - Go testpeer built: cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer/
///   - iOS simulator booted: xcrun simctl boot <SIMULATOR_ID>
///   - flutter build done (or flutter test will build on first run)
library;

import 'dart:convert';
import 'dart:io';

const _testpeerBin = 'go-mknoon/bin/testpeer';

// Harness files indexed by scenario letter.
const _singleNodeHarnesses = <String, String>{
  'B': 'integration_test/benchmark_node_startup_harness.dart',
  'BR': 'integration_test/benchmark_background_resume_harness.dart',
  'C': 'integration_test/benchmark_relay_recovery_harness.dart',
  'F': 'integration_test/benchmark_bridge_crossing_harness.dart',
  'G': 'integration_test/benchmark_encryption_harness.dart',
  'I': 'integration_test/benchmark_event_queue_harness.dart',
  'K': 'integration_test/benchmark_voice_harness.dart',
  'M': 'integration_test/benchmark_time_to_online_harness.dart',
  'N': 'integration_test/benchmark_notification_tap_harness.dart',
};

const _scriptScenarios = <String, String>{
  'H': 'integration_test/scripts/run_timeout_accuracy_benchmark.dart',
  'GP': 'integration_test/scripts/run_group_publish_benchmark.dart',
};

const _twoNodeHarnesses = <String, String>{
  'A': 'integration_test/benchmark_1_1_send_harness.dart',
  'D': 'integration_test/benchmark_inbox_harness.dart',
  'E': 'integration_test/benchmark_media_harness.dart',
  'J': 'integration_test/benchmark_connection_reuse_harness.dart',
  'L': 'integration_test/benchmark_ack_harness.dart',
  'R': 'integration_test/benchmark_routing_paths_harness.dart',
};

void main(List<String> args) async {
  final deviceId = _parseArg(args, '-d') ?? _parseArg(args, '--device');
  final scenariosStr = _parseArg(args, '--scenarios');
  final fixtureDir =
      _parseArg(args, '--fixture-dir') ?? '/tmp/benchmark_fixtures';

  if (deviceId == null) {
    stderr.writeln('Usage: dart run ... -d <SIMULATOR_ID> [--scenarios A,B,F]');
    exit(1);
  }

  final requestedScenarios =
      scenariosStr?.split(',').toSet() ??
      {
        ..._singleNodeHarnesses.keys,
        ..._twoNodeHarnesses.keys,
        ..._scriptScenarios.keys,
      };

  print('');
  print('${'═' * 60}');
  print('  mknoon Benchmark Suite');
  print('  Device: $deviceId');
  print('  Scenarios: ${requestedScenarios.join(', ')}');
  print('  Fixture dir: $fixtureDir');
  print('${'═' * 60}');
  print('');

  // Ensure fixture directory exists
  Directory(fixtureDir).createSync(recursive: true);

  final allBenchmarks = <String>[];

  // --- Phase 1: Single-node harnesses (no test peer needed) ---
  final singleNodeScenarios =
      requestedScenarios.where(_singleNodeHarnesses.containsKey).toList()
        ..sort();

  if (singleNodeScenarios.isNotEmpty) {
    print('─── Single-node scenarios: ${singleNodeScenarios.join(', ')} ───\n');

    for (final scenario in singleNodeScenarios) {
      final harness = _singleNodeHarnesses[scenario]!;
      print('\n▶ Scenario $scenario: $harness');
      final output = await _runFlutterTest(harness, deviceId);
      allBenchmarks.addAll(_extractBenchmarkLines(output));
    }
  }

  // --- Phase 2: Two-node harnesses (need Go test peer) ---
  final twoNodeScenarios =
      requestedScenarios.where(_twoNodeHarnesses.containsKey).toList()..sort();

  if (twoNodeScenarios.isNotEmpty) {
    print('\n─── Two-node scenarios: ${twoNodeScenarios.join(', ')} ───\n');

    Process? testPeer;
    String? cliFixturePath;
    String? cliPeerId;

    try {
      // Build testpeer if needed
      final testpeerFile = File(_testpeerBin);
      if (!testpeerFile.existsSync()) {
        print('[BUILD] Building Go testpeer...');
        final buildResult = await Process.run('go', [
          'build',
          '-o',
          'bin/testpeer',
          './cmd/testpeer/',
        ], workingDirectory: 'go-mknoon');
        if (buildResult.exitCode != 0) {
          stderr.writeln('Failed to build testpeer: ${buildResult.stderr}');
          exit(1);
        }
        print('[BUILD] Testpeer built successfully');
      }

      // Start test peer with command/response handling via broadcast stream
      print('[PEER] Starting Go CLI test peer...');
      testPeer = await Process.start(_testpeerBin, []);

      // Set up broadcast stream for reading multiple responses
      final peerLines = testPeer.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .asBroadcastStream();
      testPeer.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) => stderr.writeln('[PEER-ERR] $line'));

      final peer = testPeer;
      Future<Map<String, dynamic>> peerCommand(
        String cmd, [
        Map<String, dynamic>? params,
      ]) async {
        peer.stdin.writeln(
          jsonEncode({'cmd': cmd, if (params != null) 'params': params}),
        );
        await peer.stdin.flush();
        final line = await peerLines
            .firstWhere((l) {
              try {
                final json = jsonDecode(l) as Map<String, dynamic>;
                return !json.containsKey('event'); // skip push events
              } catch (_) {
                return false;
              }
            })
            .timeout(const Duration(seconds: 60));
        return jsonDecode(line) as Map<String, dynamic>;
      }

      // Generate identity
      final identityResult = await peerCommand('generate_identity');
      if (identityResult['ok'] != true) {
        throw StateError('generate_identity failed: $identityResult');
      }
      cliPeerId = identityResult['peerId'] as String;
      print('[PEER] CLI peer ID: ${cliPeerId.substring(0, 24)}...');

      // Generate ML-KEM keys for encrypted sends
      final mlkemResult = await peerCommand('mlkem_keygen');
      final cliMlKemPublicKey = mlkemResult['ok'] == true
          ? mlkemResult['publicKey'] as String?
          : null;
      print('[PEER] ML-KEM keys generated');

      // Start node with autoConfirmDirectAck for ACK benchmark (scenario L)
      final startResult = await peerCommand('start', {
        'autoRegister': true,
        'autoConfirmDirectAck': true,
      });
      if (startResult['ok'] != true) {
        stderr.writeln('[PEER] start failed: $startResult');
      }

      // Wait for relay + circuit (not a fixed sleep)
      print('[PEER] Waiting for relay...');
      final relayResult = await peerCommand('wait_relay', {'timeoutSec': 30});
      if (relayResult['ok'] != true) {
        stderr.writeln('[PEER] wait_relay failed: $relayResult');
      }
      print('[PEER] Relay connected');

      print('[PEER] Waiting for circuit address...');
      final circuitResult = await peerCommand('wait_circuit', {
        'timeoutSec': 30,
      });
      if (circuitResult['ok'] != true) {
        stderr.writeln('[PEER] wait_circuit failed: $circuitResult');
      }
      print('[PEER] Circuit address obtained — peer is discoverable');

      // Write fixture file (includes ML-KEM public key for v2 encrypted sends)
      cliFixturePath = '$fixtureDir/cli_peer_fixture.json';
      File(cliFixturePath).writeAsStringSync(
        jsonEncode({
          'peerId': cliPeerId,
          'publicKey': identityResult['publicKey'],
          if (cliMlKemPublicKey != null) 'mlKemPublicKey': cliMlKemPublicKey,
        }),
      );
      print('[PEER] Fixture written to $cliFixturePath');

      // Run two-node harnesses
      for (final scenario in twoNodeScenarios) {
        final harness = _twoNodeHarnesses[scenario]!;
        print('\n▶ Scenario $scenario: $harness');
        final output = await _runFlutterTest(
          harness,
          deviceId,
          dartDefines: ['CLI_PEER_FIXTURE=$cliFixturePath'],
        );
        allBenchmarks.addAll(_extractBenchmarkLines(output));
      }
    } finally {
      // Clean up test peer
      testPeer?.kill();
      if (cliFixturePath != null) {
        try {
          File(cliFixturePath).deleteSync();
        } catch (_) {}
      }
    }
  }

  // --- Phase 3: Script-driven scenarios (custom CLI orchestration) ---
  final scriptScenarios =
      requestedScenarios.where(_scriptScenarios.containsKey).toList()..sort();

  if (scriptScenarios.isNotEmpty) {
    print('\n─── Script scenarios: ${scriptScenarios.join(', ')} ───\n');

    for (final scenario in scriptScenarios) {
      final script = _scriptScenarios[scenario]!;
      print('\n▶ Scenario $scenario: $script');
      final output = await _runDartScript(script, ['-d', deviceId]);
      allBenchmarks.addAll(_extractBenchmarkLines(output));
    }
  }

  // --- Print baseline table ---
  print('');
  print('${'═' * 60}');
  print('  mknoon Transport Timing — Simulator Baseline');
  print('  Device: $deviceId');
  print('  Date: ${DateTime.now().toIso8601String().split('T').first}');
  print('${'═' * 60}');
  for (final line in allBenchmarks) {
    print('  $line');
  }
  print('${'═' * 60}');
}

Future<String> _runFlutterTest(
  String harnessPath,
  String deviceId, {
  List<String> dartDefines = const [],
}) async {
  final args = [
    'test',
    '-d',
    deviceId,
    for (final d in dartDefines) '--dart-define=$d',
    harnessPath,
  ];

  print('  flutter ${args.join(' ')}');

  final result = await Process.run('flutter', args, stdoutEncoding: utf8);
  final output = result.stdout as String;

  // Print test output (filtered)
  for (final line in output.split('\n')) {
    if (line.contains('[BENCHMARK]') ||
        line.contains('[PHASE') ||
        line.contains('PASS') ||
        line.contains('FAIL') ||
        line.contains('[WARNING]')) {
      print('  $line');
    }
  }

  if (result.exitCode != 0) {
    stderr.writeln('  ⚠ Test exited with code ${result.exitCode}');
    final errOutput = result.stderr as String;
    if (errOutput.isNotEmpty) {
      stderr.writeln(
        '  stderr: ${errOutput.substring(0, errOutput.length.clamp(0, 200))}',
      );
    }
  }

  return output;
}

Future<String> _runDartScript(String scriptPath, List<String> args) async {
  final command = ['run', scriptPath, ...args];
  print('  dart ${command.join(' ')}');

  final result = await Process.run('dart', command, stdoutEncoding: utf8);
  final output = result.stdout as String;

  for (final line in output.split('\n')) {
    if (line.contains('[BENCHMARK]') ||
        line.contains('PASS') ||
        line.contains('FAIL') ||
        line.contains('[WARNING]')) {
      print('  $line');
    }
  }

  if (result.exitCode != 0) {
    stderr.writeln('  ⚠ Script exited with code ${result.exitCode}');
    final errOutput = result.stderr as String;
    if (errOutput.isNotEmpty) {
      stderr.writeln(
        '  stderr: ${errOutput.substring(0, errOutput.length.clamp(0, 200))}',
      );
    }
  }

  return output;
}

List<String> _extractBenchmarkLines(String output) {
  return output.split('\n').where((line) => line.contains('[BENCHMARK]')).map((
    line,
  ) {
    final idx = line.indexOf('[BENCHMARK]');
    return line.substring(idx);
  }).toList();
}

String? _parseArg(List<String> args, String flag) {
  final idx = args.indexOf(flag);
  if (idx >= 0 && idx + 1 < args.length) return args[idx + 1];
  return null;
}
