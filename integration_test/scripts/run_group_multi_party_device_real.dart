#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'group_multi_party_device_criteria.dart';

const _harnessPath =
    'integration_test/group_multi_party_device_real_harness.dart';
const _iosRunnerBundleId = 'com.mknoon.app';

class _ProcessExit {
  const _ProcessExit(this.exitCode);

  final int exitCode;
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

String _signalPath(Directory sharedDir, String runId, String name) {
  return '${sharedDir.path}/gmp_${runId}_$name';
}

String _verdictPath(Directory sharedDir, String runId, String role) {
  return _signalPath(sharedDir, runId, '${role}_verdict.json');
}

Future<Map<String, dynamic>> _waitForJson(
  String path, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(path);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) {
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for json: $path');
}

Future<void> _waitForSignal(
  String path, {
  Duration timeout = const Duration(minutes: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  final file = File(path);
  while (DateTime.now().isBefore(deadline)) {
    if (file.existsSync()) return;
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Timed out waiting for signal: $path');
}

Future<Map<String, dynamic>> _waitForVerdictOrExit({
  required Process process,
  required String path,
  required String role,
  required String logPath,
}) async {
  final result = await Future.any<Object>([
    _waitForJson(path, timeout: const Duration(minutes: 15)),
    process.exitCode.then<Object>((exitCode) => _ProcessExit(exitCode)),
  ]);
  if (result is Map<String, dynamic>) {
    return result;
  }
  if (result is _ProcessExit) {
    throw StateError(
      '$role exited with code ${result.exitCode} before writing a verdict; '
      'log=$logPath',
    );
  }
  throw StateError('$role finished with unexpected result: $result');
}

void _pipeOutput(Stream<List<int>> stream, String tag, IOSink sink) {
  stream.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    _log(tag, line);
    try {
      sink.writeln(line);
    } on StateError {
      // The process can flush output while cleanup is closing log sinks.
    }
  });
}

Future<Process> _startHarnessRole({
  required String scenario,
  required String role,
  required String deviceId,
  required Directory sharedDir,
  required String runId,
  required String relayAddresses,
  String mode = 'proof',
  String? restoreMnemonic,
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
    '--dart-define=GROUP_MULTI_PARTY_SCENARIO=$scenario',
    '--dart-define=GROUP_MULTI_PARTY_ROLE=$role',
    '--dart-define=GROUP_MULTI_PARTY_RUN_ID=$runId',
    '--dart-define=GROUP_MULTI_PARTY_MODE=$mode',
    if (restoreMnemonic != null && restoreMnemonic.trim().isNotEmpty)
      '--dart-define=GROUP_MULTI_PARTY_RESTORE_MNEMONIC=${restoreMnemonic.trim()}',
    '--dart-define=E2E_DB_NAME=group_multi_party_${scenario}_${runId}_$role.db',
    '--dart-define=MKNOON_RELAY_ADDRESSES=$relayAddresses',
    '-d',
    deviceId,
  ];
  final displayArgs = args
      .map(
        (arg) =>
            arg.startsWith('--dart-define=GROUP_MULTI_PARTY_RESTORE_MNEMONIC=')
            ? '--dart-define=GROUP_MULTI_PARTY_RESTORE_MNEMONIC=<redacted>'
            : arg,
      )
      .join(' ');
  _log('ORCH', 'Launching $scenario/$role: flutter $displayArgs');
  return Process.start('flutter', args);
}

Future<void> _stopHarnessProcess(Process? process, String label) async {
  if (process == null) return;
  process.kill();
  try {
    await process.exitCode.timeout(const Duration(seconds: 10));
  } on TimeoutException {
    _log('ORCH', '$label did not stop after SIGTERM; sending SIGKILL');
    process.kill(ProcessSignal.sigkill);
    try {
      await process.exitCode.timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

Future<void> _terminateRunnerApp(String deviceId, String label) async {
  if (!_isIosDeviceId(deviceId)) return;
  try {
    final result = await Process.run('xcrun', [
      'simctl',
      'terminate',
      deviceId,
      _iosRunnerBundleId,
    ]).timeout(const Duration(seconds: 10));
    final stderrText = '${result.stderr}'.trim();
    if (result.exitCode != 0 &&
        !stderrText.contains('Not running') &&
        !stderrText.contains('No such process') &&
        !stderrText.contains('found nothing to terminate')) {
      _log(
        'ORCH',
        'Runner terminate on $label returned ${result.exitCode}: $stderrText',
      );
    }
  } on TimeoutException {
    _log('ORCH', 'Timed out terminating Runner on $label simulator');
  } catch (error) {
    _log('ORCH', 'Failed to terminate Runner on $label simulator: $error');
  }
}

String _parseScenario(List<String> args) {
  var scenario = 'all';
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--scenario' && i + 1 < args.length) {
      scenario = args[i + 1].trim().toLowerCase();
      i++;
    } else if (args[i].startsWith('--scenario=')) {
      scenario = args[i].substring('--scenario='.length).trim().toLowerCase();
    }
  }
  return scenario;
}

List<String> _parseDevices(List<String> args) {
  final devices = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      devices.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    }
  }
  return devices;
}

List<String> _scenariosToRun(String scenario) {
  switch (scenario) {
    case 'gm001':
      return const <String>['gm001'];
    case 'gm002':
      return const <String>['gm002'];
    case 'gm003':
      return const <String>['gm003'];
    case 'gm004':
      return const <String>['gm004'];
    case 'gm005':
      return const <String>['gm005'];
    case 'gm006':
      return const <String>['gm006'];
    case 'gm007':
      return const <String>['gm007'];
    case 'all':
      return const <String>['gm001', 'gm002'];
    default:
      throw ArgumentError.value(
        scenario,
        'scenario',
        'Expected --scenario gm001, gm002, gm003, gm004, gm005, gm006, gm007, or all',
      );
  }
}

Future<void> _runScenario({
  required String scenario,
  required List<String> devices,
  required String relayAddresses,
}) async {
  if (scenario == 'gm003') {
    await _runGm003Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'gm005') {
    await _runGm005Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }

  final deviceCheck = evaluateDeviceSelection(
    scenario: scenario,
    deviceIds: devices,
  );
  if (!deviceCheck.ok) {
    throw ArgumentError(deviceCheck.detail);
  }
  final roleDevices = roleDeviceMapForScenario(
    scenario: scenario,
    deviceIds: devices,
  );
  final roles = scenarioRequirement(scenario).roles;
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'group_multi_party_${scenario}_',
  );
  final processes = <String, Process>{};
  final logs = <String, IOSink>{};
  final logPaths = <String, String>{};

