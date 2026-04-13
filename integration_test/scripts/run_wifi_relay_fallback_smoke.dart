#!/usr/bin/env dart
// WiFi-Relay Fallback Smoke Test Orchestrator
//
// Coordinates between a Go CLI test peer and a Flutter integration test
// running on an iOS simulator or Android emulator. Focused on WiFi->relay
// fallback with retry policy and artifact capture. Baseline/recovery live
// delivery may use a direct path when the discovered peer is reachable.
//
// NON-BLOCKING: runs nightly or before release, not on every PR.
//
// Usage:
//   dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart [options]
//
// Options:
//   --platform, -p <ios|android>   Target platform (required)
//   --device, -d <id>              Device/emulator ID (auto-detected if omitted)
//   --retry <N>                    Max retries on failure (default 2)
//   --artifacts <dir>              Directory for log/artifact capture
//
// Examples:
//   dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p ios
//   dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p android --retry 3
//   dart run integration_test/scripts/run_wifi_relay_fallback_smoke.dart -p ios --artifacts ./smoke-logs

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '_android_app_package.dart';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _goMknoonDir = 'go-mknoon';
const _testpeerBin = 'go-mknoon/bin/testpeer';
final _appPackage = resolveAndroidAppPackage();

List<String> _relayDartDefines() {
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relayAddresses == null || relayAddresses.trim().isEmpty) {
    return const [];
  }
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relayAddresses.trim()}'];
}

// ---------------------------------------------------------------------------
// Run-scoped paths
// ---------------------------------------------------------------------------

class _RunPaths {
  final Directory hostTempDir;
  final String deviceDir;
  final String appWriteDir;

  _RunPaths(this.hostTempDir, this.deviceDir, this.appWriteDir);

  // Orchestrator -> Flutter signals.
  String get cliFixture => '$deviceDir/cli_peer_fixture.json';
  String get cliStopped => '$deviceDir/e2e_smoke_cli_stopped';

  // Flutter -> Orchestrator signals.
  String get flutterFixture => '$appWriteDir/flutter_peer_fixture.json';
  String get s3Sent => '$appWriteDir/e2e_smoke_s3_sent';

  // Host paths.
  String get logFile => '${hostTempDir.path}/smoke_test.log';
}

// ---------------------------------------------------------------------------
// Device I/O
// ---------------------------------------------------------------------------

String? _androidDeviceId;

String? _adbPath;
String _adb() {
  if (_adbPath != null) return _adbPath!;
  for (final base in [
    Platform.environment['ANDROID_HOME'],
    Platform.environment['ANDROID_SDK_ROOT'],
    '${Platform.environment['HOME']}/Library/Android/sdk',
  ]) {
    if (base == null) continue;
    final path = '$base/platform-tools/adb';
    if (File(path).existsSync()) {
      _adbPath = path;
      return path;
    }
  }
  _adbPath = 'adb';
  return 'adb';
}

Future<void> _deviceWriteFile(String devicePath, String content) async {
  if (_androidDeviceId != null) {
    final tmp = File(
      '${Directory.systemTemp.path}/_adb_push_${DateTime.now().millisecondsSinceEpoch}',
    );
    tmp.writeAsStringSync(content);
    try {
      final r = await Process.run(_adb(), [
        '-s',
        _androidDeviceId!,
        'push',
        tmp.path,
        devicePath,
      ]);
      if (r.exitCode != 0) {
        throw StateError('adb push failed: ${r.stderr}');
      }
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
  } else {
    File(devicePath).writeAsStringSync(content);
  }
}

Future<String?> _deviceReadFile(String devicePath) async {
  if (_androidDeviceId != null) {
    final tmp = File(
      '${Directory.systemTemp.path}/_adb_pull_${DateTime.now().millisecondsSinceEpoch}',
    );
    try {
      final r = await Process.run(_adb(), [
        '-s',
        _androidDeviceId!,
        'pull',
        devicePath,
        tmp.path,
      ]);
      if (r.exitCode != 0) return null;
      return tmp.readAsStringSync();
    } finally {
      try {
        tmp.deleteSync();
      } catch (_) {}
    }
  } else {
    final f = File(devicePath);
    if (!f.existsSync()) return null;
    return f.readAsStringSync();
  }
}

Future<bool> _deviceFileExists(String devicePath) async {
  if (_androidDeviceId != null) {
    final r = await Process.run(_adb(), [
      '-s',
      _androidDeviceId!,
      'shell',
      'ls',
      devicePath,
    ]);
    return r.exitCode == 0;
  } else {
    return File(devicePath).existsSync();
  }
}

Future<String> _createDeviceTempDir(String deviceId) async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final deviceDir = '/data/local/tmp/e2e_smoke_$ts';
  final r = await Process.run(_adb(), [
    '-s',
    deviceId,
    'shell',
    'mkdir',
    '-p',
    deviceDir,
  ]);
  if (r.exitCode != 0) {
    throw StateError('Failed to create device temp dir: ${r.stderr}');
  }
  await Process.run(_adb(), [
    '-s',
    deviceId,
    'shell',
    'chmod',
    '777',
    deviceDir,
  ]);
  return deviceDir;
}

