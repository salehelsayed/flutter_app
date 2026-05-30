#!/usr/bin/env dart
// Transport Census CLI Orchestrator — SINGLE physical device.
//
// Pairs the Go CLI test peer (go-mknoon/bin/testpeer) as the RECEIVER with the
// transport-census harness (integration_test/transport_census_harness.dart,
// CENSUS_ROLE=sender) running on ONE physical device. This removes the
// second-phone dependency entirely: the test peer plays the receiver on the
// host machine while the device under test runs the sender.
//
// Modelled closely on run_transport_e2e.dart — the TestPeer driver class
// (Process.start of the testpeer binary, line-JSON stdin/stdout, command(),
// generateIdentity(), startNode(), register()) is copied from that file.
//
// Coordination is a host-side handoff (NO second device, NO device files):
//   1. Build + spawn the test peer; generate_identity + mlkem_keygen + start +
//      wait_relay + register so the device sender can discover it via rendezvous
//      on namespace mknoon:chat:<testpeerPeerId>.
//   2. Build the receiver identity JSON {peerId, publicKey, mlKemPublicKey,
//      rendezvous} and base64-encode it (the harness reads CENSUS_PEER_B64 and
//      base64-decodes — avoids quotes in the dart-define).
//   3. Run `flutter test` on the device in the FOREGROUND with the sender
//      dart-defines, streaming output to console + sender.log.
//   4. The test peer stays alive and auto-receives/acks at the transport level
//      (it does NOT need the sender as a contact).
//   5. When flutter test exits, print the ===CENSUS_BEGIN===...===CENSUS_END===
//      block from sender.log, stop the test peer, exit with flutter's code.
//
// Usage:
//   dart run integration_test/scripts/run_transport_census_cli.dart \
//     --device <id> [--condition <label>] [--n <int>] [--cold <true|false>] \
//     [--interval-ms <int>] [--relay <csv>]
//
// Example:
//   dart run integration_test/scripts/run_transport_census_cli.dart \
//     --device 21071FDF600CSC --condition A_cli --n 5 --cold true
//
// For a cross-network run the operator puts the device on cellular / a
// different network FIRST; this orchestrator does not manage the network.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const _goMknoonDir = 'go-mknoon';
const _testpeerBin = 'go-mknoon/bin/testpeer';
const _testpeerSrc = 'go-mknoon/cmd/testpeer';
const _harness = 'integration_test/transport_census_harness.dart';

// The rendezvous value the harness uses when adding a contact (kept identical
// to transport_census_harness.dart `_kRendezvous`).
const _kRendezvous = '/dns4/relay/tcp/443/p2p/relay';

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

// ---------------------------------------------------------------------------
// TestPeer — manages the Go CLI test peer process.
// Copied from run_transport_e2e.dart (trimmed to the methods this single-device
// census orchestrator needs: start/generateIdentity/startNode/register/stop).
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

    final request = <String, dynamic>{'cmd': cmd, 'params': ?params};

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
  /// [relayAddresses] is forwarded to the testpeer `start` command; when null
  /// the testpeer uses its built-in default relay.
  Future<void> startNode({List<String>? relayAddresses}) async {
    final params = <String, dynamic>{
      // CRITICAL for a faithful transport census: make the test-peer reply the
      // direct-confirm ACK on receipt (listener.go:68). Without it, the node's
      // EnableDeferredDirectAck (default true) waits for a Flutter confirm that
      // a headless peer never sends, so the sender's direct send times out its
      // confirm and falls back to its concurrent inbox custody — recording the
      // message as `inbox` even though the direct stream delivered. A real
      // phone receiver acks, so this makes the test-peer behave like one.
      'autoConfirmDirectAck': true,
    };
    if (relayAddresses != null && relayAddresses.isNotEmpty) {
      params['relayAddresses'] = relayAddresses;
    }
    await commandOk('start', params);
    _log('NODE', 'started, waiting for relay...');

    await commandWithRetry('wait_relay', {'timeoutSec': 30}, 3);
    _log('NODE', 'relay connected, waiting for circuit...');

    await commandWithRetry('wait_circuit', {'timeoutSec': 30}, 3);
    _log('NODE', 'circuit address obtained');
  }

  /// Registers on the rendezvous namespace for this peer
  /// (`mknoon:chat:<peerId>`) so the device sender can discover it.
  Future<void> register() async {
    await commandOk('register');
    _log('NODE', 'registered on rendezvous');
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
    if (!_responses.isClosed) _responses.close();
    if (!_events.isClosed) _events.close();
  }
}

