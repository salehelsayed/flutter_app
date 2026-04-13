#!/usr/bin/env dart
// Soak E2E Orchestrator
//
// Coordinates a long-running soak test between a Go CLI test peer and
// the Flutter integration test (soak_e2e_test.dart).
//
// Usage:
//   dart run integration_test/scripts/run_soak_e2e.dart [--device <id>] [--duration <5m|30m|1h>]
//
// Examples:
//   dart run integration_test/scripts/run_soak_e2e.dart -d DE36DBBE-64FC-4652-AAD9-17329A1BA245 --duration 5m
//   dart run integration_test/scripts/run_soak_e2e.dart -p ios --duration 30m
//
// The script:
//   1. Builds the Go CLI test peer binary
//   2. Spawns the test peer, generates identity, starts node
//   3. Writes fixture file + creates signal directory
//   4. Launches Flutter integration test (soak_e2e_test.dart)
//   5. Runs a deterministic Phase 4 stale-discoverability gate on the real stack
//   6. Continues with the longer churn soak loop (send, drain, resume)
//   7. Signals completion, reads final stats, reports results

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _goMknoonDir = 'go-mknoon';
const _testpeerBin = 'go-mknoon/bin/testpeer';

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

List<String> _relayDartDefines() {
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relayAddresses == null || relayAddresses.trim().isEmpty) {
    return const [];
  }
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relayAddresses.trim()}'];
}

List<String> _relayCircuitAddresses(String peerId) {
  final addresses = <String>{};

  void addRelayBase(String? relayBase) {
    final trimmed = relayBase?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final base = trimmed.contains('/p2p-circuit')
        ? trimmed
        : '$trimmed/p2p-circuit';
    addresses.add('$base/p2p/$peerId');
  }

  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relayAddresses != null && relayAddresses.trim().isNotEmpty) {
    for (final relayBase in relayAddresses.split(',')) {
      addRelayBase(relayBase);
    }
  }
  addRelayBase(Platform.environment['MKNOON_RELAY_ADDR']);

  return addresses.toList(growable: false);
}

// ---------------------------------------------------------------------------
// TestPeer — reusable from run_transport_e2e.dart
// ---------------------------------------------------------------------------

class TestPeer {
  Process? _process;
  final _pending = <Completer<Map<String, dynamic>>>[];
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  String? peerId;
  String? publicKey;
  String? privateKey;
  String? mlKemPublicKey;
  String? mlKemSecretKey;

  Future<void> start() async {
    _process = await Process.start(_testpeerBin, []);

    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleLine);

    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('PEER-ERR', line));
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      if (!json.containsKey('event') && _pending.isNotEmpty) {
        _pending.removeAt(0).complete(json);
      }
    } catch (e) {
      _log('WARN', 'Non-JSON: $line');
    }
  }

  Future<Map<String, dynamic>> command(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending.add(completer);
    final request = {'cmd': cmd, 'params': params};
    _process!.stdin.writeln(jsonEncode(request));
    await _process!.stdin.flush();
    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(completer);
        throw TimeoutException('Command "$cmd" timed out');
      },
    );
  }

  Future<Map<String, dynamic>> commandOk(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await command(cmd, params);
    if (result['ok'] != true) {
      throw StateError('Command "$cmd" failed: ${result['errorMessage']}');
    }
    return result;
  }

  Future<Map<String, dynamic>> commandWithRetry(
    String cmd, [
    Map<String, dynamic>? params,
    int maxAttempts = 3,
    Duration baseDelay = const Duration(seconds: 3),
  ]) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await commandOk(cmd, params);
      } catch (e) {
        if (attempt == maxAttempts) rethrow;
        await Future.delayed(baseDelay * attempt);
      }
    }
    throw StateError('unreachable');
  }

  Future<void> generateIdentity() async {
    final id = await commandOk('generate_identity');
    peerId = id['peerId'] as String;
    publicKey = id['publicKey'] as String;
    privateKey = id['privateKey'] as String;

    final mlkem = await commandOk('mlkem_keygen');
    mlKemPublicKey = mlkem['publicKey'] as String;
    mlKemSecretKey = mlkem['secretKey'] as String;
  }

  Future<void> startNode() async {
    await commandOk('start', {'autoConfirmDirectAck': true});
    await commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    await commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
  }

  Future<void> register() async => commandOk('register');

  Future<void> stopNode() async {
    try {
      await command('stop');
    } catch (_) {}
  }

  Future<void> kill() async {
    _stdoutSub?.cancel();
    _stderrSub?.cancel();
    _process?.kill();
    await _process?.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] [$tag] $msg');
  }
}

// ---------------------------------------------------------------------------
// Signal helpers
// ---------------------------------------------------------------------------

late final Directory _signalDir;

void _writeSignal(String name, [String content = '']) {
  File('${_signalDir.path}/$name').writeAsStringSync(content);
}

