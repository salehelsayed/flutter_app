#!/usr/bin/env dart
// E2E Transport Test Orchestrator
//
// Coordinates between a Go CLI test peer and a Flutter integration test
// running on an iOS simulator or Android emulator.
//
// Usage:
//   dart run integration_test/scripts/run_transport_e2e.dart [--device <id>] [--platform <ios|android>]
//
// Examples:
//   dart run integration_test/scripts/run_transport_e2e.dart -p ios
//   dart run integration_test/scripts/run_transport_e2e.dart -p android
//   dart run integration_test/scripts/run_transport_e2e.dart -d emulator-5554
//
// The script:
//   1. Builds the Go CLI test peer binary
//   2. Spawns the test peer process (stdin/stdout JSON pipes)
//   3. Generates CLI peer identity + ML-KEM keys
//   4. Starts the CLI peer node and connects to relay
//   5. Writes fixture file for the Flutter test to read
//   6. Launches the Flutter integration test on a simulator/emulator
//   7. Coordinates test scenarios (sends, inbox stores, etc.)
//   8. Collects results and cleans up

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

// ---------------------------------------------------------------------------
// Run-scoped paths — unique temp directory per run for isolation + cleanup
// ---------------------------------------------------------------------------

class _RunPaths {
  final Directory hostTempDir;

  /// On iOS: same as hostTempDir.path. On Android: a /data/local/tmp/ path.
  /// Orchestrator pushes files here via adb; the app can READ from here.
  final String deviceDir;

  /// On iOS: same as deviceDir. On Android: app's own cache dir.
  /// The app writes signals here; orchestrator reads via `run-as` on Android.
  final String appWriteDir;

  _RunPaths(this.hostTempDir, this.deviceDir, this.appWriteDir);

  // Orchestrator → Flutter signals (pushed via adb, read by app).
  String get cliFixture => '$deviceDir/cli_peer_fixture.json';
  String get cliStopped => '$deviceDir/e2e_cli_stopped';
  String get cliB8Stopped => '$deviceDir/e2e_cli_b8_stopped';
  String get g6CliUploaded => '$deviceDir/e2e_g6_cli_uploaded';

  // Flutter → Orchestrator signals (written by app, read via run-as).
  String get flutterFixture => '$appWriteDir/flutter_peer_fixture.json';
  String get c1Sent => '$appWriteDir/e2e_c1_sent';
  String get b8Sent => '$appWriteDir/e2e_b8_sent';
  String get e8BlobId => '$appWriteDir/e2e_e8_blobid';
  String get g6FlutterUploaded => '$appWriteDir/e2e_g6_flutter_uploaded';

  // Host paths — files used by the Go testpeer process on the host machine.
  String get e8Downloaded => '${hostTempDir.path}/e2e_e8_downloaded.png';
  String get g6FlutterProfile =>
      '${hostTempDir.path}/e2e_g6_flutter_profile.png';
  String get g6CliProfile => '${hostTempDir.path}/e2e_g6_cli_profile.png';
}

// ---------------------------------------------------------------------------
// Device I/O — abstracts host filesystem vs adb for Android
// ---------------------------------------------------------------------------

/// Set when targeting an Android emulator; null for iOS simulator / desktop.
String? _androidDeviceId;

/// Resolves the full path to `adb`, checking common SDK locations.
String? _adbPath;
String _adb() {
  if (_adbPath != null) return _adbPath!;
  // Check ANDROID_HOME / ANDROID_SDK_ROOT, then common macOS path.
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
  // Fallback: hope it's on PATH.
  _adbPath = 'adb';
  return 'adb';
}

/// Writes content to a file on the device (or host for iOS).
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

/// Reads a file from the device (or host for iOS). Returns null if not found.
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

/// Checks if a file exists on the device (or host for iOS).
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

/// Creates a directory on the device. Returns the device path.
Future<String> _createDeviceTempDir(String deviceId) async {
  final ts = DateTime.now().millisecondsSinceEpoch;
  final deviceDir = '/data/local/tmp/e2e_transport_$ts';
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
  // Make world-writable so the sandboxed Flutter app can write signal files.
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

/// Removes a directory on the device.
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

/// Reads a file from the app's private storage via `run-as` (Android debug only).
/// On iOS/desktop, falls back to direct file access.
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

/// Checks if a file exists in the app's private storage via `run-as`.
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

/// Removes the app's e2e signal directory via `run-as`.
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
// Orchestrator result tracker
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
  final _responses = StreamController<Map<String, dynamic>>.broadcast();
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _pending = <Completer<Map<String, dynamic>>>[];
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  String? peerId;
  String? publicKey;
  String? privateKey;
  String? mnemonic;
  String? mlKemPublicKey;
  String? mlKemSecretKey;

  Future<void> start() async {
    _process = await Process.start(_testpeerBin, []);

    // Route stdout lines to responses/events.
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

      if (json.containsKey('event')) {
        _log('EVENT', '${json['event']}: ${json['data']}');
        _events.add(json);
      } else {
        _log('RESP', line.length > 200 ? '${line.substring(0, 200)}...' : line);
        _responses.add(json);

        // Complete the first pending request.
        if (_pending.isNotEmpty) {
          _pending.removeAt(0).complete(json);
        }
      }
    } catch (e) {
      _log('WARN', 'Non-JSON stdout: $line');
    }
  }

  /// Sends a command and waits for the response.
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

  /// Sends a command and asserts ok:true.
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

  /// Sends a command with retry and exponential backoff.
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
              '— retrying in ${delay.inSeconds}s',
        );
        await Future.delayed(delay);
      }
    }
    throw StateError('unreachable');
  }

  /// Generates identity and ML-KEM keys.
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

  /// Starts the node and waits for relay + circuit address.
  Future<void> startNode() async {
    await commandOk('start');
    _log('NODE', 'started, waiting for relay...');

    await commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    _log('NODE', 'relay connected, waiting for circuit...');

    await commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    _log('NODE', 'circuit address obtained');
  }

  /// Registers on the rendezvous namespace for this peer.
  Future<void> register() async {
    await commandOk('register');
    _log('NODE', 'registered on rendezvous');
  }

  /// Writes fixture file for the Flutter test.
  Future<void> writeFixture(String path) async {
    final data = {
      'peerId': peerId,
      'publicKey': publicKey,
      'mlKemPublicKey': mlKemPublicKey,
    };
    await _deviceWriteFile(path, jsonEncode(data));
    _log('FIXTURE', 'written to $path');
  }

  /// Stops the node.
  Future<void> stopNode() async {
    try {
      await command('stop');
    } catch (_) {}
  }

  /// Kills the process.
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
    _responses.close();
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

