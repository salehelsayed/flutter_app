#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

class _Scenario {
  const _Scenario({
    required this.id,
    required this.testCase,
    required this.mode,
    required this.summary,
    required this.requiredChecks,
  });

  final String id;
  final String testCase;
  final String mode;
  final String summary;
  final List<String> requiredChecks;
}

const List<_Scenario> _scenarios = <_Scenario>[
  _Scenario(
    id: 'tc_a6_replay_before_ack_custody',
    testCase: 'TC-A6',
    mode: 'real-relay',
    summary:
        'relay inbox page replays before ack, ack purges custody, second drain does not duplicate',
    requiredChecks: <String>[
      'realGoBridgeClient',
      'realRelay',
      'relayInboxSeeded',
      'replayBeforeAckObserved',
      'firstDrainAckPurgedRelay',
      'secondDrainNoDuplicateRender',
    ],
  ),
  _Scenario(
    id: 'tc_b11_payload_persist_pre_drain',
    testCase: 'TC-B11',
    mode: 'real-crypto-relay',
    summary:
        'real ciphertext push envelope stages and renders before drain, later drain dedupes',
    requiredChecks: <String>[
      'realPeerCiphertext',
      'realGoBridgeClient',
      'realRelay',
      'stagedEnvelopeRead',
      'visibleBeforeDrain',
      'noDrainBeforeVisibility',
      'laterDrainNoDuplicate',
    ],
  ),
  _Scenario(
    id: 'payload_fast_path_ios_receiver',
    testCase: 'TC-B12',
    mode: 'ios-apns-device',
    summary:
        'iPhone receiver APNs/NSE stages envelope; airplane-mode tap renders from staged payload',
    requiredChecks: <String>[
      'iosReceiver',
      'apnsDelivered',
      'nseStagingOn',
      'nse04P0WithStagingOn',
      'airplaneModeBeforeTap',
      'messageVisibleFromStagedEnvelope',
      'noRelayDrainBeforeVisibility',
    ],
  ),
  _Scenario(
    id: 'payload_fast_path_android_receiver',
    testCase: 'TC-B12',
    mode: 'android-fcm-device',
    summary:
        'Android receiver FCM background isolate stages envelope; airplane-mode tap renders from staged payload',
    requiredChecks: <String>[
      'androidReceiver',
      'fcmDelivered',
      'backgroundIsolateStaged',
      'airplaneModeBeforeTap',
      'messageVisibleFromStagedEnvelope',
      'noRelayDrainBeforeVisibility',
    ],
  ),
  _Scenario(
    id: 'payload_fast_path_cold_kill',
    testCase: 'TC-B12',
    mode: 'cold-kill-device',
    summary:
        'terminated receiver cold-launches from notification tap and ingests staged payload before drain',
    requiredChecks: <String>[
      'receiverTerminatedBeforeTap',
      'notificationTapColdLaunchedApp',
      'startupIngestRan',
      'messageVisibleFromStagedEnvelope',
      'noRelayDrainBeforeVisibility',
    ],
  ),
];

void main(List<String> args) {
  final scenario = _valueFor(args, '--scenario') ?? 'all';
  final listScenarios = args.contains('--list-scenarios');
  final printSchema = args.contains('--artifact-schema');
  final validateArtifacts = args.contains('--validate-artifacts');
  final artifactDir = _valueFor(args, '--artifact-dir');
  final devices = _devices(args);
  final selected = _selectedScenarios(scenario);

  if (listScenarios) {
    for (final item in selected) {
      stdout.writeln(item.id);
    }
    return;
  }

  if (printSchema) {
    _printSchema(selected);
    return;
  }

  if (validateArtifacts) {
    if (artifactDir == null || artifactDir.trim().isEmpty) {
      stderr.writeln('Missing --artifact-dir <dir> for artifact validation.');
      exit(64);
    }
    final ok = _validateArtifacts(Directory(artifactDir), selected);
    exit(ok ? 0 : 66);
  }

  stdout.writeln('225 notification-tap device/relay proof campaign');
  stdout.writeln(
    'Devices: ${devices.isEmpty ? '(none supplied)' : devices.join(', ')}',
  );
  for (final item in selected) {
    stdout.writeln('');
    stdout.writeln('${item.id} [${item.testCase} / ${item.mode}]');
    stdout.writeln('  ${item.summary}');
    stdout.writeln('  required checks: ${item.requiredChecks.join(', ')}');
  }
  stdout.writeln('');
  stdout.writeln(
    'BLOCKED: this repo does not contain an APNs/FCM + real relay + '
    'multi-device driver that can capture these proofs automatically. Capture '
    'one JSON artifact per scenario on the real rig, then run:',
  );
  stdout.writeln(
    '  dart run integration_test/scripts/run_notification_tap_device_real.dart '
    '--scenario $scenario --artifact-dir <dir> --validate-artifacts',
  );
  stdout.writeln(
    'Then rerun the Flutter proof tests with '
    '--dart-define=MKNOON_225_PROOF_DIR=<dir>.',
  );
  exit(78);
}

