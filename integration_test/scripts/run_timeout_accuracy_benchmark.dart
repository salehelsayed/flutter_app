#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_support/signal_files.dart';

const _defaultDevice = '38FECA55-03C1-4907-BD9D-8E64BF8E3469';
const _testpeerBin = 'go-mknoon/bin/testpeer';
const _harnessPath = 'integration_test/benchmark_harness.dart';
const _benchmarkKey = 'TIMEOUT_ACCURACY';
const _messageCount = 2;

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
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

class TestPeer {
  Process? _process;
  final _pending = <Completer<Map<String, dynamic>>>[];
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

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

  Future<void> initializeNode() async {
    await commandOk('generate_identity');
    await commandOk('start');
    await commandOk('wait_relay', {'timeoutSec': 30});
    await commandOk('wait_circuit', {'timeoutSec': 30});
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

String _parseDevice(List<String> args) {
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
  final deviceId = _parseDevice(args);
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'benchmark_timeout_accuracy_',
  );
  final signals = SignalDir(
    dir: sharedDir.path,
    prefix: 'h_',
    runId: '${runId}_',
    role: 'Orchestrator',
    pollInterval: const Duration(milliseconds: 200),
  );
  final logFile = File(
    '${sharedDir.path}/benchmark_timeout_accuracy.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);

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
    await peer.initializeNode();

    final harnessArgs = <String>[
      'test',
      '-d',
      deviceId,
      '--dart-define=BENCHMARK=$_benchmarkKey',
      '--dart-define=BENCHMARK_SHARED_DIR=${sharedDir.path}',
      '--dart-define=BENCHMARK_RUN_ID=$runId',
      _harnessPath,
    ];
    _log('ORCH', 'Launching harness: flutter ${harnessArgs.join(' ')}');
    harness = await Process.start('flutter', harnessArgs);
    _pipeOutput(harness.stdout, 'HARNESS', logFile);
    _pipeOutput(harness.stderr, 'HARNESS-ERR', logFile);

    final receiverFixture = await signals.waitForJson(
      'receiver_fixture.json',
      timeout: const Duration(minutes: 3),
    );
    final peerId = receiverFixture['peerId'] as String;
    final addresses = (receiverFixture['addresses'] as List<dynamic>)
        .cast<String>();

    signals.writeSignal('send_go');
    await signals.waitForSignal(
      'capture_ready',
      timeout: const Duration(minutes: 3),
    );

    for (var i = 0; i < _messageCount; i++) {
      await peer.command('dial', {'peerId': peerId, 'addresses': addresses});
      final sendResult = await peer.commandOk('send_v1', {
        'peerId': peerId,
        'text': 'Timeout benchmark ${i + 1}',
        'senderUsername': 'TimeoutCli',
      });
      _log(
        'ORCH',
        'CLI send ${i + 1}/$_messageCount acked=${sendResult['acked']}',
      );
    }

    signals.writeSignal('cli_send_done');

    final exitCode = await harness.exitCode;
    if (exitCode != 0) {
      throw StateError(
        'Timeout accuracy harness failed with exit code $exitCode '
        '(sharedDir=${sharedDir.path})',
      );
    }
  } finally {
    await peer.stop();
    harness?.kill();
    await logFile.flush();
    await logFile.close();
  }
}
