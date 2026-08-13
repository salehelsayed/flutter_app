#!/usr/bin/env dart
//
// R6 device-matrix orchestrator: b1b_sibling_device_convergence.
//
// Drives the availability-bounded physical-Android + Android-emulator pair.
// The fresh linked installation produces the production Plan-360 QR and starts
// with no group rows; the ordinary primary selects one group and bootstraps it
// through protected custody. Signals move only through AndroidAppSignalBroker.
//
//   dart run integration_test/scripts/run_b1b_sibling_device_convergence.dart \
//     -d <physicalAndroidId>,<androidEmulatorId>

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../_support/android_app_file_broker.dart';
import '../_support/invite_reliability_runner_contract.dart';
import '../_support/signal_files.dart';
import '_android_app_package.dart';

const _harnessPath = 'integration_test/group_multi_device_real_harness.dart';
const _scenario = 'b1b_sibling_device_convergence';

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
    'test',
    '--no-pub',
    _harnessPath,
    '--dart-define=MD004_SCENARIO=$_scenario',
    '--dart-define=MKNOON_ENABLE_DIRECT_LINKED_DEVICES=true',
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

List<String> _parseDevices(List<String> args) {
  final out = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      out.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    } else {
      throw ArgumentError('Unknown argument: ${args[i]}');
    }
  }
  if (out.length != 2 || out[0] == out[1]) {
    throw ArgumentError(
      'Expected exactly two distinct explicit device IDs via '
      '-d <physical-android,android-emulator>',
    );
  }
  if (!isPlausibleAndroidDeviceId(out[0]) ||
      !isPlausibleAndroidDeviceId(out[1])) {
    throw ArgumentError('Both B1b targets must be Android device IDs');
  }
  if (isAndroidEmulatorDeviceId(out[0]) || !isAndroidEmulatorDeviceId(out[1])) {
    throw ArgumentError(
      'B1b device order must be physical Android first and emulator second',
    );
  }
  return out;
}

Future<List<InviteReliabilityDeviceTarget>> _discoverFlutterDevices() async {
  final result = await Process.run('flutter', const <String>[
    'devices',
    '--machine',
  ]);
  if (result.exitCode != 0) {
    throw StateError('flutter devices --machine failed: ${result.stderr}');
  }
  final decoded = jsonDecode(result.stdout.toString());
  if (decoded is! List) {
    throw const FormatException('flutter devices --machine was not a list');
  }
  return decoded
      .map<InviteReliabilityDeviceTarget>((raw) {
        final value = Map<String, Object?>.from(raw as Map);
        return InviteReliabilityDeviceTarget(
          id: value['id']! as String,
          targetPlatform: value['targetPlatform']! as String,
          isEmulator: value['emulator']! as bool,
        );
      })
      .toList(growable: false);
}

Future<Set<String>> _discoverAdbDevices() async {
  final result = await Process.run('adb', const <String>['devices', '-l']);
  if (result.exitCode != 0) {
    throw StateError('adb devices -l failed: ${result.stderr}');
  }
  return result.stdout
      .toString()
      .split('\n')
      .skip(1)
      .map((line) => line.trim().split(RegExp(r'\s+')))
      .where((parts) => parts.length >= 2 && parts[1] == 'device')
      .map((parts) => parts.first)
      .toSet();
}

Future<void> _preflightTargets(List<String> devices) async {
  final discovered = await Future.wait<Object>(<Future<Object>>[
    _discoverFlutterDevices(),
    _discoverAdbDevices(),
  ]);
  final adb = discovered[1] as Set<String>;
  final missingAdb = devices.where((id) => !adb.contains(id)).toList();
  if (missingAdb.isNotEmpty) {
    throw StateError(
      'N/A (target unavailable by project policy): adb does not report '
      '${missingAdb.join(', ')}',
    );
  }
  final topology = validateLinkedGroupBootstrapB1bTopology(
    selectedDeviceIds: devices,
    liveDevices: discovered[0] as List<InviteReliabilityDeviceTarget>,
  );
  if (topology != null) {
    throw StateError('N/A (target unavailable by project policy): $topology');
  }
}

Future<void> main(List<String> args) async {
  late final List<String> devices;
  try {
    devices = _parseDevices(args);
    await _preflightTargets(devices);
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  } on StateError catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
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
  final package = resolveAndroidAppPackage();
  final remoteRelative = 'cache/b1b_linked_group_$runId';
  final remoteAbsolute = '/data/user/0/$package/$remoteRelative';
  final broker = AndroidAppSignalBroker(
    transport: AdbRunAsAppFileTransport(appPackage: package),
    deviceIds: devices,
    hostDirectory: sharedDir,
    remoteDirectory: remoteRelative,
    filePrefix: 'md004_${runId}_',
    log: (message) => _log('SYNC', message),
  );
  final brokerRun = broker.run();

  _log(
    'ORCH',
    'B1b shared dir: ${sharedDir.path}; primary=$primaryDevice sibling=$siblingDevice',
  );

  try {
    primary = await _startHarnessRole(
      role: 'primary',
      deviceId: primaryDevice,
      sharedDir: Directory(remoteAbsolute),
      runId: runId,
    );
    _pipeOutput(primary.stdout, 'PRIMARY', primaryLog);
    _pipeOutput(primary.stderr, 'PRIMARY-ERR', primaryLog);

    // The physical linked installation publishes the production QR and account
    // recovery seed; only then may the ordinary emulator start.
    await signalDir.waitForJson(
      'linked_bootstrap_fixture.json',
      timeout: const Duration(minutes: 12),
    );
    _log(
      'ORCH',
      'Linked installation published its QR; starting ordinary primary',
    );

    sibling = await _startHarnessRole(
      role: 'sibling',
      deviceId: siblingDevice,
      sharedDir: Directory(remoteAbsolute),
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
      'linked_complete',
      timeout: const Duration(minutes: 2),
    );

    // Surface the two role-qualified proof verdicts.
    for (final name in ['linked_verdict.json', 'ordinary_verdict.json']) {
      final file = File('${sharedDir.path}/md004_${runId}_$name');
      if (file.existsSync()) {
        _log('VERDICT', '$name => ${file.readAsStringSync()}');
      }
    }
    _log('ORCH', 'B1b linked-group bootstrap/reopen/dissolve proof PASSED');
    _log('ORCH', 'Primary log: ${sharedDir.path}/primary.log');
    _log('ORCH', 'Sibling log: ${sharedDir.path}/sibling.log');
  } finally {
    try {
      primary?.kill();
    } catch (_) {}
    try {
      sibling?.kill();
    } catch (_) {}
    broker.stop();
    await brokerRun;
    await primaryLog.close();
    await siblingLog.close();
  }
}
