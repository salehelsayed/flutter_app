#!/usr/bin/env dart
// Foreground Group Push Simulator Smoke — Two-Simulator Orchestrator
//
// This script approximates the Report 71 real-device checklist on two iOS
// simulators. Alice and Bob run the real bridge / P2P / relay-backed group
// stack. Bob then replays the exact foreground push router to prove:
//   S1: missed live group delivery is recovered in the same foreground session
//   S2: live-first delivery followed by foreground replay does not duplicate
//
// It does not prove APNs delivery or physical-device OS behavior.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _aliceHarness =
    'integration_test/foreground_group_push_simulator_alice_harness.dart';
const _bobHarness =
    'integration_test/foreground_group_push_simulator_bob_harness.dart';

bool _isIosDeviceId(String? id) {
  if (id == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(id);
}

List<String> _relayDartDefines() {
  final relay = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  if (relay == null || relay.trim().isEmpty) return const [];
  return ['--dart-define=MKNOON_RELAY_ADDRESSES=${relay.trim()}'];
}

void _log(String tag, String message) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $message');
}

late Directory _sharedDir;
late String _runId;

String _sig(String name) => '${_sharedDir.path}/fgpush_${_runId}_$name';

void _writeSignal(String name) {
  File(_sig(name)).writeAsStringSync('ok');
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Orchestrator: timed out waiting for $name');
}

Future<Map<String, dynamic>> _readJsonSignal(
  String name, {
  Duration timeout = const Duration(minutes: 6),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_sig(name));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      try {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      } catch (_) {}
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Orchestrator: timed out waiting for json: $name');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } catch (_) {}
  });
}

Future<Process> _launchHarness({
  required String harness,
  required String role,
  required String deviceId,
  required String dbName,
}) async {
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$harness',
      '--publish-port',
      '--no-pub',
    ] else ...[
      'test',
      '--no-pub',
      harness,
    ],
    '--dart-define=E2E_SHARED_DIR=${_sharedDir.path}',
    '--dart-define=SMOKE_ROLE=$role',
    '--dart-define=SMOKE_RUN_ID=$_runId',
    '--dart-define=E2E_DB_NAME=$dbName',
    ..._relayDartDefines(),
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

Future<List<String>> _detectBootedSimulators() async {
  final result = await Process.run('xcrun', [
    'simctl',
    'list',
    'devices',
    'booted',
  ]);
  if (result.exitCode != 0) {
    throw StateError(
      'Failed to list booted simulators: ${result.stderr ?? result.stdout}',
    );
  }

  final output = result.stdout.toString();
  return RegExp(
    r'\(([0-9A-F-]+)\)\s+\(Booted\)',
    caseSensitive: false,
  ).allMatches(output).map((match) => match.group(1)!).toList(growable: false);
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1]
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      );
      i++;
    }
  }

  if (devices.isEmpty) {
    devices.addAll(await _detectBootedSimulators().then((ids) => ids.take(2)));
  }
  if (devices.length != 2) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_foreground_group_push_simulator_smoke.dart '
      '[-d <alice_udid>,<bob_udid>]',
    );
    stderr.writeln(
      'If -d is omitted, the first two booted simulators are used.',
    );
    exit(1);
  }

  final aliceDevice = devices[0];
  final bobDevice = devices[1];
  _runId = DateTime.now().millisecondsSinceEpoch.toString();
  _sharedDir = await Directory.systemTemp.createTemp('fgpush_smoke_');

  final aliceLog = File(
    '${_sharedDir.path}/alice.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final bobLog = File(
    '${_sharedDir.path}/bob.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);

  _log('ORCH', 'Shared dir: ${_sharedDir.path}');
  _log('ORCH', 'Alice=$aliceDevice  Bob=$bobDevice  runId=$_runId');

  Process? alice;
  Process? bob;
  final failures = <String>[];

  try {
    alice = await _launchHarness(
      harness: _aliceHarness,
      role: 'alice',
      deviceId: aliceDevice,
      dbName: 'fgpush_${_runId}_alice.db',
    );
    _pipeOutput(alice.stdout, 'ALICE', aliceLog);
    _pipeOutput(alice.stderr, 'ALICE-ERR', aliceLog);

    _log('ORCH', 'Waiting for Alice to be ready...');
    await _waitForSignal('alice_ready', timeout: const Duration(minutes: 10));

    bob = await _launchHarness(
      harness: _bobHarness,
      role: 'bob',
      deviceId: bobDevice,
      dbName: 'fgpush_${_runId}_bob.db',
    );
    _pipeOutput(bob.stdout, 'BOB', bobLog);
    _pipeOutput(bob.stderr, 'BOB-ERR', bobLog);

    _log('ORCH', 'Waiting for Bob to join...');
    await _waitForSignal(
      'bob_group_joined',
      timeout: const Duration(minutes: 12),
    );

    _log('ORCH', '─── S1: foreground group gap recovery ───');
    _writeSignal('s1_go');
    final s1Verdict = await _readJsonSignal('s1_bob_verdict');
    _writeSignal('s1_verified');
    final s1Pass = s1Verdict['programmaticPass'] == true;
    _log('ORCH', 'S1: ${s1Pass ? 'PASS' : 'FAIL'} — ${jsonEncode(s1Verdict)}');
    if (!s1Pass) failures.add('S1');

    _log('ORCH', '─── S2: live-first replay dedupe ───');
    _writeSignal('s2_go');
    final s2Verdict = await _readJsonSignal('s2_bob_verdict');
    _writeSignal('s2_verified');
    final s2Pass = s2Verdict['programmaticPass'] == true;
    _log('ORCH', 'S2: ${s2Pass ? 'PASS' : 'FAIL'} — ${jsonEncode(s2Verdict)}');
    if (!s2Pass) failures.add('S2');

    _writeSignal('all_done');
    await _waitForSignal('alice_done', timeout: const Duration(minutes: 5));
    await _waitForSignal('bob_done', timeout: const Duration(minutes: 5));

    final aliceExit = await alice.exitCode;
    final bobExit = await bob.exitCode;
    if (aliceExit != 0) failures.add('alice_exit=$aliceExit');
    if (bobExit != 0) failures.add('bob_exit=$bobExit');

    _log(
      'ORCH',
      failures.isEmpty
          ? 'Foreground group push simulator smoke PASSED'
          : 'Foreground group push simulator smoke FAILED: ${failures.join(', ')}',
    );
  } finally {
    await aliceLog.close();
    await bobLog.close();
    alice?.kill();
    bob?.kill();
  }

  if (failures.isNotEmpty) {
    exitCode = 1;
  }
}