bool _signalExists(String name) {
  return File('${_signalDir.path}/$name').existsSync();
}

String? _readSignal(String name) {
  final f = File('${_signalDir.path}/$name');
  if (!f.existsSync()) return null;
  return f.readAsStringSync();
}

Future<String?> _waitForSignal(
  String name, {
  required Duration timeout,
  Duration pollInterval = const Duration(milliseconds: 500),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final content = _readSignal(name);
    if (content != null) {
      return content;
    }
    await Future.delayed(pollInterval);
  }
  return null;
}

Future<Map<String, dynamic>?> _waitForJsonSignal(
  String name, {
  required Duration timeout,
}) async {
  final content = await _waitForSignal(name, timeout: timeout);
  if (content == null || content.isEmpty) {
    return null;
  }
  return jsonDecode(content) as Map<String, dynamic>;
}

Future<bool> _discoverAndDialFlutterPeer(
  TestPeer peer,
  String flutterPeerId,
) async {
  final ns = 'mknoon:chat:$flutterPeerId';
  for (var attempt = 1; attempt <= 10; attempt++) {
    await Future.delayed(Duration(seconds: attempt * 2));
    try {
      final disc = await peer.commandOk('discover', {'namespace': ns});
      final peers = disc['peers'] as List<dynamic>? ?? [];
      for (final p in peers) {
        final pMap = p as Map<String, dynamic>;
        if (pMap['peerId'] == flutterPeerId) {
          final addrs = (pMap['addresses'] as List<dynamic>)
              .map((a) => a as String)
              .toList();
          await peer.commandOk('dial', {
            'peerId': flutterPeerId,
            'addresses': addrs,
          });
          return true;
        }
      }
    } catch (_) {}
  }

  final relayCircuitAddresses = _relayCircuitAddresses(flutterPeerId);
  if (relayCircuitAddresses.isEmpty) {
    _log('SOAK', 'Relay circuit fallback unavailable: no relay env configured');
    return false;
  }

  _log(
    'SOAK',
    'Rendezvous discovery missed Flutter peer; trying relay circuit fallback',
  );
  try {
    await peer.commandOk('dial', {
      'peerId': flutterPeerId,
      'addresses': relayCircuitAddresses,
    });
    return true;
  } catch (e) {
    _log('SOAK', 'Relay circuit dial failed: $e');
  }

  return false;
}

// ---------------------------------------------------------------------------
// CLI arguments
// ---------------------------------------------------------------------------