// ---------------------------------------------------------------------------
// Arg parsing
// ---------------------------------------------------------------------------

class _Args {
  final String device;
  final String condition;
  final int n;
  final bool cold;
  final int intervalMs;
  final String relay;

  _Args({
    required this.device,
    required this.condition,
    required this.n,
    required this.cold,
    required this.intervalMs,
    required this.relay,
  });
}

_Args _parseArgs(List<String> argv) {
  String? device;
  var condition = 'cli';
  var n = 50;
  var cold = true;
  var intervalMs = 2500;
  var relay = '';

  for (var i = 0; i < argv.length; i++) {
    final arg = argv[i];
    String next() {
      if (i + 1 >= argv.length) {
        stderr.writeln('ERROR: $arg requires a value');
        exit(64);
      }
      return argv[++i];
    }

    switch (arg) {
      case '--device':
      case '-d':
        device = next();
      case '--condition':
        condition = next();
      case '--n':
        n = int.parse(next());
      case '--cold':
        cold = next().toLowerCase() == 'true';
      case '--interval-ms':
        intervalMs = int.parse(next());
      case '--relay':
        relay = next();
      case '-h':
      case '--help':
        stdout.writeln(
          'Usage: dart run integration_test/scripts/run_transport_census_cli.dart '
          '--device <id> [--condition <label>] [--n <int>] [--cold <true|false>] '
          '[--interval-ms <int>] [--relay <csv>]',
        );
        exit(0);
      default:
        stderr.writeln('Unknown arg: $arg');
        exit(64);
    }
  }

  if (device == null || device.isEmpty) {
    stderr.writeln('ERROR: --device <id> is required');
    exit(64);
  }

  return _Args(
    device: device,
    condition: condition,
    n: n,
    cold: cold,
    intervalMs: intervalMs,
    relay: relay,
  );
}

// ---------------------------------------------------------------------------
// Build the test peer binary if missing or stale.
// ---------------------------------------------------------------------------