Future<void> _cleanupDeviceTempDir(String deviceId, String deviceDir) async {
  try {
    await Process.run(_adb(), [
      '-s',
      deviceId,
      'shell',
      'rm',
      '-rf',
      deviceDir,
    ]);
  } catch (_) {}
}

Future<String?> _appReadFile(String path) async {
  if (_androidDeviceId != null) {
    final r = await Process.run(_adb(), [
      '-s',
      _androidDeviceId!,
      'shell',
      'run-as',
      _appPackage,
      'cat',
      path,
    ]);
    if (r.exitCode != 0) return null;
    return (r.stdout as String).trimRight();
  } else {
    final f = File(path);
    if (!f.existsSync()) return null;
    return f.readAsStringSync();
  }
}

Future<bool> _appFileExists(String path) async {
  if (_androidDeviceId != null) {
    final r = await Process.run(_adb(), [
      '-s',
      _androidDeviceId!,
      'shell',
      'run-as',
      _appPackage,
      'ls',
      path,
    ]);
    return r.exitCode == 0;
  } else {
    return File(path).existsSync();
  }
}

Future<void> _cleanupAppWriteDir(String deviceId, String appWriteDir) async {
  try {
    await Process.run(_adb(), [
      '-s',
      deviceId,
      'shell',
      'run-as',
      _appPackage,
      'rm',
      '-rf',
      appWriteDir,
    ]);
  } catch (_) {}
}

// ---------------------------------------------------------------------------
// Result tracker
// ---------------------------------------------------------------------------

class _OrchestratorResult {
  final String name;
  final bool passed;
  final String detail;
  _OrchestratorResult(this.name, this.passed, this.detail);
}

// ---------------------------------------------------------------------------
// TestPeer — manages the Go CLI test peer process
// ---------------------------------------------------------------------------

class TestPeer {
  Process? _process;
  final _pending = <Completer<Map<String, dynamic>>>[];
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  /// Captured stderr lines for artifact capture.
  final stderrLines = <String>[];

  String? peerId;
  String? publicKey;
  String? privateKey;
  String? mnemonic;
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
        .listen((line) {
          _log('PEER-ERR', line);
          stderrLines.add(line);
        });
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;

