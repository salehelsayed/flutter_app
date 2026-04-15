#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultDevice = '38FECA55-03C1-4907-BD9D-8E64BF8E3469';
const _testpeerBin = 'go-mknoon/bin/testpeer';
const _harnessPath = 'integration_test/benchmark_group_publish_harness.dart';

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

String _sharedPath(Directory dir, String runId, String name) =>
    '${dir.path}/gp_${runId}_$name';

void _writeSignal(Directory dir, String runId, String name) {
  File(_sharedPath(dir, runId, name)).writeAsStringSync('ok');
}

Future<Map<String, dynamic>> _waitForJson(
  Directory dir,
  String runId,
  String name, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sharedPath(dir, runId, name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw TimeoutException('Timed out waiting for json: ${file.path}');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    sink.writeln(line);
    if (line.contains('[BENCHMARK]') ||
        line.contains('[PHASE]') ||
        line.contains('PASS') ||
        line.contains('FAIL') ||
        line.contains('[WARNING]')) {
      stdout.writeln(line);
    }
  });
}

int _percentile(List<int> sortedValues, int p) {
  if (sortedValues.isEmpty) return 0;
  if (sortedValues.length == 1) return sortedValues.first;
  final rank = (p / 100.0) * (sortedValues.length - 1);
  final lower = rank.floor();
  final upper = rank.ceil();
  if (lower == upper) return sortedValues[lower];
  return ((sortedValues[lower] + sortedValues[upper]) / 2).round();
}

class TestPeer {
  Process? _process;
  final _pending = <Completer<Map<String, dynamic>>>[];
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  String? peerId;
  String? publicKey;
  String? mlKemPublicKey;

  Future<void> start() async {
    _process = await Process.start(_testpeerBin, []);
    _stdoutSub = _process!.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleStdout);
    _stderrSub = _process!.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => _log('PEER-ERR', line));
  }

  void _handleStdout(String line) {
    if (line.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(line) as Map<String, dynamic>;
      if (decoded.containsKey('event')) {
        _log('PEER-EVENT', line);
        return;
      }
      if (_pending.isNotEmpty) {
        _pending.removeAt(0).complete(decoded);
      }
      _log('PEER-RESP', line);
    } catch (_) {
      _log('PEER-WARN', 'Non-JSON stdout: $line');
    }
  }

  Future<Map<String, dynamic>> command(
    String cmd, [
    Map<String, dynamic>? params,
  ]) async {
    final completer = Completer<Map<String, dynamic>>();
    _pending.add(completer);
    final request = <String, dynamic>{'cmd': cmd};
    if (params != null) {
      request['params'] = params;
    }
    _process!.stdin.writeln(jsonEncode(request));
    await _process!.stdin.flush();
    return completer.future.timeout(const Duration(seconds: 60));
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

  Future<void> generateIdentity() async {
    final identity = await commandOk('generate_identity');
    peerId = identity['peerId'] as String;
    publicKey = identity['publicKey'] as String;

    final mlKem = await commandOk('mlkem_keygen');
    mlKemPublicKey = mlKem['publicKey'] as String;
  }

  Future<void> startNode() async {
    await commandOk('start');
    await commandOk('wait_relay', {'timeoutSec': 30});
    await commandOk('wait_circuit', {'timeoutSec': 30});
  }

  Future<void> writeFixture(String path) async {
    File(path).writeAsStringSync(
      jsonEncode({
        'peerId': peerId,
        'publicKey': publicKey,
        'mlKemPublicKey': mlKemPublicKey,
      }),
    );
  }

  Future<void> stop() async {
    try {
      await command('stop');
    } catch (_) {}
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _process?.kill();
    await _process?.exitCode.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _process?.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }
}