  _log('ORCH', '$scenario shared dir: ${sharedDir.path}');
  _log('ORCH', '$scenario run id: $runId');
  _log('ORCH', '$scenario ${deviceCheck.detail}');

  try {
    for (final role in roles) {
      final logPath = '${sharedDir.path}/$role.log';
      final logSink = File(logPath).openWrite(mode: FileMode.writeOnlyAppend);
      logs[role] = logSink;
      logPaths[role] = logPath;
      final process = await _startHarnessRole(
        scenario: scenario,
        role: role,
        deviceId: roleDevices[role]!,
        sharedDir: sharedDir,
        runId: runId,
        relayAddresses: relayAddresses,
      );
      processes[role] = process;
      _pipeOutput(process.stdout, role.toUpperCase(), logSink);
      _pipeOutput(process.stderr, '${role.toUpperCase()}-ERR', logSink);

      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    final verdicts = await Future.wait<Map<String, dynamic>>(
      roles.map(
        (role) => _waitForVerdictOrExit(
          process: processes[role]!,
          path: _verdictPath(sharedDir, runId, role),
          role: role,
          logPath: logPaths[role]!,
        ),
      ),
    );

    final criterion = evaluateGroupMultiPartyVerdicts(
      scenario: scenario,
      relayAddresses: relayAddresses,
      verdicts: verdicts,
    );
    File(
      _signalPath(sharedDir, runId, '${scenario}_orchestrator_verdict.json'),
    ).writeAsStringSync(
      jsonEncode(<String, dynamic>{
        'scenario': scenario,
        'ok': criterion.ok,
        'detail': criterion.detail,
        'sharedDir': sharedDir.path,
        'roleDevices': roleDevices,
        'roleVerdicts': {
          for (final role in roles) role: _verdictPath(sharedDir, runId, role),
        },
      }),
    );
    if (!criterion.ok) {
      throw StateError(
        '$scenario verdict validation failed: ${criterion.detail}',
      );
    }

    for (final role in roles) {
      final exitCode = await processes[role]!.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          processes[role]!.kill();
          return -1;
        },
      );
      if (exitCode != 0) {
        throw StateError('$scenario/$role flutter process exitCode=$exitCode');
      }
    }