/// Runs the coordinated test scenarios after Flutter test starts.
/// Returns a list of orchestrator-side results for each scenario.
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
  final flutterMlKemPK = flutterPeer['mlKemPublicKey'] as String?;
  _log('ORCH', 'Flutter peer: ${flutterPeerId.substring(0, 20)}...');

  // --- G1: Status check ---
  _log('ORCH', 'Scenario G1: Status check...');
  try {
    final status = await peer.commandOk('status');
    final isStarted = status['isStarted'] == true;
    results.add(_OrchestratorResult('G1', isStarted, 'isStarted=$isStarted'));
    _log('ORCH', 'G1: isStarted=$isStarted');
  } catch (e) {
    results.add(_OrchestratorResult('G1', false, 'error: $e'));
    _log('ORCH', 'G1: failed: $e');
  }

  // Discover and dial the Flutter peer.
  _log('ORCH', 'Discovering Flutter peer...');
  final ns = 'mknoon:chat:$flutterPeerId';

  // Retry discovery (Flutter may not be registered yet).
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
    _log('ORCH', 'WARN: Could not dial Flutter peer — trying relay circuit');
    try {
      // Try relay circuit as fallback.
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

  // --- Scenario A2: Send v1 to Flutter ---
  _log('ORCH', 'Scenario A2: Sending v1 message to Flutter...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'A2: Hello from CLI peer',
    });
    results.add(_OrchestratorResult('A2', true, 'sent v1'));
    _log('ORCH', 'A2: sent');
  } catch (e) {
    results.add(_OrchestratorResult('A2', false, 'send failed: $e'));
    _log('ORCH', 'A2: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario A3: Send reply ---
  _log('ORCH', 'Scenario A3: Sending reply to Flutter...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'A3: Reply from CLI peer',
    });
    results.add(_OrchestratorResult('A3', true, 'sent reply'));
    _log('ORCH', 'A3: sent');
  } catch (e) {
    results.add(_OrchestratorResult('A3', false, 'send failed: $e'));
    _log('ORCH', 'A3: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario A5: Send v2 encrypted ---
  if (flutterMlKemPK != null) {
    _log('ORCH', 'Scenario A5: Sending v2 encrypted to Flutter...');
    try {
      await peer.commandOk('send_v2', {
        'peerId': flutterPeerId,
        'text': 'A5: Encrypted hello from CLI peer',
        'recipientMlKemPublicKey': flutterMlKemPK,
      });
      results.add(_OrchestratorResult('A5', true, 'sent v2 encrypted'));
      _log('ORCH', 'A5: sent');
    } catch (e) {
      results.add(_OrchestratorResult('A5', false, 'send failed: $e'));
      _log('ORCH', 'A5: send failed: $e');
    }
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario B2: Store in inbox for Flutter ---
  _log('ORCH', 'Scenario B2: Storing message in inbox for Flutter...');
  try {
    await peer.commandOk('inbox_store_v1', {
      'peerId': flutterPeerId,
      'text': 'B2: Inbox message from CLI peer',
    });
    results.add(_OrchestratorResult('B2', true, 'stored in inbox'));
    _log('ORCH', 'B2: stored');
  } catch (e) {
    results.add(_OrchestratorResult('B2', false, 'store failed: $e'));
    _log('ORCH', 'B2: store failed: $e');
  }

  // --- Scenario B3: Store 5 messages in inbox ---
  _log('ORCH', 'Scenario B3: Storing 5 inbox messages...');
  var b3Count = 0;
  for (var i = 1; i <= 5; i++) {
    try {
      await peer.commandOk('inbox_store_v1', {
        'peerId': flutterPeerId,
        'text': 'B3: Inbox message $i of 5',
      });
      b3Count++;
    } catch (e) {
      _log('ORCH', 'B3: store $i failed: $e');
    }
  }
  results.add(_OrchestratorResult('B3', b3Count == 5, 'stored $b3Count/5'));
  _log('ORCH', 'B3: stored $b3Count messages');

  // --- Scenario B5: Store inbox message with unknown sender ---
  _log('ORCH', 'Scenario B5: Storing inbox message from unknown sender...');
  try {
    // Build a v1 envelope with a fake sender peer ID not in Flutter's contacts.
    final ts = DateTime.now().toUtc().toIso8601String();
    final envelope = jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': 'b5-unknown-sender-msg-id',
        'text': 'B5: Message from unknown sender',
        'senderPeerId': '12D3KooWUnknownSenderForInboxLossTest',
        'senderUsername': 'UnknownPeer',
        'timestamp': ts,
      },
    });
    await peer.commandOk('inbox_store_raw', {
      'peerId': flutterPeerId,
      'envelope': envelope,
    });
    results.add(
      _OrchestratorResult('B5', true, 'stored unknown-sender envelope'),
    );
    _log('ORCH', 'B5: stored');
  } catch (e) {
    results.add(_OrchestratorResult('B5', false, 'store failed: $e'));
    _log('ORCH', 'B5: store failed: $e');
  }

  // --- Scenario B6: Store 60 messages in inbox (multi-drain) ---
  _log('ORCH', 'Scenario B6: Storing 60 inbox messages...');
  var b6Count = 0;
  for (var i = 1; i <= 60; i++) {
    try {
      final paddedIdx = i.toString().padLeft(3, '0');
      await peer.commandOk('inbox_store_v1', {
        'peerId': flutterPeerId,
        'text': 'B6: Inbox batch message $paddedIdx of 060',
        'messageId': 'b6-batch-msg-$paddedIdx',
      });
      b6Count++;
    } catch (e) {
      _log('ORCH', 'B6: store $i failed: $e');
    }
    // Pause every 10 messages to avoid relay rate-limiting.
    if (i % 10 == 0) {
      _log('ORCH', 'B6: stored $b6Count so far, pausing 500ms...');
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
  results.add(_OrchestratorResult('B6', b6Count == 60, 'stored $b6Count/60'));
  _log('ORCH', 'B6: stored $b6Count messages');

  // --- Scenario G2: Store v2 encrypted in inbox ---
  if (flutterMlKemPK != null) {
    _log('ORCH', 'Scenario G2: Storing v2 encrypted message in inbox...');
    try {
      await peer.commandOk('inbox_store_v2', {
        'peerId': flutterPeerId,
        'text': 'G2: Encrypted inbox from CLI peer',
        'recipientMlKemPublicKey': flutterMlKemPK,
      });
      results.add(_OrchestratorResult('G2', true, 'stored v2 in inbox'));
      _log('ORCH', 'G2: stored');
    } catch (e) {
      results.add(_OrchestratorResult('G2', false, 'store failed: $e'));
      _log('ORCH', 'G2: store failed: $e');
    }
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario D3: Two messages, different IDs, same text ---
  _log('ORCH', 'Scenario D3: Two messages with same text...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'D3: Duplicate text for dedup test',
    });
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'D3: Duplicate text for dedup test',
    });
    results.add(_OrchestratorResult('D3', true, 'sent 2 messages'));
    _log('ORCH', 'D3: sent 2 messages');
  } catch (e) {
    results.add(_OrchestratorResult('D3', false, 'send failed: $e'));
    _log('ORCH', 'D3: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario D4: Cross-transport dedup (same ID via relay + inbox) ---
  _log('ORCH', 'Scenario D4: Cross-transport dedup...');
  try {
    const d4MsgId = 'd4-dedup-cross-transport-test';
    // Send via relay with a fixed message ID.
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'D4: Cross-transport dedup test',
      'messageId': d4MsgId,
    });
    _log('ORCH', 'D4: sent via relay');
    // Wait for relay delivery before storing in inbox.
    await Future.delayed(const Duration(seconds: 2));
    // Store same ID in inbox (should be rejected by Flutter's messageExists).
    await peer.commandOk('inbox_store_v1', {
      'peerId': flutterPeerId,
      'text': 'D4: Cross-transport dedup test',
      'messageId': d4MsgId,
    });
    _log('ORCH', 'D4: stored duplicate in inbox');
    results.add(_OrchestratorResult('D4', true, 'sent via relay + inbox'));
  } catch (e) {
    results.add(_OrchestratorResult('D4', false, 'send failed: $e'));
    _log('ORCH', 'D4: failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario E1: Large message ---
  _log('ORCH', 'Scenario E1: Sending ~100KB message...');
  try {
    final largeText = 'E1:${'A' * 100000}';
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': largeText,
    });
    results.add(
      _OrchestratorResult('E1', true, 'sent ${largeText.length} bytes'),
    );
    _log('ORCH', 'E1: sent ${largeText.length} bytes');
  } catch (e) {
    results.add(_OrchestratorResult('E1', false, 'send failed: $e'));
    _log('ORCH', 'E1: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Scenario E3: Quote-reply ---
  _log('ORCH', 'Scenario E3: Sending quote-reply...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'E3: This is a quote reply',
      'quotedMessageId': 'fake-quoted-msg-id-12345',
    });
    results.add(_OrchestratorResult('E3', true, 'sent with quotedMessageId'));
    _log('ORCH', 'E3: sent');
  } catch (e) {
    results.add(_OrchestratorResult('E3', false, 'send failed: $e'));
    _log('ORCH', 'E3: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 1));

  // --- Scenario E4: Rapid fire 10 messages ---
  _log('ORCH', 'Scenario E4: Rapid fire 10 messages...');
  var e4Count = 0;
  for (var i = 1; i <= 10; i++) {
    try {
      await peer.commandOk('send_v1', {
        'peerId': flutterPeerId,
        'text': 'E4: Rapid message $i',
      });
      e4Count++;
    } catch (e) {
      _log('ORCH', 'E4: send $i failed: $e');
    }
  }
  results.add(_OrchestratorResult('E4', e4Count == 10, 'sent $e4Count/10'));
  _log('ORCH', 'E4: sent $e4Count rapid messages');

  await Future.delayed(const Duration(seconds: 1));

  // --- Scenario E6: Malformed envelope ---
  _log('ORCH', 'Scenario E6: Sending malformed message...');
  try {
    await peer.commandOk('send_raw', {
      'peerId': flutterPeerId,
      'raw': '{this is not valid json!!!',
    });
    results.add(_OrchestratorResult('E6', true, 'sent garbage'));
    _log('ORCH', 'E6: sent garbage');
  } catch (e) {
    // send_raw may fail if the peer rejects it — that's also acceptable.
    results.add(
      _OrchestratorResult('E6', true, 'send errored (acceptable): $e'),
    );
    _log('ORCH', 'E6: send failed (expected): $e');
  }

  // --- Scenario E7: Tampered v2 envelopes ---
  _log('ORCH', 'Scenario E7: Storing tampered v2 envelopes in inbox...');
  try {
    // E7a: Valid v2 JSON structure, garbage base64 in crypto fields.
    final e7aEnvelope = jsonEncode({
      'type': 'chat_message',
      'version': '2',
      'senderPeerId': peer.peerId,
      'encrypted': {
        'kem': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'ciphertext': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=',
        'nonce': 'CCCCCCCCCCCCCCCCCC==',
      },
    });
    await peer.commandOk('inbox_store_raw', {
      'peerId': flutterPeerId,
      'envelope': e7aEnvelope,
    });
    _log('ORCH', 'E7a: stored garbage crypto envelope');

    // E7b: Valid v2 JSON, plausible-looking but wrong base64 key material.
    final e7bEnvelope = jsonEncode({
      'type': 'chat_message',
      'version': '2',
      'senderPeerId': peer.peerId,
      'encrypted': {
        'kem':
            'dGhpcyBpcyBub3QgYSByZWFsIEtFTSBjaXBoZXJ0ZXh0IGJ1dCBpdCBsb29rcyBwbGF1c2libGU=',
        'ciphertext':
            'dGhpcyBpcyBub3QgcmVhbCBjaXBoZXJ0ZXh0IGVpdGhlciBidXQgaXQgaXMgYmFzZTY0',
        'nonce': 'bm90LWEtcmVhbC1ub25jZQ==',
      },
    });
    await peer.commandOk('inbox_store_raw', {
      'peerId': flutterPeerId,
      'envelope': e7bEnvelope,
    });
    _log('ORCH', 'E7b: stored plausible-but-wrong crypto envelope');

    results.add(
      _OrchestratorResult('E7', true, 'stored 2 tampered v2 envelopes'),
    );
  } catch (e) {
    results.add(_OrchestratorResult('E7', false, 'store failed: $e'));
    _log('ORCH', 'E7: store failed: $e');
  }

  // --- Scenario A7: Rendezvous discovery E2E ---
  _log('ORCH', 'Scenario A7: Sending via rendezvous-discovered path...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'A7: Discovered via rendezvous',
    });
    results.add(_OrchestratorResult('A7', true, 'sent via rendezvous'));
    _log('ORCH', 'A7: sent');
  } catch (e) {
    results.add(_OrchestratorResult('A7', false, 'send failed: $e'));
    _log('ORCH', 'A7: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 1));

  // --- Scenario E5: Unicode stress ---
  _log('ORCH', 'Scenario E5: Sending unicode messages...');
  var e5Count = 0;
  final e5Messages = [
    'E5-emoji: Hello \u{1F44B}\u{1F3FD} World \u{1F30D}\u{1F525}\u{1F48E}',
    'E5-rtl: \u0645\u0631\u062D\u0628\u0627 \u0628\u0627\u0644\u0639\u0627\u0644\u0645',
    'E5-cjk: \u4F60\u597D\u4E16\u754C \u3053\u3093\u306B\u3061\u306F',
    'E5-combining: \u00E9 = e\u0301, \u00F1 = n\u0303, Z\u0324\u0308 = Z\u0324\u0308',
  ];
  for (final text in e5Messages) {
    try {
      await peer.commandOk('send_v1', {'peerId': flutterPeerId, 'text': text});
      e5Count++;
    } catch (e) {
      _log('ORCH', 'E5: send failed: $e');
    }
  }
  results.add(_OrchestratorResult('E5', e5Count == 4, 'sent $e5Count/4'));
  _log('ORCH', 'E5: sent $e5Count unicode messages');

  await Future.delayed(const Duration(seconds: 1));

  // --- Scenario D1/D2: Duplicate relay messages (same message ID) ---
  _log('ORCH', 'Scenario D1: Sending duplicate relay messages...');
  try {
    const d1MsgId = 'd1-duplicate-test-id';
    final d1Ts = DateTime.now().toUtc().toIso8601String();
    final d1Envelope = jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': d1MsgId,
        'text': 'D1: Duplicate relay message',
        'senderPeerId': peer.peerId,
        'senderUsername': 'CLITestPeer',
        'timestamp': d1Ts,
      },
    });
    await peer.commandOk('send_raw', {
      'peerId': flutterPeerId,
      'raw': d1Envelope,
    });
    _log('ORCH', 'D1: first send done');
    await Future.delayed(const Duration(seconds: 3));
    await peer.commandOk('send_raw', {
      'peerId': flutterPeerId,
      'raw': d1Envelope,
    });
    _log('ORCH', 'D1: second send done');
    results.add(_OrchestratorResult('D1', true, 'sent same-ID message twice'));
  } catch (e) {
    results.add(_OrchestratorResult('D1', false, 'send failed: $e'));
    _log('ORCH', 'D1: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 1));

  // --- Scenario C3-pre: Send before network change ---
  _log('ORCH', 'Scenario C3: Sending pre-network-change message...');
  try {
    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'C3-pre: Before network change',
    });
    results.add(_OrchestratorResult('C3-pre', true, 'sent'));
    _log('ORCH', 'C3-pre: sent');
  } catch (e) {
    results.add(_OrchestratorResult('C3-pre', false, 'send failed: $e'));
    _log('ORCH', 'C3-pre: send failed: $e');
  }

  await Future.delayed(const Duration(seconds: 2));

  // --- Phase 2: C1 — Connection drop + inbox fallback ---
  _log('ORCH', 'Phase 2: C1 — stopping CLI node...');
  try {
    await Future.delayed(const Duration(seconds: 2));
    await peer.stopNode();
    _log('ORCH', 'C1: CLI node stopped');

    // Signal Flutter that the CLI node is down.
    await _deviceWriteFile(paths.cliStopped, 'stopped');
    _log('ORCH', 'C1: wrote ${paths.cliStopped} signal');

    // Wait for Flutter to send the C1 message.
    var c1SentFound = false;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _appFileExists(paths.c1Sent)) {
        c1SentFound = true;
        _log('ORCH', 'C1: Flutter sent signal received after ${i + 1}s');
        break;
      }
    }

    if (!c1SentFound) {
      _log('ORCH', 'C1: Flutter never sent signal — skipping retrieval');
      results.add(
        _OrchestratorResult(
          'C1',
          false,
          'Flutter signal not received after 60s',
        ),
      );
    } else {
      // Restart CLI node and retrieve inbox.
      await peer.startNode();
      await peer.register();
      _log('ORCH', 'C1: CLI node restarted');

      final inboxResult = await peer.commandOk('inbox_retrieve');
      final msgs = inboxResult['messages'] as List<dynamic>? ?? [];
      _log('ORCH', 'C1: retrieved ${msgs.length} inbox messages');

      // Check if any inbox message contains the C1 text.
      var c1Found = false;
      for (final m in msgs) {
        final mMap = m as Map<String, dynamic>;
        final message = mMap['message'] as String? ?? '';
        if (message.contains('C1:')) {
          c1Found = true;
          break;
        }
      }

      results.add(
        _OrchestratorResult(
          'C1',
          c1Found,
          c1Found ? 'C1 message found in inbox' : 'C1 not in inbox',
        ),
      );
      _log('ORCH', 'C1: ${c1Found ? 'PASS' : 'FAIL'}');
    }
  } catch (e) {
    results.add(_OrchestratorResult('C1', false, 'error: $e'));
    _log('ORCH', 'C1: failed: $e');
  } finally {
    // Clean up signal files.
    _deleteIfExists(paths.cliStopped);
    _deleteIfExists(paths.c1Sent);
  }

  // --- Phase 3: A8 — Relay reconnect ---
  _log('ORCH', 'Phase 3: A8 — Relay reconnect...');
  try {
    // CLI node was restarted in C1. Perform first reconnect cycle.
    await peer.commandWithRetry('reconnect_relays', null, 2);
    _log('ORCH', 'A8: first reconnect_relays done');
    await peer.commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    await peer.commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    await peer.register();
    _log('ORCH', 'A8: relay ready after reconnect');

    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'A8: After reconnect',
    });
    _log('ORCH', 'A8: sent first message');

    // Wait for Flutter reply (best-effort).
    try {
      await peer.commandOk('wait_message', {
        'fromPeerId': flutterPeerId,
        'timeoutSec': 30,
      });
      _log('ORCH', 'A8: got reply from Flutter');
    } catch (e) {
      _log('ORCH', 'A8: no reply within timeout (non-fatal): $e');
    }

    // Second reconnect cycle (regression guard).
    await peer.commandWithRetry('reconnect_relays', null, 2);
    _log('ORCH', 'A8: second reconnect done');
    await peer.commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    await peer.commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    await peer.register();

    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'A8b: Second reconnect',
    });
    _log('ORCH', 'A8: sent second message after second reconnect');
    results.add(
      _OrchestratorResult(
        'A8',
        true,
        'both reconnect cycles + sends succeeded',
      ),
    );
  } catch (e) {
    results.add(_OrchestratorResult('A8', false, 'error: $e'));
    _log('ORCH', 'A8: failed: $e');
  }

  // --- Phase 3b: C3-post — Network transition recovery ---
  _log('ORCH', 'Phase 3b: C3 — Network transition recovery...');
  try {
    await peer.commandWithRetry('reconnect_relays', null, 2);
    _log('ORCH', 'C3: reconnected relays');
    await peer.commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    await peer.commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    await peer.register();

    await peer.commandOk('send_v1', {
      'peerId': flutterPeerId,
      'text': 'C3-post: After network change',
    });
    results.add(_OrchestratorResult('C3-post', true, 'sent post-recovery'));
    _log('ORCH', 'C3-post: sent');
  } catch (e) {
    results.add(_OrchestratorResult('C3-post', false, 'error: $e'));
    _log('ORCH', 'C3-post: failed: $e');
  }

  // --- Phase 4: B8 — Encrypted inbox from Flutter ---
  _log('ORCH', 'Phase 4: B8 — Encrypted inbox...');
  try {
    await peer.stopNode();
    _log('ORCH', 'B8: CLI stopped');
    await _deviceWriteFile(paths.cliB8Stopped, 'stopped');

    var b8SentFound = false;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _appFileExists(paths.b8Sent)) {
        b8SentFound = true;
        _log('ORCH', 'B8: Flutter sent signal after ${i + 1}s');
        break;
      }
    }

    if (!b8SentFound) {
      results.add(
        _OrchestratorResult('B8', false, 'Flutter signal not received'),
      );
      _log('ORCH', 'B8: SKIP — Flutter signal not found');
    } else {
      await peer.startNode();
      await peer.register();
      _log('ORCH', 'B8: CLI restarted');

      final inboxResult = await peer.commandOk('inbox_retrieve');
      final msgs = inboxResult['messages'] as List<dynamic>? ?? [];
      _log('ORCH', 'B8: retrieved ${msgs.length} inbox messages');

      // Verify at least one v2 encrypted envelope.
      var foundV2 = false;
      for (final m in msgs) {
        final mMap = m as Map<String, dynamic>;
        final message = mMap['message'] as String? ?? '';
        if ((message.contains('"version":"2"') ||
                message.contains('"version": "2"')) &&
            message.contains('"encrypted"') &&
            message.contains('"kem"')) {
          foundV2 = true;
          _log('ORCH', 'B8: found v2 encrypted envelope in inbox');
          break;
        }
      }

      results.add(
        _OrchestratorResult(
          'B8',
          foundV2,
          foundV2
              ? 'v2 encrypted envelope found'
              : 'no v2 envelope in ${msgs.length} messages',
        ),
      );
    }
  } catch (e) {
    results.add(_OrchestratorResult('B8', false, 'error: $e'));
    _log('ORCH', 'B8: failed: $e');
  } finally {
    _deleteIfExists(paths.cliB8Stopped);
    _deleteIfExists(paths.b8Sent);
  }

  // Ensure node is running for remaining phases.
  try {
    final status = await peer.command('status');
    if (status['isStarted'] != true) {
      await peer.startNode();
      await peer.register();
    }
  } catch (_) {}

  // --- Phase 5: E8 — Media attachment ---
  _log('ORCH', 'Phase 5: E8 — Media attachment...');
  try {
    var e8BlobIdVal = '';
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      final content = await _appReadFile(paths.e8BlobId);
      if (content != null && content.trim().isNotEmpty) {
        e8BlobIdVal = content.trim();
        _log('ORCH', 'E8: blob ID = $e8BlobIdVal');
        break;
      }
    }

    if (e8BlobIdVal.isEmpty) {
      results.add(
        _OrchestratorResult('E8', false, 'blob ID signal not received'),
      );
      _log('ORCH', 'E8: SKIP — no blob ID');
    } else {
      final dlResult = await peer.commandOk('media_download', {
        'id': e8BlobIdVal,
        'outputPath': paths.e8Downloaded,
      });
      final dlSize = dlResult['size'] ?? 0;
      _log('ORCH', 'E8: downloaded, size=$dlSize');

      final listResult = await peer.commandOk('media_list');
      final blobs = listResult['blobs'] as List<dynamic>? ?? [];
      final blobFound = blobs.any(
        (b) => (b as Map<String, dynamic>)['id'] == e8BlobIdVal,
      );
      _log('ORCH', 'E8: media_list has blob=$blobFound');

      try {
        await peer.commandOk('media_delete', {'id': e8BlobIdVal});
      } catch (_) {}

      final pass = (dlSize as num) > 0 && blobFound;
      results.add(
        _OrchestratorResult(
          'E8',
          pass,
          'downloaded size=$dlSize blobInList=$blobFound',
        ),
      );
    }
  } catch (e) {
    results.add(_OrchestratorResult('E8', false, 'error: $e'));
    _log('ORCH', 'E8: failed: $e');
  } finally {
    _deleteIfExists(paths.e8BlobId);
    _deleteIfExists(paths.e8Downloaded);
  }

  // --- Phase 6: G6 — Profile upload/download ---
  _log('ORCH', 'Phase 6: G6 — Profile exchange...');
  try {
    var g6FlutterUploadedFound = false;
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(seconds: 1));
      if (await _appFileExists(paths.g6FlutterUploaded)) {
        g6FlutterUploadedFound = true;
        _log('ORCH', 'G6: Flutter upload signal after ${i + 1}s');
        break;
      }
    }

    if (!g6FlutterUploadedFound) {
      results.add(
        _OrchestratorResult('G6', false, 'Flutter upload signal not received'),
      );
      _log('ORCH', 'G6: SKIP — no upload signal');
    } else {
      // Download Flutter's profile.
      final dlResult = await peer.commandOk('profile_download', {
        'ownerPeerId': flutterPeerId,
        'outputPath': paths.g6FlutterProfile,
      });
      final dlSize = dlResult['size'] ?? 0;
      _log('ORCH', 'G6: downloaded Flutter profile, size=$dlSize');

      // Upload CLI's profile (minimal PNG).
      final cliProfileFile = File(paths.g6CliProfile);
      cliProfileFile.writeAsBytesSync(_minimalPngBytes());
      await peer.commandOk('profile_upload', {
        'mime': 'image/png',
        'filePath': paths.g6CliProfile,
      });
      _log('ORCH', 'G6: uploaded CLI profile');

      await _deviceWriteFile(paths.g6CliUploaded, 'uploaded');

      final pass = (dlSize as num) > 0;
      results.add(
        _OrchestratorResult(
          'G6',
          pass,
          'downloaded Flutter profile size=$dlSize, uploaded CLI profile',
        ),
      );
    }
  } catch (e) {
    results.add(_OrchestratorResult('G6', false, 'error: $e'));
    _log('ORCH', 'G6: failed: $e');
  } finally {
    _deleteIfExists(paths.g6FlutterUploaded);
    _deleteIfExists(paths.g6CliUploaded);
    _deleteIfExists(paths.g6FlutterProfile);
    _deleteIfExists(paths.g6CliProfile);
  }

  _log('ORCH', 'All scenarios dispatched');
  return results;
}

