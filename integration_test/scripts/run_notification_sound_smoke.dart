#!/usr/bin/env dart
// Notification Sound Smoke — Two-Simulator Orchestrator
//
// Drives four scenarios across two iOS simulators:
//   S1: 1:1 direct chat              (expect notification + sound)
//   S2: Group discussion (chat)      (expect notification + sound)
//   S3: Group announcement           (expect notification + sound)
//   S4: Suppression control          (expect NO notification — gate works)
//
// For each scenario the orchestrator asks the operator "did you hear sound?"
// so the final report combines programmatic FLOW-event verdicts with audible
// confirmation. Programmatic results alone prove the code path fires; the
// human confirmation proves the OS delivers audio at the speaker.
//
// Usage:
//   dart run integration_test/scripts/run_notification_sound_smoke.dart \
//       -d <alice_udid>,<bob_udid>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _aliceHarness =
    'integration_test/notification_sound_smoke_alice_harness.dart';
const _bobHarness =
    'integration_test/notification_sound_smoke_bob_harness.dart';

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

List<String> _notificationDartDefines() {
  if (!_nonInteractive) return const [];
  return const ['--dart-define=NOTIFICATION_SOUND_NON_INTERACTIVE=true'];
}

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

late Directory _sharedDir;
late String _runId;

String _sig(String name) => '${_sharedDir.path}/nsmoke_${_runId}_$name';

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
      // Sink may be closed during teardown; swallow to avoid killing the
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
    ..._notificationDartDefines(),
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

bool _nonInteractive = false;

String _promptOperator(String prompt) {
  stdout.write(prompt);
  if (_nonInteractive) {
    stdout.writeln('[non-interactive: skipped]');
    return '';
  }
  final line = stdin.readLineSync(encoding: utf8);
  return (line ?? '').trim().toLowerCase();
}

void _printChecklist() {
  stdout.writeln('\n${'═' * 70}');
  stdout.writeln('  NOTIFICATION SOUND SMOKE — MANUAL AUDIO CHECKLIST');
  stdout.writeln('═' * 70);
  stdout.writeln('Before starting, confirm on Bob\'s simulator:');
  stdout.writeln(
    '  [ ] Simulator menu > I/O > Audio Output > your Mac\'s speakers',
  );
  stdout.writeln('  [ ] macOS host volume > 50% and NOT muted');
  stdout.writeln('  [ ] Simulator Settings > Focus / Do Not Disturb = OFF');
  stdout.writeln(
    '  [ ] Settings > <app> > Notifications > Allow Notifications = ON',
  );
  stdout.writeln('  [ ] Settings > <app> > Notifications > Sounds = ON');
  stdout.writeln('${'═' * 70}\n');
  _promptOperator('Press Enter when ready to run S1..S4: ');
}