    try {
      final json = jsonDecode(line) as Map<String, dynamic>;

      if (json.containsKey('event')) {
        _log('EVENT', '${json['event']}: ${json['data']}');
        _events.add(json);
      } else {
        _log('RESP', line.length > 200 ? '${line.substring(0, 200)}...' : line);

        if (_pending.isNotEmpty) {
          _pending.removeAt(0).complete(json);
        }
      }
    } catch (e) {
      _log('WARN', 'Non-JSON stdout: $line');
    }
  }

  Future<Map<String, dynamic>> command(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending.add(completer);

    final request = {'cmd': cmd, if (params != null) 'params': params};

    final line = jsonEncode(request);
    _log('CMD', line.length > 200 ? '${line.substring(0, 200)}...' : line);
    _process!.stdin.writeln(line);
    await _process!.stdin.flush();

    return completer.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        _pending.remove(completer);
        throw TimeoutException('Command "$cmd" timed out after 60s');
      },
    );
  }

  Future<Map<String, dynamic>> commandOk(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final result = await command(cmd, params);
    if (result['ok'] != true) {
      throw StateError(
        'Command "$cmd" failed: ${result['errorMessage'] ?? result}',
      );
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
        final delay = baseDelay * attempt;
        _log(
          'RETRY',
          '$cmd attempt $attempt/$maxAttempts failed: $e '
              '-- retrying in ${delay.inSeconds}s',
        );
        await Future.delayed(delay);
      }
    }
    throw StateError('unreachable');
  }

  Future<void> generateIdentity() async {
    final id = await commandOk('generate_identity');
    peerId = id['peerId'] as String;
    publicKey = id['publicKey'] as String;
    privateKey = id['privateKey'] as String;
    mnemonic = id['mnemonic12'] as String?;
    _log('ID', 'peerId=${peerId!.substring(0, 20)}...');

    final mlkem = await commandOk('mlkem_keygen');
    mlKemPublicKey = mlkem['publicKey'] as String;
    mlKemSecretKey = mlkem['secretKey'] as String;
    _log('ID', 'ML-KEM keys generated');
  }

  Future<void> startNode() async {
    await commandOk('start');
    _log('NODE', 'started, waiting for relay...');

    await commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    _log('NODE', 'relay connected, waiting for circuit...');

    await commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    _log('NODE', 'circuit address obtained');
  }

  Future<void> register() async {
    await commandOk('register');
    _log('NODE', 'registered on rendezvous');
  }

  Future<void> writeFixture(String path) async {
    final data = {
      'peerId': peerId,
      'publicKey': publicKey,
      'mlKemPublicKey': mlKemPublicKey,
    };
    await _deviceWriteFile(path, jsonEncode(data));
    _log('FIXTURE', 'written to $path');
  }

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
    _events.close();
  }

  void _log(String tag, String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    stderr.writeln('[$ts] [$tag] $msg');
  }
}

// ---------------------------------------------------------------------------
// Scenario Runners
// ---------------------------------------------------------------------------

