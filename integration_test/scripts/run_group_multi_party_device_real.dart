#!/usr/bin/env dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'group_multi_party_device_criteria.dart';

const _harnessPath =
    'integration_test/group_multi_party_device_real_harness.dart';
const _iosRunnerBundleId = 'com.mknoon.app';
const _roleIdentityTimeout = Duration(minutes: 90);
const _roleVerdictTimeout = Duration(minutes: 15);

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
  final file = File(path);
  final result = await Future.any<Object>([
    _waitForJson(path, timeout: _roleVerdictTimeout),
    process.exitCode.then<Object>((exitCode) => _ProcessExit(exitCode)),
  ]);
  if (result is Map<String, dynamic>) {
    return result;
  }
  if (result is _ProcessExit) {
    if (file.existsSync()) {
      return Map<String, dynamic>.from(
        jsonDecode(file.readAsStringSync()) as Map,
      );
    }
    throw StateError(
      '$role exited with code ${result.exitCode} before writing a verdict; '
      'log=$logPath',
    );
  }
  throw StateError('$role finished with unexpected result: $result');
}

Future<Map<String, dynamic>> _waitForIdentityOrExit({
  required Process process,
  required String path,
  required String role,
  required String logPath,
}) async {
  final result = await Future.any<Object>([
    _waitForJson(path, timeout: _roleIdentityTimeout),
    process.exitCode.then<Object>((exitCode) => _ProcessExit(exitCode)),
  ]);
  if (result is Map<String, dynamic>) {
    return result;
  }
  if (result is _ProcessExit) {
    throw StateError(
      '$role exited with code ${result.exitCode} before writing identity; '
      'log=$logPath',
    );
  }
  throw StateError(
    '$role identity wait finished with unexpected result: $result',
  );
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
  String? restoreIdentityPath,
  bool reuseExistingIdentity = false,
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
    if (restoreIdentityPath != null && restoreIdentityPath.trim().isNotEmpty)
      '--dart-define=GROUP_MULTI_PARTY_RESTORE_IDENTITY_PATH=${restoreIdentityPath.trim()}',
    if (reuseExistingIdentity)
      '--dart-define=GROUP_MULTI_PARTY_REUSE_EXISTING_IDENTITY=true',
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
  final isStatefulRelaunch =
      reuseExistingIdentity ||
      (restoreMnemonic != null && restoreMnemonic.trim().isNotEmpty) ||
      (restoreIdentityPath != null && restoreIdentityPath.trim().isNotEmpty);
  if (!isStatefulRelaunch) {
    await _uninstallRunnerApp(deviceId, '$scenario/$role');
  }
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

Future<void> _uninstallRunnerApp(String deviceId, String label) async {
  if (!_isIosDeviceId(deviceId)) return;
  try {
    final result = await Process.run('xcrun', [
      'simctl',
      'uninstall',
      deviceId,
      _iosRunnerBundleId,
    ]).timeout(const Duration(seconds: 20));
    final stderrText = '${result.stderr}'.trim();
    if (result.exitCode != 0 &&
        !stderrText.contains('No such app') &&
        !stderrText.contains('No such application') &&
        !stderrText.contains('not installed')) {
      _log(
        'ORCH',
        'Runner uninstall on $label returned ${result.exitCode}: $stderrText',
      );
    }
  } on TimeoutException {
    _log('ORCH', 'Timed out uninstalling Runner on $label simulator');
  } catch (error) {
    _log('ORCH', 'Failed to uninstall Runner on $label simulator: $error');
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

bool _parseListScenarios(List<String> args) {
  return args.contains('--list-scenarios');
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
    case 'ge001':
      return const <String>['ge001'];
    case 'ge002':
      return const <String>['ge002'];
    case 'ge003':
      return const <String>['ge003'];
    case 'ge004':
      return const <String>['ge004'];
    case 'ge005':
      return const <String>['ge005'];
    case 'ge006':
      return const <String>['ge006'];
    case 'ge007':
      return const <String>['ge007'];
    case 'ge008':
      return const <String>['ge008'];
    case 'ge009':
      return const <String>['ge009'];
    case 'ge010':
      return const <String>['ge010'];
    case 'go001':
      return const <String>['go001'];
    case 'go002':
      return const <String>['go002'];
    case 'go003':
      return const <String>['go003'];
    case 'ge011':
      return const <String>['ge011'];
    case 'ge012':
      return const <String>['ge012'];
    case 'ge013':
      return const <String>['ge013'];
    case 'ge014':
      return const <String>['ge014'];
    case 'ge015':
      return const <String>['ge015'];
    case 'ge016':
      return const <String>['ge016'];
    case 'ge020':
      return const <String>['ge020'];
    case 'ge021':
      return const <String>['ge021'];
    case 'ge023':
      return const <String>['ge023'];
    case 'ge024':
      return const <String>['ge024'];
    case 'gm001':
      return const <String>['gm001'];
    case 'de002':
      return const <String>['de002'];
    case 'de003':
      return const <String>['de003'];
    case 'de007':
      return const <String>['de007'];
    case 'de017':
      return const <String>['de017'];
    case 'ir001':
      return const <String>['ir001'];
    case 'ir015':
      return const <String>['ir015'];
    case 'ir016':
      return const <String>['ir016'];
    case 'pl002':
      return const <String>['pl002'];
    case 'pl012':
      return const <String>['pl012'];
    case 'private_abc_create':
      return const <String>['private_abc_create'];
    case 'private_reaction_roundtrip':
      return const <String>['private_reaction_roundtrip'];
    case 'private_removed_reaction_rejected':
      return const <String>['private_removed_reaction_rejected'];
    case 'private_never_member_publish_rejected':
      return const <String>['private_never_member_publish_rejected'];
    case 'private_removed_old_key_publish_rejected':
      return const <String>['private_removed_old_key_publish_rejected'];
    case 'private_full_mesh_online':
      return const <String>['private_full_mesh_online'];
    case 'private_relay_only_delivery':
      return const <String>['private_relay_only_delivery'];
    case 'private_partition_readd_heal':
      return const <String>['private_partition_readd_heal'];
    case 'private_relay_reconnect_group_recovery':
      return const <String>['private_relay_reconnect_group_recovery'];
    case 'private_peer_disconnect_not_removal':
      return const <String>['private_peer_disconnect_not_removal'];
    case 'private_background_resume_group_delivery':
      return const <String>['private_background_resume_group_delivery'];
    case 'private_long_offline_epoch_churn':
      return const <String>['private_long_offline_epoch_churn'];
    case 'private_process_death_matrix':
      return const <String>['private_process_death_matrix'];
    case 'private_online_add':
      return const <String>['private_online_add'];
    case 'private_offline_add':
      return const <String>['private_offline_add'];
    case 'private_online_remove':
      return const <String>['private_online_remove'];
    case 'private_removed_notification_privacy':
      return const <String>['private_removed_notification_privacy'];
    case 'private_offline_remove':
      return const <String>['private_offline_remove'];
    case 'private_offline_readd':
      return const <String>['private_offline_readd'];
    case 'private_readd_current':
      return const <String>['private_readd_current'];
    case 'private_readd_active_members':
      return const <String>['private_readd_active_members'];
    case 'private_readd_alternating_churn':
      return const <String>['private_readd_alternating_churn'];
    case 'private_max_group_size_churn':
      return const <String>['private_max_group_size_churn'];
    case 'private_network_chaos_invariants':
      return const <String>['private_network_chaos_invariants'];
    case 'private_late_leave_readd':
      return const <String>['private_late_leave_readd'];
    case 'private_rotated_device_readd':
      return const <String>['private_rotated_device_readd'];
    case 'private_same_user_multi_device_readd':
      return const <String>['private_same_user_multi_device_readd'];
    case 'private_readd_cycles':
      return const <String>['private_readd_cycles'];
    case 'private_rapid_readd':
      return const <String>['private_rapid_readd'];
    case 'private_concurrent_admin_membership_edits':
      return const <String>['private_concurrent_admin_membership_edits'];
    case 'private_timeline_truth':
      return const <String>['private_timeline_truth'];
    case 'private_non_friend_member_delivery':
      return const <String>['private_non_friend_member_delivery'];
    case 'private_admin_role_transfer_delivery':
      return const <String>['private_admin_role_transfer_delivery'];
    case 'private_history_retention':
      return const <String>['private_history_retention'];
    case 'private_invite_terminal_states':
      return const <String>['private_invite_terminal_states'];
    case 'private_stale_invite_readd':
      return const <String>['private_stale_invite_readd'];
    case 'private_stale_lower_key_update':
      return const <String>['private_stale_lower_key_update'];
    case 'private_same_epoch_key_conflict':
      return const <String>['private_same_epoch_key_conflict'];
    case 'private_partial_key_distribution':
      return const <String>['private_partial_key_distribution'];
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
    case 'gm008':
      return const <String>['gm008'];
    case 'gm009':
      return const <String>['gm009'];
    case 'gm010':
      return const <String>['gm010'];
    case 'gm011':
      return const <String>['gm011'];
    case 'gm012':
      return const <String>['gm012'];
    case 'gm013':
      return const <String>['gm013'];
    case 'gm014':
      return const <String>['gm014'];
    case 'gm015':
      return const <String>['gm015'];
    case 'gm016':
      return const <String>['gm016'];
    case 'gm017':
      return const <String>['gm017'];
    case 'gm018':
      return const <String>['gm018'];
    case 'gm019':
      return const <String>['gm019'];
    case 'gm020':
      return const <String>['gm020'];
    case 'gm021':
      return const <String>['gm021'];
    case 'gm022':
      return const <String>['gm022'];
    case 'gm023':
      return const <String>['gm023'];
    case 'gm024':
      return const <String>['gm024'];
    case 'gm025':
      return const <String>['gm025'];
    case 'gm033':
      return const <String>['gm033'];
    case 'gm034':
      return const <String>['gm034'];
    case 'gm035':
      return const <String>['gm035'];
    case 'all':
      return allGroupMultiPartyDeviceScenarioIds;
    default:
      throw ArgumentError.value(
        scenario,
        'scenario',
        'Expected --scenario ge001, ge002, ge003, ge004, ge005, ge006, ge007, ge008, ge009, ge010, go001, go002, go003, ge011, ge012, ge013, ge014, ge015, ge016, ge020, ge021, ge023, ge024, gm001, de002, de003, de007, de017, ir001, ir015, ir016, pl002, pl012, private_abc_create, private_reaction_roundtrip, private_removed_reaction_rejected, private_never_member_publish_rejected, private_removed_old_key_publish_rejected, private_full_mesh_online, private_relay_only_delivery, private_partition_readd_heal, private_relay_reconnect_group_recovery, private_peer_disconnect_not_removal, private_background_resume_group_delivery, private_long_offline_epoch_churn, private_process_death_matrix, private_online_add, private_offline_add, private_online_remove, private_removed_notification_privacy, private_offline_remove, private_offline_readd, private_readd_current, private_readd_active_members, private_readd_alternating_churn, private_max_group_size_churn, private_network_chaos_invariants, private_late_leave_readd, private_rotated_device_readd, private_same_user_multi_device_readd, private_readd_cycles, private_rapid_readd, private_concurrent_admin_membership_edits, private_timeline_truth, private_non_friend_member_delivery, private_admin_role_transfer_delivery, private_history_retention, private_invite_terminal_states, private_stale_invite_readd, private_stale_lower_key_update, private_same_epoch_key_conflict, private_partial_key_distribution, gm002, gm003, gm004, gm005, gm006, gm007, gm008, gm009, gm010, gm011, gm012, gm013, gm014, gm015, gm016, gm017, gm018, gm019, gm020, gm021, gm022, gm023, gm024, gm025, gm033, gm034, gm035, or all',
      );
  }
}

Future<void> _runGe012Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'ge012';
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

  Future<void> launchRole(String role, {String? restoreMnemonic}) async {
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
      restoreMnemonic: restoreMnemonic,
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

  try {
    await launchRole('alice');
    await launchRole('bob');
    final bobIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final bobMnemonic = (bobIdentity['mnemonic12'] as String?)?.trim();
    if (bobMnemonic == null || bobMnemonic.isEmpty) {
      throw StateError('$scenario Bob primary did not publish a mnemonic');
    }
    await launchRole('charlie', restoreMnemonic: bobMnemonic);

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
      await sink.flush();
      await sink.close();
    }
  }
}

Future<void> _runGe013Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'ge013';
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

  Future<void> launchRole(String role, {String? restoreMnemonic}) async {
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
      restoreMnemonic: restoreMnemonic,
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

  try {
    await launchRole('alice');
    await launchRole('bob');
    final bobIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final bobMnemonic = (bobIdentity['mnemonic12'] as String?)?.trim();
    if (bobMnemonic == null || bobMnemonic.isEmpty) {
      throw StateError('$scenario Bob primary did not publish a mnemonic');
    }
    await launchRole('charlie', restoreMnemonic: bobMnemonic);

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
      await sink.flush();
      await sink.close();
    }
  }
}

