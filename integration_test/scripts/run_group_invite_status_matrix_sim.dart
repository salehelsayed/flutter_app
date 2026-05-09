#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _harnessPath = 'integration_test/group_invite_status_matrix_harness.dart';
const _roles = <_HarnessRole>[
  _HarnessRole('creator', 'CREATOR'),
  _HarnessRole('accepted_one', 'ACCEPTED-ONE'),
  _HarnessRole('accepted_two', 'ACCEPTED-TWO'),
  _HarnessRole('pending_unaccepted', 'PENDING'),
];

class _HarnessRole {
  final String name;
  final String logTag;

  const _HarnessRole(this.name, this.logTag);
}

class _ProcessExit {
  final int exitCode;

  const _ProcessExit(this.exitCode);
}

bool _isIosDeviceId(String? deviceId) {
  if (deviceId == null) return false;
  return RegExp(
    r'^(?:[0-9A-F]{8}-[0-9A-F]{16}|[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12})$',
    caseSensitive: false,
  ).hasMatch(deviceId);
}

void _log(String tag, String message) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $message');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // The process can still flush output while teardown closes log sinks.
    }
  });
}

void _parseDevices(List<String> args, List<String> out) {
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      out.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    }
  }
  if (out.length != _roles.length) {
    throw ArgumentError(
      'Expected exactly four device IDs via -d '
      '<creator,accepted_one,accepted_two,pending_unaccepted>',
    );
  }
}

String _verdictPath(Directory sharedDir, String runId, String role) =>
    '${sharedDir.path}/invite_status_${runId}_${role}_verdict.json';

Future<Map<String, dynamic>> _waitForVerdict(
  Directory sharedDir,
  String runId,
  String role, {
  Duration timeout = const Duration(minutes: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(_verdictPath(sharedDir, runId, role));
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for $role verdict at ${file.path}');
}

Future<Map<String, dynamic>> _waitForVerdictOrExit({
  required Directory sharedDir,
  required String runId,
  required _HarnessRole role,
  required Process process,
  required String logPath,
}) async {
  final result = await Future.any<Object>([
    _waitForVerdict(sharedDir, runId, role.name),
    process.exitCode.then<Object>((exitCode) => _ProcessExit(exitCode)),
  ]);
  if (result is Map<String, dynamic>) {
    return result;
  }
  if (result is _ProcessExit) {
    throw StateError(
      '${role.name} exited with code ${result.exitCode} before writing a '
      'verdict; log=$logPath',
    );
  }
  throw StateError('${role.name} finished with unexpected result: $result');
}

Future<Process> _startHarnessRole({
  required _HarnessRole role,
  required String deviceId,
  required Directory sharedDir,
  required String runId,
}) async {
  final args = <String>[
    if (_isIosDeviceId(deviceId)) ...<String>[
      'drive',
      '--driver=test_driver/integration_test.dart',
      '--target=$_harnessPath',
      '--publish-port',
      '--no-pub',
    ] else ...<String>['test', '--no-pub', _harnessPath],
    '--dart-define=E2E_SHARED_DIR=${sharedDir.path}',
    '--dart-define=INVITE_STATUS_MATRIX_ROLE=${role.name}',
    '--dart-define=INVITE_STATUS_MATRIX_RUN_ID=$runId',
    '--dart-define=E2E_DB_NAME=group_invite_status_matrix_${runId}_${role.name}.db',
    '-d',
    deviceId,
  ];
  _log(role.logTag, 'Launching: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
}

void _validateVerdict(
  _HarnessRole role,
  Map<String, dynamic> verdict,
  List<String> failures,
) {
  if (verdict['role'] != role.name) {
    failures.add('${role.name}: verdict role mismatch: ${verdict['role']}');
  }
  if (role.name == 'creator') {
    if (verdict['creatorMatrixPass'] != true) {
      failures.add('${role.name}: creatorMatrixPass was not true');
    }
  } else if (verdict['roleAttachPass'] != true) {
    failures.add('${role.name}: roleAttachPass was not true');
  }
  if (verdict['relayLifecycleProof'] == true) {
    failures.add('${role.name}: harness unexpectedly claimed relay proof');
  }
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  try {
    _parseDevices(args, devices);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(
      'Usage: dart run integration_test/scripts/run_group_invite_status_matrix_sim.dart '
      '-d <creator_udid>,<accepted_one_udid>,<accepted_two_udid>,<pending_udid>',
    );
    exit(64);
  }

  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'group_invite_status_matrix_',
  );
  final logs = <String, IOSink>{};
  final processes = <String, Process>{};
  final failures = <String>[];

  _log('ORCH', 'Shared dir: ${sharedDir.path}');
  _log('ORCH', 'Run id: $runId');
  _log(
    'ORCH',
    'This is a seeded creator-side GroupInfoWired display proof. '
        'It does not claim relay/testpeer lifecycle proof.',
  );

  try {
    for (var i = 0; i < _roles.length; i++) {
      final role = _roles[i];
      final logPath = '${sharedDir.path}/${role.name}.log';
      final logSink = File(logPath).openWrite(mode: FileMode.writeOnlyAppend);
      logs[role.name] = logSink;
      final process = await _startHarnessRole(
        role: role,
        deviceId: devices[i],
        sharedDir: sharedDir,
        runId: runId,
      );
      processes[role.name] = process;
      _pipeOutput(process.stdout, role.logTag, logSink);
      _pipeOutput(process.stderr, '${role.logTag}-ERR', logSink);

      try {
        final verdict = await _waitForVerdictOrExit(
          sharedDir: sharedDir,
          runId: runId,
          role: role,
          process: process,
          logPath: logPath,
        );
        _log(role.logTag, 'Verdict: ${jsonEncode(verdict)}');
        _validateVerdict(role, verdict, failures);
      } catch (error) {
        failures.add('${role.name}: $error');
        break;
      }

      final exitCode = await process.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      if (exitCode != 0) {
        failures.add('${role.name}: flutter process exitCode=$exitCode');
      }
      if (failures.isNotEmpty) {
        break;
      }
    }

    _log('ORCH', 'Logs and verdicts: ${sharedDir.path}');
    for (final role in _roles) {
      _log('ORCH', '${role.name} log: ${sharedDir.path}/${role.name}.log');
      _log(
        'ORCH',
        '${role.name} verdict: ${_verdictPath(sharedDir, runId, role.name)}',
      );
    }

    if (failures.isNotEmpty) {
      throw StateError('Group invite status matrix failed: $failures');
    }

    _log('ORCH', 'Group invite status matrix display proof passed');
  } finally {
    for (final process in processes.values) {
      process.kill();
    }
    for (final sink in logs.values) {
      await sink.close();
    }
  }
}