Duration _parseDuration(String s) {
  final match = RegExp(r'^(\d+)(s|m|h)$').firstMatch(s);
  if (match == null) throw ArgumentError('Invalid duration: $s');
  final value = int.parse(match.group(1)!);
  switch (match.group(2)!) {
    case 's':
      return Duration(seconds: value);
    case 'm':
      return Duration(minutes: value);
    case 'h':
      return Duration(hours: value);
    default:
      throw ArgumentError('Invalid duration: $s');
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

Future<void> main(List<String> args) async {
  String? deviceId;
  String platform = 'ios';
  Duration duration = const Duration(minutes: 5);

  // Parse args
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '-d':
      case '--device':
        deviceId = args[++i];
        break;
      case '-p':
      case '--platform':
        platform = args[++i];
        break;
      case '--duration':
        duration = _parseDuration(args[++i]);
        break;
    }
  }

  _log('SOAK', 'Duration: ${duration.inMinutes}m, Platform: $platform');

  // 1. Create signal directory
  _signalDir = Directory('/tmp/e2e_soak_signals');
  if (_signalDir.existsSync()) {
    _signalDir.deleteSync(recursive: true);
  }
  _signalDir.createSync(recursive: true);
  _log('SOAK', 'Signal dir: ${_signalDir.path}');

  // 2. Build test peer
  _log('SOAK', 'Building test peer...');
  final buildResult = await Process.run(
    'make',
    ['testpeer'],
    workingDirectory: _goMknoonDir,
    environment: {
      ...Platform.environment,
      'PATH':
          '${Platform.environment['PATH']}:${Platform.environment['HOME']}/go/bin',
    },
  );
  if (buildResult.exitCode != 0) {
    _log('SOAK', 'Build failed: ${buildResult.stderr}');
    exit(1);
  }

  // 3. Start test peer
  final peer = TestPeer();
  await peer.start();
  await peer.generateIdentity();
  await peer.startNode();
  await peer.register();
  _log('SOAK', 'CLI peer ready: ${peer.peerId!.substring(0, 20)}...');

  // 4. Write CLI fixture for Flutter
  _writeSignal(
    'cli_peer_fixture.json',
    jsonEncode({
      'peerId': peer.peerId,
      'publicKey': peer.publicKey,
      'mlKemPublicKey': peer.mlKemPublicKey,
    }),
  );

  // 5. Launch Flutter integration test
  _log('SOAK', 'Launching Flutter soak test...');
  final useFlutterDrive =
      platform == 'ios' && (deviceId == null || _isIosDeviceId(deviceId));
  final flutterArgs = [
    if (useFlutterDrive) ...[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=integration_test/soak_e2e_test.dart',
      '--publish-port',
    ] else ...[
      'test',
      '--no-dds',
      'integration_test/soak_e2e_test.dart',
    ],
    ..._relayDartDefines(),
    '--dart-define=E2E_SIGNAL_DIR=${_signalDir.path}',
    if (deviceId != null) ...['-d', deviceId],
  ];
  final flutterProcess = await Process.start(
    'flutter',
    flutterArgs,
    environment: {...Platform.environment, 'E2E_SIGNAL_DIR': _signalDir.path},
  );

  // Stream Flutter output
  flutterProcess.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => _log('FLUTTER', l));
  flutterProcess.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((l) => _log('FLUTTER-ERR', l));

  // 6. Wait for Flutter fixture
  _log('SOAK', 'Waiting for Flutter peer fixture...');
  Map<String, dynamic>? flutterPeer;
  for (var i = 0; i < 120; i++) {
    await Future.delayed(const Duration(seconds: 1));
    final content = _readSignal('flutter_peer_fixture.json');
    if (content != null) {
      flutterPeer = jsonDecode(content) as Map<String, dynamic>;
      break;
    }
  }

  if (flutterPeer == null) {
    _log('SOAK', 'ERROR: Flutter fixture not found after 120s');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }

  final flutterPeerId = flutterPeer['peerId'] as String;
  _log('SOAK', 'Flutter peer: ${flutterPeerId.substring(0, 20)}...');
  await peer.register();
  _log('SOAK', 'CLI peer re-registered after Flutter startup');

  final connectedBeforePhase4 = await _discoverAndDialFlutterPeer(
    peer,
    flutterPeerId,
  );
  if (!connectedBeforePhase4) {
    _log('SOAK', 'ERROR: Could not discover/dial Flutter peer before Phase 4');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }
  _log('SOAK', 'Connected to Flutter peer before Phase 4');

  final phase4Ready = await _waitForSignal(
    'phase4_initial_ready',
    timeout: const Duration(seconds: 120),
  );
  if (phase4Ready == null) {
    _log('SOAK', 'ERROR: Flutter never confirmed initial CLI discoverability');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }

  // 7. Deterministic Phase 4 gate: keep the CLI peer online but remove its
  // personal rendezvous registration so Flutter hits the stale-discoverability
  // send path on the real stack without restarting either side.
  const phase4Text = 'phase4-live-after-stale-discoverability';
  _log('SOAK', 'Phase 4 gate: unregister CLI namespace without restart...');
  await peer.commandOk('clear_messages');
  await peer.commandOk('unregister');
  await Future.delayed(const Duration(seconds: 2));

  _writeSignal('phase4_resume_and_send', jsonEncode({'text': phase4Text}));

  final phase4Result = await _waitForJsonSignal(
    'phase4_result',
    timeout: const Duration(seconds: 60),
  );
  if (phase4Result == null) {
    _log('SOAK', 'ERROR: phase4_result not received from Flutter');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }

  Map<String, dynamic> cliReceived;
  try {
    cliReceived = await peer.commandOk('wait_message', {
      'fromPeerId': flutterPeerId,
      'timeoutSec': 30,
    });
  } catch (e) {
    _log('SOAK', 'ERROR: CLI did not receive the Phase 4 message: $e');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }

  final phase4DiscoverMissBefore =
      phase4Result['discoverMissBeforeResume'] == true;
  final phase4DiscoverMissAfter =
      phase4Result['discoverMissAfterResume'] == true;
  final phase4LivePath = phase4Result['livePath'] == true;
  final phase4Content = cliReceived['content']?.toString() ?? '';
  final phase4ReceivedExpectedText = phase4Content.contains(phase4Text);

  if (!phase4DiscoverMissBefore ||
      !phase4DiscoverMissAfter ||
      !phase4LivePath ||
      !phase4ReceivedExpectedText) {
    _log(
      'SOAK',
      'ERROR: Phase 4 gate failed. '
          'discoverBefore=$phase4DiscoverMissBefore '
          'discoverAfter=$phase4DiscoverMissAfter '
          'livePath=$phase4LivePath '
          'receivedText=$phase4ReceivedExpectedText '
          'transport=${phase4Result['persistedTransport']} '
          'status=${phase4Result['persistedStatus']} '
          'recovery=${phase4Result['lastRecoveryMethod']}',
    );
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }

  _log(
    'SOAK',
    'Phase 4 gate PASS: '
        'transport=${phase4Result['persistedTransport']} '
        'status=${phase4Result['persistedStatus']} '
        'recovery=${phase4Result['lastRecoveryMethod']}',
  );

  await peer.commandOk('register');

  // Discover and dial Flutter peer for the remaining long-running soak loop.
  final dialed = await _discoverAndDialFlutterPeer(peer, flutterPeerId);

  if (!dialed) {
    _log('SOAK', 'ERROR: Could not discover/dial Flutter peer');
    _writeSignal('soak_done');
    await peer.kill();
    flutterProcess.kill();
    exit(1);
  }
  _log('SOAK', 'Connected to Flutter peer');

  // 8. Soak loop
  final random = Random(42);
  final stopwatch = Stopwatch()..start();
  int cliSentCount = 0;
  int signalsSent = 0;
  int disconnects = 0;
  int inboxStores = 0;

  _log('SOAK', 'Starting soak loop (${duration.inMinutes}m)...');

  while (stopwatch.elapsed < duration) {
    final elapsed = stopwatch.elapsed;

    // Send message from CLI → Flutter (every 1-3s)
    cliSentCount++;
    try {
      await peer.commandOk('send_v1', {
        'peerId': flutterPeerId,
        'text': 'soak from CLI #$cliSentCount',
      });
    } catch (e) {
      _log('SOAK', 'Send failed: $e');
    }

    // Signal Flutter to send back (every 2-5s)
    if (random.nextInt(3) == 0) {
      signalsSent++;
      _writeSignal('soak_send_next');
    }

    // Every 60s: disconnect/reconnect
    if (elapsed.inSeconds > 0 &&
        elapsed.inSeconds % 60 < 3 &&
        disconnects < elapsed.inSeconds ~/ 60) {
      disconnects++;
      _log('SOAK', 'Disconnect #$disconnects...');
      await peer.stopNode();
      await Future.delayed(const Duration(seconds: 5));
      await peer.startNode();
      await peer.register();
      _log('SOAK', 'Reconnected');

      // Re-dial Flutter
      try {
        final redialed = await _discoverAndDialFlutterPeer(peer, flutterPeerId);
        if (!redialed) {
          _log('SOAK', 'Reconnect re-dial did not find Flutter peer');
        }
      } catch (e) {
        _log('SOAK', 'Re-dial failed: $e');
      }
    }

    // Every 60s: signal Flutter health check
    if (elapsed.inSeconds > 0 &&
        elapsed.inSeconds % 60 < 3 &&
        !_signalExists('soak_health_check')) {
      _writeSignal('soak_health_check');
    }

    // Every 120s: store inbox messages + signal drain
    if (elapsed.inSeconds > 0 &&
        elapsed.inSeconds % 120 < 3 &&
        inboxStores < elapsed.inSeconds ~/ 120) {
      inboxStores++;
      _log('SOAK', 'Storing inbox messages #$inboxStores...');
      for (var i = 0; i < 5; i++) {
        try {
          await peer.commandOk('inbox_store_v1', {
            'peerId': flutterPeerId,
            'text': 'inbox soak #$inboxStores-$i',
            'messageId': 'soak-inbox-$inboxStores-$i',
          });
        } catch (e) {
          _log('SOAK', 'Inbox store failed: $e');
        }
      }
      _writeSignal('soak_drain_inbox');
    }

    // Print stats every 30s
    if (elapsed.inSeconds > 0 && elapsed.inSeconds % 30 < 3) {
      final stats = _readSignal('soak_stats');
      _log(
        'SOAK',
        'Progress: ${elapsed.inSeconds}s/${duration.inSeconds}s, '
            'cliSent=$cliSentCount, signalsSent=$signalsSent, '
            'flutterStats=${stats ?? "pending"}',
      );
    }

    // Random delay 1-3s
    await Future.delayed(Duration(milliseconds: 1000 + random.nextInt(2000)));
  }

  // 9. Signal done and collect results
  _log('SOAK', 'Soak loop complete. Signaling done...');
  _writeSignal('soak_done');

  // Wait for final stats
  await Future.delayed(const Duration(seconds: 5));
  final finalStats = _readSignal('soak_final_stats');
  _log('SOAK', '--- RESULTS ---');
  _log('SOAK', 'CLI sent: $cliSentCount');
  _log('SOAK', 'Send signals: $signalsSent');
  _log('SOAK', 'Disconnects: $disconnects');
  _log('SOAK', 'Inbox store rounds: $inboxStores');
  _log('SOAK', 'Flutter final stats: ${finalStats ?? "not available"}');

  // Cleanup
  await peer.stopNode();
  await peer.kill();
  await flutterProcess.exitCode.timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      flutterProcess.kill();
      return -1;
    },
  );

  // Clean up signal dir
  try {
    _signalDir.deleteSync(recursive: true);
  } catch (_) {}

  _log('SOAK', 'Done.');
}