// ---------------------------------------------------------------------------
// Post-Flutter verification — check CLI peer received Flutter-to-CLI messages
// ---------------------------------------------------------------------------

/// Verifies that the CLI peer's message collector received messages sent by
/// the Flutter test (A1, A4, A6). Called after the Flutter test completes.
List<_OrchestratorResult> _verifyCliReceivedMessages(
  Map<String, dynamic> getMessagesResult,
  String flutterPeerId,
) {
  final results = <_OrchestratorResult>[];
  final messages = getMessagesResult['messages'] as List<dynamic>? ?? [];
  final count = messages.length;
  _log('VERIFY', 'CLI peer collected $count messages');

  // Collect raw content strings from the message collector.
  final rawContents = <String>[];
  for (final m in messages) {
    final msg = m as Map<String, dynamic>;
    final content = msg['content'] as String? ?? '';
    rawContents.add(content);
  }

  // A1: Flutter sent v1 plaintext — look for "A1:" in raw envelopes.
  final hasA1 = rawContents.any((c) => c.contains('"A1:'));
  results.add(
    _OrchestratorResult(
      'RECV-A1',
      hasA1,
      hasA1 ? 'v1 envelope received' : 'not found',
    ),
  );
  _log('VERIFY', 'RECV-A1: ${hasA1 ? 'PASS' : 'FAIL'}');

  // A4: Flutter sent v2 encrypted — look for version "2" AND Flutter's peer ID.
  // Matching both avoids false positives from non-A4 v2 messages.
  final hasA4 = rawContents.any(
    (c) =>
        (c.contains('"version":"2"') || c.contains('"version": "2"')) &&
        c.contains(flutterPeerId),
  );
  results.add(
    _OrchestratorResult(
      'RECV-A4',
      hasA4,
      hasA4 ? 'v2 envelope from Flutter received' : 'not found',
    ),
  );
  _log('VERIFY', 'RECV-A4: ${hasA4 ? 'PASS' : 'FAIL'}');

  // A6: Flutter sent fast-path message — look for "A6:" in raw envelopes.
  final hasA6 = rawContents.any((c) => c.contains('"A6:'));
  results.add(
    _OrchestratorResult(
      'RECV-A6',
      hasA6,
      hasA6 ? 'fast-path envelope received' : 'not found',
    ),
  );
  _log('VERIFY', 'RECV-A6: ${hasA6 ? 'PASS' : 'FAIL'}');

  return results;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

void main(List<String> args) async {
  _log('ORCH', 'E2E Transport Test Orchestrator');

  // Parse --device and --platform arguments.
  String? deviceId;
  String? platform;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--device' || args[i] == '-d') {
      deviceId = args[i + 1];
    }
    if (args[i] == '--platform' || args[i] == '-p') {
      platform = args[i + 1];
    }
  }

  // Auto-detect device when --platform is given but --device is not.
  if (deviceId == null && platform != null) {
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

  // Create unique temp directory for this run (isolation + cleanup).
  final hostTempDir = await Directory.systemTemp.createTemp('e2e_transport_');
  final isAndroid = platform == 'android';

  String deviceDir;
  String appWriteDir;
  if (isAndroid && deviceId != null) {
    _androidDeviceId = deviceId;
    deviceDir = await _createDeviceTempDir(deviceId);
    appWriteDir = '/data/data/$_appPackage/cache/e2e_signals';
    _log('ORCH', 'Android device temp dir: $deviceDir');
    _log('ORCH', 'Android app write dir: $appWriteDir');
  } else {
    deviceDir = hostTempDir.path;
    appWriteDir = hostTempDir.path;
  }
  final paths = _RunPaths(hostTempDir, deviceDir, appWriteDir);
  _log('ORCH', 'Host temp dir: ${hostTempDir.path}');

  final peer = TestPeer();

  // Register cleanup on Ctrl+C / kill.
  late final StreamSubscription sigintSub;
  sigintSub = ProcessSignal.sigint.watch().listen((_) async {
    _log('ORCH', 'SIGINT received — cleaning up...');
    await peer.kill();
    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }
    exit(130); // Standard SIGINT exit code
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      _log('ORCH', 'SIGTERM received — cleaning up...');
      await peer.kill();
      _cleanupTempDir(hostTempDir);
      if (_androidDeviceId != null) {
        await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
        await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
      }
      exit(143);
    });
  }

  try {
    // Step 1: Build CLI test peer.
    _log('ORCH', 'Building CLI test peer...');
    final buildResult = await Process.run('make', [
      'testpeer',
    ], workingDirectory: _goMknoonDir);
    if (buildResult.exitCode != 0) {
      _log('ORCH', 'ERROR: Build failed:\n${buildResult.stderr}');
      exit(1);
    }
    _log('ORCH', 'Build complete');

    // Step 2: Start CLI test peer process.
    _log('ORCH', 'Starting CLI test peer...');
    await peer.start();

    // Step 3: Generate identity + ML-KEM keys.
    await peer.generateIdentity();

    // Step 4: Start node, connect to relay, get circuit address.
    await peer.startNode();

    // Step 5: Register on rendezvous.
    await peer.register();

    // Step 6: Write fixture file.
    await peer.writeFixture(paths.cliFixture);

    // Step 7: Launch Flutter integration test.
    // On Android, clear app data to remove stale DBs from previous runs.
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
    _log('ORCH', 'Launching Flutter integration test...');

    final flutterArgs = [
      'test',
      'integration_test/transport_e2e_test.dart',
      '--dart-define=CLI_PEER_FIXTURE=${paths.cliFixture}',
      '--dart-define=E2E_TEMP_DIR=$deviceDir',
      '--dart-define=E2E_WRITE_DIR=$appWriteDir',
    ];
    if (deviceId != null) {
      flutterArgs.addAll(['-d', deviceId]);
    }

    final flutterProcess = await Process.start(
      'flutter',
      flutterArgs,
      mode: ProcessStartMode.inheritStdio,
    );

    // Step 8: Run scenarios in parallel with the Flutter test.
    final scenariosFuture = _runScenarios(peer, paths);

    // Wait for Flutter test to complete.
    final flutterExitCode = await flutterProcess.exitCode;
    _log('ORCH', 'Flutter test exited with code $flutterExitCode');

    // Wait for scenarios to finish (with timeout).
    List<_OrchestratorResult> orchResults;
    try {
      orchResults = await scenariosFuture.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          _log('ORCH', 'Scenarios timed out (ok — Flutter test finished)');
          return <_OrchestratorResult>[];
        },
      );
    } catch (e) {
      _log('ORCH', 'Scenarios errored: $e');
      orchResults = [_OrchestratorResult('SCENARIOS', false, 'error: $e')];
    }

    // Step 9: Post-Flutter verification — check CLI peer received messages.
    _log(
      'ORCH',
      'Post-Flutter verification: waiting 5s for in-flight messages...',
    );
    await Future.delayed(const Duration(seconds: 5));

    try {
      final msgs = await peer.commandOk('get_messages');
      final verifyResults = _verifyCliReceivedMessages(
        msgs,
        // Read Flutter peer ID from fixture if available.
        await _readFlutterPeerId(paths) ?? 'unknown',
      );
      orchResults.addAll(verifyResults);
    } catch (e) {
      _log('ORCH', 'Post-Flutter verification failed: $e');
      orchResults.add(
        _OrchestratorResult('VERIFY', false, 'get_messages failed: $e'),
      );
    }

    // G3: Exercise inbox_retrieve on CLI peer's own inbox.
    _log('ORCH', 'Scenario G3: inbox_retrieve...');
    try {
      final inboxResult = await peer.commandOk('inbox_retrieve');
      final inboxCount = inboxResult['count'] ?? 0;
      orchResults.add(
        _OrchestratorResult('G3', true, 'inbox_retrieve returned $inboxCount'),
      );
      _log('ORCH', 'G3: inbox_retrieve count=$inboxCount');
    } catch (e) {
      orchResults.add(_OrchestratorResult('G3', false, 'error: $e'));
      _log('ORCH', 'G3: failed: $e');
    }

    // G4: Exercise clear_messages + verify get_messages returns 0.
    _log('ORCH', 'Scenario G4: clear_messages + verify...');
    try {
      await peer.commandOk('clear_messages');
      final afterClear = await peer.commandOk('get_messages');
      final afterCount = afterClear['count'] ?? -1;
      final pass = afterCount == 0;
      orchResults.add(
        _OrchestratorResult('G4', pass, 'count after clear=$afterCount'),
      );
      _log('ORCH', 'G4: count after clear=$afterCount');
    } catch (e) {
      orchResults.add(_OrchestratorResult('G4', false, 'error: $e'));
      _log('ORCH', 'G4: failed: $e');
    }

    // G5: Exercise restore_identity — stop node, restore, verify peer ID matches.
    _log('ORCH', 'Scenario G5: restore_identity...');
    if (peer.mnemonic != null) {
      try {
        final originalPeerId = peer.peerId;
        await peer.stopNode();
        final restored = await peer.commandOk('restore_identity', {
          'mnemonic12': peer.mnemonic,
        });
        final restoredPeerId = restored['peerId'] as String?;
        final pass = restoredPeerId == originalPeerId;
        orchResults.add(
          _OrchestratorResult(
            'G5',
            pass,
            pass ? 'peerId matches' : 'mismatch: $restoredPeerId',
          ),
        );
        _log('ORCH', 'G5: ${pass ? 'PASS' : 'FAIL'}');
      } catch (e) {
        orchResults.add(_OrchestratorResult('G5', false, 'error: $e'));
        _log('ORCH', 'G5: failed: $e');
      }
    } else {
      orchResults.add(_OrchestratorResult('G5', false, 'no mnemonic saved'));
      _log('ORCH', 'G5: SKIP — no mnemonic');
    }

    // Step 10: Print orchestrator summary.
    _log('ORCH', '');
    _log('ORCH', '========================================');
    _log('ORCH', 'ORCHESTRATOR SUMMARY');
    _log('ORCH', '========================================');
    var orchPassed = 0;
    var orchFailed = 0;
    for (final r in orchResults) {
      final status = r.passed ? 'PASS' : 'FAIL';
      if (r.passed)
        orchPassed++;
      else
        orchFailed++;
      _log('ORCH', '  ${r.name}: $status — ${r.detail}');
    }
    _log('ORCH', '----------------------------------------');
    _log(
      'ORCH',
      '  $orchPassed/${orchResults.length} passed, $orchFailed failed',
    );
    _log('ORCH', '========================================');

    // Step 11: Cleanup.
    _log('ORCH', 'Cleaning up...');
    // Node may already be stopped from G5 — stopNode handles this gracefully.
    await peer.stopNode();
    await peer.kill();
    sigintSub.cancel();

    // Delete entire temp directory (all fixtures + signals).
    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }

    // Combined exit code: fail if either Flutter test OR orchestrator failed.
    final orchExitCode = orchFailed > 0 ? 1 : 0;
    final combinedExitCode = (flutterExitCode != 0 || orchExitCode != 0)
        ? 1
        : 0;

    _log(
      'ORCH',
      'Done. Flutter=$flutterExitCode Orch=$orchExitCode '
          'Combined=$combinedExitCode',
    );
    exit(combinedExitCode);
  } catch (e, st) {
    _log('ORCH', 'ERROR: $e\n$st');
    await peer.kill();
    sigintSub.cancel();
    _cleanupTempDir(hostTempDir);
    if (_androidDeviceId != null) {
      await _cleanupDeviceTempDir(_androidDeviceId!, deviceDir);
      await _cleanupAppWriteDir(_androidDeviceId!, appWriteDir);
    }
    exit(1);
  }
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

/// Auto-detect a device/emulator for the given platform.
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

/// Minimal valid 1x1 red PNG (67 bytes).
List<int> _minimalPngBytes() {
  return [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
    // IHDR chunk (13 bytes)
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
    0xDE,
    // IDAT chunk
    0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
    0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
    0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33,
    // IEND chunk
    0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
    0xAE, 0x42, 0x60, 0x82,
  ];
}

Future<String?> _readFlutterPeerId(_RunPaths paths) async {
  try {
    final content = await _appReadFile(paths.flutterFixture);
    if (content == null) return null;
    final data = jsonDecode(content) as Map<String, dynamic>;
    return data['peerId'] as String?;
  } catch (_) {
    return null;
  }
}