/// Runs the S1-S4 scenarios against the Flutter smoke test.
Future<List<_OrchestratorResult>> _runScenarios(
  TestPeer peer,
  _RunPaths paths,
) async {
  final results = <_OrchestratorResult>[];

  _log('ORCH', 'Waiting for Flutter peer fixture...');

  // Wait for Flutter to write its fixture file.
  Map<String, dynamic>? flutterPeer;
  for (var i = 0; i < 120; i++) {
    await Future.delayed(const Duration(seconds: 1));

    try {
      final content = await _appReadFile(paths.flutterFixture);
      if (content != null) {
        flutterPeer = jsonDecode(content) as Map<String, dynamic>;
        break;
      }
    } catch (_) {}
  }

  if (flutterPeer == null) {
    _log('ORCH', 'ERROR: Flutter peer fixture not found after 120s');
    results.add(
      _OrchestratorResult(
        'SETUP',
        false,
        'Flutter peer fixture not found after 120s',
      ),
    );
    return results;
  }

  final flutterPeerId = flutterPeer['peerId'] as String;
  _log('ORCH', 'Flutter peer: ${flutterPeerId.substring(0, 20)}...');

  // --- Discover and dial Flutter peer ---
  _log('ORCH', 'Discovering Flutter peer...');
  final ns = 'mknoon:chat:$flutterPeerId';

  var dialed = false;
  for (var attempt = 1; attempt <= 5; attempt++) {
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
          dialed = true;
          break;
        }
      }
    } catch (e) {
      _log('ORCH', 'Discover attempt $attempt failed: $e');
    }

    if (dialed) break;
  }

  if (!dialed) {
    _log('ORCH', 'WARN: Could not dial Flutter peer -- trying relay circuit');
    try {
      await peer.commandOk('dial', {
        'peerId': flutterPeerId,
        'addresses': [
          '/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g/p2p-circuit/p2p/$flutterPeerId',
        ],
      });
      dialed = true;
    } catch (e) {
      _log('ORCH', 'Relay circuit dial also failed: $e');
    }
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- S1: Send baseline live message to Flutter ---
  _log('ORCH', 'Scenario S1: Sending v1 message to Flutter...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'S1: Hello from CLI smoke peer',
    });
    results.add(_OrchestratorResult('S1', true, 'sent baseline live message'));
    _log('ORCH', 'S1: sent');
  } catch (e) {
    results.add(_OrchestratorResult('S1', false, 'send failed: $e'));
    _log('ORCH', 'S1: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- S2: Wait for Flutter's message in collector ---
  _log('ORCH', 'Scenario S2: Waiting for Flutter message...');
  try {
    final msg = await peer.commandOk('wait_message', {
      'fromPeerId': flutterPeerId,
      'timeoutSec': 60,
    });
    final content = msg['content'] as String? ?? '';
    final hasS2 = content.contains('S2:');
    results.add(
      _OrchestratorResult(
        'S2',
        hasS2,
        hasS2 ? 'received Flutter S2 message' : 'wrong content',
      ),
    );
    _log(
      'ORCH',
      'S2: ${hasS2 ? 'PASS' : 'FAIL'} -- '
          'content=${content.length > 80 ? content.substring(0, 80) : content}',
    );
  } catch (e) {
    results.add(_OrchestratorResult('S2', false, 'wait failed: $e'));
    _log('ORCH', 'S2: wait failed: $e');
  }

  // --- S3: Stop CLI node, signal Flutter, wait for inbox store, restart ---
  _log('ORCH', 'Scenario S3: Connection drop + inbox fallback...');
  try {
    await Future.delayed(const Duration(seconds: 2));
    await peer.stopNode();
    _log('ORCH', 'S3: CLI node stopped');

    // Signal Flutter that CLI is down.
    await _deviceWriteFile(paths.cliStopped, 'stopped');
    _log('ORCH', 'S3: wrote stop signal');

    // Wait for Flutter to send the S3 message to inbox.
    var s3SentFound = false;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _appFileExists(paths.s3Sent)) {
        s3SentFound = true;
        _log('ORCH', 'S3: Flutter sent signal received after ${i + 1}s');
        break;
      }
    }

    if (!s3SentFound) {
      _log('ORCH', 'S3: Flutter never sent signal -- skipping retrieval');
      results.add(
        _OrchestratorResult(
          'S3',
          false,
          'Flutter signal not received after 60s',
        ),
      );
    } else {
      // Restart CLI node and retrieve inbox.
      await peer.startNode();
      await peer.register();
      _log('ORCH', 'S3: CLI node restarted');

      final inboxResult = await peer.commandOk('inbox_retrieve');
      final msgs = inboxResult['messages'] as List<dynamic>? ?? [];
      _log('ORCH', 'S3: retrieved ${msgs.length} inbox messages');

      // Check if any inbox message contains the S3 text.
      var s3Found = false;
      for (final m in msgs) {
        final mMap = m as Map<String, dynamic>;
        final message = mMap['message'] as String? ?? '';
        if (message.contains('S3:')) {
          s3Found = true;
          break;
        }
      }

      results.add(
        _OrchestratorResult(
          'S3',
          s3Found,
          s3Found
              ? 'S3 message found in inbox'
              : 'S3 not in inbox (${msgs.length} messages)',
        ),
      );
      _log('ORCH', 'S3: ${s3Found ? 'PASS' : 'FAIL'}');
    }
  } catch (e) {
    results.add(_OrchestratorResult('S3', false, 'error: $e'));
    _log('ORCH', 'S3: failed: $e');
  } finally {
    _deleteIfExists(paths.cliStopped);
    _deleteIfExists(paths.s3Sent);
  }

  // --- S4: Post-recovery message ---
  _log('ORCH', 'Scenario S4: Post-recovery message...');
  try {
    // Ensure node is running.
    final status = await peer.command('status');
    if (status['isStarted'] != true) {
      await peer.startNode();
      await peer.register();
    }

    // Reconnect relays to refresh connections after the stop/start.
    await peer.commandWithRetry('reconnect_relays', null, 2);
    await peer.commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    await peer.commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    await peer.register();
    _log('ORCH', 'S4: relays reconnected');

    // Re-discover and dial Flutter.
    var s4Dialed = false;
    for (var attempt = 1; attempt <= 3; attempt++) {
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
            s4Dialed = true;
            break;
          }
        }
      } catch (e) {
        _log('ORCH', 'S4: dial attempt $attempt failed: $e');
      }
      if (s4Dialed) break;
    }

    if (!s4Dialed) {
      // Try relay circuit as fallback.
      try {
        await peer.commandOk('dial', {
          'peerId': flutterPeerId,
          'addresses': [
            '/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g/p2p-circuit/p2p/$flutterPeerId',
          ],
        });
        s4Dialed = true;
      } catch (e) {
        _log('ORCH', 'S4: relay circuit dial failed: $e');
      }
    }

    await Future.delayed(const Duration(seconds: 2));

    // Send post-recovery message.
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'S4: Post-recovery message from CLI peer',
    });
    _log('ORCH', 'S4: sent post-recovery message');

    // Best-effort: wait for Flutter reply.
    try {
      await peer.commandOk('wait_message', {
        'fromPeerId': flutterPeerId,
        'timeoutSec': 30,
      });
      _log('ORCH', 'S4: received Flutter recovery reply');
    } catch (e) {
      _log('ORCH', 'S4: no reply within timeout (non-fatal): $e');
    }

    results.add(_OrchestratorResult('S4', true, 'post-recovery message sent'));
  } catch (e) {
    results.add(_OrchestratorResult('S4', false, 'error: $e'));
    _log('ORCH', 'S4: failed: $e');
  }

  _log('ORCH', 'All scenarios dispatched');
  return results;
}