Future<String> _parseDevice(List<String> args) async {
  final idxShort = args.indexOf('-d');
  if (idxShort >= 0 && idxShort + 1 < args.length) {
    return args[idxShort + 1];
  }
  final idxLong = args.indexOf('--device');
  if (idxLong >= 0 && idxLong + 1 < args.length) {
    return args[idxLong + 1];
  }
  return _defaultDevice;
}

Future<void> main(List<String> args) async {
  final deviceId = await _parseDevice(args);
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'benchmark_group_publish_',
  );
  final logFile = File(
    '${sharedDir.path}/benchmark_group_publish.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final cliFixturePath = '${sharedDir.path}/cli_peer_fixture.json';

  final peer = TestPeer();
  Process? harness;

  try {
    _log('ORCH', 'Building Go test peer...');
    final build = await Process.run('go', [
      'build',
      '-o',
      'bin/testpeer',
      './cmd/testpeer/',
    ], workingDirectory: 'go-mknoon');
    if (build.exitCode != 0) {
      throw StateError('go build testpeer failed: ${build.stderr}');
    }

    await peer.start();
    await peer.generateIdentity();
    await peer.startNode();
    await peer.writeFixture(cliFixturePath);

    final args = <String>[
      'test',
      '-d',
      deviceId,
      '--dart-define=CLI_PEER_FIXTURE=$cliFixturePath',
      '--dart-define=BENCHMARK_SHARED_DIR=${sharedDir.path}',
      '--dart-define=BENCHMARK_RUN_ID=$runId',
      _harnessPath,
    ];
    _log('ORCH', 'Launching harness: flutter ${args.join(' ')}');
    harness = await Process.start('flutter', args);
    _pipeOutput(harness.stdout, 'HARNESS', logFile);
    _pipeOutput(harness.stderr, 'HARNESS-ERR', logFile);

    final joinFixture = await _waitForJson(
      sharedDir,
      runId,
      'join_fixture.json',
    );
    _log(
      'ORCH',
      'CLI joining group ${joinFixture['groupId']} as peer ${peer.peerId}',
    );
    await peer.commandOk('group_join', joinFixture);
    await peer.commandOk('clear_messages');
    _writeSignal(sharedDir, runId, 'cli_joined');

    final exitCode = await harness.exitCode;
    if (exitCode != 0) {
      throw StateError(
        'Group publish harness failed with exit code $exitCode '
        '(sharedDir=${sharedDir.path})',
      );
    }

    final groupMessages = await peer.commandOk('get_group_messages');
    final messages =
        (groupMessages['messages'] as List<dynamic>? ?? const <dynamic>[])
            .map((raw) => Map<String, dynamic>.from(raw as Map))
            .toList(growable: false);
    final deliveryTimings = <int>[];
    final decryptTimings = <int>[];
    for (final message in messages) {
      final delivery = (message['deliveryMs'] as num?)?.toInt() ?? 0;
      final decrypt = (message['decryptMs'] as num?)?.toInt() ?? 0;
      if (delivery > 0) {
        deliveryTimings.add(delivery);
      }
      decryptTimings.add(decrypt);
    }

    print(
      '[BENCHMARK] sim_group_publish_peers_ready_receiver_count = '
      '${messages.length}',
    );
    if (deliveryTimings.isNotEmpty) {
      deliveryTimings.sort();
      print(
        '[BENCHMARK] sim_group_publish_peers_ready_e2e_ms '
        'p50=${_percentile(deliveryTimings, 50)}ms '
        'p95=${_percentile(deliveryTimings, 95)}ms '
        '(n=${deliveryTimings.length})',
      );
    }
    if (decryptTimings.isNotEmpty) {
      decryptTimings.sort();
      print(
        '[BENCHMARK] sim_group_publish_receiver_decrypt_ms '
        'p50=${_percentile(decryptTimings, 50)}ms '
        'p95=${_percentile(decryptTimings, 95)}ms '
        '(n=${decryptTimings.length})',
      );
    }
  } finally {
    await peer.stop();
    harness?.kill();
    await logFile.flush();
    await logFile.close();
  }
}
