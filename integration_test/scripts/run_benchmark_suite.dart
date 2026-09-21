#!/usr/bin/env dart

/// Benchmark Suite Orchestrator
///
/// Automates running all implemented simulator benchmarks and aggregates results
/// into the baseline table from 03b Section 5.
///
/// Usage:
///   `dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID>`
///   `dart run integration_test/scripts/run_benchmark_suite.dart -d <SIMULATOR_ID> --scenarios B,F,G`
///
/// Prerequisites:
///   - Go testpeer built: cd go-mknoon && go build -o bin/testpeer ./cmd/testpeer/
///   - iOS simulator booted: `xcrun simctl boot <SIMULATOR_ID>`
///   - flutter build done (or flutter test will build on first run)
library;

import 'dart:convert';
import 'dart:io';

import 'benchmark_completion.dart';
import 'benchmark_boundary.dart';
import 'routing_stage_handshake.dart';

const _testpeerBin = 'go-mknoon/bin/testpeer';

// Each BENCHMARK dart-define is a distinct compile input. The shared entrypoint
// does not make binaries compiled for different selectors interchangeable.
const _benchmarkHarness = 'integration_test/benchmark_harness.dart';

// BENCHMARK dispatch keys indexed by scenario letter.
const _singleNodeHarnesses = <String, String>{
  'B': 'NODE_STARTUP',
  'BR': 'BACKGROUND_RESUME',
  'C': 'RELAY_RECOVERY',
  'F': 'BRIDGE_CROSSING',
  'G': 'ENCRYPTION',
  'I': 'EVENT_QUEUE',
  'K': 'VOICE',
  'M': 'TIME_TO_ONLINE',
  'N': 'NOTIFICATION_TAP',
};

const _scriptScenarios = <String, String>{
  'H': 'integration_test/scripts/run_timeout_accuracy_benchmark.dart',
  'GP': 'integration_test/scripts/run_group_publish_benchmark.dart',
};