    _log('ORCH', '$scenario proof passed: ${criterion.detail}');
    _log('ORCH', '$scenario logs and verdicts: ${sharedDir.path}');
    for (final role in roles) {
      _log('ORCH', '$role log: ${logPaths[role]}');
      _log('ORCH', '$role verdict: ${_verdictPath(sharedDir, runId, role)}');
    }
  } finally {
    for (final entry in processes.entries) {
      await _stopHarnessProcess(entry.value, '$scenario/${entry.key}');
    }
    for (final entry in roleDevices.entries) {
      await _terminateRunnerApp(entry.value, '$scenario/${entry.key}');
    }
    for (final sink in logs.values) {
      await sink.close();
    }
  }
}

Future<void> _runGm005Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'gm005';
  final deviceCheck = evaluateDeviceSelection(
    scenario: scenario,
    deviceIds: devices,
  );
  if (!deviceCheck.ok) {
    throw ArgumentError(deviceCheck.detail);
  }
  final roleDevices = roleDeviceMapForScenario(
    scenario: scenario,
    deviceIds: devices,
  );
  final roles = scenarioRequirement(scenario).roles;
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'group_multi_party_${scenario}_',
  );
  final processes = <String, Process>{};
  final logs = <String, IOSink>{};
  final logPaths = <String, String>{};

  _log('ORCH', '$scenario shared dir: ${sharedDir.path}');
  _log('ORCH', '$scenario run id: $runId');
  _log('ORCH', '$scenario ${deviceCheck.detail}');

  Future<Process> launchRole(
    String role, {
    String mode = 'proof',
    String? restoreMnemonic,
    String? logLabel,
  }) async {
    final label = logLabel ?? role;
    final logPath = '${sharedDir.path}/$label.log';
    final logSink = File(logPath).openWrite(mode: FileMode.writeOnlyAppend);
    logs[label] = logSink;
    logPaths[label] = logPath;
    final process = await _startHarnessRole(
      scenario: scenario,
      role: role,
      deviceId: roleDevices[role]!,
      sharedDir: sharedDir,
      runId: runId,
      relayAddresses: relayAddresses,
      mode: mode,
      restoreMnemonic: restoreMnemonic,
    );
    processes[label] = process;
    _pipeOutput(process.stdout, label.toUpperCase(), logSink);
    _pipeOutput(process.stderr, '${label.toUpperCase()}-ERR', logSink);
    return process;
  }

  try {
    for (final role in const <String>['alice', 'bob']) {
      await launchRole(role);
      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    final charlieSeed = await launchRole(
      'charlie',
      mode: 'seedOffline',
      logLabel: 'charlie_seed',
    );
    final charlieIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final charlieMnemonic = (charlieIdentity['mnemonic12'] as String?)?.trim();
    if (charlieMnemonic == null || charlieMnemonic.isEmpty) {
      throw StateError('gm005 Charlie seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_old_state_persisted.json'),
      timeout: const Duration(minutes: 15),
    );
    final seedExit = await charlieSeed.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        charlieSeed.kill();
        return -1;
      },
    );
    if (seedExit != 0) {
      throw StateError('gm005/charlie seed flutter process exitCode=$seedExit');
    }
    processes.remove('charlie_seed');
    await _terminateRunnerApp(
      roleDevices['charlie']!,
      '$scenario/charlie-seed',
    );
    File(
      _signalPath(sharedDir, runId, 'charlie_offline_before_removal'),
    ).writeAsStringSync('ok');
    _log('ORCH', '$scenario/charlie old state persisted; Charlie offline');

    await _waitForSignal(
      _signalPath(sharedDir, runId, 'charlie_relaunch_ready'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario relaunching Charlie after removal and sends');
    await launchRole('charlie', restoreMnemonic: charlieMnemonic);
    await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/charlie reconnect identity ready');

    final verdicts = await Future.wait<Map<String, dynamic>>(
      roles.map(
        (role) => _waitForVerdictOrExit(
          process: processes[role]!,
          path: _verdictPath(sharedDir, runId, role),
          role: role,
          logPath: logPaths[role]!,
        ),
      ),
    );

    final criterion = evaluateGroupMultiPartyVerdicts(
      scenario: scenario,
      relayAddresses: relayAddresses,
      verdicts: verdicts,
    );
    File(
      _signalPath(sharedDir, runId, '${scenario}_orchestrator_verdict.json'),
    ).writeAsStringSync(
      jsonEncode(<String, dynamic>{
        'scenario': scenario,
        'ok': criterion.ok,
        'detail': criterion.detail,
        'sharedDir': sharedDir.path,
        'roleDevices': roleDevices,
        'roleVerdicts': {
          for (final role in roles) role: _verdictPath(sharedDir, runId, role),
        },
      }),
    );
    if (!criterion.ok) {
      throw StateError(
        '$scenario verdict validation failed: ${criterion.detail}',
      );
    }

    for (final role in roles) {
      final exitCode = await processes[role]!.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          processes[role]!.kill();
          return -1;
        },
      );
      if (exitCode != 0) {
        throw StateError('$scenario/$role flutter process exitCode=$exitCode');
      }
    }

    _log('ORCH', '$scenario proof passed: ${criterion.detail}');
    _log('ORCH', '$scenario logs and verdicts: ${sharedDir.path}');
    for (final role in roles) {
      _log('ORCH', '$role log: ${logPaths[role]}');
      _log('ORCH', '$role verdict: ${_verdictPath(sharedDir, runId, role)}');
    }
  } finally {
    for (final entry in processes.entries) {
      await _stopHarnessProcess(entry.value, '$scenario/${entry.key}');
    }
    for (final entry in roleDevices.entries) {
      await _terminateRunnerApp(entry.value, '$scenario/${entry.key}');
    }
    for (final sink in logs.values) {
      await sink.close();
    }
  }
}