Future<void> _buildTestPeerIfNeeded() async {
  final bin = File(_testpeerBin);
  var needsBuild = !bin.existsSync();

  if (!needsBuild) {
    // Rebuild if any source under cmd/testpeer is newer than the binary.
    final binModified = bin.lastModifiedSync();
    final srcDir = Directory(_testpeerSrc);
    if (srcDir.existsSync()) {
      for (final entry in srcDir.listSync(recursive: true)) {
        if (entry is File && entry.path.endsWith('.go')) {
          if (entry.lastModifiedSync().isAfter(binModified)) {
            needsBuild = true;
            break;
          }
        }
      }
    }
  }

  if (!needsBuild) {
    _log('BUILD', 'test peer binary up-to-date — skipping build');
    return;
  }

  _log('BUILD', 'building test peer: go build -o bin/testpeer ./cmd/testpeer');
  final result = await Process.run(
    'go',
    ['build', '-o', 'bin/testpeer', './cmd/testpeer'],
    workingDirectory: _goMknoonDir,
  );
  if (result.exitCode != 0) {
    _log('BUILD', 'STDOUT: ${result.stdout}');
    _log('BUILD', 'STDERR: ${result.stderr}');
    throw StateError('test peer build failed (exit ${result.exitCode})');
  }
  _log('BUILD', 'test peer built');
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------

Future<void> main(List<String> argv) async {
  final args = _parseArgs(argv);

  final relayAddresses = args.relay.trim().isEmpty
      ? <String>[]
      : args.relay
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

  final logDir = Directory('/tmp/transport_census_cli_${args.condition}');
  logDir.createSync(recursive: true);
  final senderLog = File('${logDir.path}/sender.log');

  stdout.writeln('============================================================');
  stdout.writeln('[CENSUS-CLI] Single-device transport census');
  stdout.writeln('[CENSUS-CLI]   device=${args.device} condition=${args.condition}');
  stdout.writeln('[CENSUS-CLI]   n=${args.n} cold=${args.cold} '
      'interval=${args.intervalMs}ms');
  stdout.writeln('[CENSUS-CLI]   relay=${relayAddresses.isEmpty ? '<testpeer built-in default>' : relayAddresses.join(',')}');
  stdout.writeln('[CENSUS-CLI]   sender log: ${senderLog.path}');
  stdout.writeln('============================================================');
  stdout.writeln('[CENSUS-CLI] The Go test peer is the RECEIVER (host machine).');
  stdout.writeln('[CENSUS-CLI] The device runs the harness as the SENDER.');
  stdout.writeln('[CENSUS-CLI] For a cross-network run, put the device on');
  stdout.writeln('[CENSUS-CLI] cellular / a different network BEFORE launching.');
  stdout.writeln('============================================================');

  // 1. Build the test peer if needed.
  await _buildTestPeerIfNeeded();

  // 2. Spawn + drive the test peer (RECEIVER role).
  final peer = TestPeer();
  await peer.start();
  _log('CLI', 'test peer process spawned');

  var peerStarted = false;
  try {
    await peer.generateIdentity();
    await peer.startNode(relayAddresses: relayAddresses);
    await peer.register();
    peerStarted = true;
    _log('CLI', 'test peer RECEIVER ready: peerId=${peer.peerId!.substring(0, 20)}... '
        'registered on mknoon:chat:<peerId>');

    // 3. Build + base64-encode the receiver identity for the harness.
    final identity = {
      'peerId': peer.peerId,
      'publicKey': peer.publicKey,
      'mlKemPublicKey': peer.mlKemPublicKey ?? '',
      'rendezvous': _kRendezvous,
    };
    final peerJson = jsonEncode(identity);
    final peerB64 = base64.encode(utf8.encode(peerJson));
    _log('CLI', 'receiver identity JSON: $peerJson');

    // 4. Run the census harness on the device, FOREGROUND, streaming output to
    //    console + sender.log. Keep the test peer pumping in the background:
    //    its node auto-receives/acks at the transport level while flutter runs.
    final relayDefine = relayAddresses.isEmpty ? '' : relayAddresses.join(',');
    final flutterArgs = <String>[
      'test',
      _harness,
      '-d',
      args.device,
      '--dart-define=CENSUS_ROLE=sender',
      '--dart-define=CENSUS_CONDITION=${args.condition}',
      '--dart-define=CENSUS_N=${args.n}',
      '--dart-define=CENSUS_COLD=${args.cold}',
      '--dart-define=CENSUS_SEND_INTERVAL_MS=${args.intervalMs}',
      '--dart-define=E2E_DB_NAME=census_sender.db',
      '--dart-define=MKNOON_RELAY_ADDRESSES=$relayDefine',
      '--dart-define=CENSUS_PEER_B64=$peerB64',
    ];

    _log('CLI', 'launching sender (foreground): flutter ${flutterArgs.join(' ')}');

    final sink = senderLog.openWrite();
    final flutterProc = await Process.start('flutter', flutterArgs);

    final stdoutDone = flutterProc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stdout.writeln(line);
      sink.writeln(line);
    });
    final stderrDone = flutterProc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      stderr.writeln(line);
      sink.writeln(line);
    });

    final exitCode = await flutterProc.exitCode;
    await stdoutDone.asFuture<void>();
    await stderrDone.asFuture<void>();
    await sink.flush();
    await sink.close();

    // 5. Print the census block from sender.log.
    stdout.writeln('');
    stdout.writeln('============================================================');
    stdout.writeln('[CENSUS-CLI] RUN COMPLETE — condition=${args.condition} '
        'exitCode=$exitCode');
    stdout.writeln('[CENSUS-CLI] sender log: ${senderLog.path}');
    stdout.writeln('============================================================');
    stdout.writeln('[CENSUS-CLI] ===== census block (SENDER vantage — authoritative) =====');
    _printCensusBlock(senderLog);

    // 6. Tear down the test peer.
    await peer.stopNode();
    await peer.kill();
    _log('CLI', 'test peer stopped');

    exit(exitCode);
  } catch (e, st) {
    _log('CLI', 'ERROR: $e');
    _log('CLI', '$st');
    if (peerStarted) {
      await peer.stopNode();
    }
    await peer.kill();
    exit(1);
  }
}

/// Extracts and prints the ===CENSUS_BEGIN===...===CENSUS_END=== block.
void _printCensusBlock(File senderLog) {
  if (!senderLog.existsSync()) {
    stdout.writeln('[CENSUS-CLI] (sender log not found — no census block)');
    return;
  }
  final lines = senderLog.readAsLinesSync();
  var inBlock = false;
  var found = false;
  for (final line in lines) {
    if (line.contains('===CENSUS_BEGIN===')) {
      inBlock = true;
      found = true;
    }
    if (inBlock) {
      stdout.writeln(line);
    }
    if (line.contains('===CENSUS_END===')) {
      inBlock = false;
    }
  }
  if (!found) {
    stdout.writeln('[CENSUS-CLI] (no census block in sender log — the sender '
        'may have failed before dumping; check ${senderLog.path})');
  }
}