const _twoNodeHarnesses = <String, String>{
  'A': 'ONE_TO_ONE_SEND',
  'D': 'INBOX',
  'E': 'MEDIA',
  'J': 'CONNECTION_REUSE',
  'L': 'ACK',
  'R': 'ROUTING_PATHS',
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

  final failures = <String>[];
  final supported = {..._singleNodeHarnesses.keys, ..._twoNodeHarnesses.keys, ..._scriptScenarios.keys};
  if (requestedScenarios.isEmpty || requestedScenarios.difference(supported).isNotEmpty) {
    throw ArgumentError('Unknown benchmark scenario');
  }
  final boundary = BenchmarkBoundary(deviceId,
      hostFiles: requestedScenarios.any(_scriptScenarios.containsKey));
  String? routingPlatform;
  if (requestedScenarios.contains('R')) {
    // Simulators/desktops share host loopback. Android uses a fresh, explicitly
    // pinned adb reverse mapping; physical iOS has no supported channel here.
    final inventory = await Process.run('flutter', ['devices', '--machine']);
    final devices = inventory.exitCode == 0 ? jsonDecode(inventory.stdout as String) as List : [];
    final targets = devices.where((d) => d['id'] == deviceId).toList();
    if (targets.length == 1) {
      final d = targets.single;
      final platform = d['targetPlatform'] as String;
      if (platform.startsWith('android')) { routingPlatform = 'android'; }
      if (platform == 'darwin' || (platform == 'ios' && d['emulator'] == true)) { routingPlatform = 'loopback'; }
    }
    if (routingPlatform == null) {
      failures.add('R: stage channel requires a discovered Android, iOS simulator or macOS target');
      requestedScenarios.remove('R');
    }
  }

  print('');
  print('═' * 60);
  print('  mknoon Benchmark Suite');
  print('  Device: $deviceId');
  print('  Scenarios: ${requestedScenarios.join(', ')}');
  print('  Fixture dir: $fixtureDir');
  print('═' * 60);
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
      final benchmarkKey = _singleNodeHarnesses[scenario]!;
      print('\n▶ Scenario $scenario: BENCHMARK=$benchmarkKey');
      try {
        final output = await _runFlutterTest(benchmarkKey, deviceId, boundary);
        allBenchmarks.addAll(_extractBenchmarkLines(output));
      } catch (error) { failures.add('$scenario: $error'); }
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
        // Subscribe before writing: a fast local CLI reply must not be lost.
        final response = peerLines
            .firstWhere((l) {
              try {
                final json = jsonDecode(l) as Map<String, dynamic>;
                return !json.containsKey('event'); // skip push events
              } catch (_) {
                return false;
              }
            })
            .timeout(const Duration(seconds: 60));
        peer.stdin.writeln(jsonEncode({'cmd': cmd, 'params': ?params}));
        await peer.stdin.flush();
        return jsonDecode(await response) as Map<String, dynamic>;
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
      final peerStart = <String, dynamic>{
        'autoRegister': true,
        'autoConfirmDirectAck': true,
        ...boundary.startParams,
      };
      final startResult = await peerCommand('start', peerStart);
      if (startResult['ok'] != true) {
        throw StateError('[PEER] start failed: $startResult');
      }

      // Wait for relay + circuit (not a fixed sleep)
      print('[PEER] Waiting for relay...');
      final relayResult = await peerCommand('wait_relay', {'timeoutSec': 30});
      if (relayResult['ok'] != true) {
        throw StateError('[PEER] wait_relay failed: $relayResult');
      }
      print('[PEER] Relay connected');

      print('[PEER] Waiting for circuit address...');
      final circuitResult = await peerCommand('wait_circuit', {
        'timeoutSec': 30,
      });
      if (circuitResult['ok'] != true) {
        throw StateError('[PEER] wait_circuit failed: $circuitResult');
      }
      print('[PEER] Circuit address obtained — peer is discoverable');

      // Write fixture file (includes ML-KEM public key for v2 encrypted sends)
      cliFixturePath = '$fixtureDir/cli_peer_fixture.json';
      File(cliFixturePath).writeAsStringSync(
        jsonEncode({
          'peerId': cliPeerId,
          'publicKey': identityResult['publicKey'],
          'mlKemPublicKey': ?cliMlKemPublicKey,
        }),
      );
      print('[PEER] Fixture written to $cliFixturePath');

      // Run two-node harnesses
      for (final scenario in twoNodeScenarios) {
        final benchmarkKey = _twoNodeHarnesses[scenario]!;
        print('\n▶ Scenario $scenario: BENCHMARK=$benchmarkKey');
        RoutingStageHost? stages;
        String? reversePort;
        try {
          if (scenario == 'R') {
            stages = await RoutingStageHost.start(run: routingNonce(), target: deviceId,
              peerCommand: (command) async {
                final ack = await peerCommand(command, command == 'start' ? peerStart : null);
                if (command == 'start' && ack['ok'] == true) {
                  for (final readiness in ['wait_relay', 'wait_circuit']) {
                    final ready = await peerCommand(readiness, {'timeoutSec': 20});
                    if (ready['ok'] != true) throw StateError('Restarted peer is not ready');
                  }
                }
                return ack;
              });
            if (routingPlatform == 'android') {
              final reverse = await Process.run('adb', ['-s', deviceId, 'reverse', 'tcp:0', 'tcp:${stages.server.port}']);
              final port = (reverse.stdout as String).trim();
              if (reverse.exitCode != 0 || !RegExp(r'^[0-9]{1,5}$').hasMatch(port) ||
                  int.parse(port) < 1 || int.parse(port) > 65535) {
                throw StateError('Pinned Android stage forwarding failed');
              }
              reversePort = port;
              stages.forwardedEndpoint = 'http://127.0.0.1:$port';
            }
          }
          final output = await _runFlutterTest(
            benchmarkKey,
            deviceId,
            boundary,
            dartDefines: [
              'CLI_PEER_FIXTURE_JSON=${File(cliFixturePath).readAsStringSync()}',
              ...?stages?.defines,
            ],
          );
          stages?.requireConsumed(output);
          allBenchmarks.addAll(_extractBenchmarkLines(output));
        } catch (error) {
          failures.add('$scenario: $error');
        } finally {
          if (reversePort != null) {
            final cleanup = await Process.run('adb', ['-s', deviceId, 'reverse', '--remove', 'tcp:$reversePort']);
            if (cleanup.exitCode != 0) failures.add('R: owned Android forwarding cleanup failed');
          }
          await stages?.close();
        }
      }
    } catch (error) {
      failures.add('peer setup: $error');
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
      try {
        final output = await _runDartScript(script, ['-d', deviceId]);
        allBenchmarks.addAll(_extractBenchmarkLines(output));
      } catch (error) { failures.add('$scenario: $error'); }
    }
  }

  // --- Print baseline table ---
  print('');
  print('═' * 60);
  print('  mknoon Transport Timing — Simulator Baseline');
  print('  Device: $deviceId');
  print('  Date: ${DateTime.now().toIso8601String().split('T').first}');
  print('═' * 60);
  for (final line in allBenchmarks) {
    print('  $line');
  }
  print('═' * 60);
  if (failures.isNotEmpty) {
    for (final failure in failures) { stderr.writeln('[FAIL] $failure'); }
    exitCode = 1;
    return;
  }
  print('FULL_BENCHMARK_COMPLETED peer-suite');
  final completedSelection = requestedScenarios.toList()..sort();
  print('FULL_BENCHMARK_SELECTION $deviceId ${completedSelection.join(',')}');
}

Future<String> _runFlutterTest(
  String benchmarkKey,
  String deviceId,
  BenchmarkBoundary boundary, {
  List<String> dartDefines = const [],
}) async {
  final args = [
    'test',
    '--machine',
    '-d',
    deviceId,
    '--dart-define=BENCHMARK=$benchmarkKey',
    for (final d in dartDefines) '--dart-define=$d',
    ...boundary.flutterArgs,
    _benchmarkHarness,
  ];

  print('  flutter test BENCHMARK=$benchmarkKey device=$deviceId');

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

  if (result.exitCode != 0) throw StateError('Benchmark child failed: ${result.exitCode}');
  final completion = BenchmarkCompletion(expectedTestName: 'benchmark $benchmarkKey');
  output.split('\n').forEach(completion.observe);
  completion.requireCompleted();
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

  final receipt = 'FULL_BENCHMARK_COMPLETED ${File(scriptPath).uri.pathSegments.last.replaceAll('.dart', '')}';
  if (result.exitCode != 0 || output.split('\n').where((line) => line == receipt).length != 1) {
    throw StateError('Benchmark script did not complete its proof.');
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