Future<void> _runGm003Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'gm003';
  final deviceCheck = evaluateDeviceSelection(
    scenario: scenario,
    deviceIds: devices,
  );
  if (!deviceCheck.ok) {
    throw ArgumentError(deviceCheck.detail);
  }
  final roleDevices = roleDeviceMapForScenario(
    scenario: scenario,
    deviceIds: devices,
  );
  final roles = scenarioRequirement(scenario).roles;
  final runId = DateTime.now().millisecondsSinceEpoch.toString();
  final sharedDir = await Directory.systemTemp.createTemp(
    'group_multi_party_${scenario}_',
  );
  final processes = <String, Process>{};
  final logs = <String, IOSink>{};
  final logPaths = <String, String>{};

  _log('ORCH', '$scenario shared dir: ${sharedDir.path}');
  _log('ORCH', '$scenario run id: $runId');
  _log('ORCH', '$scenario ${deviceCheck.detail}');

  Future<Process> launchRole(
    String role, {
    String mode = 'proof',
    String? restoreMnemonic,
    String? logLabel,
  }) async {
    final label = logLabel ?? role;
    final logPath = '${sharedDir.path}/$label.log';
    final logSink = File(logPath).openWrite(mode: FileMode.writeOnlyAppend);
    logs[label] = logSink;
    logPaths[label] = logPath;
    final process = await _startHarnessRole(
      scenario: scenario,
      role: role,
      deviceId: roleDevices[role]!,
      sharedDir: sharedDir,
      runId: runId,
      relayAddresses: relayAddresses,
      mode: mode,
      restoreMnemonic: restoreMnemonic,
    );
    processes[label] = process;
    _pipeOutput(process.stdout, label.toUpperCase(), logSink);
    _pipeOutput(process.stderr, '${label.toUpperCase()}-ERR', logSink);
    return process;
  }

  try {
    final danaPreflight = await launchRole(
      'dana',
      mode: 'identityOnly',
      logLabel: 'dana_preflight',
    );
    final danaIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'dana_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final danaMnemonic = (danaIdentity['mnemonic12'] as String?)?.trim();
    if (danaMnemonic == null || danaMnemonic.isEmpty) {
      throw StateError('gm003 Dana preflight did not publish a mnemonic');
    }
    final danaPreflightExit = await danaPreflight.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        danaPreflight.kill();
        return -1;
      },
    );
    if (danaPreflightExit != 0) {
      throw StateError(
        'gm003/dana preflight flutter process exitCode=$danaPreflightExit',
      );
    }
    processes.remove('dana_preflight');
    await _terminateRunnerApp(roleDevices['dana']!, '$scenario/dana-preflight');
    _log('ORCH', '$scenario/dana identity preflight complete; Dana offline');

    for (final role in const <String>['alice', 'bob', 'charlie']) {
      await launchRole(role);
      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    await _waitForSignal(
      _signalPath(sharedDir, runId, 'dana_late_launch_ready'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario launching Dana after offline add/post-add send');
    await launchRole('dana', restoreMnemonic: danaMnemonic);
    await _waitForJson(
      _signalPath(sharedDir, runId, 'dana_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/dana late identity ready');

    final verdicts = await Future.wait<Map<String, dynamic>>(
      roles.map(
        (role) => _waitForVerdictOrExit(
          process: processes[role]!,
          path: _verdictPath(sharedDir, runId, role),
          role: role,
          logPath: logPaths[role]!,
        ),
      ),
    );

    final criterion = evaluateGroupMultiPartyVerdicts(
      scenario: scenario,
      relayAddresses: relayAddresses,
      verdicts: verdicts,
    );
    File(
      _signalPath(sharedDir, runId, '${scenario}_orchestrator_verdict.json'),
    ).writeAsStringSync(
      jsonEncode(<String, dynamic>{
        'scenario': scenario,
        'ok': criterion.ok,
        'detail': criterion.detail,
        'sharedDir': sharedDir.path,
        'roleDevices': roleDevices,
        'roleVerdicts': {
          for (final role in roles) role: _verdictPath(sharedDir, runId, role),
        },
      }),
    );
    if (!criterion.ok) {
      throw StateError(
        '$scenario verdict validation failed: ${criterion.detail}',
      );
    }

    for (final role in roles) {
      final exitCode = await processes[role]!.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          processes[role]!.kill();
          return -1;
        },
      );
      if (exitCode != 0) {
        throw StateError('$scenario/$role flutter process exitCode=$exitCode');
      }
    }

    _log('ORCH', '$scenario proof passed: ${criterion.detail}');
    _log('ORCH', '$scenario logs and verdicts: ${sharedDir.path}');
    for (final role in roles) {
      _log('ORCH', '$role log: ${logPaths[role]}');
      _log('ORCH', '$role verdict: ${_verdictPath(sharedDir, runId, role)}');
    }
  } finally {
    for (final entry in processes.entries) {
      await _stopHarnessProcess(entry.value, '$scenario/${entry.key}');
    }
    for (final entry in roleDevices.entries) {
      await _terminateRunnerApp(entry.value, '$scenario/${entry.key}');
    }
    for (final sink in logs.values) {
      await sink.close();
    }
  }
}

Future<void> main(List<String> args) async {
  final scenario = _parseScenario(args);
  final devices = _parseDevices(args);
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  final relayCheck = evaluateRelayConfiguration(relayAddresses);
  final usage =
      'Usage: dart run integration_test/scripts/run_group_multi_party_device_real.dart '
      '--scenario gm001|gm002|gm003|gm004|gm005|gm006|gm007|all -d <alice,bob,charlie[,dana]>';

  try {
    final scenarioForDeviceCheck = scenario == 'all' ? 'all' : scenario;
    scenarioRequirement(scenarioForDeviceCheck);
    final deviceCheck = evaluateDeviceSelection(
      scenario: scenarioForDeviceCheck,
      deviceIds: devices,
    );
    if (!deviceCheck.ok) {
      throw ArgumentError(deviceCheck.detail);
    }
    if (!relayCheck.ok) {
      throw ArgumentError(relayCheck.detail);
    }
  } on ArgumentError catch (error) {
    stderr.writeln(error.message);
    stderr.writeln(usage);
    exit(64);
  }

  for (final scenarioToRun in _scenariosToRun(scenario)) {
    await _runScenario(
      scenario: scenarioToRun,
      devices: devices,
      relayAddresses: relayAddresses!.trim(),
    );
  }
}