Future<void> _runSt007Scenario({
  required String scenario,
  required List<String> devices,
  required String relayAddresses,
}) async {
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
  final activeProcessLabelByRole = <String, String>{};
  final logs = <String, IOSink>{};
  final logPaths = <String, String>{};

  _log('ORCH', '$scenario shared dir: ${sharedDir.path}');
  _log('ORCH', '$scenario run id: $runId');
  _log('ORCH', '$scenario ${deviceCheck.detail}');

  Future<Process> launchRole(
    String role, {
    String? logLabel,
    bool reuseExistingIdentity = false,
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
      reuseExistingIdentity: reuseExistingIdentity,
    );
    processes[label] = process;
    activeProcessLabelByRole[role] = label;
    _pipeOutput(process.stdout, label.toUpperCase(), logSink);
    _pipeOutput(process.stderr, '${label.toUpperCase()}-ERR', logSink);
    return process;
  }

  Future<void> killActiveRole(String role, String stage) async {
    final label = activeProcessLabelByRole[role];
    if (label == null) {
      throw StateError('$scenario has no active process for $role');
    }
    final process = processes.remove(label);
    if (process == null) {
      throw StateError('$scenario missing process label $label');
    }
    await _stopHarnessProcess(process, '$scenario/$role-$stage');
    await _terminateRunnerApp(roleDevices[role]!, '$scenario/$role-$stage');
    activeProcessLabelByRole.remove(role);
  }

  try {
    for (final role in roles) {
      final process = await launchRole(role);
      await _waitForIdentityOrExit(
        process: process,
        path: _signalPath(sharedDir, runId, '${role}_identity.json'),
        role: role,
        logPath: logPaths[role]!,
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_st007_add_state_persisted.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario killing Charlie after add checkpoint');
    await killActiveRole('charlie', 'after-add');
    File(
      _signalPath(sharedDir, runId, 'charlie_st007_add_crash_complete'),
    ).writeAsStringSync('ok');
    await launchRole(
      'charlie',
      logLabel: 'charlie_after_add_relaunch',
      reuseExistingIdentity: true,
    );
    await _waitForSignal(
      _signalPath(sharedDir, runId, 'charlie_st007_add_recovered'),
      timeout: const Duration(minutes: 15),
    );

    await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_st007_remove_state_persisted.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario killing Bob after remove checkpoint');
    await killActiveRole('bob', 'after-remove');
    File(
      _signalPath(sharedDir, runId, 'bob_st007_remove_crash_complete'),
    ).writeAsStringSync('ok');
    await launchRole(
      'bob',
      logLabel: 'bob_after_remove_relaunch',
      reuseExistingIdentity: true,
    );
    await _waitForSignal(
      _signalPath(sharedDir, runId, 'bob_st007_remove_recovered'),
      timeout: const Duration(minutes: 15),
    );

    await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_st007_readd_state_persisted.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario killing Charlie after re-add checkpoint');
    await killActiveRole('charlie', 'after-readd');
    File(
      _signalPath(sharedDir, runId, 'charlie_st007_readd_crash_complete'),
    ).writeAsStringSync('ok');
    await launchRole(
      'charlie',
      logLabel: 'charlie_after_readd_relaunch',
      reuseExistingIdentity: true,
    );
    await _waitForSignal(
      _signalPath(sharedDir, runId, 'charlie_st007_readd_recovered'),
      timeout: const Duration(minutes: 15),
    );

    final verdicts = await Future.wait<Map<String, dynamic>>(
      roles.map((role) {
        final label = activeProcessLabelByRole[role]!;
        return _waitForVerdictOrExit(
          process: processes[label]!,
          path: _verdictPath(sharedDir, runId, role),
          role: role,
          logPath: logPaths[label]!,
        );
      }),
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
      final label = activeProcessLabelByRole[role]!;
      final exitCode = await processes[label]!.exitCode.timeout(
        const Duration(minutes: 5),
        onTimeout: () {
          processes[label]!.kill();
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
      final label = activeProcessLabelByRole[role]!;
      _log('ORCH', '$role log: ${logPaths[label]}');
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

Future<void> _runScenario({
  required String scenario,
  required List<String> devices,
  required String relayAddresses,
}) async {
  if (scenario == 'gm003' || scenario == 'private_offline_add') {
    await _runGm003Scenario(
      scenario: scenario,
      devices: devices,
      relayAddresses: relayAddresses,
    );
    return;
  }
  if (scenario == 'gm005' || scenario == 'private_offline_remove') {
    await _runGm005Scenario(
      scenario: scenario,
      devices: devices,
      relayAddresses: relayAddresses,
    );
    return;
  }
  if (scenario == 'ge006') {
    await _runGe006Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ge007') {
    await _runGe007Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ge012') {
    await _runGe012Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ge013') {
    await _runGe013Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ge014') {
    await _runGe014Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ge015') {
    await _runGe015Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'gm008') {
    await _runGm008Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ir001') {
    await _runIr001Scenario(devices: devices, relayAddresses: relayAddresses);
    return;
  }
  if (scenario == 'ir015' || scenario == 'ir016') {
    await _runIr001Scenario(
      scenario: scenario,
      devices: devices,
      relayAddresses: relayAddresses,
    );
    return;
  }
  if (scenario == 'private_process_death_matrix') {
    await _runSt007Scenario(
      scenario: scenario,
      devices: devices,
      relayAddresses: relayAddresses,
    );
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

Future<void> _runGe014Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'ge014';
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
      mode: 'restartSeed',
      logLabel: 'charlie_seed',
    );
    final charlieIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final charlieMnemonic = (charlieIdentity['mnemonic12'] as String?)?.trim();
    if (charlieMnemonic == null || charlieMnemonic.isEmpty) {
      throw StateError('ge014 Charlie seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(
        sharedDir,
        runId,
        'charlie_ge014_persisted_invite_restart_ready.json',
      ),
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
      throw StateError('ge014/charlie seed flutter process exitCode=$seedExit');
    }
    processes.remove('charlie_seed');
    await _terminateRunnerApp(
      roleDevices['charlie']!,
      '$scenario/charlie-seed',
    );
    _log('ORCH', '$scenario/charlie stopped after persisted invite/key');

    await launchRole('charlie', restoreMnemonic: charlieMnemonic);
    await _waitForSignal(
      _signalPath(
        sharedDir,
        runId,
        'charlie_ge014_restarted_before_topic_join',
      ),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/charlie restart boundary recorded');

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
    for (final process in processes.values) {
      process.kill();
    }
    for (final entry in roleDevices.entries) {
      await _terminateRunnerApp(entry.value, '$scenario/${entry.key}');
    }
    for (final sink in logs.values) {
      await sink.flush();
      await sink.close();
    }
  }
}

Future<void> _runGe015Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'ge015';
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
    for (final role in const <String>['bob', 'charlie']) {
      await launchRole(role);
      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    final aliceSeed = await launchRole(
      'alice',
      mode: 'restartSeed',
      logLabel: 'alice_seed',
    );
    final aliceIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'alice_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final aliceMnemonic = (aliceIdentity['mnemonic12'] as String?)?.trim();
    if (aliceMnemonic == null || aliceMnemonic.isEmpty) {
      throw StateError('ge015 Alice seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(
        sharedDir,
        runId,
        'alice_ge015_post_remove_restart_ready.json',
      ),
      timeout: const Duration(minutes: 15),
    );
    final seedExit = await aliceSeed.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        aliceSeed.kill();
        return -1;
      },
    );
    if (seedExit != 0) {
      throw StateError('ge015/alice seed flutter process exitCode=$seedExit');
    }
    processes.remove('alice_seed');
    await _terminateRunnerApp(roleDevices['alice']!, '$scenario/alice-seed');
    _log('ORCH', '$scenario/alice stopped before fanout repair');

    await launchRole('alice', restoreMnemonic: aliceMnemonic);
    await _waitForSignal(
      _signalPath(
        sharedDir,
        runId,
        'alice_ge015_restarted_before_fanout_repair',
      ),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/alice restart boundary recorded');

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
      await sink.flush();
      await sink.close();
    }
  }
}

Future<void> _runGm008Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'gm008';
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
      mode: 'restartSeed',
      logLabel: 'charlie_seed',
    );
    final charlieIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final charlieMnemonic = (charlieIdentity['mnemonic12'] as String?)?.trim();
    if (charlieMnemonic == null || charlieMnemonic.isEmpty) {
      throw StateError('gm008 Charlie seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(sharedDir, runId, 'charlie_removed_restart_ready.json'),
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
      throw StateError('gm008/charlie seed flutter process exitCode=$seedExit');
    }
    processes.remove('charlie_seed');
    await _terminateRunnerApp(
      roleDevices['charlie']!,
      '$scenario/charlie-seed',
    );
    _log('ORCH', '$scenario/charlie stopped after removal; relaunching');

    await launchRole('charlie', restoreMnemonic: charlieMnemonic);
    await _waitForSignal(
      _signalPath(sharedDir, runId, 'charlie_restarted_after_removal'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/charlie restart boundary recorded');

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
  required String scenario,
  required List<String> devices,
  required String relayAddresses,
}) {
  return _runOfflineCharlieRelaunchScenario(
    scenario: scenario,
    devices: devices,
    relayAddresses: relayAddresses,
  );
}

Future<void> _runIr001Scenario({
  String scenario = 'ir001',
  required List<String> devices,
  required String relayAddresses,
}) async {
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
  final oldStateSignal = scenario == 'ir015'
      ? 'bob_ir015_old_state_persisted.json'
      : scenario == 'ir016'
      ? 'bob_ir016_old_state_persisted.json'
      : 'bob_ir001_old_state_persisted.json';
  final offlineSignal = scenario == 'ir015'
      ? 'bob_ir015_offline'
      : scenario == 'ir016'
      ? 'bob_ir016_offline'
      : 'bob_ir001_offline';
  final relaunchReadySignal = scenario == 'ir015'
      ? 'bob_ir015_relaunch_ready'
      : scenario == 'ir016'
      ? 'bob_ir016_relaunch_ready'
      : 'bob_ir001_relaunch_ready';
  final relaunchReason = scenario == 'ir015'
      ? 'variant replay backlog'
      : scenario == 'ir016'
      ? 'retention cutoff backlog'
      : 'missed backlog';

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
    for (final role in const <String>['alice', 'charlie']) {
      await launchRole(role);
      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    final bobSeed = await launchRole(
      'bob',
      mode: 'seedOffline',
      logLabel: 'bob_seed',
    );
    final bobIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final bobMnemonic = (bobIdentity['mnemonic12'] as String?)?.trim();
    if (bobMnemonic == null || bobMnemonic.isEmpty) {
      throw StateError('$scenario Bob seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(sharedDir, runId, oldStateSignal),
      timeout: const Duration(minutes: 15),
    );
    final seedExit = await bobSeed.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        bobSeed.kill();
        return -1;
      },
    );
    if (seedExit != 0) {
      throw StateError('$scenario/bob seed flutter process exitCode=$seedExit');
    }
    processes.remove('bob_seed');
    await _terminateRunnerApp(roleDevices['bob']!, '$scenario/bob-seed');
    File(_signalPath(sharedDir, runId, offlineSignal)).writeAsStringSync('ok');
    _log('ORCH', '$scenario/bob joined state persisted; Bob offline');

    await _waitForSignal(
      _signalPath(sharedDir, runId, relaunchReadySignal),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario relaunching Bob after $relaunchReason');
    await launchRole('bob', restoreMnemonic: bobMnemonic);
    await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/bob reconnect identity ready');

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

Future<void> _runGe006Scenario({
  required List<String> devices,
  required String relayAddresses,
}) {
  return _runOfflineCharlieRelaunchScenario(
    scenario: 'ge006',
    devices: devices,
    relayAddresses: relayAddresses,
  );
}

Future<void> _runGe007Scenario({
  required List<String> devices,
  required String relayAddresses,
}) async {
  const scenario = 'ge007';
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
    for (final role in const <String>['alice', 'charlie']) {
      await launchRole(role);
      await _waitForJson(
        _signalPath(sharedDir, runId, '${role}_identity.json'),
        timeout: const Duration(minutes: 15),
      );
      _log('ORCH', '$scenario/$role identity ready');
    }

    final bobSeed = await launchRole(
      'bob',
      mode: 'seedOffline',
      logLabel: 'bob_seed',
    );
    final bobIdentity = await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final bobMnemonic = (bobIdentity['mnemonic12'] as String?)?.trim();
    if (bobMnemonic == null || bobMnemonic.isEmpty) {
      throw StateError('$scenario Bob seed did not publish a mnemonic');
    }
    await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_old_state_persisted.json'),
      timeout: const Duration(minutes: 15),
    );
    final seedExit = await bobSeed.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        bobSeed.kill();
        return -1;
      },
    );
    if (seedExit != 0) {
      throw StateError('$scenario/bob seed flutter process exitCode=$seedExit');
    }
    processes.remove('bob_seed');
    await _terminateRunnerApp(roleDevices['bob']!, '$scenario/bob-seed');
    File(
      _signalPath(sharedDir, runId, 'bob_offline_before_mutation'),
    ).writeAsStringSync('ok');
    _log('ORCH', '$scenario/bob old state persisted; Bob offline');

    await _waitForSignal(
      _signalPath(sharedDir, runId, 'bob_relaunch_ready'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario relaunching Bob after mutation and sends');
    await launchRole('bob', restoreMnemonic: bobMnemonic);
    await _waitForJson(
      _signalPath(sharedDir, runId, 'bob_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    _log('ORCH', '$scenario/bob reconnect identity ready');

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

Future<void> _runOfflineCharlieRelaunchScenario({
  required String scenario,
  required List<String> devices,
  required String relayAddresses,
}) async {
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
      throw StateError('$scenario Charlie seed did not publish a mnemonic');
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
      throw StateError(
        '$scenario/charlie seed flutter process exitCode=$seedExit',
      );
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
  String scenario = 'gm003',
  required List<String> devices,
  required String relayAddresses,
}) async {
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
    String? restoreIdentityPath,
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
      restoreIdentityPath: restoreIdentityPath,
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
    await _waitForJson(
      _signalPath(sharedDir, runId, 'dana_identity.json'),
      timeout: const Duration(minutes: 15),
    );
    final danaRestoreIdentityPath = _signalPath(
      sharedDir,
      runId,
      'dana_identity_restore.json',
    );
    await _waitForJson(danaRestoreIdentityPath);
    final danaPreflightExit = await danaPreflight.exitCode.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        danaPreflight.kill();
        return -1;
      },
    );
    if (danaPreflightExit != 0) {
      throw StateError(
        '$scenario/dana preflight flutter process exitCode=$danaPreflightExit',
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
    await launchRole('dana', restoreIdentityPath: danaRestoreIdentityPath);
    await _waitForJson(
      _signalPath(sharedDir, runId, 'dana_late_identity.json'),
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
  final listScenarios = _parseListScenarios(args);
  final devices = _parseDevices(args);
  final relayAddresses = Platform.environment['MKNOON_RELAY_ADDRESSES'];
  final relayCheck = evaluateRelayConfiguration(relayAddresses);
  final usage =
      'Usage: dart run integration_test/scripts/run_group_multi_party_device_real.dart '
      '--scenario ge001|ge002|ge003|ge004|ge005|ge006|ge007|ge008|ge009|ge010|go001|go002|go003|ge011|ge012|ge013|ge014|ge015|ge016|ge020|ge021|ge023|ge024|gm001|de002|de003|de007|de017|ir001|ir015|ir016|pl002|pl012|private_abc_create|private_reaction_roundtrip|private_removed_reaction_rejected|private_never_member_publish_rejected|private_removed_old_key_publish_rejected|private_full_mesh_online|private_relay_only_delivery|private_partition_readd_heal|private_relay_reconnect_group_recovery|private_peer_disconnect_not_removal|private_background_resume_group_delivery|private_long_offline_epoch_churn|private_process_death_matrix|private_online_add|private_offline_add|private_online_remove|private_removed_notification_privacy|private_offline_remove|private_offline_readd|private_readd_current|private_readd_active_members|private_readd_alternating_churn|private_max_group_size_churn|private_network_chaos_invariants|private_late_leave_readd|private_rotated_device_readd|private_same_user_multi_device_readd|private_readd_cycles|private_rapid_readd|private_concurrent_admin_membership_edits|private_timeline_truth|private_non_friend_member_delivery|private_admin_role_transfer_delivery|private_history_retention|private_invite_terminal_states|private_stale_invite_readd|private_stale_lower_key_update|private_same_epoch_key_conflict|private_partial_key_distribution|gm002|gm003|gm004|gm005|gm006|gm007|gm008|gm009|gm010|gm011|gm012|gm013|gm014|gm015|gm016|gm017|gm018|gm019|gm020|gm021|gm022|gm023|gm024|gm025|gm033|gm034|gm035|all -d <alice,bob,charlie[,dana]> [--list-scenarios]';

  if (listScenarios) {
    try {
      for (final scenarioToRun in _scenariosToRun(scenario)) {
        stdout.writeln(scenarioToRun);
      }
    } on ArgumentError catch (error) {
      stderr.writeln(error.message);
      stderr.writeln(usage);
      exit(64);
    }
    return;
  }

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