String? _valueFor(List<String> args, String name) {
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == name && i + 1 < args.length) {
      return args[i + 1];
    }
    if (arg.startsWith('$name=')) {
      return arg.substring(name.length + 1);
    }
  }
  return null;
}

List<String> _devices(List<String> args) {
  final values = <String>[];
  for (var i = 0; i < args.length; i++) {
    if ((args[i] == '--device' || args[i] == '-d') && i + 1 < args.length) {
      values.addAll(
        args[i + 1]
            .split(',')
            .map((part) => part.trim())
            .where((part) => part.isNotEmpty),
      );
      i++;
    }
  }
  return values;
}

List<_Scenario> _selectedScenarios(String scenario) {
  if (scenario == 'all') {
    return _scenarios;
  }
  final matches = _scenarios.where((item) => item.id == scenario).toList();
  if (matches.isEmpty) {
    stderr.writeln(
      'Unknown --scenario "$scenario". Expected all or one of: '
      '${_scenarios.map((item) => item.id).join(', ')}',
    );
    exit(64);
  }
  return matches;
}

void _printSchema(List<_Scenario> selected) {
  for (final item in selected) {
    stdout.writeln('${item.id}.json');
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'testCase': item.testCase,
        'scenario': item.id,
        'status': 'passed',
        'capturedAt': '2026-07-09T17:24:00Z',
        'devices': <String>['ios-or-android-device-id'],
        'checks': <String, bool>{
          for (final check in item.requiredChecks) check: true,
        },
      }),
    );
  }
}

bool _validateArtifacts(Directory artifactDir, List<_Scenario> selected) {
  var ok = true;
  for (final item in selected) {
    final file = File(
      '${artifactDir.path}${Platform.pathSeparator}${item.id}.json',
    );
    if (!file.existsSync()) {
      stderr.writeln('Missing artifact: ${file.path}');
      ok = false;
      continue;
    }
    Object? decoded;
    try {
      decoded = jsonDecode(file.readAsStringSync());
    } catch (error) {
      stderr.writeln('Invalid JSON in ${file.path}: $error');
      ok = false;
      continue;
    }
    if (decoded is! Map<String, dynamic>) {
      stderr.writeln('Artifact root must be an object: ${file.path}');
      ok = false;
      continue;
    }
    if (decoded['testCase'] != item.testCase ||
        decoded['scenario'] != item.id ||
        decoded['status'] != 'passed' ||
        decoded['capturedAt'] is! String) {
      stderr.writeln('Artifact metadata mismatch: ${file.path}');
      ok = false;
    }
    final checks = decoded['checks'];
    if (checks is! Map<String, dynamic>) {
      stderr.writeln('Artifact checks object missing: ${file.path}');
      ok = false;
      continue;
    }
    for (final check in item.requiredChecks) {
      if (checks[check] != true) {
        stderr.writeln('Artifact ${file.path} missing check "$check": true');
        ok = false;
      }
    }
  }
  if (ok) {
    stdout.writeln(
      '225 proof artifacts validated for ${selected.length} scenario(s).',
    );
  }
  return ok;
}
