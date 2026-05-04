#!/usr/bin/env dart
// Notification-open during other chat — Two-Simulator Orchestrator
//
// Reproduces this user-reported bug:
//
//   Alice opens user-C's chat from Orbit, backgrounds the app. Bob sends
//   Alice a message; the OS shows a notification. Alice taps the
//   notification — the app should route Alice to Bob's conversation
//   (or to the Feed). Today the app stays on user-C's chat.
//
// Pairs alice + bob harnesses across two iOS simulators with shared
// signal-file coordination, and persists a single-row verdict the test
// run can use as a CI gate.
//
// Usage:
//   dart run integration_test/scripts/run_notification_open_during_other_chat.dart \
//       -d <alice_udid>,<bob_udid>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _aliceHarness =
    'integration_test/notification_open_during_other_chat_alice_harness.dart';
const _bobHarness =
    'integration_test/notification_open_during_other_chat_bob_harness.dart';

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

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

late Directory _sharedDir;
late String _runId;

String _sig(String name) => '${_sharedDir.path}/notifopen_${_runId}_$name';

void _writeSignal(String name) {
  File(_sig(name)).writeAsStringSync('ok');
}

Future<void> _waitForSignal(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (File(path).existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Orchestrator: timed out waiting for $name');
}

Future<Map<String, dynamic>> _readJsonSignal(
  String name, {
  Duration timeout = const Duration(minutes: 5),
}) async {
  final path = _sig(name);
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final file = File(path);
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
    } catch (_) {
      // Sink may be closed during teardown — swallow to avoid killing the
      // orchestrator with a cosmetic StreamSink exception.
    }
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

Future<void> main(List<String> args) async {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
      i++;
    }
  }
  if (devices.length != 2) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_notification_open_during_other_chat.dart '
      '-d <alice_udid>,<bob_udid>',
    );
    exit(1);
  }
  final aliceDevice = devices[0];
  final bobDevice = devices[1];

  _runId = DateTime.now().millisecondsSinceEpoch.toString();
  _sharedDir = await Directory.systemTemp.createTemp('notif_open_');

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
  Map<String, dynamic>? verdict;

  try {
    alice = await _launchHarness(
      harness: _aliceHarness,
      role: 'alice',
      deviceId: aliceDevice,
      dbName: 'notif_open_during_other_chat_${_runId}_alice.db',
    );
    _pipeOutput(alice.stdout, 'ALICE', aliceLog);
    _pipeOutput(alice.stderr, 'ALICE-ERR', aliceLog);

    _log('ORCH', 'Waiting for alice_ready...');
    // Generous timeout — first iOS Xcode build alone routinely takes
    // 4–5 min, then the harness needs another ~30–60s to come online via
    // relay and write the ready signal.
    await _waitForSignal(
      'alice_ready',
      timeout: const Duration(minutes: 12),
    );
    _log('ORCH', 'Alice ready — launching Bob');

    bob = await _launchHarness(
      harness: _bobHarness,
      role: 'bob',
      deviceId: bobDevice,
      dbName: 'notif_open_during_other_chat_${_runId}_bob.db',
    );
    _pipeOutput(bob.stdout, 'BOB', bobLog);
    _pipeOutput(bob.stderr, 'BOB-ERR', bobLog);

    _log('ORCH', 'Waiting for bob_ready...');
    await _waitForSignal(
      'bob_ready',
      timeout: const Duration(minutes: 12),
    );
    _log('ORCH', 'Both harnesses ready');

    _log('ORCH', 'Waiting for alice to enter user-c chat + background');
    await _waitForSignal('alice_in_user_c_chat');
    await _waitForSignal('alice_backgrounded');

    _log('ORCH', 'Triggering Bob send');
    _writeSignal('bob_send_go');

    _log('ORCH', 'Waiting for alice notification + verdict');
    await _waitForSignal('alice_notification_received');
    verdict = await _readJsonSignal('alice_verdict');

    _log('ORCH', 'Waiting for cold-start verdict');
    Map<String, dynamic>? coldStartVerdict;
    try {
      coldStartVerdict = await _readJsonSignal(
        'alice_cold_start_verdict',
        timeout: const Duration(minutes: 2),
      );
    } catch (e) {
      _log('ORCH', 'No cold-start verdict (older harness?): $e');
    }
    if (coldStartVerdict != null) {
      verdict['coldStart'] = coldStartVerdict;
    }

    _writeSignal('all_done');
    await _waitForSignal('alice_done', timeout: const Duration(seconds: 60));
    await _waitForSignal('bob_done', timeout: const Duration(seconds: 60));
  } finally {
    _log('ORCH', 'Cleaning up...');
    alice?.kill();
    bob?.kill();
    await aliceLog.flush();
    await aliceLog.close();
    await bobLog.flush();
    await bobLog.close();

    final summary = <String, dynamic>{
      'runId': _runId,
      'sharedDir': _sharedDir.path,
      'verdict': verdict,
    };
    final summaryPath =
        '${Directory.systemTemp.path}/notification_open_during_other_chat_summary_$_runId.json';
    File(summaryPath).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(summary),
    );

    stdout.writeln('\n${'═' * 70}');
    stdout.writeln('  NOTIFICATION-OPEN DURING OTHER CHAT — RESULTS');
    stdout.writeln('═' * 70);
    if (verdict == null) {
      stdout.writeln('  Verdict: <missing> — alice harness never wrote one');
    } else {
      stdout.writeln('  bobOnstage          : ${verdict['bobOnstage']}');
      stdout.writeln('  userCOnstage        : ${verdict['userCOnstage']}');
      stdout.writeln('  bobInTree           : ${verdict['bobInTree']}');
      stdout.writeln('  userCInTree         : ${verdict['userCInTree']}');
      stdout.writeln('  topRouteName        : ${verdict['topRouteName']}');
      stdout.writeln('  shownCount          : ${verdict['shownCount']}');
      stdout.writeln(
        '  notificationPayload : ${verdict['notificationPayload']}',
      );
      stdout.writeln('  programmaticPass    : ${verdict['programmaticPass']}');
      stdout.writeln('  reproducedBug       : ${verdict['reproducedBug']}');
      stdout.writeln('  trace               : ${verdict['trace']}');
      final navEvents = verdict['navEvents'];
      if (navEvents is List) {
        stdout.writeln('  navEvents:');
        for (final e in navEvents) {
          stdout.writeln('    $e');
        }
      }
      final coldStart = verdict['coldStart'];
      if (coldStart is Map) {
        stdout.writeln('\n  ── Cold-start phase ──');
        stdout.writeln('  bobOnstage          : ${coldStart['bobOnstage']}');
        stdout.writeln('  userCOnstage        : ${coldStart['userCOnstage']}');
        stdout.writeln('  topRouteName        : ${coldStart['topRouteName']}');
        stdout.writeln('  programmaticPass    : ${coldStart['programmaticPass']}');
        stdout.writeln('  reproducedBug       : ${coldStart['reproducedBug']}');
        final csNav = coldStart['navEvents'];
        if (csNav is List) {
          stdout.writeln('  navEvents:');
          for (final e in csNav) {
            stdout.writeln('    $e');
          }
        }
      }
    }
    stdout.writeln('\n  Summary JSON: $summaryPath');
    stdout.writeln('${'═' * 70}\n');

    final pass = verdict != null && (verdict['programmaticPass'] as bool? ?? false);
    exit(pass ? 0 : 1);
  }
}
