#!/usr/bin/env dart
//
// R6 device-matrix orchestrator: b1b_sibling_device_convergence.
//
// Drives the 2-role multi-device harness on two booted iOS simulators to prove
// per-device ML-KEM key separation. The primary (admin/creator) admits its OWN
// restored sibling device; the sibling obtains the current group key ONLY via
// the live announce->admit->redistribute path (a 1:1 key-update ML-KEM-sealed to
// its FRESH per-device key), never via the fixture. Built with the multi-device
// sync flag ON (test-scoped, via --dart-define). No CLI peer (unlike MD-004).
//
//   dart run integration_test/scripts/run_b1b_sibling_device_convergence.dart \
//     [-d <primarySimUuid>,<siblingSimUuid>]
//
// Defaults to the booted iPhone Air (primary) + iPhone 17 (sibling).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_support/signal_files.dart';

const _defaultPrimaryDevice = '347FB118-10D0-40C8-A05B-B0C3BD6B8CCD';
const _defaultSiblingDevice = '5BA69F1C-B112-47BE-B1FF-8C1003728C8F';
const _harnessPath = 'integration_test/group_multi_device_real_harness.dart';
const _scenario = 'b1b_sibling_device_convergence';

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

void _log(String tag, String msg) {
  final ts = DateTime.now().toIso8601String().substring(11, 23);
  stderr.writeln('[$ts] [$tag] $msg');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // The harness may still flush output after teardown closes the log.
    }
  });
}

Future<Process> _startHarnessRole({
  required String role,
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
    '--dart-define=MD004_SCENARIO=$_scenario',
    '--dart-define=MKNOON_ENABLE_MULTI_DEVICE_SYNC=true',
    '--dart-define=E2E_SHARED_DIR=${sharedDir.path}',
    '--dart-define=MD004_ROLE=$role',
    '--dart-define=MD004_RUN_ID=$runId',
    '--dart-define=E2E_DB_NAME=b1b_sibling_convergence_${runId}_$role.db',
    ..._relayDartDefines(),
    '-d',
    deviceId,
  ];
  _log('ORCH', 'Launching $role harness: flutter ${args.join(' ')}');
  return Process.start('flutter', args);
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
  if (out.isEmpty) {
    out.addAll([_defaultPrimaryDevice, _defaultSiblingDevice]);
  }
  if (out.length != 2) {
    throw ArgumentError(
      'Expected exactly two device IDs via -d <primary,sibling> or defaults',
    );
  }
}

Future<void> main(List<String> args) async {
  final devices = <String>[];
  _parseDevices(args, devices);
  final primaryDevice = devices[0];
  final siblingDevice = devices[1];
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'b1b_sibling_convergence_',
  );
  final signalDir = SignalDir(
    dir: sharedDir.path,
    prefix: 'md004_',
    runId: '${runId}_',
    role: 'Orchestrator',
  );
  final primaryLog = File(
    '${sharedDir.path}/primary.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  final siblingLog = File(
    '${sharedDir.path}/sibling.log',
  ).openWrite(mode: FileMode.writeOnlyAppend);
  Process? primary;
  Process? sibling;

  _log(
    'ORCH',
    'B1b shared dir: ${sharedDir.path}; primary=$primaryDevice sibling=$siblingDevice',
  );

  try {
    primary = await _startHarnessRole(
      role: 'primary',
      deviceId: primaryDevice,
      sharedDir: sharedDir,
      runId: runId,
    );
    _pipeOutput(primary.stdout, 'PRIMARY', primaryLog);
    _pipeOutput(primary.stderr, 'PRIMARY-ERR', primaryLog);

    // The primary publishes its identity + the group fixture once the group is
    // created; that is the cue to launch the sibling (which restores from it).
    await signalDir.waitForJson(
      'group_fixture.json',
      timeout: const Duration(minutes: 12),
    );
    _log('ORCH', 'Primary published the group fixture; starting sibling');

    sibling = await _startHarnessRole(
      role: 'sibling',
      deviceId: siblingDevice,
      sharedDir: sharedDir,
      runId: runId,
    );
    _pipeOutput(sibling.stdout, 'SIBLING', siblingLog);
    _pipeOutput(sibling.stderr, 'SIBLING-ERR', siblingLog);

    final primaryExit = await primary.exitCode;
    final siblingExit = await sibling.exitCode;
    if (primaryExit != 0 || siblingExit != 0) {
      throw StateError(
        'Harness failure: primaryExit=$primaryExit siblingExit=$siblingExit '
        'sharedDir=${sharedDir.path}',
      );
    }

    await signalDir.waitForSignal(
      'sibling_complete',
      timeout: const Duration(minutes: 2),
    );

    // Surface the per-device proof verdicts.
    for (final name in ['primary_verdict.json', 'sibling_verdict.json']) {
      final file = File('${sharedDir.path}/md004_${runId}_$name');
      if (file.existsSync()) {
        _log('VERDICT', '$name => ${file.readAsStringSync()}');
      }
    }
    _log('ORCH', 'B1b per-device ML-KEM convergence proof PASSED');
    _log('ORCH', 'Primary log: ${sharedDir.path}/primary.log');
    _log('ORCH', 'Sibling log: ${sharedDir.path}/sibling.log');
  } finally {
    try {
      primary?.kill();
    } catch (_) {}
    try {
      sibling?.kill();
    } catch (_) {}
    await primaryLog.close();
    await siblingLog.close();
  }
}