// ---------------------------------------------------------------------------
// Single run — returns true if all scenarios pass
// ---------------------------------------------------------------------------

Future<bool> _runOnce({
  required String? deviceId,
  required String? platform,
  required IOSink? logSink,
}) async {
  final isAndroid = platform == 'android';
  final useFlutterDrive = platform == 'ios' && _isIosDeviceId(deviceId);

  // Create unique temp directory for this run.
  final hostTempDir = await Directory.systemTemp.createTemp('smoke_');

  String deviceDir;
  String appWriteDir;
  if (isAndroid && deviceId != null) {
    _androidDeviceId = deviceId;
    deviceDir = await _createDeviceTempDir(deviceId);
    appWriteDir = '/data/data/$_appPackage/cache/e2e_smoke_signals';
    _log('ORCH', 'Android device temp dir: $deviceDir');
    _log('ORCH', 'Android app write dir: $appWriteDir');
  } else {
    _androidDeviceId = null;
    deviceDir = hostTempDir.path;
    appWriteDir = hostTempDir.path;
  }
  final paths = _RunPaths(hostTempDir, deviceDir, appWriteDir);
  _log('ORCH', 'Host temp dir: ${hostTempDir.path}');

  final peer = TestPeer();

  // Register cleanup on Ctrl+C / kill.
  late final StreamSubscription sigintSub;
  sigintSub = ProcessSignal.sigint.watch().listen((_) async {
    _log('ORCH', 'SIGINT received -- cleaning up...');
    await peer.kill();
    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }
    exit(130);
  });

  try {
    // Step 1: Build CLI test peer.
    _log('ORCH', 'Building CLI test peer...');
    final buildResult = await Process.run('make', [
      'testpeer',
    ], workingDirectory: _goMknoonDir);
    if (buildResult.exitCode != 0) {
      _log('ORCH', 'ERROR: Build failed:\n${buildResult.stderr}');
      return false;
    }
    _log('ORCH', 'Build complete');

    // Step 2: Start CLI test peer process.
    _log('ORCH', 'Starting CLI test peer...');
    await peer.start();

    // Step 3: Generate identity + ML-KEM keys.
    await peer.generateIdentity();

    // Step 4: Start node, connect to relay.
    await peer.startNode();

    // Step 5: Register on rendezvous.
    await peer.register();

    // Step 6: Write fixture file.
    await peer.writeFixture(paths.cliFixture);

    // Step 7: Clear app data on Android.
    if (_androidDeviceId != null) {
      _log('ORCH', 'Clearing Android app data...');
      await Process.run(_adb(), [
        '-s',
        _androidDeviceId!,
        'shell',
        'pm',
        'clear',
        _appPackage,
      ]);
    }

    // Step 8: Launch Flutter smoke test.
    _log('ORCH', 'Launching Flutter smoke test...');

    final flutterArgs = [
      if (useFlutterDrive) ...[
        'drive',
        '--driver=test_driver/integration_test.dart',
        '--target=integration_test/wifi_relay_fallback_smoke_test.dart',
        '--publish-port',
      ] else ...[
        'test',
        '--no-dds',
        'integration_test/wifi_relay_fallback_smoke_test.dart',
      ],
      '--dart-define=CLI_PEER_FIXTURE=${paths.cliFixture}',
      '--dart-define=E2E_TEMP_DIR=$deviceDir',
      '--dart-define=E2E_WRITE_DIR=$appWriteDir',
      ..._relayDartDefines(),
    ];
    if (deviceId != null) {
      flutterArgs.addAll(['-d', deviceId]);
    }

    final flutterProcess = await Process.start(
      'flutter',
      flutterArgs,
      mode: ProcessStartMode.inheritStdio,
    );

    // Step 9: Run scenarios in parallel with the Flutter test.
    final scenariosFuture = _runScenarios(peer, paths);

    // Wait for Flutter test to complete.
    final flutterExitCode = await flutterProcess.exitCode;
    _log('ORCH', 'Flutter test exited with code $flutterExitCode');

    // Wait for scenarios to finish.
    List<_OrchestratorResult> orchResults;
    try {
      orchResults = await scenariosFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log('ORCH', 'Scenarios timed out (ok -- Flutter test finished)');
          return <_OrchestratorResult>[];
        },
      );
    } catch (e) {
      _log('ORCH', 'Scenarios errored: $e');
      orchResults = [_OrchestratorResult('SCENARIOS', false, 'error: $e')];
    }

    // Step 10: Print orchestrator summary.
    _log('ORCH', '');
    _log('ORCH', '========================================');
    _log('ORCH', 'SMOKE TEST ORCHESTRATOR SUMMARY');
    _log('ORCH', '========================================');
    var orchPassed = 0;
    var orchFailed = 0;
    for (final r in orchResults) {
      final status = r.passed ? 'PASS' : 'FAIL';
      if (r.passed) {
        orchPassed++;
      } else {
        orchFailed++;
      }
      _log('ORCH', '  ${r.name}: $status -- ${r.detail}');
      logSink?.writeln('  ${r.name}: $status -- ${r.detail}');
    }
    _log('ORCH', '----------------------------------------');
    _log(
      'ORCH',
      '  $orchPassed/${orchResults.length} passed, $orchFailed failed',
    );
    _log('ORCH', '========================================');

    // Write peer stderr to log sink for artifact capture.
    if (logSink != null && peer.stderrLines.isNotEmpty) {
      logSink.writeln('\n--- CLI Peer Stderr ---');
      for (final line in peer.stderrLines) {
        logSink.writeln(line);
      }
    }

    // Step 11: Cleanup.
    _log('ORCH', 'Cleaning up...');
    await peer.stopNode();
    await peer.kill();
    sigintSub.cancel();

    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }

    final combinedExitCode = (flutterExitCode != 0 || orchFailed > 0) ? 1 : 0;
    _log(
      'ORCH',
      'Done. Flutter=$flutterExitCode Orch=${orchFailed > 0 ? 1 : 0} '
          'Combined=$combinedExitCode',
    );
    return combinedExitCode == 0;
  } catch (e, st) {
    _log('ORCH', 'ERROR: $e\n$st');
    logSink?.writeln('ERROR: $e\n$st');
    await peer.kill();
    sigintSub.cancel();
    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }
    return false;
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  _log('ORCH', 'WiFi-Relay Fallback Smoke Test Orchestrator');

  // Parse arguments.
  String? deviceId;
  String? platform;
  int maxRetries = 2;
  String? artifactsDir;

  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      deviceId = args[i + 1];
      i++;
    }
    if ((args[i] == '--platform' || args[i] == '-p') && i + 1 < args.length) {
      platform = args[i + 1];
      i++;
    }
    if (args[i] == '--retry' && i + 1 < args.length) {
      maxRetries = int.tryParse(args[i + 1]) ?? 2;
      i++;
    }
    if (args[i] == '--artifacts' && i + 1 < args.length) {
      artifactsDir = args[i + 1];
      i++;
    }
  }

  if (platform == null) {
    _log('ORCH', 'ERROR: --platform (-p) is required. Use "ios" or "android".');
    exit(1);
  }

  // Auto-detect device.
  if (deviceId == null) {
    deviceId = await _detectDevice(platform);
    if (deviceId == null) {
      _log(
        'ORCH',
        'ERROR: No $platform device found. '
            'Start an emulator/simulator first.',
      );
      exit(1);
    }
  }

  // Prepare artifacts directory.
  IOSink? logSink;
  if (artifactsDir != null) {
    final dir = Directory(artifactsDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
  }

  // Retry loop.
  var passed = false;
  for (var attempt = 1; attempt <= maxRetries + 1; attempt++) {
    _log('ORCH', '');
    _log('ORCH', '========================================');
    _log('ORCH', 'ATTEMPT $attempt/${maxRetries + 1}');
    _log('ORCH', '========================================');

    // Create per-attempt log file.
    if (artifactsDir != null) {
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final logPath = '$artifactsDir/smoke_attempt_${attempt}_$ts.log';
      final logFile = File(logPath);
      logSink = logFile.openWrite();
      logSink.writeln('Smoke test attempt $attempt at ${DateTime.now()}');
      logSink.writeln('Platform: $platform Device: $deviceId');
      logSink.writeln('');
    }

    try {
      passed = await _runOnce(
        deviceId: deviceId,
        platform: platform,
        logSink: logSink,
      );
    } catch (e, st) {
      _log('ORCH', 'Attempt $attempt crashed: $e\n$st');
      logSink?.writeln('CRASH: $e\n$st');
      passed = false;
    } finally {
      await logSink?.flush();
      await logSink?.close();
      logSink = null;
    }

    if (passed) {
      _log('ORCH', 'Attempt $attempt: PASSED');
      break;
    } else {
      _log('ORCH', 'Attempt $attempt: FAILED');
      if (attempt <= maxRetries) {
        final backoff = Duration(seconds: attempt * 5);
        _log('ORCH', 'Retrying in ${backoff.inSeconds}s...');
        await Future.delayed(backoff);
      }
    }
  }

  // Final summary.
  _log('ORCH', '');
  _log('ORCH', '========================================');
  _log('ORCH', 'FINAL RESULT: ${passed ? 'PASSED' : 'FAILED'}');
  _log('ORCH', '========================================');

  if (artifactsDir != null) {
    _log('ORCH', 'Artifacts saved to: $artifactsDir');
  }

  exit(passed ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

void _deleteIfExists(String path) {
  try {
    File(path).deleteSync();
  } catch (_) {}
}

void _cleanupTempDir(Directory dir) {
  try {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  } catch (_) {}
}

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

Future<String?> _detectDevice(String platform) async {
  _log('ORCH', 'Auto-detecting $platform device...');
  final result = await Process.run('flutter', ['devices', '--machine']);
  if (result.exitCode != 0) {
    _log('ORCH', 'flutter devices failed: ${result.stderr}');
    return null;
  }

  final devices = jsonDecode(result.stdout as String) as List<dynamic>;
  for (final d in devices) {
    final device = d as Map<String, dynamic>;
    final targetPlatform = device['targetPlatform'] as String? ?? '';
    final isEmulator = device['emulator'] as bool? ?? false;

    if (platform == 'android' &&
        targetPlatform.startsWith('android') &&
        isEmulator) {
      final id = device['id'] as String;
      _log('ORCH', 'Found Android emulator: $id');
      return id;
    }
    if (platform == 'ios' && targetPlatform.contains('ios') && isEmulator) {
      final id = device['id'] as String;
      _log('ORCH', 'Found iOS simulator: $id');
      return id;
    }
  }

  _log('ORCH', 'No $platform emulator/simulator found');
  return null;
}