class ScenarioOutcome {
  final String id;
  final bool programmaticPass;
  final bool? audibleConfirmed;
  final Map<String, dynamic> verdict;
  ScenarioOutcome({
    required this.id,
    required this.programmaticPass,
    required this.audibleConfirmed,
    required this.verdict,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'programmaticPass': programmaticPass,
    'audibleConfirmed': audibleConfirmed,
    'verdict': verdict,
  };
}

Future<ScenarioOutcome> _runScenario({
  required String id,
  required String goSignal,
  required String bobVerdictSignal,
  required String verdictAckSignal,
  required String description,
  required bool expectAudible,
}) async {
  _log('ORCH', '─── $id: $description ───');
  _writeSignal(goSignal);
  final verdict = await _readJsonSignal(bobVerdictSignal);
  final programmaticPass = verdict['programmaticPass'] as bool? ?? false;
  _log(
    'ORCH',
    '$id programmatic: ${programmaticPass ? 'PASS' : 'FAIL'} '
        '(shown=${verdict['notificationShown']}, '
        'suppressed=${verdict['notificationSuppressed']})',
  );

  bool? audibleConfirmed;
  if (_nonInteractive) {
    audibleConfirmed = null;
  } else if (expectAudible) {
    final answer = _promptOperator(
      '$id — did you hear a notification SOUND on Bob\'s simulator? (y/n): ',
    );
    audibleConfirmed = answer.startsWith('y');
  } else {
    final answer = _promptOperator(
      '$id — confirm Bob\'s simulator stayed SILENT (no sound)? (y/n): ',
    );
    audibleConfirmed = answer.startsWith('y');
  }

  _writeSignal(verdictAckSignal);
  return ScenarioOutcome(
    id: id,
    programmaticPass: programmaticPass,
    audibleConfirmed: audibleConfirmed,
    verdict: verdict,
  );
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1].split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
      i++;
    } else if (args[i] == '--non-interactive') {
      _nonInteractive = true;
    }
  }
  if (devices.length != 2) {
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_notification_sound_smoke.dart '
      '-d <alice_udid>,<bob_udid>',
    );
    exit(1);
  }
  final aliceDevice = devices[0];
  final bobDevice = devices[1];

  _runId = DateTime.now().millisecondsSinceEpoch.toString();
  _sharedDir = await Directory.systemTemp.createTemp('notif_sound_smoke_');

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
  final outcomes = <ScenarioOutcome>[];

  try {
    alice = await _launchHarness(
      harness: _aliceHarness,
      role: 'alice',
      deviceId: aliceDevice,
      dbName: 'notif_sound_smoke_${_runId}_alice.db',
    );
    _pipeOutput(alice.stdout, 'ALICE', aliceLog);
    _pipeOutput(alice.stderr, 'ALICE-ERR', aliceLog);

    _log('ORCH', 'Waiting for alice_ready...');
    await _waitForSignal('alice_ready');
    _log('ORCH', 'Alice ready — launching Bob');

    bob = await _launchHarness(
      harness: _bobHarness,
      role: 'bob',
      deviceId: bobDevice,
      dbName: 'notif_sound_smoke_${_runId}_bob.db',
    );
    _pipeOutput(bob.stdout, 'BOB', bobLog);
    _pipeOutput(bob.stderr, 'BOB-ERR', bobLog);

    _log('ORCH', 'Waiting for bob_ready...');
    await _waitForSignal('bob_ready');
    _log('ORCH', 'Both harnesses ready');

    // Human checklist + audio-setup confirmation.
    _printChecklist();

    // S1: 1:1 direct
    outcomes.add(
      await _runScenario(
        id: 'S1',
        goSignal: 's1_go',
        bobVerdictSignal: 's1_bob_verdict',
        verdictAckSignal: 's1_verdict_ack',
        description: '1:1 direct chat (expect notification + sound)',
        expectAudible: true,
      ),
    );

    // S2: Group discussion (GroupType.chat). Group creation + join runs
    // inside the harnesses; orchestrator just triggers the send.
    _log('ORCH', 'Waiting for Bob to join chat group...');
    await _waitForSignal('bob_group_chat_joined');
    outcomes.add(
      await _runScenario(
        id: 'S2',
        goSignal: 's2_go',
        bobVerdictSignal: 's2_bob_verdict',
        verdictAckSignal: 's2_verdict_ack',
        description: 'Group discussion (expect notification + sound)',
        expectAudible: true,
      ),
    );

    // S3: Group announcement
    _log('ORCH', 'Waiting for Bob to join announcement group...');
    await _waitForSignal('bob_group_announcement_joined');
    outcomes.add(
      await _runScenario(
        id: 'S3',
        goSignal: 's3_go',
        bobVerdictSignal: 's3_bob_verdict',
        verdictAckSignal: 's3_verdict_ack',
        description: 'Group announcement (expect notification + sound)',
        expectAudible: true,
      ),
    );

    // S4: Suppression control — Bob simulates viewing Alice's 1:1 conversation.
    _log('ORCH', 'Waiting for Bob to simulate viewing conversation...');
    await _waitForSignal('bob_viewing_conversation');
    outcomes.add(
      await _runScenario(
        id: 'S4',
        goSignal: 's4_go',
        bobVerdictSignal: 's4_bob_verdict',
        verdictAckSignal: 's4_verdict_ack',
        description: 'Suppression control (expect SILENCE)',
        expectAudible: false,
      ),
    );

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

    // Summary
    final summary = <String, dynamic>{
      'runId': _runId,
      'sharedDir': _sharedDir.path,
      'scenarios': outcomes.map((o) => o.toJson()).toList(),
    };
    final summaryPath =
        '${Directory.systemTemp.path}/notification_sound_smoke_summary_$_runId.json';
    File(
      summaryPath,
    ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));

    stdout.writeln('\n${'═' * 70}');
    stdout.writeln('  NOTIFICATION SOUND SMOKE — RESULTS');
    stdout.writeln('═' * 70);
    for (final o in outcomes) {
      final audioMark = o.audibleConfirmed == null
          ? 'skip'
          : (o.audibleConfirmed! ? 'YES' : 'NO');
      final progMark = o.programmaticPass ? 'PASS' : 'FAIL';
      stdout.writeln('  ${o.id}: programmatic=$progMark  audible=$audioMark');
    }
    stdout.writeln('\n  Summary JSON: $summaryPath');
    stdout.writeln('${'═' * 70}\n');

    // Exit code: non-zero if any programmatic failure, OR any S1/S2/S3 was
    // NOT audibly confirmed, OR S4 was audible (suppression failure).
    // In non-interactive mode, audibleConfirmed is null and does not count.
    final failed = outcomes.any((o) {
      if (!o.programmaticPass) return true;
      if (o.audibleConfirmed == null) return false;
      if (o.id == 'S4') return o.audibleConfirmed == true;
      return o.audibleConfirmed == false;
    });
    exit(failed ? 1 : 0);
  }
}
